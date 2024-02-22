#!/bin/bash
#

# -------------------------------------------------------------------------- #
# Copyright 2015-2024, StorPool (storpool.com)                               #
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

# a tool to check the VM Snapshots and the corresponding StorPool Snapshots
# for (in)consistency:
# - list.missing contains the StorPool Snapshots that are not VM Snapsots
# - list.unknown contains the VM Snapshots that had no StorPool Snapshots
#
# The script should be called on the (leader) frontend node

set -e -o pipefail

storpool -Bj snapshot list | jq -r '.data[]|.name' >list.snapshots

onevm list -x | xmlstarlet sel -t -m "//VM" -v ID -n >list.vms

:>list.known
:>list.unknown

while read -u 4 vmid; do
    while read -u 5 snap; do
        grep -q "$snap" list.snapshots && echo "$snap" >>list.known || echo "$snap $vmid" >>list.unknown
    done 5< <(onevm show "$vmid" --xml | xmlstarlet sel -t -m "//TEMPLATE/SNAPSHOT" -v HYPERVISOR_ID -n)
done 4< <(cat list.vms)

grep -v -f list.known list.snapshots >list.missing

