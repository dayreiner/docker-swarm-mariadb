#!/bin/bash

#set -o xtrace # uncomment for debug

# Strict modes. Same as -euo pipefail
set -o errexit
set -o pipefail
set -o nounset

./destroy_cluster.sh
./build_cluster.sh
