#!/bin/sh
# build.sh —— 打完整包。
#
# 只打一个包,而且必须是完整的:装完就该是能用的全套,不留"以后还得再下一次"的尾巴。
# 更新的开销靠实现去省,不靠少发文件:
#   · clash_selfupdate.sh 用 `curl | tar -xz` 流式解包,tmpfs 峰值 45MB → 24MB;
#   · install.sh 的 cp_smart() 先比大小再比内容,内容没变的文件不写回 U 盘
#     (bin64 11MB + dashboard 13MB 在多数版本之间一个字节都没变)。
set -e
cd "$(dirname "$0")"
VER="$(tr -d ' \r\n' < merlinclash/version)"
case "$VER" in
	*.*.*.*) : ;;
	*) echo "版本号必须四段纯数字(install.sh 会剥字母后整数比较),当前: $VER"; exit 1 ;;
esac
mkdir -p packages
find merlinclash -name '.DS_Store' -delete 2>/dev/null || true
OUT="packages/MC2_${VER}_ARM64.tar.gz"
COPYFILE_DISABLE=1 tar --no-xattrs -czf "$OUT" merlinclash
ls -la "$OUT" | awk '{printf "%s  %.2f MB\n", $NF, $5/1048576}'
echo "gh release create v${VER} $OUT --title \"MC2 ${VER}\" --notes \"...\""
