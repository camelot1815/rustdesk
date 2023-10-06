#!/bin/bash

# Get user options
while getopts i:-: option; do
    case "${option}" in
        -)
            case "${OPTARG}" in
                help)
                    help="true";;
                resolveip)
                    resolveip="true";;
                resolvedns)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    resolvedns=${val};;
                install-http)
                    http="true";;
                skip-http)
                    http="false";;
            esac;;
        i) resolveip="true";;
    esac
done

function displayhelp() {
    if [[ ! -z $help ]]; then
        echo 'usage: install.sh --resolveip --resolvedns "fqdn"'
        echo "options:"
        echo "--resolveip    Use IP for server name.  Cannot use in combination with --resolvedns or -d"
        echo '--resolvedns "fqdn"    Use FQDN for server name.  Cannot use in combination with --resolveip or -i'
        echo "--install-http    Install http server to host installation scripts.  Cannot use in combination with --skip-http or -n"
        echo "--skip-http    Skip installation of http server.  Cannot use in combination with --install-http or -h"
        exit 0
    fi
}
displayhelp
# Get Username
uname=$(whoami)
admintoken=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c16)

ARCH=$(uname -m)

# identify OS
if [ -f /etc/os-release ]; then
    # freedesktop.org and systemd
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID

    UPSTREAM_ID=${ID_LIKE,,}

    # Fallback to ID_LIKE if ID was not 'ubuntu' or 'debian'
    if [ "${UPSTREAM_ID}" != "debian" ] && [ "${UPSTREAM_ID}" != "ubuntu" ]; then
        UPSTREAM_ID="$(echo ${ID_LIKE,,} | sed s/\"//g | cut -d' ' -f1)"
    fi


elif type lsb_release >/dev/null 2>&1; then
    # linuxbase.org
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
    # For some versions of Debian/Ubuntu without lsb_release command
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    # Older Debian/Ubuntu/etc.
    OS=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSe-release ]; then
    # Older SuSE/etc.
    OS=SuSE
    VER=$(cat /etc/SuSe-release)
elif [ -f /etc/redhat-release ]; then
    # Older Red Hat, CentOS, etc.
    OS=RedHat
    VER=$(cat /etc/redhat-release)
else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
    VER=$(uname -r)
fi


# output ebugging info if $DEBUG set
if [ "$DEBUG" = "true" ]; then
    echo "OS: $OS"
    echo "VER: $VER"
    echo "UPSTREAM_ID: $UPSTREAM_ID"
    exit 0
fi

# Setup prereqs for server
# common named prereqs
PREREQ="curl wget unzip tar"

echo "Installing prerequisites"
apt-get update
apt-get install -y  ${PREREQ}

# Make Folder /opt/rustdesk/
if [ ! -d "/opt/rustdesk" ]; then
    echo "Creating /opt/rustdesk"
    mkdir -p /opt/rustdesk/
fi
chown "${uname}" -R /opt/rustdesk
cd /opt/rustdesk/ || exit 1
#Download latest version of Rustdesk
echo "Installing Rustdesk Server"
RDLATEST=$(curl https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest -s | grep "tag_name"| awk '{print substr($2, 2, length($2)-3) }')
wget "https://github.com/rustdesk/rustdesk-server/releases/download/${RDLATEST}/rustdesk-server-linux-amd64.zip"
unzip rustdesk-server-linux-amd64.zip
mv amd64/* /opt/rustdesk/
chmod +x /opt/rustdesk/hbbs
chmod +x /opt/rustdesk/hbbr


# Make Folder /var/log/rustdesk/
if [ ! -d "/var/log/rustdesk" ]; then
    echo "Creating /var/log/rustdesk"
    mkdir -p /var/log/rustdesk/
fi
chown "${uname}" -R /var/log/rustdesk/

pubname=$(find /opt/rustdesk -name "*.pub")
key=$(cat "${pubname}")

echo "Tidying up install"
rm rustdesk-server-linux-amd64.zip
rm -rf amd64


function setuphttp () {
    # Create windows install script
    wget https://raw.githubusercontent.com/dinger1986/rustdeskinstall/master/WindowsAgentAIOInstall.ps1
    sed -i "s|wanipreg|${wanip}|g" WindowsAgentAIOInstall.ps1
    sed -i "s|keyreg|${key}|g" WindowsAgentAIOInstall.ps1

    # Create linux install script
    wget https://raw.githubusercontent.com/dinger1986/rustdeskinstall/master/linuxclientinstall.sh
    sed -i "s|wanipreg|${wanip}|g" linuxclientinstall.sh
    sed -i "s|keyreg|${key}|g" linuxclientinstall.sh

    # Download and install gohttpserver
    # Make Folder /opt/gohttp/
    if [ ! -d "/opt/gohttp" ]; then
        echo "Creating /opt/gohttp"
        mkdir -p /opt/gohttp/
        mkdir -p /opt/gohttp/public
    fi
    chown "${uname}" -R /opt/gohttp
    cd /opt/gohttp
    GOHTTPLATEST=$(curl https://api.github.com/repos/codeskyblue/gohttpserver/releases/latest -s | grep "tag_name"| awk '{print substr($2, 2, length($2)-3) }')

    echo "Installing Go HTTP Server"
    if [ "${ARCH}" = "x86_64" ] ; then
    wget "https://github.com/codeskyblue/gohttpserver/releases/download/${GOHTTPLATEST}/gohttpserver_${GOHTTPLATEST}_linux_amd64.tar.gz"
    tar -xf  gohttpserver_${GOHTTPLATEST}_linux_amd64.tar.gz
    elif [ "${ARCH}" =  "aarch64" ] ; then
    wget "https://github.com/codeskyblue/gohttpserver/releases/download/${GOHTTPLATEST}/gohttpserver_${GOHTTPLATEST}_linux_arm64.tar.gz"
    tar -xf  gohttpserver_${GOHTTPLATEST}_linux_arm64.tar.gz
    elif [ "${ARCH}" = "armv7l" ] ; then
    echo "Go HTTP Server not supported on 32bit ARM devices"
    echo -e "Your IP/DNS Address is ${wanip}"
    echo -e "Your public key is ${key}"
    exit 1
    fi

    # Copy Rustdesk install scripts to folder
    mv /opt/rustdesk/WindowsAgentAIOInstall.ps1 /opt/gohttp/public/
    mv /opt/rustdesk/linuxclientinstall.sh /opt/gohttp/public/

    # Make gohttp log folders
    if [ ! -d "/var/log/gohttp" ]; then
        echo "Creating /var/log/gohttp"
        mkdir -p /var/log/gohttp/
    fi
    chown "${uname}" -R /var/log/gohttp/

    echo "Tidying up Go HTTP Server Install"
    if [ "${ARCH}" = "x86_64" ] ; then
    rm gohttpserver_"${GOHTTPLATEST}"_linux_amd64.tar.gz
    elif [ "${ARCH}" = "armv7l" ] || [ "${ARCH}" =  "aarch64" ]; then
    rm gohttpserver_"${GOHTTPLATEST}"_linux_arm64.tar.gz
    fi


    # Setup Systemd to launch Go HTTP Server
    gohttpserver="$(cat << EOF
[Unit]
Description=Go HTTP Server
[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/opt/gohttp/gohttpserver -r ./public --port 8000 --auth-type http --auth-http admin:${admintoken}
WorkingDirectory=/opt/gohttp/
User=${uname}
Group=${uname}
Restart=always
StandardOutput=append:/var/log/gohttp/gohttpserver.log
StandardError=append:/var/log/gohttp/gohttpserver.error
# Restart service after 10 seconds if node service crashes
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
)"
    echo "${gohttpserver}" | tee /etc/systemd/system/gohttpserver.service > /dev/null
    systemctl daemon-reload
    systemctl enable gohttpserver.service
    systemctl start gohttpserver.service


    echo -e "Your IP/DNS Address is ${wanip}"
    echo -e "Your public key is ${key}"
    echo -e "Install Rustdesk on your machines and change your public key and IP/DNS name to the above"
    echo -e "You can access your install scripts for clients by going to http://${wanip}:8000"
    echo -e "Username is admin and password is ${admintoken}"
    if [[ -z "$http" ]]; then
        echo "Press any key to finish install"
        while [ true ] ; do
        read -t 3 -n 1
        if [ $? = 0 ] ; then
        exit ;
        else
        echo "waiting for the keypress"
        fi
        done
        break
    fi
}

echo -e "Your IP/DNS Address is ${wanip}"
echo -e "Your public key is ${key}"
echo -e "Install Rustdesk on your machines and change your public key and IP/DNS name to the above"

