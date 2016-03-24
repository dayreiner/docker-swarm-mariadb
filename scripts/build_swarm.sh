#!/bin/bash

#############################################################################
# Build an n-node docker swarm HA cluster with HA consul for discovery
# running on the swarm itself. Uses docker machine generic driver
# and pre-existing CentOS 7 nodes in Softlayer.
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

# Build cluster members with docker machine
export node_consul=consul.service.consul
for node in ${nodelist[@]} ; do
    export node_private_ip=$(slcli vs detail ${node} | grep private_ip | awk '{print $2}')
    export node_public_ip=$(slcli vs detail ${node} | grep public_ip | awk '{print $2}')
    export node_ssh_ip=$(slcli vs detail ${node} | grep ${sl_ssh_interface}_ip | awk '{print $2}')

    echo
    echo "-------------------------------------------------" 
    echo "Current Run Details..."   
    echo "Provisioning node ${node}"
    echo "Public IP = ${node_public_ip}"
    echo "Private IP = ${node_private_ip}"
    echo "Consul URL = consul://${node_consul}:8500"
    echo "DNS Search Doamin = ${dns_search_domain}"
    echo "-------------------------------------------------" 
    echo

    docker-machine ${machine_opts} create \
    --driver generic \
    --generic-ip-address ${node_ssh_ip} \
    --generic-ssh-key ${__root}/ssh/swarm.rsa \
    --generic-ssh-user root \
    --engine-storage-driver btrfs \
    --swarm --swarm-master \
    --swarm-opt="replication=true" \
    --swarm-opt="advertise=${node_private_ip}:3376" \
    --swarm-discovery="consul://${node_consul}:8500" \
    --engine-opt="cluster-store consul://${node_consul}:8500" \
    --engine-opt="cluster-advertise=eth0:2376" \
    --engine-opt="dns ${node_private_ip}" \
    --engine-opt="dns ${dns_primary}" \
    --engine-opt="dns ${dns_secondary}" \
    --engine-opt="log-driver json-file" \
    --engine-opt="log-opt max-file=10" \
    --engine-opt="log-opt max-size=10m" \
    --engine-opt="dns-search=${dns_search_domain}" \
    --engine-label="dc=${datacenter}" \
    --engine-label="instance_type=public_cloud" \
    --tls-san ${node} \
    --tls-san ${node_private_ip} \
    --tls-san ${node_public_ip} \
    ${node}
done

# Install consul across cluster members for swarm discovery
export nodelist=( $(docker-machine ls -q) )
for node in ${nodelist[@]} ; do
    othernodes=( $(echo ${nodelist[@]} | tr ' ' '\n' | grep -v ${node}) )
    nodecount=${#othernodes[@]}
    for (( nodenum=0; nodenum<${nodecount}; nodenum++ )) ; do
        export othernode${nodenum}_cluster_ip=$(docker-machine ip ${othernodes[${nodenum}]})
    done
    export node_cluster_ip=$(docker-machine ip ${node})
    export swarm_total_nodes=${#nodelist[@]}
    export node
    echo
    echo
    echo "-------------------------------------------------" 
    echo "Current Run Details..."   
    echo "Node = ${node}"
    echo "Node Consul Advertise IP = ${node_cluster_ip}"
    echo "Joining Consul IP #1  = ${othernode0_cluster_ip}"
    echo "Joining Consul IP #2  = ${othernode1_cluster_ip}"
    echo "DNS Search Doamin = ${dns_search_domain}"
    echo "-------------------------------------------------"
    echo
    echo
    docker-machine ssh ${node} "printf 'nameserver ${node_cluster_ip}\nnameserver ${dns_primary}\nnameserver ${dns_secondary}\ndomain ${dns_search_domain}\n' > /etc/resolv.conf"
    docker-machine scp -r ${__root}/compose/consul/config ${node}:/tmp/consul
    docker-machine ssh ${node} "mv /tmp/consul /etc"
    eval $(docker-machine env ${node})
    docker-compose -f ${__root}/compose/consul/consul.yml up -d consul
    docker-machine ssh ${node} "systemctl restart docker"
done

echo "Done"
