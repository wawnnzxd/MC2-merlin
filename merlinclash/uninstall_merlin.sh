#!/bin/sh
# Magic Catling 2 卸载脚本

KSROOT="${KSROOT:-/jffs/koolshare}"
[ -d /koolshare ] && KSROOT=/koolshare
. "$KSROOT/scripts/base.sh"
alias echo_date='echo 【$(TZ=UTC-8 date -R +%Y年%m月%d日\ %X)】:'

module=merlinclash
echo_date "停止并卸载 Magic Catling 2…"

# ── ① 停服务 ──
# 走 MC2 自己的 stop_config:它会 kill 定时任务、清 ipset、flush 掉 7 条自定义
# iptables 链、恢复 dnsmasq。直接删文件而不停服务的话,规则会一直挂在内核里,
# 代理已经没了但流量还往 TPROXY 端口送 —— 表现为全网打不开。
# 传 "" 是为了让动作落在 $2 上(见 clash_config.sh 的双 case 设计)。
[ -x "$KSROOT/scripts/clash_config.sh" ] && "$KSROOT/scripts/clash_config.sh" "" stop >/dev/null 2>&1
killall clash 2>/dev/null
sleep 1

# 兜底:stop_config 没跑成功时手工清链,避免残留规则劫持流量
for t in nat mangle; do
	for c in merlinclash merlinclash_CHN merlinclash_EXT merlinclash_NOR \
	         merlinclash_OUTPUT merlinclash_PREROUTING merlinclash_divert; do
		iptables -t $t -F $c 2>/dev/null
		iptables -t $t -X $c 2>/dev/null
	done
done

# ── ② 删文件 ──
rm -f "$KSROOT/scripts/"clash_*.sh "$KSROOT/scripts/"mc2_*.sh
rm -f "$KSROOT/scripts/merlinclash_install.sh" "$KSROOT/scripts/uninstall_${module}.sh"
rm -f "$KSROOT/webs/Module_merlinclash.asp" "$KSROOT/webs/Module_mc2.asp"
rm -f "$KSROOT/res/merlinclash.css" "$KSROOT/res/icon-merlinclash.png" "$KSROOT/res/mc2.js" "$KSROOT/res/mc2.css"
rm -f "$KSROOT/bin/clash"                       # 只删自己的,yq/jq 可能被别的插件用着
rm -f "$KSROOT/init.d/"*merlinclash*

# ⚠️ 数据目录 $KSROOT/merlinclash 保留 —— 里面是机场节点配置(yaml_use)、
#    自定义规则、订阅缓存。卸载重装不该丢,要彻底清理请手工:
#        rm -rf $KSROOT/merlinclash
echo_date "数据目录已保留:$KSROOT/merlinclash(节点与规则配置)"

# ── ③ 撤菜单 ──
# 不撤的话文件都删光了菜单还杵着,点进去是空白页(2026-08-25 卸 gostun 时踩过)
[ -x "$KSROOT/scripts/ks-autoreg.sh" ] && "$KSROOT/scripts/ks-autoreg.sh" del "$module" >/dev/null 2>&1; "$KSROOT/scripts/ks-autoreg.sh" del mc2 >/dev/null 2>&1

# ── ④ 清 dbus ──
for k in install version name title description; do dbus remove softcenter_module_${module}_$k; done
# MC2 自己的键全清(含 128 个 nokpacl_ ACL 项),但保留 sub_links ——
# 那是用户手填的机场订阅地址,重装后不用再找一遍。
for k in $(dbus list merlinclash 2>/dev/null | sed 's/=.*//'); do
	[ "$k" = "merlinclash_sub_links" ] && continue
	dbus remove "$k"
done

echo_date "卸载完成。"
