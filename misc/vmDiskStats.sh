#!/bin/bash
#
# -------------------------------------------------------------------------- #
# Copyright 2015-2025, StorPool (storpool.com)                               #
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

cd "${ONE_PATH}/tm/storpool"
# shellcheck source=tm/storpool/storpool_common.sh
source "${ONE_PATH}/tm/storpool/storpool_common.sh"
# shellcheck source=addon-storpoolrc
source "${ONE_PATH}/addon-storpoolrc"

TMP_DIR="$(mktemp -d)"
trapAdd "rm -rf \"${TMP_DIR}\""

echo -n "*** StorPool Volumes JSON " >&2
spVols="${TMP_DIR}/spVols.json"
${SUDO:-} storpool -Bj volume list >"${spVols}"
echo "($?)" >&2

echo -n "*** StorPool Snapshots JSON " >&2
spSnaps="${TMP_DIR}/spSnaps.json"
${SUDO:-} storpool -Bj snapshot list >"${spSnaps}"
echo "($?)" >&2

echo -n "*** OpenNebula VM extended XML " >&2
vmPool="${TMP_DIR}/vmPool.xml"
${SUDO:-} onevm list -x --extended >"${vmPool}"
echo "($?)" >&2

echo -n "*** OpenNebula Images XML " >&2
imagePool="${TMP_DIR}/imagePool.xml"
${SUDO:-} oneimage list -x >"${imagePool}"
echo "($?)" >&2

declare -A oneVol spVol oneImg oneImgType spParent

# shellcheck disable=SC2312
while read -r -u 4 NAME SIZE PARENT; do
    if [[ -n "${PARENT}" ]]; then
        spParent["${PARENT}"]="${NAME}"
    fi
    # shellcheck disable=SC2310
    if boolTrue "DEBUG"; then
        echo "spvolume,${NAME},${SIZE},parent,${PARENT}"
    fi
    spVol["${NAME}"]="${SIZE}"
done 4< <( jq -r '.data[]|
           (.name|tostring)
           + " " + (.size|tostring)
           + " " + (.parentName|tostring)
           ' "${spVols}" )

echo "*** Processing Image Pool ..." >&2
unset i x
# shellcheck disable=SC2312
while read -r -u 4 e; do
    x[i++]="${e}"
done 4< <("${ONE_PATH}/datastore/xpath_multi.py" -s \
		/IMAGE_POOL/IMAGE/ID \
                /IMAGE_POOL/IMAGE/SIZE \
                /IMAGE_POOL/IMAGE/PERSISTENT < "${imagePool}" )
unset i
_IMAGE_ID="${x[i++]}"
_IMAGE_SIZE="${x[i++]}"
_IMAGE_TYPE="${x[i++]}"
_OLDIFS="${IFS}"
IFS=';'
IMAGE_ID_A=("${_IMAGE_ID}")
IMAGE_SIZE_A=("${_IMAGE_SIZE}")
IMAGE_TYPE_A=("${_IMAGE_TYPE}")
IFS="${_OLDIFS}"

echo "*** Processing Image Pool data ..." >&2
for i in ${!IMAGE_ID_A[*]}; do
    ID="${IMAGE_ID_A[i]}"
    SIZE="${IMAGE_SIZE_A[i]}"
    TYPE="${IMAGE_TYPE_A[i]}"
    VOLUME="${ONE_PX}-img-${ID}"
    [[ "${TYPE}" = "0" ]] && T="Non-Persistent" || T="Persistent"
    # shellcheck disable=SC2310
    if boolTrue "DEBUG"; then
        echo "imagePool,${ID},${VOLUME},${SIZE},${T}"
    fi
    oneImgType["${VOLUME}"]="${T}"
    oneImg["${VOLUME}"]="${SIZE}"
done

echo "*** Processing VM disks ..." >&2
diskSum=0
# shellcheck disable=SC2312
while read -r -u 4 -d' ' VM_ID; do
    vmVolumes=
    oneVmVolumes "${VM_ID}" "${vmPool}"
    for VOL in ${vmVolumes}; do
        PARENT=
        if [[ -n "${oneImg["${VOL}"]}" ]]; then
            TYPE=Persistent
        elif [[ "${VOL/sys}" = "${VOL}" ]]; then
            IFS='-' read -r -a va <<< "${VOL}"
            IMG_ID="${va[2]}"
            TYPE=Non-persistent
            PARENT="${ONE_PX}-img-${IMG_ID}"
            if [[ -n "${oneImg["${PARENT}"]}" ]]; then
                unset oneImg["${PARENT}"]
            fi
        else
            TYPE=Volatile
        fi
        SIZE="${spVol["${VOL}"]:-0}"
        # shellcheck disable=SC2310
        if ! boolTrue "VMDISKS_HIDE_VM_DISKS"; then
            echo "vm,${VM_ID},${VOL},${SIZE},${TYPE},${PARENT}"
        fi
        oneVol["${VOL}"]="${VM_ID}"
        diskSum=$((diskSum + SIZE))
    done
done 4< <("${ONE_PATH}/datastore/xpath.rb" --stdin %m%/VM_POOL/VM/ID < "${vmPool}"||true; echo " ")
echo "VMDISKS: ${diskSum} // $((diskSum/1024**3)) GiB"

imgSum=0
for v in ${!oneImg[*]}; do
    [[ -z "${oneVol["${v}"]}" ]] || continue
    [[ "${v#"${ONE_PX}"}" = "${v}" ]] && TYPE=other || TYPE=ONE
    [[ "${TYPE}" = "ONE" ]] || continue
    SIZE="${spVol["${v}"]}"
    echo "image,${v},${SIZE},${oneImgType["${v}"]}"
    imgSum=$((imgSum + SIZE))
done
echo "IMAGES: ${imgSum} // $((imgSum/1024**3)) GiB"

volSum=0
for v in ${!spVol[*]}; do
  [[ -z "${oneVol["${v}"]}" ]] || continue
  [[ -z "${oneImgType["${v}"]}" ]] || continue
  SIZE="${spVol["${v}"]}"
  echo "volume,${v},${SIZE}"
  volSum=$((volSum + SIZE))
done
echo "VOLUMES: ${volSum} // $((volSum/1024**3)) GiB"

# shellcheck disable=SC2312
while read -r -u 4 NAME SIZE PARENT; do
    if [[ -n "${PARENT}" ]]; then
        spParent["${PARENT}"]="${NAME}"
    fi
    # shellcheck disable=SC2310
    if boolTrue "DEBUG"; then
        echo "spsnapshot,${NAME},${SIZE},parent,${PARENT}"
    fi
done 4< <( jq -r --arg p "${ONE_PX}" '.data[]|
           select(.transient==false)|
           select(.name|startswith($p))|
           select(.onVolume=="-")|
           (.name|tostring)
           + " " + (.size|tostring)
           + " " + (.parentName|tostring)
           ' "${spSnaps}" )

echo "*** Processing VM Snapshots ..." >&2
declare -A vmSnaps
while read -r -u 4 -d' ' entry; do
    if [[ -n "${entry}" ]]; then
        vmSnaps["${entry}"]="${entry}"
    fi
done 4< <("${ONE_PATH}/datastore/xpath.rb" --stdin %m%/VM_POOL/VM/TEMPLATE/SNAPSHOT/HYPERVISOR_ID < "${vmPool}"||true; echo " ")

echo "*** Processing StorPool Snapshots ..." >&2
snapSum=0
# shellcheck disable=SC2312
while read -r -u 4 NAME SIZE PARENT; do
    if [[ -n "${spParent["${NAME}"]}" ]]; then
        # shellcheck disable=SC2310
        if boolTrue "DEBUG"; then
            echo ">>>skip ${NAME} has child ${spParent["${NAME}"]}" >&2
        fi
        continue
    fi
    hid="ONESNAP${NAME#*ONESNAP}"
    if [[ -n "${vmSnaps["${hid}"]}" ]]; then
        # shellcheck disable=SC2310
        if boolTrue "DEBUG"; then
            echo ">>>skip ${NAME} is VM snapshot ${hid}" >&2
        fi
        continue
    fi
    echo "snapshot,${NAME},${SIZE}"
    snapSum=$((snapSum + SIZE))
done 4< <( jq -r --arg p "${ONE_PX}" '.data[]|
           select(.transient==false)|
           select(.name|startswith($p))|
           select(.onVolume=="-")|
           (.name|tostring)
           + " " + (.size|tostring)
           + " " + (.parentName|tostring)
           ' "${spSnaps}" )
echo "SNAPSHOTS: ${snapSum} // $((snapSum/1024**3)) GiB"
