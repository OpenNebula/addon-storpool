#!/bin/bash
#
# -------------------------------------------------------------------------- #
# Copyright 2015-2022, StorPool (storpool.com)                               #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #
#

#
# A helper script to print StorPool commands to tag The VM volumes
# Should be run in the front-end node
#

set -e -o pipefail

ONE_PATH="${ONE_PATH:-/var/lib/one/remotes}"

cd "$ONE_PATH/tm/storpool"

source "$ONE_PATH/tm/storpool/storpool_common.sh"

TMP_DIR="$(mktemp -d)"
trapAdd 'rm -rf "$TMP_DIR"'

vmPool="$TMP_DIR/vmPool.xml"

$SUDO onevm list -x --extended >"$vmPool"

snapshots_json="$TMP_DIR/snapshots.json"
$SUDO storpool -B -j snapshot list >"$snapshots_json"

while read -u 4 -d' ' VM_ID; do
    vmVolumes=
    oneVmVolumes "$VM_ID" "$vmPool"
    echo "# VM_ID=$VM_ID vmVolumes=$vmVolumes"
    for vol in $vmVolumes; do
        if [ "${vol%iso}" = "$vol" ]; then
            storpoolVolumeTag "$vol" "$VM_ID;${VC_POLICY};${SP_QOSCLASS}" "$VM_TAG;${VC_POLICY:+vc-policy};${SP_QOSCLASS:+qc}"
            while read -u 5 snap; do
                storpoolSnapshotTag "$snap" "$VM_ID" "$VM_TAG"
            done 5< <( jq -r --arg n "${vol}-ONESNAP" ".data[]|select(.name|startswith(\$n))|.name" "$snapshots_json")
        else
            echo "# skipping $vol"
        fi
    done
done 4< <(cat "$vmPool"| $ONE_PATH/datastore/xpath.rb --stdin %m%/VM_POOL/VM/ID)
