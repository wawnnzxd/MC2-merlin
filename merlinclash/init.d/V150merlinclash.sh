#!/bin/sh
# V150merlinclash.sh —— MC2 开机自启(services-start 钩子)
#
# ★ 为什么是 wrapper 而不是软链:clash_config.sh 有两个 case(ACTION=$1 给
#   init.d,$2 给前端),ks-services-start 无参调用两个都不匹配;上游靠 perp
#   守护拉起(koolshare 私有),原版梅林没有 —— 显式把 start 放 $1。
#
# ★ NTP 门控(2026-08-25 加):路由器无 RTC 电池,上电时钟=固件默认纪元
#   (2024-01-01 UTC),要到 PPPoE 拨通 + NTP 对时后才跳到真实时间。
#   对时前启动 clash,TLS 证书会被判「尚未生效」握手全挂。
#   原先靠 start 分支里的 startdelay=120s 盲等,拨号慢一点就穿帮 ——
#   改为精确等 ntp_ready=1(上限 180s,兜底照常启动,别把没网时的
#   本地功能也卡死)。startdelay 保持不动,两道保险叠加。
# ★★ 时区必须在 mihomo 启动前钉死（2026-08-27 加，血泪见下）
#
#   mihomo 是 Go 程序，**只认 IANA 时区名**（Asia/Shanghai）。
#   而 ASUS 固件设的是 `TZ=GMT-8` —— busybox/glibc 的 POSIX 写法，Go 不认，
#   于是 Go 退回去读 /etc/localtime。
#
#   上游 clash_config.sh 里有个 fixTimeZone()，但它的条件是
#       [ ! -e "/etc/localtime" ] && ln -sf .../Shanghai /etc/localtime
#   —— **只在 localtime "不存在" 时才修**。开机早期那个软链可能已经存在
#   但指向的 /rom 还没就绪（读不到），fixTimeZone 直接跳过，
#   mihomo 就用了 UTC。
#
#   后果不是"日志时间难看"这么简单：connection.start 从
#       2026-08-27T01:17:28.546+08:00
#   变成
#       2026-08-26T18:48:58.986Z
#   而 netlog 的 collector 生成的 last_seen 仍是 CST。两种格式混在一张表里，
#   **字符串排序彻底错乱** —— "08-26T18:48"(实际最新) 排在 "08-27T01:17"(实际更早)
#   后面，"最近 N 小时" 永远查出 0 条，last_seen-start 变成负数。
#   2026-08-27 凌晨排查 Apple TV 掉线时，就是被这个假象带偏了大半夜。
#
#   这里做两件上游没做的事：
#     ① 检查 localtime 是否**可读**，而不只是"存在"
#     ② unset TZ(2026-09-03 起;原来是 export TZ=Asia/Shanghai,理由见 fix_tz 里的注释)——
#        mihomo 的时区如今由 bin/clash 那层 shim(unset TZ + exec bin/real/clash)兜住,
#        这里只管让 busybox 的 date/logger 按 /etc/localtime 记本地时间。
#
# ★ 2026-09-23 审计修复 initwd-12:本文件曾分两份 —— 线上/存档 migration/init.d 是带 fix_tz 的新版,
#   而 MC2 插件包(mc2-merlin/plugin/init.d)里还是 08-25 旧版,重装/升级 MC2 时 install.sh 会
#   `cp -rf init.d/*` 把线上这份覆盖掉。现在两份内容一致,只差文件末尾 KSROOT 探测那一行:
#   插件包里写 koolshare 原生路径(装机时 ks-fixpath 自动改写),存档里直接写改写后的 jffs 路径。
#   第三份 MC2-merlin/merlinclash/init.d/(发布包,install_merlin.sh 同样 cp -rf)与插件包这份逐字相同
#   (2026-09-23 第二轮同步)。改任何一份,三份一起改:插件包 = MC2-merlin,存档 = 插件包经 ks-fixpath 改写。
fix_tz() {
	if [ ! -r /etc/localtime ] && [ -f "$KSROOT/merlinclash/Shanghai" ]; then
		ln -sf "$KSROOT/merlinclash/Shanghai" /etc/localtime
		logger -t mc2-boot "localtime 不可读，已重建 → merlinclash/Shanghai"
	fi
	# ★ 2026-09-03:这里原来还有一句 export TZ=Asia/Shanghai。它对 mihomo 早已没意义(bin/clash 那层
	#   shim 会 unset TZ 让 Go 自己读 /etc/localtime),却害了 busybox:它不认 IANA 名,遇到就按 UTC 算,
	#   于是下面 logger 那行和 syslog 时间戳都差 8 小时(重启日志里出现过 "Sep 3 04:02:56 ... Asia 2026")。
	#   删掉;localtime 的重建照旧保留。
	unset TZ
}

KSROOT="${KSROOT:-/jffs/koolshare}"
[ -d /koolshare ] && KSROOT=/koolshare

(
	n=0
	until [ "$(nvram get ntp_ready)" = "1" ] || [ $n -ge 36 ]; do
		n=$((n+1)); sleep 5
	done
	[ "$(nvram get ntp_ready)" = "1" ] \
		&& logger -t mc2-boot "NTP 已同步($(date)),启动 MC2" \
		|| logger -t mc2-boot "等 NTP 180 秒未同步,照常启动(TLS 可能短暂失败)"
	fix_tz
	logger -t mc2-boot "TZ=$TZ  date=$(date)"
	# ★ 2026-09-23 审计修复 mc2ui-15 ④(纵深防御):watchdog_sw=1 时 clash_config.sh start 走 perpctl 分支,
	#   而 perp 是 koolshare 固件私有、原版梅林没有 ⇒ 内核根本起不来、MC2 自关。安装脚本会置 0,
	#   但配置迁移 / 备份恢复 / 旧界面开关都可能把它写回 1 —— 开机前这里再兜一次,被改过就记一笔。
	#   只在原版梅林上做(koolshare 固件有 perp,且那边不用本文件,由 S150/N150 软链启动);
	#   拼接写法是为了不被 ks-fixpath 改成 /jffs/koolshare(那样条件在梅林上恒假),同 MC2 分发器。
	KS_NATIVE="/kool""share"
	if [ "$KSROOT" != "$KS_NATIVE" ]; then
		w=$("$KSROOT/bin/dbus" get merlinclash_set_watchdog_sw 2>/dev/null)
		if [ -n "$w" ] && [ "$w" != "0" ]; then
			"$KSROOT/bin/dbus" set merlinclash_set_watchdog_sw=0
			logger -t mc2-boot "merlinclash_set_watchdog_sw 被写成了 $w(会走 perp、原版梅林起不来),已复位为 0"
		fi
	fi
	"$KSROOT/scripts/clash_config.sh" start >/dev/null 2>&1
) &

exit 0
