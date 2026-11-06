#!/bin/bash

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

# svc_extract.sh <backup image id> <kvm host> [output dir]
#
# Rebuild the front-end files of a StorPool backup (vm.xml, svc.tar) from the
# service snapshot its SOURCE names, when <BASE_PATH>/<vm>/<epoch>/ was lost.
# Runs on the front-end as oneadmin: the service snapshot is cloned, the clone
# is attached to <kvm host>, the tar is read there and shipped back, then the
# clone (and a pulled snapshot in remote mode) is deleted.

set -o pipefail

DRIVER_PATH="$(dirname "$0")"
export LOG_PREFIX="misc"
umask 077

# shellcheck source=tm/storpool/storpool_common.sh
source "${ONE_LOCATION:-/var/lib/one/remotes}/tm/storpool/storpool_common.sh"

IMG_ID="${1:-}"
KVMHOST="${2:-}"
OUT_DIR="${3:-}"

if [[ -z "${IMG_ID}" || -z "${KVMHOST}" ]]; then
    echo "Usage: ${0##*/} <backup image id> <kvm host> [output dir]" >&2
    exit 1
fi

oneBackupImageInfo "${IMG_ID}"
oneDatastoreInfo "${B_DATASTORE_ID:?}"
if [[ "${DS_DS_MAD}" != "storpool" ]]; then
    echo "Image ${IMG_ID} is on a ${DS_DS_MAD} backup datastore, not storpool" >&2
    exit 1
fi
if ! oneBackupSourceParse "${B_IMAGE_SOURCE}"; then
    echo "Image ${IMG_ID} SOURCE '${B_IMAGE_SOURCE}' is not a StorPool backup manifest" >&2
    exit 1
fi
SVC_ID="${BS_IDS_A[svc]:-}"
if [[ -z "${SVC_ID}" ]]; then
    echo "Backup ${B_IMAGE_SOURCE} has no service snapshot: vm.xml was kept on the front-end only" >&2
    exit 1
fi
[[ -n "${OUT_DIR}" ]] || OUT_DIR="${DS_BASE_PATH}/${BS_VM_ID}/${BS_EPOCH}"

TMP_NAME="$(mktemp --dry-run svcXXXXXXXX)"
SCRATCH_VOL="${ONE_PX}-sys-${BS_VM_ID}-SVC-extract-${TMP_NAME}"
SCRATCH_UID=""
PULL_UID=""
HOST_DIR="/var/tmp/${SCRATCH_VOL}"

function cleanup()
{
    if [[ -n "${SCRATCH_UID}" ]]; then
        storpoolDetach "${SCRATCH_UID}" "force" "" "all"
        DELAY_DELETE="" _SOFT_FAIL=1 storpoolDelete "${SCRATCH_UID}" "force"
    fi
    if [[ -n "${PULL_UID}" ]]; then
        storpoolPulledSnapshotDrop "${PULL_UID}"
    fi
    ssh_forward ssh_exec_and_log_no_error "${KVMHOST}" "rm -rf \"${HOST_DIR}\"" "Error removing ${HOST_DIR} on ${KVMHOST}"
}
trapAdd "cleanup"

# the VM and its system datastore may be gone (DR): the cluster's default template
TEMPLATE="$(spBackupPullTemplate "")"
if [[ "${BS_LOCATION}" == "local" ]]; then
    SNAP_UID="~${SVC_ID}"
    storpoolVolumeFromSnapshot "${SNAP_UID}" "${SCRATCH_VOL}" "${TEMPLATE}" \
        "img;${LOC_TAG};virt;${VM_TAG};type" "${SCRATCH_VOL};${LOC_TAG_VAL};one;${BS_VM_ID};SVC" || exit 1
else
    storpoolSnapshotPullRemote "${SCRATCH_VOL}-pull" "${SVC_ID}" "${BS_LOCATION}" "${TEMPLATE}" \
        "img;${LOC_TAG};virt;${VM_TAG}" "${SCRATCH_VOL}-pull;${LOC_TAG_VAL};one;${BS_VM_ID}" || exit 1
    SNAP_UID="${SP_UID}"
    [[ -n "${SP_PULL_REUSED}" ]] || PULL_UID="${SNAP_UID}"
    storpoolVolumeFromPulledSnapshot "${SNAP_UID}" "${SCRATCH_VOL}" "${TEMPLATE}" \
        "img;${LOC_TAG};virt;${VM_TAG};type" "${SCRATCH_VOL};${LOC_TAG_VAL};one;${BS_VM_ID};SVC" || exit 1
fi
SCRATCH_UID="${SP_UID}"
storpoolAttach "${SCRATCH_UID}" "${KVMHOST}"
ssh_forward ssh_exec_and_log "${KVMHOST}" "${REMOTE_HDR}
    rm -rf \"${HOST_DIR}\"
    mkdir -p \"${HOST_DIR}\"
    tar -xf \"/dev/storpool-byid/${SCRATCH_UID#*~}\" -C \"${HOST_DIR}\"
    tar -cf \"${HOST_DIR}/svc.tar\" -C \"${HOST_DIR}\" \$(cd \"${HOST_DIR}\" && ls | grep -v '^svc.tar\$')${REMOTE_FTR}" \
    "Error extracting the service tar of backup ${IMG_ID} on ${KVMHOST}"
mkdir -p "${OUT_DIR}"
"${RSYNC:-rsync}" -a "${KVMHOST}:${HOST_DIR}/vm.xml" "${KVMHOST}:${HOST_DIR}/svc.tar" "${OUT_DIR}/" || exit 1
ls -la "${OUT_DIR}"
splog "[I] backup ${IMG_ID} (${B_IMAGE_SOURCE}) files restored to ${OUT_DIR}"
echo "Files of backup ${IMG_ID} written to ${OUT_DIR}"
