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
yum -y install lvm2 lvm2-libs
yum -y install btrfs-progs

echo "Setup xvdc partition layout for docker"
if [[ ! -b /dev/xvdc1 ]]; then
    cat << EOF > /tmp/xvdc.layout
# partition table of /dev/xvde
unit: sectors

/dev/xvdc1 : start=     2048, size= 20969472, Id=8e
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
fi

echo "Mounting btrfs volume to /var/lib/docker"
mount /dev/docker_vg/docker_lv1 /var/lib/docker

echo "Adding lvm volumes to fstab.."
echo "/dev/docker_vg/docker_lv1 /var/lib/docker                       btrfs   defaults,noatime,autodefrag     0 0" >> /etc/fstab
