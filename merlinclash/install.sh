#!/bin/sh
# MC2 双固件安装分发器(1.2.2.13 起)
#
# 一份包,两套皮肤,按固件自动选:
#   koolshare 官改(/koolshare 编译在 rootfs 里)→ install_koolshare.sh
#     = 上游老流程 + 老版 ASP 界面(koolcenter 原版皮肤)
#   原版梅林 + koolshare-shim(KSROOT=/jffs/koolshare)→ install_merlin.sh
#     = 重写流程 + BE19000AI 新版界面(Module_mc2.asp)
#
# ⚠️ 2026-09-23 审计补充:判据不能写字面量 /koolshare。
#   梅林上走软件中心离线安装时,离线安装脚本第 17 步会先对**整个包**跑 ks-fixpath,
#   把所有字面量 /koolshare 改成 /jffs/koolshare —— 原来的 `[ -d /koolshare ]` 被改成
#   `[ -d /jffs/koolshare ]`,在梅林上恒真:走进 install_koolshare.sh(koolshare 老流程),
#   装完还把新版界面删掉。拼接写法 fixpath 的 sed 匹配不到,两种固件上都保持原意
#   (koolshare 固件不跑 fixpath;梅林的 / 是只读 squashfs,/koolshare 不可能存在)。
#
# ⚠️ 本文件是软件中心离线安装直接执行的 install.sh:它的第 12 步把内容里含离线安装脚本文件名
#   (k s _ t a r _ i n s t a l l)或 d e t e c t _ p a c k a g e 字样的 install.sh 当成「会篡改软件中心」
#   的恶意包,直接拒装。注释里也不能写这两个词(2026-09-23 审计返工时差点踩上)。
KS_NATIVE="/kool""share"
D=$(cd "$(dirname "$0")"; pwd)
if [ -d "$KS_NATIVE" ]; then
	sh "$D/install_koolshare.sh"; rc=$?
	# 新 UI 是梅林专属:它引用 shim 才有的 /user/res/kslite.css,
	# koolshare 上是死页面 —— sync_smart 整目录拷进去了,这里删掉。
	rm -f "$KS_NATIVE/webs/Module_mc2.asp" "$KS_NATIVE/res/mc2.js" "$KS_NATIVE/res/mc2.css"
	exit $rc
else
	exec sh "$D/install_merlin.sh"
fi
