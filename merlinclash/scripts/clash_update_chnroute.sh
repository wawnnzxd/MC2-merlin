#!/bin/sh

export KSROOT=/koolshare
source $KSROOT/scripts/clash_base.sh
eval $(dbus export merlinclash_)
alias echo_date='echo 【$(date +%Y年%m月%d日\ %X)】:'
LOG_FILE=/tmp/upload/merlinclash_log.txt
LOCK_FILE=/var/lock/chnroute_update.lock

# 通用下载与校验函数
# 参数: $1:版本(4/6), $2:远程地址, $3:本地目标路径, $4:临时路径, $5:旧路由缓存路径
core_update_chnroute(){
    local VER="$1"
    local URL="$2"
    local DEST="$3"
    local TEMP="$4"
    local IPSET_CACHE="$5"
    local NAME="【ipv${VER}】"

    echo_date "$NAME 开始下载更新..."
    
    # 1. 下载文件 (使用你之前的 download 函数，自带 CDN/原站重试逻辑)
    # 这里的 $UA 变量通常在 clash_base.sh 中定义
    download "$UA" "$URL" "$TEMP"

    if [ "$?" -ne 0 ] || [ ! -s "$TEMP" ]; then
        echo_date "$NAME 下载失败。请检查网络或尝试开启【代理路由自身访问】！"
        rm -rf "$TEMP"
        return 1
    fi

    # 2. 检查合法性 (检查 payload 关键字)
    if [ -z "$(grep "payload" "$TEMP")" ]; then
        echo_date "$NAME 文件内容错误（缺少 payload），请稍后重试。"
        rm -rf "$TEMP"
        return 1
    fi

    # 3. 检查是否有更新 (cmp 比较)
    if [ -f "$DEST" ] && cmp -s "$TEMP" "$DEST"; then
        echo_date "$NAME 已经是最新版本，无需替换。"
        rm -rf "$TEMP"
    else
        echo_date "$NAME 检测到更新，正在替换旧版本..."
        mv -f "$TEMP" "$DEST"
        [ -f "$IPSET_CACHE" ] && rm -rf "$IPSET_CACHE"
        echo_date "$NAME 更新成功！下次重启 Clash 生效。"
    fi
    return 0
}

set_lock(){
    mkdir -p "${LOCK_FILE%/*}"
    exec 233>"$LOCK_FILE"
    if ! flock -n 233; then
        # 2026-09-23 审计修复(D-X6 ②):以前这里记一句就 unset_lock(解锁 + 删锁文件)然后照跑,
        #   等于没锁 —— 两次更新并发写 ChinaIP*.yaml、互删缓存。现在:回包、留一句话就退出。
        #   不清日志、不写结束标记 BBABBBBC:正在跑的那次(本脚本 case 25,或 mc2_chnupdate.sh 的
        #   IPv6 段 —— 它拿的是同一把锁)结束时会写,页面照样等得到;这里抢先写会让前端提前判「完成」。
        #   (「已经在运行」这几个字新界面的 chnVerdict 靠它判「本次未执行」,别改。)
        echo_date "大陆白名单规则更新已经在运行，请稍候再试！（本次未执行）" >> $LOG_FILE
        http_response "$1"
        exit 0
    fi
}

unset_lock(){
    flock -u 233
    # 2026-09-23 审计修复(D-X6 ②):锁文件不再删。删了之后后来者 open 的是新 inode,
    #   和还攥着旧 inode 的进程互不相斥(mc2_chnupdate.sh 也 open 这个路径拿锁)。/var/lock 在 tmpfs,留着无害。
}

case $2 in
25)
    set_lock "$1"
    echo "" > $LOG_FILE
    http_response "$1"
    
    echo_date "开始下载大陆IP白名单..." >> $LOG_FILE

    # 更新 IPv4
    # 2026-09-23 审计修复(D-X6 ① / initnet-12):装了 N98chnupdate.sh 的机器(武汉)IPv4 交给它 force ——
    #   APNIC ∪ 17mon 并集 + 条数/抽查校验 + 同盘原子替换 + ipset swap,立即生效、不用重启内核;
    #   res/china_ip_route.ipset 只剩 N98 一个写入者(更新时间也由它在校验通过后写)。
    #   以前这里下 fernvenue 单源、再 rm 掉 res/china_ip_route.ipset,下次 apply 就把并集整份换成单源,
    #   要等下次 nat-start 的 N98 heal 才恢复。与新界面 mc2_chnupdate.sh 同一套判断(看 N98 在不在),
    #   所以无论从哪条路进来(旧界面按钮、新界面找不到 mc2_chnupdate.sh 时的回退、mc2_chnupdate.sh
    #   自己的无 N98 分支)结果都一样。没有 N98 的机器(koolshare 固件 / 杭州)照旧走下面的单源更新。
    N98="$KSROOT/init.d/N98chnupdate.sh"
    if [ -f "$N98" ]; then
        echo_date "IPv4 大陆白名单交给 N98chnupdate(APNIC ∪ 17mon 并集,校验通过后原子替换、立即生效,无需重启 Clash)..." >> $LOG_FILE
        sh "$N98" force >> $LOG_FILE 2>&1
        rc=$?
        [ "$rc" = 0 ] || echo_date "❌ IPv4 更新失败(N98 退出码 $rc),现网集合与数据文件保持原样,原因见上面的 [FAIL] 行" >> $LOG_FILE
    else
    core_update_chnroute "4" \
        "https://testingcf.jsdelivr.net/gh/fernvenue/chn-cidr-list@master/ipv4.yaml" \
        "/koolshare/merlinclash/yaml_basic/ChinaIP.yaml" \
        "/tmp/ChinaIP.list" \
        "/koolshare/res/china_ip_route.ipset" >> $LOG_FILE
    fi

    # 更新 IPv6
    core_update_chnroute "6" \
        "https://testingcf.jsdelivr.net/gh/fernvenue/chn-cidr-list@master/ipv6.yaml" \
        "/koolshare/merlinclash/yaml_basic/ChinaIPv6.yaml" \
        "/tmp/ChinaIPv6.list" \
        "/koolshare/res/china_ip_route6.ipset" >> $LOG_FILE

    echo BBABBBBC >> $LOG_FILE
    unset_lock
    ;;
esac