#!/bin/bash

# Post-Provisioning script for a generic CentOS 7 dockerhost on Softlayer
# Second disk is added to LVM and formatted as btrfs to take advantage
# of the btrfs driver in docker over the crappy default loopback devices.
#
# Assumes second provisioned volume is at /dev/xvdc, which should be
# the default on a two-disk CentOS minimal hourly instance.

#set -x
set -euo pipefail

exec 1> >(logger -s -t $(basename $0)) 2>&1

yum -y update && yum clean all && yum makecache fast
yum -y install lvm2 lvm2-libs btrfs-progs git

echo "Setup xvdc partition layout for docker"
    cat << EOF > /tmp/xvdc.layout
# partition table of /dev/xvde
unit: sectors

/dev/xvdc1 : start=     2048, size= 26213376, Id=8e
/dev/xvdc2 : start=        0, size=        0, Id= 0
/dev/xvdc3 : start=        0, size=        0, Id= 0
/dev/xvdc4 : start=        0, size=        0, Id= 0
EOF

echo "Apply partition layouts..."
sfdisk --force /dev/xvdc < /tmp/xvdc.layout

echo "Create physical volumes in lvm..."
pvcreate /dev/xvdc1

echo "Create lvm volume groups..."
vgcreate docker_vg /dev/xvdc1

echo "Create lvm logical volumes..."
lvcreate -l 100%FREE -n docker_lv1 docker_vg

echo "Setup btrfs filesystem of lvm volumes..."
mkfs.btrfs /dev/docker_vg/docker_lv1
rm /tmp/xvdc.layout

echo "Mounting btrfs volume to /var/lib/docker"
[[ ! -d /var/lib/docker ]] && mkdir /var/lib/docker
mount /dev/docker_vg/docker_lv1 /var/lib/docker

echo "Adding lvm volumes to fstab.."
echo "/dev/docker_vg/docker_lv1 /var/lib/docker                       btrfs   defaults,noatime,autodefrag     0 0" >> /etc/fstab

motd="/etc/motd"
W="\033[01;37m"
B="\033[00;34m"
R="\033[01;31m"
RST="\033[0m"
clear > $motd
printf "${W}======================================================\n" >> $motd
printf "\n" >> $motd
printf "   ${B}███████╗██╗    ██╗ █████╗ ██████╗ ███╗   ███╗\n" >> $motd
printf "   ██╔════╝██║    ██║██╔══██╗██╔══██╗████╗ ████║\n" >> $motd
printf "   ███████╗██║ █╗ ██║███████║██████╔╝██╔████╔██║\n" >> $motd
printf "   ╚════██║██║███╗██║██╔══██║██╔══██╗██║╚██╔╝██║\n" >> $motd
printf "   ███████║╚███╔███╔╝██║  ██║██║  ██║██║ ╚═╝ ██║\n" >> $motd
printf "   ╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝\n" >> $motd
printf "\n" >> $motd
printf " ${R}This service is restricted to authorized users only.\n" >> $motd
printf "      All activities on this system are logged.\n" >> $motd
printf "$RST" >> $motd
printf "${W}======================================================\n" >> $motd
printf "$RST" >> $motd

echo "Post-provisioning for host $(hostname) complete!"
