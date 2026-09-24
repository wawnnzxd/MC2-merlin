#!/bin/sh
# check.sh —— 不变量断言。两条线踩过的坑,固化成 grep,发版前跑一次。
#
#   sh check.sh
#
# 存在的理由:这个仓库被两条线同时改(见 COLLAB.md),而两边的 git author 完全相同。
# 重构/拆分文件时很容易把对面的修复顺手做没了 —— 比如 1.2.2.13 把 install.sh 拆成
# koolshare/merlin 两份,koolshare 那份带走了写入优化,merlin 那份没有(是有意的,
# 但当时没人立刻发现)。这个脚本让"做没了"当场可见。
#
# 加断言的规矩:**只加你真的踩过、并且能说清失败场景的**。
# 每条都要在注释里写清楚:不满足会怎样。别把它变成风格检查器。

cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0

# have <说明> <文件> <grep模式>      —— 必须存在
# absent <说明> <文件> <grep模式>    —— 必须不存在
have(){
	if [ ! -f "$2" ]; then printf '  ?? %-52s 文件不存在: %s\n' "$1" "$2"; FAIL=$((FAIL+1)); return; fi
	if grep -q -- "$3" "$2"; then printf '  ok %-52s\n' "$1"; PASS=$((PASS+1))
	else printf '  ✗  %-52s %s 里找不到 /%s/\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); fi
}
absent(){
	if [ ! -f "$2" ]; then printf '  ?? %-52s 文件不存在: %s\n' "$1" "$2"; FAIL=$((FAIL+1)); return; fi
	if grep -q -- "$3" "$2"; then printf '  ✗  %-52s %s 里不该有 /%s/\n' "$1" "$2" "$3"; FAIL=$((FAIL+1))
	else printf '  ok %-52s\n' "$1"; PASS=$((PASS+1)); fi
}

# same <说明> <母版> <副本>          —— 两份必须逐字节一致(母版在 ../GT-BE19000AI,koolshare 线的
#                                       clone 里没有这个目录时跳过,不算失败)
same(){
	if [ ! -d "$GT" ]; then printf '  -- %-52s 跳过(没有 %s)\n' "$1" "$GT"; return; fi
	if [ ! -f "$2" ] || [ ! -f "$3" ]; then printf '  ?? %-52s 文件不存在: %s / %s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); return; fi
	if cmp -s "$2" "$3"; then printf '  ok %-52s\n' "$1"; PASS=$((PASS+1))
	else printf '  ✗  %-52s %s ≠ %s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); fi
}

SU=merlinclash/scripts/clash_selfupdate.sh
IK=merlinclash/install_koolshare.sh
IM=merlinclash/install_merlin.sh
UM=merlinclash/uninstall_merlin.sh
ASP=merlinclash/webs/Module_merlinclash.asp
CSS=merlinclash/res/merlinclash.css
MJS=merlinclash/res/mc2.js
GT=../GT-BE19000AI/mc2-merlin/plugin

echo "── 安全:dbus/eval 注入面(两条线都适用)──"
# 没有 sane():外部字符串直接进 dbus → eval $(dbus export merlinclash_) 时以 root 执行
have   "外部值统一过 sane() 消毒"            "$SU" 'sane()'
# 这个键写了没人读,却是把 GitHub Release 正文送进 root eval 的通道
absent "不得写 merlinclash_selfupdate_note"  "$SU" 'dbus set merlinclash_selfupdate_note'

echo "── 自更新链路 ──"
# 少了它:解包出的 /tmp/merlinclash(27MB)常驻 tmpfs 直到重启
have   "失败/成功都清理 /tmp"                 "$SU" 'cleanup_tmp'
# 先落 21MB tarball 再解 24MB → tmpfs 峰值 45MB;流式只要 24MB
have   "流式下载解包(不落 tarball)"          "$SU" 'tar -xz -C /tmp'
# busybox 的 find 只有 -mtime DAYS,没有 -mmin;用 -mmin 写的新鲜度判断是哑弹,
# 不报错、永远不命中 → 缓存形同虚设、锁永不过期
have   "时间判断用 age_ok 而非 find -mmin"    "$SU" 'age_ok'
# 只认完整包:slim 增量包装完是残的,以后还得再下一次(已撤销,别加回来)
absent "不得重新引入 slim 增量包"             "$SU" 'slim'

echo "── 前端 ──"
# 点了更新后 onclick 被清空,失败/超时/登录过期三条终止分支若不复位,
# 按钮看着是活的、点了完全没反应,用户只能自己想到按 F5
have   "终止分支复位按钮 mc_su_rearm"          "$ASP" 'mc_su_rearm'

echo "── koolshare 线:写入优化 ──"
# 没有它:每次更新把 bin64(11M)+dashboard(13M)+rule_configs(1.6M)原样重写回 U 盘。
# 这块 eVtran U 盘已经因写入损坏过多次(见 router-ops/)
have   "sync_smart(改了才写)"                "$IK" 'sync_smart'
have   "dir_fp(目录指纹快路)"                "$IK" 'dir_fp'
# 预删除会架空上面两条:目标被清空,比对必然全部落空(1.2.2.8 踩过,日志显示"写入409/跳过0")
absent "不得在复制前 rm -rf dashboard"        "$IK" 'rm -rf /koolshare/merlinclash/dashboard'
absent "不得在复制前 rm -rf rule_configs"     "$IK" 'rm -rf /koolshare/merlinclash/rule_configs'

echo "── koolshare 线:CSS ──"
# 漏了 tfoot:代理设置卡片被劈成 337px/668px 两套布局,tfoot 四行一条分隔线都没有
have   "flex 行规则覆盖 tfoot"                 "$CSS" 'is(tbody,tfoot)'

echo "── AI 线 ──"
# watchdog=1 会走 perp(koolshare 私有),原版梅林没有 → 内核根本起不来
have   "梅林侧强制 watchdog_sw=0"              "$IM" 'merlinclash_set_watchdog_sw=0'
# 大文件常被搬去 /jffs/ksdata、原位留软链;busybox 的 cp 会把软链换成实体文件,
# 44M 的内核就又压回 200M 的 /jffs
have   "梅林侧解引用软链再写(readlink)"       "$IM" 'readlink'

echo "── AI 线:覆盖安装不回退线上定制(2026-09-23 审计)──"
# 老版升级循环对 yaml_basic/yaml_dns 整目录 rm -rf 再拷 ⇒ 手工对齐的 DNS 母版回到上游默认,
# Apple/airwallex 解析回国内 IP、被 ipset 直接放行(08-27 Airwallex 事故原样复现)
absent "梅林侧不得整目录覆盖 yaml_dns"               "$IM" '"yaml_dns:yaml_dns"'
# 包里 bin/clash 是旧内核:直接拷会盖掉 TZ shim(时间戳差 8 小时)并把在线更新过的内核降级
have   "梅林侧内核走 install_core/core_probe(保 shim)" "$IM" 'core_probe'
# 包里的 dnsmasq.postconf 是上游原版,不重打 dns-guard 就没有 AI kill-switch,要等下次开机才补
have   "梅林侧装完立即重打 dns-guard"               "$IM" 'dnsguard/apply.sh'
# 自更新自己会 restart;安装脚本再后台 start 一次 ⇒ 两轮 apply_mc 并发(可能起两个内核)
have   "自更新调起的安装不重复启动 MC2"             "$IM" 'mc_selfupdate.lock'
have   "自更新显式告诉安装脚本 MC2_SELFUPDATE=1"    "$SU" 'MC2_SELFUPDATE=1 sh'
# 软件中心离线安装先对整个包跑 ks-fixpath:字面 /koolshare 被改成 /jffs/koolshare,梅林上恒真
# ⇒ 走进 koolshare 老流程、装完还删掉新版界面。(^if 锚定:注释里有同样的字样)
absent "分发器条件不得写字面 /koolshare"             merlinclash/install.sh '^if \[ -d /koolshare'
# 软件中心离线安装第 12 步:install.sh 里(含注释)出现这两个词就当恶意包整包拒装
absent "入口 install.sh 不得含软件中心恶意包关键字"  merlinclash/install.sh 'ks_tar_install\|detect_package'
# 只撤 postconf 软链不够:新版 dns-guard 的 conf.add 兜底段 / IP 层封锁会一直留着,AI 域名卸完还被封
have   "卸载时让 dns-guard 一起退役"                "$UM" 'grep -qw remove'
# 通配 rm scripts/mc2_*.sh 会把 migration 单独部署的 mc2_chnupdate.sh 一起删掉
absent "卸载不得通配删 mc2_*.sh"                    "$UM" 'scripts/"mc2_\*'
# grep -c merlinclash 会把 -N 链定义也数进去:跳转丢了(全网直连)状态条照样绿色「运行中」
have   "mc2_status 直接 -C 查 PREROUTING 跳转"        merlinclash/scripts/mc2_status.sh '-C PREROUTING'
# 120 秒盲等 / 每天中午 12 点整套重启 / 「每隔」默认 2 分钟,都与已定配置相反(只影响全新安装)
have   "defaults:开机延迟关"                         merlinclash/config/defaults.conf '^merlinclash_set_startdelay_sw=0$'
have   "defaults:定时重启内核关"                     merlinclash/config/defaults.conf '^merlinclash_select_clash_restart=1$'
have   "defaults:「每隔 N」默认 30"                  merlinclash/config/defaults.conf '^merlinclash_select_clash_restart_minute_2=30$'
# koolshare 分支 `sync_smart bin64 /koolshare/bin` 会把 bin64 里所有文件铺进固件的 bin:
# 带上 base64_decode/base64_encode 就用 openssl 包装盖掉 koolshare 固件原生的 base64_encode(ELF)
# 和 base64_decode 软链。梅林分支缺这两个名字时自己从 base64 派生(约定 C5),包里只放 base64。
if [ -e merlinclash/bin64/base64_decode ] || [ -e merlinclash/bin64/base64_encode ]; then
	printf '  ✗  %-52s %s\n' "bin64 只带 base64,不带 _decode/_encode" "会盖掉 koolshare 固件原生件"; FAIL=$((FAIL+1))
else printf '  ok %-52s\n' "bin64 只带 base64,不带 _decode/_encode"; PASS=$((PASS+1)); fi

echo "── 共用脚本(2026-09-23 审计)──"
# 以前 `xargs -0 printf "%b"` 把整段内容当一个参数:busybox xargs 32KB 上限,超了一个字节不出,
# 而 `> 文件` 已先截断 ⇒ 保存稍大的配置段 = 原文件被清空;printf "%s" "$content" 过 128KB 直接 E2BIG
# (^[^#]* 排除注释行 —— 修复说明里原样引用了旧写法)
absent "编辑器保存:urldecode 不经 xargs 参数"        merlinclash/scripts/clash_yamlfilechange.sh '^[^#]*xargs -0 printf'
absent "编辑器保存:分片不经 printf 参数"            merlinclash/scripts/clash_yamlfilechange.sh '^[^#]*printf "%s" "\$content"'
# 删规则留下的空键 → 规则文件一行「,,」→ check_rule 拼成「,,,」→ 内核解析失败、MC2 自关,每次启动复现
have   "自定规则:缺类型/出口不写进规则文件"         merlinclash/scripts/clash_saveacls.sh '\[ -z "\$type" \] || \[ -z "\$lianjie" \]'
have   "自定规则:缺类型/出口不插进配置"             merlinclash/scripts/clash_config.sh '\[ -z "\$type" \] || \[ -z "\$lianjie" \]'
# busybox crond 对越界值是把整个字段置满:旧界面「周日」=7 → 每周重启变成每天重启
have   "定时重启:周日 7 换成 0(即时生效那份)"       merlinclash/scripts/clash_restart_regularly.sh '"$mscrw" = "7"'
have   "定时重启:周日 7 换成 0(apply 重注册那份)"   merlinclash/scripts/clash_config.sh '"$mscrw" = "7"'
# 上游 case 25 下 fernvenue 单源并 rm res/china_ip_route.ipset,下次 apply 把 N98 的并集整份换掉
have   "大陆 IP 更新:装了 N98 就交给它"              merlinclash/scripts/clash_update_chnroute.sh 'N98chnupdate.sh'
# 原来 flock 失败只记一句、解锁删锁文件后照跑,等于没锁
absent "大陆 IP 更新:锁不到不得照跑(unset_lock)"    merlinclash/scripts/clash_update_chnroute.sh 'rm -rf "\$LOCK_FILE"'

echo "── AI 线:两份副本一致(母版 ../GT-BE19000AI/mc2-merlin/plugin)──"
# 不一致 = 用本仓库的包重装时把旧前端 / 旧状态脚本 / 旧卸载脚本 / 旧默认值装回路由器,
# 新界面的修复(草稿保护、并发锁、大陆 IP 判定只认本次输出……)被悄悄回退(09-23 审计 mc2ui-17 / 22 / 26 / 28)
same   "新界面 mc2.js"                               "$GT/res/mc2.js"            "$MJS"
same   "新界面 mc2.css"                              "$GT/res/mc2.css"           merlinclash/res/mc2.css
same   "新界面 Module_mc2.asp"                       "$GT/webs/Module_mc2.asp"   merlinclash/webs/Module_mc2.asp
same   "老界面 Module_merlinclash.asp"               "$GT/webs/Module_merlinclash.asp" "$ASP"
same   "梅林卸载脚本(母版 plugin/uninstall.sh)"     "$GT/uninstall.sh"          "$UM"
same   "defaults.conf"                              "$GT/config/defaults.conf"  merlinclash/config/defaults.conf
same   "base64 包装(bin/base64 ↔ bin64/base64)"     "$GT/bin/base64"            merlinclash/bin64/base64
same   "开机自启 V150merlinclash.sh"                 "$GT/init.d/V150merlinclash.sh" merlinclash/init.d/V150merlinclash.sh
same   "nat-start N150merlinclash.sh"               "$GT/init.d/N150merlinclash.sh" merlinclash/init.d/N150merlinclash.sh
if [ -d "$GT" ]; then
	# scripts/:两边都有的同名脚本必须一致(plugin 独有的 merlinclash_install.sh 等不比)
	_n=0; _bad=""
	for _f in "$GT"/scripts/*.sh; do
		_b=${_f##*/}; [ -f "merlinclash/scripts/$_b" ] || continue
		_n=$((_n+1)); cmp -s "$_f" "merlinclash/scripts/$_b" || _bad="$_bad $_b"
	done
	if [ -z "$_bad" ]; then printf '  ok %-52s %s 个\n' "scripts/ 同名脚本逐字一致" "$_n"; PASS=$((PASS+1))
	else printf '  ✗  %-52s 不一致:%s\n' "scripts/ 同名脚本逐字一致" "$_bad"; FAIL=$((FAIL+1)); fi
else
	printf '  -- %-52s 跳过(没有 %s)\n' "scripts/ 同名脚本逐字一致" "$GT"
fi
# 新界面关键修复的「存在性」—— 两份一起回退时上面的比对照样全绿,这几条兜底
have   "mc2.js:没读到原内容不许保存"                 "$MJS" 'if (!editLoaded)'
have   "mc2.js:长任务期间锁住操作"                   "$MJS" 'function lockOps'
have   "mc2.js:长任务统一出口"                       "$MJS" 'function runLogged'
have   "mc2.js:大陆 IP 结论只认本次输出"             "$MJS" 'function chnVerdict'
# 新界面「更新大陆 IP」调它;缺了前端只能退回上游单源(武汉会把 N98 的并集换掉)
have   "包里带 mc2_chnupdate.sh(交给 N98)"          merlinclash/scripts/mc2_chnupdate.sh 'N98chnupdate.sh'

echo "── 发版 ──"
V=$(tr -d ' \r\n' < merlinclash/version 2>/dev/null)
case "$V" in
	# install.sh 会剥掉字母再整数比较,带字母的版本号会让比较出错
	*.*.*.*) case "$V" in *[!0-9.]*) printf '  ✗  版本号含非数字: %s\n' "$V"; FAIL=$((FAIL+1));;
	                       *) printf '  ok %-52s %s\n' "版本号四段纯数字" "$V"; PASS=$((PASS+1));; esac ;;
	*) printf '  ✗  版本号不是四段: %s\n' "$V"; FAIL=$((FAIL+1)) ;;
esac

echo
if [ "$FAIL" -eq 0 ]; then
	echo "全部通过($PASS 条)"
else
	echo "通过 $PASS,失败 $FAIL —— 失败的每一条都对应一个真实踩过的坑,"
	echo "别直接改断言让它变绿,先确认那个坑是不是又回来了(理由见 COLLAB.md)。"
	exit 1
fi
