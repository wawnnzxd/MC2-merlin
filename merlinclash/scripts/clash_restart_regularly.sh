#!/bin/sh

source /koolshare/scripts/base.sh
alias echo_date='echo 【$(date +%Y年%m月%d日\ %X)】:'
LOG_FILE=/tmp/upload/merlinclash_log.txt

eval `dbus export merlinclash_`

get(){
	a=$(echo $(dbus get $1))
	a=$(echo $(dbus get $1))
	echo $a
}
mscr=$(get merlinclash_select_clash_restart)
mscrm=$(get merlinclash_select_clash_restart_minute)
mscrh=$(get merlinclash_select_clash_restart_hour)
mscrw=$(get merlinclash_select_clash_restart_week)
mscrd=$(get merlinclash_select_clash_restart_day)
mscrm_2=$(get merlinclash_select_clash_restart_minute_2)
# 2026-09-23 审计修复(K-X3):busybox crond 遇到越界值不是「不执行」—— ParseField 的 failsafe
#   会把整个字段置满,syslog 再报一句 parse error。旧界面「周日」存的是 7 ⇒ 每周重启变成每天重启;
#   旧界面分钟下拉以前给到 60 ⇒ 那个小时里每分钟整套重启一次。cron 的周日是 0,分钟只有 0~59。
#   (clash_config.sh 的 write_clash_restart_cron_job 每次 apply 都会重新注册,那边做了同样的收口。)
[ "$mscrw" = "7" ] && mscrw=0
case "$mscrm" in [0-9]|[1-5][0-9]) ;; *) mscrm=0 ;; esac
remove_clash_restart_regularly(){
	if [ -n "$(cru l|grep clash_restart)" ]; then
		
		sed -i '/clash_restart/d' /var/spool/cron/crontabs/* >/dev/null 2>&1
	fi
}
start_clash_restart_regularly_day(){
	remove_clash_restart_regularly
	cru a clash_restart ${mscrm} ${mscrh}" * * * /bin/sh /koolshare/scripts/clash_restart_update.sh"
}
start_clash_restart_regularly_week(){
	remove_clash_restart_regularly
	cru a clash_restart ${mscrm} ${mscrh}" * * "${mscrw}" /bin/sh /koolshare/scripts/clash_restart_update.sh"
}
start_clash_restart_regularly_month(){
	remove_clash_restart_regularly
	cru a clash_restart ${mscrm} ${mscrh} ${mscrd}" * * /bin/sh /koolshare/scripts/clash_restart_update.sh"

}
start_clash_restart_regularly_mhour(){
	remove_clash_restart_regularly
	# 25 保留(两个界面都有这一项),但要知道:cron 的 */25 按整点对齐,实际是每小时 :00/:25/:50,
	#   间隔 25/25/10 分钟;其余几档都能整除 60 / 24,是真正的等间隔。
	if [ "$mscrm_2" == "2" ] || [ "$mscrm_2" == "5" ] || [ "$mscrm_2" == "10" ] || [ "$mscrm_2" == "15" ] || [ "$mscrm_2" == "20" ] || [ "$mscrm_2" == "25" ] || [ "$mscrm_2" == "30" ]; then
		cru a clash_restart "*/"${mscrm_2}" * * * * /bin/sh /koolshare/scripts/clash_restart_update.sh"
	fi
	if [ "$mscrm_2" == "1" ] || [ "$mscrm_2" == "3" ] || [ "$mscrm_2" == "6" ] || [ "$mscrm_2" == "12" ]; then
		cru a clash_restart "0 */"${mscrm_2} "* * * /bin/sh /koolshare/scripts/clash_restart_update.sh"
	fi
}

case $mscr in
1)
	remove_clash_restart_regularly
	http_response "close"
	;;
2)
	start_clash_restart_regularly_day
	http_response "open"
	;;
3)
	start_clash_restart_regularly_week
	http_response "open"
	;;
4)
	start_clash_restart_regularly_month
	http_response "open"
	;;
5)
	start_clash_restart_regularly_mhour
	http_response "open"
	;;
*)
	remove_clash_restart_regularly
	http_response "close"
	;;
esac
