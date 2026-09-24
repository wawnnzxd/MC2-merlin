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
#
# ★ 2026-09-23 审计修复(覆盖安装不许再悄悄回退线上定制,P3):
#   · yaml_dns / yaml_basic 不再整目录 rm -rf 覆盖,只补缺失文件(mc2ui-02)
#   · 内核按「bin/clash = TZ shim、bin/real/clash = 真内核」布局装,不盖 shim、不降级(mc2ui-16)
#   · base64 / base64_decode / base64_encode 三件套 755 落盘(mc2ui-04,约定 C5)
#   · 装完立刻重打 dns-guard 并重启 dnsmasq(dnsguard-04,约定 C7)
#   · 安装前代理开着的,装完恢复开关并后台重启 MC2(mc2ui-06)
#   · 菜单 URL 以 Module_mc2.asp 实际槽位为准,装完重铺 tmpfs 页面/资源(mc2ui-35、softcenter-18)
#   ⚠️ GT-BE19000AI/mc2-merlin/plugin/install.sh 是同一套逻辑的旧包布局版,改这里要同步改那里。

KSROOT="${KSROOT:-/jffs/koolshare}"
[ -d /koolshare ] && KSROOT=/koolshare

. "$KSROOT/scripts/base.sh"
alias echo_date='echo 【$(TZ=UTC-8 date -R +%Y年%m月%d日\ %X)】:'

DIR=$(cd "$(dirname "$0")"; pwd)
module=merlinclash
TITLE="Magic Catling"

# ── 内核安装(2026-09-23 审计修复 mc2ui-16)──
# 线上布局(2026-08-27 起):bin/clash 是几行的 TZ shim(unset TZ; exec bin/real/clash),
# 真内核在 bin/real/clash;用户会在面板上「在线更新 alpha 内核」,写的是 real/clash。
# 原来对 bin/clash 直接 cp -f,用包里 46.6MB 的旧内核(alpha-f295ba6)把 shim 整个盖掉:
# 时间戳又差 8 小时(Go 不认 TZ=GMT-8)、内核降级、57MB 的 real/clash 成孤儿。现在:
#   · bin/clash 一律是 shim(旧布局里的 ELF / 软链先迁进 real/);
#   · real/clash 只在「缺失 / 跑不起来 / 比包里的旧」时才换。alpha 版本号是 commit hash,
#     比不了大小,比的是 `clash -v` 行尾的构建时间(形如 … with go1.26.8 Fri Sep 11 02:06:35 UTC 2026);
#     现有内核能跑、但构建时间读不出(自编译 / 格式不同)时一律保留,宁可不升级也不降级。
core_probe(){   # $1 = 内核文件 → 设全局变量 CORE_RUN / CORE_ST(别放进 $() 里调,变量带不出来)
	# CORE_RUN=1:能跑,`-v` 首行是 Mihomo / Clash 版本行;CORE_ST:行尾构建时间 YYYYMMDDhhmmss,读不出为空。
	# 2026-09-23 审计返工 mc2ui-16:「跑不起来」和「能跑、但构建时间格式不认识」必须分开 ——
	#   原来两者都输出空、一律当成内核坏了换掉:自编译内核(没注入 BuildTime,行尾是 `unknown time`)、
	#   行尾是 RFC3339 时间的内核明明好好的,也会被包里更旧的内核悄悄盖掉,正是这里要防的降级。
	CORE_RUN=0; CORE_ST=""
	[ -f "$1" ] || return 0
	chmod 755 "$1" 2>/dev/null
	# 跑两次:「跑不起来」会被当成内核坏了而换掉它,别让一次偶发失败造成降级。
	# 只看第 1 行,但把输出读完(不用 head -1 提前关管道,免得内核写第 2 行时吃 SIGPIPE)。
	for _try in 1 2; do
		_l=$("$1" -v 2>/dev/null | awk 'NR == 1')
		case "$_l" in Mihomo*|Clash*) ;; *) continue ;; esac
		CORE_RUN=1
		# NF 不够的行不碰:busybox awk 取负数下标的字段会段错误。
		CORE_ST=$(echo "$_l" | awk 'NF >= 6 {
			y = $NF; t = $(NF-2); d = $(NF-3); mon = $(NF-4)
			m = (length(mon) == 3) ? index("JanFebMarAprMayJunJulAugSepOctNovDec", mon) : 0
			if (y ~ /^[0-9][0-9][0-9][0-9]$/ && t ~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/ && d ~ /^[0-9][0-9]?$/ && m > 0 && m % 3 == 1) {
				gsub(":", "", t)
				printf "%s%02d%02d%s\n", y, (m + 2) / 3, d, t
			}
		}')
		return 0
	done
	return 0
}
core_newer(){  # $1 比 $2 新才返回 0;取不到时间的一方当作最旧
	awk -v a="$1" -v b="$2" 'BEGIN { exit !(a != "" && (b == "" || a > b)) }'
}
install_core(){  # $1 = 包里的内核
	PKG="$1"; B="$KSROOT/bin"; R="$B/real/clash"
	[ -f "$PKG" ] || return 0
	mkdir -p "$B/real"
	# ① 旧布局迁移:bin/clash 还是真内核(ELF,或早期 ksdata 布局下指向 ELF 的软链)
	if [ -L "$B/clash" ]; then
		[ -e "$R" ] || ln -sf "$(readlink "$B/clash")" "$R"
		rm -f "$B/clash"
	elif [ -f "$B/clash" ] && [ "$(head -c 2 "$B/clash")" != "#!" ]; then
		# 旧安装器把 shim 盖成 ELF 的混合态。real/ 是用户「在线更新内核」写的那份:
		# 它能跑、且 bin/ 这份不是**确定**更新(两边构建时间都读得出、bin/ 更晚)时,留 real/;否则用 bin/ 这份
		core_probe "$B/clash"; B_ST=$CORE_ST
		core_probe "$R"
		if [ -e "$R" ] && [ "$CORE_RUN" = "1" ] && ! { [ -n "$CORE_ST" ] && core_newer "$B_ST" "$CORE_ST"; }; then
			rm -f "$B/clash"
		else
			rm -f "$R"; mv -f "$B/clash" "$R"
		fi
	fi
	# ② 真内核:缺失 / 跑不起来 / 确定比包里的旧 才换(先写 .new 再 rename,内核在跑也不会 ETXTBSY)
	core_probe "$PKG"; S_PKG=$CORE_ST
	core_probe "$R"; S_OLD=$CORE_ST
	DO=0
	if [ "$CORE_RUN" != "1" ]; then
		DO=1
		if [ -e "$R" ]; then MSG="现有内核跑不起来"; else MSG="原先没有内核"; fi
	elif [ -z "$S_OLD" ]; then
		echo_date "  内核保留现有 bin/real/clash(能跑,但构建时间格式不认识、没法和安装包比新旧,不冒险替换)"
	elif core_newer "$S_PKG" "$S_OLD"; then
		DO=1; MSG="替换构建于 $S_OLD 的旧内核"
	else
		echo_date "  内核保留现有 bin/real/clash(构建于 $S_OLD,不旧于安装包的 ${S_PKG:-?})"
	fi
	if [ "$DO" = "1" ]; then
		D="$R"; [ -L "$R" ] && D=$(readlink "$R")
		if cp -f "$PKG" "$D.new" && chmod 755 "$D.new" && mv -f "$D.new" "$D"; then
			echo_date "  内核 → bin/real/clash(${MSG},新内核构建于 ${S_PKG:-?})"
		else
			rm -f "$D.new"; echo_date "  【警告】内核写入 $D 失败"
		fi
	fi
	# ③ shim:已经是指向 real/clash 的脚本就不动(保留线上那份带注释的原件),否则重写
	if [ -f "$B/clash" ] && [ ! -L "$B/clash" ] && [ "$(head -c 2 "$B/clash")" = "#!" ] \
	   && grep -q "real/clash" "$B/clash" 2>/dev/null; then
		:
	else
		rm -f "$B/clash"
		cat > "$B/clash" <<EOF
#!/bin/sh
# TZ shim —— 由 MC2 安装脚本生成(原件 2026-08-27,来龙去脉见 路由器插件/CLAUDE.md「TZ shim」)
# ASUS 固件环境是 TZ=GMT-8,mihomo(Go)只认 IANA 名,解析不了就静默按 UTC,时间戳差 8 小时。
# unset 之后 Go 自己读 /etc/localtime。文件名必须叫 clash:MC2 用 pidof/killall clash 管进程。
unset TZ
exec $R "\$@"
EOF
		echo_date "  bin/clash → TZ shim(exec $R)"
	fi
	chmod 755 "$B/clash" "$R" 2>/dev/null
}

echo_date "安装 Magic Catling 2(梅林定制版)…"

# ── ① 空间检查 ──
NEED=90000   # KB,内核 44.5M + 数据,留余量
FREE=$(df -k "$KSROOT" 2>/dev/null | tail -1 | awk '{print $4}')
if [ -n "$FREE" ] && [ "$FREE" -lt "$NEED" ]; then
	echo_date "【中止】空间不足:剩余 $((FREE/1024))M,需要 $((NEED/1024))M"
	# 2026-09-23 审计修复 mc2ui-37:原来提示「大文件可搬去 /jffs/ksdata」—— 08-26 起 p11 直接挂在
	#   /jffs/koolshare,/jffs/ksdata 已是 200M 的 /jffs 上的普通目录,照做只会把 /jffs 撑爆。
	echo_date "提示:先 df -h $KSROOT 看看是谁占满了分区"
	exit 1
fi
echo_date "空间检查通过(剩余 $((FREE/1024))M)"

# ── ② 停掉可能在跑的旧进程 ──
# 2026-09-23 审计修复 mc2ui-06:stop_config 会把 merlinclash_enable 写成 0,原来装完不恢复 ——
#   覆盖安装后代理一直关着(natguard / 开机自启都只认 enable=1),没人发现就一直关着。
#   先记下安装前的开关,第 ⑩ 步照原样恢复。
OLD_EN=$(dbus get merlinclash_enable)
if pidof clash >/dev/null 2>&1; then
	echo_date "停止正在运行的 clash…"
	[ -x "$KSROOT/scripts/clash_config.sh" ] && "$KSROOT/scripts/clash_config.sh" "" stop >/dev/null 2>&1
	killall clash 2>/dev/null
	sleep 2
fi

# ── ③ 路径改写 ──
# 只对代码目录做,不碰 bin64/ 和数据目录(ELF 与 .dat 让 grep 扫纯属浪费);
# 唯一含 /koolshare 的数据文件 conf/dnsmasq.postconf 单独处理。
# (这里写字面量 /koolshare 没问题:经软件中心装时整包已被 fixpath 过,条件变假、跳过的正是已做完的事;
#  SSH 里直接 sh install.sh 时条件为真、照常改写)
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
# 菜单图标:softcenter-lite 自带的 kslite-icons.css 里 .ks-app-mc2 指向 /user/res/icon-mc2.png,
# 而本包只带 icon-merlinclash.png(下面 ⑧ 见到已有 ks-app-mc2 就不再追加自己的规则)——
# 两个名字都放一份,哪条规则生效图标都在(2026-09-23 审计 softcenter-18 顺带发现)。
cp -f "$DIR/res/icon-merlinclash.png" "$KSROOT/res/icon-mc2.png"
rm -f "$KSROOT/webs/Module_merlinclash.asp" \
      "$KSROOT/res/merlinclash.css" "$KSROOT/res/mc-menu.js" \
      "$KSROOT/res/accountadd.png" "$KSROOT/res/accountdelete.png"
[ -x "$KSROOT/scripts/ks-autoreg.sh" ] && "$KSROOT/scripts/ks-autoreg.sh" del "$module" >/dev/null 2>&1
cp -rf "$DIR/init.d/"*  "$KSROOT/init.d/"

# bin64:内核单独走 install_core(见上);其余可执行文件照旧。
# 软链(早期 ksdata 布局)照旧解引用写穿;普通文件拷成 .new 再 mv 原子替换 —— 目标若是硬链
# (早期手工 ln 过 base64_decode),原地覆盖会把另一个名字的内容一起改掉;rename 只换目录项。
# (2026-09-23 审计修复 B-X2 ①:以前是先 rm 再 cp,拷失败(空间满)时旧文件已经没了;
#  相对软链以前按当前目录解析,会写到别处 —— 现在按链接所在目录解析。)
for f in "$DIR/bin64/"*; do
	[ -f "$f" ] || continue
	n=$(basename "$f")
	[ "$n" = "clash" ] && continue
	T="$KSROOT/bin/$n"
	if [ -L "$T" ]; then
		R=$(readlink "$T"); case "$R" in /*) ;; *) R="${T%/*}/$R" ;; esac
		cp -f "$f" "$R" && echo_date "  $n → $R(经软链)"
	else
		cp -f "$f" "$T.new" && chmod 755 "$T.new" && mv -f "$T.new" "$T" \
			|| { rm -f "$T.new"; echo_date "【警告】bin/$n 没装上(旧文件保留)"; }
	fi
done
# 2026-09-23 审计修复 mc2ui-04(约定 C5):clash_base.sh 的 decode_url_link / encode_url_link、
#   clash_yamlfilechange.sh 按固定名找 base64_decode / base64_encode(koolshare 固件自带,原版梅林没有)。
#   缺 decode:订阅与自定规则解码恒为空;缺 encode:push_dbus 把 ACL 全写成空串 → `,,` 规则 → 内核起不来。
#   包里带了就用包里的(上面的循环已装);没带就从 base64 派生 —— 它按 -d 分派方向,两个名字都能用。
for n in base64_decode base64_encode; do
	[ -f "$DIR/bin64/$n" ] && continue
	[ -f "$KSROOT/bin/base64" ] || continue
	cp -f "$KSROOT/bin/base64" "$KSROOT/bin/$n.new" && chmod 755 "$KSROOT/bin/$n.new" \
		&& mv -f "$KSROOT/bin/$n.new" "$KSROOT/bin/$n" || rm -f "$KSROOT/bin/$n.new"
done
install_core "$DIR/bin64/clash"
cp -f "$DIR/uninstall.sh"           "$KSROOT/scripts/uninstall_${module}_dispatch.sh"
cp -f "$DIR/uninstall_merlin.sh"    "$KSROOT/scripts/uninstall_${module}.sh"

# ── ⑤ 部署数据 ──
# 包内布局(跟上游):clash/=Geo库+时区,conf/rule_configs/yaml_basic/yaml_dns 散目录。
# 安装后布局:全部收进 $KSROOT/merlinclash/(两种固件一致)。
MDIR="$KSROOT/merlinclash"
if [ -d "$MDIR" ]; then
	# 2026-09-23 审计修复 mc2ui-02:原来这里说「保留用户配置」,循环里却对 yaml_basic / yaml_dns
	#   整目录 rm -rf 再换成包里的上游默认模板 —— 手工对齐过的 DNS 母版(APPLE-ALL-OVERSEAS、
	#   airwallex 境外解析……)被静默冲掉,金融后台登录 IP 跳回国内(08-27 Airwallex 事故的原样重演)。
	#   现在这两个目录只补缺失文件;上游 install_koolshare.sh 升级时同样不碰 yaml_dns、保留 head/hosts。
	echo_date "检测到已有数据目录:更新 Geo 库 / 面板 / 规则模板;yaml_dns、yaml_basic 保留用户文件,只补缺失项"
	# ⚠️ 这几项可能被搬去 /jffs/ksdata,原位只剩软链 —— 直接 cp -rf 会把软链
	#    替换成真文件,数据又落回 jffs。先解引用,写到软链真正指向的地方。
	for pair in "clash/GeoIP.dat:GeoIP.dat" "clash/GeoSite.dat:GeoSite.dat" \
	            "dashboard:dashboard" "rule_configs:rule_configs"; do
		S="$DIR/${pair%%:*}"; N="${pair##*:}"; T="$MDIR/$N"
		[ -e "$S" ] || continue
		# Geo 库:现有的已是 >1MB 的完整库(页面上选过 full 并更新过)就保留,
		# 不拿包里的精简库倒回去 —— 与上游 install_koolshare.sh 的判断一致。
		case "$N" in GeoIP.dat|GeoSite.dat)
			SZ=$(wc -c < "$T" 2>/dev/null)
			if [ -n "$SZ" ] && [ "$SZ" -gt 1000000 ]; then
				echo_date "  $N 已是完整库(${SZ} 字节),保留(要更新到页面上点「设置并更新」)"
				continue
			fi ;;
		esac
		if [ -L "$T" ]; then
			R=$(readlink "$T")
			if [ -d "$S" ]; then rm -rf "$R"; cp -rf "$S" "$R"; else cp -f "$S" "$R"; fi
			echo_date "  $N → $R(经软链)"
		else
			if [ -d "$S" ]; then rm -rf "$T"; fi
			cp -rf "$S" "$MDIR/"
		fi
	done
	# yaml_basic / yaml_dns:只补缺失文件,已有的一个字节不动(目录是软链时写穿)
	for sub in yaml_basic yaml_dns; do
		[ -d "$DIR/$sub" ] || continue
		T="$MDIR/$sub"; [ -L "$T" ] && T=$(readlink "$T")
		mkdir -p "$T"
		for f in "$DIR/$sub/"*; do
			[ -f "$f" ] || continue
			n=$(basename "$f")
			case "$n" in *.bak*) continue ;; esac
			[ -e "$T/$n" ] && continue
			cp -f "$f" "$T/$n" && echo_date "  补缺:$sub/$n"
		done
	done
	# 包里的 postconf 是上游原版(不含 dns-guard 补丁),第 ⑨ 步会立刻重打
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
          "$KSROOT/init.d/"*merlinclash* "$KSROOT/bin/clash" "$KSROOT/bin/real/clash" \
          "$KSROOT/bin/yq" "$KSROOT/bin/jq" "$KSROOT/bin/base64" \
          "$KSROOT/bin/base64_decode" "$KSROOT/bin/base64_encode" \
          "$MDIR/conf/dnsmasq.postconf" 2>/dev/null

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
# 走 bin/clash(shim)→ 报的是**实际装着的**内核(可能是保留下来的更新版),不是包里那份
CLVER="$("$KSROOT/bin/clash" -v 2>/dev/null | head -1 | awk '{print $3}')"
dbus set softcenter_module_${module}_version="${PLVER}"
dbus set softcenter_module_${module}_install="1"
dbus set softcenter_module_${module}_name="${module}"
dbus set softcenter_module_${module}_title="${TITLE}"
# 2026-09-24:说明里不再带内核版本 —— 用户会在 MC2 里在线更新 alpha 内核,那条路径不回写这个键,
#   软件中心就一直挂着安装时的旧版本号(当天实测写着 f295ba6、实际跑 dca26db)。版本以插件页顶部实时读数为准。
dbus set softcenter_module_${module}_description="mihomo 透明代理"
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
	# 2026-09-23 审计修复 mc2ui-35:菜单 URL 以 webs.conf 里 Module_mc2.asp **实际占的槽位**为准。
	#   原来从 topmenu.conf 反查,可第 ④ 步 `ks-autoreg.sh del merlinclash` 已经把那行删了,
	#   永远取不到,只能退回写死的 /user8.asp —— 槽位不是 8(p11 重建后重新分配)时菜单就指错页。
	SLOT=$(grep "|Module_mc2.asp\$" "$KSROOT/webs.conf" 2>/dev/null | cut -d'|' -f1 | head -1)
	# 页名 mc2 / merlinclash 的旧菜单行全部撤掉(autoreg 新挂的「mc2」、v1.1.0 时期手工挂的
	# 「MC2 新版」),下面统一重挂一行。先整体取出再逐行删:边读边改 topmenu.conf 不可靠。
	if [ -n "$SLOT" ]; then
		OLDS=$(grep -E "\|(mc2|merlinclash)\|" "$KSROOT/topmenu.conf" 2>/dev/null | cut -d'|' -f1)
		echo "$OLDS" | while IFS= read -r OLD; do
			[ -n "$OLD" ] && "$KSROOT/scripts/ks-topmenu.sh" del "$OLD" >/dev/null 2>&1 </dev/null
		done
		"$KSROOT/scripts/ks-topmenu.sh" add "$TITLE" "merlinclash" "/user${SLOT}.asp" "ks-app-icon ks-app-mc2" >/dev/null 2>&1
		echo_date "菜单:「$TITLE」→ /user${SLOT}.asp(页名 merlinclash)"
	else
		echo_date "【警告】webs.conf 里找不到 Module_mc2.asp 的槽位(20 个 Addon 槽位用完?),「Magic Catling」菜单没挂上,腾出槽位后重装一次"
	fi
fi

# 2026-09-23 审计修复 mc2ui-35 / softcenter-18:浏览器读的是 /tmp/var/wwwext 里的**副本**。
#   模块已登记时 autoreg 直接跳过、不重铺(覆盖升级后页面还是旧的);首装时图标样式又是在
#   autoreg 铺完之后才追加的(菜单图标要到重启才出现)。这里无条件重铺一次(deploy 幂等)。
[ -x "$KSROOT/scripts/ks-webs.sh" ] && sh "$KSROOT/scripts/ks-webs.sh" deploy >/dev/null 2>&1 \
	&& echo_date "页面与资源已重铺到 /tmp/var/wwwext"

# ── ⑨ 重打 dns-guard(约定 C7;2026-09-23 审计修复 dnsguard-04 / mc2ui-06)──
# 第 ⑤ 步装进来的 postconf 是上游原版,没有 ai_guard(AI 域名 kill-switch + DNS 兜底)。
# 原来只有开机时 V05dnsguard 才打回,而每日重启已长期关闭 ⇒ 可能几周没有保护、也没有任何日志。
# 装完立刻按内容版本重打并重启 dnsmasq。旧版 apply.sh 不认 --force/--restart,退回 reload 语义
# (补丁缺失时打入并重启 dnsmasq),效果相同。
PC="$MDIR/conf/dnsmasq.postconf"
if [ -f "$KSROOT/dnsguard/apply.sh" ]; then
	if grep -q -- "--restart" "$KSROOT/dnsguard/apply.sh" 2>/dev/null; then
		sh "$KSROOT/dnsguard/apply.sh" --force --restart >/dev/null 2>&1
	else
		sh "$KSROOT/dnsguard/apply.sh" reload >/dev/null 2>&1
	fi
	if grep -q "ai_guard" "$PC" 2>/dev/null; then
		echo_date "dns-guard 补丁已重新打入 postconf,dnsmasq 已重启"
	else
		echo_date "【警告】dns-guard 补丁没能打入 postconf,AI 封锁 / DNS 兜底失效!手动跑:sh $KSROOT/dnsguard/apply.sh"
	fi
fi

# ── ⑩ 收尾:按安装前的状态恢复总开关 ──
echo_date "当前内核:$("$KSROOT/bin/clash" -v 2>/dev/null | head -1)"
echo_date "Magic Catling 2 安装完毕!"
# 2026-09-23 审计返工 mc2ui-06:MC2 自更新(clash_selfupdate.sh)调本脚本时,它自己会在装完后
#   `dbus set merlinclash_enable=1` + `clash_config.sh restart restart` —— 那条 restart 分支不拿 MC2 的锁,
#   这里再后台起一次 start,两轮 apply_mc 会同时跑(kill/flush/启动各两遍,可能起两个内核、规则重复)。
#   自更新在场就把恢复交给它:认它导出的 MC2_SELFUPDATE=1,或它的锁目录在、锁不到 15 分钟
#   (与 clash_selfupdate.sh 自己判陈旧锁的 900 秒一致)、且状态是 installing:*。
#   状态单独看不作数 —— 自更新中途挂掉会一直停在 installing;锁在 /tmp,重启即清。
SELFUPD=0
[ "$MC2_SELFUPDATE" = "1" ] && SELFUPD=1
if [ -d /tmp/mc_selfupdate.lock ]; then
	_ts=$(cat /tmp/mc_selfupdate.lock/ts 2>/dev/null)
	case "$_ts" in ''|*[!0-9]*) _ts=0 ;; esac
	case "$(dbus get merlinclash_selfupdate_status)" in
		installing:*) [ $(($(date +%s) - _ts)) -lt 900 ] && SELFUPD=1 ;;
	esac
fi
if [ "$SELFUPD" = "1" ]; then
	echo_date "由 MC2 自更新调用:总开关恢复与内核重启交给自更新流程(不在这里重复启动)"
elif [ "$OLD_EN" = "1" ]; then
	dbus set merlinclash_enable=1
	echo_date "安装前代理是开着的 → 已恢复总开关,后台重启 MC2(约半分钟,进度看页面日志)"
	# 走前端「应用」同一条路($2=start:加锁 → apply_mc → 写结束标记)。
	# 双重 fork 脱离安装进程组:busybox 没有 setsid,软件中心装完会回收进程组。
	( nohup sh "$KSROOT/scripts/clash_config.sh" "" start >/dev/null 2>&1 & ) &
else
	echo_date "总开关保持关闭(安装前就是关的),到页面上确认后再启用。"
fi
