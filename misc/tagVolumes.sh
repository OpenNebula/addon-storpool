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

# shellcheck source=tm/storpool/storpool_common.sh
source "${ONE_PATH}/tm/storpool/storpool_common.sh"

LOG_PREFIX="misc"
export LOG_PREFIX

vmPoolXml="${TMPDIR:-/tmp}/vmPool.xml"
dsPoolXml="${TMPDIR:-/tmp}/dsPool.xml"
snapshotsJson="${TMPDIR:-/tmp}/snapshots.json"

oneCallXml onevm list --extended "${vmPoolXml}"
oneCallXml onedatastore list "${dsPoolXml}"

declare -A datastoreSpAuthToken  # datastoreSpAuthToken[DATASTORE_ID]=SP_AUTH_TOKEN
declare -A datastoreSpApiHttpHost  # datastoreSpApiHttpHost[DATASTORE_ID]=SP_API_HTTP_HOST
declare -A datastoreSpApiHttpPort  # datastoreSpApiHttpPort[DATASTORE_ID]=SP_API_HTTP_PORT

while read -r -u "${vmfh}" VM_ID; do
    vmVolumes=
    oneVmVolumes "${VM_ID}" "${vmPoolXml}"
    echo "# VM ${VM_ID} SYSTEM_DS_ID=${VM_DS_ID} vmVolumes=${vmVolumes}"

    if [[ -z "${datastoreSpAuthToken["${VM_DS_ID}"]+found}" ]]; then
        oneDatastoreInfo "${VM_DS_ID}" "${dsPoolXml}"
        if [[ -n "${SP_AUTH_TOKEN}" ]]; then
            datastoreSpAuthToken["${VM_DS_ID}"]="${SP_AUTH_TOKEN}"
        fi
        if [[ -n "${SP_API_HTTP_HOST}" ]]; then
            datastoreSpApiHttpHost["${VM_DS_ID}"]="${SP_API_HTTP_HOST}"
        fi
        if [[ -n "${SP_API_HTTP_PORT}" ]]; then
            datastoreSpApiHttpPort["${VM_DS_ID}"]="${SP_API_HTTP_PORT}"
        fi
    fi

    if [[ -n "${datastoreSpAuthToken["${VM_DS_ID}"]}" ]]; then
        export SP_AUTH_TOKEN="${datastoreSpAuthToken["${VM_DS_ID}"]}"
    else
        unset SP_AUTH_TOKEN
    fi
    if [[ -n "${datastoreSpApiHttpHost["${VM_DS_ID}"]}" ]]; then
        export SP_API_HTTP_HOST="${datastoreSpApiHttpHost["${VM_DS_ID}"]}"
    else
        unset SP_API_HTTP_HOST
    fi
    if [[ -n "${datastoreSpApiHttpPort["${VM_DS_ID}"]}" ]]; then
        export SP_API_HTTP_PORT="${datastoreSpApiHttpPort["${VM_DS_ID}"]}"
    else
        unset SP_API_HTTP_PORT
    fi

    snapshotsJsonFile="${snapshotsJson}-${SP_API_HTTP_HOST:-0.0.0.0}"
    if [[ ! -f "${snapshotsJsonFile}" ]]; then
        storpool -B -j snapshot list >"${snapshotsJsonFile}"
    fi

    for volume in ${vmVolumes}; do
        if [[ "${volume%iso}" == "${volume}" ]]; then
            storpoolVolumeTag "${volume}" "virt;${LOC_TAG:-nloc};${VM_TAG:-nvm};${VC_POLICY:+vc-policy}" "one;${LOC_TAG_VAL};${VM_ID};${VC_POLICY}"
            while read -r -u "${snapfh}" snap; do
                storpoolSnapshotTag "${snap}" "virt;${LOC_TAG:-nloc};${VM_TAG}" "one;${LOC_TAG_VAL};${VM_ID}"
            done {snapfh}< <( jq -r --arg name "${volume}-ONESNAP" ".data[]|select(.name|startswith(\$name))|.name" "${snapshotsJsonFile}" || true)
        else
            echo "# skipping ${volume}"
        fi
    done
done {vmfh}< <(xmlstarlet sel -t -m //VM -v ID -n "${vmPoolXml}" || true)
