#!/bin/sh
# MC2 双固件卸载分发器(见 install.sh 说明)
D=$(cd "$(dirname "$0")"; pwd)
if [ -d /koolshare ]; then
	exec sh "$D/uninstall_koolshare.sh"
else
	exec sh "$D/uninstall_merlin.sh"
fi
