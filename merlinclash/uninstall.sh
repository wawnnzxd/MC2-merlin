#!/bin/sh
eval `dbus export merlinclash`
source /koolshare/scripts/base.sh


if [ "$merlinclash_enable" == "1" ];then
	echo 先关闭clash插件！
    sleep 1s
	exit 1
fi


find /koolshare/init.d/ -name "*clash*" | xargs rm -rf
rm -rf /koolshare/bin/clash
rm -rf /koolshare/bin/yq >/dev/null 2>&1
rm -rf /koolshare/bin/haveged >/dev/null 2>&1
rm -rf /tmp/upload/yamls.txt >/dev/null 2>&1
rm -rf /tmp/upload/clash_* >/dev/null 2>&1
rm -rf /tmp/upload/merlinclash*/ >/dev/null 2>&1
rm -rf /tmp/upload/dnsfile.log >/dev/null 2>&1
rm -rf /tmp/upload/proxygroups.txt >/dev/null 2>&1
rm -rf /tmp/upload/proxytype.txt >/dev/null 2>&1
rm -rf /tmp/upload/view.txt >/dev/null 2>&1

rm -rf /koolshare/res/icon-merlinclash.png >/dev/null 2>&1
rm -rf /koolshare/res/clash*/ >/dev/null 2>&1
rm -rf /koolshare/res/merlinclash.css >/dev/null 2>&1
rm -rf /koolshare/res/mc-tablednd.js >/dev/null 2>&1
rm -rf /koolshare/res/mc-menu.js >/dev/null 2>&1
rm -rf /koolshare/res/china*.ipset >/dev/null 2>&1
rm -rf /koolshare/res/lan*.ipset >/dev/null 2>&1
rm -rf /koolshare/res/ip*.ipset >/dev/null 2>&1
rm -rf /koolshare/res/mac*.ipset >/dev/null 2>&1
#
rm -rf /koolshare/merlinclash/GeoIP.dat >/dev/null 2>&1
rm -rf /koolshare/merlinclash/GeoSite.dat >/dev/null 2>&1
rm -rf /koolshare/merlinclash/Shanghai >/dev/null 2>&1
rm -rf /koolshare/merlinclash/yaml_bak/*
rm -rf /koolshare/merlinclash/yaml_use/*
rm -rf /koolshare/merlinclash/yaml_basic/*
rm -rf /koolshare/merlinclash/yaml_dns/*
rm -rf /koolshare/merlinclash/rule_configs/*
rm -rf /koolshare/merlinclash/conf/*
rm -rf /koolshare/merlinclash/dashboard/*
rm -rf /koolshare/scripts/clash*.sh
rm -rf /koolshare/webs/Module_merlinclash.asp
rm -rf /koolshare/merlinclash
rm -rf /koolshare/scripts/merlinclash_install.sh
rm -rf /koolshare/scripts/uninstall_merlinclash.sh
rm -rf /jffs/scripts/dnsmasq.postconf >/dev/null 2>&1
rm -rf /jffs/scripts/dnsmasq-sdn.postconf >/dev/null 2>&1

#清除相关skipd数据

datas=`dbus list merlinclash_ | cut -d "=" -f 1`
for data in $datas
do
	dbus remove $data
done
dbus remove softcenter_module_merlinclash_install
dbus remove softcenter_module_merlinclash_version
