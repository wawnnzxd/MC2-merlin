#!/bin/sh
# N150merlinclash.sh —— NAT 重启时重建 MC2 的 iptables 规则(nat-start 钩子)
#
# 触发时机:WAN 重拨、防火墙重启、VPN 起停…… 任何导致 iptables 被重刷的事件。
# 这些事件会把 MC2 建的 7 条自定义链(merlinclash / merlinclash_CHN / _EXT /
# _NOR / _OUTPUT / _PREROUTING / _divert)连同规则一起冲掉,代理就此失效 ——
# 内核还活着、页面也显示"运行中",但流量已经不走代理了。
#
# clash_config.sh 的 `case $ACTION in start_nat)` 分支专门处理这个:
# 它只调 apply_nat()(flush → 重建 ipset → 重建 iptables → 重启 dnsmasq),
# **不重启内核**,所以很轻,几秒完成。而且它自带前置判断 ——
# 插件没开或内核没完全起来时直接跳过,不会在半启动状态下写坏规则。
#
# 这里用 "$@" 透传而不是写死 start_nat:调度器传什么就是什么,
# 将来 koolshare 改了 action 名字也不用跟着改。

KSROOT="${KSROOT:-/jffs/koolshare}"
[ -d /koolshare ] && KSROOT=/koolshare

exec "$KSROOT/scripts/clash_config.sh" "$@"
