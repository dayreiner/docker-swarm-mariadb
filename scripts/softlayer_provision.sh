#!/bin/bash

#############################################################################
# Provision configured instances in the public cloud in IBM Softlayer
#############################################################################

#set -o xtrace # uncomment for debug

#############################################################################
# Nothing to set past here
#############################################################################

# Strict modes. Same as -euo pipefail
set -o errexit
set -o pipefail
set -o nounset

# Set some useful vars
IFS=$'\n\t' # Set field separator to return+tab
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # Dir this script runs out of
__root="$(cd "$(dirname "${__dir}")" && pwd)" # Parent dir
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")" # This script's filename

# Trap errors
trap $(printf "\n\tERROR: ${LINENO}\n\n" && exit 1) ERR

cd ${__dir}

# Get config. Load local override config if present.
if [[ -e ${__root}/config/swarm.local ]] ; then
    source ${__root}/config/swarm.local
else
    source ${__root}/config/swarm.conf
fi

# Set machine storage to machine subdir of repo
export MACHINE_STORAGE_PATH="${__root}/machine"

# Check for slcli
[[ ! $(which slcli 2>/dev/null) ]] && echo "slcli tool required. Make sure slcli is configured and in your path" && exit 1

# Order swarm instances using slcli

# Get per-node cost
export node=${nodelist[0]}
node_hourly_cost="$(slcli vs create --test --public ${sl_disk_type} \
-H ${node} -D ${sl_domain} -c ${sl_cpu} -m ${sl_memory} \
-d ${sl_region} -o CENTOS_LATEST --billing ${sl_billing} \
--disk ${sl_os_disk_size} --disk ${sl_docker_disk_size} -n 100 \
| grep "Total hourly" | awk '{print $4}')"

echo
echo "########################################################"
echo "#       ATTENTION - THIS WILL PROVISION LIVE VM'S      #"
echo "#        YOU *WILL* ACCRUE COSTS IF YOU CONTINUE       #"
echo "########################################################"
echo
echo "- Total # of Nodes: ${#nodelist[@]}"
echo "- Nodes: ${nodelist[@]}"
echo "- CPU: ${sl_cpu} core(s) RAM: ${sl_memory}GB"
echo "- Hourly Cost Per Node: \$${node_hourly_cost} / ${sl_billing}"
swarm_hourly_cost=$(echo "${node_hourly_cost} ${#nodelist[@]}" | awk '{printf "%f", $1 * $2}' | cut -b1-4)
echo "- TOTAL Hourly cost to run swarm: \$${swarm_hourly_cost} / ${sl_billing}"
echo
echo "########################################################"
echo

read -p "Are you sure you wish to continue? Type ORDER to continue: " answer
case ${answer} in
    ORDER)
    echo "OK Lets go"
;;
*)
    echo "Cancelling, no order will be placed..."
    exit
;;
esac

echo "Provisioning ssh key for swarm provisioning..."
if [[ ! $(slcli sshkey list | grep ${sl_sshkey_name}) ]] ; then
    if [[ ! -e ${__root}/ssh/swarm.rsa && ! -e ${__root}/ssh/swarm.rsa.pub ]] ; then
        echo "Existing swarm ssh cert and key not found, generating a new set..."
        echo -e 'y\n' | ssh-keygen -f ${__root}/ssh/swarm.rsa -t rsa -N ''
    fi
    echo "Adding swarm.rsa.pub to Softlayer account as ${sl_sshkey_name}"
    slcli sshkey add -f ${__root}/ssh/swarm.rsa.pub \
    --note "Test Key for https://github.com/dayreiner/docker-swarm-mariadb" ${sl_sshkey_name}
else
    if [[ ! -e ${__root}/ssh/swarm.rsa && ! -e ${__root}/ssh/swarm.rsa.pub ]] ; then
        echo
        echo "SSH Key present in softlayer but not found locally. Cannot continue."
        echo "Please run 'slcli sshkey remove ${sl_sshkey_name}' and re-run this script. Exiting."
        echo
        exit 1
    fi
   echo "SSH Key already present locally added to Softlayer account. Skipping..." 
fi

echo

# Actually place the orders

echo
echo "Provisioning ${#nodelist[@]} nodes: ${nodelist[@]}"
echo
[[ ! -f /usr/bin/expect ]] && echo "Please install expect to continue..." && exit 1
for node in ${nodelist[@]} ; do
    echo "Ordering ${node}..."
    /usr/bin/expect <<- EOF
	set force_conservative 0
	set timeout 10
	spawn slcli vs create \
	-H ${node} -D ${sl_domain} -c ${sl_cpu} -m ${sl_memory} \
	-d ${sl_region} -o CENTOS_LATEST --billing ${sl_billing} \
	--public ${sl_disk_type} -k $(slcli sshkey list | grep ${sl_sshkey_name} | awk '{print $1}') \
	--disk ${sl_os_disk_size} --disk ${sl_docker_disk_size} -n 100 \
	--tag dockerhost --vlan-public ${sl_public_vlan_id} --vlan-private ${sl_private_vlan_id}
	expect "*?N]: "
	send "Y\r"
	expect eof
	EOF
    echo "Ordering for ${node} complete!"
done

echo
echo "Swarm nodes ordered in softlayer. Waiting for provisioning to complete..."
echo

for node in ${nodelist[@]} ; do
    provision_state="waiting"
    while [[ ${provision_state} = "waiting" ]]; do
        provision_status=$(slcli vs detail ${node} | grep status | awk '{print $2}')
        if [[ $provision_status != "ACTIVE" ]]; then
            echo "Provisioning in progress. Status is ${provision_status}. Will check again in 1 minute..."
            sleep 60
        else
            state=$provision_status
            echo "Provisioning of ${node} completed. Running post-provision script." 
        fi
    done
    node_ssh_ip=$(slcli vs detail ${node} | grep ${sl_ssh_interface}_ip | awk '{print $2}')
    echo
    scp ${__root}/scripts/provisioning/sl_post_provision.sh root@${node_ssh_ip}:/tmp
    ssh root@${node_ssh_ip} "chmod +x /tmp/sl_post_provision.sh"
    ssh root@${node_ssh_ip} "/tmp/sl_post_provision.sh"
done

echo "########################################################"
echo "#         SWARM INSTANCE PROVISIONING COMPLETE         #"
echo "########################################################"
echo
echo "You can now run build_cluster.sh to build the docker swarm
echo "cluster on the provisioned instances"
echo
