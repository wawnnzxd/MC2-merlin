#!/bin/sh
# mc2_fixlink.sh —— Geo 更新后把大文件归位 ksdata 并重建软链(幂等)
#   (2026-08-26 koolshare 整体迁到 p11 后已无事可做,只在 /jffs/ksdata 仍是独立挂载点时生效)
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
# ⚠️ 2026-09-23 审计修复 mc2ui-37:08-26 起 p11 直接挂在 /jffs/koolshare(零软链),/jffs/ksdata
#    不再是挂载点,而是 200M 小 /jffs 上的普通路径。这时"搬去 ksdata"= 把 Geo 库从 16G 的 p11
#    搬回 /jffs,语义正好反了(有人照旧文档手工建了这个目录就会中招)。只在它真是独立挂载点时才动手。
mount 2>/dev/null | grep -q " /jffs/ksdata " || { http_response "$1"; exit 0; }
for f in GeoIP.dat GeoSite.dat; do
	S="$KSROOT/merlinclash/$f"
	[ -f "$S" ] && [ ! -L "$S" ] || continue      # 只处理"实体文件"状态
	mv -f "$S" "$D/$f" && ln -s "$D/$f" "$S" \
		&& logger -t mc2-fixlink "$f 已归位 ksdata 并重建软链"
done
http_response "$1"
exit 0
