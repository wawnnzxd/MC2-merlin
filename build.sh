#!/bin/sh
# build.sh —— 打两个包:完整包 + 增量(slim)包
#
# 为什么要两个:
#   完整包 21MB,其中 24MB 解包内容里有 22MB 是 mihomo 二进制(bin64 11M)和
#   面板(dashboard 13M)。这两样逐版没变过 —— 2026-08-23 一下午发的 4 个 release,
#   包体积只差几 KB,而实际改动是 462 行 CSS/JS/shell。
#   每点一次「立即更新」就为了送 ~300KB 的改动走 21MB 流量、在 tmpfs 里解出 24MB、
#   再把那 22MB 一字不差地重写回 U 盘。所以再发一个只含改动面的瘦包,
#   clash_selfupdate.sh 优先下它(名字里带 slim),没有才回落完整包。
#
#   瘦包不能用于全新安装(没有内核)—— install.sh 的 slim_guard() 会拦。
#
# 用法: sh build.sh            → 按 merlinclash/version 的版本号打包
#       sh build.sh --full-only → 只打完整包(动了 bin64/dashboard/Geo/规则时用)
set -e
cd "$(dirname "$0")"

VER="$(tr -d ' \r\n' < merlinclash/version)"
[ -n "$VER" ] || { echo "读不到 merlinclash/version"; exit 1; }
case "$VER" in
	*.*.*.*) : ;;
	*) echo "版本号必须是四段纯数字(install.sh 会剥字母后整数比较),当前: $VER"; exit 1 ;;
esac

mkdir -p packages
find merlinclash -name '.DS_Store' -delete 2>/dev/null || true

FULL="packages/MC2_${VER}_ARM64.tar.gz"
SLIM="packages/MC2_${VER}_ARM64_slim.tar.gz"

echo "打完整包 $FULL ..."
COPYFILE_DISABLE=1 tar --no-xattrs -czf "$FULL" merlinclash

if [ "$1" != "--full-only" ]; then
	echo "打增量包 $SLIM ..."
	# 只带会改的那几样。清单在这里显式列出,不要写成"排除法" ——
	# 将来新增一个大目录时,排除法会把它悄悄塞进瘦包,白名单不会。
	COPYFILE_DISABLE=1 tar --no-xattrs -czf "$SLIM" \
		merlinclash/version \
		merlinclash/install.sh \
		merlinclash/uninstall.sh \
		merlinclash/scripts \
		merlinclash/webs \
		merlinclash/res \
		merlinclash/conf
fi

echo
ls -la packages/MC2_${VER}_* | awk '{printf "%-46s %8.2f MB\n", $NF, $5/1048576}'
echo
echo "发版:"
echo "  gh release create v${VER} packages/MC2_${VER}_ARM64*.tar.gz --title \"MC2 ${VER}\" --notes \"...\""
echo
echo "⚠️ Release 正文(--notes)不会再进 dbus 了(见 clash_selfupdate.sh 顶部说明),"
echo "   但仍建议别在里头写反引号 —— GitHub 页面上也更干净。"
