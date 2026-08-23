#! /bin/sh

source /koolshare/scripts/base.sh
eval $(dbus export merlinclash)
#alias echo_date='echo 【$(TZ=UTC-8 date -R +%Y年%m月%d日\ %X)】:'
alias echo_date='echo 【$(date +%Y年%m月%d日\ %X)】:'
MODEL=
DIR=$(cd $(dirname $0); pwd)
module=${DIR##*/}
LINUX_VER=$(uname -r|awk -F"." '{print $1$2}')
builddate=$(uname -v | awk '{print $NF}')
mcinstall=$(dbus get softcenter_module_merlinclash_install)
Geosite_PATH="/koolshare/merlinclash/GeoSite.dat" 
GeoIP_PATH="/koolshare/merlinclash/GeoIP.dat"
get_model(){
	local ODMPID=$(nvram get odmpid)
	local PRODUCTID=$(nvram get productid)
	if [ -n "${ODMPID}" ];then
		MODEL="${ODMPID}"
	else
		MODEL="${PRODUCTID}"
	fi
}

get_fw_type() {
	local KS_TAG=$(nvram get extendno|grep -Eo "kool.+")
	if [ -d "/koolshare" ];then
		if [ -n "${KS_TAG}" ];then
			FW_TYPE_CODE="2"
			FW_TYPE_NAME="${KS_TAG}官改固件"
		else
			FW_TYPE_CODE="4"
			FW_TYPE_NAME="koolshare梅林改版固件"
		fi
	else
		if [ "$(uname -o|grep Merlin)" ];then
			FW_TYPE_CODE="3"
			FW_TYPE_NAME="梅林原版固件"
		else
			FW_TYPE_CODE="1"
			FW_TYPE_NAME="华硕官方固件"
		fi
	fi
}

fuck_bug(){
	local LINUX_FUCK=$(uname -r|awk -F"." '{print $1$2$3}')
	local FIRMVER_VER=$(nvram get buildno|awk -F"." '{print $1$2}')
	if [ "${LINUX_FUCK}" -eq "419294" ]; then
			echo_date "注意：检测到您的Linux内核版本为：4.19.294！"
			echo_date "如果您的固件版本为梅改102.3~102.7，官改102.39256以下"
			echo_date "--- Magic Catling可能会运行不稳定 ---"
	fi

	mc2_install=$(dbus get softcenter_module_merlinclash_title)
	mc2_version=$(dbus get merlinclash_version | sed 's/[A-Za-z]//g' | sed 's/\.[^.]*$//' | tr -d '.')
	mc2_version=${mc2_version:-68}		
	if [ "${mcinstall}" == "1" ] && [ "$mc2_install" != "Magic Catling2" -o "$mc2_version" -lt 100 ]; then
		echo_date "已安装旧版本的Merlin Clash，本插件与之冲突！"
		echo_date "请卸载后，再次安装Magic Catling 2！"
		exit_install 2
	fi
}
platform_test(){
	# 带koolshare文件夹，有httpdb和skipdb的固件位支持固件
	if [ -d "/koolshare" -a -x "/koolshare/bin/httpdb" -a -x "/usr/bin/skipd" ];then
		echo_date "机型：${MODEL} ${FW_TYPE_NAME} 符合安装要求，开始安装插件！"
	else
		exit_install 1
	fi
	# 继续判断各个固件的内核和架构
	if [ -d "/tmp/merlinclash/bin32" ]; then
        PKG_ARCH="arm32"
    elif [ -d "/tmp/merlinclash/bin64" ]; then
    	PKG_ARCH="arm64"
    else
        echo_date "安装包不完整，请重新下载！"	
    fi
	local ROT_ARCH=$(uname -m)
	local KEL_VERS=$(uname -r)
	# ARM64
	if [ "${PKG_ARCH}" = "arm64" ]; then
		case "${LINUX_VER}" in
			"41"|"419")
				if [ "${ROT_ARCH}" = "aarch64" ]; then
					echo_date "内核：${KEL_VERS}，架构：${ROT_ARCH}，安装Magic Catling2_${PKG_ARCH}！"
				else
					echo_date "内核：${KEL_VERS}，架构：${ROT_ARCH}，Magic Catling2_${PKG_ARCH}不适用于该架构！退出！"
					exit_install 1
				fi
				;;
			"44")
				echo_date "内核：${KEL_VERS}，架构：${ROT_ARCH}，Magic Catling2_${PKG_ARCH}不适用于该内核版本！"
				echo_date "建议使用Magic Catling2_arm32！"
				exit_install 2
				;;
			"54")
				case "${MODEL}" in
					"ZenWiFi_BD4")
            echo_date "内核：${KEL_VERS}，架构：${ROT_ARCH}，Magic Catling2_${PKG_ARCH}不适用于该内核版本！"
						echo_date "建议使用Magic Catling2_arm32！"	
						exit_install 2
						;;
					"TUF_6500")
						echo_date "内核：${KEL_VERS}，架构：${ROT_ARCH}，安装Magic Catling2_${PKG_ARCH}！"	
						;;
					"TX-AX6000"|"TUF-AX4200Q"|"TUF-AX4200"|"RT-AX57_Go"|"GS7"|"ZenWiFi_BT8P"|"GS7_Air")
						echo_date "内核：${KEL_VERS}，架构：${ROT_ARCH}，安装Magic Catling2_${PKG_ARCH}！"	
						;;
					*)
						echo_date "原因：暂不支持你的路由器型号：${MODEL}，请联系插件作者！"		
						exit_install 1
						;;
				esac
				;;
			*)
				echo_date "内核：${KEL_VERS}，架构：${ROT_ARCH}，Magic Catling2_${PKG_ARCH}不适用于该内核版本！"
				exit_install 1
				;;
		esac
	fi

	# ARM32
	if [ "${PKG_ARCH}" = "arm32" ]; then
		case "${LINUX_VER}" in
			"44")
				echo_date "内核：${KEL_VERS}，架构：${ROT_ARCH}，安装Magic Catling2_${PKG_ARCH}！"
				;;
			"41"|"419")
				if [ "${ROT_ARCH}" = "aarch64" ]; then
                        echo_date "内核：${KEL_VERS}，架构：${ROT_ARCH}，Magic Catling2_${PKG_ARCH}不适用于该内核版本！"
						echo_date "建议使用Magic Catling2_arm64！"	
					exit_install 2
				else
					echo_date "内核：${KEL_VERS}，架构：${ROT_ARCH}，安装Magic Catling2_${PKG_ARCH}！"
				fi
				;;
			"54")
				case "${MODEL}" in
					"ZenWiFi_BD4")
						echo_date "内核：${KEL_VERS}，架构：${ROT_ARCH}，安装Magic Catling2_${PKG_ARCH}！"
						;;
					"TUF_6500")
                        echo_date "内核：${KEL_VERS}，架构：${ROT_ARCH}，Magic Catling2_${PKG_ARCH}不适用于该内核版本！"
						echo_date "建议使用Magic Catling2_arm64！"	
						exit_install 2
						;;
					"TX-AX6000"|"TUF-AX4200Q"|"TUF-AX4200"|"RT-AX57_Go"|"GS7"|"ZenWiFi_BT8P"|"GS7_Air")
                        echo_date "内核：${KEL_VERS}，架构：${ROT_ARCH}，Magic Catling2_${PKG_ARCH}不适用于该内核版本！"
						echo_date "建议使用Magic Catling2_arm64！"	
						exit_install 2
						;;
					*)
						echo_date "原因：暂不支持你的路由器型号：${MODEL}，请联系插件作者！"
						exit_install 1
						;;
				esac
				;;
			*)
				echo_date "内核：${KEL_VERS}，架构：${ROT_ARCH}，Magic Catling2_${PKG_ARCH}不适用于该内核版本！"
				exit_install 1
				;;
		esac
	fi
}

set_skin(){
  # new nethod: use nvram value to set skin
	local UI_TYPE=ASUSWRT
	local SC_SKIN=$(nvram get sc_skin)
	local TS_FLAG=$(grep -o "2ED9C3" /www/css/difference.css 2>/dev/null|head -n1)
	local ROG_FLAG=$(cat /www/form_style.css|grep -A1 ".tab_NW:hover{"|grep "background"|sed 's/,//g'|grep -o "2071044")
	local TUF_FLAG=$(cat /www/form_style.css|grep -A1 ".tab_NW:hover{"|grep "background"|sed 's/,//g'|grep -o "D0982C")
	local WRT_FLAG=$(cat /www/form_style.css|grep -A1 ".tab_NW:hover{"|grep "background"|sed 's/,//g'|grep -o "4F5B5F")
	if [ -n "${TS_FLAG}" ];then
		UI_TYPE="TS"
	else
		if [ -n "${TUF_FLAG}" ];then
			UI_TYPE="TUF"
		fi
		if [ -n "${ROG_FLAG}" ];then
			UI_TYPE="ROG"
		fi
		if [ -n "${WRT_FLAG}" ];then
			UI_TYPE="ASUSWRT"
		fi
	fi
	if [ -z "${SC_SKIN}" -o "${SC_SKIN}" != "${UI_TYPE}" ];then
		nvram set sc_skin="${UI_TYPE}"
		nvram commit
	fi
}

exit_install(){
	local state=$1
	case $state in
		1)
			echo_date "Magic Catling2项目地址：https://t.me/merlinclashcat"
			echo_date "退出安装！"
			rm -rf /tmp/${module}* >/dev/null 2>&1
			exit 1
			;;
		2)
			echo_date "Magic Catling2 升级/安装失败！！！"
			echo_date "退出安装！"
			rm -rf /tmp/${module}* >/dev/null 2>&1
			exit 2
			;;
		0|*)
			rm -rf /tmp/${module}* >/dev/null 2>&1
			exit 0
			;;
	esac
}
dbus_nset(){
	# set key when value not exist
	local ret=$(dbus get $1)
	if [ -z "${ret}" ];then
		dbus set $1=$2
	fi
}

install_now(){
	mkdir -p /koolshare/merlinclash
	mkdir -p /tmp/upload
	sleep 2s

	# 先关闭clash
	if [ "${merlinclash_enable}" == "1" ];then
		if [ -f "/koolshare/scripts/clash_config.sh" ] ;then
			echo_date "正在关闭Magic Catling插件，保证文件更新成功"
			sleep 1
			sh /koolshare/scripts/clash_config.sh stop stop >/dev/null 2>&1
			sleep 1
		else	
			echo_date ""
			echo_date "======================  ！！异常退出！！ ==========================="
			echo_date ""
			echo_date "         +++++++++++++++++++++++++++++++++++++++++++++++++"
			echo_date "         +    请先关闭Magic Catling插件，保证文件更新成功!     +" 
			echo_date "         +++++++++++++++++++++++++++++++++++++++++++++++++"
			exit_install 2
		fi

    fi

	echo_date "清理旧文件"
	rm -rf /koolshare/merlinclash/shanghai >/dev/null 2>&1
	rm -rf /koolshare/merlinclash/version
	rm -rf /koolshare/merlinclash/dashboard/
	rm -rf /koolshare/bin/clash
	rm -rf /koolshare/bin/yq
	rm -rf /koolshare/res/icon-merlinclash.png
	rm -rf /koolshare/res/clash*
	rm -rf /koolshare/res/merlinclash.css
	rm -rf /koolshare/res/mc-tablednd.js
	rm -rf /koolshare/res/mc-menu.js
	rm -rf /koolshare/res/china*.ipset >/dev/null 2>&1
	rm -rf /koolshare/res/lan*.ipset >/dev/null 2>&1
	rm -rf /koolshare/res/ip*.ipset >/dev/null 2>&1
	rm -rf /koolshare/res/mac*.ipset >/dev/null 2>&1
	rm -rf /tmp/upload/clash_* >/dev/null 2>&1
	find /koolshare/init.d/ -name "*merlinclash*" | xargs rm -rf
	rm -rf /koolshare/merlinclash/rule_configs
	rm -rf /koolshare/merlinclash/conf
	rm -rf /koolshare/webs/Module_merlinclash*
	rm -rf /koolshare/scripts/clash*

	local SPACE_GEO=$(df | grep -w "/jffs" | awk '{print $4}')
	if [ "$SPACE_GEO" -gt "20000" ];then
		echo_date "当前jffs分区剩余空间足够，保留Geo数据库文件！"
	else
		echo_date "当前jffs分区剩余空间紧张，为保证升级顺利"
		echo_date "删除Geo数据库文件，有需要的请升级成功后重新下载！"
		rm -rf /koolshare/merlinclash/GeoSite.dat >/dev/null 2>&1
		rm -rf /koolshare/merlinclash/GeoIP.dat >/dev/null 2>&1
	fi

	# 检测储存空间是否足够
	echo_date "检测jffs分区剩余空间..."
	SPACE_AVAL=$(df | grep -w "/jffs" | awk '{print $4}')
	SPACE_NEED=$(du -s /tmp/merlinclash | awk '{print $1}')
	if [ "$SPACE_AVAL" -gt "$SPACE_NEED" ];then
		  echo_date "当前jffs分区剩余${SPACE_AVAL}KB, 插件安装大概需要${SPACE_NEED}KB，空间满足，继续安装！"
	else
		if [ "${mcinstall}" == "1" ]; then
			echo_date ""
			echo_date "======================  ！！异常退出！！ ==========================="
			echo_date ""
			echo_date "当前jffs分区剩余${SPACE_AVAL}KB, 插件安装大概需要${SPACE_NEED}KB，空间不足！"
			echo_date "         ++++++++++++++++++++++++++++++++++++++++++++++++++++++"
			echo_date "         +           注意：安装脚本已删除插件部分重要文件           +" 
			echo_date "         +   请清理JFFS空间重新安装，或者卸载Magic Catling2全新安装   +" 
			echo_date "         +        ！！！否则无法正常启动Magic Catling2！！！         +" 
			echo_date "         ++++++++++++++++++++++++++++++++++++++++++++++++++++++"
			sleep 5
			exit_install 2
		else
			echo_date "当前jffs分区剩余${SPACE_AVAL}KB, 插件安装大概需要${SPACE_NEED}KB，空间不足！"
			exit_install 2
		fi
	fi

	# 开始安装
	cd /koolshare/merlinclash && mkdir -p dashboard && cd
	cd /koolshare/merlinclash && mkdir -p yaml_basic && cd
	cd /koolshare/merlinclash && mkdir -p yaml_dns && cd
	cd /koolshare/merlinclash && mkdir -p yaml_bak && cd
	cd /koolshare/merlinclash && mkdir -p yaml_use && cd
	cd /koolshare/merlinclash && mkdir -p rule_configs && cd
	cd /koolshare/merlinclash && mkdir -p conf && cd

	echo_date "开始复制文件..."	
	cd /tmp

		#检查是否有jq
	if [ -f /usr/bin/jq ];then
		rm -rf /tmp/merlinclash/bin32/jq >/dev/null 2>&1
    	rm -rf /tmp/merlinclash/bin64/jq >/dev/null 2>&1
		if [ ! -L /koolshare/bin/jq ];then
			ln -sf /usr/bin/jq /koolshare/bin/jq
		fi
	fi
	
	if [ "${PKG_ARCH}" = "arm32" ]; then
		#非armv7内核删除haveged
		if [ "${LINUX_VER}" != "44" ]; then
			rm -rf /tmp/merlinclash/bin32/haveged
		fi
		cp -rf /tmp/merlinclash/bin32/* /koolshare/bin/
	else
		cp -rf /tmp/merlinclash/bin64/* /koolshare/bin/
	fi
	
	cp -rf /tmp/merlinclash/conf/* /koolshare/merlinclash/conf/
	cp -rf /tmp/merlinclash/clash/Shanghai /koolshare/merlinclash/
	cp -rf /tmp/merlinclash/version /koolshare/merlinclash/

	if [ "${mcinstall}" == "1" ]; then
		echo_date "----------------------------------------------------------------"
		echo_date "检测到早期版本的Magic Catling，开始进行升级安装..."
		echo_date "若升级后使用异常，请完全卸载插件，重新进行全新安装！！！"
		echo_date "----------------------------------------------------------------"

		rm -rf /tmp/merlinclash/yaml_basic/hosts.yaml
		rm -rf /tmp/merlinclash/yaml_basic/head.yaml

	fi
	cp -rf /tmp/merlinclash/yaml_basic/* /koolshare/merlinclash/yaml_basic/
	
	if [ "${mcinstall}" != "1" ]; then
		cp -rf /tmp/merlinclash/yaml_dns/* /koolshare/merlinclash/yaml_dns/
	fi
	  cp -rf /tmp/merlinclash/dashboard/* /koolshare/merlinclash/dashboard/
	  cp -rf /tmp/merlinclash/rule_configs/* /koolshare/merlinclash/rule_configs/
	#判断是否需要覆盖GeoSite  
	geo_size=$(ls -l "$Geosite_PATH" 2>/dev/null | awk '{print $5}')
	geoip_size=$(ls -l "$GeoIP_PATH" 2>/dev/null | awk '{print $5}')
	if [ -f "$Geosite_PATH" ] && [ "$geo_size" -gt 1000000 ]; then
		echo_date "已经存在GeoSite.dat文件，略过"
	else
		cp -rf /tmp/merlinclash/clash/GeoSite.dat /koolshare/merlinclash/
	fi
	if [ -f "$GeoIP_PATH" ] && [ "$geoip_size" -gt 1000000 ]; then
		echo_date "已经存在GeoIP.dat文件，略过"
	else
		cp -rf /tmp/merlinclash/clash/GeoIP.dat /koolshare/merlinclash/
	fi

	echo_date "复制相关脚本文件..."	
	cp -rf /tmp/merlinclash/scripts/* /koolshare/scripts/
	cp -rf /tmp/merlinclash/install.sh /koolshare/scripts/merlinclash_install.sh
	cp -rf /tmp/merlinclash/uninstall.sh /koolshare/scripts/uninstall_merlinclash.sh

	echo_date "复制相关网页文件..."	
	cp -rf /tmp/merlinclash/webs/* /koolshare/webs/
	cp -rf /tmp/merlinclash/res/* /koolshare/res/

	echo_date "为新文件赋权..."	
	chmod 755 /koolshare/bin/clash
	chmod 755 /koolshare/bin/yq
	chmod 755 /koolshare/bin/jq >/dev/null 2>&1	
	chmod 755 /koolshare/bin/haveged >/dev/null 2>&1
	chmod 755 /koolshare/merlinclash/yaml_basic/*
	chmod 755 /koolshare/merlinclash/yaml_dns/*
	chmod 755 /koolshare/merlinclash/rule_configs/*
	chmod 755 /koolshare/merlinclash/conf/*
	chmod 755 /koolshare/merlinclash/*
	chmod 755 /koolshare/scripts/clash*


	echo_date "创建自启脚本软链接！"
	ln -sf /koolshare/scripts/clash_config.sh /koolshare/init.d/S150merlinclash.sh
	ln -sf /koolshare/scripts/clash_config.sh /koolshare/init.d/N150merlinclash.sh

	echo_date "数据初始化"
	dbus_nset merlinclash_set_mixport_sw "0"
	dbus_nset merlinclash_ipt_closeproxy_sw "0"
	dbus_nset merlinclash_sub_useragent "bWlob21vLzEuMTkuMjA="
	dbus_nset merlinclash_set_logcheck_val "40"
	dbus_nset merlinclash_dns_sniffer_sw "1"
	dbus_nset merlinclash_sub_links " "
	dbus_nset merlinclash_dns_cleardns_sw "1"
	dbus_nset merlinclash_ipt_tproxy_type "closed"
	dbus_nset merlinclash_ipt_ipv6_sw "0"
	dbus_nset merlinclash_dns_proxydns_sw "1"
	dbus_nset merlinclash_dns_dnshijack_sw "1"
    #判断是否需要开启队列请求
	if [ "${builddate}" -lt "2025" ]; then
		dbus_nset merlinclash_set_queue_sw "1"
	else
		dbus_nset merlinclash_set_queue_sw "0"
	fi
	#判断是否开启大陆绕行IP
	if [ "${LINUX_VER}" -le "41" ] || [ "${LINUX_VER}" -eq "44" ]; then
		dbus_nset merlinclash_set_chnroute_sw "1"
	else
		dbus_nset merlinclash_set_chnroute_sw "0"
	fi
	#提取默认密码
	secret=$(yq eval ".secret" "/koolshare/merlinclash/yaml_basic/head.yaml" 2>/dev/null)
	dbus_nset merlinclash_set_dashboard_password "$secret"
	dbus set merlinclash_linuxver="$LINUX_VER"
	#设置版本号
	CUR_VERSION=$(cat /koolshare/merlinclash/version)
	if [ "${PKG_ARCH}" = "arm32" ]; then
		dbus set merlinclash_version="$CUR_VERSION.A32"
	else
		dbus set merlinclash_version="$CUR_VERSION.A64"
	fi
	dbus set softcenter_module_merlinclash_install="1"
	dbus set softcenter_module_merlinclash_version="$CUR_VERSION"
	dbus set softcenter_module_merlinclash_title="Magic Catling2"
	dbus set softcenter_module_merlinclash_description="Magic Catling2:一个基于规则的代理程序，支持多种协议~" 
	#设置内核版本
	local ret=$(env -i PATH=${PATH} /koolshare/bin/clash -v 2>/dev/null | head -n 1)
	local clashTmpV1=$(echo "$ret" | cut -d " " -f2)
	local clashTmpV2=$(echo "$ret" | cut -d " " -f3)
	if [ "$clashTmpV1" = "Meta" ];then
		merlinclash_binary_ver_tmp="Mihomo $clashTmpV2"; 
	else
		merlinclash_binary_ver_tmp=$clashTmpV1
	fi

	if [ -n "$merlinclash_binary_ver_tmp" ]; then
		mcv="$merlinclash_binary_ver_tmp"		
	else
		mcv="null"
	fi
	dbus set merlinclash_binary_ver="$mcv"

	echo_date "Magic Catling2插件安装成功！"
	#yaml不为空则复制文件 然后生成yamls.txt
	dir=/koolshare/merlinclash/yaml_bak
	a=$(ls $dir | wc -l)
	if [ $a -gt 0 ]; then
		cp -rf /koolshare/merlinclash/yaml_bak/*.yaml  /koolshare/merlinclash/yaml_use/ >/dev/null 2>&1
	fi

	#生成新的txt文件
	rm -rf /koolshare/merlinclash/yaml_bak/yamls.txt >/dev/null 2>&1
	echo_date "初始化yaml文件列表"
	find /koolshare/merlinclash/yaml_bak -maxdepth 1 -name "*.yaml" |sed 's#.*/##' |sed '/^$/d' | awk -F'.' '{print $1}' > /koolshare/merlinclash/yaml_bak/yamls.txt
	#创建软链接
	ln -sf /koolshare/merlinclash/yaml_bak/yamls.txt /tmp/upload/yamls.txt
	
	echo_date "初始化配置文件处理完成"

	# intall different UI
	set_skin

}
install(){
	get_model
	get_fw_type
	platform_test
	fuck_bug
	install_now
}

install