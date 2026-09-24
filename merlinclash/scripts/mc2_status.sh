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

# 透明代理是否真的接管了 —— 2026-09-23 审计修复 mc2ui-22:
#   原来 `iptables -S | grep -c merlinclash` 把 `-N merlinclash…` 这类**链定义**也数进去:
#   防火墙重建后自定义链还在、PREROUTING 里那条跳转丢了(设备全部直连),计数照样 >0,
#   状态条仍是绿色「运行中」,不带「(未接管流量)」。V90natguard / V99bootcheck 09-02 已改判据,这里漏了。
#   现在按透明代理模式直接 -C 查跳转本身(形态见 clash_config.sh 的 apply_nat_rules):
#     closed / udp :nat    PREROUTING -p tcp -j merlinclash
#     tcp / tcpudp :mangle PREROUTING -p tcp -j merlinclash_PREROUTING
#     udp / tcpudp :mangle PREROUTING -p udp -j merlinclash_PREROUTING
#   开了「关闭透明代理」(closeproxy_sw=1)就一条都没有 ⇒ 0,如实显示「未接管」。
#   键名沿用 merlinclash_mc2_chains(前端只判 >0),值改为 1 = 已接管 / 0 = 未接管。
TAKEN=1
MODE=$("$DBUS" get merlinclash_ipt_tproxy_type)
case "$MODE" in
	tcp|tcpudp) iptables -t mangle -C PREROUTING -p tcp -j merlinclash_PREROUTING 2>/dev/null || TAKEN=0 ;;
	*)          iptables -t nat -C PREROUTING -p tcp -j merlinclash 2>/dev/null || TAKEN=0 ;;
esac
case "$MODE" in
	udp|tcpudp) iptables -t mangle -C PREROUTING -p udp -j merlinclash_PREROUTING 2>/dev/null || TAKEN=0 ;;
esac
"$DBUS" set merlinclash_mc2_chains=$TAKEN

http_response "$1"
exit 0
