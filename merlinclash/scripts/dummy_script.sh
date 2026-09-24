#!/bin/sh
# dummy_script.sh —— koolshare 固件自带的"空动作"脚本(原版梅林缺件,补上)
#
# MC2 前端大量用它做「只把 fields 写进 dbus、不执行任何动作」的通道:
# DNS 方案切换、chnroute 开关、访问控制名单、高级设置……全走这条路。
# ksapid-handler 的流程是「验脚本存在 → 写 fields → 执行脚本」,
# 脚本不存在时**fields 也不会写**,于是所有这类保存都静默失败 ——
# dbus 纹丝不动,前端还显示"已保存"(2026-08-25 真机踩到,
# 顺手把前端 post() 也改成了检查 response.error)。
#
# 它唯一的职责就是回一个响应,让前端知道请求被受理了。

KSROOT="${KSROOT:-/jffs/koolshare}"
[ -d /koolshare ] && KSROOT=/koolshare
. "$KSROOT/scripts/base.sh"

http_response "$1"
exit 0
