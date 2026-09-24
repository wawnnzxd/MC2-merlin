#!/bin/sh
# MC2 双固件卸载分发器(见 install.sh 说明)
# ⚠️ 判据用拼接写法,理由同 install.sh:ks-fixpath 会把字面量 /koolshare 改成 /jffs/koolshare,
#    梅林上恒真 → 走错 koolshare 分支(2026-09-23 审计补充)。
KS_NATIVE="/kool""share"
D=$(cd "$(dirname "$0")"; pwd)
if [ -d "$KS_NATIVE" ]; then
	exec sh "$D/uninstall_koolshare.sh"
else
	exec sh "$D/uninstall_merlin.sh"
fi
