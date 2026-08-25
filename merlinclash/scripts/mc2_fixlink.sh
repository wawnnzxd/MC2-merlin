#!/bin/sh
# mc2_fixlink.sh —— Geo 更新后把大文件归位 ksdata 并重建软链(幂等)
#
# 病根:GeoIP/GeoSite 平时放 /jffs/ksdata(eMMC 大分区),/jffs/koolshare 下只留
# 软链省空间(jffs 才 200M)。但上游 clash_update_ipdb.sh"替换数据库文件"用 mv
# 直接覆盖 —— 软链被换成实体,新文件落回 jffs,ksdata 那份成孤儿
# (2026-08-25 实测:更新一次后软链变 -rw- 实体)。上游脚本不改,
# 由前端在更新完成回调里调本脚本收拾:实体 → 搬去 ksdata → 重建软链。
KSROOT="${KSROOT:-/jffs/koolshare}"
[ -d /koolshare ] && KSROOT=/koolshare
. "$KSROOT/scripts/base.sh"
D=/jffs/ksdata/merlinclash
[ -d "$D" ] || { http_response "$1"; exit 0; }   # 无 ksdata(如真koolshare固件)则无事可做
for f in GeoIP.dat GeoSite.dat; do
	S="$KSROOT/merlinclash/$f"
	[ -f "$S" ] && [ ! -L "$S" ] || continue      # 只处理"实体文件"状态
	mv -f "$S" "$D/$f" && ln -s "$D/$f" "$S" \
		&& logger -t mc2-fixlink "$f 已归位 ksdata 并重建软链"
done
http_response "$1"
exit 0
