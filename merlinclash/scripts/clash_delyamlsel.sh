#!/bin/sh

export KSROOT=/koolshare
source $KSROOT/scripts/base.sh
source /koolshare/scripts/clash_base.sh
eval $(dbus export merlinclash_)
alias echo_date='echo 【$(date +%Y年%m月%d日\ %X)】:'
LOG_FILE=/tmp/upload/merlinclash_log.txt
LOCK_FILE=/tmp/yaml_online_del.lock


start_online_del(){
    rm -rf $LOG_FILE
    echo_date ======================== 删除YAM配置 ======================== >> $LOG_FILE
    echo_date "📌定位yaml文件" >> $LOG_FILE

    #delpath1=/koolshare/merlinclash
    delpath1=/koolshare/merlinclash/yaml_use
    delpath2=/koolshare/merlinclash/yaml_bak
    rulepath=/koolshare/merlinclash/rule_bak
    markpath=/koolshare/merlinclash/mark
    marktmp=/tmp/clash/mark
    yamlname=$(get merlinclash_set_yamlsel_edit)

    rm -rf $delpath1/$yamlname.yaml >/dev/null 2>&1
    rm -rf $delpath2/$yamlname.yaml >/dev/null 2>&1
    rm -rf $delpath2/$yamlname >/dev/null 2>&1
    rm -rf $delpath2/${yamlname}.dlinks >/dev/null 2>&1
    rm -rf $rulepath/${yamlname}_rules.yaml >/dev/null 2>&1
    rm -rf $rulepath/${yamlname}_custom_rule.yaml >/dev/null 2>&1
    rm -rf $markpath/${yamlname}.txt >/dev/null 2>&1
    rm -rf $marktmp/clash_web_save_${yamlname}.txt >/dev/null 2>&1

    echo_date "🟠删除yaml文件" >> $LOG_FILE

    echo_date "🟠重建yaml文件列表" >> $LOG_FILE
    rm -rf $delpath2/yamls.txt >/dev/null 2>&1
    rm /tmp/upload/yamls.txt >/dev/null 2>&1
    find $delpath2 -maxdepth 1 -name "*.yaml" |sed 's#.*/##' |sed '/^$/d' | awk -F'.' '{print $1}' >> $delpath2/yamls.txt
    #创建软链接
    ln -sf $delpath2/yamls.txt /tmp/upload/yamls.txt
    #
    dbus remove merlinclash_${yamlname}
    
    echo_date "✅配置文件删除完毕" >>"$LOG_FILE"
    echo_date ======================== 删除YAM配置 ======================== >> $LOG_FILE
}
case $2 in
0)
    set_lock
	echo "" > $LOG_FILE
	http_response "$1"
	start_online_del >> $LOG_FILE
	echo BBABBBBC >> $LOG_FILE
	unset_lock
	;;
esac
