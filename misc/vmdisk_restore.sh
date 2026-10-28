#!/bin/bash
#
# -------------------------------------------------------------------------- #
# Copyright 2015-2026, StorPool (storpool.com)                               #
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
# Replace the StorPool volume behind a VM disk with a new volume created from
# a given StorPool snapshot (globalId).
#
# The new volume takes over the disk's OpenNebula identity: the etcd byName
# key is pointed at the new globalId, the old byUid key is removed, the volume
# is re-attached on the VM's host and the datastore symlink is refreshed. The
# old volume is disposed of through storpoolDelete, so DELAY_DELETE (when set)
# keeps a delayed-delete snapshot of it tagged reason=vmdisk_restore.
#
# A VolumeRevert is deliberately not used: it keeps the volume but changes its
# canonical globalId, leaving etcd on the preserved id. A fresh volume gives
# one object with one id.
#
# Usage: vmdisk_restore.sh [-n|--dry-run] [-f|--force] [-s|--snapshot-size] VM_ID DISK_ID SNAPSHOT_GLOBALID
#
#  -n, --dry-run        print what would be done and exit
#  -f, --force          proceed when the snapshot does not belong to the disk
#                       (img tag mismatch) or the old volume is attached to a
#                       client other than the VM's host
#  -s, --snapshot-size  adopt the snapshot's size and write it into the VM's
#                       DISK/SIZE; by default a smaller snapshot is grown back
#                       to the current volume size (the addon's revertSize:false
#                       behaviour) so OpenNebula's DISK/SIZE stays correct
#
# Run on the (leader) front-end as oneadmin. The VM must not be ACTIVE or
# SUSPENDED. In POWEROFF the volume is swapped on the VM's host; in the other
# states only StorPool and etcd are updated and the next prolog attaches the
# new volume.
#

set -o pipefail

ONE_PATH="${ONE_PATH:-/var/lib/one/remotes}"
export LOG_PREFIX="misc"

DRY_RUN=""
FORCE=""
SNAPSHOT_SIZE=""
POSITIONAL=()

function usage()
{
    sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run)
            DRY_RUN=1
            ;;
        -f|--force)
            FORCE=1
            ;;
        -s|--snapshot-size)
            SNAPSHOT_SIZE=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option '$1'" >&2
            usage >&2
            exit 2
            ;;
        *)
            POSITIONAL+=("$1")
            ;;
    esac
    shift
done

if [[ ${#POSITIONAL[@]} -ne 3 ]]; then
    usage >&2
    exit 2
fi

VM_ID="${POSITIONAL[0]}"
DISK_ID="${POSITIONAL[1]}"
SNAP_UID="${POSITIONAL[2]}"

if [[ -n "${VM_ID//[[:digit:]]/}" ]] || [[ -n "${DISK_ID//[[:digit:]]/}" ]]; then
    echo "VM_ID and DISK_ID must be numeric" >&2
    exit 2
fi
# globalIds only; accept with or without the leading '~'
SNAP_UID="~${SNAP_UID#\~}"
if [[ ! "${SNAP_UID}" =~ ^~[A-Za-z0-9]+\.[A-Za-z0-9]+\.[A-Za-z0-9]+$ ]]; then
    echo "'${SNAP_UID#\~}' does not look like a StorPool globalId (location.cluster.id)" >&2
    exit 2
fi

export VM_ID

cd "${ONE_PATH}/tm/storpool" || exit 1

# shellcheck source=/dev/null
source "${ONE_PATH}/scripts_common.sh"
# shellcheck source=tm/storpool/storpool_common.sh
source "${ONE_PATH}/tm/storpool/storpool_common.sh"

function msg()
{
    echo "$*"
    splog "$*"
}

function fail()
{
    local _rc="${1}"
    shift
    echo "Error: $*" >&2
    splog "[E] $*"
    exit "${_rc}"
}

msg "VM ${VM_ID} disk ${DISK_ID} restore from ${SNAP_UID}${DRY_RUN:+ (dry run)}${FORCE:+ (force)}${SNAPSHOT_SIZE:+ (snapshot size)}"

if ! isRaftLeader; then
    msg "[W] this front-end is not the RAFT leader (RAFT_LEADER_IP=${RAFT_LEADER_IP:-unset})"
fi

#-------------------------------------------------------------------------------
# OpenNebula side: VM state, host, the disk and its StorPool name
#-------------------------------------------------------------------------------

oneVmInfo "${VM_ID}" "${DISK_ID}"
VM_XML="${TMPDIR}/oneVmInfo-${VM_ID}.XML"

VM_HOST="$("${SPXML}" get "/VM/HISTORY_RECORDS/HISTORY[last()]/HOSTNAME" <"${VM_XML}" | tr -d '\0' || true)"

oneDatastoreInfo "${VM_DS_ID}"
SYSTEM_DS_BASE_PATH="${DS_BASE_PATH:-/var/lib/one/datastores/${VM_DS_ID}}"
SYSTEM_DS_SP_QOSCLASS="${DS_SP_QOSCLASS}"
MONITOR_TM_MAD=""
if ! boolTrue "DS_SHARED"; then
    MONITOR_TM_MAD="${DS_TM_MAD}"
fi

SP_QOSCLASS="${VM_DISK_SP_QOSCLASS:-${IMAGE_SP_QOSCLASS:-${VM_SP_QOSCLASS:-${SYSTEM_DS_SP_QOSCLASS:-${DEFAULT_QOSCLASS}}}}}"
# shellcheck disable=SC2034  # read by boolTrue through its name
DISK_READONLY="${READONLY^^}"
DISK_TYPE="${TYPE^^}"
BASE_IMAGE="${SOURCE##*/}"

# the StorPool name and type of the disk exactly as the drivers derive them
oneVmVolumes "${VM_ID}" "" "${VM_XML}"
SP_VOL=""
xTYPE=""
for _entry in ${vmDisksMap}; do
    [[ "${_entry##*:}" == "${DISK_ID}" ]] || continue
    SP_VOL="${_entry%:*}"
    break
done
if [[ -z "${SP_VOL}" ]]; then
    fail 1 "VM ${VM_ID} has no StorPool disk ${DISK_ID}${oneVmVolumesNotStorPool:+ (${oneVmVolumesNotStorPool})}"
fi
for _entry in ${vmDisksTypeMap}; do
    [[ "${_entry%:*}" == "${SP_VOL}" ]] || continue
    xTYPE="${_entry##*:}"
    break
done
case "${xTYPE}" in
    CDROM|IMMUT|CNTXT|NVRAM|CHKPNT)
        fail 1 "disk ${DISK_ID} (${SP_VOL}) is of type ${xTYPE}, not supported"
        ;;
    *)
        ;;
esac
if [[ "${DISK_TYPE}" == "CDROM" ]]; then
    fail 1 "disk ${DISK_ID} (${SP_VOL}) is a CDROM, not supported"
fi

SP_MODE="rw"
if boolTrue "DISK_READONLY"; then
    SP_MODE="${READONLY_MODE,,}"
fi

VM_STATE_NAME="${VmState[${VMSTATE}]:-${VMSTATE}}"
LCM_STATE_NAME="${LcmState[${LCM_STATE}]:-${LCM_STATE}}"
HAS_HOST=""
case "${VMSTATE}" in
    3)
        fail 1 "VM ${VM_ID} is ACTIVE (${LCM_STATE_NAME}); power it off first"
        ;;
    5)
        fail 1 "VM ${VM_ID} is SUSPENDED, the checkpoint references the disk; resume and power off first"
        ;;
    6|7)
        fail 1 "VM ${VM_ID} is ${VM_STATE_NAME}"
        ;;
    8)
        [[ -n "${VM_HOST}" ]] || fail 1 "VM ${VM_ID} is POWEROFF but has no host in its history"
        HAS_HOST=1
        ;;
    *)
        # never deployed, STOPPED, UNDEPLOYED, CLONING...: no attachment to
        # care about, the next prolog attaches and links the new volume
        ;;
esac

DST_PATH="${SYSTEM_DS_BASE_PATH}/${VM_ID}/disk.${DISK_ID}"

#-------------------------------------------------------------------------------
# StorPool side: the current volume and the source snapshot
#-------------------------------------------------------------------------------

kvGetUid "${SP_VOL}" fatal
OLD_UID="${SP_UID}"

OLD_UID_NAME="$(kvGet byUid "${OLD_UID}")"
if [[ "${OLD_UID_NAME}" != "${SP_VOL}" ]]; then
    fail 1 "etcd mismatch: byName/${SP_VOL}=${OLD_UID} but byUid/${OLD_UID}='${OLD_UID_NAME}'; fix the KV first (kvchk)"
fi

storpoolVolumeInfo "${OLD_UID}"
if [[ -z "${V_SIZE}" ]]; then
    fail 1 "volume ${OLD_UID} (${SP_VOL}) not found in StorPool"
fi
OLD_SIZE="${V_SIZE}"
OLD_TEMPLATE="${V_TEMPLATE_NAME}"
OLD_CLUSTER="${V_CLUSTER_ID}"
if [[ "${OLD_TEMPLATE}" == "null" ]]; then
    OLD_TEMPLATE=""
fi

if [[ "${SNAP_UID}" == "${OLD_UID}" ]]; then
    fail 1 "${SNAP_UID} is the disk's current volume, not a snapshot"
fi

if ! _SOFT_FAIL=1 storpoolSnapshotInfo "${SNAP_UID}"; then
    fail 1 "snapshot ${SNAP_UID} not found in StorPool"
fi
IFS=';' read -r SNAP_SIZE SNAP_CLUSTER SNAP_DELETED SNAP_IMG SNAP_VM <<< "$(jq -r \
    --arg vm_tag "${VM_TAG}" \
    '.data[0]|"\(.size|tostring);\(.clusterId);\(.deleted);\(.tags.img|tostring);\(.tags[$vm_tag]|tostring)"' \
    "${TMPDIR}/Snapshot.json" || true)"
if [[ -z "${SNAP_SIZE}" ]] || [[ "${SNAP_SIZE}" == "null" ]]; then
    fail 1 "can't read the size of snapshot ${SNAP_UID}"
fi
if [[ "${SNAP_DELETED}" == "true" ]]; then
    fail 1 "snapshot ${SNAP_UID} is deleted"
fi

# The API accepts any parent. Guard against a snapshot of another disk unless
# forced: the img tag of a disk's own snapshots is the disk name or a name
# derived from it (-snapN, -ONESNAP-..., -TEMP-..., delayed-delete), and for
# a cloned disk the base image or its snapshots are legitimate too.
SNAP_OWNER=""
if [[ "${SNAP_IMG}" == "${SP_VOL}" ]] || [[ "${SNAP_IMG}" == "${SP_VOL}-"* ]]; then
    SNAP_OWNER="disk"
elif [[ -n "${BASE_IMAGE}" ]] && [[ "${SP_VOL}" != "${BASE_IMAGE}" ]]; then
    if [[ "${SNAP_IMG}" == "${BASE_IMAGE}" ]] || [[ "${SNAP_IMG}" == "${BASE_IMAGE}-snap"* ]]; then
        SNAP_OWNER="image"
    fi
fi
if [[ -z "${SNAP_OWNER}" ]]; then
    _m="snapshot ${SNAP_UID} img tag '${SNAP_IMG}'${SNAP_VM:+ ${VM_TAG}:${SNAP_VM}} does not belong to ${SP_VOL}${BASE_IMAGE:+ or ${BASE_IMAGE}}"
    if boolTrue "FORCE"; then
        msg "[W] ${_m}, continuing (force)"
    else
        fail 1 "${_m}; use --force to restore from it anyway"
    fi
fi

# current attachments of the old volume
HOST_CLIENT=""
if [[ -n "${HAS_HOST}" ]]; then
    HOST_CLIENT="$(storpoolClientId "${VM_HOST}" "${COMMON_DOMAIN}")"
    [[ -n "${HOST_CLIENT}" ]] || fail 1 "can't get the StorPool client id of host ${VM_HOST}"
fi
DO_MULTICLUSTER=1 DO_ALLCLUSTERS=1 storpoolRetry AttachmentsList >/dev/null
OLD_CLIENTS="$(jq -r --arg uid "${OLD_UID}" \
    '(if (.data|type)=="array" then .data[] else .data.clusters[].response.data[]? end)
     |select(.volume==$uid and .snapshot==false)|.client' "${TMPDIR}/AttachmentsList.json" | sort -n | tr '\n' ' ' || true)"
OLD_CLIENTS="${OLD_CLIENTS% }"
OTHER_CLIENTS=""
for _c in ${OLD_CLIENTS}; do
    [[ "${_c}" == "${HOST_CLIENT}" ]] || OTHER_CLIENTS+="${OTHER_CLIENTS:+ }${_c}"
done
if [[ -n "${OTHER_CLIENTS}" ]]; then
    _m="volume ${OLD_UID} (${SP_VOL}) is attached to client(s) ${OTHER_CLIENTS}${HAS_HOST:+ besides ${VM_HOST} (${HOST_CLIENT})}"
    if boolTrue "FORCE"; then
        msg "[W] ${_m}, they will be force-detached"
    else
        fail 1 "${_m}; use --force to detach them"
    fi
fi

#-------------------------------------------------------------------------------
# Plan
#-------------------------------------------------------------------------------

OLD_SIZE_M=$((OLD_SIZE / 1024 / 1024))
SNAP_SIZE_M=$((SNAP_SIZE / 1024 / 1024))
SIZE_ACTION="keep ${OLD_SIZE_M}M"
if [[ ${SNAP_SIZE} -lt ${OLD_SIZE} ]]; then
    if boolTrue "SNAPSHOT_SIZE"; then
        SIZE_ACTION="shrink to the snapshot's ${SNAP_SIZE_M}M and update DISK/SIZE in the VM (was ${OLD_SIZE_M}M)"
    else
        SIZE_ACTION="grow the new volume from the snapshot's ${SNAP_SIZE_M}M back to ${OLD_SIZE_M}M"
    fi
elif [[ ${SNAP_SIZE} -gt ${OLD_SIZE} ]]; then
    SIZE_ACTION="take the snapshot's ${SNAP_SIZE_M}M and update DISK/SIZE in the VM (was ${OLD_SIZE_M}M)"
fi

HOST_ACTION="nothing (not deployed), the next prolog attaches the new volume"
if [[ -n "${HAS_HOST}" ]]; then
    HOST_ACTION="detach ${OLD_UID}, attach new ${SP_MODE}, ln -sf ${DST_PATH}"
fi
cat <<EOF
VM ${VM_ID} state ${VM_STATE_NAME}${HAS_HOST:+ on ${VM_HOST} (client ${HOST_CLIENT})}, system DS ${VM_DS_ID}
disk ${DISK_ID}: ${SP_VOL} type ${xTYPE} mode ${SP_MODE}${BASE_IMAGE:+ image ${BASE_IMAGE}}
old volume: ${OLD_UID} size ${OLD_SIZE_M}M template ${OLD_TEMPLATE:-none} cluster ${OLD_CLUSTER}${OLD_CLIENTS:+ attached to ${OLD_CLIENTS}}
snapshot:   ${SNAP_UID} size ${SNAP_SIZE_M}M cluster ${SNAP_CLUSTER} img ${SNAP_IMG}${SNAP_VM:+ ${VM_TAG} ${SNAP_VM}} (${SNAP_OWNER:-foreign})
size:       ${SIZE_ACTION}
etcd:       /byName/${SP_VOL} -> new globalId, /byUid/${OLD_UID} removed
host:       ${HOST_ACTION}
old volume: ${DELAY_DELETE:+delayed-delete snapshot (DELAY_DELETE=${DELAY_DELETE}, reason=vmdisk_restore), then }delete
EOF

if boolTrue "DRY_RUN"; then
    msg "dry run, nothing changed"
    exit 0
fi

#-------------------------------------------------------------------------------
# Execute. Every API failure below exits through storpoolRetry and the EXIT
# trap runs the rollback steps registered so far (last registered first).
#-------------------------------------------------------------------------------

if [[ -n "${HAS_HOST}" ]]; then
    msg "detach ${OLD_UID} (${SP_VOL}) from ${VM_HOST}"
    storpoolDetach "${OLD_UID}" "force" "${VM_HOST}" "all"
    trapAdd "storpoolAttach '${OLD_UID}' '${VM_HOST}' '${SP_MODE}'; oneSymlink '${VM_HOST}' '${OLD_UID}' '${DST_PATH}'"
fi

msg "create ${SP_VOL} from ${SNAP_UID}${OLD_TEMPLATE:+ template ${OLD_TEMPLATE}}"
storpoolVolumeFromSnapshot "${SNAP_UID}" "${SP_VOL}" "${OLD_TEMPLATE}"
_ret=$?
if [[ ${_ret} -ne 0 ]] || [[ -z "${SP_UID}" ]]; then
    fail "${_ret}" "can't create a volume from ${SNAP_UID} (${_ret})"
fi
NEW_UID="${SP_UID}"
msg "new volume ${NEW_UID}, etcd byName/${SP_VOL} -> ${NEW_UID}"
# undo: drop the new volume and its byUid key, point byName back to the old uid
trapAdd "ONLY_DELETE=volume _SOFT_FAIL=1 storpoolDelete '${NEW_UID}' force '' '' '' 1; kvPut '${SP_VOL}' '${OLD_UID}'"

storpoolVolumeInfo "${NEW_UID}"
NEW_SIZE="${V_SIZE}"
[[ -n "${NEW_SIZE}" ]] || fail 1 "new volume ${NEW_UID} not found after create"
ONE_SIZE_M=""
if [[ ${NEW_SIZE} -lt ${OLD_SIZE} ]] && ! boolTrue "SNAPSHOT_SIZE"; then
    msg "resize ${NEW_UID} from $((NEW_SIZE / 1024 / 1024))M to ${OLD_SIZE_M}M"
    storpoolVolumeResize "${NEW_UID}" "${OLD_SIZE}"
elif [[ ${NEW_SIZE} -ne ${OLD_SIZE} ]]; then
    ONE_SIZE_M=$((NEW_SIZE / 1024 / 1024))
fi

storpoolVolumeTag "${NEW_UID}" \
    "virt;${LOC_TAG:-nloc};${VM_TAG:-nvm};diskid;type;${VC_POLICY:+vc-policy};${SP_QOSCLASS:+qc}" \
    "one;${LOC_TAG_VAL};${VM_ID};${DISK_ID};${xTYPE};${VC_POLICY};${SP_QOSCLASS}"

if [[ -n "${HAS_HOST}" ]]; then
    msg "attach ${NEW_UID} ${SP_MODE} on ${VM_HOST} and link ${DST_PATH}"
    storpoolAttach "${NEW_UID}" "${VM_HOST}" "${SP_MODE}"
    oneSymlink "${VM_HOST}" "${NEW_UID}" "${DST_PATH}"
fi

if [[ -n "${ONE_SIZE_M}" ]]; then
    if onedb change-body vm --id "${VM_ID}" "/VM/TEMPLATE/DISK[DISK_ID=${DISK_ID}]/SIZE" "${ONE_SIZE_M}"; then
        msg "VM ${VM_ID} disk ${DISK_ID} DISK/SIZE set to ${ONE_SIZE_M}M (was ${OLD_SIZE_M}M)"
    else
        fail $? "onedb change-body DISK/SIZE=${ONE_SIZE_M} failed"
    fi
fi

# commit: the new volume is in place, nothing below is rolled back
trapReset

msg "dispose of the old volume ${OLD_UID}${DELAY_DELETE:+ (DELAY_DELETE=${DELAY_DELETE})}"
_SOFT_FAIL=1 storpoolDelete "${OLD_UID}" "force" "" "${REMOTE_BACKUP_DELETE}" \
    "\"img\":\"${SP_VOL}\",\"reason\":\"vmdisk_restore\"" "1"
_ret=$?
if [[ ${_ret} -ne 0 ]]; then
    msg "[W] old volume ${OLD_UID} not deleted (${_ret}); the disk already uses ${NEW_UID}, delete ${OLD_UID} by hand"
fi

# verify etcd
KV_NAME="$(kvGet byName "${SP_VOL}")"
KV_NEW="$(kvGet byUid "${NEW_UID}")"
KV_OLD="$(kvGet byUid "${OLD_UID}")"
if [[ "${KV_NAME}" != "${NEW_UID}" ]] || [[ "${KV_NEW}" != "${SP_VOL}" ]] || [[ -n "${KV_OLD}" ]]; then
    msg "[E] etcd not as expected: byName/${SP_VOL}='${KV_NAME}' byUid/${NEW_UID}='${KV_NEW}' byUid/${OLD_UID}='${KV_OLD}'"
    exit 1
fi

msg "END VM ${VM_ID} disk ${DISK_ID} (${SP_VOL}): ${OLD_UID} replaced by ${NEW_UID} from ${SNAP_UID}"
exit 0
