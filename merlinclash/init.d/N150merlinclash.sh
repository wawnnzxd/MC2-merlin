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
#
# ★ 2026-09-23 审计修复 initwd-14:start_nat 前先置上 /tmp/clash_firewall_triggered(写本进程 PID)。
#   MC2 的 flush_nat() 末尾约定:这个标志不在就 restart_firewall()(proxyrouter_sw=1 时
#   service restart_firewall)。上游设计里只有 MC2 自己发起的防火墙重启会先 touch 它;
#   而这里是被固件的 nat-start 调起的 —— 防火墙**刚被固件重建完**,再重启一次纯属浪费:
#   第二轮整表重建 + 整条 N* 链重跑(fullcone / hwaccel / chnupdate / natmap 各再来一遍)、
#   第二次 apply_nat 与 dnsmasq 重启,中间还多一段 LAN 新连接不进 mihomo 的裸奔窗口。
#   (最终表内容不变:第二轮的 flush_nat 同样会 -F nat OUTPUT 且不再重启,省掉它结果完全一样。)
#   ★ 标志里写本进程 PID,跑完**只删自己那份**(内容仍是 $$ = 没被 flush_nat 消费、也没被后来者覆盖):
#     start_nat 因「插件没开 / 内核没起」跳过时它不会被消费,残留会让之后的 stop 少重启一次防火墙,所以要收尾;
#     但**绝不能无条件 rm** —— 这是一个全局文件,两轮 nat-start 重叠时(PPPoE 重拨 syslog 里 1 秒内两次
#     nat-start、或 natguard 重建期间来一次),后一轮 N150 刚写上的标志会被前一轮收尾删掉,后一轮的 flush_nat
#     找不到标志又 restart_firewall → 下一轮 nat-start 再被删……每 15~20 秒整表重建一次、永不收敛
#     (2026-09-23 复审模拟复现:40 秒 9 次重启仍在继续)。按 PID 认领后,重叠时最多多一次重启就收敛
#     (MC2 的 restart_firewall 只 touch、不改内容,后来者覆盖成自己的 PID 即受保护)。natguard 同一套写法。

KSROOT="${KSROOT:-/jffs/koolshare}"
[ -d /koolshare ] && KSROOT=/koolshare

if [ "$1" = "start_nat" ]; then
	echo $$ > /tmp/clash_firewall_triggered
	"$KSROOT/scripts/clash_config.sh" "$@"; rc=$?
	[ "$(cat /tmp/clash_firewall_triggered 2>/dev/null)" = "$$" ] && rm -f /tmp/clash_firewall_triggered
	exit $rc
fi
exec "$KSROOT/scripts/clash_config.sh" "$@"
