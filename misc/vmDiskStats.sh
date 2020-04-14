#!/bin/bash
#
# -------------------------------------------------------------------------- #
# Copyright 2015-2020, StorPool (storpool.com)                               #
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
# A helper script to print the VM volumes and their size in CSV
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

spVols="$TMP_DIR/spVols.json"
$SUDO storpool -Bj volume list >"$spVols"

imagePool="$TMP_DIR/imagePool.xml"
$SUDO oneimage list -x >"$imagePool"

declare -A oneVolumes oneVolumesSize spVolumes oneImages oneImagesSize

while read -u 4 v sz; do
#    echo "spvol,$v,$sz"
    spVolumes["$v"]=$sz
done 4< <( jq -r '.data[]|(.name|tostring) + " " + (.size|tostring)' "$spVols" )

unset i x
while read -u 4 -r e; do
    x[i++]="$e"
done 4< <(cat "$imagePool" | $ONE_PATH/datastore/xpath_multi.py -s \
		/VM_POOL/IMAGE/ID \
                /VM_POOL/IMAGE/SIZE \
                /VM_POOL/IMAGE/PERSISTENT)
unset i
_IMAGE_ID=${x[i++]}
_IMAGE_SIZE=${x[i++]}
_IMAGE_TYPE=${x[i++]}
_OLDIFS=$IFS
IFS=";"
IMAGE_ID_A=($_IMAGE_ID)
IMAGE_SIZE_A=($_IMAGE_SIZE)
IMAGE_TYPE_A=($_IMAGE_TYPE)
IFS=$_OLDIFS

for i in ${!IMAGE_ID_A[*]}; do
    ID=${IMAGE_ID_A[i]}
    SIZE=${IMAGE_SIZE_A[i]}
    TYPE=${IMAGE_TYPE_A[i]}
    VOLUME="${ONE_PX}-img-$ID"
    [ "$TYPE" = "0" ] && T="Non-Persistent" || T="Persistent"
    if boolTrue "VMDISKS_SHOW_IMAGES"; then
        echo "image,$ID,$VOLUME,$SIZE,$T"
    fi
    oneImages["$VOLUME"]="$T"
done

while read -u 4 -d' ' VM_ID; do
    vmVolumes=
    oneVmVolumes "$VM_ID" "$vmPool"
    for VOL in $vmVolumes; do
        #size=$(jq -r --arg v "$VOL" '.data[]|select(.name==$v)|.size' "$spVols")
        #echo "$VM_ID,$VOL,${size:-0}"
        if [ -n "${oneImages["$VOL"]}" ]; then
            TYPE=Persistent
        elif [ "${VOL/sys}" = "$VOL" ]; then
            TYPE=Non-persistent
        else
            TYPE=Volatile
        fi
        if ! boolTrue "VMDISKS_HIDE_VM_DISKS"; then
            echo "vm,$VM_ID,$VOL,${spVolumes["$VOL"]:-0},$TYPE"
        fi
        oneVolumes["$VOL"]=$VM_ID
    done
done 4< <(cat "$vmPool"| $ONE_PATH/datastore/xpath.rb --stdin %m%/VM_POOL/VM/ID)

if boolTrue "VMDISKS_SHOW_OTHER"; then
    for v in ${!spVolumes[*]}; do
        [ -z "${oneImages["$v"]}" ] || continue
        [ -z "${oneVolumes["$v"]}" ] || continue
        [ "${v#$ONE_PX}" = "$v" ] && TYPE=other || TYPE=ONE
        if boolTrue "VMDISKS_ORPHANS_ONLY"; then
            [ $TYPE = ONE ] || continue
        fi
        echo "volume,$v,${spVolumes[$v]},$TYPE"
    done
fi

