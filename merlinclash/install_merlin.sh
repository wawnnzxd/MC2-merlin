#!/bin/sh
# Magic Catling 2 —— 原版梅林(koolshare-shim)安装分支
#
# 与 install_koolshare.sh(上游 21KB)的关系:
#   上游那份做了大量 koolshare 固件专属的事 —— 软件中心注册、perp 守护装配、
#   在线下载内核、判断 U 盘挂载点…… 在原版梅林上大半跑不通。
#   这份是**重写**的,只做三件事:把文件放对位置、初始化配置、挂菜单。
#
#   ⚠️ MC2 本体的上游脚本一个字节都不改(唯一例外 clash_config.sh 的
#      startime 引号修复,见脚本内注释)。里面几百处 /koolshare 由
#      ks-fixpath.sh 在安装时改写 —— 同一份源码两种固件都能装。
#
# UI 策略(2026-08-25 定):梅林侧只装新版界面(Module_mc2.asp,BE19000AI
# 风格),并清掉老版 ASP 的部署与菜单;koolshare 侧走 install_koolshare.sh
# 装老皮肤。一份包,两套皮肤,互不掺和。

KSROOT="${KSROOT:-/jffs/koolshare}"
[ -d /koolshare ] && KSROOT=/koolshare

. "$KSROOT/scripts/base.sh"
alias echo_date='echo 【$(TZ=UTC-8 date -R +%Y年%m月%d日\ %X)】:'

DIR=$(cd "$(dirname "$0")"; pwd)
module=merlinclash
TITLE="Magic Catling"

echo_date "安装 Magic Catling 2(梅林定制版)…"

# ── ① 空间检查 ──
NEED=90000   # KB,内核 44.5M + 数据,留余量
FREE=$(df -k "$KSROOT" 2>/dev/null | tail -1 | awk '{print $4}')
if [ -n "$FREE" ] && [ "$FREE" -lt "$NEED" ]; then
	echo_date "【中止】空间不足:剩余 $((FREE/1024))M,需要 $((NEED/1024))M"
	echo_date "提示:大文件可搬去 /jffs/ksdata(见 emmc-expand),原位留软链,本脚本会跟着软链写"
	exit 1
fi
echo_date "空间检查通过(剩余 $((FREE/1024))M)"

# ── ② 停掉可能在跑的旧进程 ──
if pidof clash >/dev/null 2>&1; then
	echo_date "停止正在运行的 clash…"
	[ -x "$KSROOT/scripts/clash_config.sh" ] && "$KSROOT/scripts/clash_config.sh" "" stop >/dev/null 2>&1
	killall clash 2>/dev/null
	sleep 2
fi

# ── ③ 路径改写 ──
# 只对代码目录做,不碰 bin64/ 和数据目录(ELF 与 .dat 让 grep 扫纯属浪费);
# 唯一含 /koolshare 的数据文件 conf/dnsmasq.postconf 单独处理。
if [ "$KSROOT" != "/koolshare" ] && [ -x "$KSROOT/scripts/ks-fixpath.sh" ]; then
	for d in scripts webs res init.d config; do
		[ -d "$DIR/$d" ] && KSROOT="$KSROOT" "$KSROOT/scripts/ks-fixpath.sh" "$DIR/$d" >/dev/null 2>&1
	done
	PC="$DIR/conf/dnsmasq.postconf"
	[ -f "$PC" ] && sed -i "s|$KSROOT|@@PH@@|g; s|/koolshare|$KSROOT|g; s|@@PH@@|$KSROOT|g" "$PC"
	echo_date "路径改写完毕(/koolshare → $KSROOT)"
fi

# ── ④ 部署代码 ──
mkdir -p "$KSROOT/scripts" "$KSROOT/webs" "$KSROOT/res" "$KSROOT/bin" "$KSROOT/init.d"
cp -rf "$DIR/scripts/"* "$KSROOT/scripts/"
# UI:只装新版。老版 ASP(Module_merlinclash.asp)是 koolshare 皮肤,这里不部署,
# 且清掉先前部署过的,避免 ks-autoreg 重装时把老页面又挂回菜单。
cp -f "$DIR/webs/Module_mc2.asp" "$KSROOT/webs/"
cp -f "$DIR/res/mc2.js" "$DIR/res/mc2.css" "$DIR/res/icon-merlinclash.png" "$KSROOT/res/"
rm -f "$KSROOT/webs/Module_merlinclash.asp" \
      "$KSROOT/res/merlinclash.css" "$KSROOT/res/mc-menu.js" \
      "$KSROOT/res/accountadd.png" "$KSROOT/res/accountdelete.png"
[ -x "$KSROOT/scripts/ks-autoreg.sh" ] && "$KSROOT/scripts/ks-autoreg.sh" del "$module" >/dev/null 2>&1
cp -rf "$DIR/init.d/"*  "$KSROOT/init.d/"

# bin64 单独处理:clash 有 44.5M,通常被搬到别的分区(见 emmc-expand),
# 原位置只剩软链。busybox 的 cp 会把软链换成实体文件,44M 就又压回 jffs。
# 显式解引用,写到软链指向的地方。
for f in "$DIR/bin64/"*; do
	[ -f "$f" ] || continue
	T="$KSROOT/bin/$(basename "$f")"
	if [ -L "$T" ]; then
		cp -f "$f" "$(readlink "$T")" && echo_date "  $(basename "$f") → $(readlink "$T")(经软链)"
	else
		cp -f "$f" "$T"
	fi
done
cp -f "$DIR/uninstall.sh"           "$KSROOT/scripts/uninstall_${module}_dispatch.sh"
cp -f "$DIR/uninstall_merlin.sh"    "$KSROOT/scripts/uninstall_${module}.sh"

# ── ⑤ 部署数据 ──
# 包内布局(跟上游):clash/=Geo库+时区,conf/rule_configs/yaml_basic/yaml_dns 散目录。
# 安装后布局:全部收进 $KSROOT/merlinclash/(两种固件一致)。
MDIR="$KSROOT/merlinclash"
if [ -d "$MDIR" ]; then
	echo_date "检测到已有数据目录,保留用户配置,只更新数据库与面板"
	# ⚠️ 这几项可能被搬去 /jffs/ksdata,原位只剩软链 —— 直接 cp -rf 会把软链
	#    替换成真文件,数据又落回 jffs。先解引用,写到软链真正指向的地方。
	for pair in "clash/GeoIP.dat:GeoIP.dat" "clash/GeoSite.dat:GeoSite.dat" \
	            "dashboard:dashboard" "rule_configs:rule_configs" \
	            "yaml_basic:yaml_basic" "yaml_dns:yaml_dns"; do
		S="$DIR/${pair%%:*}"; N="${pair##*:}"; T="$MDIR/$N"
		[ -e "$S" ] || continue
		if [ -L "$T" ]; then
			R=$(readlink "$T")
			if [ -d "$S" ]; then rm -rf "$R"; cp -rf "$S" "$R"; else cp -f "$S" "$R"; fi
			echo_date "  $N → $R(经软链)"
		else
			if [ -d "$S" ]; then rm -rf "$T"; fi
			cp -rf "$S" "$MDIR/"
		fi
	done
	cp -f "$DIR/conf/dnsmasq.postconf" "$MDIR/conf/" 2>/dev/null
	cp -f "$DIR/clash/Shanghai" "$MDIR/" 2>/dev/null
	cp -f "$DIR/version" "$MDIR/version"
else
	echo_date "首次安装,初始化数据目录"
	mkdir -p "$MDIR/yaml_use" "$MDIR/yaml_bak" "$MDIR/mark" "$MDIR/rule_custom" "$MDIR/ruleset"
	cp -rf "$DIR/conf" "$DIR/rule_configs" "$DIR/yaml_basic" "$DIR/yaml_dns" "$DIR/dashboard" "$MDIR/"
	cp -f "$DIR/clash/GeoIP.dat" "$DIR/clash/GeoSite.dat" "$DIR/clash/Shanghai" "$MDIR/"
	cp -f "$DIR/version" "$MDIR/version"
fi

chmod 755 "$KSROOT/scripts/"clash_*.sh "$KSROOT/scripts/"mc2_*.sh \
          "$KSROOT/scripts/dummy_script.sh" "$KSROOT/scripts/uninstall_${module}.sh" \
          "$KSROOT/init.d/"*merlinclash* "$KSROOT/bin/clash" "$KSROOT/bin/yq" \
          "$KSROOT/bin/jq" "$KSROOT/bin/base64" "$MDIR/conf/dnsmasq.postconf" 2>/dev/null

# ── ⑥ 初始化配置(只写缺失键,覆盖安装不冲用户设置)──
if [ -f "$DIR/config/defaults.conf" ]; then
	N=0
	while IFS= read -r line; do
		case "$line" in ''|'#'*) continue;; esac
		k="${line%%=*}"; v="${line#*=}"
		[ -z "$(dbus get "$k")" ] && { dbus set "$k=$v"; N=$((N+1)); }
	done < "$DIR/config/defaults.conf"
	echo_date "配置初始化:写入 $N 个新键(已有的保持不动)"
fi

# ── ⑦ 强制项 ──
# watchdog=1 会走 perp(koolshare 私有),原版梅林没有 → 内核根本起不来
dbus set merlinclash_set_watchdog_sw=0
dbus set merlinclash_linuxver="$(uname -r | awk -F. '{print $1$2}')"

# ── ⑧ 注册 + 挂菜单(新 UI:页面模块名 mc2)──
PLVER="$(cat "$DIR/version" 2>/dev/null)"
CLVER="$("$KSROOT/bin/clash" -v 2>/dev/null | head -1 | awk '{print $3}')"
dbus set softcenter_module_${module}_version="${PLVER}"
dbus set softcenter_module_${module}_install="1"
dbus set softcenter_module_${module}_name="${module}"
dbus set softcenter_module_${module}_title="${TITLE}"
dbus set softcenter_module_${module}_description="mihomo 代理 ${CLVER}"
dbus set merlinclash_version="${PLVER}"
dbus set merlinclash_core_version="${CLVER}"

[ -x "$KSROOT/scripts/ks-autoreg.sh" ] && "$KSROOT/scripts/ks-autoreg.sh" mc2

# 图标 + 菜单行统一。autoreg 按 Module_mc2.asp 推出的页名是 mc2,但软件中心条目
# 的 name=merlinclash,「打开」按钮走 pageRedirect(name) → 找 pages/merlinclash.html
# —— 页名必须叫 merlinclash 才能对上(2026-08-25 清理双条目时踩到:页名 mc2 时
# Magic Catling 条目的打开按钮点了没反应)。所以 autoreg 之后无条件把菜单行
# 重挂成 module=merlinclash(del+add 幂等,标题、页名一次对齐)。
CSS="$KSROOT/res/kslite-icons.css"
if [ -f "$CSS" ] && [ -x "$KSROOT/scripts/ks-topmenu.sh" ]; then
	grep -q "ks-app-mc2" "$CSS" || \
		echo ".ks-app-mc2 { background-image: url(\"/user/res/icon-merlinclash.png\"); }  /* MC2 */" >> "$CSS"
	OLD=$(grep -E "\|(mc2|merlinclash)\|" "$KSROOT/topmenu.conf" 2>/dev/null | cut -d'|' -f1 | head -1)
	URL=$(grep -E "\|(mc2|merlinclash)\|" "$KSROOT/topmenu.conf" 2>/dev/null | cut -d'|' -f3 | head -1)
	[ -n "$OLD" ] && "$KSROOT/scripts/ks-topmenu.sh" del "$OLD" >/dev/null 2>&1
	"$KSROOT/scripts/ks-topmenu.sh" add "$TITLE" "merlinclash" "${URL:-/user8.asp}" "ks-app-icon ks-app-mc2" >/dev/null 2>&1
	echo_date "菜单:「${OLD:-新装}」→「$TITLE」(页名 merlinclash)"
fi

echo_date "内置内核:$("$KSROOT/bin/clash" -v 2>/dev/null | head -1)"
echo_date "Magic Catling 2 安装完毕!"
echo_date "⚠️ 总开关默认关闭,到页面上确认后再启用。"
