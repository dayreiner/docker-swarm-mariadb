#!/bin/bash
#set -o xtrace 

set -euo pipefail

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 

cd ${__dir}
./destroy_cluster.sh
./build_cluster.sh
