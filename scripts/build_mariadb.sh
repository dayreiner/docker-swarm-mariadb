#!/bin/bash

#############################################################################
# Build an n-node docker swarm HA cluster with HA consul for discovery
# running on the swarm itself. Uses docker machine generic driver
# and pre-existing CentOS 7 nodes in Softlayer.
#############################################################################

set -o xtrace # uncomment for debug

#############################################################################
# Nothing to set past here
#############################################################################

# Strict modes. Same as -euo pipefail
set -o errexit
set -o pipefail
set -o nounset

# Set some useful vars
#IFS=$'\n\t' # Set field separator to return+tab
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

# Get our list of nodes from docker machine
export nodelist=( $(docker-machine ls -q) )
eval $(docker-machine env ${node})

# Create our overlay network if it doesn't already exist
[[ ! $(docker network ls | grep mariadb) ]] && docker network create -d overlay --subnet=172.100.100.0/24 mariadb

# Bootstrap mariadb cluster on the first node if not already here
# Otherwise, try to join as a regular node
export node=${nodelist[0]}
cd ${__root}/compose/mariadb
if [[ ! $(docker ps | grep db) ]] ; then
    echo "${nodelist[0]}/db not running. Attempting to bootstrap cluster..."
    for node in ${nodelist[0]} ; do
        eval $(docker-machine env ${node})
        # Set the cluster mode to bootstrap, as we're the first one
        export cluster_members=BOOTSTRAP
        export node
        sed "s/%%DBNODE%%/db-${node}/g" mariadb.yml > ${node}.yml
        docker-compose -f ${__root}/compose/mariadb/${node}.yml up -d --no-recreate
    done
else
    echo "${nodelist[0]}/db already running. Attempting to rejoin cluster as regular node..."
    for node in ${nodelist[0]} ; do
        eval $(docker-machine env ${node})
        # Set the cluster mode to bootstrap, as we're the first one
        cluster_members=$(printf ",db-%s" "${nodelist[@]}")
        export cluster_members=${cluster_members:1}
        export node
        sed "s/%%DBNODE%%/db-${node}/g" mariadb.yml > ${node}.yml
        docker-compose -f ${__root}/compose/mariadb/${node}.yml up -d --no-recreate
    done
fi

while [[ ! $(docker logs db-${node} 2>&1 |grep "Synchronized with group, ready for connections") ]] ; do
    echo "Waiting for ${nodelist[0]}/db to become available"
    sleep 10
done

sec_nodelist="${nodelist[@]:1}"
for node in ${sec_nodelist} ; do
    cluster_members=$(printf ",db-%s" "${nodelist[@]}")
    export cluster_members=${cluster_members:1}
    export node
    echo "Building ${node} mariadb instance..."
    eval $(docker-machine env ${node})
    sed "s/%%DBNODE%%/db-${node}/g" mariadb.yml > ${node}.yml
    docker-compose -f ${__root}/compose/mariadb/${node}.yml up -d --no-recreate
done

echo "Done"
