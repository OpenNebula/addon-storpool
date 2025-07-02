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

set -e -o pipefail

SLP=${SLP:-1}
# shellcheck source=tm/storpool/storpool_common.sh
source /var/lib/one/remotes/tm/storpool/storpool_common.sh

# nobody else will create this.
# hopefuly.
VM_NAME="${VM_NAME:-SPTEST.fadCarlarr}"
VN_NAME="${VN_NAME:-192.168.122-virbr0}"
DATA_DIR="${0}.DATA"
#KEEP_DATA_DIR=
#KEEP_TEST_TEMPLATE=

trap 'echo "PID:$$ exit status:$?"' EXIT QUIT

function hdr()
{
    echo -ne "\n[$(date +%T || true)]${DEBUG:+[${BASH_LINENO[*]}]} $*"
    logger -t TEST_sp_TEST -- "$* //${FUNCNAME[*]:1}"
}

function msg()
{
    echo -n " $*"
}

function xmlget()
{
    # shellcheck disable=SC2086
    xmlstarlet sel -t -m "$1" -v "$2" ${3:-}
}

function do_waitfor()
{
	local vmid="$1" CMD="$2" STATE="$3" TIMEOUT="${4:-60}"
	local SEC=0 CSTATE="" DO_CMD=""
    DO_CMD="${CMD} list --list STAT,ID,NAME --csv"

	while [[ "${SEC}" -lt "${TIMEOUT}" ]]; do
		CSTATE=$(${DO_CMD} | grep -E ",${vmid}\$|,${vmid}," | cut -d, -f1) || true
        [[ -z "${DEBUG}" ]] || echo "  ${vmid} state '${CSTATE}' waiting for '${STATE}' #${SEC}::${TIMEOUT} //${DO_CMD}"
        [[ -n "${CSTATE}" ]] || hdr "[Warn] Can't get ${CMD} '${vmid}' state! (${STATE})"
		if [[ "${CSTATE}" == "${STATE}" ]]; then
            [[ -z "${DEBUG}" ]] || hdr "[DBG] cstate match"
            return 0
		fi
		sleep "${SLP}"
		SEC=$((SEC + SLP))
	done
    hdr "Timeout waiting for '${STATE}'. Last is '${CSTATE}'"
    return 1
}

function waitforimg()
{
	do_waitfor "$1" oneimage "$2" "$3"
}

function waitforvm()
{
	do_waitfor "$1" onevm "$2" "$3"
}

function die()
{
	echo -e "\nERROR: $*!"
    logger -t test_sp_test -- "[ERROR] $*! //${FUNCNAME[*]:1}"
	exit 5
}

function ipsetTest()
{
    local hst="$1" name="one-${2}-${3}-ip-spoofing"
    local error=0 ipaddr="" ipSet=""
    shift 3
    # shellcheck disable=SC2029
    ipSet="$(ssh "${hst}" \
        "sudo /usr/sbin/ipset list '${name}' 2>/dev/null" |\
            tee "${DATA_DIR}/ipset_list-${CURRENT_HOST}.out")"
    [[ -n "${ipSet}" ]] || return 1
    for ipaddr in "$@"; do
        if echo "${ipSet}" | grep -q "^${ipaddr}\$"; then
            [[ -z "${DEBUG}" ]] || msg "ipsetTest(${hst},${name}) have ${ipaddr}"
        else
            msg "ipsetTest(${hst},${name}) miss ${ipaddr}"
            error=1
        fi
    done
    return "${error}"
}

function ipPing() {
    local hst="$1" rcmd=""
    shift
    hdr "Ping $* via '${hst}'"
    rcmd=$(cat <<EOF
    set -e
    i=0
    while [[ \${i} -lt 120 ]]; do
      if ping -q -c 1 ${1} >/dev/null; then
        for ip in $*; do
          ping -q -c 2 \${ip} >/dev/null
        done
        exit
      fi
      i=\$((i+1))
      sleep "${SLP:-1}"
      echo -n '.'
    done
    false
EOF
)
    # shellcheck disable=SC2029
    ssh "${hst}" "${rcmd}" || die "IP ${1} ping failed"
}

function ipCheck()
{
    local hst="$1"
    if [[ "${FILTER_MAC_SPOOFING^^}" = 'YES' ]]; then
        hdr "Check FILTER_MAC_SPOOFING"
        # shellcheck disable=SC2310
        if ! ipsetTest "${hst}" "${VM_ID}" "${NIC_ID}" "${NIC_IP}" "${ALIAS_NIC_IP}"; then
            msg "Retrying after 3s"
            sleep 3
            ipsetTest "${hst}" "${VM_ID}" "${NIC_ID}" "${NIC_IP}" "${ALIAS_NIC_IP}" ||\
                die "Error in ipset"
        fi
        ipPing "${hst}" "${NIC_IP}" "${ALIAS_NIC_IP}"
    fi
}

function vmDeploy()
{
    local vmid="${1:-${VM_ID}}" hst="${2:-${CURRENT_HOST}}"
    hdr "Deploy on '${hst}'"
    if onevm deploy "${vmid}" "${hst}" &>"${DATA_DIR}/deploy-${VM_NAME}"; then
        # shellcheck disable=SC2310
        waitforvm "${vmid}" runn 120 || die "Failed to deploy VM '${vmid}' on '${hst}'"
    else
        cat "${DATA_DIR}/deploy-${VM_NAME}"
        die "Deploy VM '${vmid}' failed"
    fi
    CURRENT_HOST="$(onevm show "${vmid}" --xml | \
        xmlget '//HISTORY[last()]' HOSTNAME)"
    msg "on '${CURRENT_HOST}'."
    ipCheck "${CURRENT_HOST}"
}

# shellcheck disable=SC2120
function vmResume()
{
    local vmid="${1:-${VM_ID:-0}}"
    hdr "Resuming"
    if onevm resume "${vmid}" &>"${DATA_DIR}/resume-${VM_NAME}"; then
        # shellcheck disable=SC2310
        waitforvm "${vmid}" runn || die "Cannot resume '${vmid}'"
    else
        cat "${DATA_DIR}/resume-${VM_NAME}"
        die "Resume VM '${vmid}' failed"
    fi
    CURRENT_HOST="$(onevm show "${vmid}" --xml | \
        xmlget '//HISTORY[last()]' HOSTNAME)"
    msg "on '${CURRENT_HOST}'."
    ipCheck "${CURRENT_HOST}"
}

function vmMigrate()
{
    local DST="$1" ARGS="$2" EXPECT="${3:-runn}"
    hdr "Migrating to '${DST}'${ARGS:+ ${ARGS}} //(${EXPECT})"
    declare -a _cmd=()
    read -r -a _cmd <<< "onevm migrate ${ARGS} ${VM_ID} ${DST}"
    "${_cmd[@]}"
    # shellcheck disable=SC2310
    waitforvm "${VM_NAME}" "${EXPECT}" ||\
        die "Migration failed (expected ${EXPECT})"
    CURRENT_HOST=$(onevm show --xml "${VM_ID}" |\
        xmlget '//HISTORY[last()]' HOSTNAME)
    [[ "${CURRENT_HOST}" == "${DST}" ]] || die "Migration to '${DST}' failed"
    if [[ "${EXPECT}" == "runn" ]]; then
        ipCheck "${CURRENT_HOST}"
    fi
}

function vmPoweroff()
{
    hdr "Powering off${1:+ ($1)}"
    onevm poweroff ${1:+--$1} "${VM_ID}"
    # shellcheck disable=SC2310
    waitforvm "${VM_NAME}" poff || die "Power off${1:+ --$1} failed"
}

function vmSuspend()
{
    hdr "Suspending"
    onevm suspend "${VM_ID}"
    # shellcheck disable=SC2310
    waitforvm "${VM_NAME}" susp || die "VM suspend timed out"
}

function vmStop()
{
    hdr "Stopping"
    onevm stop "${VM_ID}"
    # shellcheck disable=SC2310
    waitforvm "${VM_NAME}" stop || die "VM stop timed out"
}

function vmUndeploy()
{
    hdr "Undeploy"
    onevm undeploy "${VM_ID}"
    # shellcheck disable=SC2310
    waitforvm "${VM_NAME}" unde || die "VM undeploy timed out"
}

function vmTerminate()
{
    local ID=""
    # shellcheck disable=SC2310
    ID=$(onevm list --xml | \
        xmlget "//VM[NAME=\"${VM_NAME}\"]" ID || true)
    if [[ -n "${ID}" ]]; then
        hdr "Terminate (hard) VM (${ID}) ${VM_NAME}"
        if onevm terminate --hard "${VM_NAME}" &>"${DATA_DIR}/terminate-${VM_NAME}"; then
            echo "   Terminate '${VM_NAME}'"
        else
            cat "${DATA_DIR}/terminate-${VM_NAME}"
            die "Terminate '${VM_NAME}' failed!"
        fi
        waitforvm "${VM_NAME}" ""
    else
        hdr "Terminate VM - ${VM_NAME} not found."
    fi
}

function vmSnapshotEnabled()
{
    grep -q snapshot_create-storpool ~oneadmin/config || return 1
}

function vmSnapshotCreate()
{
    local vmname="${VM_NAME}-$1"
    # shellcheck disable=SC2310
    vmSnapshotEnabled || return 0
    hdr "Creating VM Snapshot '${vmname}'"
    onevm snapshot-create "${VM_ID}" "${vmname}"
    # shellcheck disable=SC2310
    waitforvm "${VM_NAME}" runn || die "VM Snapshot create timed out"
    VM_SNAPSHOT_ID=$(onevm show "${VM_ID}" --xml |\
        xmlget "//SNAPSHOT[NAME=\"${vmname}\"]" SNAPSHOT_ID)
    msg "VM Snapshot ID '${VM_SNAPSHOT_ID}'"
}

function vmSnapshotRevert()
{
    local vmname="${VM_NAME}-$1" VM_SNAPSHOT_ID=""
    # shellcheck disable=SC2310
    vmSnapshotEnabled || return 0
    hdr "Reverting VM Snapshot '${vmname}'"
    # shellcheck disable=SC2310
    VM_SNAPSHOT_ID=$(onevm show "${VM_ID}" --xml |\
        xmlget "//SNAPSHOT[NAME=\"${vmname}\"]" SNAPSHOT_ID)
    onevm snapshot-revert "${VM_ID}" "${VM_SNAPSHOT_ID}"
    msg "waiting for power-off"
    # shellcheck disable=SC2310
    if ! waitforvm "${VM_NAME}" poff; then
        vmPoweroff hard
    fi
    vmResume
}

# shellcheck disable=SC2310
function vmSnapshotDelete()
{
    local vmname="${VM_NAME}-$1" VM_SNAPSHOT_ID=""
    vmSnapshotEnabled || return 0
    hdr "Deleting VM Snapshot '${vmname}'"
    VM_SNAPSHOT_ID=$(onevm show "${VM_ID}" --xml |\
        xmlget "//SNAPSHOT[NAME=\"${vmname}\"]" SNAPSHOT_ID)
    onevm snapshot-delete "${VM_ID}" "${VM_SNAPSHOT_ID}"
    waitforvm "${VM_NAME}" runn || die "VM Snapshot delete timed out"
    VM_SNAPSHOT_ID=$(onevm show "${VM_ID}" --xml| \
        xmlget "//SNAPSHOT[NAME=\"${vmname}\"]" SNAPSHOT_ID || true)
    [[ -z "${VM_SNAPSHOT_ID}" ]] || die "VM Snapshot delete failed"
}

function diskCreate()
{
    local _disk_type="$1"
    hdr "Adding disk (volatile ${_disk_type})"
    local VOLATILE_TEMPLATE="${DATA_DIR}/volatile-${_disk_type}.template"
    cat >"${VOLATILE_TEMPLATE}" <<EOF
DISK=[
  SIZE="1024",
  TYPE="${_disk_type}",
  FORMAT="raw",
  DRIVER="raw",
  CACHE="none",
  IO="native",
  DISCARD="unmap",
  DEV_PREFIX="sd"
]
EOF
    onevm disk-attach "${VM_ID}" --file "${VOLATILE_TEMPLATE}"
    sleep 0.9
    # shellcheck disable=SC2310
    waitforvm "${VM_NAME}" runn || die "Disk add timed out"
    DISK_ID=$(onevm show "${VM_ID}" --xml |\
        xmlget "//DISK[TYPE=\"${_disk_type}\"]" DISK_ID)
    [[ -n "${DISK_ID}" ]] || die "Adding disk failed"
    msg "Disk ${_disk_type} ID '${DISK_ID}'"
}

# shellcheck disable=SC2310
function diskAttach()
{
    hdr "Attaching ${1} to VM ${VM_ID}"
    onevm disk-attach "${VM_ID}" --image "${1}"
    # shellcheck disable=SC2310
    waitforvm "${VM_NAME}" runn || die "Attach ${1} timed out"
    DISK_ID=$(onevm show "${VM_ID}" --xml |\
        xmlget "//DISK[IMAGE=\"${1}\"]" DISK_ID)
    if [[ -z "${DISK_ID}" ]]; then
    	die "Attach ${1} failed"
    fi
    msg "Disk ID '${DISK_ID}'"
}

# shellcheck disable=SC2310
function diskDetach()
{
    hdr "Detaching VM disk ID ${1}"
    onevm disk-detach "${VM_ID}" "${1}"
    waitforvm "${VM_NAME}" runn || die "Disk detach timed out"
    IMAGE=$(onevm show "${VM_ID}" --xml |\
        xmlget "//DISK[DISK_ID=\"${1}\"]" IMAGE || true)
    [[ -z "${IMAGE}" ]] || die "Disk detach failed"
    msg "Image '${IMAGE}'"
}

# shellcheck disable=SC2310
function diskSaveas()
{
    local vm_id="$1" disk_id="$2" name="$3"
    hdr "VM disk-saveas $*"
    echo
    if onevm disk-saveas "${vm_id}" "${disk_id}" "${name}" \
        &>"${DATA_DIR}/saveas-${name}"; then
        waitforimg "${name}" "rdy"  || die "Image delete failed"
    else
        cat "${DATA_DIR}/saveas-${name}"
        die "onevm disk-saveas failed"
    fi
    IMAGE_ID=$(oneimage list --xml |\
        xmlget "//IMAGE[NAME=\"${name}\"]" ID)
    [[ -n "${IMAGE_ID}" ]] || die "disk-saveas failed"
}

# shellcheck disable=SC2310
function imageCreate()
{
    hdr "Create${2:+ persistent} image '$1'"
    if oneimage create --name "${1}" --datastore "${IMAGE_DS_ID}" --size 10000 \
        --type datablock --prefix sd ${2:+--persistent} \
        &>"${DATA_DIR}/image-${1}"; then
        waitforimg "${1}" rdy || die "Image creation failed"
        IMAGE_ID=$(oneimage list --xml |\
            xmlget "//IMAGE[NAME=\"${1}\"]" ID)
        [[ -n "${IMAGE_ID}" ]] || die "Create image failed"
    else
        cat "${DATA_DIR}/image-${PE_IMAGE_NAME:-${1}}"
        die "Image creation failed"
    fi
    msg "Image ID '${IMAGE_ID}'"
}

# shellcheck disable=SC2310
function imageDelete()
{
    local IMAGE_ID=""
    IMAGE_ID="$(oneimage list --xml |\
        xmlget "//IMAGE[NAME=\"${1}\"]" ID || true)"
    if [[ -n "${IMAGE_ID}" ]]; then
        hdr "Removing image ${IMAGE_ID} (${1})"
        oneimage delete "${IMAGE_ID}"
        waitforimg "${1}" "" || die "Image delete failed"
    fi
}

# shellcheck disable=SC2230
if ! which storpool &>/dev/null; then
	echo "storpool cli not installed?"
	exit 2
fi

# shellcheck disable=SC2230
if ! which onevm &>/dev/null; then
	echo "ONE cli not installed?"
	exit 2
fi

if ! [[ -d /var/lib/one/remotes/datastore/storpool ]] ||\
   ! [[ -d /var/lib/one/remotes/tm/storpool ]]; then
	echo "addon-storpool not installed?"
	exit 2
fi

if [[ -z "$2" ]]; then
	echo "Usage: $0 host1 host2 '[templateid]'"
	echo
	onehost list
	exit 2
fi

mkdir -p "${DATA_DIR}"

HOST1="$1"
HOST2="$2"

CLUSTER_ID1="$(onehost show "${HOST1}" --xml |\
    tee "${DATA_DIR}/host-${HOST1}.XML" |\
    xmlget '//HOST' 'CLUSTER_ID')"
CLUSTER_ID2="$(onehost show "${HOST2}" --xml |\
    tee "${DATA_DIR}/host-${HOST2}.XML" |\
    xmlget '//HOST' 'CLUSTER_ID')"
export CLUSTER_ID2

if [[ "${CLUSTER_ID1}" != "${CLUSTER_ID2}" ]]; then
	echo "cluster IDs of both hosts do not match, exiting."
	exit 2
fi

IMAGE_DS_ID="$(onedatastore list --xml |\
    xmlget "//DATASTORE[TM_MAD=\"storpool\" and TYPE=0 and CLUSTERS[ID=${CLUSTER_ID1}]]" "ID" -n |\
    tail -n 1)"
if [[ -z "${IMAGE_DS_ID}" ]]; then
    die "Can't find IMAGE datastore with TM_MAD=storpool"
fi

IMAGE_DS_NAME="$(onedatastore show "${IMAGE_DS_ID}" --xml |\
    xmlget "//DATASTORE" NAME)"

# shellcheck disable=SC2310
if vmTerminate; then
    hdr "VM terminated"
else
    hdr "vmTerminate status $?"
fi

hdr "Using IMAGE datastore: ${IMAGE_DS_ID} (${IMAGE_DS_NAME})"

###############################################################################
# VM Template

if [[ -n "${3}" ]]; then
	VM_TEMPLATE_NAME="${3}"
	deltemplate=n
else
	VM_TEMPLATE_NAME="t-${VM_NAME}-tmpl"

	if ! onetemplate show "${VM_TEMPLATE_NAME}" &>/dev/null; then
        imageDelete "${VM_TEMPLATE_NAME}"
		TEMPLATE_ID="$(onemarketapp list -f NAME~'Alpine Linux' -l ID,NAME,TYPE,STAT --csv |\
            grep 'img,rdy' | tail -n 1 | cut -d, -f 1)"
		hdr "Downloading template ${TEMPLATE_ID} from OpenNebula Marketplace as '${VM_TEMPLATE_NAME}'"
		if onemarketapp export "${TEMPLATE_ID}" "${VM_TEMPLATE_NAME}" --datastore "${IMAGE_DS_ID}" \
            &>"${DATA_DIR}/export-${VM_TEMPLATE_NAME}"; then
    	    hdr "Waiting for template image '${VM_TEMPLATE_NAME}' to become ready"
            # shellcheck disable=SC2310
        	waitforimg "${VM_TEMPLATE_NAME}" rdy 300 \
                || die "VM Tmeplate download timed out"
        else
            cat "${DATA_DIR}/export-${VM_TEMPLATE_NAME}"
            die "Download failed!"
        fi
	fi

	deltemplate=y
fi

if [[ -n "${VN_NAME}" ]]; then
    hdr "Looking for network '${VN_NAME}'"
    # shellcheck disable=SC2310
    VN_ID="$(onevnet list --xml |\
        tee "${DATA_DIR}/vnet-list.XML" |\
        xmlget "//VNET[NAME=\"${VN_NAME}\"]" ID || true)"
    [[ -z "${VN_ID}" ]] || msg "VNet ID ${VN_ID}"
fi

###############################################################################
# VM create
hdr "Creating VM ${VM_NAME} from Template ${VM_TEMPLATE_NAME}${VN_ID:+ using VNet ID ${VN_ID}}"
echo
if onetemplate instantiate "${VM_TEMPLATE_NAME}" --name "${VM_NAME}" \
    ${VN_ID:+--nic "${VN_ID}"} --hold &>"${DATA_DIR}/instantiate-${VM_NAME}"; then
    # shellcheck disable=SC2310
    waitforvm "${VM_NAME}" hold || die "Failed to instantiate VM '${VM_NAME}' //HOLD"
else
    cat "${DATA_DIR}/instantiate-${VM_NAME}"
    die "Create VM failed //HOLD"
fi

vmDeploy "${VM_NAME}" "${HOST1}"
VM_ID=$(onevm show "${VM_NAME}" --xml |\
    tee "${DATA_DIR}/vm-${VM_NAME}.XML" |\
    xmlget '//VM' ID)
if [[ -z "${VM_ID}" ]]; then
    die "Can't get VM ID for '${VM_NAME}'"
fi

CURRENT_HOST="$(onevm show "${VM_ID}" --xml | xmlget '//HISTORY[last()]' HOSTNAME)"
msg "VM ${VM_ID} is runnung on host '${CURRENT_HOST}'"

NP_IMAGE_NAME="NP-${VM_NAME}"
imageDelete "${NP_IMAGE_NAME}"
imageCreate "${NP_IMAGE_NAME}"
NP_IMAGE_ID="${IMAGE_ID}"
diskAttach "${NP_IMAGE_NAME}"
NP_DISK_ID="${DISK_ID}"
export NP_IMAGE_ID

PE_IMAGE_NAME="PE-${VM_NAME}"
imageDelete "${PE_IMAGE_NAME}"
imageCreate "${PE_IMAGE_NAME}" persistent
PE_IMAGE_ID="${IMAGE_ID}"
diskAttach "${PE_IMAGE_NAME}"
PE_DISK_ID="${DISK_ID}"
export PE_IMAGE_ID

diskCreate swap
SWAP_DISK_ID="${DISK_ID}"
diskCreate fs
FS_DISK_ID="${DISK_ID}"
export SWAP_DISK_ID

vmSnapshotCreate 'A'

if [[ -n "${VN_ID}" ]]; then
    NIC_NAME=$(onevm show "${VM_ID}" --xml | xmlget "//NIC[NETWORK_ID=${VN_ID}]" NAME)
    hdr "Add alias IP from VNet ID ${VN_ID} to '${NIC_NAME}'"
    onevm nic-attach "${VM_ID}" --network "${VN_ID}" --alias "${NIC_NAME}"
    # shellcheck disable=SC2310
    waitforvm "${VM_NAME}" runn || die "Alias NIC attach timed out"
    ALIAS_NIC_ID=$(onevm show "${VM_ID}" --xml |\
        tee "${DATA_DIR}/vm+alias.XML" |\
        xmlget "//NIC_ALIAS[NETWORK_ID=${VN_ID}]" NIC_ID -n | tail -n 1)
    if [[ -n "${ALIAS_NIC_ID}" ]]; then
        ALIAS_NIC_IP=$(xmlget < "${DATA_DIR}/vm+alias.XML" "//NIC_ALIAS[NIC_ID=${ALIAS_NIC_ID}]" IP)
        NIC_ID=$(xmlget < "${DATA_DIR}/vm+alias.XML" "//NIC[NAME=\"${NIC_NAME}\"]" NIC_ID)
        NIC_IP=$(xmlget < "${DATA_DIR}/vm+alias.XML" "//NIC[NIC_ID=${NIC_ID}]" IP)
        FILTER_IP_SPOOFING=$(xmlget < "${DATA_DIR}/vm+alias.XML" "//NIC[NIC_ID=${NIC_ID}]" FILTER_IP_SPOOFING)
        FILTER_MAC_SPOOFING=$(xmlget < "${DATA_DIR}/vm+alias.XML" "//NIC[NIC_ID=${NIC_ID}]" FILTER_MAC_SPOOFING)
        export FILTER_IP_SPOOFING
    else
        die "Can't get NIC_ALIAS/NIC_ID"
    fi
    ipCheck "${CURRENT_HOST}"
fi


DISK_SAVEAS_NAME="SAVEAS-${VM_NAME}"
imageDelete "${DISK_SAVEAS_NAME}"

diskSaveas "${VM_ID}" 0 "${DISK_SAVEAS_NAME}"
DISK_SAVEAS_ID="${IMAGE_ID}"
export DISK_SAVEAS_ID

###############################################################################
# VM migration
[[ "${CURRENT_HOST}" == "${HOST1}" ]] && HOST_TO_MOVE="${HOST2}" || HOST_TO_MOVE="${HOST1}"

FIRST_HOST="${CURRENT_HOST}"
SECOND_HOST="${HOST_TO_MOVE}"

vmMigrate "${SECOND_HOST}" --live

vmSnapshotCreate 'B'

vmMigrate "${FIRST_HOST}" --live

vmMigrate "${SECOND_HOST}"

vmPoweroff hard

vmMigrate "${FIRST_HOST}" "" poff

vmResume

vmSnapshotRevert 'A'

vmSnapshotDelete 'A'

###############################################################################
# non-persistent detach/destroy

diskDetach "${NP_DISK_ID}"

imageDelete "${NP_IMAGE_NAME}"

###############################################################################
# persistent detach/destroy

diskDetach "${PE_DISK_ID}"

imageDelete "${PE_IMAGE_NAME}"

###############################################################################
# Volatile destroy

diskDetach "${FS_DISK_ID}"

imageDelete "${DISK_SAVEAS_NAME}"

###############################################################################
# VM Suspend
vmSuspend

vmResume

###############################################################################
# VM Undeploy
vmUndeploy

vmDeploy

###############################################################################
# VM Stop
vmStop

vmDeploy

###############################################################################
# Cleanup
vmTerminate

if [[ "${deltemplate}" == "y" ]] && [[ -z "${KEEP_TEST_TEMPLATE}" ]]; then
    hdr "Deleting VM Template '${VM_TEMPLATE_NAME}'"
	onetemplate delete "${VM_TEMPLATE_NAME}" --recursive
fi
if [[ -z "${KEEP_DATA_DIR}" ]]; then
    rm -rf "${DATA_DIR}"
fi

hdr "Validation PASSED."
