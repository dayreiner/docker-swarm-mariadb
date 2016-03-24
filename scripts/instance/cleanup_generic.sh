#!/bin/bash

# Cleanup after removing a generic centos system from docker machine.
#
# Without cleaning up first, attempting to reprovision with the 
# generic driver in machine will fail.
#
# Run on docker-machine $node before performing docker-machine rm $node
# Node can then be reprovisioned using machine without crapping out.

# Stop Docker
systemctl stop docker

# If using btrfs for /var/lib/docker, cleanup btrfs snapshots
if [[ $(btrfs filesystem show /var/lib/docker|grep devid|wc -l) != 0 ]] ; then
    cd /var/lib/docker
    btrfs subvol del $(btrfs subvol list -t .|awk '{print $4}' |tail -n+3)
    cd /
fi

# Clear docker dirs and systemd config placed by machine
rm -rf /etc/docker
rm -rf /var/lib/docker
rm /etc/systemd/system/docker.service

# Remove Docker packages and yum repo
yum -y remove docker-engine docker-engine-selinux
rm /etc/yum.repos.d/docker*

# Cleanup consul dirs if present
rm -rf /etc/consul
rm -rf /tmp/consul

# Reset resolv.conf to use google
echo "nameserver 8.8.8.8" > /etc/resolv.conf
