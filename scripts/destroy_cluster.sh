#!/bin/bash

#set -o xtrace # uncomment for debug

# Strict modes. Same as -euo pipefail
set -o errexit
set -o pipefail
set -o nounset

# Set some magic vars
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

for node in ${nodelist[@]} ; do
 docker-machine scp ${__root}/scripts/instance/cleanup_generic.sh ${node}:/tmp
 docker-machine ssh ${node} "chmod +x /tmp/cleanup_generic.sh"
 docker-machine ssh ${node} "/tmp/cleanup_generic.sh"
 docker-machine rm -f -y ${node}
done
