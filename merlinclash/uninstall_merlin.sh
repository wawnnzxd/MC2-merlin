#!/bin/sh
# Magic Catling 2 卸载脚本
#
# ★ 2026-09-23 审计修复:这一份同时覆盖新旧两种布局(新版界面 / TZ shim + bin/real),
#   两个包各带一份,MC2-merlin/merlinclash/uninstall_merlin.sh 必须与本文件**逐字一致**
#   (本文件是母版;MC2-merlin/check.sh 用 cmp 把关)。
#   · 撤 dnsmasq.postconf 钩子(mc2ui-27,dnsguard-12 ①)
#   · dns-guard 在场就调它的 remove 一起退役(conf.add 兜底段、IP 层封锁),不留看不见的残留(mc2ui-27 返工)
#   · 删新版界面、mc2_status/mc2_fixlink、bin/real/clash(真内核),撤「mc2」页面槽位(mc2ui-26)

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

# 撤 dnsmasq 的 postconf 钩子(2026-09-23 审计修复 mc2ui-27 / dnsguard-12)。
# 上游卸载脚本同样会删这两个软链;我们保留了数据目录,不撤的话链接一直有效,
# 之后每次 dnsmasq 重启(主网络 + IoT/SDN 实例)都会执行 MC2 的 postconf:
# dbus 里的 merlinclash_* 已清空 ⇒ ai_guard 永远判「未接管」,AI 域名时通时断地被封成 0.0.0.0,
# 换了别的代理方案也拿不回来,而且很难联想到是个已卸载插件的残留。
# ⚠️ 必须放在上面的 stop 之后 —— stop_config 里的 restart_dnsmasq 会把链接重新建回来。
#    只删指向 MC2 postconf 的软链,用户自己写的 postconf 不碰。
UNHOOK=0
for l in /jffs/scripts/dnsmasq.postconf /jffs/scripts/dnsmasq-sdn.postconf; do
	[ -L "$l" ] || continue
	case "$(readlink "$l")" in
		*/merlinclash/conf/dnsmasq.postconf) rm -f "$l"; UNHOOK=1 ;;
	esac
done
[ "$UNHOOK" = "1" ] && echo_date "已撤 dnsmasq.postconf 钩子(主网络 + IoT/SDN 实例)"
# dns-guard 一起退役(2026-09-23 审计返工 mc2ui-27):新版 dns-guard 不只靠 postconf ——
#   它还在 /jffs/configs/dnsmasq.conf.add 放了一段「失败即封锁」(梅林不管 postconf 钩子在不在都会加载),
#   开机 V05dnsguard / cron「dnsguard」会把它维护回去;N94aiblock 另有 IP 层 REJECT + DNS 兜底劫持。
#   光撤软链的话,卸完 AI 域名在 DNS 层和 IP 层都还封着,屏幕上却说「已解除」—— 还是 mc2ui-27 那种
#   看不见的残留。新版在场就走它自己的退役流程:写退役标记(开机 / cron 不再打回)、摘掉 postconf
#   补丁段和 conf.add 兜底段、N94 按关闭处理、重启 dnsmasq;以后重装 MC2 时安装脚本的 --force 会清掉标记。
#   旧版 apply.sh 没有 remove(传个不认识的参数它反而会重新打补丁),只能照旧重启 dnsmasq。
DG="$KSROOT/dnsguard/apply.sh"
if [ -f "$DG" ] && grep -qw remove "$DG" 2>/dev/null; then
	sh "$DG" remove >/dev/null 2>&1
	if [ -e "$KSROOT/dnsguard/disabled" ]; then
		echo_date "dns-guard 已退役:AI 域名封锁(DNS 层 + IP 层)随 MC2 一起解除"
	else
		echo_date "【警告】dns-guard 退役没成功,AI 域名可能仍被封锁,手动跑:sh $DG remove"
	fi
	echo_date "  卸载后若不再用任何代理、仍要「AI 要么走代理要么断」,执行:sh $DG enable"
elif [ "$UNHOOK" = "1" ]; then
	# 重启一次,让 stop 时写进去的 address=/…/0.0.0.0 这类记录从当前 dnsmasq 里消失
	service restart_dnsmasq >/dev/null 2>&1
	echo_date "dnsmasq 已重启,AI 域名封锁随 MC2 一起解除"
fi

# ── ② 删文件 ──
# mc2_*.sh 只删 mc2_status.sh / mc2_fixlink.sh —— 同名前缀的 mc2_chnupdate.sh 保留:它另由 migration/
# 单独部署(约定 C6;武汉的 N98 流程也靠它),通配删会误伤(2026-09-23 审计返工 mc2ui-26)。
# (2026-09-23 第二轮起 MC2 包也带一份 mc2_chnupdate.sh,重装会补回;卸载仍不删,没有 MC2 时它留着也无害。)
rm -f "$KSROOT/scripts/"clash_*.sh "$KSROOT/scripts/mc2_status.sh" "$KSROOT/scripts/mc2_fixlink.sh"
rm -f "$KSROOT/scripts/merlinclash_install.sh" "$KSROOT/scripts/uninstall_${module}.sh" \
      "$KSROOT/scripts/uninstall_${module}_dispatch.sh"
rm -f "$KSROOT/webs/Module_merlinclash.asp" "$KSROOT/webs/Module_mc2.asp"
rm -f "$KSROOT/res/merlinclash.css" "$KSROOT/res/icon-merlinclash.png" "$KSROOT/res/icon-mc2.png" \
      "$KSROOT/res/mc2.js" "$KSROOT/res/mc2.css" "$KSROOT/res/mc-menu.js" \
      "$KSROOT/res/accountadd.png" "$KSROOT/res/accountdelete.png"
# bin/clash 是 TZ shim,真内核在 bin/real/clash(约 57MB),两个都是我们的。
# yq/jq、base64 三件套、dummy_script.sh 属于通用兼容件,别的插件可能在用,保留。
rm -f "$KSROOT/bin/clash"
rm -rf "$KSROOT/bin/real"
rm -f "$KSROOT/init.d/"*merlinclash*
# 安装时往 kslite-icons.css 追加过的图标行(带「MC2」标记的那几行)一并收回
[ -f "$KSROOT/res/kslite-icons.css" ] && \
	sed -i -e '/ks-app-merlinclash/d' -e '/\/\* MC2 \*\//d' "$KSROOT/res/kslite-icons.css"

# ⚠️ 数据目录 $KSROOT/merlinclash 保留 —— 里面是机场节点配置(yaml_use)、
#    自定义规则、订阅缓存。卸载重装不该丢,要彻底清理请手工:
#        rm -rf $KSROOT/merlinclash
echo_date "数据目录已保留:$KSROOT/merlinclash(节点与规则配置)"

# ── ③ 撤菜单 ──
# 不撤的话文件都删光了菜单还杵着,点进去是空白页(2026-08-25 卸 gostun 时踩过)。
# 两个都要撤:del merlinclash 撤「Magic Catling」菜单行(页名 merlinclash)与老页面槽位;
# del mc2 撤新版界面 Module_mc2.asp 的槽位,以及手工挂过的页名 mc2 的菜单行(如「MC2 新版」)。
if [ -x "$KSROOT/scripts/ks-autoreg.sh" ]; then
	"$KSROOT/scripts/ks-autoreg.sh" del "$module" >/dev/null 2>&1
	"$KSROOT/scripts/ks-autoreg.sh" del mc2 >/dev/null 2>&1
fi

# ── ④ 清 dbus ──
for k in install version name title description; do dbus remove softcenter_module_${module}_$k; done
# MC2 自己的键全清(含 128 个 nokpacl_ ACL 项),但保留 sub_links ——
# 那是用户手填的机场订阅地址,重装后不用再找一遍。
for k in $(dbus list merlinclash 2>/dev/null | sed 's/=.*//'); do
	[ "$k" = "merlinclash_sub_links" ] && continue
	dbus remove "$k"
done

echo_date "卸载完成。"
