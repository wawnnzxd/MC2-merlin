#!/bin/sh
# mc2_chnupdate.sh —— MC2 新界面「附加功能 → 大陆 IP 白名单 → 更新」的后端
#   (2026-09-23 审计修复 initnet-12 / mc2ui-34,跨包约定 C6;部署到 /koolshare/scripts/)
#
# 为什么不再用 MC2 自带的 `clash_update_chnroute.sh <ID> 25`:
#   它下载 fernvenue 单一来源到 yaml_basic/ChinaIP.yaml,然后 `rm` 掉 res/china_ip_route.ipset;
#   下次 apply(重拨、订阅、WebUI 应用)MC2 就按 fernvenue 重建,把 N98chnupdate 维护的
#   APNIC ∪ 17mon 并集(含阿里云 8.128/10、腾讯云 43.x 这些受让段)整份换掉,最长一周才回来。
#   ⇒ 同一个文件两个写入者。
# 现在:IPv4 交给 N98chnupdate.sh force(并集 + 条数/抽查校验 + 同盘原子替换 + ipset swap,
#   立即生效、不用重启内核),res/china_ip_route.ipset 只剩 N98 一个写入者。
#   IPv6(ChinaIPv6.yaml → china_ip_route6)N98 不管,仍借 MC2 上游的 core_update_chnroute 更新,
#   行为与原按钮一致(MC2 的 ipv6_mode 只看有没有 inet6 地址,实际总是 true,v6 表一直在用)。
#
# 调用:/_api/ POST {"method":"mc2_chnupdate.sh","params":[]} → ksapid-handler 以 `脚本 <ID>` 执行。
#   先 http_response 回包;进度行与结束标记 BBABBBBC 追加到 /tmp/upload/merlinclash_log.txt,前端 pollLog 读。
#   手工:sh /koolshare/scripts/mc2_chnupdate.sh(无 ID 时 http_response 只打印)
# 预计 10~60 秒;硬上限约 5 分钟(N98 自带 180 秒看门狗 + IPv6 下载 ≤120 秒)。
#
# 机读结论(2026-09-23 审计修复 F1-X1;前端 chnVerdict 优先认它,界面上不显示):
#   本次日志的结尾、BBABBBBC 之前顶格两行 ——
#     MC2_RESULT=OK|FAIL|BUSY        IPv4:N98 退出码非 0 = FAIL;退出码 0 且输出 [OK] 行 = OK;
#                                    输出「[SKIP] 已有一次…」= BUSY(N98 的锁被每周 cron 更新 / 开机 heal 占着,
#                                    本次**什么都没做**,不能再报「✅ 处理完成」)
#     MC2_RESULT6=OK|SAME|FAIL|SKIP  IPv6:已更新 / 已是最新 / 下载或内容校验失败 /
#                                    没执行(旧界面正在更新、没有上游脚本或上游没有 core_update_chnroute)
#   以下三种情况不写(前端回退到文本判定,已兼容):
#     · 连点第二次(本脚本自己的锁忙):这份日志属于正在跑的那一次,结论和 BBABBBBC 由它写;第二次只留一句
#       「已有一次大陆 IP 白名单更新正在进行」(前端靠这句判 busy)。再往里写一对 MC2_RESULT,「取第一处」的读者
#       就会把正在跑那次的真实结果读成 BUSY。
#     · 没有 N98、整个交给上游脚本(exec 之后由上游自己写日志和 BBABBBBC)。
#     · IPv4 退出码 0 却既没有 [OK] 也没有「已有一次」(只可能是输出没截到):结论不明,只写 MC2_RESULT6,
#       不猜 OK / FAIL。
#
# ⚠️ 部署:三份同源(2026-09-23 审计修复 F1-X1)——
#   GT-BE19000AI/migration/mc2_chnupdate.sh:jffs 下的路径写法,单独推到武汉路由器;
#   GT-BE19000AI/mc2-merlin/plugin/scripts/ 与 MC2-merlin/merlinclash/scripts/ 各一份:koolshare 固件的路径写法,
#   随 MC2 包安装,装到梅林时由 ks-fixpath 改写路径 —— 改写后与 migration 那份逐字一致。改一份,三份一起改。
#   MC2 包从本次审计修复起自带它,重装 MC2 会一起装回;但用更早的 MC2 包卸载 / 重装还是会把它删掉
#   (旧包不带它,旧 uninstall 还会通配 `rm scripts/mc2_*.sh`)⇒ 重装 MC2 后核对一次,没了就重新推送并 chmod 755。
#   前端发现它不在会提示「需要重新部署」,不会静默退回上游单源。

export KSROOT="${KSROOT:-/koolshare}"
. "$KSROOT/scripts/base.sh"
LOG=/tmp/upload/merlinclash_log.txt
N98=$KSROOT/init.d/N98chnupdate.sh
UP=$KSROOT/scripts/clash_update_chnroute.sh
OUT=/tmp/mc2_chnupdate.out      # 某一步的完整输出,判结论用(本脚本的锁保证同一时刻只有一份在用)

say() { echo "【$(date '+%Y年%m月%d日 %X')】:$*" >> "$LOG"; }
# 机读结论(见文件头):$1 = IPv4(空 = 不明、不写),$2 = IPv6
result() {
	[ -n "$1" ] && echo "MC2_RESULT=$1" >> "$LOG"
	echo "MC2_RESULT6=$2" >> "$LOG"
}
# 跑一步:输出照旧实时追加进 $LOG(前端 pollLog 看进度),同时完整留一份到 $OUT 判结论;返回这一步的退出码。
#   ash 没有 pipefail,退出码经 $OUT.rc 带出管道;拿不到 / 不是数字(比如 /tmp 写满)按 1 算
#   (别用 `read RC < 文件`:读失败时 read 会先把 RC 清空,`return ""` 在 ash 里是致命错误,脚本当场退出、不写 BBABBBBC)。
#   子进程一律不带本脚本的锁 fd 8(2026-09-23 审计修复):N98 的看门狗子 shell 被 kill 后,它手上的 `sleep 1`
#   还会多活 ≤1 秒;N98 被 kill -9 时看门狗更会活到 180 秒 —— 继承了 fd 8 就把这把锁一起占着,这期间再点「更新」
#   只会得到「已有一次…正在进行」、永远等不到 BBABBBBC。N98 有自己的锁,用不着这一把。
run_logged() {
	rm -f "$OUT" "$OUT.rc"
	{ "$@" 2>&1; echo $? > "$OUT.rc"; } 8>&- | tee -a "$LOG" > "$OUT" 8>&-
	RC=$(cat "$OUT.rc" 2>/dev/null)
	rm -f "$OUT.rc"
	case "$RC" in ''|*[!0-9]*) RC=1 ;; esac
	return "$RC"
}

mkdir -p /tmp/upload
if [ ! -f "$N98" ]; then
	# 没装 N98(别的机器 / 被删了):原样交给 MC2 上游脚本,由它自己回包、写 BBABBBBC
	[ -f "$UP" ] && exec sh "$UP" "$1" 25
	echo "" > "$LOG"
	http_response "$1"
	say "❌ 既没有 N98chnupdate.sh 也没有 clash_update_chnroute.sh,无法更新"
	result FAIL SKIP
	echo BBABBBBC >> "$LOG"
	exit 1
fi

# 连点两次:第二次只回包、留一句话,不清日志、不写机读结论也不写结束标记
# (都由正在跑的那次写,前端照样能等到;为什么不写 MC2_RESULT=BUSY 见文件头)
exec 8>/tmp/mc2_chnupdate.lock
if ! flock -n 8; then
	http_response "$1"
	say "已有一次大陆 IP 白名单更新正在进行,请等它结束"
	exit 0
fi

echo "" > "$LOG"
http_response "$1"

say "开始更新大陆 IP 白名单(IPv4 由 N98chnupdate:APNIC ∪ 17mon 并集 + 抽查校验,通过后原子替换、立即生效,无需重启内核)"
say "预计 10~60 秒,硬上限约 5 分钟"
run_logged sh "$N98" force
rc=$?
# force 模式下 N98 退出码 0 只有两种结局:[OK](已替换)或「[SKIP] 已有一次…」(锁忙,什么都没做)
if [ "$rc" != 0 ]; then
	R4=FAIL
	say "❌ IPv4 更新失败(退出码 $rc),现网集合与数据文件保持原样,原因见上面的 [FAIL] 行"
elif grep -q '^\[OK\]' "$OUT"; then
	R4=OK
	say "✅ IPv4 大陆白名单已更新并立即生效(见上面 [OK] 行)"
elif grep -q '^\[SKIP\].*已有一次' "$OUT"; then
	R4=BUSY
	say "⚠️ 另一次更新/恢复正在进行,本次未执行(N98 的每周定时更新或开机恢复占着锁;等它结束后看「上次」时间)"
else
	R4=""
	say "⚠️ IPv4:N98 正常退出,但没截到 [OK] / [SKIP] 结论行,结果不明 —— 看下面「当前状态」里 update.log 的最后几行"
fi

# IPv6:借 MC2 上游函数(在子 shell 里 source,清空位置参数,免得触发它自己的 case 25 分支)。
#   退出码 = core_update_chnroute 的(0 = 更新成功或已是最新,1 = 下载 / 内容校验失败);上游没有这个函数时 3
v6_update() (
	set --
	. "$UP" >/dev/null 2>&1
	type core_update_chnroute >/dev/null 2>&1 || { echo "(MC2 脚本里没有 core_update_chnroute,跳过 IPv6)"; exit 3; }
	core_update_chnroute "6" \
		"https://testingcf.jsdelivr.net/gh/fernvenue/chn-cidr-list@master/ipv6.yaml" \
		"$KSROOT/merlinclash/yaml_basic/ChinaIPv6.yaml" \
		"/tmp/ChinaIPv6.list" \
		"$KSROOT/res/china_ip_route6.ipset"
)
#   先拿上游那把锁 /var/lock/chnroute_update.lock(审查返工 initnet-12):旧界面按钮(上游 case 25)
#   同时在跑时这次就不碰 v6,免得两边并发写 ChinaIPv6.yaml
#   跳过时的说明都带「跳过 IPv6」字样:没有机读行时前端按这几个字判 skip
R6=SKIP
mkdir -p /var/lock
exec 7>/var/lock/chnroute_update.lock
if [ ! -f "$UP" ]; then
	say "没有 MC2 上游脚本 clash_update_chnroute.sh,这次跳过 IPv6"
elif ! flock -n 7; then
	say "MC2 旧界面的大陆白名单更新正在跑,这次跳过 IPv6(它会顺带更新 IPv6)"
else
	say "IPv6 大陆白名单(ChinaIPv6.yaml)按 MC2 原逻辑更新…"
	run_logged v6_update
	case $? in
		0) if grep -q '已经是最新版本' "$OUT"; then R6=SAME; else R6=OK; fi ;;
		3) R6=SKIP ;;
		*) R6=FAIL ;;
	esac
	flock -u 7
fi
exec 7>&-

say "当前状态:"
sh "$N98" status >> "$LOG" 2>&1
result "$R4" "$R6"
echo BBABBBBC >> "$LOG"
rm -f "$OUT"
exit 0
