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

TMP_DIR="$(mktemp -d)"
trapAdd "rm -rf '${TMP_DIR}'"

vmPoolXml="${TMP_DIR}/vmPool.xml"
dsPoolXml="${TMP_DIR}/dsPool.xml"
snapshotsJson="${TMP_DIR}/snapshots.json"

${SUDO:-sudo} onevm list -x --extended >"${vmPoolXml}"
${SUDO:-sudo} onedatastore list -x >"${dsPoolXml}"
${SUDO:-sudo} storpool -B -j snapshot list >"${snapshotsJson}"

declare -A datastoreSpAuthToken  # datastoreSpAuthToken[DATASTORE_ID]=SP_AUTH_TOKEN
declare -A datastoreSpApiHttpHost  # datastoreSpApiHttpHost[DATASTORE_ID]=SP_API_HTTP_HOST
declare -A datastoreSpApiHttpPort  # datastoreSpApiHttpPort[DATASTORE_ID]=SP_API_HTTP_PORT

while read -r -u "${vmfd}" VM_ID; do
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

    for volume in ${vmVolumes}; do
        if [[ "${volume%iso}" == "${volume}" ]]; then
            storpoolVolumeTag "${volume}" "one;${LOC_TAG_VAL};${VM_ID};${VC_POLICY}" "virt;${LOC_TAG:-nloc};${VM_TAG:-nvm};${VC_POLICY:+vc-policy}"
            while read -r -u "${snapfd}" snap; do
                storpoolSnapshotTag "${snap}" "one;${LOC_TAG_VAL};${VM_ID}" "virt;${LOC_TAG:-nloc};${VM_TAG}"
            done {snapfd}< <( jq -r --arg name "${volume}-ONESNAP" ".data[]|select(.name|startswith(\$name))|.name" "${snapshotsJson}" || true)
        else
            echo "# skipping ${volume}"
        fi
    done
done {vmfd}< <(xmlstarlet sel -t -m //VM -v ID -n "${vmPoolXml}" || true)
