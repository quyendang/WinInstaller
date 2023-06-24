#!/bin/bash
if [ -z "$BASH" ]; then
    bash $0 "$@"
    exit 0
fi
if [ "$(id -u)" != "0" ]; then
    echo "You must be root to execute the script. Exiting."
    exit 1
fi

if ! command -v ip > /dev/null || ! command -v wget > /dev/null || ! command -v lsblk > /dev/null || ! command -v fdisk > /dev/null; then
	echo "Installing dependencies..."
	if [ -e /etc/debian_version ]; then
        	apt-get --quiet --yes update || true
		apt-get --quiet --quiet --yes install iproute2 wget fdisk || true
	else
		yum --quiet --assumeyes install iproute2 wget fdisk util-linux || true
	fi
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
mkdir -p /usr/local
wget -4 -qO /usr/local/tinstaller raw.githubusercontent.com/quyendang/WinInstaller/main/install.sh || wget -6 -qO /usr/local/tinstaller raw.githubusercontent.com/quyendang/WinInstaller/main/install.sh
chmod +x /usr/local/tinstaller
/usr/local/tinstaller "$@"
