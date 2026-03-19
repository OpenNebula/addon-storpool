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
# A helper script to print StorPool commands to tag The VM volumes
# Should be run in the front-end node
#

set -e -o pipefail

ONE_PATH="${ONE_PATH:-/var/lib/one/remotes}"

cd "${ONE_PATH}/tm/storpool"

# shellcheck source=tm/storpool/storpool_common.sh
source "${ONE_PATH}/tm/storpool/storpool_common.sh"

snapshotsJson="${TMPDIR}/snapshots.json"
vmPoolXml="${TMPDIR}/vmPool.xml"
dsPoolXml="${TMPDIR}/dsPool.xml"

oneCallXml onevm list --extended "${vmPoolXml}"
oneCallXml onedatastore list "" "${dsPoolXml}"

storpool -B -j snapshot list >"${snapshotsJson}" # TBD remove

declare -i VM_ID
while read -r -u "${vmfh}" -d' ' VM_ID; do
    vmVolumes=
    oneVmVolumes "${VM_ID}" "${vmPoolXml}"
    echo "# VM ${VM_ID} SYSTEM_DS_ID=${VM_DS_ID} vmVolumes=${vmVolumes}"
    unset disks_a disksType_a
    declare -A disks_a disksType_a
    for entry in ${vmDisksMap}; do
        disks_a["${entry%%:*}"]="${entry#*:}"
    done
    for entry in ${vmDisksTypeMap}; do
        disksType_a["${entry%%:*}"]="${entry#*:}"
    done
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
        ret=$?
        if [[ ${ret} -ne 0 ]]; then
            splog "Can't get snapshot list from ${SP_API_HTTP_HOST:-0.0.0.0}"
            exit 1
        fi
    fi

    for vol in ${vmVolumes}; do
        if [[ "${vol%iso}" == "${vol}" ]]; then
            storpoolVolumeTag "${vol}" \
                "virt;${LOC_TAG:-nloc}:${VM_TAG:-nvm};diskid;type" \
                "one;${LOC_TAG_VAL}:${VM_ID};${disks_a["${vol}"]};${disksType_a["${vol}"]}"
            while read -r -u 5 snap; do
                storpoolSnapshotTag "${snap}" \
                    "virt;${LOC_TAG:-nloc};${VM_TAG:-nvm};diskid;type" \
                    "one;${LOC_TAG_VAL};${VM_ID};${disks_a["${vol}"]};${disksType_a["${vol}"]}"
            done 5< <( jq -r --arg n "${vol}-ONESNAP" '.data[]|select(.name|startswith($n))|.name' "${snapshotsJson}" || true)
        else
            echo "# skipping ${vol}"
        fi
    done
done {vmfh}< <(xmlstarlet sel -t -m //VM -v ID -n "${vmPoolXml}" || true)
exec {vmfh}<&-
rm -f "${snapshotsJson}" "${vmPoolXml}" "${dsPoolXml}"
