#!/bin/sh

### 基础环境 ###
export KSROOT=/koolshare
source $KSROOT/scripts/base.sh
eval $(dbus export merlinclash_)

alias echo_date='echo 【$(date +%Y年%m月%d日\ %X)】:'

# 路径
DNS_PATH="$KSROOT/merlinclash/yaml_dns"
BASIC_PATH="$KSROOT/merlinclash/yaml_basic"
TMP_FILE="/tmp/edityaml.txt"
LOG_FILE="/tmp/upload/dnsfile.log"

# 清空日志
rm -rf "$LOG_FILE"

# 2026-09-23 审计修复(B-X3):有 pipefail 就用(busybox 1.25.1 的 ash 支持),好让管道里任何一段
#   失败都算失败;先在子 shell 里探测,老 ash 不认也不会因为 set 报错把本脚本带走。
PIPEFAIL=""
( set -o pipefail ) 2>/dev/null && PIPEFAIL=1

### 工具函数 ###
# URL 解码（不追加多余换行）
# 2026-09-23 审计修复(B-X3):原来是 `sed 's/%\(..\)/\\x\1/g' | xargs -0 printf "%b"` ——
#   整段内容成了 printf 的**一个参数**。busybox xargs 单条命令行默认上限约 32KB(1.25.1 实测:
#   转义后超过就报 argument line too long,一个字节都不输出;就算放大 -s,单参数到 128KB 也会 E2BIG)。
#   而下游管道的返回值只看最后的 awk(恒 0),`> "$outfile"` 又已先把原文件截断 ⇒ 保存稍大的
#   配置段(DNS 母版带中文注释就够了)= 原文件被清空,页面照样提示「已保存」。
#   现在用 awk 流式解码,不经命令行参数、多大都行;语义与原来一致(+ → 空格,%XX → 字节)。
urldecode() {
    awk 'BEGIN { for (i = 0; i < 256; i++) hex[sprintf("%02X", i)] = i }
    {
        if (NR > 1) printf "\n"
        gsub(/\+/, " ")
        n = split($0, p, "%")
        printf "%s", p[1]
        for (k = 2; k <= n; k++) {
            h = toupper(substr(p[k], 1, 2))
            if (length(p[k]) >= 2 && (h in hex)) printf "%c%s", hex[h], substr(p[k], 3)
            else printf "%%%s", p[k]
        }
    }'
}

# 统一去掉 Windows 回车并删除所有“仅空白”的行
strip_blank_lines() {
    # sub(/\r$/,"") 去掉每行末尾的 \r；NF 为 0 则是空白行（含空格/Tab）
    awk '{ sub(/\r$/,""); if (NF) print }'
}

get_dbus_value() {
    dbus get "$1"
}

get_base64_bin() {
    if [ -f "/koolshare/bin/base64_decode" ]; then
        printf "%s" "/koolshare/bin/base64_decode"
    elif [ -f "/bin/base64" ]; then
        printf "%s" "/bin/base64"
    elif [ -f "/koolshare/bin/base64" ]; then
        printf "%s" "/koolshare/bin/base64"
    elif [ -f "/sbin/base64" ]; then
        printf "%s" "/sbin/base64"
    else
        echo_date "【错误】未找到 base64 解码工具，无法继续执行" >> "$LOG_FILE"
        echo_date "请参考 MerlinClash Wiki 解决办法" >> "$LOG_FILE"
        exit 1
    fi
}

clear_dbus_content() {
    dbus list merlinclash_yamledit_content_ | cut -d "=" -f 1 | while read -r key; do
        dbus remove "$key"
    done
}

write_yaml_file() {
    local tag="$1" outfile

    case "$tag" in
        redirhost) outfile="$DNS_PATH/redirhost.yaml" ;;
        fakeip)    outfile="$DNS_PATH/fakeip.yaml" ;;
        sniffer)   outfile="$BASIC_PATH/sniffer.yaml" ;;
        hosts)     outfile="$BASIC_PATH/hosts.yaml" ;;
        head)      outfile="$BASIC_PATH/head.yaml" ;;
        acl)       outfile="/koolshare/merlinclash/rule_custom/${merlinclash_set_yamlsel_start}_custom_rule.yaml" ;;
        iptblack)  outfile="$BASIC_PATH/ipsetproxyarround.yaml" ;;
        iptwhite)  outfile="$BASIC_PATH/ipsetproxy.yaml" ;;
        *) echo_date "【警告】未知的 tag: $tag" >> "$LOG_FILE"; return ;;
    esac

    # urldecode -> 去 CRLF + 删空行 -> 写入文件
    # 注意：错误追加到日志，不混入 YAML 文件
    # 2026-09-23 审计修复(B-X3):先写同目录的隐藏临时文件(`| cat >`:busybox cat 会检查写错误,
    #   写满返回非 0),整条管道都成功(pipefail)才替换原文件;任何一步失败原文件一个字节不动。
    #   以前直接 `> "$outfile"`:重定向先把原文件截断,解码一失败就只剩空文件。
    #   目标是软链时照旧写穿(cat >),不把软链换成实体文件。
    local tmp="${outfile%/*}/.${outfile##*/}.tmp.$$"
    if ! ( [ -n "$PIPEFAIL" ] && set -o pipefail
           urldecode < "$TMP_FILE" | strip_blank_lines | cat > "$tmp" ) 2>>"$LOG_FILE"; then
        rm -f "$tmp"
        echo_date "【错误】生成 $outfile 失败,原文件未改动" >> "$LOG_FILE"
        return 1
    fi
    if [ -L "$outfile" ]; then
        cat "$tmp" > "$outfile"
    else
        mv -f "$tmp" "$outfile"
    fi || { rm -f "$tmp"; echo_date "【错误】写入 $outfile 失败" >> "$LOG_FILE"; return 1; }
    rm -f "$tmp"
}

### 主逻辑 ###
main() {
    local count tag b64_bin wrote_ok

    count_0="$(get_dbus_value merlinclash_yamledit_content_0)"
    count="$(get_dbus_value merlinclash_yamledit_content_count)"
    tag="$(get_dbus_value merlinclash_yamledit_tag)"

    # 无数据则直接响应并退出
    if [ -z "$count" ] || [ "$count" -eq 0 ] >/dev/null 2>&1; then
        http_response "$1"
        exit 0
    fi
    # ipt绕行为空，删除文件yaml
    if [ "$count_0" == " " ] ; then
        if [ "$tag" == "iptwhite" ]; then
            rm -rf /koolshare/merlinclash/yaml_basic/ipsetproxy.yaml
        elif [ "$tag" == "iptblack" ]; then
            rm -rf /koolshare/merlinclash/yaml_basic/ipsetproxyarround.yaml
        elif [ "$tag" == "acl" ]; then
            rm -rf /koolshare/merlinclash/rule_custom/${merlinclash_set_yamlsel_start}_custom_rule.yaml
        fi
    fi
    # 聚合分片内容 + base64 解码到临时文件
    # 2026-09-23 审计修复(B-X3):分片不再拼进变量再 `printf "%s" "$content"` 喂给解码器 ——
    #   本机 busybox ash 没有内建 printf,外部 printf 的单个参数超过 128KB(MAX_ARG_STRLEN)
    #   exec 直接 E2BIG,大配置段保存失败。现在逐片 dbus get 直接流进解码器;tr 去掉换行
    #   (koolshare 原版 dbus get 每片末尾带换行,兼容层不带),解码器收到的字节与以前完全相同。
    #   解码结果经 `| cat >` 落盘(查写错误),管道任一段失败都走下面的错误分支。
    b64_bin="$(get_base64_bin)"
    if ! ( [ -n "$PIPEFAIL" ] && set -o pipefail
           i=0
           while [ "$i" -lt "$count" ]; do
               get_dbus_value merlinclash_yamledit_content_$i
               i=$((i+1))
           done | tr -d '\n' | "$b64_bin" -d | cat > "$TMP_FILE" ) 2>>"$LOG_FILE"; then
        echo_date "【错误】Base64 解码失败" >> "$LOG_FILE"
        rm -f "$TMP_FILE"
        http_response "error:Base64 解码失败,原配置未改动"
        exit 1
    fi

    wrote_ok=1
    if [ -s "$TMP_FILE" ]; then
        echo_date "中间文件已创建" >> "$LOG_FILE"
        echo_date "生成新文件: $tag" >> "$LOG_FILE"
        write_yaml_file "$tag" || wrote_ok=0
        rm -f "$TMP_FILE"
    fi
    if [ "$tag" == "acl" ]; then
        /bin/sh /koolshare/scripts/clash_saveacls.sh push push
    fi
    # 清理 dbus 临时键
    clear_dbus_content

    # 2026-09-23 审计修复(B-X3):写失败时回 "error:…"(与 clash_selfupdate.sh 的约定一致),
    #   前端可据此提示「没保存上」;成功照旧回 ID。详情在 /tmp/upload/dnsfile.log。
    if [ "$wrote_ok" = 1 ]; then
        http_response "$1"
    else
        http_response "error:写入配置文件失败,原文件未改动"
    fi
}

main "$@"
