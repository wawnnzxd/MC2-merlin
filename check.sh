#!/bin/sh
# check.sh —— 不变量断言。两条线踩过的坑,固化成 grep,发版前跑一次。
#
#   sh check.sh
#
# 存在的理由:这个仓库被两条线同时改(见 COLLAB.md),而两边的 git author 完全相同。
# 重构/拆分文件时很容易把对面的修复顺手做没了 —— 比如 1.2.2.13 把 install.sh 拆成
# koolshare/merlin 两份,koolshare 那份带走了写入优化,merlin 那份没有(是有意的,
# 但当时没人立刻发现)。这个脚本让"做没了"当场可见。
#
# 加断言的规矩:**只加你真的踩过、并且能说清失败场景的**。
# 每条都要在注释里写清楚:不满足会怎样。别把它变成风格检查器。

cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0

# have <说明> <文件> <grep模式>      —— 必须存在
# absent <说明> <文件> <grep模式>    —— 必须不存在
have(){
	if [ ! -f "$2" ]; then printf '  ?? %-52s 文件不存在: %s\n' "$1" "$2"; FAIL=$((FAIL+1)); return; fi
	if grep -q -- "$3" "$2"; then printf '  ok %-52s\n' "$1"; PASS=$((PASS+1))
	else printf '  ✗  %-52s %s 里找不到 /%s/\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); fi
}
absent(){
	if [ ! -f "$2" ]; then printf '  ?? %-52s 文件不存在: %s\n' "$1" "$2"; FAIL=$((FAIL+1)); return; fi
	if grep -q -- "$3" "$2"; then printf '  ✗  %-52s %s 里不该有 /%s/\n' "$1" "$2" "$3"; FAIL=$((FAIL+1))
	else printf '  ok %-52s\n' "$1"; PASS=$((PASS+1)); fi
}

SU=merlinclash/scripts/clash_selfupdate.sh
IK=merlinclash/install_koolshare.sh
IM=merlinclash/install_merlin.sh
ASP=merlinclash/webs/Module_merlinclash.asp
CSS=merlinclash/res/merlinclash.css

echo "── 安全:dbus/eval 注入面(两条线都适用)──"
# 没有 sane():外部字符串直接进 dbus → eval $(dbus export merlinclash_) 时以 root 执行
have   "外部值统一过 sane() 消毒"            "$SU" 'sane()'
# 这个键写了没人读,却是把 GitHub Release 正文送进 root eval 的通道
absent "不得写 merlinclash_selfupdate_note"  "$SU" 'dbus set merlinclash_selfupdate_note'

echo "── 自更新链路 ──"
# 少了它:解包出的 /tmp/merlinclash(27MB)常驻 tmpfs 直到重启
have   "失败/成功都清理 /tmp"                 "$SU" 'cleanup_tmp'
# 先落 21MB tarball 再解 24MB → tmpfs 峰值 45MB;流式只要 24MB
have   "流式下载解包(不落 tarball)"          "$SU" 'tar -xz -C /tmp'
# busybox 的 find 只有 -mtime DAYS,没有 -mmin;用 -mmin 写的新鲜度判断是哑弹,
# 不报错、永远不命中 → 缓存形同虚设、锁永不过期
have   "时间判断用 age_ok 而非 find -mmin"    "$SU" 'age_ok'
# 只认完整包:slim 增量包装完是残的,以后还得再下一次(已撤销,别加回来)
absent "不得重新引入 slim 增量包"             "$SU" 'slim'

echo "── 前端 ──"
# 点了更新后 onclick 被清空,失败/超时/登录过期三条终止分支若不复位,
# 按钮看着是活的、点了完全没反应,用户只能自己想到按 F5
have   "终止分支复位按钮 mc_su_rearm"          "$ASP" 'mc_su_rearm'

echo "── koolshare 线:写入优化 ──"
# 没有它:每次更新把 bin64(11M)+dashboard(13M)+rule_configs(1.6M)原样重写回 U 盘。
# 这块 eVtran U 盘已经因写入损坏过多次(见 router-ops/)
have   "sync_smart(改了才写)"                "$IK" 'sync_smart'
have   "dir_fp(目录指纹快路)"                "$IK" 'dir_fp'
# 预删除会架空上面两条:目标被清空,比对必然全部落空(1.2.2.8 踩过,日志显示"写入409/跳过0")
absent "不得在复制前 rm -rf dashboard"        "$IK" 'rm -rf /koolshare/merlinclash/dashboard'
absent "不得在复制前 rm -rf rule_configs"     "$IK" 'rm -rf /koolshare/merlinclash/rule_configs'

echo "── koolshare 线:CSS ──"
# 漏了 tfoot:代理设置卡片被劈成 337px/668px 两套布局,tfoot 四行一条分隔线都没有
have   "flex 行规则覆盖 tfoot"                 "$CSS" 'is(tbody,tfoot)'

echo "── AI 线 ──"
# watchdog=1 会走 perp(koolshare 私有),原版梅林没有 → 内核根本起不来
have   "梅林侧强制 watchdog_sw=0"              "$IM" 'merlinclash_set_watchdog_sw=0'
# 大文件常被搬去 /jffs/ksdata、原位留软链;busybox 的 cp 会把软链换成实体文件,
# 44M 的内核就又压回 200M 的 /jffs
have   "梅林侧解引用软链再写(readlink)"       "$IM" 'readlink'

echo "── 发版 ──"
V=$(tr -d ' \r\n' < merlinclash/version 2>/dev/null)
case "$V" in
	# install.sh 会剥掉字母再整数比较,带字母的版本号会让比较出错
	*.*.*.*) case "$V" in *[!0-9.]*) printf '  ✗  版本号含非数字: %s\n' "$V"; FAIL=$((FAIL+1));;
	                       *) printf '  ok %-52s %s\n' "版本号四段纯数字" "$V"; PASS=$((PASS+1));; esac ;;
	*) printf '  ✗  版本号不是四段: %s\n' "$V"; FAIL=$((FAIL+1)) ;;
esac

echo
if [ "$FAIL" -eq 0 ]; then
	echo "全部通过($PASS 条)"
else
	echo "通过 $PASS,失败 $FAIL —— 失败的每一条都对应一个真实踩过的坑,"
	echo "别直接改断言让它变绿,先确认那个坑是不是又回来了(理由见 COLLAB.md)。"
	exit 1
fi
