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


function splog()
{
    echo ">>>$*"    
}
function boolTrue()
{
   case "${!1^^}" in
       1|Y|YES|TRUE|ON)
           return 0
           ;;
       *)
           return 1
   esac
}
oneVmVolumes()
{
    local VM_ID="$1" VM_POOL_FILE="$2"
    tmpXML="${VM_POOL_FILE}-${VM_ID}"

    xmllint -xpath "/VM_POOL/VM[ID=$VM_ID]" "$VM_POOL_FILE" >"$tmpXML"
    ret=$?
    if [ $ret -ne 0 ]; then
        errmsg="(oneVmVolumes) Error: Can't get VM info! $(head -n 1 "$tmpXML") (ret:$ret)"
        splog "$errmsg"
        exit $ret
    fi

    unset XPATH_ELEMENTS i
    while read element; do
        XPATH_ELEMENTS[i++]="$element"
    done < <(cat "$tmpXML" |\
        ${ONE_PATH}/datastore/xpath_multi.py -s \
        /VM/HISTORY_RECORDS/HISTORY[last\(\)]/DS_ID \
        /VM/TEMPLATE/CONTEXT/DISK_ID \
        /VM/TEMPLATE/DISK/DISK_ID \
        /VM/TEMPLATE/DISK/CLONE \
        /VM/TEMPLATE/DISK/FORMAT \
        /VM/TEMPLATE/DISK/TYPE \
        /VM/TEMPLATE/DISK/TM_MAD \
        /VM/TEMPLATE/DISK/TARGET \
        /VM/TEMPLATE/DISK/IMAGE_ID \
        /VM/TEMPLATE/SNAPSHOT/SNAPSHOT_ID \
        /VM/USER_TEMPLATE/VMSNAPSHOT_LIMIT \
        /VM/USER_TEMPLATE/DISKSNAPSHOT_LIMIT \
        /VM/USER_TEMPLATE/VC_POLICY)
    rm -f "$tmpXML"
    unset i
    VM_DS_ID="${XPATH_ELEMENTS[i++]}"
    local CONTEXT_DISK_ID="${XPATH_ELEMENTS[i++]}"
    local DISK_ID="${XPATH_ELEMENTS[i++]}"
    local CLONE="${XPATH_ELEMENTS[i++]}"
    local FORMAT="${XPATH_ELEMENTS[i++]}"
    local TYPE="${XPATH_ELEMENTS[i++]}"
    local TM_MAD="${XPATH_ELEMENTS[i++]}"
    local TARGET="${XPATH_ELEMENTS[i++]}"
    local IMAGE_ID="${XPATH_ELEMENTS[i++]}"
    local SNAPSHOT_ID="${XPATH_ELEMENTS[i++]}"
    local _TMP=
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [ -n "$_TMP" ] && [ "${_tmp//[[:digit:]]/}" = "" ]; then
        VM_VMSNAPSHOT_LIMIT="${_TMP}"
    fi
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [ -n "$_TMP" ] && [ "${_tmp//[[:digit:]]/}" = "" ]; then
        DISKSNAPSHOT_LIMIT="${_TMP}"
    fi
    VC_POLICY="${XPATH_ELEMENTS[i++]}"
    local IMG=
    _OFS=$IFS
    IFS=';'
    DISK_ID_A=($DISK_ID)
    CLONE_A=($CLONE)
    FORMAT_A=($FORMAT)
    TYPE_A=($TYPE)
    TM_MAD_A=($TM_MAD)
    TARGET_A=($TARGET)
    IMAGE_ID_A=($IMAGE_ID)
    SNAPSHOT_ID_A=($SNAPSHOT_ID)
    IFS=$_OFS
    for ID in ${!DISK_ID_A[@]}; do
        IMAGE_ID="${IMAGE_ID_A[$ID]}"
        CLONE="${CLONE_A[$ID]}"
        FORMAT="${FORMAT_A[$ID]}"
        TYPE="${TYPE_A[$ID]}"
        TM_MAD="${TM_MAD_A[$ID]}"
        TARGET="${TARGET_A[$ID]}"
        DISK_ID="${DISK_ID_A[$ID]}"
        if [ "${TM_MAD:0:8}" != "storpool" ]; then
            splog "DISK_ID:$DISK_ID TYPE:$TYPE TM_MAD:$TM_MAD "
            if ! boolTrue "SYSTEM_COMPATIBLE_DS[$TM_MAD]"; then
                oneVmVolumesNotStorPool="$TM_MAD:disk.$DISK_ID"
                continue
            fi
        fi
        IMG="${ONE_PX}-img-$IMAGE_ID"
        if [ -n "$IMAGE_ID" ]; then
            if boolTrue "CLONE"; then
                IMG+="-$VM_ID-$DISK_ID"
            elif [ "$TYPE" = "CDROM" ]; then
                IMG+="-$VM_ID-$DISK_ID"
            fi
        else
            case "$TYPE" in
                swap)
                    IMG="${ONE_PX}-sys-${VM_ID}-${DISK_ID}-swap"
                    ;;
                *)
                    IMG="${ONE_PX}-sys-${VM_ID}-${DISK_ID}-${FORMAT:-raw}"
            esac
        fi
        vmVolumes+="$IMG "
        if boolTrue "DEBUG_oneVmVolumes"; then
            splog "oneVmVolumes() VM_ID:$VM_ID disk.$DISK_ID $IMG"
        fi
        vmDisks=$((vmDisks+1))
        vmDisksMap+="$IMG:$DISK_ID "
    done
    DISK_ID="$CONTEXT_DISK_ID"
    if [ -n "$DISK_ID" ]; then
        IMG="${ONE_PX}-sys-${VM_ID}-${DISK_ID}-iso"
        vmVolumes+="$IMG "
        if boolTrue "DEBUG_oneVmVolumes"; then
            splog "oneVmVolumes() VM_ID:$VM_ID disk.$DISK_ID $IMG"
        fi
    fi
    if boolTrue "DEBUG_oneVmVolumes"; then
        splog "oneVmVolumes() VM_ID:$VM_ID VM_DS_ID=$VM_DS_ID${VMSNAPSHOT_LIMIT:+ VMSNAPSHOT_LIMIT=$VMSNAPSHOT_LIMIT}${DISKSNAPSHOT_LIMIT:+ DISKSNAPSHOT_LIMIT=$DISKSNAPSHOT_LIMIT}${VC_POLICY:+ VC_POLICY=$VC_POLICY}"
    fi
}


TMP_DIR="$(mktemp -d)"
trapAdd 'rm -rf "$TMP_DIR"'

echo -n "*** StorPool Volumes JSON " >&2
spVols="$TMP_DIR/spVols.json"
$SUDO storpool -Bj volume list >"$spVols"
echo "($?)" >&2

echo -n "*** StorPool Snapshots JSON " >&2
spSnaps="$TMP_DIR/spSnaps.json"
$SUDO storpool -Bj snapshot list >"$spSnaps"
echo "($?)" >&2

echo -n "*** OpenNebula VM extended XML " >&2
vmPool="$TMP_DIR/vmPool.xml"
$SUDO onevm list -x --extended >"$vmPool"
echo "($?)" >&2

echo -n "*** OpenNebula Images XML " >&2
imagePool="$TMP_DIR/imagePool.xml"
$SUDO oneimage list -x >"$imagePool"
echo "($?)" >&2

declare -A oneVol oneVolSize spVol oneImg oneImgType spParent

while read -u 4 NAME SIZE PARENT; do
    if [ -n "$PARENT" ]; then
        spParent["$PARENT"]="$NAME"
    fi
    if boolTrue "DEBUG"; then
        echo "spvolume,$NAME,$SIZE,parent,$PARENT"
    fi
    spVol["$NAME"]=$SIZE
done 4< <( jq -r '.data[]|
           (.name|tostring)
           + " " + (.size|tostring)
           + " " + (.parentName|tostring)
           ' "$spVols" )

echo "*** Processing Image Pool ..." >&2
unset i x
while read -u 4 -r e; do
    x[i++]="$e"
done 4< <(cat "$imagePool" | $ONE_PATH/datastore/xpath_multi.py -s \
		/IMAGE_POOL/IMAGE/ID \
                /IMAGE_POOL/IMAGE/SIZE \
                /IMAGE_POOL/IMAGE/PERSISTENT)
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

echo "*** Processing Image Pool data ..." >&2
for i in ${!IMAGE_ID_A[*]}; do
    ID=${IMAGE_ID_A[i]}
    SIZE=${IMAGE_SIZE_A[i]}
    TYPE=${IMAGE_TYPE_A[i]}
    VOLUME="${ONE_PX}-img-$ID"
    [ "$TYPE" = "0" ] && T="Non-Persistent" || T="Persistent"
    if boolTrue "DEBUG"; then
        echo "imagePool,$ID,$VOLUME,$SIZE,$T"
    fi
    oneImgType["$VOLUME"]="$T"
    oneImg["$VOLUME"]="$SIZE"
done

echo "*** Processing VM disks ..." >&2
diskSum=0
while read -u 4 -d' ' VM_ID; do
    vmVolumes=
    oneVmVolumes "$VM_ID" "$vmPool"
    for VOL in $vmVolumes; do
        PARENT=
        if [ -n "${oneImg["$VOL"]}" ]; then
            TYPE=Persistent
        elif [ "${VOL/sys}" = "$VOL" ]; then
            va=(${VOL//-/ })
            IMG_ID=${va[2]}
            TYPE=Non-persistent
            PARENT="${ONE_PX}-img-${IMG_ID}"
            if [ -n "${oneImg["$PARENT"]}" ]; then
                unset oneImg[$PARENT]
            fi
        else
            TYPE=Volatile
        fi
        SIZE=${spVol["$VOL"]:-0}
        if ! boolTrue "VMDISKS_HIDE_VM_DISKS"; then
            echo "vm,$VM_ID,$VOL,$SIZE,$TYPE,$PARENT"
        fi
        oneVol["$VOL"]=$VM_ID
        diskSum=$((diskSum + SIZE))
    done
done 4< <(cat "$vmPool"|$ONE_PATH/datastore/xpath.rb --stdin %m%/VM_POOL/VM/ID;echo " ")
echo "VMDISKS: $diskSum // $((diskSum/1024**3)) GiB"

imgSum=0
for v in ${!oneImg[*]}; do
    [ -z "${oneVol["$v"]}" ] || continue
    [ "${v#$ONE_PX}" = "$v" ] && TYPE=other || TYPE=ONE
    [ $TYPE = ONE ] || continue
    SIZE=${spVol[$v]}
    echo "image,$v,$SIZE,${oneImgType[$v]}"
    imgSum=$((imgSum + SIZE))
done
echo "IMAGES: $imgSum // $((imgSum/1024**3)) GiB"

volSum=0
for v in ${!spVol[*]}; do
  [ -z "${oneVol[$v]}" ] || continue
  [ -z "${oneImgType[$v]}" ] || continue
  SIZE=${spVol[$v]}
  echo "volume,$v,$SIZE"
  volSum=$((volSum + SIZE))
done
echo "VOLUMES: $volSum // $((volSum/1024**3)) GiB"

while read -u 4 NAME SIZE PARENT; do
    if [ -n "$PARENT" ]; then
        spParent["$PARENT"]="$NAME"
    fi
    if boolTrue "DEBUG"; then
        echo "spsnapshot,$NAME,$SIZE,parent,$PARENT"
    fi
done 4< <( jq -r --arg p "$ONE_PX" '.data[]|
           select(.transient==false)|
           select(.name|startswith($p))|
           select(.onVolume=="-")|
           (.name|tostring)
           + " " + (.size|tostring)
           + " " + (.parentName|tostring)
           ' "$spSnaps" )

echo "*** Processing VM Snapshots ..." >&2
declare -A vmSnaps
while read -u 4 -d' ' e; do
    if [ -n "$e" ]; then
        vmSnaps["$e"]="$e"
    fi
done 4< <(cat "$vmPool"|$ONE_PATH/datastore/xpath.rb --stdin %m%/VM_POOL/VM/TEMPLATE/SNAPSHOT/HYPERVISOR_ID;echo " ")

echo "*** Processing StorPool Snapshots ..." >&2
snapSum=0
while read -u 4 NAME SIZE PARENT; do
    if [ -n "${spParent["$NAME"]}" ]; then
        if boolTrue "DEBUG"; then
            echo ">>>skip $NAME has child ${spParent["$NAME"]}" >&2
        fi
        continue
    fi
    hid="ONESNAP${NAME#*ONESNAP}"
    if [ -n "${vmSnaps["$hid"]}" ]; then
        if boolTrue "DEBUG"; then
            echo ">>>skip $NAME is VM snapshot $hid" >&2
        fi
        continue
    fi
    echo "snapshot,$NAME,$SIZE"
    snapSum=$((snapSum + SIZE))
done 4< <( jq -r --arg p "$ONE_PX" '.data[]|
           select(.transient==false)|
           select(.name|startswith($p))|
           select(.onVolume=="-")|
           (.name|tostring)
           + " " + (.size|tostring)
           + " " + (.parentName|tostring)
           ' "$spSnaps" )
echo "SNAPSHOTS: $snapSum // $((snapSum/1024**3)) GiB"

