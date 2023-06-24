#!/bin/bash
if [ -z "$BASH" ]; then
    bash $0 "$@"
    exit 0
fi
if [ "$(id -u)" != "0" ]; then
    echo "You must be root to execute the script. Exiting."
    exit 1
fi

if ! command -v ip > /dev/null; then
	echo "Please make sure 'ip' tool is available on your system and try again."
	exit 1
fi
if ! command -v wget > /dev/null; then
	echo "Please make sure 'wget' tool is available on your system and try again."
	exit 1
fi

if ! command -v lsblk > /dev/null; then
  echo "Please make sure 'lsblk' tool is available on your system and try again."
  exit 1
fi

if ! command -v blkid > /dev/null; then
  echo "Please make sure 'blkid' tool is available on your system and try again."
  exit 1
fi

if ! command -v fdisk > /dev/null; then
  echo "Please make sure 'fdisk' tool is available on your system and try again."
  exit 1
fi

confirm="no"
POSITIONAL=()
disk=
ipAddr=
brd=
ipGate=
installId=
image=
interface=
beta=
while [ $# -ge 1 ]; do
    case $1 in
    -b | --beta)
        beta="y"
        shift
        ;;
    -d | --disk)
        disk=$2
        shift
        shift
        ;;
    -i | --image)
        image=$2
        shift
        shift
        ;;
    -r | --resume)
        installId=$2
        shift
        shift
        ;;

    --iface)
        interface=$2
        shift
        shift
        ;;
    --ip)
        ipAddr=$2
        shift
        shift
        ;;

    --brd)
        brd=$2
        shift
        shift
        ;;

    --gate | --gateway)
        ipGate=$2
        shift
        shift
        ;;

    -y | --yes)
        shift
        confirm="yes"
        ;;
    *)
        POSITIONAL+=("$1")
        shift
        ;;
    esac
done

set -- "${POSITIONAL[@]}"

USER=$1


ipDNS='8.8.8.8'
setNet='0'
if [ "$USER" = "" ]; then
    echo -n "Enter license key: "
    read USER
fi
[ -n "$USER" ] || [ -n "$installId" ] || {
    printf '\nError: No license key provided\n\n'
    exit 1
}
if ! which wget >/dev/null; then
    apt install -y wget
fi

getDisk() {
    bootDisk=$(mount | grep -E '(/boot)' | head -1 | awk '{print $1}')
    if [ -z "$bootDisk" ];then
        bootDisk=$(mount | grep -E '(/ )' | head -1 | awk '{print $1}')
    fi
    if echo "$bootDisk" | grep -q "/mapper/"; then
        bootDisk=""
    fi
    allDisk=$(fdisk -l | grep 'Disk /' | grep -o "\/dev\/[^:[:blank:]]\+")

    for item in $allDisk; do
        dsize=$(lsblk -b --output SIZE -n -d $item)
        [ "$dsize" -gt "4294967296" ] || continue
        if [ -n "$bootDisk" ]; then
            if echo "$bootDisk" | grep -q "$item"; then
                echo "$item" && break
            fi
        else
            if ! echo "$item" | grep -q "/mapper/"; then
                echo "$item"
            fi
        fi
    done
}

if [ -z "$disk" ]; then
    disk=$(getDisk)
    dCount=$(echo "$disk" | wc -l)
    [ "$dCount" -lt 2 ] || {
        echo "Could not auto select disk. Please select it manually by specify option --disk your_disk. Available disks: "
        echo "$disk"
        exit 1
    }
    if echo "$disk" | grep -q "/dev/md"; then
        echo "Install on raid device is not supported. Please select disk manually by specify option --disk your_disk. e.g. sh setup.sh --disk /dev/sda"
        exit 1
    fi

fi
[ -n "$disk" ] || {
    printf '\nError: No disk available\n\n'
    exit 1
}

getInterface() {
    Interfaces=$(cat /proc/net/dev | grep ':' | cut -d':' -f1 | sed 's/\s//g' | grep -iv '^lo\|^sit\|^stf\|^gif\|^dummy\|^vmnet\|^vir\|^gre\|^ipip\|^ppp\|^bond\|^tun\|^tap\|^ip6gre\|^ip6tnl\|^teql\|^ocserv\|^vpn')
    defaultRoute=$(ip route show default | grep "^default")
    for item in $(echo "$Interfaces"); do
        [ -n "$item" ] || continue
        if echo "$defaultRoute" | grep -q "$item"; then
            interface="$item" && break
        fi
    done
    echo "$interface"
}
[ -n "$ipAddr" ] && [ -n "$brd" ] && [ -n "$ipGate" ] && setNet='1'

if [ "$setNet" = "0" ]; then
    [ -n "$interface" ] || interface=$(getInterface)
    inet=$(ip addr show dev "$interface" | grep "inet.*" | grep -v "127.0.0" | head -n1)
    ipAddr=$(echo $inet | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\/[0-9]\{1,2\}')
    brd=$(echo $inet | grep -o 'brd[ ]\+[^ ]\+' | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}')
    ipGate=$(ip route show default | grep "^default" | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | head -n1)
    mac=$(cat "/sys/class/net/$interface/address")
    if [ -z "$brd" ] && [ -n "$ipAddr" ]; then
        brd=$(wget -q -O - "https://ti.4it.top/calculator/brd?ip=$ipAddr")
    fi
fi

[ -n "$ipAddr" ] && [ -n "$brd" ] && [ -n "$ipGate" ] && [ -n "$ipDNS" ] || {
    printf '\nError: Invalid network config\n\n'
    exit 1
}
[ -n "$mac" ] || {
    printf '\nError: Invalid network config\n\n'
    printf "\nCould not get MAC address for $interface \n\n"
    yesno="n"
    printf "Still continue? (y,n) : "
    read yesno
    if [ "$yesno" != "y" ]; then
        exit 1
    fi
}
rm -rf /usr/local/ti
mkdir /usr/local/ti
selectedImage=/usr/local/ti/image.txt
ipStr="$ipAddr|$brd|$ipGate|$mac"
installIp=$ipStr
if [ -z "$installId" ]; then
    if [ "$image" = "" ]; then
        #Only load image list if not selected
        userInfoFile=/usr/local/ti/user.txt
        userUrl="https://ti.4it.top/u/$USER/i"
        wget -4 -q -O $userInfoFile "$userUrl" || wget -6 -q -O $userInfoFile "$userUrl"
        if [ ! -s $userInfoFile ]; then
            echo "*** Unable to get user info ***"
            echo "tried: $USER"
            exit 1
        fi
        cat $userInfoFile
        # shellcheck disable=SC2063
        COUNT=$(head -n 4 $userInfoFile | grep -c "* TinyInstaller error *")
        if [ "$COUNT" -ne 0 ]; then
            echo ""
            exit 2
        fi
    fi



    dsize=$(lsblk -b --output SIZE -n -d $disk)
    diskUuid=$(blkid -s UUID -o value "$(blkid -o device | grep $disk | head -1)")
    diskStr="$diskUuid|$dsize|$disk"

    if [ "$image" = "" ]; then
        echo -n "Select Image: "
        read image
        selectImageUrl="https://ti.4it.top/u/$USER/create/::$image?disk=$diskStr&ip=$ipStr&beta=$beta"
    else
        selectImageUrl="https://ti.4it.top/u/$USER/create/$image?disk=$diskStr&ip=$ipStr&beta=$beta"
    fi
    wget -4 -q -O $selectedImage "$selectImageUrl" || wget -6 -q -O $selectedImage "$selectImageUrl"
else
    wget -q -O $selectedImage "https://ti.4it.top/i/$installId/image"
fi

if [ ! -s $selectedImage ]; then
    echo "*** Unable to select image ***"
    echo "Image: $image"
    exit 3
fi
# shellcheck disable=SC2063
COUNT=$(head -n 4 $selectedImage | grep -c "* TinyInstaller error *")
if [ "$COUNT" -ne 0 ]; then
    cat $selectedImage
    echo ""
    exit 4
fi
installId=$(cat $selectedImage | cut -d: -f1)
image=$(cat $selectedImage | cut -d: -f2-)



clear && printf "\n\033[36m# Install\033[0m\n"
yesno="n"
echo "Installer will reboot your computer then re-install with using these information"


trackingUrl="https://ti.4it.top/i/$installId"
echo ""
echo "Image: $image"
echo "IPv4: $ipAddr"
echo "Brd: $brd"
echo "Gate: $ipGate"
echo "Disk: $disk"
echo "Tracking: $trackingUrl"
echo ""

if [ "$confirm" = "no" ]; then
    printf "I have copied and opened Tracking url? (y,n) : "
    read yesno
    if [ "$yesno" != "y" ]; then
        exit 1
    fi
fi

echo "Downloading TinyInstaller..."
installerUrl="https://ti.4it.top/installer.gz?t=1"
wget -4 -qO /usr/local/installer.gz $installerUrl || wget -6 -qO /usr/local/installer.gz $installerUrl
rm -f /usr/local/installer
gunzip /usr/local/installer.gz
chmod +x /usr/local/installer
/usr/local/installer "$installId" "$installIp"
