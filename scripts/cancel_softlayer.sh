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

# Cancel swarm instances using slcli

re=$(tput setaf 1)
wh=$(tput setaf 7)
nor=$(tput sgr0)
echo
echo "########################################################"
echo "#     ${wh}ATTENTION - THIS WILL CANCEL ALL SWARM VM'S${nor}      #"
echo "########################################################"
echo
echo "All data on the cancelled systems will be lost."
echo
echo "${wh}The following instances will be cancelled:"
echo
echo "${re}${nodelist[@]}${nor}"
echo

read -p "Are you sure you wish to continue? Type ${re}CANCEL${nor} to initiate cancellations: " answer
case ${answer} in
    CANCEL)
    echo "OK, going to cancel nodes: ${re}${nodelist[@]}${nor}"
;;
*)
    echo "Aborting cancellation. No instances will be destroyed..."
    exit
;;
esac

[[ ! -f /usr/bin/expect ]] && echo "Please install expect to continue..." && exit 1
for node in ${nodelist[@]} ; do
    # Try to avoid collateral damage. Abort if we get anything other than a single hit.
    export uniq_check=$(slcli vs list | grep ${node} || true | wc -l)
    if [[ ${uniq_check} = 0 ]] ; then
        echo "Match for ${node} not found. Exiting"
        exit 1
    elif [[ ${uniq_check} > 1 ]] ; then
        echo "More than one match for ${node} found. Exiting."
        exit 1
    else
	echo "Found exactly one match, continuing"
    fi
    # OK to go...
    node_id=$(slcli vs list | grep ${node} | awk '{print $1}')
    echo
    echo "Cancelling ${node}..."
    /usr/bin/expect <<- EOF
	set force_conservative 0
	set timeout 10
	spawn slcli vs cancel ${node}
	expect "Enter to abort: "
	send -- "${node_id}\r";
	expect eof
	EOF
    echo "########## Cancellation of node ${node} complete!"
    echo
done

echo "
