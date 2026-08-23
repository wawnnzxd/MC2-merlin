#!/bin/sh
# clash_selfupdate.sh —— MC2-merlin 自更新:查 GitHub Release → 对比版本 → 一键安装
#
# 为什么存在(2026-08-23):
#   MC2 自己没有版本检查;更新提醒全靠 koolshare 软件中心从 rogsoft.ddnsto.com 拉列表。
#   我们的定制版推在自己的 GitHub(wawnnzxd/MC2-merlin),软件中心永远不知道。
#   本脚本让插件页面自己检查自己的仓库,有新版就提示,点一下直接装。
#
# 用法(由前端经 /_api/ 调用,$1=请求ID 由 base.sh 接住):
#   clash_selfupdate.sh <id> check     → 写 merlinclash_selfupdate_* 几个 dbus 键,前端读
#   clash_selfupdate.sh <id> install   → 下载 Release 里的 tar.gz,校验,调 install.sh;装完自动恢复开关+重启内核
#   clash_selfupdate.sh <id> status    → 回传 merlinclash_selfupdate_status(页面轮询安装进度)
#
# 认证:仓库私有时需 dbus set merlinclash_selfupdate_token=<github PAT>;公开仓库留空即可。
source /koolshare/scripts/base.sh
REPO="${merlinclash_selfupdate_repo:-wawnnzxd/MC2-merlin}"
TOKEN="$(dbus get merlinclash_selfupdate_token)"
API="https://api.github.com/repos/$REPO/releases/latest"
LOG=/tmp/upload/merlinclash_selfupdate.log
ACTION="$2"

AUTH=""
[ -n "$TOKEN" ] && AUTH="-H \"Authorization: Bearer $TOKEN\""

cur_ver(){ cat /koolshare/merlinclash/version 2>/dev/null | tr -d ' \r\n'; }

fetch_latest(){
	# 输出: tag \t 下载URL \t asset API URL \t 发布说明(单行)
	eval curl -s -m 25 $AUTH -H '"Accept: application/vnd.github+json"' "$API" > /tmp/mc_release.json 2>/dev/null
	[ -s /tmp/mc_release.json ] || return 1
	grep -q '"tag_name"' /tmp/mc_release.json || return 1
	TAG=$(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' /tmp/mc_release.json | head -1)
	# 私有仓库的 asset 必须走 API url + Accept: application/octet-stream,browser_download_url 会 404
	ASSET_API=$(grep -oE '"url": *"https://api.github.com/repos/[^"]+/releases/assets/[0-9]+"' /tmp/mc_release.json | head -1 | sed 's/.*"url": *"//;s/"$//')
	DL=$(sed -n 's/.*"browser_download_url": *"\([^"]*\.tar\.gz\)".*/\1/p' /tmp/mc_release.json | head -1)
	NOTE=$(sed -n 's/.*"body": *"\([^"]*\)".*/\1/p' /tmp/mc_release.json | head -1 | sed 's/\\r\\n/ /g;s/\\n/ /g' | cut -c1-300)
	printf '%s\t%s\t%s\t%s\n' "$TAG" "$DL" "$ASSET_API" "$NOTE"
}

case "$ACTION" in
check)
	echo_date "检查 $REPO 最新版本..." > $LOG
	R=$(fetch_latest) || { dbus set merlinclash_selfupdate_status="error:无法访问 api.github.com(代理未起?)"; http_response "error"; exit 0; }
	TAG=$(echo "$R" | cut -f1); DL=$(echo "$R" | cut -f2); NOTE=$(echo "$R" | cut -f4)
	LATEST="${TAG#v}"; CUR=$(cur_ver)
	dbus set merlinclash_selfupdate_latest="$LATEST"
	dbus set merlinclash_selfupdate_current="$CUR"
	dbus set merlinclash_selfupdate_note="$NOTE"
	dbus set merlinclash_selfupdate_checked="$(date '+%Y-%m-%d %H:%M')"
	# ⚠️ versioncmp 语义反直觉:`versioncmp A B` 在 **A 比 B 新时输出 -1**(实测 1.2.2.2 vs 1.2.2.1 → -1)。
	#    软件中心自己也是这么用的:versioncmp 在线版 本地版 → 判 -1 为有新版。别改成 1,会永远"已是最新"。
	CMP=$(/koolshare/bin/versioncmp "$LATEST" "$CUR" 2>/dev/null)
	if [ "$CMP" = "-1" ]; then
		dbus set merlinclash_selfupdate_status="new"
		echo_date "发现新版本 $LATEST(当前 $CUR)" >> $LOG
		http_response "new:$LATEST"
	else
		dbus set merlinclash_selfupdate_status="latest"
		echo_date "已是最新($CUR)" >> $LOG
		http_response "latest:$CUR"
	fi
	;;
install)
	echo_date "开始自更新..." > $LOG
	R=$(fetch_latest) || { echo_date "❌ 获取 Release 失败" >> $LOG; http_response "error"; exit 0; }
	TAG=$(echo "$R" | cut -f1); DL=$(echo "$R" | cut -f2); ASSET_API=$(echo "$R" | cut -f3)
	LATEST="${TAG#v}"
	echo_date "目标版本 $LATEST,下载中..." >> $LOG
	rm -f /tmp/mc_update.tar.gz
	if [ -n "$TOKEN" ] && [ -n "$ASSET_API" ]; then
		curl -sL -m 300 -H "Authorization: Bearer $TOKEN" -H "Accept: application/octet-stream" -o /tmp/mc_update.tar.gz "$ASSET_API"
	else
		curl -sL -m 300 -o /tmp/mc_update.tar.gz "$DL"
	fi
	SZ=$(wc -c < /tmp/mc_update.tar.gz 2>/dev/null || echo 0)
	if [ "$SZ" -lt 1000000 ]; then
		echo_date "❌ 下载失败或文件异常($SZ 字节)" >> $LOG; http_response "error"; exit 0
	fi
	if ! tar -tzf /tmp/mc_update.tar.gz >/dev/null 2>&1; then
		echo_date "❌ 压缩包损坏" >> $LOG; rm -f /tmp/mc_update.tar.gz; http_response "error"; exit 0
	fi
	echo_date "下载完成($((SZ/1024/1024))MB),校验通过,开始安装..." >> $LOG
	WAS_ON="$(dbus get merlinclash_enable)"
	dbus set merlinclash_selfupdate_status="installing:$LATEST"
	http_response "installing:$LATEST"
	# 交给原版 install.sh(它会 clash_config.sh stop stop → stop_config 把 merlinclash_enable 置 0 → 复制文件 → 建软链)。
	# 后台跑、脱离本请求;装完后若原本是开着的,自动恢复开关并重启内核(两个参数 restart restart,见 HANDOFF 坑表)。
	# 子 shell 体在 fork 前已整体解析完,install.sh 随后覆盖本脚本文件也不影响它。
	(
		trap '' HUP
		rm -rf /tmp/merlinclash && cd /tmp && tar -xzf /tmp/mc_update.tar.gz && sh /tmp/merlinclash/install.sh >> $LOG 2>&1
		rc=$?
		NOW="$(cat /koolshare/merlinclash/version 2>/dev/null | tr -d ' \r\n')"
		if [ "$rc" = "0" ] && [ "$NOW" = "$LATEST" ]; then
			if [ "$WAS_ON" = "1" ]; then
				echo_date "文件更新完成,恢复开关并重启内核..." >> $LOG
				dbus set merlinclash_selfupdate_status="restarting:$LATEST"
				dbus set merlinclash_enable=1
				sh /koolshare/scripts/clash_config.sh restart restart >/dev/null 2>&1
			fi
			dbus set merlinclash_selfupdate_status="done:$LATEST"
			dbus set merlinclash_selfupdate_current="$LATEST"
			echo_date "✅ 自更新完成:$LATEST" >> $LOG
		else
			dbus set merlinclash_selfupdate_status="failed:install.sh rc=$rc 当前版本 $NOW"
			echo_date "❌ install.sh 退出码 $rc,当前版本 $NOW,请看日志" >> $LOG
		fi
		rm -f /tmp/mc_update.tar.gz
	) &
	;;
status)
	# 页面轮询安装进度:installing:<v> → restarting:<v> → done:<v> | failed:<原因>
	http_response "$(dbus get merlinclash_selfupdate_status)"
	;;
*)
	http_response "usage: check|install|status"
	;;
esac
rm -f /tmp/mc_release.json
exit 0
