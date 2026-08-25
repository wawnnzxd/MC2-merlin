#!/bin/sh
# mc2_status.sh —— 给新版界面用的轻量运行态收集(我们自己加的,上游 25 个脚本一字未动)
#
# 为什么需要它:上游**没有**任何机器可读的进程状态接口 ——
#   clash_status.sh      只写 merlinclash_db_chnroute_num
#   clash_proc_status.sh 输出的是给「详细状态」弹窗看的人类可读文本报告
# 而页面顶部的状态条要判断「内核到底在不在跑」。
# ⚠️ 我一开始想当然假设有个 merlinclash_pid 键,结果那个键根本不存在,
#    页面就一直显示「已启用,内核未就绪」——内核明明跑着(2026-08-25 踩到)。
#
# 键名带 mc2_ 前缀,避免和上游任何键撞名。

KSROOT="${KSROOT:-/jffs/koolshare}"
[ -d /koolshare ] && KSROOT=/koolshare
. "$KSROOT/scripts/base.sh"

DBUS="$KSROOT/bin/dbus"

PID=$(pidof clash 2>/dev/null | awk '{print $1}')
"$DBUS" set merlinclash_mc2_pid="${PID:-}"

# 内核真正「就绪」= 进程在 + 端口听着。只看 pidof 会把「起来了但配置报错、
# 还没 listen」也算成运行中,状态条就说了假话。
if [ -n "$PID" ] && netstat -anp 2>/dev/null | grep -q "$PID/clash"; then
	"$DBUS" set merlinclash_mc2_ready=1
else
	"$DBUS" set merlinclash_mc2_ready=0
fi

# 透明代理是否真的接管了(iptables 链在不在)
N=$(iptables -t nat -S 2>/dev/null | grep -c merlinclash)
M=$(iptables -t mangle -S 2>/dev/null | grep -c merlinclash)
"$DBUS" set merlinclash_mc2_chains=$((N + M))

http_response "$1"
exit 0
