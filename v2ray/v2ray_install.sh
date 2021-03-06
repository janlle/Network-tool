#!/usr/bin/bash

# If not specify, default meaning of return value:
# 0: Success
# 1: System error
# 2: Application error
# 3: Network error

#--------- Colors Code ---------
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;36m"

#--------- script constant ---------
ISA="64"
OS_TYPE="unknown"
OS_FULL_NAME=""
PROTOCOL=""
PASSWORD=$(openssl rand -base64 8)
USERNAME=$(openssl rand -hex 4)
SOURCE_FILE="/tmp/v2ray/v2ray-linux-${ISA}.zip"
LOG_DIR="/var/log/v2ray"
COMMAND="/usr/local/bin/v2ray"
CONFIG_FILE="/etc/v2ray/config.json"
SERVICE_FILE="/etc/systemd/system/v2ray.service"
PORT=$(shuf -i10000-65535 -n1)
UUID=$(cat /proc/sys/kernel/random/uuid)
SYSTEMCTL_CMD=$(command -v systemctl 2>/dev/null)
SERVICE_CMD=$(command -v service 2>/dev/null)


print() {
    echo -e "$1${@:2}\033[0m"
}

clear

# Check run with root .
[[ $(id -u) != 0 ]] && print ${RED} "This script only supports run with the root ." && exit 1


# Check system ISA .
sys_arch(){
    ARCH=$(uname -m)
    if [[ "$ARCH" == "i686" ]] || [[ "$ARCH" == "i386" ]]; then
        ISA="32"
    elif [[ "$ARCH" == *"armv7"* ]] || [[ "$ARCH" == "armv6l" ]]; then
        ISA="arm"
    elif [[ "$ARCH" == *"armv8"* ]] || [[ "$ARCH" == "aarch64" ]]; then
        ISA="arm64"
    elif [[ "$ARCH" == *"mips64le"* ]]; then
        ISA="mips64le"
    elif [[ "$ARCH" == *"mips64"* ]]; then
        ISA="mips64"
    elif [[ "$ARCH" == *"mipsle"* ]]; then
        ISA="mipsle"
    elif [[ "$ARCH" == *"mips"* ]]; then
        ISA="mips"
    elif [[ "$ARCH" == *"s390x"* ]]; then
        ISA="s390x"
    elif [[ "$ARCH" == "ppc64le" ]]; then
        ISA="ppc64le"
    elif [[ "$ARCH" == "ppc64" ]]; then
        ISA="ppc64"
    fi
    return 0
}

# Check machine type .

# CentOS yum dnf
if [[ -f "/etc/redhat-release" ]];then
    OS_TYPE="CentOS" && OS_FULL_NAME=$(cat /etc/redhat-release)
# Debian apt
elif [[ -f "/etc/debian_version" ]];then
    OS_TYPE="Debian" && OS_FULL_NAME=$(cat /etc/debian_version)
# Ubuntu apt
elif [[ -f "/etc/lsb-release" ]];then
    OS_TYPE="Ubuntu" && OS_FULL_NAME=$(head -1 /etc/lsb-release)
# Fedora yum dnf
elif [[ -f "/etc/fedora-release" ]];then
    OS_TYPE="Fedora" && OS_FULL_NAME=$(/etc/fedora-release)
fi

if [[ ${OS_TYPE} == "unknown" ]];then
    echo
    print ${RED} "This script not support your machine" && echo && exit 1
fi


# Check network
IP=$(curl --connect-timeout 1 -s https://ifconfig.me/)
[[ -z ${IP} ]] && ip=$(curl -s https://api.ip.sb/ip)
[[ -z ${IP} ]] && ip=$(curl -s https://api.ipify.org)
[[ -z ${IP} ]] && ip=$(curl -s https://ip.seeip.org)
[[ -z ${IP} ]] && ip=$(curl -s https://ifconfig.co/ip)
[[ -z ${IP} ]] && ip=$(curl -s http://icanhazip.com)
if [[ ! ${IP} =~ ^([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]]
then
    echo
    print ${RED} "Your machine can't connect to the Internet" && echo && exit 3
fi

# Print machine information .
system_info() {
    echo
    echo "##############################################"
    echo "# An easy to install v2ray script            #"
    echo "# Source: https://github.com/v2ray/v2ray-core#"
    echo "# Author: Leone <exklin@gmail.com>           #"
    echo "# Support: CentOS_7+ Ubuntu Debian Fedora    #"
    echo "##############################################"
    echo
    echo
    print ${GREEN} "System type: ${OS_FULL_NAME}"
    echo
    print ${GREEN} "Kernel version: $(uname -r)"
    echo
    print ${GREEN} "ISA: ${OS_TYPE} $(uname -m)"
    echo
    print ${GREEN} "Ip: ${IP}"
    echo && echo
}

system_info

# Install require packages.
install_package() {
    for i in $@;do
        if [[ ! -x "$(command -v ${i})" ]];then
            if [[ "${OS_TYPE}" == "CentOS" || "${OS_TYPE}" == "Fedora" ]];then
                yum install -y ${i}
            elif [[ "${OS_TYPE}" == "Ubuntu" || "${OS_TYPE}" == "Debian" ]];then
                apt install -y ${i}
            fi
        fi
    done
}

install_package curl wget git unzip jq


# Async date
async_date() {
    yum install -y chrony && systemctl start chronyd && systemctl enable chronyd
#    cat >/etc/chrony.conf <<EOF
#        server 0.centos.pool.ntp.org iburst
#        server 1.centos.pool.ntp.org iburst
#        server 2.centos.pool.ntp.org iburst
#        server 3.centos.pool.ntp.org iburst
#    EOF
}

config_port() {
    while :;do
        PORT=$(shuf -i10000-65535 -n1)
        echo
        print ${GREEN} "Please enter ${1} port 10000 to 65535"
        echo
        read -p "$(print ${BLUE} "(Default: ${PORT}): ")" port
        [[ -z "${port}" ]] && break
        if [[ `echo "${port}*1" | bc` -eq 0 && ((${port}<10000)) && ((${port}>65535)) ]];then
            PORT=${port}
            break
        fi
    done
}

config_username() {
    while :;do
        USERNAME=$(openssl rand -hex 4)
        echo
        print ${GREEN} "Please enter ${1} username not less than 6 characters ."
        echo
        read -p "$(print ${BLUE} "(Default: ${USERNAME}): ")" username
        [[ -z "${username}" ]] && break
        if (($(echo ${USERNAME} | wc -c)>6 && $(echo ${USERNAME} | wc -c)<37));then
            USERNAME=${username}
            break
        fi
    done
}


config_password() {
    while :;do
        PASSWORD=$(openssl rand -base64 8)
        echo
        print ${GREEN} "Please enter ${1} password not less than 6 characters ."
        echo
        read -p "$(print ${BLUE} "(Default: ${PASSWORD}): ")" password
        [[ -z "${password}" ]] && break
        if (($(echo ${PASSWORD} | wc -c)>6 && $(echo ${PASSWORD} | wc -c)<37));then
            PASSWORD=${password}
            break
        fi
    done
}

config_protocol() {
    PROTOCOL=$1
    flag=0
    while [[ flag -eq 0 ]];do
        echo
		for ((i=1;i<$#;i++));do
		    print ${GREEN} "${i}.${!i}"
		    echo
        done
        print ${GREEN} "Please enter ${@:$#:1} protocol 1 to "$(( $#-1 ))
        echo
        read -p "$(print ${BLUE} "(Default: ${PROTOCOL}): ")" option
        [[ -z "${option}" ]] && option=1
        if [[ ${option} -gt 0 ]];then
            for ((i=1;i<$#;i++));do
                if [[ ${option} -eq ${i} ]];then
		            PROTOCOL=${!i}
		            flag=1
		            break
		        fi
            done
        fi
    done
}


download_v2ray() {
    rm -rf /tmp/v2ray && mkdir -p /tmp/v2ray
    LATEST_VERSION=$(curl -s https://api.github.com/repos/v2ray/v2ray-core/releases/latest | jq .tag_name)
    if [[ ! ${LATEST_VERSION} ]]; then
        print ${RED} "Got v2ray version failed please check your network and retry" && exit 3
    fi
    echo
    V2RAY_DOWNLOAD_LINK="https://github.com/v2ray/v2ray-core/releases/download/${LATEST_VERSION//\"/}/v2ray-linux-${ISA}.zip"
    if ! wget --no-check-certificate -q --show-progress -O ${SOURCE_FILE} ${V2RAY_DOWNLOAD_LINK}; then
		print ${RED} "Download failed please check your network and retry." && exit 3
	fi
}

install_v2ray_service() {
    if [[ -n "${SYSTEMCTL_CMD}" ]];then
        cp -f /tmp/v2ray/systemd/v2ray.service /etc/systemd/system/
        chmod +x /etc/systemd/system/v2ray.service
        systemctl enable v2ray && systemctl start v2ray
        return
    elif [[ -n "${SERVICE_CMD}" ]] && [[ ! -f "/etc/init.d/v2ray" ]]; then
        cp -f /tmp/v2ray/systemv/v2ray /etc/init.d/v2ray
        chmod +x /etc/init.d/v2ray
        update-rc.d v2ray defaults
    fi
}


install_v2ray() {
    if [[ -f /usr/bin/v2ray/v2ray || -f ${CONFIG_FILE} || -f /etc/systemd/system/v2ray.service ]]; then
        echo
		print ${RED} "You have installed v2ray. Please uninstall it first ." && echo && exit 1
	fi
    download_v2ray
    rm -rf /usr/bin/v2ray/* /etc/v2ray/config.json
    mkdir -p /usr/bin/v2ray/ /etc/v2ray/ /var/log/v2ray
    unzip /tmp/v2ray/v2ray-linux-${ISA}.zip -d /tmp/v2ray/ > /dev/null 2>&1
    cp -f /tmp/v2ray/v2ray /tmp/v2ray/v2ctl /usr/bin/v2ray/
    cp -f /tmp/v2ray/geoip.dat /tmp/v2ray/geosite.dat /usr/bin/v2ray/
    cp -f /tmp/v2ray/vpoint_vmess_freedom.json ${CONFIG_FILE}

	# Config port
	config_port "v2ray vmess protocol"
    echo
    # Config
    sed -i "s/10086/${PORT}/g" "${CONFIG_FILE}"
    sed -i "s/23ad6b10-8d1a-40f7-8ad0-e3e35cd38297/${UUID}/g" "${CONFIG_FILE}"

    # Install service and start
    install_v2ray_service


	# Print install config info
	echo
    print ${YELLOW} "V2Ray port: ${PORT}"
    echo
    print ${YELLOW} "Ip: ${IP}"
    echo
	print ${YELLOW} "UUID: ${UUID}"
    echo
	print ${YELLOW} "ExtraID: $(jq .inbounds[0].settings.clients[0].alterId ${CONFIG_FILE})"
    echo
    print ${YELLOW} "Level: $(jq .inbounds[0].settings.clients[0].level ${CONFIG_FILE})"
    echo
    print ${YELLOW} "Protocol: VMess"
    echo
    print ${YELLOW} "Install v2ary successful"
    echo
}


uninstall_v2ray() {
    if [[ -f "/etc/systemd/system/v2ray.service" ]];then
        echo
        systemctl disable v2ray && systemctl stop v2ray && rm -f /etc/systemd/system/v2ray.service
    fi

    if [[ -d /usr/bin/v2ray ]]; then
		rm -rf /usr/bin/v2ray
	fi

    if [[ -d /etc/v2ray ]];then
        rm -rf /etc/v2ray
    fi

    if [[ -d "/var/log/v2ray" ]];then
        rm -rf /var/log/v2ray
    fi
    echo
    print ${GREEN} "V2Ray uninstall successful!" && echo && exit 0
}

reinstall_v2ray() {
    uninstall_v2ray
    install_v2ray
    print ${GREEN} "Reinstall successful!"
}



# Addition new v2ray protocol .
addition_protocol() {
    if [[ ! -f /etc/systemd/system/v2ray.service || ! -f ${CONFIG_FILE} ]];then
        echo
        print ${RED} "You don't install v2ray please install v2ray first ." && echo && exit 1
    fi

    while :;do
        echo
        print ${GREEN}  "1.Shadowsocks"
        echo
        print ${GREEN}  "2.Socks"
        echo
        print ${GREEN}  "3.Http"
        echo
        print ${GREEN}  "4.MTProto"
        echo
        print ${GREEN}  "5.Dokodemo-door"
        echo
        read -p "$(print ${BLUE} "请选择 V2Ray 传输协议 1 to 5: ")" protocol
        case ${protocol} in
        1)
            LEN=$(cat ${CONFIG_FILE} | jq '.inbounds | length')
            for i in $(cat ${CONFIG_FILE} | jq '.inbounds[] | .protocol')
            do
                if [[ "${i//\"/}" = "shadowsocks" ]];then
                    echo
                    print ${RED} "You've installed shadowsocks nothing to do ." && exit 1
                    echo
                fi
            done
            systemctl stop v2ray

            # Config port
            config_port "shadowsocks"

            # Config password
            config_password "shadowsocks"

            # Config protocol
            config_protocol "aes-256-cfb" "aes-128-cfb" "chacha20" "chacha20-ietf" "chacha20-poly1305" "aes-128-gcm" "aes-256-gcm" "shadowsocks"

            CONFIG='{"protocol":"shadowsocks","port":'${PORT}',"settings":{"method":"'${PROTOCOL}'","password":"'${PASSWORD}'","network":"tcp,udp","level":1,"ota":false}}'
            cat ${CONFIG_FILE} | jq 'setpath(["inbounds",'${LEN}'];'${CONFIG}')' > /etc/v2ray/config.json.bak
            rm -f ${CONFIG_FILE} && mv /etc/v2ray/config.json.bak ${CONFIG_FILE}

            # start service
            systemctl start v2ray

            # Show config info
            echo
            print ${YELLOW} "Ip: ${IP}"
            echo
            print ${YELLOW} "Shadowsocks port: ${PORT}"
            echo
            print ${YELLOW} "Password: ${PASSWORD}"
            echo
            print ${YELLOW} "Encrypt: ${PROTOCOL}"
            echo
            print ${YELLOW} "Protocol: Shadowsocks"
            echo
            print ${YELLOW} "Addition shadowsocks successful"
            echo
            break
        ;;

        2)
            # {"port":1080,"protocol":"socks","settings":{"auth":"password","accounts":[{"user":"username","pass":"password"}],"udp":false,"ip":"127.0.0.1","userLevel":0}}

            # Config port
            config_port "socks"

            # Config username
            config_username "socks"

            # Config password
            config_password "socks"

            LEN=$(cat ${CONFIG_FILE} | jq '.inbounds | length')
            for i in $(cat ${CONFIG_FILE} | jq '.inbounds[] | .protocol')
            do
                if [[ "${i//\"/}" = "socks" ]];then
                    echo
                    print ${RED} "You've installed socks nothing to do ." && echo && exit 1
                fi
            done
            systemctl stop v2ray

            CONFIG='{"port":'${PORT}',"protocol":"socks","settings":{"auth":"password","accounts":[{"user":"'${USERNAME}'","pass":"'${PASSWORD}'"}],"udp":false,"ip":"127.0.0.1","userLevel":0}}'
            cat ${CONFIG_FILE} | jq 'setpath(["inbounds",'${LEN}'];'${CONFIG}')' > /etc/v2ray/config.json.tmp
            mv ${CONFIG_FILE} /etc/v2ray/config.json.bak && mv /etc/v2ray/config.json.tmp ${CONFIG_FILE}
            systemctl start v2ray && rm -f /etc/v2ray/config.json.bak

            # Show config info
            echo
            print ${YELLOW} "Ip: ${IP}"
            echo
            print ${YELLOW} "Http port: ${PORT}"
            echo
            print ${YELLOW} "Username: ${USERNAME}"
            echo
            print ${YELLOW} "Password: ${PASSWORD}"
            echo
            print ${YELLOW} "Protocol: Socks"
            echo
            print ${YELLOW} "Addition socks successful"
            echo

            break
        ;;
        3)
            # {"port":1080,"protocol":"socks","settings":{"timeout":60,"accounts":[{"user":"username","pass":"password"}],"allowTransparent":false,"userLevel":0}}
            # Config port
            config_port "http"

            # Config username
            config_username "http"

            # Config password
            config_password "http"

            LEN=$(cat ${CONFIG_FILE} | jq '.inbounds | length')
            for i in $(cat ${CONFIG_FILE} | jq '.inbounds[] | .protocol')
            do
                if [[ "${i//\"/}" = "http" ]];then
                    echo
                    print ${RED} "You've installed http nothing to do ." && echo && exit 1
                fi
            done
            systemctl stop v2ray

            CONFIG='{"port":'${PORT}',"protocol":"socks","settings":{"timeout":60,"accounts":[{"user":"'${USERNAME}'","pass":"'${PASSWORD}'"}],"allowTransparent":false,"userLevel":0}}'
            cat ${CONFIG_FILE} | jq 'setpath(["inbounds",'${LEN}'];'${CONFIG}')' > /etc/v2ray/config.json.tmp
            mv ${CONFIG_FILE} /etc/v2ray/config.json.bak && mv /etc/v2ray/config.json.tmp ${CONFIG_FILE}
            systemctl start v2ray && rm -f /etc/v2ray/config.json.bak

            # Show config info
            echo
            print ${YELLOW} "Ip: ${IP}"
            echo
            print ${YELLOW} "Http port: ${PORT}"
            echo
            print ${YELLOW} "Username: ${USERNAME}"
            echo
            print ${YELLOW} "Password: ${PASSWORD}"
            echo
            print ${YELLOW} "Protocol: Http"
            echo
            print ${YELLOW} "Addition http successful"
            echo
            break
        ;;
        *)
            print ${RED} "Please enter 1 to 3 ."
        ;;
        esac
    done


}

show_v2ray_config() {
    if [[ ! -f ${CONFIG_FILE} ]];then
        print ${RED} "Maybe you don't install v2ray please check you v2ray status."
    fi
    local ID=$(jq .inbounds[0].settings.clients[0].id ${CONFIG_FILE})

    # Print install config info
    echo
    print ${GREEN} "Ip: ${IP}"
    echo
    print ${GREEN} "V2Ray port: $(jq .inbounds[0].port /etc/v2ray/config.json)"
    echo
	print ${GREEN} "UUID: ${ID//\"/}"
    echo
	print ${GREEN} "ExtraID: $(jq .inbounds[0].settings.clients[0].alterId ${CONFIG_FILE})"
    echo
    print ${GREEN} "Level: $(jq .inbounds[0].settings.clients[0].level ${CONFIG_FILE})"
    echo
    print ${GREEN} "Protocol: VMess"
    echo
    exit 0
}

remove_protocol() {
    echo
    if [[ ! -f ${CONFIG_FILE} || ! -f ${SERVICE_FILE} ]];then
        print ${RED} "You don't install v2ray please install v2ray first ." && echo && exit 1
    fi

    LEN=$(cat ${CONFIG_FILE} | jq '.inbounds | length')
    if (( ${LEN}<2 ));then
        print ${RED} "V2ray must have at least one protocol ." && echo && exit 1
    fi
    systemctl stop v2ray
    while :;do
        index=0
        for i in $(cat ${CONFIG_FILE} | jq '.inbounds[] | .protocol');do
            index=`expr ${index} + 1`
            print ${GREEN} "${index}.${i//\"/}"
            echo
        done
        print ${GREEN} "Enter any key cancel." && echo
        read -p "$(print ${BLUE} "请选择需要删除的 V2ray 协议 1-${index}: ")" option
        echo
        if [[ ${option} -gt 0 ]] && (( ${option} < ${LEN}+1 ));then
            ((option=${option}-1))
            PROTOCOL=$(cat ${CONFIG_FILE} | jq '.inbounds['${option}'].protocol')
            cat ${CONFIG_FILE} | jq 'del(.inbounds['${option}'])' > /etc/v2ray/config.json.tmp
            mv ${CONFIG_FILE} /etc/v2ray/config.json.bak && mv /etc/v2ray/config.json.tmp ${CONFIG_FILE} && systemctl start v2ray
            print ${GREEN} "Removed ${PROTOCOL//\"/} successful ."
            break
        else
            break
        fi
    done
    echo && exit 0
}


while :; do

    print ${GREEN} "----------------------------------------------"
	echo
	print ${GREEN} "1.Install V2Ray"
	echo
	print ${GREEN} "2.Uninstall V2Ray"
	echo
	print ${GREEN} "3.Reinstall V2Ray"
	echo
	print ${GREEN} "4.Show v2ray config"
	echo
	print ${GREEN} "5.Addition new protocol"
	echo
	print ${GREEN} "6.Remove a protocol"
	echo
	print ${GREEN} "Enter any key to exit ."
	echo
	print ${GREEN} "----------------------------------------------"
	read -p "$(print ${BLUE} "请选择 [1-6]:")" option
	case ${option} in
	1)
		install_v2ray
		break
		;;
	2)
		uninstall_v2ray
		break
		;;
	3)
	    reinstall_v2ray
	    break
	    ;;
	4)
	    show_v2ray_config
	    break
	    ;;
	5)
	    addition_protocol
	    break
	    ;;
	6)
	    remove_protocol
	    break
	    ;;
	*)
		exit 0
		;;
	esac
done

exit 0
