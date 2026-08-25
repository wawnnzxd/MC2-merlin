#!/bin/sh
# MC2 双固件安装分发器(1.2.2.13 起)
#
# 一份包,两套皮肤,按固件自动选:
#   koolshare 官改(/koolshare 编译在 rootfs 里)→ install_koolshare.sh
#     = 上游老流程 + 老版 ASP 界面(koolcenter 原版皮肤)
#   原版梅林 + koolshare-shim(KSROOT=/jffs/koolshare)→ install_merlin.sh
#     = 重写流程 + BE19000AI 新版界面(Module_mc2.asp)
D=$(cd "$(dirname "$0")"; pwd)
if [ -d /koolshare ]; then
	sh "$D/install_koolshare.sh"; rc=$?
	# 新 UI 是梅林专属:它引用 shim 才有的 /user/res/kslite.css,
	# koolshare 上是死页面 —— sync_smart 整目录拷进去了,这里删掉。
	rm -f /koolshare/webs/Module_mc2.asp /koolshare/res/mc2.js /koolshare/res/mc2.css
	exit $rc
else
	exec sh "$D/install_merlin.sh"
fi
