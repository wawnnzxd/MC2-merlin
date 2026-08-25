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
# 内核与面板在 .gitignore 里(不进 git),fresh clone 会缺 —— 打包前验完整性:
#   内核:从上一版 release 包取,或 MetaCubeX/mihomo 官方 release 下载 arm64 版
#   面板:gh release download --repo wawnnzxd/zashboard --pattern dist.zip
[ -f merlinclash/bin64/clash ] || { echo "缺 merlinclash/bin64/clash(内核,44M,见 README)"; exit 1; }
[ -f merlinclash/dashboard/zashboard/index.html ] || { echo "缺面板 dashboard/zashboard/(fork dist,见 patches/03)"; exit 1; }
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
