#!/bin/sh
# clash_selfupdate.sh —— MC2-merlin 自更新:查 GitHub Release → 对比版本 → 一键安装
#
# 为什么存在(2026-08-23):
#   MC2 自己没有版本检查;更新提醒全靠 koolshare 软件中心从 rogsoft.ddnsto.com 拉列表。
#   我们的定制版推在自己的 GitHub(wawnnzxd/MC2-merlin),软件中心永远不知道。
#   本脚本让插件页面自己检查自己的仓库,有新版就提示,点一下直接装。
#
# 用法(由前端经 /_api/ 调用,$1=请求ID 由 base.sh 接住,动作在 $2):
#   clash_selfupdate.sh <id> check     → 强制查一次(用户点按钮),回传 new:/latest:/error:
#   clash_selfupdate.sh <id> autocheck → 同上,但 30 分钟内复用缓存(页面自动检查用)
#   clash_selfupdate.sh <id> install   → 下载 → 校验 → install.sh → 恢复开关 + 重启内核
#   clash_selfupdate.sh <id> status    → 回传 merlinclash_selfupdate_status(页面轮询进度)
#
# ─────────────────────────────────────────────────────────────────────────────
# 🟥 本脚本只允许写 merlinclash_selfupdate_status 这一个 dbus 键,而且写进去的值
#    必须先过 sane()。原因:18 个 MC2 脚本(含 clash_config.sh:9,开机自启和总开关
#    都走它)会执行 `eval $(dbus export merlinclash_)`,而 `dbus export` 吐出的是
#    **零转义**的 `export KEY="值"`。往 merlinclash_ 命名空间里塞任何外部内容 =
#    把 root 命令执行权交出去。实测:
#        dbus set zz_x='note with $(id -u) inside'
#        eval $(dbus export zz_)      →  sh: eval: line 1: id: not found   ← 真的执行了
#    v1.2.2.5 曾把 GitHub Release 正文原样写进 merlinclash_selfupdate_note,
#    一条带反引号的发布说明就能在下次开机时以 root 执行。已删除该键。
#    (这也是 CLAUDE.md 致命坑#4 记的同一个坑,当时只堵了 eval 的读侧,没堵写侧。)
# ─────────────────────────────────────────────────────────────────────────────
#
# 认证:仓库私有时需 dbus set merlinclash_selfupdate_token=<github PAT>;公开仓库留空即可。
source /koolshare/scripts/base.sh
REPO="${merlinclash_selfupdate_repo:-wawnnzxd/MC2-merlin}"
TOKEN="$(dbus get merlinclash_selfupdate_token)"
API="https://api.github.com/repos/$REPO/releases/latest"
LOG=/tmp/upload/merlinclash_selfupdate.log        # 安装日志:失败时用户唯一的线索,只许追加
CHKLOG=/tmp/upload/merlinclash_selfcheck.log      # 检查日志:每次开页面都会重写,不能和上面共用
LOCK=/tmp/mc_selfupdate.lock
# 页面每次打开 3 秒后都会自动检查一次。GitHub 未认证 API 是 60 次/小时/IP,
# 家里几个人各开几次页面就可能被限流(限流返回 403,脚本会误报成"连不上")。
# 缓存放 /tmp(tmpfs):既省 API 配额,又不像 dbus 那样每次都写 NAND。
CACHE=/tmp/mc_lastcheck
CACHE_MIN=30
ACTION="$2"

# 版本号/标签只允许这些字符。任何要进 dbus 或进 shell 展开的外部字符串都过这里。
sane(){ echo "$1" | tr -cd 'A-Za-z0-9._:-' | cut -c1-64; }
set_status(){ dbus set merlinclash_selfupdate_status="$(sane "$1")"; }

cur_ver(){ cat /koolshare/merlinclash/version 2>/dev/null | tr -d ' \r\n'; }

# 装完/失败都要走这里。/tmp 是 tmpfs(占内存),解包出来的 /tmp/merlinclash 实测 27MB,
# 不删就一直占着 2GB 内存里的 27MB 直到重启 —— 这正是"bug 造成的资源占用"。
cleanup_tmp(){ rm -rf /tmp/mc_update.tar.gz /tmp/merlinclash >/dev/null 2>&1; }

fetch_latest(){
	# 输出: tag \t 下载URL \t asset API URL
	# 临时文件带 $$:页面轮询每 5 秒调一次 status,若与另一个标签页的 check 撞上,
	# 固定文件名会被对方删掉,check 于是误报"无法访问 GitHub"。
	JF="/tmp/mc_release.$$.json"
	# 不用 eval:TOKEN 来自 dbus,含引号会让 eval 语法炸掉,含 $() 则以 root 执行。
	# 改成条件分支传参,curl 自己处理引号,没有再解析一层的机会。
	if [ -n "$TOKEN" ]; then
		curl -s -m 25 -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "$API" > "$JF" 2>/dev/null
	else
		curl -s -m 25 -H "Accept: application/vnd.github+json" "$API" > "$JF" 2>/dev/null
	fi
	if [ ! -s "$JF" ] || ! grep -q '"tag_name"' "$JF"; then rm -f "$JF"; return 1; fi
	TAG=$(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' "$JF" | head -1)
	# 只认完整包。包必须始终是完整的:装完就该是能用的全套,不能留下"以后还得
	# 再下一次"的尾巴。省流量要靠更好的实现(流式解包 + install.sh 的内容比对写入),
	# 不是靠少发文件。
	DL=$(sed -n 's/.*"browser_download_url": *"\([^"]*\.tar\.gz\)".*/\1/p' "$JF" | head -1)
	# 私有仓库的 asset 必须走 API url + Accept: application/octet-stream(browser_download_url 会 404)。
	# 把 assets 数组按 },{ 拆行,只在**含所选包名的那一条**里取 url。
	ASSET_API=""
	if [ -n "$DL" ]; then
		ASSET_API=$(sed 's/},{/}\n{/g' "$JF" | grep -F "$(basename "$DL")" \
			| sed -n 's|.*"url": *"\(https://api\.github\.com/[^"]*releases/assets/[0-9]*\)".*|\1|p' | head -1)
	fi
	rm -f "$JF"
	printf '%s\t%s\t%s\n' "$TAG" "$DL" "$ASSET_API"
}

case "$ACTION" in
check|autocheck)
	# autocheck 来自页面自动触发:缓存还新鲜就直接用,不打 GitHub。
	# check 来自用户点按钮:永远查实时的 —— 用户点了就是想知道现在的情况。
	if [ "$ACTION" = "autocheck" ] && [ -n "$(find /tmp -maxdepth 1 -name mc_lastcheck -mmin -${CACHE_MIN} 2>/dev/null)" ]; then
		CACHED="$(cat $CACHE 2>/dev/null)"
		if [ -n "$CACHED" ]; then http_response "$CACHED"; exit 0; fi
	fi
	echo_date "检查 $REPO 最新版本..." > $CHKLOG
	R=$(fetch_latest) || { set_status "error:github-unreachable"; http_response "error:无法访问 api.github.com(代理未起?)"; exit 0; }
	TAG=$(echo "$R" | cut -f1)
	LATEST="$(sane "${TAG#v}")"; CUR="$(sane "$(cur_ver)")"
	# ⚠️ versioncmp 语义反直觉:`versioncmp A B` 在 **A 比 B 新时输出 -1**(实测 1.2.2.2 vs 1.2.2.1 → -1)。
	#    软件中心自己也是这么用的:versioncmp 在线版 本地版 → 判 -1 为有新版。别改成 1,会永远"已是最新"。
	CMP=$(/koolshare/bin/versioncmp "$LATEST" "$CUR" 2>/dev/null)
	# 安装正在进行时不要覆盖状态机:页面每次加载 3 秒后自动 check,而 status 是
	# 安装进度的唯一载体,被 check 写成 new/latest 会让轮询彻底看不懂。
	ST="$(dbus get merlinclash_selfupdate_status)"
	case "$ST" in
		downloading:*|installing:*|restarting:*) BUSY=1 ;;
		*) BUSY=0 ;;
	esac
	if [ "$CMP" = "-1" ]; then
		[ "$BUSY" = "0" ] && set_status "new"
		echo_date "发现新版本 $LATEST(当前 $CUR)" >> $CHKLOG
		echo "new:$LATEST" > $CACHE
		http_response "new:$LATEST"
	else
		[ "$BUSY" = "0" ] && set_status "latest"
		echo_date "已是最新($CUR)" >> $CHKLOG
		echo "latest:$CUR" > $CACHE
		http_response "latest:$CUR"
	fi
	;;
install)
	# 互斥:mkdir 是原子的。刷新页面会让「立即更新」按钮重新可点,不加锁就可能有
	# 两路安装共用 /tmp/mc_update.tar.gz 和 /tmp/merlinclash 互相拆台。
	# 锁超过 15 分钟视为上一轮崩了(子 shell 被 kill 就不会 rmdir),强行接管。
	# 没有这个兜底,一次异常就会让「立即更新」永久点不动,直到重启清空 /tmp。
	[ -n "$(find /tmp -maxdepth 1 -name mc_selfupdate.lock -mmin +15 2>/dev/null)" ] && rmdir "$LOCK" 2>/dev/null
	if ! mkdir "$LOCK" 2>/dev/null; then
		# 已经有一路在装:把真实进度回给前端,让它直接接着轮询,别显示 "already"
		http_response "$(dbus get merlinclash_selfupdate_status)"
		exit 0
	fi
	echo_date "开始自更新..." > $LOG
	R=$(fetch_latest) || {
		echo_date "❌ 获取 Release 失败" >> $LOG
		set_status "failed:github-unreachable"; rmdir "$LOCK" 2>/dev/null
		http_response "error:无法访问 api.github.com"; exit 0; }
	TAG=$(echo "$R" | cut -f1); DL=$(echo "$R" | cut -f2); ASSET_API=$(echo "$R" | cut -f3)
	LATEST="$(sane "${TAG#v}")"
	WAS_ON="$(dbus get merlinclash_enable)"
	set_status "downloading:$LATEST"
	# ★ 立即返回,不在前台等下载(前台等会让 /_api/ ajax 超时,页面误报"更新失败")。
	#   下载→校验→install.sh→恢复开关重启内核 全部塞进后台子 shell;页面轮询 status 看进度。
	http_response "installing:$LATEST"
	(
		trap '' HUP
		echo_date "目标版本 $LATEST,下载并解包中..." >> $LOG
		# 流式:curl 直接喂给 tar,不在 tmpfs 里落一份 21MB 的 tar.gz。
		# 原来是「先存 21MB 再解出 24MB」,峰值占内存 45MB;现在只有解包出来的 24MB。
		# /tmp 是 tmpfs —— 省下的就是实打实的 2GB 内存。
		# 管道里 $? 取的是最后一个命令(tar)的状态:输入被截断时 tar 必定非 0,
		# 所以这一条同时兼了"下载完整性校验",不用再单独 tar -tzf 把整包 gunzip 一遍。
		rm -rf /tmp/merlinclash
		if [ -n "$TOKEN" ] && [ -n "$ASSET_API" ]; then
			curl -sL -m 300 -H "Authorization: Bearer $TOKEN" -H "Accept: application/octet-stream" "$ASSET_API" | tar -xz -C /tmp
		else
			curl -sL -m 300 "$DL" | tar -xz -C /tmp
		fi
		rc=$?
		GOT="$(cat /tmp/merlinclash/version 2>/dev/null | tr -d ' \r\n')"
		if [ "$rc" != "0" ] || [ ! -f /tmp/merlinclash/install.sh ] || [ "$GOT" != "$LATEST" ]; then
			echo_date "❌ 下载或解包失败(tar rc=$rc,解出版本 '$GOT',期望 '$LATEST')" >> $LOG
			set_status "failed:fetch-rc$rc"; cleanup_tmp; rmdir "$LOCK" 2>/dev/null; exit 0
		fi
		echo_date "解包完成($(du -sk /tmp/merlinclash | cut -f1)KB),开始安装..." >> $LOG
		set_status "installing:$LATEST"
		sh /tmp/merlinclash/install.sh >> $LOG 2>&1
		rc=$?
		NOW="$(sane "$(cur_ver)")"
		if [ "$rc" = "0" ] && [ "$NOW" = "$LATEST" ]; then
			if [ "$WAS_ON" = "1" ]; then
				echo_date "文件更新完成,恢复开关并重启内核..." >> $LOG
				set_status "restarting:$LATEST"
				dbus set merlinclash_enable=1
				sh /koolshare/scripts/clash_config.sh restart restart >/dev/null 2>&1
			fi
			set_status "done:$LATEST"
			rm -f $CACHE
			echo_date "✅ 自更新完成:$LATEST" >> $LOG
		else
			# install.sh 已经跑过 `clash_config.sh stop stop`,里面 stop_config() 会把
			# merlinclash_enable 置 0。失败就停在这里的话,用户是"代理被关掉 + 一行红字",
			# 家里直接没代理。原来是开着的就把它拉回来,能救多少救多少。
			echo_date "❌ install.sh 退出码 $rc,当前版本 $NOW" >> $LOG
			if [ "$WAS_ON" = "1" ]; then
				echo_date "尝试用原有文件恢复代理..." >> $LOG
				dbus set merlinclash_enable=1
				sh /koolshare/scripts/clash_config.sh restart restart >/dev/null 2>&1
			fi
			set_status "failed:install-rc$rc-now$NOW"
		fi
		cleanup_tmp
		rmdir "$LOCK" 2>/dev/null
	) &
	;;
status)
	# 页面轮询安装进度:downloading:<v> → installing:<v> → restarting:<v> → done:<v> | failed:<原因>
	http_response "$(dbus get merlinclash_selfupdate_status)"
	;;
*)
	http_response "usage: check|autocheck|install|status"
	;;
esac
exit 0
