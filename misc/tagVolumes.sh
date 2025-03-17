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
#

#
# A helper script to print StorPool commands to tag The VM volumes
# Should be run in the front-end node
#

set -e -o pipefail

ONE_PATH="${ONE_PATH:-/var/lib/one/remotes}"

cd "${ONE_PATH}/tm/storpool"

source "${ONE_PATH}/tm/storpool/storpool_common.sh"

TMP_DIR="$(mktemp -d)"
trapAdd "rm -rf '${TMP_DIR}'"

vmPool="${TMP_DIR}/vmPool.xml"
dsPool="${TMP_DIR}/dsPool.xml"

${SUDO:-sudo} onevm list -x --extended >"${vmPool}"
${SUDO:-sudo} onedatastore list -x >"${dsPool}"

snapshots_json="${TMP_DIR}/snapshots.json"
${SUDO:-sudo} storpool -B -j snapshot list >"${snapshots_json}"


functions volumes_qos
{
    unset vols
    declare -A vols  # vols[VolumeName]=DISK_ID
    for disk in ${vmDisksMap:-}; do
        volume="${disk%:*}"
        vols["${volume}"]="${disk#*:}"  # [VOLUME_NAME]=DISK_ID
    done

    unset volumesQc
    declare -A volumesQc  # volumesQc[VOLUME_NAME]=QosClassName
    for vol in ${vmDisksQcMap:-}; do
        volumesQc["${vol%%:*}"]="${vol#*:}"  # [VOLUME_NAME]=QOSCLASS
    done

    declare -A persistentDisksQc  # persistentDisksQc[VOLUME_NAME]=QOSCLASS
    for vol in ${persistentDisksQcMap:-}; do
        persistentDisksQc["${vol%%:*}"]="${vol#*:}"  # [VOLUME_NAME]=QOSCLASS
    done

    declare -A diskType  # diskType[VOLUME_NAME]=DISK_TYPE
    for vol in ${vmDiskTypeMap:-}; do
        diskType["${vol%%:*}"]="${vol#*:}"  # [VOLUME_NAME]=DISK_TYPE
    done

}

declare -A datastoresQc  # datastoresQc[DATASTORE_ID]=QosClassName
declare -A datastoresSpAuthTokens  # datastoresSpAuthTokens[DATASTORE_ID]=SP_AUTH_TOKEN
declare -A datastoresSpApiHttpHosts  # datastoresSpApiHttpHosts[DATASTORE_ID]=SP_API_HTTP_HOST
declare -A datastoresSpApiHttpPorts  # datastoresSpApiHttpPorts[DATASTORE_ID]=SP_API_HTTP_PORT

while read -r -u 4 -d' ' VM_ID; do
    SP_QOSCLASS=""
    vmVolumes=
    oneVmVolumes "${VM_ID}" "${vmPool}"
    echo "# VM_ID=${VM_ID} vmVolumes=${vmVolumes}${vmVolumesQc:+, vmVolumesQc=${vmVolumesQc}}"
    # QoS Begin
    unset volumesDsIds
    declare -A volumesDsIds  # volumesDsIds[VOLUME_NAME]=DATASTORE_ID
    for entry in ${vmDisksDsMap:-}; do
        volume="${entry%%:*}"
        dsId="${entry#*:}"
        if [[ -z "${datastoresQc[${dsId}+found]}" ]] || [[ -z "${datastoresSpAuthTokens[${dsId}+found]}" ]]; then
            oneDatastoreInfo "${dsId}" "${dsPoolFile}"
            datastoresQc["${dsId}"]="${DS_SP_QOSCLASS}"  # [DATASTORE_ID]=DS_SP_QOSCLASS
            if [[ -n "${SP_AUTH_TOKEN}" ]]; then
                datastoresSpAuthTokens["${dsId}"]="${SP_AUTH_TOKEN}"
            fi
            if [[ -n "${SP_API_HTTP_HOST}" ]]; then
                datastoresSpApiHttpHosts["${dsId}"]="${SP_API_HTTP_HOST}"
            fi
            if [[ -n "${SP_API_HTTP_PORT}" ]]; then
                datastoresSpApiHttpPorts["${dsId}"]="${SP_API_HTTP_PORT}"
            fi
        fi
        volumesDsIds["${volume}"]="${dsId}"  # [VOLUME_NAME]=DATASTORE_ID
    done

    unset vols
    declare -A vols  # vols[VolumeName]=DISK_ID
    for disk in ${vmDisksMap:-}; do
        volume="${disk%:*}"
        vols["${volume}"]="${disk#*:}"  # [VOLUME_NAME]=DISK_ID
    done

    unset volumesQc
    declare -A volumesQc  # volumesQc[VOLUME_NAME]=QosClassName
    for vol in ${vmDisksQcMap:-}; do
        volumesQc["${vol%%:*}"]="${vol#*:}"  # [VOLUME_NAME]=QOSCLASS
    done

    declare -A persistentDisksQc  # persistentDisksQc[VOLUME_NAME]=QOSCLASS
    for vol in ${persistentDisksQcMap:-}; do
        persistentDisksQc["${vol%%:*}"]="${vol#*:}"  # [VOLUME_NAME]=QOSCLASS
    done

    declare -A diskType  # diskType[VOLUME_NAME]=DISK_TYPE
    for vol in ${vmDiskTypeMap:-}; do
        diskType["${vol%%:*}"]="${vol#*:}"  # [VOLUME_NAME]=DISK_TYPE
    done
    # QoS End

    for vol in ${vmVolumes}; do
        if [[ "${vol%iso}" == "${vol}" ]]; then
            storpoolVolumeTag "${vol}" "one;${LOC_TAG_VAL}:${VM_ID};${VC_POLICY};${SP_QOSCLASS}" "virt;${LOC_TAG:-nloc}:${VM_TAG:-nvm};${VC_POLICY:+vc-policy};${SP_QOSCLASS:+qc}"
            while read -r -u 5 snap; do
                storpoolSnapshotTag "${snap}" "one;${LOC_TAG_VAL};${VM_ID}" "virt;${LOC_TAG:-nloc};${VM_TAG}"
            done 5< <( jq -r --arg n "${vol}-ONESNAP" ".data[]|select(.name|startswith(\$n))|.name" "${snapshots_json}" || true)
        else
            echo "# skipping ${vol}"
        fi
    done
done 4< <("${ONE_PATH}/datastore/xpath.rb" --stdin %m%/VM_POOL/VM/ID <"${vmPool}" || true)
