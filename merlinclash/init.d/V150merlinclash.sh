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
	"$KSROOT/scripts/clash_config.sh" start >/dev/null 2>&1
) &

exit 0
