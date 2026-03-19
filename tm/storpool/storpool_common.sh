#!/bin/bash

# -------------------------------------------------------------------------- #
# Copyright 2015-2025, StorPool (storpool.com)                               #
#                                                                            #
# Portions copyright OpenNebula Project (OpenNebula.org), CG12 Labs          #
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

# paranoid
PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:${PATH}"

#-------------------------------------------------------------------------------
# syslog logger function
#-------------------------------------------------------------------------------

function splog()
{
    local logmsg="" interactive=""
    logmsg="[$$] $* //${DEBUG_LINENO:+[${BASH_LINENO[-2]}] }${FUNCNAME[*]:1}"
    # test if the terminal is interactive
    if [[ -t 0 ]] && [[ -t 1 ]]; then
        interactive="{i} "
        if boolTrue "DEBUG_INTERACTIVE"; then
            echo "${logmsg}"
        fi
    fi
    logger -t "${LOG_PREFIX:-tm}_sp_${0##*/}" "${interactive:-}${logmsg}"
    if [[ -n "${LOG_TO_FILE}" ]] && [[ -d /var/log/one ]]; then
        echo "$(date +'%F %X.%N %Z') ${LOG_PREFIX:-tm}_sp_${0##*/}[$$] $* //[${BASH_LINENO[-2]}] ${FUNCNAME[*]:1}" \
            >>/var/log/one/addon-storpool.log || true
    fi
}

#-------------------------------------------------------------------------------
# Set up the environment to source common tools
#-------------------------------------------------------------------------------

if [[ -n "${ONE_LOCATION}" ]]; then
    PATH="${PATH}:${ONE_LOCATION}"
    TMCOMMON="${ONE_LOCATION}/var/remotes/tm/tm_common.sh"
else
    TMCOMMON="/var/lib/one/remotes/tm/tm_common.sh"
fi

for srcfile in "${TMCOMMON}" "/var/tmp/one/tm/tm_common.sh"; do
    if [[ -f "${srcfile}" ]]; then
        # shellcheck source=/dev/null
        source "${srcfile}"
        break
    fi
done

#-------------------------------------------------------------------------------
# configuration parameters
#-------------------------------------------------------------------------------
export DEBUG_COMMON=""
export DEBUG_TRAPS=""
export DEBUG_SP_RUN_CMD=1
export DDEBUG_SP_RUN_CMD=""
export DEBUG_oneVmInfo=""
export DEBUG_oneDatastoreInfo=""
export DEBUG_oneTemplateInfo=""
export DEBUG_oneDsDriverAction=""
export DEBUG_KV=""

# enable the alternate VM Snapshot function to do atomic snapshots
export VMSNAPSHOT_OVERRIDE=1
# the common tag of the snapshots created by the alternate VM Snapshot interface
export VMSNAPSHOT_TAG="ONESNAP"
# (obsolete) used for the alternate VM snapshot interface before atomic snapshotting was implemented
export VMSNAPSHOT_FSFREEZE=0
# Delete VM snapshots when terminating a VM
export VMSNAPSHOT_DELETE_ON_TERMINATE=1
# block creating new VM Snapshots when the limit is reached
export VMSNAPSHOT_LIMIT=""
# alter the SYSTEM snapshot behavior depending on the underlying file system
export SP_SYSTEM="ssh"
# update Disk size in OpenNebula when reverting a snapshot
export UPDATE_ONE_DISK_SIZE=0
# Do not enforce the datastore template on the StorPool volumes
export NO_VOLUME_TEMPLATE="1"
# save the VM's checkpoint file directly to a block device, require qemu-kvm-ev
export SP_CHECKPOINT_BD=0
# clasify the import process to a given cgroup(s)
export SP_IMPORT_CGROUPS=""
# override datastore bridge list for datastore/export script
export EXPORT_BRIDGE_LIST=""
# do no copy th eVM home back to sunstone on undeploy
export SKIP_UNDEPLOY_SSH=0
# cleanup the VM home on undeploy
export CLEAN_SRC_ON_UNDEPLOY=1
# block creation of new disk snapshots when the limit is reached
export DISKSNAPSHOT_LIMIT=""
# update image template's variables DRIVER=raw and FORMAT=raw during import
export UPDATE_IMAGE_ON_IMPORT=0
# Tag all VM disks with tag $VM_TAG=${VM_ID}
# Empty string will disable the tagging
export VM_TAG="nvm"
# common opennebula tools args
export ONE_ARGS=""
#
export PROPAGATE_YES=1
#
export FORCE_DETACH_BY_TAG=0
#
export FORCE_DETACH_OTHER_MV=1
#
export FORCE_DETACH_OTHER_CONTEXT=1
#
export STORPOOL_CLIENT_ID_SOURCES="LOCAL ONEHOST FROMHOST HOSTHOSTNAME BRIDGELIST CLONEGW"
#
export DELAY_DELETE="48h"
#
export DISK_SNAPSHOT_FSFREEZE=0
# datastore/cp to report iamge format (one 5.12+)
export DS_CP_REPORT_FORMAT=1
# exclude CDROM images from VM Snapshots
export VMSNAPSHOT_EXCLUDE_CDROM=0
# libvirt 7.0.0 require cdrom volumes to be RW
export READONLY_MODE="rw"
# do domfsfreezer when cloninfg a disk
export DISK_SAVEAS_FSFREEZE=0
# tag contextualization iso with nvm (and vc-policy tags)
export TAG_CONTEXT_ISO=1
# timeout on attach when the client is not reachable (in seconds)
export ATTACH_TIMEOUT=20
# TM/monitor send VM disk stats over UDP
export MONITOR_SEND_UDP=""
#
export ONE_PX="${ONE_PX:-one}"
#
export DEFAULT_QOSCLASS=""
#
export MULTICLUSTER=1
#
export ADDON_RELEASE="25.01.2"
#
export SP_API_TIMEOUT=300

declare -A SYSTEM_COMPATIBLE_DS
# shellcheck disable=SC2034
SYSTEM_COMPATIBLE_DS["ceph"]=1
export SYSTEM_COMPATIBLE_DS
# save the VM's vTPM data
export ONE_TPM_SAVE=1

DRV_ACTION="${DRV_ACTION:-}"

function boolTrue()
{
   case "${!1^^}" in
       1|Y|YES|T|TRUE|ON)
           return 0
           ;;
       *)
           return 1
           ;;
   esac
}

function lookup_file()
{
    local _FILE="$1"
    local _PATH=""
    for _PATH in /var{/lib/one/remotes,/tmp/one}/{,datastore/,tm/storpool/}; do
        if [[ -f "${_PATH}${_FILE}" ]]; then
            if boolTrue "DEBUG_lookup_file"; then
                splog "[D] lookup_file(${_FILE}) FOUND:${_PATH}${_FILE}"
            fi
            echo "${_PATH}${_FILE}"
            return
        else
            if boolTrue "DEBUG_lookup_file"; then
                splog "[D] lookup_file(${_FILE}) NOT FOUND:${_PATH}${_FILE}"
            fi
        fi
    done
}

function get_one_version()
{
    local ONE_VERSION_FILE="" ONE_EDITION_FILE=""
    ONE_VERSION_FILE="$(lookup_file "VERSION")"
    if [[ -f "${ONE_VERSION_FILE}" ]]; then
        ONE_EDITION="CE"
        ONE_VERSION="${ONE_VERSION:-$(head -n 1 "${ONE_VERSION_FILE}")}"
        IFS='.' read -r -a ONE_VERSION_ARR <<< "${ONE_VERSION}"
        ONE_EDITION_FILE="${ONE_VERSION_FILE/VERSION/EDITION}"
        if [[ -f "${ONE_EDITION_FILE}" ]]; then
            ONE_EDITION="$(head -n 1 "${ONE_EDITION_FILE}")"
        fi
        if [[ ${#ONE_VERSION_ARR[*]} -gt 3 ]]; then
            ONE_EDITION="CE${ONE_VERSION_ARR[3]}"
        fi
        ONE_VERSION_INT=$((ONE_VERSION_ARR[0]*10000 + ONE_VERSION_ARR[1]*100 + ONE_VERSION_ARR[2]))
        splog "${ONE_VERSION} ${ONE_EDITION} ${ONE_VERSION_INT}"
    fi
}

DRIVER_PATH="$(dirname -- "$0")"
export DRIVER_PATH
sprcfile="$(lookup_file "addon-storpoolrc" || true)"

if [[ -f "${sprcfile}" ]]; then
    # shellcheck source=addon-storpoolrc
    source "${sprcfile}"
else
    splog "File '${sprcfile}' NOT FOUND!"
fi

if [[ -f "/etc/storpool/addon-storpool.conf" ]]; then
    # shellcheck source=/dev/null
    source "/etc/storpool/addon-storpool.conf"
fi

set -o pipefail

export ONE_PX="${ONE_PX:-one}"
export LOC_TAG="${LOC_TAG:-nloc}"
export LOC_TAG_VAL="${LOC_TAG_VAL:-${ONE_PX}}"
export SP_QOSCLASS="${SP_QOSCLASS:-}"
export STORPOOL_EXIST_HINT="${STORPOOL_EXIST_HINT:-Volume Snapshot}"
export SKIP_KV_DATA=0

VmState=(INIT PENDING HOLD ACTIVE STOPPED SUSPENDED DONE FAILED POWEROFF UNDEPLOYED CLONING CLONING_FAILURE)
LcmState=(LCM_INIT PROLOG BOOT RUNNING MIGRATE SAVE_STOP SAVE_SUSPEND SAVE_MIGRATE PROLOG_MIGRATE PROLOG_RESUME EPILOG_STOP EPILOG
        SHUTDOWN CANCEL FAILURE CLEANUP_RESUBMIT UNKNOWN HOTPLUG SHUTDOWN_POWEROFF BOOT_UNKNOWN BOOT_POWEROFF BOOT_SUSPENDED BOOT_STOPPED
        CLEANUP_DELETE HOTPLUG_SNAPSHOT HOTPLUG_NIC HOTPLUG_SAVEAS HOTPLUG_SAVEAS_POWEROFF HOTPLUG_SAVEAS_SUSPENDED SHUTDOWN_UNDEPLOY
        EPILOG_UNDEPLOY PROLOG_UNDEPLOY BOOT_UNDEPLOY HOTPLUG_PROLOG_POWEROFF HOTPLUG_EPILOG_POWEROFF BOOT_MIGRATE BOOT_FAILURE
        BOOT_MIGRATE_FAILURE PROLOG_MIGRATE_FAILURE PROLOG_FAILURE EPILOG_FAILURE EPILOG_STOP_FAILURE EPILOG_UNDEPLOY_FAILURE
        PROLOG_MIGRATE_POWEROFF PROLOG_MIGRATE_POWEROFF_FAILURE PROLOG_MIGRATE_SUSPEND PROLOG_MIGRATE_SUSPEND_FAILURE
        BOOT_UNDEPLOY_FAILURE BOOT_STOPPED_FAILURE PROLOG_RESUME_FAILURE PROLOG_UNDEPLOY_FAILURE DISK_SNAPSHOT_POWEROFF
        DISK_SNAPSHOT_REVERT_POWEROFF DISK_SNAPSHOT_DELETE_POWEROFF DISK_SNAPSHOT_SUSPENDED DISK_SNAPSHOT_REVERT_SUSPENDED
        DISK_SNAPSHOT_DELETE_SUSPENDED DISK_SNAPSHOT DISK_SNAPSHOT_REVERT DISK_SNAPSHOT_DELETE PROLOG_MIGRATE_UNKNOWN
        PROLOG_MIGRATE_UNKNOWN_FAILURE DISK_RESIZE DISK_RESIZE_POWEROFF DISK_RESIZE_UNDEPLOYED HOTPLUG_NIC_POWEROFF
        HOTPLUG_RESIZE HOTPLUG_SAVEAS_UNDEPLOYED HOTPLUG_SAVEAS_STOPPED BACKUP BACKUP_POWEROFF)
HostState=(INIT MONITORING_MONITORED MONITORED ERROR DISABLED MONITORING_ERROR MONITORING_INIT MONITORING_DISABLED OFFLINE)

if [[ -d "/opt/storpool/python3/bin" ]]; then
    export PATH="/opt/storpool/python3/bin:${PATH}"
fi

ATTACH_TIMEOUT="${ATTACH_TIMEOUT//[^[:digit:]]/}"
if [[ -z "${ATTACH_TIMEOUT}" ]]; then
    splog "Warning: ATTACH_TIMEOUT=${ATTACH_TIMEOUT} is not digits! Defaulting to 20 seconds"
    ATTACH_TIMEOUT=20
fi

function getFromConf()
{
    local cfgFile="$1" varName="$2" first="$3"
    local response
    if [[ -n "${first}" ]]; then
        response="$(grep "^${varName}" "${cfgFile}" | head -n 1 || true)"
    else
        response="$(grep "^${varName}" "${cfgFile}" | tail -n 1 || true)"
    fi
    response="${response#*=}"
    if boolTrue "DEBUG_COMMON"; then
        splog "[D] getFromConf(${cfgFile},${varName},${first}): ${response}"
    fi
    echo "${response//\"/}"
}

function delayDeleteSeconds()
{
    local n="${1//[^0-9]/}"
    if [[ -n "${n}" ]]; then
        case "${1: -1}" in
            d)
                echo "$((n*86400))"
                ;;
            h)
                echo "$((n*3600))"
                ;;
            m)
                echo "$((n*60))"
                ;;
            *)
                echo "${n}"
                ;;
        esac
    else
        echo 0
    fi
}

#-------------------------------------------------------------------------------
# trap handling functions
#-------------------------------------------------------------------------------
function trapReset()
{
    if [[ ! -d "${TMPDIR}" ]]; then
        TMPDIR="$(mktemp --tmpdir=/run/one -d addon-XXXXXXXX)"
        export TMPDIR
    fi
    local OLD_TRAP_CMD="${TRAP_CMD}"
    export TRAP_CMD="rm -rf \"${TMPDIR}\";"
    if boolTrue "DDEBUG_TRAPS"; then
        splog "[DD] trapReset:[${TRAP_CMD}] (old:[${OLD_TRAP_CMD}])"
    fi
    # shellcheck disable=SC2064
    trap "${TRAP_CMD}" TERM INT QUIT EXIT
}
function trapAdd()
{
    local _trap_cmd="$1"
    if boolTrue "DEBUG_TRAPS"; then
        splog "[D] trapAdd:'$*'"
    fi

    [[ -n "${TRAP_CMD}" ]] || TRAP_CMD="rm -rf \"${TMPDIR}\";"

    if [[ "${_trap_cmd}" == "PREPEND" ]]; then
        _trap_cmd="$2"
        export TRAP_CMD="${TRAP_CMD}${_trap_cmd};"
    else
        export TRAP_CMD="${_trap_cmd};${TRAP_CMD}"
    fi

    if boolTrue "DDEBUG_TRAPS"; then
        splog "[DD] trapAdd:[${TRAP_CMD}]"
    fi
    # shellcheck disable=SC2064
    trap "${TRAP_CMD}" TERM INT QUIT EXIT
}
function trapDel()
{
    local _trap_cmd="$1"
    if boolTrue "DEBUG_TRAPS"; then
        splog "[D] trapDel:$*"
    fi
    local OLD_TRAP_CMD="${TRAP_CMD}"
    export TRAP_CMD="${TRAP_CMD/${_trap_cmd};/}"
    if [[ -n "${TRAP_CMD}" ]]; then
        if boolTrue "DDEBUG_TRAPS"; then
            splog "[DD] trapDel:[${TRAP_CMD}] (old:[${OLD_TRAP_CMD}])"
        fi
        # shellcheck disable=SC2064
        trap "${TRAP_CMD}" TERM INT QUIT EXIT
    else
        trapReset
    fi
}

trapReset

REMOTE_HDR=$(cat <<EOF
    #_REMOTE_HDR
    set -e
    export PATH=/bin:/usr/bin:/sbin:/usr/sbin:\$PATH
    splog(){ logger -t "${LOG_PREFIX:-tm}_sp_${0##*/}_r" "\$*"; }
EOF
)
REMOTE_FTR=$(cat <<EOF
    #_END
    splog "END \${endmsg}"
EOF
)

function kvPut()
{
    local _kvName="$1" _kvUid="$2"
    local KVRET=1 KVKEY="/byName/${_kvName}" KVRES="" _DBGPX=""
    if boolTrue "DEBUG_KV"; then
        splog "[D] KV put $*"
    fi
    KVRES="$(ETCDCTL_API=3 etcdctl put --prev-kv -- "${KVKEY}" "${_kvUid}")"
    KVRET=$?
    if boolTrue "DDEBUG_KV" || [[ ${KVRET} -ne 0 ]]; then
        [[ ${KVRET} -ne 0 ]] && _DBGPX="E" || _DBGPX="DD"
        splog "[${_DBGPX}] kvPut(${KVKEY}):${_kvUid} (${KVRET}) //${KVRES[*]}"
    fi
    if [[ ${KVRET} -eq 0 ]]; then
        KVKEY="/byUid/${_kvUid}"
        KVRES="$(ETCDCTL_API=3 etcdctl put --prev-kv -- "${KVKEY}" "${_kvName}")"
        KVRET=$?
        if boolTrue "DDEBUG_KV" || [[ ${KVRET} -ne 0 ]]; then
            [[ ${KVRET} -ne 0 ]] && _DBGPX="E" || _DBGPX="DD"
            splog "[${_DBGPX}] kvPut(${KVKEY}):${_kvName} (${KVRET}) //${KVRES[*]}"
        fi
    fi
    return "${KVRET}"
}

function kvGet()
{
    local _kvKey="$1" _kvName="$2" _prefix="$3" _keysAndVals="$4"
    local KVRES="" KVRET=1 _line="" _pvo="1" _DBGPX=""
    local KVKEY="/${_kvKey}/${_kvName}"
    local _errFile="${TMPDIR}/etcdctl_get_err"
    local _kvGetLogFile="${TMPDIR}/etcdctl_get"
    [[ -z "${_keysAndVals}" ]] || _pvo=""
    if boolTrue "DDEBUG_KV"; then
        splog "[D] kvGet(${_kvKey}, ${_kvName}, ${_prefix}, ${_keysAndVals}) =-> ${KVKEY}"
    fi
    ETCDCTL_API=3 etcdctl get${_pvo:+ --print-value-only}${_prefix:+ --prefix} -- "${KVKEY}" 2>"${_errFile}" | tee "${_kvGetLogFile}"
    KVRET=$?
    if boolTrue "DEBUG_KV" || [[ ${KVRET} -ne 0 ]]; then
        boolTrue "DEBUG_KV" && _DBGPX="D" || _DBGPX="W"
        splog "[${_DBGPX}] get($*) stdout:'$(tr '\n' ' ' <"${_kvGetLogFile}" || true)' (${KVRET})"
        if [[ -s "${_errFile}" ]]; then
            while read -r -u "${errfh}" _line; do
               splog "[D] kvGet(${KVKEY}) stderr:${_line}"
            done {errfh}< <(cat "${_errFile}" || true)
        fi
    fi
    return "${KVRET}"
}

function kvGetUid()
{
    local _NAME="$1" _FATAL="$2"
    local ret=0 errmsg=""
    unset SP_UID
    SP_UID="$(kvGet byName "${_NAME}")"
    if [[ -z "${SP_UID}" ]]; then
        ret=1
        errmsg="Can't get StorPool generic name for ${_NAME}!"
        if [[ -n "${_FATAL}" ]]; then
            splog "[E] KV Error: ${errmsg}"
            exit "${ret}"
        else
            splog "[W] KV kvGetUid($*) ${errmsg}"
        fi
    fi
    export SP_UID
    return "${ret}"
}

function kvDel()
{
    local _kvName="$1" _kvUid="$2"
    local KVRET="" KVKEY="" line="" _DBGPX=""
    declare -a KVRES_A
    if boolTrue "DEBUG_KV"; then
        splog "[D] KV del byName:${_kvName:-n/a} byUid:${_kvUid:-n/a}"
    fi
    if [[ -n "${_kvName}" ]]; then
        KVKEY="/byName/${_kvName}"
        line="$(ETCDCTL_API=3 etcdctl del --prev-kv -- "${KVKEY}")"
        KVRET=$?
        read -r -a KVRES_A <<< "${line}"
        if boolTrue "DDEBUG_KV" || [[ ${KVRET} -ne 0 ]]; then
            [[ ${KVRET} -ne 0 ]] && _DBGPX="E" || _DBGPX="DD"
            splog "[${_DBGPX}] KV kvDel(${KVKEY}):${KVRES_A[2]} //${KVRES_A[0]} (${KVRET})"
        fi
    else
        if boolTrue "DDEBUG_KV"; then
            splog "[DD] KV kvDel byUid only"
        fi
        KVRET=0
    fi
    if [[ -n "${_kvUid}" ]] && [[ ${KVRET} -eq 0 ]]; then
        KVKEY="/byUid/${_kvUid}"
        line="$(ETCDCTL_API=3 etcdctl del --prev-kv -- "${KVKEY}")"
        KVRET=$?
        read -r -a KVRES_A <<< "${line}"
        if boolTrue "DDEBUG_KV" || [[ ${KVRET} -ne 0 ]]; then
            [[ ${KVRET} -ne 0 ]] && _DBGPX="E" || _DBGPX="DD"
            splog "[${_DBGPX}] KV kvDel(${KVKEY}):${KVRES_A[2]} //${KVRES_A[0]} (${KVRET})"
        fi
    fi
    return "${KVRET}"
}

function kvDelByKey()
{
    local KVKEY="$1"
    local KVRET=1 line="" _DBGPX=""
    declare -a KVRES_A
    if boolTrue "DEBUG_KV"; then
        splog "[D] KV del ByKey $*"
    fi
    line="$(ETCDCTL_API=3 etcdctl del --prev-kv -- "${KVKEY}")"
    KVRET=$?
    read -r -a KVRES_A <<< "${line}"
    if boolTrue "DDEBUG_KV" || [[ ${KVRET} -ne 0 ]]; then
        [[ ${KVRET} -ne 0 ]] && _DBGPX="E" || _DBGPX="DD"
        splog "[${_DBGPX}] kvDelByKey(${KVKEY}):${KVRES_A[2]} //${KVRES_A[0]} (${KVRET})"
    fi
    return "${KVRET}"
}

function oneCallXml()
{
    local _call="$1" _method="$2" _id="$3" _outfile="$4"
    local _errfile="${TMPDIR:-/tmp}/${_call}-${_id}.error"
    local _timefile="${TMPDIR:-/tmp}/${_call}-${_id}.time"
    local _onetry=${ONE_CALL_RETRIES:-3} _ret=1
    local _tmpXML="" _time="" _xml_lines=0 _debug_prefix=""
    declare -a _onecmd
    if [[ -z "${_outfile}" ]]; then
        _tmpXML="${TMPDIR:-/tmp}/${_call}-${_id}.XML"
        _outfile="${_tmpXML}"
    fi
    case "${_call}" in
        onevm|onehost|onedatastore|oneimage)
            read -r -a _onecmd <<< "${_call} ${_method} ${ONE_ARGS} -x ${_id}"
            ;;
        *)
            echo "oneCallXml($*) Error: Unknown call'"
            return 1
            ;;
    esac
    while :; do
        time ("${_onecmd[@]}" >"${_outfile}" 2>"${_errfile}") 2>"${_timefile}"
        _ret=$?
        _time="$(tr '\n' ' ' <"${_timefile}" | tr '\t' ' ' || true)"
        _xml_lines=$(wc -l "${_outfile}")
        if boolTrue "DEBUG_oneCallXml" || [[ ${_onetry} -lt 3 ]]; then
            boolTrue "DEBUG_oneCallXml" && _debug_prefix="D" || _debug_prefix="I"
            splog "[${_debug_prefix}] oneCallXml(${_onecmd[*]}) # ret=${_ret} time:${_time} xmlLines:${_xml_lines} _tmpXML='${_tmpXML}' _outfile='${_outfile}'"
        fi
        if [[ ${_ret} -eq 0 ]]; then
            break
        fi
        if [[ ${_onetry} -lt 1 ]]; then
            splog "'${_onecmd[*]} ${_id}' retry:${_onetry} Error: Timeout"
            exit "${_ret}"
        fi
        _onetry=$((_onetry-1))
        sleep 0.5
    done
    if [[ -n "${_tmpXML}" ]]; then
        cat "${_tmpXML}"
    fi
    return "${_ret}"
}

function oneHostInfo()
{
    local _name="$1" _force="$2"
    local ret=1 errmsg="" _tmpXML="" _XPATH="" _element=""
    local xfh=""
    [[ "${_name}" == "${HOST_NAME}" ]] || _force="nameDiffer"
    if [[ -n "${_force}" ]]; then
        _tmpXML="$(mktemp --tmpdir "oneHostInfo-${_name}-XXXXXX")"
        ret=$?
        if [[ ${ret} -ne 0 ]]; then
            errmsg="(oneHostInfo) Error: Can't create temp file! (ret:${ret})"
            log_error "${errmsg}"
            splog "${errmsg}"
            exit "${ret}"
        fi
        oneCallXml onehost show "${_name}" "${_tmpXML}"
        ret=$?
        if [[ ${ret} -ne 0 ]]; then
            errmsg="(oneHostInfo) Error: Can't get info for host '${_name}'! $(head -n 1 "${_tmpXML}") (ret:${ret})"
            log_error "${errmsg}"
            splog "${errmsg}"
            exit "${ret}"
        fi
        _XPATH="$(lookup_file "datastore/xpath.rb" || true)"
        declare -a _XPATH_A _XPATH_QUERY
        _XPATH_A=(
            "${_XPATH}"
            "--stdin"
        )
        _XPATH_QUERY=(
            "/HOST/ID"
            "/HOST/NAME"
            "/HOST/STATE"
            "/HOST/TEMPLATE/SP_OURID"
            "/HOST/TEMPLATE/SP_CLUSTER_ID"
            "/HOST/TEMPLATE/HOSTNAME"
        )
        sed -i '/\/>$/d' "${_tmpXML}"
        unset XPATH_ELEMENTS i
        while IFS='' read -r -u "${xfh}" -d '' _element; do
            XPATH_ELEMENTS[i++]="${_element}"
        done {xfh}< <("${_XPATH_A[@]}" < "${_tmpXML}" "${_XPATH_QUERY[@]}" 2>/dev/null || true)
        exec {xfh}<&-
        rm -f "${_tmpXML}"
        unset i
        HOST_ID="${XPATH_ELEMENTS[i++]}"
        HOST_NAME="${XPATH_ELEMENTS[i++]}"
        HOST_STATE="${XPATH_ELEMENTS[i++]}"
        HOST_SP_OURID="${XPATH_ELEMENTS[i++]}"
        HOST_SP_CLUSTER_ID="${XPATH_ELEMENTS[i++]}"
        HOST_HOSTNAME="${XPATH_ELEMENTS[i++]}"
    fi
    boolTrue "DEBUG_oneHostInfo" || return 0
    local _dbgmsg="ID:${HOST_ID} NAME:${HOST_NAME} STATE:${HOST_STATE}(${HostState[${HOST_STATE}]})"
    _dbgmsg+=" HOSTNAME:${HOST_HOSTNAME}"
    _dbgmsg+="${HOST_SP_OURID:+ HOST_SP_OURID=${HOST_SP_OURID}}"
    _dbgmsg+="${HOST_SP_CLUSTER_ID:+ HOST_SP_CLUSTER_ID=${HOST_SP_CLUSTER_ID}}"
    _dbgmsg+="${_force:+ force:${_force}}"
    splog "[D] oneHostInfo($*): ${_dbgmsg}"
}

function storpoolGetIdLOCAL()
{
    local _hst="$1" _common_domain="$2"
    CLIENT_OURID="$(/usr/sbin/storpool_confget -s "${_hst}" | grep SP_OURID | cut -d '=' -f 2 | tail -n 1 || true)"
    if [[ -z "${CLIENT_OURID}" ]]; then
        if [[ -n "${_common_domain}" ]]; then
            CLIENT_OURID="$(/usr/sbin/storpool_confget -s "${_hst}.${_common_domain}" | grep SP_OURID | cut -d '=' -f 2 | tail -n 1 || true)"
            if [[ -n "${CLIENT_OURID}" ]] && boolTrue "DEBUG_SP_OURID"; then
                splog "[D] storpoolGetIdLOCAL(${_hst}.${_common_domain}) CLIENT_OURID=${CLIENT_OURID}"
            fi
        fi
    elif boolTrue "DEBUG_SP_OURID"; then
        splog "[D] storpoolGetIdLOCAL($*) CLIENT_OURID=${CLIENT_OURID} (local storpool.conf)"
    fi
}
function storpoolGetIdBRIDGELIST()
{
    local _hst="$1" _common_domain="$2"
    local _bridge=""
    for _bridge in ${BRIDGE_LIST}; do
        CLIENT_OURID="$(${SSH:-ssh} "${_bridge}" /usr/sbin/storpool_confget -s "${_hst}" | grep SP_OURID | cut -d '=' -f 2 | tail -n 1 || true)"
        if [[ -n "${CLIENT_OURID}" ]]; then
            if boolTrue "DEBUG_SP_OURID"; then
                splog "[D] storpoolGetIdBRIDGELIST(${_hst}) CLIENT_OURID=${CLIENT_OURID} via ${_bridge}"
            fi
            break
        fi
        if [[ -n "${_common_domain}" ]]; then
            CLIENT_OURID="$(${SSH:-ssh} "${_bridge}" /usr/sbin/storpool_confget -s "${_hst}.${_common_domain}" | grep SP_OURID | cut -d '=' -f 2 | tail -n 1 || true)"
            if [[ -n "${CLIENT_OURID}" ]]; then
                if boolTrue "DEBUG_SP_OURID"; then
                    splog "[D] storpoolGetIdBRIDGELIST(${_hst}.${_common_domain}) CLIENT_OURID=${CLIENT_OURID} via ${_bridge}"
                fi
                break
            fi
        fi
    done
}
function storpoolGetIdCLONEGW()
{
    local _hst="$1" _common_domain="$2"
    if [[ -n "${CLONE_GW}" ]]; then
        CLIENT_OURID="$(${SSH:-ssh} "${CLONE_GW}" /usr/sbin/storpool_confget -s "\$(hostname)" | grep SP_OURID | cut -d '=' -f 2 | tail -n 1 || true)"
        if boolTrue "DEBUG_SP_OURID"; then
            splog "[D] storpoolGetIdCLONEGW(${_hst}) CLIENT_OURID=${CLIENT_OURID} (CLONE_GW:${CLONE_GW})"
        fi
    fi
}
function storpoolGetIdFROMHOST()
{
    local _hst="$1" _common_domain="$2"
    if [[ -z "${CLIENT_OURID}" ]]; then
        CLIENT_OURID="$(${SSH:-ssh} "${_hst}" /usr/sbin/storpool_confget | grep SP_OURID | cut -d '=' -f 2 | tail -n 1 || true)"
        if [[ -n "${CLIENT_OURID}" ]]; then
            if boolTrue "DEBUG_SP_OURID"; then
                splog "[D] storpoolGetIdFROMHOST(${_hst}) CLIENT_OURID=${CLIENT_OURID} (remote ${_hst}:/etc/storpool.conf)"
            fi
        fi
    fi
}
function storpoolGetIdONEHOST()
{
    local _hst="$1" _common_domain="$2"
    oneHostInfo "${_hst}"
    if [[ -n "${HOST_SP_OURID}" ]]; then
        if [[ -z "${HOST_SP_OURID//[[:digit:]]/}" ]]; then
            CLIENT_OURID="${HOST_SP_OURID}"
            if boolTrue "DEBUG_SP_OURID"; then
                splog "[D] storpoolGetIdONEHOST(${_hst}) CLIENT_OURID=${CLIENT_OURID}"
            fi
        else
            splog "[W] storpoolGetIdONEHOST(${_hst}): Has HOST_SP_OURID but not numeric:'${HOST_SP_OURID}'"
        fi
    fi
}
function storpoolGetIdHOSTHOSTNAME()
{
    local _hst="$1" _common_domain="$2"
    [[ -n "${HOST_HOSTNAME}" ]] || oneHostInfo "${_hst}"
    storpoolGetHost "${HOST_HOSTNAME}"
}
function storpoolClientId()
{
    local _hst="$1" _common_domain="${2:-${COMMON_DOMAIN}}"
    local _method="" _default=""
    for _default in LOCAL ONEHOST FROMHOST HOSTHOSTNAME; do
        if [[ "${STORPOOL_CLIENT_ID_SOURCES/${_default}/}" == "${STORPOOL_CLIENT_ID_SOURCES}" ]]; then
            STORPOOL_CLIENT_ID_SOURCES+=" ${_default}"
        fi
    done
    for _method in ${STORPOOL_CLIENT_ID_SOURCES}; do
        if type -t "storpoolGetId${_method}" >/dev/null; then
            "storpoolGetId${_method}" "${_hst}" "${_common_domain}"
            if [[ -n "${CLIENT_OURID}" ]]; then
                if [[ -z "${CLIENT_OURID//[[:digit:]]/}" ]]; then
                    echo "${CLIENT_OURID}"
                    if boolTrue "DEBUG_storpoolClientId"; then
                        splog "[D] storpoolClientId(${_hst}${_common_domain:+,${_common_domain}}) CLIENT_OURID=${CLIENT_OURID} (storpoolGetId${_method})"
                    fi
                    return 0
                else
                    splog "[W] storpoolClientId${_method}(${_hst}${_common_domain:+,${_common_domain}}) CLIENT_OURID has incorrect format '${CLIENT_OURID}'"
                fi
            fi
        else
            splog "[W] storpoolClientId(${_hst}${_common_domain:+,${_common_domain}}) unknown function storpoolGetId${_method}"
        fi
    done
    if boolTrue "DEBUG_storpoolClientId"; then
        splog "[D] storpoolClientId(${_hst}${_common_domain:+,${_common_domain}}) empty CLIENT_OURID //sources:${STORPOOL_CLIENT_ID_SOURCES}"
    fi
    return 1
}

function storpoolApi()
{
    local _method="$1" _data="$2" _max_time="${3:-300}"
    local _apiCmd="" _ret=1
    if [[ -z "${SP_API_HTTP_HOST}" ]]; then
        if [[ -x "/usr/sbin/storpool_confget" ]]; then
            # shellcheck disable=SC2046
            eval $(/usr/sbin/storpool_confget -S || true)
        fi
        if [[ -z "${SP_API_HTTP_HOST}" ]]; then
            splog "[E][storpoolApi] ERROR! SP_API_HTTP_HOST is not set!"
            return "${_ret}"
        fi
    fi
    if boolTrue "NO_PROXY_API"; then
        export NO_PROXY="${NO_PROXY:+${NO_PROXY},}${SP_API_HTTP_HOST}"
    fi
    if boolTrue "DDEBUG_SP_RUN_CMD"; then
        splog "[DD] SP_API_HTTP_HOST=${SP_API_HTTP_HOST} SP_API_HTTP_PORT=${SP_API_HTTP_PORT} SP_AUTH_TOKEN=${SP_AUTH_TOKEN:+available} ${NO_PROXY:+NO_PROXY=${NO_PROXY}} $*"
    fi
    if boolTrue "DDDEBUG_SP_RUN_CMD"; then
        splog "[DDD] $0 $*"
    fi
    if boolTrue "storpoolApiCmdline"; then
        _apiCmd="curl -s -S -q -N -H 'Authorization: Storpool v1:${SP_AUTH_TOKEN}' \
        --connect-timeout '${SP_API_CONNECT_TIMEOUT:-1}' \
        --max-time '${_max_time}' ${_data:+-d "${_data}"} \
        '${SP_API_HTTP_HOST}:${SP_API_HTTP_PORT:-81}/ctrl/1.0/${_method}'"
        echo "${_apiCmd}"
    else
        curl -s -S -q -N -H "Authorization: Storpool v1:${SP_AUTH_TOKEN}" \
        --connect-timeout "${SP_API_CONNECT_TIMEOUT:-1}" \
        --max-time "${_max_time}" ${_data:+-d "${_data}"} \
        "${SP_API_HTTP_HOST}:${SP_API_HTTP_PORT:-81}/ctrl/1.0/${_method}" 2>/dev/null
        _ret=$?
        if [[ ${_ret} -ne 0 ]]; then
            splog "${_method} ${_data:+${_data}} max-time:${_max_time} ret:${_ret}"
        fi
        return "${_ret}"
    fi
    return "${_ret}"
}

function storpoolWrapper()
{
    local method="$1"
    local json="" res="" ret="" ok="" error_name="" cmd="${method}"
    TRANSIENT="false"
    if boolTrue "MULTICLUSTER"; then
        if [[ -n "${DO_MULTICLUSTER}" ]]; then
            cmd="MultiCluster"
            if [[ -n "${DO_ALLCLUSTERS}" ]]; then
                cmd+="/AllClusters"
            else
                if boolTrue "DDDEBUG_SP_RUN_CMD"; then
                    splog "DO_ALLCLUSTERS is not set${SP_LOCATION:+ SP_LOCATION=${SP_LOCATION}}"
                fi
            fi
            cmd+="/${method}"
        else
            if boolTrue "DDDEBUG_SP_RUN_CMD"; then
                splog "DO_MULTICLUSTER is not set"
            fi
        fi
        if [[ -n "${DO_REMOTE}" ]]; then
            cmd="RemoteCommand/${SP_LOCATION:-${DO_REMOTE}}/${cmd}"
        else
            if boolTrue "DDDEBUG_SP_RUN_CMD"; then
                splog "DO_REMOTE is not set${SP_LOCATION:+ using SP_LOCATION=${SP_LOCATION}}"
            fi
        fi
    fi
    case "${method}" in
        # POST API {JSON}
        VolumesReassignWait)
            shift
            res="$(storpoolApi "${cmd}" "{$1}" "${SP_API_TIMEOUT:-300}")"
            ret=$?
            if [[ ${ret} -ne 0 ]]; then
                splog "API ${cmd} {$1} communication error:${res} (${ret})"
            else
                ok="$(echo "${res}"|jq -r ".data|.ok" 2>&1)"
                if [[ "${ok}" == "true" ]]; then
                    if boolTrue "DEBUG_SP_RUN_CMD"; then
                        splog "API ${cmd} {$1} response:${res}"
                    fi
                else
                    error_name="$(echo "${res}" | jq -r ".error|.name" 2>&1)"
                    TRANSIENT="$(echo "${res}" | jq -r ".error|.transient" 2>&1)"
                    splog "API ${cmd} {$1} ERROR:${error_name} ${res//$'\n'/ }"
                    ret=1
                    [[ "${error_name}" != "objectDoesNotExist" ]] || ret=2
                    [[ "${error_name}" != "invalidParam" ]] || ret=3
                    [[ "${error_name}" != "jsonError" ]] || ret=4
                    [[ "${error_name}" != "preconditionViolation" ]] || ret=5
                fi
            fi
            ;;
        # POST API {JSON} -> ~sp_uid
        VolumeCreate|VolumeBackup)
            shift
            res="$(storpoolApi "${cmd}" "{$1}" "${SP_API_TIMEOUT:-300}")"
            ret=$?
            if [[ ${ret} -ne 0 ]]; then
                splog "API ${cmd} {$1} communication error:${res} (${ret})"
            else
                ok="$(echo "${res}" | jq -r ".data|.ok" 2>&1)"
                if [[ "${ok}" == "true" ]]; then
                    if boolTrue "DEBUG_SP_RUN_CMD"; then
                        splog "API ${cmd} {$1} response:${res}"
                    fi
                    echo "${res}" | jq -r '.data.name'
                else
                    error_name="$(echo "${res}" | jq -r ".error|.name" 2>&1)"
                    TRANSIENT="$(echo "${res}" | jq -r ".error|.transient" 2>&1)"
                    splog "API ${cmd} {$1} ERROR:${error_name} ${res//$'\n'/ }"
                    ret=1
                    [[ "${error_name}" != "objectDoesNotExist" ]] || ret=2
                    [[ "${error_name}" != "invalidParam" ]] || ret=3
                    [[ "${error_name}" != "jsonError" ]] || ret=4
                    [[ "${error_name}" != "preconditionViolation" ]] || ret=5
                fi
            fi
            ;;
        # POST API {JSON} -> {JSON}
        VolumesGroupSnapshot)
            export DATA_JSON="${TMPDIR}/${method}.json"
            shift
            res="$(storpoolApi "${cmd}" "{$1}" "${SP_API_TIMEOUT:-300}" | tee "${DATA_JSON}")"
            ret=$?
            if [[ ${ret} -ne 0 ]]; then
                splog "API ${cmd} {$1} communication error:${res} (${ret})"
            else
                ok="$(echo "${res}" | jq -r ".data|.ok" 2>&1)"
                if [[ "${ok}" == "true" ]]; then
                    if boolTrue "DEBUG_SP_RUN_CMD"; then
                        splog "API ${cmd} {$1} response:${res}"
                    fi
                    echo "${res}"
                else
                    error_name="$(echo "${res}" | jq -r ".error|.name" 2>&1)"
                    TRANSIENT="$(echo "${res}" | jq -r ".error|.transient" 2>&1)"
                    splog "API ${cmd} {$1} ERROR:${error_name} ${res//$'\n'/ }"
                    ret=1
                    [[ "${error_name}" != "objectDoesNotExist" ]] || ret=2
                    [[ "${error_name}" != "invalidParam" ]] || ret=3
                    [[ "${error_name}" != "jsonError" ]] || ret=4
                    [[ "${error_name}" != "preconditionViolation" ]] || ret=5
                fi
            fi
            ;;
        # POST API/NAME {JSON} -> ~sp_uid
        VolumeSnapshot)
            shift
            res="$(storpoolApi "${cmd}/$1" "{$2}" "${SP_API_TIMEOUT:-300}")"
            ret=$?
            if [[ ${ret} -ne 0 ]]; then
                splog "API ${cmd}/$1 {$2} communication error:${res} (${ret})"
            else
                ok="$(echo "${res}" | jq -r ".data|.ok" 2>&1)"
                if [[ "${ok}" == "true" ]]; then
                    if boolTrue "DEBUG_SP_RUN_CMD"; then
                        splog "API ${cmd}/$1 {$2} response:${res}"
                    fi
                    snapshotName="$(echo "${res}" | jq -r '.data.snapshotGlobalId')"
                    echo "~${snapshotName}"
                else
                    error_name="$(echo "${res}" | jq -r ".error|.name" 2>&1)"
                    TRANSIENT="$(echo "${res}" | jq -r ".error|.transient" 2>&1)"
                    splog "API ${cmd}/$1 {$2} ERROR:${error_name} ${res//$'\n'/ }"
                    ret=1
                    [[ "${error_name}" != "objectDoesNotExist" ]] || ret=2
                    [[ "${error_name}" != "invalidParam" ]] || ret=3
                    [[ "${error_name}" != "jsonError" ]] || ret=4
                    [[ "${error_name}" != "preconditionViolation" ]] || ret=5
                fi
            fi
            ;;
        # POST API/NAME {JSON} -> globalId
        VolumeRevert)
            shift
            res="$(storpoolApi "${cmd}/$1" "{$2}" "${SP_API_TIMEOUT:-300}")"
            ret=$?
            if [[ ${ret} -ne 0 ]]; then
                splog "API ${cmd}/$1 {$2} communication error:${res} (${ret})"
            else
                ok="$(echo "${res}" | jq -r ".data|.ok" 2>&1)"
                if [[ "${ok}" == "true" ]]; then
                    if boolTrue "DEBUG_SP_RUN_CMD"; then
                        splog "API ${cmd}/$1 {$2} response:${res}"
                    fi
                    echo "${res}" | jq -r '.data.globalId'
                else
                    error_name="$(echo "${res}" | jq -r ".error|.name" 2>&1)"
                    TRANSIENT="$(echo "${res}" | jq -r ".error|.transient" 2>&1)"
                    splog "API ${cmd}/$1 {$2} ERROR:${error_name} ${res//$'\n'/ }"
                    ret=1
                    [[ "${error_name}" != "objectDoesNotExist" ]] || ret=2
                    [[ "${error_name}" != "invalidParam" ]] || ret=3
                    [[ "${error_name}" != "jsonError" ]] || ret=4
                    [[ "${error_name}" != "preconditionViolation" ]] || ret=5
                fi
            fi
            ;;
        # POST API/NAME {JSON} // ${TMPDIR}/${cmd}.json
        VolumeDelete|VolumeFreeze|VolumeUpdate|SnapshotUpdate|SnapshotDelete)
            export DATA_JSON="${TMPDIR}/${method}.json"
            shift
            res="$(storpoolApi "${cmd}/$1" "{$2}" "${SP_API_TIMEOUT:-300}" | tee "${DATA_JSON}")"
            ret=$?
            if [[ ${ret} -ne 0 ]]; then
                splog "API ${cmd}/$1 {$2} communication error:${res} (${ret})"
            else
                ok="$(echo "${res}" | jq -r ".data|.ok" 2>&1)"
                if [[ "${ok}" == "true" ]]; then
                    if boolTrue "DEBUG_SP_RUN_CMD"; then
                        splog "API ${cmd}/$1 {$2} response:${res}"
                    fi
                else
                    error_name="$(echo "${res}" | jq -r ".error|.name" 2>&1)"
                    TRANSIENT="$(echo "${res}" | jq -r ".error|.transient" 2>&1)"
                    splog "API ${cmd}/$1 {$2} ERROR:${error_name} ${res//$'\n'/ }"
                    ret=1
                    [[ "${error_name}" != "objectDoesNotExist" ]] || ret=2
                    [[ "${error_name}" != "invalidParam" ]] || ret=3
                    [[ "${error_name}" != "jsonError" ]] || ret=4
                    [[ "${error_name}" != "preconditionViolation" ]] || ret=5
                fi
            fi
            ;;
        # GET API/NAME -> {JSON} // ${TMPDIR}/${cmd}.json
        Volume|Snapshot)
            export DATA_JSON="${TMPDIR}/${method}.json"
            shift
            res="$(storpoolApi "${cmd}/$1" "" "${SP_API_TIMEOUT:-300}" | tee "${DATA_JSON}")"
            ret=$?
            if [[ ${ret} -ne 0 ]]; then
                splog "API ${cmd}/$1 communication error:${res} (${ret})"
            else
                error_descr="$(echo "${res}" | jq -r ".error|.descr" 2>&1)"
                if [[ "${error_descr}" == "null" ]]; then
                    if boolTrue "DEBUG_SP_RUN_CMD"; then
                        splog "API ${cmd}/$1 response:${res:0:850}"
                    fi
                else
                    error_name="$(echo "${res}" | jq -r ".error|.name" 2>&1)"
                    TRANSIENT="$(echo "${res}" | jq -r ".error|.transient" 2>&1)"
                    splog "API ${cmd}/$1 ERROR:${error_name} ${res//$'\n'/ }"
                    ret=1
                    [[ "${error_name}" != "objectDoesNotExist" ]] || ret=2
                    [[ "${error_name}" != "invalidParam" ]] || ret=3
                fi
            fi
            ;;
        # GET API -> {JSON} // ${TMPDIR}/${cmd}.json
        AttachmentsList|SnapshotsList|VolumesList|VolumeTemplatesStatus|SnapshotsSpace|VolumesSpace|VolumeTemplatesList|ClustersList|ServicesList)
            export DATA_JSON="${TMPDIR}/${method}.json"
            shift
            res="$(storpoolApi "${cmd}" "" "${SP_API_TIMEOUT:-300}" | tee "${DATA_JSON}")"
            ret=$?
            if [[ ${ret} -ne 0 ]]; then
                splog "API ${cmd} communication error:${res} ${DATA_JSON} (${ret})"
            else
                error_descr="$(jq -r ".error|.descr" "${DATA_JSON}" 2>&1)"
                if [[ "${error_descr}" == "null" ]]; then
                    if boolTrue "DEBUG_SP_RUN_CMD"; then
                        splog "API ${cmd} response:${res:0:512}... file:${DATA_JSON}"
                    fi
                else
                    error_name="$(echo "${res}" | jq -r ".error|.name" 2>&1)"
                    TRANSIENT="$(echo "${res}" | jq -r ".error|.transient" 2>&1)"
                    splog "API ${cmd} ERROR:${error_name} ${res//$'\n'/ }"
                    ret=1
                    [[ "${error_name}" != "objectDoesNotExist" ]] || ret=2
                    [[ "${error_name}" != "invalidParam" ]] || ret=3
                    [[ "${error_name}" != "multiCluster" ]] || ret=4
                fi
            fi
            ;;
        *)
            splog "Error: Unexpected command '${cmd}' ($*)"
            ret=255
            ;;
    esac
    return "${ret}"
}

function splogFile() {
    local _logfile="$1"
    local _line="" logfh=""
    if boolTrue "DEBUG_splogFile"; then
        splog "[D][splogFile] $*"
    fi
    while read -r -u "${logfh}" _line; do
        splog "splogFile: ${_line}"
    done {logfh}< <(cat "${_logfile}" 2>&1 || true)
    exec {logfh}<&-
    [[ -z "${2}" ]] || rm -f "${_logfile}"
}

function tagsHelper()
{
    local _TAG_KEY="$1" _TAG_VAL="$2"
    local _TAGSJSON="" _tagKey=""
    IFS=';' read -r -a _tagVals <<< "${_TAG_VAL}"
    IFS=';' read -r -a _tagKeys <<< "${_TAG_KEY}"
    for i in ${!_tagKeys[*]}; do
        _tagKey="${_tagKeys[i]//[[:space:]]/}"
        [[ -n ${_tagKey} ]] || continue
        _TAGSJSON+="${_TAGSJSON:+,}\"${_tagKey}\":\"${_tagVals[i]//[[:space:]]/}\""
    done
    echo "${_TAGSJSON}"
}

function storpoolRetry() {
    local _retries=${STORPOOL_RETRIES:-10}
    local _errfile="" _err="1" DO_MULTICLUSTER="${DO_MULTICLUSTER}"
    _errfile="$(mktemp --tmpdir storpoolRetry-XXXXXXXX.err || mktemp --tmpdir=/tmp storpoolRetry-XXXXXX.err)"
    if boolTrue "DEBUG_storpoolRetry"; then
        if boolTrue "DDEBUG_storpoolRetry"; then
            splog "[DD] ${SP_API_HTTP_HOST:+${SP_API_HTTP_HOST}:}API $* #${_errfile}"
        else
            for _last_cmd;do :;done
            if [[ ${_last_cmd} != "list" ]]; then
                if boolTrue "DEBUG_storpoolRetry"; then
                    splog "[D] ${SP_API_HTTP_HOST:+${SP_API_HTTP_HOST}:} $*"
                fi
            fi
        fi
    fi
    while true; do
        TRANSIENT="false"
        if storpoolWrapper "$@" 2>"${_errfile}"; then
            _err=$?
            if boolTrue "DEBUG_storpoolRetry"; then
                splogFile "${_errfile}" clean
            fi
            break
        else
            _err=$?
            if ! boolTrue "DO_MULTICLUSTER"; then
                if [[ ${_err} -eq 2 ]] && [[ -z "${NO_MC_RETRY}" ]]; then
                    DO_MULTICLUSTER=1
                    splog "Retry with MultiCluster '$*'"
                    continue
                fi
            fi
            if boolTrue "_SOFT_FAIL"; then
                if ! boolTrue "_QUIET_FAIL"; then
                    splog "Warn: $* SOFT_FAIL"
                    splogFile "${_errfile}" clean
                fi
                if [[ "${TRANSIENT,,}" != "true" ]]; then
                    break
                fi
            fi
            if [[ "${TRANSIENT,,}" == "true" ]]; then
                # retry forever, reduce logs flooding with a bit longer retry
                _retries=$((_retries + 1))
                splog "VM ${VM_ID} TRANSIENT error! Waiting ${TRANSIENT_ERROR_SLEEP_SECONDS:-3} seconds before retry"
                # reduce logs flooding with a bit longer delay
                sleep "${TRANSIENT_ERROR_SLEEP_SECONDS:-3}"
            else
                splog "TRANSIENT=${TRANSIENT}"
            fi
            _retries=$((_retries - 1))
            if [[ ${_retries} -lt 1 ]]; then
                splog "storpoolRetry($*) FAILED (try:[${_retries}], err:${_err})"
                splogFile "${_errfile}" clean
                exit 1
            fi
            if [[ ${_err} -gt 1 ]]; then
                splog "storpoolRetry($*) FAILED (try:${_retries}, err:[${_err}])"
                splogFile "${_errfile}"
                exit "${_err}"
            fi
            splogFile "${_errfile}"
        fi
        sleep .1
        splog "API retry ${_retries} storpool $* (err:${_err})"
    done
    if [[ -f "${_errfile}" ]]; then
        rm -f "${_errfile}"
    fi
    return "${_err}"
}

function storpoolVolumeInfo()
{
    local _SP_UID="$1" STORPOOL_RETRIES="${2:-${STORPOOL_RETRIES}}"
    local _V_TAGS="" _RET=1
    if boolTrue "DDEBUG_storpoolVolumeInfo"; then
        splog "[DD]storpoolVolumeInfo($*) DO_REMOTE=${DO_REMOTE} DO_MULTICLUSTER=${DO_MULTICLUSTER} STORPOOL_RETRIES=${STORPOOL_RETRIES}"
    fi
    V_SIZE=
    V_PARENT_NAME=
    V_TEMPLATE_NAME=
    V_TYPE=
    V_GLOBAL_ID=
    V_PRESERVED_GLOBAL_ID=
    V_CLUSTER_ID=
    V_TAG_KEYS=
    V_TAG_VALS=
    DO_MULTICLUSTER=1 DO_REMOTE="" storpoolRetry Volume "${_SP_UID}"
    _RET=$?
    if [[ ${_RET} -eq 0 ]]; then
        IFS=';' read -r V_SIZE V_PARENT_NAME V_GLOBAL_ID V_PRESERVED_GLOBAL_ID V_TEMPLATE_NAME V_CLUSTER_ID V_TAGS <<< "$(jq -r \
            '.data[]|"\(.size|tostring);\(.parentName);\(.globalId);\(.preservedGlobalId);\(.templateName);\(.clusterId);\(.tags|tostring)"' \
            "${TMPDIR}/Volume.json" || true)"
        unset V_TAGS_ARR
        declare -g -A V_TAGS_ARR
        while read -r -u "${spfh}" tagline; do
            _TAG_KEY="${tagline%%=*}"
            _TAG_VAL="${tagline#*=}"
            V_TAGS_ARR["${_TAG_KEY}"]="${_TAG_VAL}"
            V_TAG_KEYS+="${V_TAG_KEYS:+;}${_TAG_KEY}"
            V_TAG_VALS+="${V_TAG_VALS:+;}${_TAG_VAL}"
        done {spfh}< <(echo "${V_TAGS}" | jq -r 'to_entries[]|"\(.key|tostring)=\(.value|tostring)"' || true)
        exec {spfh}<&-
        V_TYPE="${V_TAGS_ARR["type"]}"
    fi
    export V_SIZE V_PARENT_NAME V_GLOBAL_ID V_TEMPLATE_NAME V_CLUSTER_ID V_TAGS
    if boolTrue "DEBUG_storpoolVolumeInfo"; then
        splog "[D]storpoolVolumeInfo(${_SP_UID}) size:${V_SIZE} parentName:${V_PARENT_NAME} globalId:${V_GLOBAL_ID}${V_PRESERVED_GLOBAL_ID:+preservedGlobaId:${V_PRESERVED_GLOBAL_ID}} templateName:${V_TEMPLATE_NAME} tags:${V_TAGS}${V_TYPE:- tag.type:${V_TYPE}} (${_RET})"
    fi
    return "${_RET}"
}

function storpoolExist()
{
    local _NAME="$1" _ENTRY="${2:-${STORPOOL_EXIST_HINT}}" _RETRIES="${3:-1}"
    local _RET="1" _method="" _LOOP=""
    unset X_FOUND_AS X_CLUSTER_ID
    for _LOOP in ${_ENTRY}; do
        _method="${_LOOP}Update"
        DO_MULTICLUSTER="1" DO_REMOTE="" _SOFT_FAIL="1" _QUIET_FAIL="1" storpoolRetry "${_method}" "${_NAME}" ""
        _RET=$?
        if [[ ${_RET} -eq 0 ]]; then
            X_FOUND_AS="${_LOOP}"
            read -r X_CLUSTER_ID <<< "$(jq -r '.clusterId' "${TMPDIR}/${_method}.json" || true)"
            export X_CLUSTER_ID X_FOUND_AS
            break
        fi
    done
    if boolTrue "DEBUG_storpoolExist" || [[ ${_RET} -ne 0 ]]; then
        boolTrue "DEBUG_storpoolExist" && _DBGPX="D" || _DBGPX="E"
        splog "[${_DBGPX}]storpoolExist(${_NAME}, '${_ENTRY}', ${_RETRIES}) ${X_FOUND_AS:-not found}, clusterId ${X_CLUSTER_ID:-not found} (${_RET})"
    fi
    return "${_RET}"
}

function storpoolLocate()
{
    local _NAME="$1" _ENTRY="$2" _RETRIES="${3:-1}"
    local DO_REMOTE="" _RET=1 cluster="" _method="" JSFILE="" _tagline=""
    local NO_MC_RETRY=1 _SOFT_FAIL=1
    unset X_NAME X_SIZE X_GLOBAL_ID X_TAGS X_TYPE
    unset X_TEMPLATE_NAME X_PARENT_NAME
    unset X_TAGS_ARR
    if boolTrue "DDEBUG_storpoolLocate"; then
        splog "[DD](${_NAME}, ${_ENTRY}, ${_RETRIES})"
    else
        # shellcheck disable=SC2034
        local DEBUG_SP_RUN_CMD=""
    fi
    if storpoolExist "${_NAME}" "${_ENTRY}" "${_RETRIES}"; then
        _method="${X_FOUND_AS}sList"
        DO_MULTICLUSTER=1 DO_ALLCLUSTERS=1 storpoolRetry "${_method}"
        JSFILE="${TMPDIR}/${_method}.json"
        IFS=';' read -r X_NAME X_SIZE X_PARENT_NAME X_GLOBAL_ID X_TEMPLATE_NAME X_TAGS <<< "$(jq -r \
            --arg cId "${X_CLUSTER_ID}" \
            '.data.clusters[]|select(.clusterId==$cId).response.data[]|"\(.name);\(.size|tostring);\(.parentName);\(.globalId);\(.templateName);\(.tags|tostring)"' \
            "${JSFILE}" | grep -e "^${_NAME};" || true)"
        if [[ -n ${X_SIZE} ]]; then
            _RET=0
            declare -g -A X_TAGS_ARR
            while read -r -u "${spfh}" _tagline; do
                X_TAGS_ARR["${_tagline%%=*}"]="${_tagline#*=}"
            done {spfh}< <(echo "${X_TAGS}" | jq -r 'to_entries[]|"\(.key|tostring)=\(.value|tostring)"' || true)
            X_TYPE="${X_TAGS_ARR["type"]}"
        fi
        export X_NAME X_SIZE X_PARENT_NAME X_GLOBAL_ID X_TEMPLATE_NAME X_TAGS X_TAGS_ARR
    fi
    if boolTrue "DEBUG_storpoolLocate"; then
        splog "[D](${_NAME}) ${X_FOUND_AS} clusterId:${X_CLUSTER_ID} size:${X_SIZE} parentName:${X_PARENT_NAME} globalId:${X_GLOBAL_ID} templateName:${X_TEMPLATE_NAME} tags:${X_TAGS}${X_TYPE:- tag.type:${X_TYPE}} (${_RET})"
    fi
    return "${_RET}"
}

function storpoolVolumeExists()
{
    local _match="$1" _type=${2:-globalId}
    local _RET=1 _RES=""
    case "${_type}" in
        byName)
            _RES=$(kvGet byName "${_match}")
            if [[ -n ${_RES} ]]; then
                _RET=0
                SP_UID="${_RES}"
            fi
            if boolTrue "DDEBUG_storpoolVolumeExists"; then
                splog "[DD] KV ${_match} (${_RET})"
            fi
            ;;
        *)
            storpoolLocate "${_match}" "Volume" 2
            _RET=$?
            if boolTrue "DDEBUG_storpoolVolumeExists"; then
                splog "[DD] SP ${_match} (${_RET})"
            fi
            ;;
    esac
    if boolTrue "DEBUG_storpoolVolumeExists"; then
        splog "[D]($*): ${_RES:+res:"${_RES}" }return ${_RET}"
    fi
    return "${_RET}"
}

function storpoolVolumeCheck()
{
    local _match="$1" _type="$2"
    if storpoolVolumeExists "${_match}" "${_type}"; then
        errmsg="Error: StorPool volume ${_match} exists"
        splog "${errmsg}"
        log_error "${errmsg}"
        exit 1
    fi
}

function storpoolVolumeCreate()
{
    local _SP_VOL="$1" _SP_SIZE="$2" _SP_TEMPLATE="$3" _TAG_KEY="$4" _TAG_VAL="$5"
    local _RET=1 _DATA="" _TAGS=""
    _TAGS="$(tagsHelper "img;${LOC_TAG};virt${_TAG_KEY:+;${_TAG_KEY}}" "${_SP_VOL};${LOC_TAG_VAL};one${_TAG_VAL:+;${_TAG_VAL}}")"
    _DATA="\"size\":\"${_SP_SIZE}\",\"tags\":{${_TAGS}},\"template\":\"${_SP_TEMPLATE}\""
    SP_UID=$(storpoolRetry VolumeCreate "${_DATA}")
    _RET=$?
    if [[ -n ${SP_UID} ]]; then
        kvPut "${_SP_VOL}" "${SP_UID}"
        _RET=$?
    fi
    return "${_RET}"
}

function storpoolVolumeStartswith()
{
    local _MATCH="$1" globalid="" sp_uid="" tags="" _RET=1 spfh=""
    declare -A spnames_a  # spnames_a[SP_UID]=SP_NAME
    declare -A spuids_a  # spuids_a[SP_UID]=CLUSTER_ID
    DO_MULTICLUSTER=1 DO_ALLCLUSTERS=1 DO_REMOTE="" storpoolRetry VolumesList
    _RET=$?
    if [[ ${_RET} -ne 0 ]]; then
        splog "StorPool API error ${_RET}"
        return "${_RET}"
    fi
    while read -r -u "${spfh}" clusterid cluster sp_uid globalid tags; do
        splog "(${_MATCH}) clusterId=${clusterid}(${cluster}) sp_uid=${sp_uid} globalId=${globalid} tags ${tags} //from VolumesList"
        spuids_a["${sp_uid}"]="${clusterid}"
    done {spfh}< <(jq -r --arg match "${_MATCH}" \
                '.data.clusters[]|"\(.clusterId) \(.response.data[]|select(.tags.img|tostring|startswith($match))|"\(.name) \(.globalId) \(.tags|tostring)")"' \
                 "${TMPDIR}/VolumesList.json" || true)
    exec {spfh}<&-
    if [[ "${_MATCH:0:1}" != "~" ]]; then
        for sp_uid in $(kvGet byName "${_MATCH}" startswith); do
            splog "(${_MATCH}) ${sp_uid} //from kvGet startswith"
            spnames_a["${sp_uid}"]="${sp_uid}"
        done
    fi
    [[ -z "${spnames_a[*]}" ]] || echo "${spnames_a[*]}"
    if boolTrue "DEBUG_storpoolVolumeStartswith"; then
        splog "[D] spuids_a:[${spuids_a[*]}] spnames_a:[${spnames_a[*]}]"
    fi
}

function storpoolVolumeBackup()
{
    local _VOL_UID="$1" _SP_VOL="$2" _REMOTE_DATA="$3"
    local _TAGS="" _REMOTE="" _k="" _json="" _RET=1 _element=""
    IFS=':' read -r -a _rdata <<<"${_REMOTE_DATA}"

    for _element in "${_rdata[@]}"; do
        if [[ -z ${_REMOTE} ]]; then
            _REMOTE="${_element}"
            continue
        fi
        [[ -z ${_TAGS} ]] || _TAGS+=","
        _k="${_element%%=*}"
        _TAGS+="\"${_k//[[:space:]]/}\":\"${_element#*=}\""
    done

    [[ -z "${_TAGS}" ]] || _TAGS="\"del\":\"y\"}"

    _json="\"volume\":\"${_VOL_UID}\",\"remote\":\"${_REMOTE}\",\"tags\":{${_TAGS}}"

    DO_MULTICLUSTER=1 storpoolRetry VolumeBackup "${_json}" >/dev/null
    _RET=$?
    if [[ ${_RET} -ne 0 ]]; then
        DO_MULTICLUSTER=1 storpoolVolumeRename "${_VOL_UID}" "${_SP_VOL}" "${_SP_VOL}-$(date +%s||true)" "" "${_TAGS}" >/dev/null
        _RET=$?
    fi
    return "${_RET}"
}

function storpoolDelete()
{
    local _SP_UID="$1" _FORCE="$2" _SNAPSHOTS="$3" _REMOTE="$4" _DD_TAGS="$5" _UID_ONLY="$6"
    local _ret=0 DO_MULTICLUSTER=1 _SP_VOL="" json=""
    local _snapshot="" _DELAY_DELETE=""

    _SP_VOL="$(kvGet byUid "${_SP_UID}")"
    if boolTrue "DEBUG_storpoolDelete"; then
        splog "[D]($*) (KV byUid -> ${_SP_VOL})"
    fi
    # TODO: handdle temporary unavailable volumes/snapshots
    if [[ -n "${ONLY_DELETE}" ]] || storpoolExist "${_SP_UID}"; then
        DO_REMOTE="${X_CLUSTER_ID:+~${X_CLUSTER_ID}}"
        case "${ONLY_DELETE,,}" in
            volume)
                _snapshot=""
                _REMOTE=""
                _DELAY_DELETE=""
                ;;
            snapshot)
                _snapshot=1
                _REMOTE=""
                _DELAY_DELETE=""
                ;;
            *)
                _DELAY_DELETE="${DELAY_DELETE}"
                [[ "${X_FOUND_AS,,}" == "volume" ]] || _snapshot=1
                DO_REMOTE="" storpoolDetach "${_SP_UID}" "${_FORCE}" "" "all" "" "${_snapshot}"
                _ret=$?
                ;;
        esac

        if [[ -n "${_REMOTE}" ]] && [[ -z "${_snapshot}" ]]; then
            storpoolVolumeBackup "${_SP_UID}" "${_SP_VOL}" "${_REMOTE}"
            _ret=$?
            if [[ ${_ret} -ne 0 ]]; then
                splog "[E] Failed to create a (remote) backup. (${_ret})"
                return "${_ret}"
            fi
        fi
        if [[ -n "${_DELAY_DELETE}" ]] && [[ -z "${_snapshot}" ]]; then
            local DELAY_DELETE_tmp="${_DELAY_DELETE//[[:digit:]]/}"
            if [[ -n "${DELAY_DELETE_tmp}" ]] && [[ -z "${DELAY_DELETE_tmp/[smhd]/}" ]]; then
                json="\"deleteAfter\":$(delayDeleteSeconds "${_DELAY_DELETE}")"
                if [[ -n "${_DD_TAGS}" ]]; then
                    json+=",\"tags\":{${_DD_TAGS}}"
                fi
                DO_REMOTE="" storpoolRetry VolumeSnapshot "${_SP_UID}" "${json}" >/dev/null
                _ret=$?
                if [[ ${_ret} -eq 0 ]]; then
                    DO_REMOTE="" storpoolRetry VolumeDelete "${_SP_UID}" >/dev/null
                    _ret=$?
                else
                   splog "[E]Can't create anonymous snapshot for ${_SP_UID} (${_SP_VOL})!"
                fi
            else
                local msg="Unsupported format in DELAY_DELETE='${_DELAY_DELETE}'!" newName=""
                local _msgpx="E"
                newName="${_SP_VOL#*~}_DELETE$(date +%s||true)"
                DO_REMOTE="" storpoolVolumeRename "${_SP_UID}" "${_SP_VOL}" "${newName}" >/dev/null
                _ret=$?
                if [[ ${_ret} -ne 0 ]]; then
                    storpoolVolumeFreeze "${_SP_UID}" "volume"
                    _ret=$?
                    if [[ ${_ret} -eq 0 ]]; then
                        msg+=" ${_SP_UID} converted to snapshot ${newName}"
                        _msgpx="I"
                    else
                        msg+=" Unable to convert ${_SP_UID} as snapshot ${newName}"
                    fi
                else
                    msg+=" Unable to rename ${_SP_UID} to ${newName}."
                fi
                splog "[${_msgpx}]${msg}"
            fi
        else
            if [[ -n "${_snapshot}" ]]; then
                DO_REMOTE="" storpoolRetry SnapshotDelete "${_SP_UID}" >/dev/null
            else
                DO_REMOTE="" storpoolRetry VolumeDelete "${_SP_UID}" >/dev/null
            fi
            _ret=$?
        fi
        if boolTrue "_UID_ONLY"; then
            kvDel "" "${_SP_UID}"
        else
            kvDel "${_SP_VOL}" "${_SP_UID}"
        fi
    else
        splog "[W] volume ${_SP_UID} (${_SP_VOL}) not found"
    fi
    if [[ ${_ret} -eq 0 ]]; then
        if [[ "${_SNAPSHOTS:0:5}" == "snaps" ]]; then
            if [[ -z "${snapshot}" ]]; then
                storpoolSnapshotsDelete "${_SP_VOL}" "snap"
            else
                splog "[-TBD-] SnapshotSnapshotsDelete?"
            fi
        fi
    else
        splog "[E] Volume snapshots not deleted due to registered error (${_ret})!"
    fi
    return "${_ret}"
}

function storpoolVolumeFreeze()
{
    local _VOL_UID="$1" _ONLY_DELETE="$2"
    local _SP_NAME="" _TMP_NAME="" _RET=1
    _SP_NAME="$(kvGet byUid "${_VOL_UID}")"
    if [[ -z "${_SP_NAME}" ]]; then
        splog "[E] Volume not found ${_VOL_UID}"
        return "${_RET}"
    fi
    _TMP_NAME="${_SP_NAME}-TEMP-$(mktemp --dry-run XXXXXXXX)"
    if storpoolVolumeInfo "${_VOL_UID}"; then
        if storpoolSnapshotCreate "${_TMP_NAME}" "${_VOL_UID}" "${V_TAG_KEYS}" "${V_TAG_VALS}"; then
            if ONLY_DELETE="${_ONLY_DELETE:+volume}" storpoolDelete "${_VOL_UID}"; then
                DO_REMOTE="" storpoolSnapshotRename "${SP_UID}" "${_TMP_NAME}" "${_SP_NAME}"
                _RET=$?
            else
                _RET=$?
                splog "[E] Can't delete ${_VOL_UID}(${_SP_NAME})"
            fi
        else
            _RET=$?
            splog "[E] Can't create snapshot '${_TMP_NAME}' for ${_VOL_UID}(${_SP_NAME}) (${_RET})"
        fi
    else
        _RET=$?
        splog "[W] Volume not found ${_VOL_UID} (${_RET})"
    fi
    return "${_RET}"
}

function storpoolSnapshotRename()
{
    local _SNAP_UID="$1" _SP_SNAP="$2" _SP_NEW="$3" _SP_TEMPLATE="$4" _SP_TAGS_JSON="$5"
    local _ret=1 _JSON=""
    if [[ -z "${_SP_NEW}" ]]; then
        splog "[E] Empty new snapshot name (args:$*)"
        return "${_ret}"
    fi
    kvDel "${_SP_SNAP}"
    kvPut "${_SP_NEW}" "${_SNAP_UID}"
    _ret=$?
    if [[ ${_ret} -eq 0 ]]; then
        _JSON+="\"tags\":{\"img\":\"${_SP_NEW}\""
        if [[ -n "${_SP_TAGS_JSON}" ]]; then
            _JSON+="${_SP_TAGS_JSON}"
        fi
        _JSON+="}"
        if [[ -n "${_SP_TEMPLATE}" ]]; then
            _JSON+="\",template\":\"${_SP_TEMPLATE}\""
        fi
        storpoolRetry SnapshotUpdate "${_SNAP_UID}" "${_JSON}"
        _ret=$?
        splog "[I] ${_SNAP_UID} renamed ${_SP_SNAP} to ${_SP_NEW} (${_ret})"
    fi
    return "${_ret}"
}

function storpoolVolumeRename()
{
    local _VOL_UID="$1" _SP_VOL="$2" _SP_NEW="$3" _SP_TEMPLATE="$4" _SP_TAGS_JSON="$5"
    local _RET=1 _JSON=""
    kvDel "${_SP_VOL}"
    kvPut "${_SP_NEW}" "${_VOL_UID}"
    _RET=$?
    if [[ ${_RET} -eq 0 ]]; then
        _JSON+="\"tags\":{\"img\":\"${_SP_NEW}\""
        if [[ -n "${_SP_TAGS_JSON}" ]]; then
            _JSON+="${_SP_TAGS_JSON}"
        fi
        _JSON+="}"
        if [[ -n "${_SP_TEMPLATE}" ]]; then
            _JSON+=",\"template\":\"${_SP_TEMPLATE}\""
        fi
        storpoolRetry VolumeUpdate "${_VOL_UID}" "${_JSON}"
        _RET=$?
        splog "[I] ${_VOL_UID} renamed ${_SP_VOL} to ${_SP_NEW} (${_RET})"
    fi
    return "${_RET}"
}

function storpoolVolumeClone()
{
    local _VOL_UID="$1" _SP_VOL="$2" _SP_TEMPLATE="$3" _TAG_KEY="$4" _TAG_VAL="$5"
    local _RET=1 _DATA="" _TAGS=""
    _TAGS="$(tagsHelper "img;${LOC_TAG};virt${_TAG_KEY:+;${_TAG_KEY}}" "${_SP_VOL};${LOC_TAG_VAL};one${_TAG_VAL:+;${_TAG_VAL}}")"
    _DATA="\"baseOn\":\"${_VOL_UID}\",\"tags\":{${_TAGS}}"
    [[ -z "${_SP_TEMPLATE}" ]] || _DATA+=",\"template\":\"${_SP_TEMPLATE}\""
    SP_UID="$(DO_MULTICLUSTER=1 storpoolRetry VolumeCreate "${_DATA}")"
    _RET=$?
    if [[ -n "${SP_UID}" ]] && [[ ${_RET} -eq 0 ]]; then
        kvPut "${_SP_VOL}" "${SP_UID}"
        _RET=$?
    fi
    return "${_RET}"
}

function storpoolVolumeResize()
{
    local _SP_UID="$1" _SP_SIZE="$2" _SP_SHRINKOK="$3"
    local _DATA="\"size\":\"${_SP_SIZE}\""
    [[ -z "${_SP_SHRINKOK}" ]] || _DATA+=",\"shrinkOk\":true"

    DO_MULTICLUSTER=1 storpoolRetry VolumeUpdate "${_SP_UID}" "${_DATA}"
}

function storpoolVolumeJsonHelper()
{
    local _UID="$1" _TYPE="$2" _SP_CLIENT="$3" _SP_MODE="${4:-rw}" _FORCE="$5" _SOFT_FAIL="$6" _DETACH_ALL="$7"
    if boolTrue "DEBUG_storpoolVolumeJsonHelper"; then
        splog "[D](${_UID},${_TYPE},${_SP_CLIENT},${_SP_MODE},${_FORCE},${_SOFT_FAIL},${_DETACH_ALL})"
    fi
    if [[ -z "${_SP_CLIENT}" ]]; then
        splog "[E] storpoolVolumeJsonHelper($*) Empty CLIENT_ID"
        exit 1
    fi
    if boolTrue "_SOFT_FAIL"; then
        _FORCE=
    fi
    echo "{\"${_TYPE}\":\"${_UID}\",\"${_SP_MODE}\":${_SP_CLIENT}${_FORCE:+,\"force\":true}${_DETACH_ALL:+,\"detach\":\"all\"}}"
}

function storpoolAttach()
{
    local _VOL_UID="$1" _SP_HOST="$2" _SP_MODE="${3:-rw}" _SP_TARGET="${4:-volume}" _DETACH_ALL="$5"
    local _SP_CLIENT="" _DATA=""
    [[ -n "${_SP_HOST}" ]] || _SP_HOST="$(hostname)"
    if boolTrue "DEBUG_storpoolAttach"; then
        splog "storpoolAttach(_VOL_UID=$1 _SP_HOST=$2 _SP_MODE=$3 _SP_TARGET=$4 _DETACH_ALL=$5)"
    fi
    _SP_CLIENT="$(storpoolClientId "${_SP_HOST}" "${COMMON_DOMAIN}")"
    if [[ -z "${_SP_CLIENT}" ]]; then
        splog "[E] Can't get remote CLIENT_ID from ${_SP_HOST}"
        exit 255
    fi
    if boolTrue "MULTICLUSTER"; then
        oneHostInfo "${_SP_HOST}"
        local DO_MULTICLUSTER=1
        local DO_REMOTE="~${HOST_SP_CLUSTER_ID:-${SP_CLUSTER_ID}}"
    fi
    _DATA="$(storpoolVolumeJsonHelper "${_VOL_UID}" "${_SP_TARGET}" "[${_SP_CLIENT}]" "${_SP_MODE}" "force" 0 "${_DETACH_ALL}")"
    storpoolRetry VolumesReassignWait "\"attachTimeout\":${ATTACH_TIMEOUT},\"reassign\":[${_DATA}]"
}

function storpoolDetach()
{
    local _VOL_UID="$1" _FORCE="$2" _SP_HOST="$3" _DETACH_ALL="$4" _SOFT_FAIL="$5" _SNAPSHOT="${6}" _VOLUMES_GROUP="$7"
    local _SP_CLIENT="" _type="" DO_REMOTE="" DO_MULTICLUSTER=1 _name=""
    if boolTrue "DEBUG_storpoolDetach"; then
        splog "[D] storpoolDetach(_VOL_UID=$1 _FORCE=$2 _SP_HOST=$3 _DETACH_ALL=$4 _SOFT_FAIL=$5 _SNAPSHOT=${6:+snapshot} _VOLUMES_GROUP='$7')"
    fi
    [[ -n "${_SNAPSHOT}" ]] && _type='snapshot' || _type='volume'
    if [[ "${_DETACH_ALL}" = "all" ]] && [[ -z "${_VOLUMES_GROUP}" ]] ; then
        _SP_CLIENT="\"all\""
    else
        if [[ -n "${_SP_HOST}" ]]; then
            _SP_CLIENT="$(storpoolClientId "${_SP_HOST}" "${COMMON_DOMAIN}")"
            if [[ -z "${_SP_CLIENT}" ]]; then
                splog "[E] Can't get SP_OURID for host ${_SP_HOST}"
                exit 255
            fi
            _SP_CLIENT="[${_SP_CLIENT}]"
            if boolTrue "MULTICLUSTER"; then
                oneHostInfo "${_SP_HOST}"
                DO_REMOTE="~${HOST_SP_CLUSTER_ID}"
            fi
        fi
    fi
    unset _DATA_A
    declare -A _DATA_A  # _DATA_A[HOST_SP_CLUSTER_ID]=DATA
    if [[ -n "${_SP_CLIENT}" ]]; then
        if [[ -n "${_VOLUMES_GROUP}" ]]; then
            for _name in ${_VOLUMES_GROUP}; do
                [[ -z "${_DATA_A["${HOST_SP_CLUSTER_ID:--}"]}" ]] || _DATA_A["${HOST_SP_CLUSTER_ID:--}"]+=","
                _DATA_A["${HOST_SP_CLUSTER_ID:--}"]+="$(storpoolVolumeJsonHelper "${_name}" "${_type}" "${_SP_CLIENT}" "detach" "force")"
            done
        else
            if boolTrue "_SOFT_FAIL"; then
                _FORCE=
            fi
            if [[ "${_DETACH_ALL}" == "all" ]]; then
                _DATA_A["${HOST_SP_CLUSTER_ID:--}"]=$(storpoolVolumeJsonHelper "${_VOL_UID}" "${_type}" "\"all\"" "detach" "${_FORCE}")
            else
                storpoolLocate "${_VOL_UID}" "Volume" 2
                if [[ -n "${X_SIZE}" ]]; then
                    if boolTrue "DEBUG_storpoolDetach"; then
                        splog "Volume ${_VOL_UID} is in cluster '${X_CLUSTER_ID}'"
                    fi
                    [[ -z "${_DATA_A["${X_CLUSTER_ID:--}"]}" ]] || _DATA_A["${X_CLUSTER_ID:--}"]+=","
                    _DATA_A["${X_CLUSTER_ID:--}"]+=$(storpoolVolumeJsonHelper "${_VOL_UID}" "${_type}" "${_SP_CLIENT}" "detach" "${_FORCE}")
                else
                    #ant: not sure is this here needed at all ... :/
                    splog "[W] Volume ${_VOL_UID} not found?! Trying MC detach anyway..."
                    _DATA_A["-"]+=$(storpoolVolumeJsonHelper "${_VOL_UID}" "${_type}" "${_SP_CLIENT}" "detach" "${_FORCE}")
                    DO_REMOTE=
                fi
            fi
        fi
        if [[ ${#_DATA_A[*]} -gt 0 ]]; then
            for _SP_CLUSTER_ID in "${!_DATA_A[@]}"; do
                X_HOST_SP_CLUSTER_ID="${HOST_SP_CLUSTER_ID}"
                [[ -z "${_SP_CLUSTER_ID#*-}" ]] || HOST_SP_CLUSTER_ID="${_SP_CLUSTER_ID}"
                storpoolRetry VolumesReassignWait "\"reassign\":[${_DATA_A[${_SP_CLUSTER_ID}]}]"
                HOST_SP_CLUSTER_ID="${X_HOST_SP_CLUSTER_ID}"
            done
        else
            splog "[I] ${_VOL_UID} not attached"
        fi
    else
        splog "[E] Can't get SP_OURID!"
    fi
}

# storpoolVolumeTemplate NAME/UID TEMPLATE_NAME
function storpoolVolumeTemplate()
{
    local _VOLUME="$1" _TEMPLATE="$2"
    DO_MULTICLUSTER=1 storpoolRetry VolumeUpdate "${_VOLUME}" "\"template\":\"${_TEMPLATE}\"" >/dev/null
}

# storpoolSnapshotInfo NAME/UID
function storpoolSnapshotInfo()
{
    local _SP_UID="$1" ret=1
    DO_MULTICLUSTER=1 DO_REMOTE="" storpoolRetry Snapshot "${_SP_UID}"
    ret=$?
    unset X_NAME X_SIZE X_GLOBALID X_TEMPLATENAME X_CLUSTERID
    if [[ ${ret} -eq 0 ]]; then
        SNAPSHOT_INFO="$(jq -r '.data[]|"\(.size|tostring);\(.globalId);\(.name);\(.templateName);\(.clusterId)"' \
                            "${TMPDIR}/Snapshot.json")"
        IFS=';' read -r X_SIZE X_GLOBALID X_NAME X_TEMPLATENAME X_CLUSTERID <<< "${SNAPSHOT_INFO}"
        export X_SIZE X_GLOBALID X_NAME X_TEMPLATENAME X_CLUSTERID
    else
        SNAPSHOT_INFO=""
    fi
    export SNAPSHOT_INFO
    if boolTrue "DEBUG_storpoolSnapshotInfo"; then
        splog "[D] (${_SP_UID}):'${SNAPSHOT_INFO}' (${ret})"
    fi
    return "${ret}"
}

# storpoolSnapshotCreate SnapshotName VolumeUID TAG_NAME;... TAG_VALUE;...
function storpoolSnapshotCreate()
{
    local _SP_SNAPSHOT="$1" _SP_UID="$2" _TAG_KEY="$3" _TAG_VAL="$4"
    local _TAGS_JSON="" _DATAJ="" _RET="1"
    _TAGS_JSON="$(tagsHelper "${_TAG_KEY}" "${_TAG_VAL}")"
    if [[ -n "${_TAGS_JSON}" ]]; then
        _DATAJ="\"tags\":{${_TAGS_JSON}}"
    fi
    SP_UID="$(DO_MULTICLUSTER=1 storpoolRetry VolumeSnapshot "${_SP_UID}" "${_DATAJ}")"
    _RET=$?
    if [[ ${_RET} -eq 0 ]]; then
        if [[ -n "${SP_UID}" ]]; then
            kvPut "${_SP_SNAPSHOT}" "${SP_UID}"
            _RET=$?
        else
            _RET=1
        fi
    fi
    export SP_UID
    return "${_RET}"
}

# storpoolSnapshotDelete SnapshotUID [OnlyDeleteUID]
function storpoolSnapshotDelete()
{
    local _SP_UID="$1" _UID_ONLY="$2"
    local _SP_SNAPSHOT_NAME="" _RET=1
    if boolTrue "DEBUG_storpoolSnapshotDelete"; then
        splog "[D](${_SP_UID}${_UID_ONLY:+, only UID})"
    fi
    DO_MULTICLUSTER=1 DO_REMOTE="" storpoolRetry SnapshotDelete "${_SP_UID}" >/dev/null
    _RET=$?
    if [[ ${_RET} -eq 0 ]] && ! boolTrue "SKIP_KV_DATA" ; then
        _SP_SNAPSHOT_NAME="$(kvGet byUid "${_SP_UID}")"
        if [[ -z "${_SP_SNAPSHOT_NAME}" ]]; then
            splog "[W] Can't get snapshot name for ${_SP_UID}"
        fi
        if [[ -n "${_UID_ONLY}" ]]; then
            _SP_SNAPSHOT_NAME=""
        fi
        kvDel "${_SP_SNAPSHOT_NAME}" "${_SP_UID}"
        _RET=$?
    fi
    return "${_RET}"
}

function storpoolSnapshotRevert()
{
    local _SNAPSHOT_UID="$1" _SP_VOL="$2" _IS_SNAPSHOT="$3" _SP_TEMPLATE="$4"
    local _VOL_UID=""
    _VOL_UID=$(kvGet byName "${_SP_VOL}")
    local ret=$?
    if storpoolVolumeFromSnapshot "${_SNAPSHOT_UID}" "${_SP_VOL}" "${_SP_TEMPLATE}"; then
        ret=$?
        if [[ -n "${_IS_SNAPSHOT}" ]]; then
            storpoolSnapshotDelete "${_VOL_UID}" "UID_only"
            storpoolVolumeTag "${SP_UID}" "${LOC_TAG};virt;img" "${LOC_TAG_VAL};one;${_SP_VOL}"
            storpoolVolumeFreeze "${SP_UID}"
        else
            storpoolDelete "${_VOL_UID}" "force" "" "${REMOTE_BACKUP_DELETE}" "\"img\":\"${_SP_VOL}\",\"reason\":\"snap_revert\"" "1"  # TBD: tags
        fi
    else
        ret=$?
        splog "[E] storpoolSnapshotRevert($*) failed! (${ret})"
    fi
    return "${ret}"
}

function storpoolSnapshotsDelete()
{
    local _NAME="$1" _SP_SNAPSHOTS_PREFIX="$2"
    local _SP_UID="" _RET=1 _name="" _spfh=""
    # Parse multiple prefixes if comma-separated
    local multi_prefix="" kv_count=0 prefixes_array=()
    local _SP_NAME_SNAPSHOTS=""
    IFS=',' read -ra prefixes_array <<< "${_SP_SNAPSHOTS_PREFIX}"
    if [[ ${#prefixes_array[@]} -gt 1 ]]; then
        multi_prefix="1"
    fi
    if boolTrue "DEBUG_storpoolSnapshotsDelete"; then
        splog "[D] storpoolSnapshotsDelete($*) DO_REMOTE=${DO_REMOTE}"
    fi
    # Process KV store for each prefix
    for prefix in "${prefixes_array[@]}"; do
        _SP_NAME_SNAPSHOTS="${_NAME}-${prefix}"
        while read -r -u "${kvfh}" _name; do
            read -r -u "${kvfh}" _SP_UID
            _name="${_name##*/}"
            ((kv_count++))
            if boolTrue "DDEBUG_storpoolSnapshotsDelete"; then
                splog "[DD] KV/LOOP _name:${_name} SP_UID:${_SP_UID}"
            fi
            if [[ ${#_name} -lt ${#_SP_NAME_SNAPSHOTS} ]]; then
                splog "[I] storpoolSnapshotsDelete ${_name}(${#_name} chars) > ${_SP_NAME_SNAPSHOTS}(${#_SP_NAME_SNAPSHOTS} chars)"
                continue
            fi
            storpoolSnapshotDelete "${_SP_UID}"
        done {kvfh}< <(kvGet "byName" "${_SP_NAME_SNAPSHOTS}" "startswith" "KeysAndVals" || true)
        exec {kvfh}<&-
    done
    # process storpool snapshots by tags too
    if DO_MULTICLUSTER=1 DO_ALLCLUSTERS=1 DO_REMOTE="" storpoolRetry SnapshotsList; then
        # Build jq filter for multiple prefixes
        local jq_filter_conditions=""
        local jq_args=""
        local prefix_count=0
        if [[ -n "${multi_prefix}" ]]; then
            # Multi-prefix mode: build OR conditions
            for prefix in "${prefixes_array[@]}"; do
                if [[ ${prefix_count} -gt 0 ]]; then
                    jq_filter_conditions+=" or "
                fi
                jq_filter_conditions+="(.tags[\$snap] | startswith(\$prefix${prefix_count}))"
                jq_args+=" --arg prefix${prefix_count} \"${prefix}\""
                ((prefix_count++))
            done
        else
            # Single prefix mode (backward compatibility)
            jq_filter_conditions="(.tags[\$snap] | startswith(\$prefix))"
            jq_args=" --arg prefix \"${_SP_SNAPSHOTS_PREFIX}\""
        fi

        local snap_count=0
        while read -r -u "${_spfh}" _SP_UID deleted snap img tags; do
            ((snap_count++))
            # jq now filters everything, so we just need to delete the snapshots
            if boolTrue "DDEBUG_storpoolSnapshotsDelete"; then
                splog "[DD] storpoolSnapshotsDelete($*) ${_SP_UID} d:${deleted} '${snap}' '${img}' ${tags}"
            fi
            storpoolSnapshotDelete "${_SP_UID}"
        done {_spfh}< <(eval "jq -r --arg snap snap --arg img img --arg target_img \"${_NAME}\" ${jq_args} \
           '.data.clusters[].response.data[]
           | select(.deleted == false and .tags.img == \$target_img and (.tags[\$snap] // null) != null and (${jq_filter_conditions}))
           | \"\(.name) \(.deleted|tostring) \(.tags[\$snap]|tostring) \(.tags[\$img]|tostring) \(.tags|tostring)\"' \
            \"${TMPDIR}/SnapshotsList.json\"" || true)
        exec {_spfh}<&-
    fi
}

function oneMvds()
{
    local _SP_VOL="$1" _SP_UID=""
    for _SP_UID in $(kvGet "byName" "${_SP_VOL}" "startswith"); do
        storpoolSnapshotTag "${_SP_UID}" \
                "diskid;${VM_TAG};img;${LOC_TAG};virt" \
                ";;${_SP_VOL};${LOC_TAG_VAL};one"
    done
}

function storpoolVolumeRevert()
{
    local _SP_UID="$1" _SP_VOL="$2" _SNAP_UID="$3" _REMOTE="$4" _REVERT_SIZE="${5:-0}"
    local _RET=1 DO_REMOTE=""
    local _JSON_DATA="\"toSnapshot\":\"${_SNAP_UID}\""
    if boolTrue "_REVERT_SIZE"; then
        _JSON_DATA+=",\"revertSize\":true"
    else
        _JSON_DATA+=",\"revertSize\":false"
    fi
    if [[ -n "${_REMOTE}" ]]; then
        storpoolVolumeBackup "${_SP_UID}" "${_SP_VOL}" "${_REMOTE}"
        _RET=$?
        if [[ ${_RET} -ne 0 ]]; then
            splog "[E] Failed to create a (remote) backup. (${_RET})"
            return "${_RET}"
        fi
    fi
    if [[ -n "${DELAY_DELETE}" ]] && [[ -z "${_snapshot}" ]]; then
        local DELAY_DELETE_tmp="${DELAY_DELETE//[[:digit:]]/}"
        if [[ -n "${DELAY_DELETE_tmp}" ]] && [[ -z "${DELAY_DELETE_tmp/[smhd]/}" ]]; then
            json="\"deleteAfter\":$(delayDeleteSeconds "${DELAY_DELETE}")"
            json+=",\"tags\":{\"reason\":\"revert\"${_DD_TAGS:+,${_DD_TAGS}}}"
            DO_REMOTE="" storpoolRetry VolumeSnapshot "${_SP_UID}" "${json}" >/dev/null
            _ret=$?
        fi
    fi
    SP_GLOBALID=$(DO_MULTICLUSTER=1 storpoolRetry VolumeRevert "${_SP_UID}" "${_JSON_DATA}")
    _RET=$?
    export SP_GLOBALID
    splog "[I] revert ${_SP_UID} (${_SP_VOL}) to snapshot:${_SNAP_UID} -> ${SP_GLOBALID} (${_RET})"
    return "${_RET}"
}

function storpoolVolumeFromSnapshot()
{
    local _SNAPSHOT_UID="$1" _SP_VOL="$2" _SP_TEMPLATE="$3"
    local _TAG_KEY="${4:-img;${LOC_TAG};virt}" _TAG_VAL="${5:-${_SP_VOL};${LOC_TAG_VAL};one}"
    local _RET=1 _TAGS=""
    _TAGS="$(tagsHelper "${_TAG_KEY}" "${_TAG_VAL}")"
    local _CMD="\"parent\":\"${_SNAPSHOT_UID}\",\"tags\":{${_TAGS}}"
    [[ -z "${_SP_TEMPLATE}" ]] || _CMD+=",\"template\":\"${_SP_TEMPLATE}\"}"
    SP_UID=$(DO_MULTICLUSTER=1 storpoolRetry VolumeCreate "${_CMD}" 2>/dev/null)
    _RET=$?
    export SP_UID
    splog "[I] parent snapshot ${_SNAPSHOT_UID} -> created volume ${SP_UID} ${_SP_VOL} (${_RET})"
    if [[ -n "${SP_UID}" ]] && [[ ${_RET} -eq 0 ]]; then
        kvPut "${_SP_VOL}" "${SP_UID}" || _RET=$?
    fi
    return "${_RET}"
}

function storpoolVolumeTag()
{
    local _SP_UID="$1" _TAG_KEY="${2:-${VM_TAG}}" _TAG_VAL="$3"
    local _DATAJSON=""
    _DATAJSON="$(tagsHelper "${_TAG_KEY}" "${_TAG_VAL}")"
    if [[ -n "${_DATAJSON}" ]]; then
        DO_MULTICLUSTER=1 DO_REMOTE="" storpoolRetry VolumeUpdate \
                                        "${_SP_UID}" "\"tags\":{${_DATAJSON}}"
    else
        return 0 # no tags to set
    fi
}

function storpoolSnapshotTag()
{
    local _SP_UID="$1" _TAG_KEY="${2:-${VM_TAG}}" _TAG_VAL="$3"
    local _DATAJSON=""
    _DATAJSON="$(tagsHelper "${_TAG_KEY}" "${_TAG_VAL}")"
    if [[ -n "${_DATAJSON}" ]]; then
        DO_MULTICLUSTER=1 DO_REMOTE="" storpoolRetry SnapshotUpdate \
                                        "${_SP_UID}" "\"tags\":{${_DATAJSON}}" >/dev/null
    else
        return 0 # no tags to set
    fi
}

function oneSymlink()
{
    local _host="$1" _SP_UID="$2"
    shift 2
    local _dst="$*" _src="" _remote_cmd=""
    _src="/dev/storpool-byid/${_SP_UID#*~}"
    splog "[I] ${VM_ID:+VM ${VM_ID} }symlink ${_src} -> ${_host}:{${_dst//[[:space:]]/,}}${MONITOR_TM_MAD:+ (.monitor=${MONITOR_TM_MAD})}"
    _remote_cmd=$(cat <<EOF
    #_SYMLINK
    for dst in ${_dst}; do
        dst_dir="\$(dirname "\${dst}")"
        if [[ -d "\${dst_dir}" ]]; then
            true
        else
            splog "mkdir -p \${dst_dir} (for:\$(basename "\${dst}"))"
            trap "splog \"Can't create destination dir \${dst_dir} (\$?)\"" TERM INT QUIT HUP EXIT
            splog "mkdir -p \${dst_dir}"
            mkdir -p "\${dst_dir}"
            trap - TERM INT QUIT HUP EXIT
        fi
        if [[ -n "${MONITOR_TM_MAD}" ]]; then
            monitor_mad=
            if [[ -f "\${dst_dir}/../.monitor" ]]; then
                monitor_mad=\$(<"\${dst_dir}/../.monitor")
            fi
            if [[ "\${monitor_mad}" != "${MONITOR_TM_MAD}" ]]; then
                echo "${MONITOR_TM_MAD}" >"\${dst_dir}/../.monitor"
                splog "Wrote '${MONITOR_TM_MAD}' to \${dst_dir}/../.monitor (\$?)\${monitor_mad:+ was \${monitor_mad}}"
            fi
        fi
        ln -sf "${_src}" "\${dst}"
        splog "ln -sf ${_src} \${dst} (\$?)"
        echo "storpool" >"\${dst}".monitor
    done
EOF
)
    ssh_exec_and_log "${_host}" "${REMOTE_HDR}${_remote_cmd}${REMOTE_FTR}" \
                 "Error creating symlink from ${_src} to ${_dst//[[:space:]]/,} on host ${_host}"
}

function oneFsfreeze()
{
    local _host="$1" _domain="$2"
    local _SCRIPTS_REMOTE_DIR="" _remote_cmd=""
    _SCRIPTS_REMOTE_DIR="${SCRIPTS_REMOTE_DIR:-$(getFromConf "/etc/one/oned.conf" "SCRIPTS_REMOTE_DIR")}"

    _remote_cmd=$(cat <<EOF
    #_FSFREEZE
    if [[ -n "${_domain}" ]]; then
        [[ -f "${_SCRIPTS_REMOTE_DIR}/etc/vmm/kvm/kvmrc" ]] && source "${_SCRIPTS_REMOTE_DIR}/etc/vmm/kvm/kvmrc" || source "${_SCRIPTS_REMOTE_DIR}/vmm/kvm/kvmrc"
        tmplog="\$(mktemp --tmpdir oneFsfreeze-XXXXXXXX)"
        if virsh --connect \${LIBVIRT_URI:-qemu:///system} domfsfreeze "${_domain}" 2>&1 >"\${tmplog}"; then
            splog "domfsfreeze ${_domain} \${tmplog}:\$(tr '\\n' ' ' < "\${tmplog}")"
        else
            splog "($?) ${_domain} domfsfreeze failed! snapshot not consistent! \${tmplog}:\$(tr '\\n' ' ' < "\${tmplog}")"
        fi
        rm -rf "\${tmplog}"
    fi

EOF
)
    ssh_exec_and_log "${_host}" "${REMOTE_HDR}${_remote_cmd}${REMOTE_FTR}" \
                 "Error in fsfreeze of domain ${_domain} on host ${_host}"
    splog "fsfreeze ${_domain} on ${_host} ($?)"
}

function oneFsthaw()
{
    local _host="$1" _domain="$2"
    local _SCRIPTS_REMOTE_DIR="" _remote_cmd=""
    _SCRIPTS_REMOTE_DIR="${SCRIPTS_REMOTE_DIR:-$(getFromConf "/etc/one/oned.conf" "SCRIPTS_REMOTE_DIR")}"

    _remote_cmd=$(cat <<EOF
    #_FSTHAW
    if [[ -n "${_domain}" ]]; then
        [[ -f "${_SCRIPTS_REMOTE_DIR}/etc/vmm/kvm/kvmrc" ]] && source "${_SCRIPTS_REMOTE_DIR}/etc/vmm/kvm/kvmrc" || source "${_SCRIPTS_REMOTE_DIR}/vmm/kvm/kvmrc"
        tmplog="\$(mktemp --tmpdir oneFsthaw-XXXXXXXX)"
        if virsh --connect \${LIBVIRT_URI:-qemu:///system} domfsthaw "${_domain}" 2>&1 >"\${tmplog}"; then
            splog "domfsthaw ${_domain} \${tmplog}:\$(tr '\\n' ' ' < "\${tmplog}")"
        else
            splog "(\$?) ${_domain} domfsthaw failed! VM fs freezed? (retry in 200 ms) \${tmplog}:\$(tr '\\n' ' ' < "\${tmplog}")"
            sleep .2
            if virsh --connect \${LIBVIRT_URI:-qemu:///system} domfsthaw "${_domain}" 2>&1 >"\${tmplog}"; then
                splog "domfsthaw ${_domain} \${tmplog}:\$(tr '\\n' ' ' < "\${tmplog}")"
            else
                splog "(\$?) ${_domain} domfsthaw failed! VM fs freezed? \${tmplog}:\$(tr '\\n' ' ' < "\${tmplog}")"
            fi
        fi
        rm -rf "\${tmplog}"
    fi

EOF
)
    ssh_exec_and_log "${_host}" "${REMOTE_HDR}${_remote_cmd}${REMOTE_FTR}" \
                 "Error in fsthaw of domain ${_domain} on host ${_host}"
    splog "fsthaw ${_domain} on ${_host} ($?)"
}

function oneCheckpointSave()
{
    local _host="${1%%:*}" _path="${1#*:}"
    local _vmid="" _dsid="" _checkpoint="" _template="" _volume="" _sp_link=""
    local _DELAY_DELETE="${DELAY_DELETE}" _SP_COMPRESSION="${SP_COMPRESSION:-lz4}"
    local _remote_cmd="" _file_size=0 _volume_size=0
    local _SP_UID=""
    _vmid="$(basename "${_path}")"
    _dsid="$(basename "$(dirname "${_path}")")"
    _checkpoint="${_path}/checkpoint"
    _template="${ONE_PX:-one}-ds-${_dsid}"
    _volume="${ONE_PX:-one}-sys-${_vmid}-checkpoint"
    _sp_link="/dev/storpool-byid/${_SP_UID#*~}"
    _file_size=$(${SSH:-ssh} "${_host}" "du -b \"${_checkpoint}\" | cut -f 1" || true)
    if [[ -n "${_file_size}" ]]; then
        _volume_size=$(( ((_file_size *2 +511) /512) *512 ))
        _volume_size=$(( _volume_size/1024/1024 ))
    else
        splog "Checkpoint file not found! ${_checkpoint}"
        return 0
    fi
    splog "checkpoint_size=${_file_size} volume_size=${_volume_size}M"

    _SP_UID="$(kvGet byName "${_volume}")"
    if [[ -n "${_SP_UID}" ]]; then
        DELAY_DELETE=""
        storpoolDelete "${_SP_UID}" "force"
    fi
    storpoolVolumeCreate "${_volume}" "${_volume_size}" "${_template}"
    _SP_UID="${SP_UID}"
    if [[ -z "${_SP_UID}" ]]; then
        DELAY_DELETE="${_DELAY_DELETE}"
        splog "Can't get StorPool name for ${_volume}"
        return 1
    fi
    _sp_link="/dev/storpool-byid/${_SP_UID#*~}"

    trapAdd "storpoolDelete \"${_SP_UID}\" \"force\""

    storpoolAttach "${_SP_UID}" "${_host}"

    _remote_cmd=$(cat <<EOF
    # checkpoint Save
    if [[ -f "${_checkpoint}" ]]; then
        if tar --no-seek --use-compress-program="${SP_COMPRESSION}" \
               --create --file="${_sp_link}" "${_checkpoint}"; then
            splog "rm -f ${_checkpoint}"
            rm -f "${_checkpoint}"
        else
            splog "Checkpoint import failed! ${_checkpoint} (\$?)"
            exit 1
        fi
    else
        splog "Checkpoint file not found! ${_checkpoint}"
    fi

EOF
)
    splog "Saving ${_checkpoint} to ${_SP_UID} (${_volume})"
    ssh_exec_and_log "${_host}" "${REMOTE_HDR}${_remote_cmd}${REMOTE_FTR}" \
                 "Error in checkpoint save of VM ${_vmid} on host ${_host}"

    trapReset
    DELAY_DELETE="${_DELAY_DELETE}"

    storpoolDetach "${_SP_UID}" "" "${_host}" "all"
}

function oneCheckpointRestore()
{
    local _host="${1%%:*}" _path="${1#*:}" _monitor="${2}"
    local _SP_UID=""
    local _vmid="" _checkpoint="" _volume="" _sp_link=""
    local _remote_cmd="" _SP_COMPRESSION="${SP_COMPRESSION:-lz4}"
    _vmid="$(basename "${_path}")"
    _checkpoint="${_path}/checkpoint"
    _volume="${ONE_PX:-one}-sys-${_vmid}-checkpoint"
    _SP_UID=$(kvGet byName "${_volume}")
    _sp_link="/dev/storpool-byid/${_SP_UID#*~}"
    if [[ -z "${_SP_UID}" ]]; then
        splog "Can't get StorPool name for ${_volume}"
        return 1
    fi

    _remote_cmd=$(cat <<EOF
    # checkpoint Restore
    if [[ -f "${_checkpoint}" ]]; then
        splog "file exists ${_checkpoint}"
    else
        mkdir -p "${_path}"

        if [[ -n "${_monitor}" ]]; then
            [[ -f "${_path}/.monitor" ]] || echo "storpool" >"${_path}/.monitor"
        fi

        if tar --no-seek --use-compress-program="${_SP_COMPRESSION}" --to-stdout --extract --file="${_sp_link}" >"${_checkpoint}"; then
            splog "RESTORED ${_volume} ${_checkpoint}"
        else
            splog "Error: Failed to export ${_checkpoint}"
            exit 1
        fi
    fi
EOF
)
    if storpoolVolumeExists "${_SP_UID}"; then
        storpoolAttach "${_SP_UID}" "${_host}"

        trapAdd "storpoolDetach \"${_SP_UID}\" \"force\" \"${_host}\" \"all\""

        splog "Restoring ${_checkpoint} from ${_SP_UID} (${_volume})"
        ssh_exec_and_log "${_host}" "${REMOTE_HDR}${_remote_cmd}${REMOTE_FTR}" \
                 "Error in checkpoint restore of VM ${_vmid} on host ${_host}"

        trapReset

        storpoolDelete "${_SP_UID}" "force"
    else
        splog "Checkpoint volume ${_SP_UID} (${_volume}) not found"
    fi
}

function oneBackupImageInfo()
{
    local _IMAGE_ID="$1"
    local _tmpXML="${TMPDIR:-/tmp}/oneimage-${_IMAGE_ID}.XML"
    local _XPATH="" _element=""

    oneCallXml oneimage show "${_IMAGE_ID}" "${_tmpXML}"

    _XPATH="$(lookup_file "datastore/xpath.rb" || true)"
    declare -a _XPATH_A _XPATH_QUERY
    _XPATH_A=(
        "${_XPATH}"
        "--stdin"
    )
    _XPATH_QUERY=(
        "/IMAGE/NAME"
        "/IMAGE/TYPE"
        "/IMAGE/SOURCE"
        "/IMAGE/DATASTORE_ID"
        "%m%/IMAGE/BACKUP_DISK_IDS/ID"
    )
    unset i XPATH_ELEMENTS
    while IFS='' read -r -u "${xfh}" -d '' _element; do
        XPATH_ELEMENTS[i++]="${_element}"
    done {xfh}< <("${_XPATH_A[@]}" < "${_tmpXML}" "${_XPATH_QUERY[@]}" || true)
    exec {xfh}<&-
    rm -f "${_tmpXML}"
    unset i
    B_IMAGE_NAME="${XPATH_ELEMENTS[i++]}"
    B_IMAGE_TYPE="${XPATH_ELEMENTS[i++]}"
    B_IMAGE_SOURCE="${XPATH_ELEMENTS[i++]}"
    B_DATASTORE_ID="${XPATH_ELEMENTS[i++]}"
    _BACKUP_DISK_IDS="${XPATH_ELEMENTS[i++]}"
    read -r -a BACKUP_DISK_IDS <<< "${_BACKUP_DISK_IDS}"

    boolTrue "DEBUG_oneBackupImageInfo" || return 0
    local _DBGMSG="[D] oneBackupImageInfo"
    _DBGMSG+=" B_IMAGE_NAME:'${B_IMAGE_NAME}'"
    _DBGMSG+=" B_IMAGE_TYPE:${B_IMAGE_TYPE}"
    _DBGMSG+=" B_IMAGE_SOURCE:${B_IMAGE_SOURCE}"
    _DBGMSG+=" B_DATASTORE_ID:${B_DATASTORE_ID}"
    _DBGMSG+=" BACKUP_DISK_IDS:${BACKUP_DISK_IDS[*]}"
    splog "${_DBGMSG}"
}

function oneImageInfo()
{
    local _IMAGE_ID="$1" _IMAGE_POOL_FILE="$2"
    local _XPATH="" _ret=0 _errmsg="" _tmpXML="" xfh=""

    _tmpXML="${TMPDIR:-/tmp}/oneImageInfo-${_IMAGE_ID}.XML"

    if [[ -n "${_IMAGE_POOL_FILE}" ]]; then
        if [[ ! -f "${_IMAGE_POOL_FILE}" ]]; then
            oneCallXml oneimage list "" "${_IMAGE_POOL_FILE}"
            _ret=$?
            if boolTrue "DEBUG_oneImageInfo"; then
                splog "[D] oneimage list -x >${_IMAGE_POOL_FILE} (${_ret})"
            fi
            if [[ ${_ret} -ne 0 ]]; then
                _errmsg="(oneImageInfo) Error: Can't get info IMAGE=${_IMAGE_ID}! $(head -n 1 "${_tmpXML}") (ret:${_ret})"
                log_error "${_errmsg}"
                splog "${_errmsg}"
                exit "${_ret}"
            fi
        fi
        xmllint -xpath "/IMAGE_POOL/IMAGE[ID=${_IMAGE_ID}]" "${_IMAGE_POOL_FILE}" >"${_tmpXML}"
        _ret=$?
    else
        oneCallXml oneimage show "${_IMAGE_ID}" "${_tmpXML}"
        _ret=$?
    fi

    if [[ ${_ret} -ne 0 ]]; then
        _errmsg="(oneImageInfo) Error: Can't get info IMAGE=${_IMAGE_ID}! $(head -n 1 "${_tmpXML}") (ret:${_ret})"
        log_error "${_errmsg}"
        splog "${_errmsg}"
        exit "${_ret}"
    fi

    sed -i '/\/>$/d' "${_tmpXML}"
    _XPATH="$(lookup_file "datastore/xpath.rb")"
    declare -a _XPATH_A _XPATH_QUERY
    _XPATH_A=(
        "${_XPATH}"
        "--stdin"
    )
    _XPATH_QUERY=(
        "/IMAGE/NAME"
        "/IMAGE/TYPE"
        "/IMAGE/DISK_TYPE"
        "/IMAGE/PERSISTENT"
        "/IMAGE/TM_MAD"
        "/IMAGE/SOURCE"
        "/IMAGE/DATASTORE_ID"
        "%m%/IMAGE/VMS/ID"
        "/IMAGE/TEMPLATE/SP_QOSCLASS"
        "/IMAGE/TEMPLATE/VC_POLICY"
        "/IMAGE/TEMPLATE/SHAREABLE"
        "/IMAGE/TEMPLATE/PERSISTENT_TYPE"
    )

    unset i XPATH_ELEMENTS
    while IFS='' read -r -u "${xfh}" -d '' _element; do
        XPATH_ELEMENTS[i++]="${_element}"
    done {xfh}< <("${_XPATH_A[@]}" < "${_tmpXML}" "${_XPATH_QUERY[@]}" || true)
    exec {xfh}<&-
    rm -f "${_tmpXML}"

    unset i
    IMAGE_NAME="${XPATH_ELEMENTS[i++]}"
    IMAGE_TYPE="${XPATH_ELEMENTS[i++]}"
    IMAGE_DISK_TYPE="${XPATH_ELEMENTS[i++]}"
    IMAGE_PERSISTENT="${XPATH_ELEMENTS[i++]}"
    IMAGE_TM_MAD="${XPATH_ELEMENTS[i++]}"
    IMAGE_SOURCE="${XPATH_ELEMENTS[i++]}"
    IMAGE_DATASTORE_ID="${XPATH_ELEMENTS[i++]}"
    _IMAGE_VMS="${XPATH_ELEMENTS[i++]}"
    read -r -a IMAGE_VMS_A <<< "${_IMAGE_VMS}"
    IMAGE_SP_QOSCLASS="${XPATH_ELEMENTS[i++]}"
    IMAGE_VC_POLICY="${XPATH_ELEMENTS[i++]}"
    SHAREABLE="${XPATH_ELEMENTS[i++]}"
    PERSISTENT_TYPE="${XPATH_ELEMENTS[i++]}"

    boolTrue "DEBUG_oneImageInfo" || return 0

    _MSG="[oneImageInfo]${IMAGE_NAME:+IMAGE_NAME=${IMAGE_NAME} }${IMAGE_TYPE:+IMAGE_TYPE=${IMAGE_TYPE} }${IMAGE_DISK_TYPE:+DISK_TYPE=${IMAGE_DISK_TYPE} }${IMAGE_PERSISTENT:+PERSISTENT=${IMAGE_PERSISTENT} }"
    _MSG+="${IMAGE_TM_MAD:+TM_MAD=${IMAGE_TM_MAD} }${IMAGE_SOURCE:+SOURCE=${IMAGE_SOURCE} }${IMAGE_DATASTORE_ID:+DATASTORE_ID=${IMAGE_DATASTORE_ID} }"
    _MSG+="${IMAGE_VMS:+VMS=[${IMAGE_VMS_A[*]}] }${IMAGE_SP_QOSCLASS:+SP_QOSCLASS=${IMAGE_SP_QOSCLASS} }${IMAGE_VC_POLICY:+VC_POLICY=${IMAGE_VC_POLICY} }"
    _MSG+="${SHAREABLE:+SHAREABLE=${SHAREABLE} }${PERSISTENT_TYPE:+PERSISTENT_TYPE=${PERSISTENT_TYPE} }"
    splog "[D]${_MSG}"
}

function oneVmInfo()
{
    local _VM_ID="$1" _DISK_ID="$2"
    local _XPATH="" _tmpXML="" _ret=1 _errmsg="" _element="" xfh=""

    _tmpXML="${TMPDIR:-/tmp}/oneVmInfo-${_VM_ID}.XML"
    oneCallXml onevm show "${_VM_ID}" "${_tmpXML}"
    _ret=$?
    if [[ ${_ret} -ne 0 ]]; then
        _errmsg="(oneVmInfo) Error: Can't get info! '$(head -n 1 "${_tmpXML}")' (ret:${_ret})"
        log_error "${_errmsg}"
        splog "${_errmsg}"
        exit "${_ret}"
    fi
    sed -i '/\/>$/d' "${_tmpXML}"
    _XPATH="$(lookup_file "datastore/xpath.rb" || true)"
    declare -a _XPATH_A _XPATH_QUERY
    _XPATH_A=(
        "${_XPATH}"
        "--stdin"
    )
    _XPATH_QUERY=(
        "/VM/DEPLOY_ID"
        "/VM/STATE"
        "/VM/PREV_STATE"
        "/VM/LCM_STATE"
        "/VM/CONTEXT/DISK_ID"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/SOURCE"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/IMAGE_ID"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/IMAGE"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/CLONE"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/SAVE"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/TYPE"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/DRIVER"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/FORMAT"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/READONLY"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/PERSISTENT"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/SHAREABLE"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/FS"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/HOTPLUG_SAVE_AS"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/HOTPLUG_SAVE_AS_ACTIVE"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/HOTPLUG_SAVE_AS_SOURCE"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/SIZE"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/ORIGINAL_SIZE"
        "/VM/TEMPLATE/DISK[DISK_ID=${_DISK_ID}]/DATASTORE_ID"
        "/VM/BACKUPS/BACKUP_CONFIG/KEEP_LAST"
        "/VM/BACKUPS/BACKUP_CONFIG/BACKUP_VOLATILE"
        "/VM/BACKUPS/BACKUP_CONFIG/FS_FREEZE"
        "/VM/BACKUPS/BACKUP_CONFIG/MODE"
        "/VM/BACKUPS/BACKUP_CONFIG/LAST_DATASTORE_ID"
        "/VM/BACKUPS/BACKUP_CONFIG/LAST_BACKUP_ID"
        "/VM/BACKUPS/BACKUP_CONFIG/LAST_BACKUP_SIZE"
        "/VM/BACKUPS/BACKUP_CONFIG/ACTIVE_FLATTEN"
        "/VM/HISTORY_RECORDS/HISTORY[last()]/TM_MAD"
        "/VM/HISTORY_RECORDS/HISTORY[last()]/DS_ID"
        "/VM/USER_TEMPLATE/VMSNAPSHOT_LIMIT"
        "/VM/USER_TEMPLATE/DISKSNAPSHOT_LIMIT"
        "/VM/USER_TEMPLATE/INCLUDE_CONTEXT_PACKAGES"
        "/VM/USER_TEMPLATE/T_OS_NVRAM"
        "/VM/USER_TEMPLATE/SP_QOSCLASS"
        "/VM/USER_TEMPLATE/VC_POLICY"
        "/VM/TEMPLATE/TPM/MODEL"
    )
    unset i XPATH_ELEMENTS
    while IFS='' read -r -u "${xfh}" -d '' _element; do
        XPATH_ELEMENTS[i++]="${_element}"
    done {xfh}< <("${_XPATH_A[@]}" < "${_tmpXML}" "${_XPATH_QUERY[@]}" || true)
    exec {xfh}<&-
    rm -f "${_tmpXML}"
    unset i
    DEPLOY_ID="${XPATH_ELEMENTS[i++]}"
    VMSTATE="${XPATH_ELEMENTS[i++]}"
    VMPREVSTATE="${XPATH_ELEMENTS[i++]}"
    LCM_STATE="${XPATH_ELEMENTS[i++]}"
    CONTEXT_DISK_ID="${XPATH_ELEMENTS[i++]}"
    SOURCE="${XPATH_ELEMENTS[i++]}"
    IMAGE_ID="${XPATH_ELEMENTS[i++]}"
    IMAGE="${XPATH_ELEMENTS[i++]}"
    CLONE="${XPATH_ELEMENTS[i++]}"
    SAVE="${XPATH_ELEMENTS[i++]}"
    TYPE="${XPATH_ELEMENTS[i++]}"
    DRIVER="${XPATH_ELEMENTS[i++]}"
    FORMAT="${XPATH_ELEMENTS[i++]}"
    READONLY="${XPATH_ELEMENTS[i++]}"
    PERSISTENT="${XPATH_ELEMENTS[i++]}"
    SHAREABLE="${XPATH_ELEMENTS[i++]}"
    FS="${XPATH_ELEMENTS[i++]}"
    HOTPLUG_SAVE_AS="${XPATH_ELEMENTS[i++]}"
    HOTPLUG_SAVE_AS_ACTIVE="${XPATH_ELEMENTS[i++]}"
    HOTPLUG_SAVE_AS_SOURCE="${XPATH_ELEMENTS[i++]}"
    SIZE="${XPATH_ELEMENTS[i++]}"
    ORIGINAL_SIZE="${XPATH_ELEMENTS[i++]}"
    IMAGE_DS_ID="${XPATH_ELEMENTS[i++]}"
    export B_KEEP_LAST="${XPATH_ELEMENTS[i++]}"
    export B_BACKUP_VOLATILE="${XPATH_ELEMENTS[i++]}"
    export B_FS_FREEZE="${XPATH_ELEMENTS[i++]}"
    export B_MODE="${XPATH_ELEMENTS[i++]}"
    export B_LAST_DATASTORE_ID="${XPATH_ELEMENTS[i++]}"
    export B_LAST_BACKUP_ID="${XPATH_ELEMENTS[i++]}"
    export B_LAST_BACKUP_SIZE="${XPATH_ELEMENTS[i++]}"
    export B_ACTIVE_FLATTEN="${XPATH_ELEMENTS[i++]}"
    VM_TM_MAD="${XPATH_ELEMENTS[i++]}"
    VM_DS_ID="${XPATH_ELEMENTS[i++]}"
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [[ -n "${_TMP}" ]] && [[ -z "${_TMP//[[:digit:]]/}" ]]; then
        VMSNAPSHOT_LIMIT="${_TMP}"
    fi
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [[ -n "${_TMP}" ]] && [[ -z "${_TMP//[[:digit:]]/}" ]]; then
        DISKSNAPSHOT_LIMIT="${_TMP}"
    fi
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [[ -n "${_TMP}" ]] && [[ -z "${_TMP//[[:digit:]]/}" ]]; then
        INCLUDE_CONTEXT_PACKAGES="${_TMP}"
    fi
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [[ -n "${_TMP}" ]]; then
        T_OS_NVRAM="${_TMP}"
    fi
    SP_QOSCLASS_LINE="${XPATH_ELEMENTS[i++]}"
    VC_POLICY="${XPATH_ELEMENTS[i++]}"
    TPM_MODEL="${XPATH_ELEMENTS[i++]}"
    IFS=';' read -r -a SP_QOSCLASS_A <<< "${SP_QOSCLASS_LINE}"
    unset DISKS_QC_A VM_DISK_SP_QOSCLASS VM_SP_QOSCLASS IMAGE_SP_QOSCLASS
    if [[ "${CLONE^^}" == "NO" ]]; then
        oneImageQc "${IMAGE_ID}"
    fi
    declare -gA DISKS_QC_A  # DISKS_QC_A[DISK_ID]=QOSCLASS
    local _qosclass="" _did=""
    for _qosclass in "${SP_QOSCLASS_A[@]}"; do
        IFS=':' read -r -a _tmparr <<< "${_qosclass}"
        if [[ ${#_tmparr[*]} -eq 1 ]]; then
            VM_SP_QOSCLASS="${_qosclass}"
        elif [[ ${#_tmparr[*]} -eq 2 ]]; then
            _did="${_tmparr[0]//[^[:digit:]]/}"
            if [[ -n "${_did}" ]]; then
                DISKS_QC_A[${_did}]="${_tmparr[1]}"
            fi
        fi
    done
    if [[ -n "${DISKS_QC_A[${_DISK_ID}]+found}" ]]; then
        VM_DISK_SP_QOSCLASS="${DISKS_QC_A[${_DISK_ID}]}"
    fi

    boolTrue "DEBUG_oneVmInfo" || return 0

    splog "[D] oneVmInfo \
VM ${_VM_ID} \
${_DISK_ID:+DISK_ID=${_DISK_ID} }\
${DEPLOY_ID:+DEPLOY_ID=${DEPLOY_ID} }\
${VMSTATE:+VMSTATE=${VM_STATE}(${VmState[${VMSTATE}]}) }\
${LCM_STATE:+LCM_STATE=${LCM_STATE}(${LcmState[${LCM_STATE}]}) }\
${VMPREVSTATE:+VMPREVSTATE=${VMPREVSTATE}(${VmState[${VMPREVSTATE}]}) }\
${CONTEXT_DISK_ID:+CONTEXT_DISK_ID=${CONTEXT_DISK_ID} }\
${SOURCE:+SOURCE=${SOURCE} }\
${IMAGE_ID:+IMAGE_ID=${IMAGE_ID} }\
${IMAGE_DS_ID:+IMAGE_DS_ID=${IMAGE_DS_ID} }\
${CLONE:+CLONE=${CLONE} }\
${SAVE:+SAVE=${SAVE} }\
${TYPE:+TYPE=${TYPE} }\
${DRIVER:+DRIVER=${DRIVER} }\
${FORMAT:+FORMAT=${FORMAT} }\
${READONLY:+READONLY=${READONLY} }\
${PERSISTENT:+PERSISTENT=${PERSISTENT} }\
${SHAREABLE:+SHAREABLE=${SHAREABLE} }\
${FS:+FS=${FS} }\
${IMAGE:+IMAGE=${IMAGE} }\
${SIZE:+SIZE=${SIZE} }\
${ORIGINAL_SIZE:+ORIGINAL_SIZE=${ORIGINAL_SIZE} }\
${VM_TM_MAD:+VM_TM_MAD=${VM_TM_MAD} }\
${VM_DS_ID:+VM_DS_ID=${VM_DS_ID} }\
${VMSNAPSHOT_LIMIT:+VMSNAPSHOT_LIMIT=${VMSNAPSHOT_LIMIT} }\
${DISKSNAPSHOT_LIMIT:+DISKSNAPSHOT_LIMIT=${DISKSNAPSHOT_LIMIT} }\
${VM_SP_QOSCLASS:+VM_SP_QOSCLASS=${VM_SP_QOSCLASS} }\
${VM_DISK_SP_QOSCLASS:+VM_DISK_SP_QOSCLASS=${VM_DISK_SP_QOSCLASS} }\
${VC_POLICY:+VC_POLICY=${VC_POLICY} }\
${T_OS_NVRAM:+T_OS_NVRAM=${T_OS_NVRAM} }\
${INCLUDE_CONTEXT_PACKAGES:+INCLUDE_CONTEXT_PACKAGES=${INCLUDE_CONTEXT_PACKAGES} }\
${B_KEEP_LAST:+B_KEEP_LAST=${B_KEEP_LAST} }\
${B_BACKUP_VOLATILE:+B_BACKUP_VOLATILE=${B_BACKUP_VOLATILE} }\
${B_FS_FREEZE:+B_FS_FREEZE=${B_FS_FREEZE} }\
${B_KEEP_LAST:+B_KEEP_LAST=${B_KEEP_LAST} }\
${B_MODE:+B_MODE=${B_MODE} }\
${B_LAST_DATASTORE_ID:+B_LAST_DATASTORE_ID=${B_LAST_DATASTORE_ID} }\
${B_LAST_BACKUP_ID:+B_LAST_BACKUP_ID=${B_LAST_BACKUP_ID} }\
${B_LAST_BACKUP_SIZE:+B_LAST_BACKUP_SIZE=${B_LAST_BACKUP_SIZE} }\
${B_ACTIVE_FLATTEN:+B_ACTIVE_FLATTEN=${B_ACTIVE_FLATTEN} }\
${TPM_MODEL:+TPM_MODEL=${TPM_MODEL} }\
"
    local _DBGMSG="${HOTPLUG_SAVE_AS:+HOTPLUG_SAVE_AS=${HOTPLUG_SAVE_AS} }${HOTPLUG_SAVE_AS_ACTIVE:+HOTPLUG_SAVE_AS_ACTIVE=${HOTPLUG_SAVE_AS_ACTIVE} }${HOTPLUG_SAVE_AS_SOURCE:+HOTPLUG_SAVE_AS_SOURCE=${HOTPLUG_SAVE_AS_SOURCE} }"
    [[ -z "${_DBGMSG}" ]] || splog "${_DBGMSG}"
}

function oneDatastoreInfo()
{
    local _DS_ID="$1" _DS_POOL_FILE="$2"
    local _XPATH="" _tmpXML="" _errmsg="" _ret=1 _element="" xfh=""

    _tmpXML="${TMPDIR:-/tmp}/oneDatastoreInfo-${_DS_ID}.XML"

    if [[ -n "${_DS_POOL_FILE}" ]]; then
        if [[ ! -f "${_DS_POOL_FILE}" ]]; then
            oneCallXml onedatastore list "" "${_DS_POOL_FILE}"
            _ret=$?
            if boolTrue "DEBUG_oneDatastoreInfo"; then
                splog "[D] oneCallXml onedatastore list '' ${_DS_POOL_FILE} (${_ret})"
            fi
            if [[ ${_ret} -ne 0 ]]; then
                _errmsg="(oneDatastoreInfo) Error: Can't get info DS=${_DS_ID}! $(head -n 1 "${_tmpXML}") (ret:${_ret})"
                log_error "${_errmsg}"
                splog "${_errmsg}"
                exit "${_ret}"
            fi
        fi
        xmllint -xpath "/DATASTORE_POOL/DATASTORE[ID=${_DS_ID}]" "${_DS_POOL_FILE}" >"${_tmpXML}"
        _ret=$?
    else
        oneCallXml onedatastore show "${_DS_ID}" "${_tmpXML}"
        _ret=$?
    fi

    if [[ ${_ret} -ne 0 ]]; then
        _errmsg="(oneDatastoreInfo) Error: Can't get info DS=${_DS_ID}! $(head -n 1 "${_tmpXML}") (ret:${_ret})"
        log_error "${_errmsg}"
        splog "${_errmsg}"
        exit "${_ret}"
    fi

    sed -i '/\/>$/d' "${_tmpXML}"
    _XPATH="$(lookup_file "datastore/xpath.rb" || true)"
    declare -a _XPATH_A _XPATH_QUERY
    _XPATH_A=(
        "${_XPATH}"
        "--stdin"
    )
    _XPATH_QUERY=(
        "/DATASTORE/NAME"
        "/DATASTORE/TYPE"
        "/DATASTORE/DISK_TYPE"
        "/DATASTORE/DS_MAD"
        "/DATASTORE/TM_MAD"
        "/DATASTORE/BASE_PATH"
        "/DATASTORE/CLUSTER_ID"
        "%m%/DATASTORE/CLUSTERS/ID"
        "/DATASTORE/TEMPLATE/SHARED"
        "/DATASTORE/TEMPLATE/TYPE"
        "/DATASTORE/TEMPLATE/RSYNC_HOST"
        "/DATASTORE/TEMPLATE/RSYNC_USER"
        "/DATASTORE/TEMPLATE/RESTIC_SFTP_SERVER"
        "/DATASTORE/TEMPLATE/RESTIC_SFTP_USER"
        "/DATASTORE/TEMPLATE/BRIDGE_LIST"
        "/DATASTORE/TEMPLATE/EXPORT_BRIDGE_LIST"
        "/DATASTORE/TEMPLATE/SP_REPLICATION"
        "/DATASTORE/TEMPLATE/SP_PLACEALL"
        "/DATASTORE/TEMPLATE/SP_PLACETAIL"
        "/DATASTORE/TEMPLATE/SP_PLACEHEAD"
        "/DATASTORE/TEMPLATE/SP_IOPS"
        "/DATASTORE/TEMPLATE/SP_BW"
        "/DATASTORE/TEMPLATE/SP_SYSTEM"
        "/DATASTORE/TEMPLATE/SP_TEMPLATE_PROPAGATE"
        "/DATASTORE/TEMPLATE/SP_API_HTTP_HOST"
        "/DATASTORE/TEMPLATE/SP_API_HTTP_PORT"
        "/DATASTORE/TEMPLATE/SP_AUTH_TOKEN"
        "/DATASTORE/TEMPLATE/SP_CLONE_GW"
        "/DATASTORE/TEMPLATE/SP_CLUSTER_ID"
        "/DATASTORE/TEMPLATE/VMSNAPSHOT_LIMIT"
        "/DATASTORE/TEMPLATE/DISKSNAPSHOT_LIMIT"
        "/DATASTORE/TEMPLATE/SP_QOSCLASS"
        "/DATASTORE/TEMPLATE/REMOTE_BACKUP_DELETE"
    )
    unset i XPATH_ELEMENTS
    while IFS='' read -r -u "${xfh}" -d '' _element; do
        XPATH_ELEMENTS[i++]="${_element}"
    done {xfh}< <("${_XPATH_A[@]}" < "${_tmpXML}" "${_XPATH_QUERY[@]}" || true)
    exec {xfh}<&-
    rm -f "${_tmpXML}"

    unset i
    DS_NAME="${XPATH_ELEMENTS[i++]}"
    DS_TYPE="${XPATH_ELEMENTS[i++]}"
    DS_DISK_TYPE="${XPATH_ELEMENTS[i++]}"
    DS_DS_MAD="${XPATH_ELEMENTS[i++]}"
    DS_TM_MAD="${XPATH_ELEMENTS[i++]}"
    DS_BASE_PATH="${XPATH_ELEMENTS[i++]}"
    DS_CLUSTER_ID="${XPATH_ELEMENTS[i++]}"
    _DS_CLUSTERS_ID="${XPATH_ELEMENTS[i++]}"
    read -r -a DS_CLUSTERS_ID <<< "${_DS_CLUSTERS_ID}"
    DS_SHARED="${XPATH_ELEMENTS[i++]}"
    DS_TEMPLATE_TYPE="${XPATH_ELEMENTS[i++]}"
    DS_RSYNC_HOST="${XPATH_ELEMENTS[i++]}"
    DS_RSYNC_USER="${XPATH_ELEMENTS[i++]}"
    DS_RESTIC_SFTP_SERVER="${XPATH_ELEMENTS[i++]}"
    DS_RESTIC_SFTP_USER="${XPATH_ELEMENTS[i++]}"
    BRIDGE_LIST="${XPATH_ELEMENTS[i++]}"
    EXPORT_BRIDGE_LIST="${XPATH_ELEMENTS[i++]}"
    SP_REPLICATION="${XPATH_ELEMENTS[i++]}"
    SP_PLACEALL="${XPATH_ELEMENTS[i++]}"
    SP_PLACETAIL="${XPATH_ELEMENTS[i++]}"
    SP_PLACEHEAD="${XPATH_ELEMENTS[i++]}"
    SP_IOPS="${XPATH_ELEMENTS[i++]:--}"
    SP_BW="${XPATH_ELEMENTS[i++]:--}"
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [[ -n "${_TMP}" ]]; then
        SP_SYSTEM="${_TMP}"
    fi
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [[ -n "${_TMP}" ]]; then
        SP_TEMPLATE_PROPAGATE="${_TMP}"
    fi
    SP_API_HTTP_HOST="${XPATH_ELEMENTS[i++]}"
    SP_API_HTTP_PORT="${XPATH_ELEMENTS[i++]}"
    SP_AUTH_TOKEN="${XPATH_ELEMENTS[i++]}"
    SP_CLONE_GW="${XPATH_ELEMENTS[i++]}"
    SP_CLUSTER_ID="${XPATH_ELEMENTS[i++]}"
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [[ -n "${_TMP}" ]] && [[ -z "${_TMP//[[:digit:]]/}" ]]; then
        VMSNAPSHOT_LIMIT="${_TMP}"
    fi
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [[ -n "${_TMP}" ]] && [[ -z "${_TMP//[[:digit:]]/}" ]]; then
        DISKSNAPSHOT_LIMIT="${_TMP}"
    fi
    DS_SP_QOSCLASS="${XPATH_ELEMENTS[i++]}"
    REMOTE_BACKUP_DELETE="${XPATH_ELEMENTS[i++]}"

    if [[ -n "${SP_API_HTTP_HOST}" ]]; then
        export SP_API_HTTP_HOST
    else
        unset SP_API_HTTP_HOST
    fi
    if [[ -n "${SP_API_HTTP_PORT}" ]]; then
        export SP_API_HTTP_PORT
    else
        unset SP_API_HTTP_PORT
    fi
    if [[ -n "${SP_AUTH_TOKEN}" ]]; then
        export SP_AUTH_TOKEN
    else
        unset SP_AUTH_TOKEN
    fi

    boolTrue "DEBUG_oneDatastoreInfo" || return 0
    local _DBGMSG="${DS_TYPE:+DS_TYPE=${DS_TYPE} }${DS_TEMPLATE_TYPE:+TEMPLATE_TYPE=${DS_TEMPLATE_TYPE} }"
    _DBGMSG+="${DS_DISK_TYPE:+DISK_TYPE=${DS_DISK_TYPE} }${DS_DS_MAD:+DS_DS_MAD=${DS_DS_MAD} }${DS_TM_MAD:+DS_TM_MAD=${DS_TM_MAD} }"
    _DBGMSG+="${DS_BASE_PATH:+BASE_PATH=${DS_BASE_PATH} }${DS_CLUSTER_ID:+CLUSTER_ID=${DS_CLUSTER_ID} }"
    _DBGMSG+="${DS_CLUSTERS_ID:+DS_CLUSTERS_ID=[${DS_CLUSTERS_ID[*]}] }"
    _DBGMSG+="${DS_SHARED:+SHARED=${DS_SHARED} }${SP_CLUSTER_ID:+SP_CLUSTER_ID=${SP_CLUSTER_ID} }"
    _DBGMSG+="${SP_SYSTEM:+SP_SYSTEM=${SP_SYSTEM} }${SP_CLONE_GW:+SP_CLONE_GW=${SP_CLONE_GW} }"
    _DBGMSG+="${EXPORT_BRIDGE_LIST:+EXPORT_BRIDGE_LIST=${EXPORT_BRIDGE_LIST} }"
    _DBGMSG+="${DS_NAME:+NAME=${DS_NAME} }${VMSNAPSHOT_LIMIT:+VMSNAPSHOT_LIMIT=${VMSNAPSHOT_LIMIT} }${DISKSNAPSHOT_LIMIT:+DISKSNAPSHOT_LIMIT=${DISKSNAPSHOT_LIMIT} }"
    _DBGMSG+="${SP_REPLICATION:+SP_REPLICATION=${SP_REPLICATION} }"
    _DBGMSG+="${SP_PLACEALL:+SP_PLACEALL=${SP_PLACEALL} }${SP_PLACETAIL:+SP_PLACETAIL=${SP_PLACETAIL} }${SP_PLACEHEAD:+SP_PLACEHEAD=${SP_PLACEHEAD} }"
    _DBGMSG+="${DS_SP_QOSCLASS:+DS_SP_QOSCLASS=${DS_SP_QOSCLASS} }"
    _DBGMSG+="${REMOTE_BACKUP_DELETE:+REMOTE_BACKUP_DELETE=${REMOTE_BACKUP_DELETE} }"
    _DBGMSG+="${DS_RSYNC_HOST:+DS_RSYNC_HOST=${DS_RSYNC_HOST} }${DS_RSYNC_USER:+DS_RSYNC_USER=${DS_RSYNC_USER} }"
    _DBGMSG+="${DS_RESTIC_SFTP_SERVER:+DS_RESTIC_SFTP_SERVER=${DS_RESTIC_SFTP_SERVER} }${DS_RESTIC_SFTP_USER:+DS_RESTIC_SFTP_USER=${DS_RESTIC_SFTP_USER} }"
    splog "[D][oneDatastoreInfo]${_DBGMSG}"
}

function dumpTemplate()
{
    local _TEMPLATE="$1"
    echo "${_TEMPLATE}" | base64 -d | xmllint --format - > "/tmp/${LOG_PREFIX:-tm}_${0##*/}-$$.xml" || true
}

function oneTemplateInfo()
{
    local _TEMPLATE="$1"
    local _XPATH="" _ret=0 _errmsg="" _tmpXML="" _element="" xfh=""
    local _DBGMSG="" _ONEVMXML=""
    if boolTrue "DDDDEBUG_oneTemplateInfo"; then
        dumpTemplate "${_TEMPLATE}"
    fi
    if [[ -z "${_TEMPLATE}" ]]; then
        _TEMPLATE="${TMPDIR:-/tmp}/onevm-${VM_ID}.XML.b64"
        _ONEVMXML="${TMPDIR:-/tmp}/onevm-${VM_ID}.XML"
        if [[ ! -f "${_ONEVMXML}" ]]; then
            oneCallXml onevm show "${VM_ID}" "${_ONEVMXML}"
            _ret=$?
            if [[ ${_ret} -ne 0 ]]; then
                _errmsg="(oneTemplateInfo) Error: Can't get template for VM=${VM_ID}! (ret:${_ret})"
                log_error "${_errmsg}"
                splog "${_errmsg}"
                exit "${_ret}"
            fi
        fi
        base64 -w 0 "${_ONEVMXML}" >"${_TEMPLATE}"
        _ret=$?
        if [[ ${_ret} -ne 0 ]]; then
            _errmsg="(oneTemplateInfo) Error: Can't pack with base64${_ONEVMXML} to ${_TEMPLATE}! (ret:${_ret})"
            log_error "${_errmsg}"
            splog "${_errmsg}"
            exit "${_ret}"
        fi
    fi

    _XPATH="$(lookup_file "datastore/xpath-sp.rb" || true)"
    declare -a _XPATH_A _XPATH_QUERY
    _XPATH_A=("${_XPATH}" "-b")
    if [[ -f "${_TEMPLATE}" ]]; then
        _XPATH_A+=("yes" "-f")
    fi
    _XPATH_QUERY=(
        "/VM/ID"
        "/VM/STATE"
        "/VM/LCM_STATE"
        "/VM/PREV_STATE"
        "/VM/TEMPLATE/CONTEXT/DISK_ID"
        "/VM/USER_TEMPLATE/T_OS_NVRAM"
        "/VM/USER_TEMPLATE/SP_QOSCLASS"
        "/VM/USER_TEMPLATE/VC_POLICY"
        "/VM/TEMPLATE/TPM/MODEL"
    )

    if boolTrue "DEBUG_oneTemplateInfo"; then
        splog "[D][oneTemplateInfo] _XPATH=${_XPATH_A[*]} ${_TEMPLATE:0:20}..."
    fi

    unset i XPATH_ELEMENTS
    while IFS='' read -r -u "${xfh}" -d '' _element; do
        XPATH_ELEMENTS[i++]="${_element}"
    done {xfh}< <("${_XPATH_A[@]}" "${_TEMPLATE}" "${_XPATH_QUERY[@]}" || true)
    exec {xfh}<&-

    unset i
    VM_ID="${XPATH_ELEMENTS[i++]}"
    VM_STATE="${XPATH_ELEMENTS[i++]}"
    VM_LCM_STATE="${XPATH_ELEMENTS[i++]}"
    VM_PREV_STATE="${XPATH_ELEMENTS[i++]}"
    CONTEXT_DISK_ID="${XPATH_ELEMENTS[i++]}"
    T_OS_NVRAM="${XPATH_ELEMENTS[i++]}"
    VM_SP_QOSCLASS="${XPATH_ELEMENTS[i++]}"
    VC_POLICY="${XPATH_ELEMENTS[i++]}"
    TPM_MODEL="${XPATH_ELEMENTS[i++]}"
    if boolTrue "DEBUG_oneTemplateInfo"; then
        _DBGMSG="VM_ID=${VM_ID} VM_STATE=${VM_STATE}(${VmState[${VM_STATE}]})"
        _DBGMSG+=" VM_LCM_STATE=${VM_LCM_STATE}(${LcmState[${VM_LCM_STATE}]})"
        _DBGMSG+=" VM_PREV_STATE=${VM_PREV_STATE}(${VmState[${VM_PREV_STATE}]})"
        _DBGMSG+=" CONTEXT_DISK_ID=${CONTEXT_DISK_ID}"
        _DBGMSG+=" VC_POLICY=${VC_POLICY}"
        _DBGMSG+=" VM_SP_QOSCLASS=${VM_SP_QOSCLASS}"
        _DBGMSG+=" TPM_MODEL=${TPM_MODEL}"
        splog "[D][oneTemplateInfo]${_DBGMSG}"
    fi

    _XPATH="$(lookup_file "datastore/xpath_multi.py" || true)"
    _XPATH_A=("${_XPATH}" "-b")
    if [[ -f "${_TEMPLATE}" ]]; then
        _XPATH_A+=("-f")
    fi
    _XPATH_QUERY=(
        "/VM/TEMPLATE/DISK/TM_MAD"
        "/VM/TEMPLATE/DISK/DATASTORE_ID"
        "/VM/TEMPLATE/DISK/DISK_ID"
        "/VM/TEMPLATE/DISK/CLUSTER_ID"
        "/VM/TEMPLATE/DISK/SOURCE"
        "/VM/TEMPLATE/DISK/PERSISTENT"
        "/VM/TEMPLATE/DISK/SHAREABLE"
        "/VM/TEMPLATE/DISK/TYPE"
        "/VM/TEMPLATE/DISK/CLONE"
        "/VM/TEMPLATE/DISK/READONLY"
        "/VM/TEMPLATE/DISK/IMAGE_ID"
        "/VM/TEMPLATE/DISK/FORMAT"
    )
    unset i XPATH_ELEMENTS
    while read -r -u "${xfh}" _element; do
        XPATH_ELEMENTS[i++]="${_element}"
    done {xfh}< <("${_XPATH_A[@]}" "${_TEMPLATE}" "${_XPATH_QUERY[@]}" || true)
    exec {xfh}<&-

    unset i
    _DISK_TM_MAD="${XPATH_ELEMENTS[i++]}"
    _DISK_DS_ID="${XPATH_ELEMENTS[i++]}"
    _DISK_ID="${XPATH_ELEMENTS[i++]}"
    _DISK_CLUSTER_ID="${XPATH_ELEMENTS[i++]}"
    _DISK_SOURCE="${XPATH_ELEMENTS[i++]}"
    _DISK_PERSISTENT="${XPATH_ELEMENTS[i++]}"
    _DISK_SHAREABLE="${XPATH_ELEMENTS[i++]}"
    _DISK_TYPE="${XPATH_ELEMENTS[i++]}"
    _DISK_CLONE="${XPATH_ELEMENTS[i++]}"
    _DISK_READONLY="${XPATH_ELEMENTS[i++]}"
    _DISK_IMAGE_ID="${XPATH_ELEMENTS[i++]}"
    _DISK_FORMAT="${XPATH_ELEMENTS[i++]}"

    # shellcheck disable=SC2034
    {
    IFS=';' read -r -a DISK_TM_MAD_ARRAY <<< "${_DISK_TM_MAD}"
    IFS=';' read -r -a DISK_DS_ID_ARRAY <<< "${_DISK_DS_ID}"
    IFS=';' read -r -a DISK_ID_ARRAY <<< "${_DISK_ID}"
    IFS=';' read -r -a DISK_CLUSTER_ID_ARRAY <<< "${_DISK_CLUSTER_ID}"
    IFS=';' read -r -a DISK_SOURCE_ARRAY <<< "${_DISK_SOURCE}"
    IFS=';' read -r -a DISK_PERSISTENT_ARRAY <<< "${_DISK_PERSISTENT}"
    IFS=';' read -r -a DISK_SHAREABLE_ARRAY <<< "${_DISK_SHAREABLE}"
    IFS=';' read -r -a DISK_TYPE_ARRAY <<< "${_DISK_TYPE}"
    IFS=';' read -r -a DISK_CLONE_ARRAY <<< "${_DISK_CLONE}"
    IFS=';' read -r -a DISK_READONLY_ARRAY <<< "${_DISK_READONLY}"
    IFS=';' read -r -a DISK_IMAGE_ID_ARRAY <<< "${_DISK_IMAGE_ID}"
    IFS=';' read -r -a DISK_FORMAT_ARRAY <<< "${_DISK_FORMAT}"
    }

    boolTrue "DEBUG_oneTemplateInfo" || return 0
    _DBGMSG="disktm:${_DISK_TM_MAD} ds:${_DISK_DS_ID} disk:${_DISK_ID} cluster:${_DISK_CLUSTER_ID}"
    _DBGMSG+=" src:${_DISK_SOURCE} persistent:${_DISK_PERSISTENT} type:${_DISK_TYPE} clone:${_DISK_CLONE}"
    _DBGMSG+=" readonly:${_DISK_READONLY} format:${_DISK_FORMAT} shareable:${_DISK_SHAREABLE}"
    splog "[D][oneTemplateInfo] ${_DBGMSG}"
}

function oneDsDriverAction()
{
    local _XPATH="" _ret=0 _errmsg="" _tmpXML="" _element="" xfh=""

    if boolTrue "DDDDEBUG_oneDsDriverAction"; then
        local _DBGFILE="/tmp/${LOG_PREFIX:-tm}_${0##*/}-$$.xml"
        echo "${DRV_ACTION:-}" |base64 -d | xmllint --format - >"${_DBGFILE}" || true
        splog "[DDDD][DriverAction] ${_DBGFILE}"
    fi

    _XPATH="$(lookup_file "datastore/xpath.rb" || true)"
    declare -a _XPATH_A _XPATH_QUERY
    _XPATH_A=("${_XPATH}" "-b")
    _XPATH_QUERY=(
        "/DS_DRIVER_ACTION_DATA/DATASTORE/BASE_PATH"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/ID"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/STATE"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/UID"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/GID"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/CLUSTER_ID"
        "%m%/DS_DRIVER_ACTION_DATA/DATASTORE/CLUSTERS/ID"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TYPE"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TM_MAD"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/BRIDGE_LIST"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/EXPORT_BRIDGE_LIST"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_REPLICATION"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_PLACEALL"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_PLACETAIL"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_PLACEHEAD"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_IOPS"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_BW"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_API_HTTP_HOST"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_API_HTTP_PORT"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_AUTH_TOKEN"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_CLONE_GW"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_CLUSTER_ID"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_SYSTEM"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_QOSCLASS"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_TEMPLATE_PROPAGATE"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/NO_DECOMPRESS"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/LIMIT_TRANSFER_BW"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/TYPE"
        "/DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/REMOTE_BACKUP_DELETE"
        "/DS_DRIVER_ACTION_DATA/IMAGE/TEMPLATE/MD5"
        "/DS_DRIVER_ACTION_DATA/IMAGE/TEMPLATE/SHA1"
        "/DS_DRIVER_ACTION_DATA/IMAGE/TEMPLATE/DRIVER"
        "/DS_DRIVER_ACTION_DATA/IMAGE/TEMPLATE/FORMAT"
        "/DS_DRIVER_ACTION_DATA/IMAGE/TEMPLATE/SP_QOSCLASS"
        "/DS_DRIVER_ACTION_DATA/IMAGE/TEMPLATE/SAVED_DISK_ID"
        "/DS_DRIVER_ACTION_DATA/IMAGE/TEMPLATE/SAVED_VM_ID"
        "/DS_DRIVER_ACTION_DATA/IMAGE/TEMPLATE/SAVE_AS_HOT"
        "/DS_DRIVER_ACTION_DATA/IMAGE/TEMPLATE/PERSISTENT_TYPE"
        "/DS_DRIVER_ACTION_DATA/IMAGE/PATH"
        "/DS_DRIVER_ACTION_DATA/IMAGE/PERSISTENT"
        "/DS_DRIVER_ACTION_DATA/IMAGE/SHAREABLE"
        "/DS_DRIVER_ACTION_DATA/IMAGE/FSTYPE"
        "/DS_DRIVER_ACTION_DATA/IMAGE/SOURCE"
        "/DS_DRIVER_ACTION_DATA/IMAGE/TYPE"
        "/DS_DRIVER_ACTION_DATA/IMAGE/FS"
        "/DS_DRIVER_ACTION_DATA/IMAGE/CLONE"
        "/DS_DRIVER_ACTION_DATA/IMAGE/SAVE"
        "/DS_DRIVER_ACTION_DATA/IMAGE/DISK_TYPE"
        "/DS_DRIVER_ACTION_DATA/IMAGE/STATE"
        "/DS_DRIVER_ACTION_DATA/IMAGE/CLONING_ID"
        "/DS_DRIVER_ACTION_DATA/IMAGE/CLONING_OPS"
        "/DS_DRIVER_ACTION_DATA/IMAGE/TARGET_SNAPSHOT"
        "/DS_DRIVER_ACTION_DATA/IMAGE/SIZE"
        "/DS_DRIVER_ACTION_DATA/IMAGE/UID"
        "/DS_DRIVER_ACTION_DATA/IMAGE/GID"
        "/DS_DRIVER_ACTION_DATA/MONITOR_VM_DISKS"
    )

    unset i XPATH_ELEMENTS
    while IFS='' read -r -u "${xfh}" -d '' _element; do
        XPATH_ELEMENTS[i++]="${_element}"
    done {xfh}< <("${_XPATH_A[@]}" "${DRV_ACTION}" "${_XPATH_QUERY[@]}" || true)
    exec {xfh}<&-
    unset i
    # shellcheck disable=SC2034
    {
    BASE_PATH="${XPATH_ELEMENTS[i++]}"
    DATASTORE_ID="${XPATH_ELEMENTS[i++]}"
    DATASTORE_STATE="${XPATH_ELEMENTS[i++]}"
    DATASTORE_UID="${XPATH_ELEMENTS[i++]}"
    DATASTORE_GID="${XPATH_ELEMENTS[i++]}"
    CLUSTER_ID="${XPATH_ELEMENTS[i++]}"
    CLUSTERS_ID="${XPATH_ELEMENTS[i++]}"
    DATASTORE_TYPE="${XPATH_ELEMENTS[i++]}"
    TM_MAD="${XPATH_ELEMENTS[i++]}"
    BRIDGE_LIST="${XPATH_ELEMENTS[i++]}"
    EXPORT_BRIDGE_LIST="${XPATH_ELEMENTS[i++]}"
    SP_REPLICATION="${XPATH_ELEMENTS[i++]:-2}"
    SP_PLACEALL="${XPATH_ELEMENTS[i++]}"
    SP_PLACETAIL="${XPATH_ELEMENTS[i++]}"
    SP_PLACEHEAD="${XPATH_ELEMENTS[i++]}"
    SP_IOPS="${XPATH_ELEMENTS[i++]:--}"
    SP_BW="${XPATH_ELEMENTS[i++]:--}"
    SP_API_HTTP_HOST="${XPATH_ELEMENTS[i++]}"
    SP_API_HTTP_PORT="${XPATH_ELEMENTS[i++]}"
    SP_AUTH_TOKEN="${XPATH_ELEMENTS[i++]}"
    SP_CLONE_GW="${XPATH_ELEMENTS[i++]}"
    SP_CLUSTER_ID="${XPATH_ELEMENTS[i++]}"
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [[ -n "${_TMP}" ]]; then
        SP_SYSTEM="${_TMP}"
    fi
    DS_SP_QOSCLASS="${XPATH_ELEMENTS[i++]}"
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [[ -n "${_TMP}" ]]; then
        SP_TEMPLATE_PROPAGATE="${_TMP}"
    fi
    NO_DECOMPRESS="${XPATH_ELEMENTS[i++]}"
    LIMIT_TRANSFER_BW="${XPATH_ELEMENTS[i++]}"
    DS_TYPE="${XPATH_ELEMENTS[i++]}"
    REMOTE_BACKUP_DELETE="${XPATH_ELEMENTS[i++]}"
    MD5="${XPATH_ELEMENTS[i++]}"
    SHA1="${XPATH_ELEMENTS[i++]}"
    DRIVER="${XPATH_ELEMENTS[i++]}"
    FORMAT="${XPATH_ELEMENTS[i++]}"
    IMAGE_SP_QOSCLASS="${XPATH_ELEMENTS[i++]}"
    SAVED_DISK_ID="${XPATH_ELEMENTS[i++]}"
    SAVED_VM_ID="${XPATH_ELEMENTS[i++]}"
    SAVE_AS_HOT="${XPATH_ELEMENTS[i++]}"
    PERSISTENT_TYPE="${XPATH_ELEMENTS[i++]}"
    IMAGE_PATH="${XPATH_ELEMENTS[i++]}"
    PERSISTENT="${XPATH_ELEMENTS[i++]}"
    SHAREABLE="${XPATH_ELEMENTS[i++]}"
    FSTYPE="${XPATH_ELEMENTS[i++]}"
    SOURCE="${XPATH_ELEMENTS[i++]}"
    TYPE="${XPATH_ELEMENTS[i++]}"
    FS="${XPATH_ELEMENTS[i++]}"
    CLONE="${XPATH_ELEMENTS[i++]}"
    SAVE="${XPATH_ELEMENTS[i++]}"
    DISK_TYPE="${XPATH_ELEMENTS[i++]}"
    STATE="${XPATH_ELEMENTS[i++]}"
    CLONING_ID="${XPATH_ELEMENTS[i++]}"
    CLONING_OPS="${XPATH_ELEMENTS[i++]}"
    TARGET_SNAPSHOT="${XPATH_ELEMENTS[i++]}"
    SIZE="${XPATH_ELEMENTS[i++]}"
    IMAGE_UID="${XPATH_ELEMENTS[i++]}"
    IMAGE_GID="${XPATH_ELEMENTS[i++]}"
    MONITOR_VM_DISKS="${XPATH_ELEMENTS[i++]}"
    }

    if [[ -n "${SP_API_HTTP_HOST}" ]]; then
        export SP_API_HTTP_HOST
    else
        unset SP_API_HTTP_HOST
    fi
    if [[ -n "${SP_API_HTTP_PORT}" ]]; then
        export SP_API_HTTP_PORT
    else
        unset SP_API_HTTP_PORT
    fi
    if [[ -n "${SP_AUTH_TOKEN}" ]]; then
        export SP_AUTH_TOKEN
    else
        unset SP_AUTH_TOKEN
    fi

    boolTrue "DEBUG_oneDsDriverAction" || return 0
    local _DBGMSG="[oneDsDriverAction]\
${ID:+ID=${ID} }\
${IMAGE_UID:+IMAGE_UID=${IMAGE_UID} }\
${IMAGE_GID:+IMAGE_GID=${IMAGE_GID} }\
${DATASTORE_ID:+DATASTORE_ID=${DATASTORE_ID} }\
${DATASTORE_STATE:+DATASTORE_STATE=${DATASTORE_STATE} }\
${DATASTORE_TYPE:+DATASTORE_TYPE=${DATASTORE_TYPE} }\
${CLUSTER_ID:+CLUSTER_ID=${CLUSTER_ID} }\
${CLUSTERS_ID:+CLUSTERS_ID=${CLUSTERS_ID} }\
${STATE:+STATE=${STATE} }\
${SIZE:+SIZE=${SIZE} }\
${SP_API_HTTP_HOST:+SP_API_HTTP_HOST=${SP_API_HTTP_HOST} }\
${SP_API_HTTP_PORT:+SP_API_HTTP_PORT=${SP_API_HTTP_PORT} }\
${SP_AUTH_TOKEN:+SP_AUTH_TOKEN=DEFINED }\
${SP_CLONE_GW:+SP_CLONE_GW=${SP_CLONE_GW} }\
${SP_CLUSTER_ID:+SP_CLUSTER_ID=${SP_CLUSTER_ID} }\
${SOURCE:+SOURCE=${SOURCE} }\
${PERSISTENT:+PERSISTENT=${PERSISTENT} }\
${SHAREABLE:+SHAREABLE=${SHAREABLE} }\
${PERSISTENT_TYPE:+PERSISTENT_TYPE=${PERSISTENT_TYPE} }\
${DRIVER:+DRIVER=${DRIVER} }\
${FORMAT:+FORMAT=${FORMAT} }\
${SAVED_DISK_ID:+SAVED_DISK_ID=${SAVED_DISK_ID} }\
${SAVED_VM_ID:+SAVED_VM_ID=${SAVED_VM_ID} }\
${SAVE_AS_HOT:+SAVE_AS_HOT=${SAVE_AS_HOT} }\
${FSTYPE:+FSTYPE=${FSTYPE} }\
${FS:+FS=${FS} }\
${TYPE:+TYPE=${TYPE} }\
${CLONE:+CLONE=${CLONE} }\
${SAVE:+SAVE=${SAVE} }\
${SHA1:+SHA1=${SHA1} }\
${NO_DECOMPRESS:+NO_DECOMPRESS=${NO_DECOMPRESS} }\
${LIMIT_TRANSFER_BW:+LIMIT_TRANSFER_BW=${LIMIT_TRANSFER_BW} }\
${DISK_TYPE:+DISK_TYPE=${DISK_TYPE} }\
${CLONING_ID:+CLONING_ID=${CLONING_ID} }\
${CLONING_OPS:+CLONING_OPS=${CLONING_OPS} }\
${IMAGE_PATH:+IMAGE_PATH=${IMAGE_PATH} }\
${BRIDGE_LIST:+BRIDGE_LIST=${BRIDGE_LIST} }\
${EXPORT_BRIDGE_LIST:+EXPORT_BRIDGE_LIST=${EXPORT_BRIDGE_LIST} }\
${BASE_PATH:+BASE_PATH=${BASE_PATH} }\
${SP_REPLICATION:+SP_REPLICATION=${SP_REPLICATION} }\
${SP_PLACEALL:+SP_PLACEALL=${SP_PLACEALL} }\
${SP_PLACETAIL:+SP_PLACETAIL=${SP_PLACETAIL} }\
${SP_PLACEHEAD:+SP_PLACEHEAD=${SP_PLACEHEAD} }\
${SP_IOPS:+SP_IOPS=${SP_IOPS} }\
${SP_BW:+SP_BW=${SP_BW} }\
${SP_SYSTEM:+SP_SYSTEM=${SP_SYSTEM} }\
${TARGET_SNAPSHOT:+TARGET_SNAPSHOT=${TARGET_SNAPSHOT} }\
${SP_TEMPLATE_PROPAGATE:+SP_TEMPLATE_PROPAGATE=${SP_TEMPLATE_PROPAGATE} }\
${REMOTE_BACKUP_DELETE:+REMOTE_BACKUP_DELETE=${REMOTE_BACKUP_DELETE} }\
${MONITOR_VM_DISKS:+MONITOR_VM_DISKS=${MONITOR_VM_DISKS} }\
${IMAGE_SP_QOSCLASS:+IMAGE_SP_QOSCLASS=${IMAGE_SP_QOSCLASS} }\
${DS_SP_QOSCLASS:+DS_SP_QOSCLASS=${DS_SP_QOSCLASS} }\
"
    splog "[D][oneDsDriverAction] ${_DBGMSG}"
}

function oneMarketDriverAction()
{
    local _XPATH="" _element="" xfh=""

    _XPATH="$(lookup_file "datastore/xpath.rb" || true)"
    declare -a _XPATH_A _XPATH_QUERY
    _XPATH_A=("${_XPATH}" "-b")
    _XPATH_QUERY=(
        "/MARKET_DRIVER_ACTION_DATA/IMPORT_SOURCE"
        "/MARKET_DRIVER_ACTION_DATA/FORMAT"
        "/MARKET_DRIVER_ACTION_DATA/DISPOSE"
        "/MARKET_DRIVER_ACTION_DATA/SIZE"
        "/MARKET_DRIVER_ACTION_DATA/MD5"
        "/MARKET_DRIVER_ACTION_DATA/MARKETPLACE/TEMPLATE/BASE_URL"
        "/MARKET_DRIVER_ACTION_DATA/MARKETPLACE/TEMPLATE/BRIDGE_LIST"
        "/MARKET_DRIVER_ACTION_DATA/MARKETPLACE/TEMPLATE/PUBLIC_DIR"
        "/MARKET_DRIVER_ACTION_DATA/MARKETPLACE/TEMPLATE/SP_API_HTTP_HOST"
        "/MARKET_DRIVER_ACTION_DATA/MARKETPLACE/TEMPLATE/SP_API_HTTP_PORT"
        "/MARKET_DRIVER_ACTION_DATA/MARKETPLACE/TEMPLATE/SP_AUTH_TOKEN"
    )
    unset i XPATH_ELEMENTS
    while IFS='' read -r -u "${xfh}" -d '' _element; do
        XPATH_ELEMENTS[i++]="${_element}"
    done {xfh}< <("${_XPATH_A[@]}" "${DRV_ACTION}" "${_XPATH_QUERY[@]}" || true)
    exec {xfh}<&-

    unset i
    IMPORT_SOURCE="${XPATH_ELEMENTS[i++]}"
    FORMAT="${XPATH_ELEMENTS[i++]}"
    DISPOSE="${XPATH_ELEMENTS[i++]}"
    SIZE="${XPATH_ELEMENTS[i++]}"
    MD5="${XPATH_ELEMENTS[i++]}"
    BASE_URL="${XPATH_ELEMENTS[i++]}"
    BRIDGE_LIST="${XPATH_ELEMENTS[i++]}"
    PUBLIC_DIR="${XPATH_ELEMENTS[i++]}"
    SP_API_HTTP_HOST="${XPATH_ELEMENTS[i++]}"
    SP_API_HTTP_PORT="${XPATH_ELEMENTS[i++]}"
    SP_AUTH_TOKEN="${XPATH_ELEMENTS[i++]}"

    if [[ -n "${SP_API_HTTP_HOST}" ]]; then
        export SP_API_HTTP_HOST
    else
        unset SP_API_HTTP_HOST
    fi
    if [[ -n "${SP_API_HTTP_PORT}" ]]; then
        export SP_API_HTTP_PORT
    else
        unset SP_API_HTTP_PORT
    fi
    if [[ -n "${SP_AUTH_TOKEN}" ]]; then
        export SP_AUTH_TOKEN
    else
        unset SP_AUTH_TOKEN
    fi

    boolTrue "DEBUG_oneMarketDriverAction" || return 0
    local _DBGMSG="${IMPORT_SOURCE:+IMPORT_SOURCE=${IMPORT_SOURCE} }"
    _DBGMSG+="${FORMAT:+FORMAT=${FORMAT} }"
    _DBGMSG+="${DISPOSE:+DISPOSE=${DISPOSE} }"
    _DBGMSG+="${SIZE:+SIZE=${SIZE} }"
    _DBGMSG+="${MD5:+MD5=${MD5} }"
    _DBGMSG+="${BASE_URL:+BASE_URL=${BASE_URL} }"
    _DBGMSG+="${BRIDGE_LIST:+BRIDGE_LIST=${BRIDGE_LIST} }"
    _DBGMSG+="${PUBLIC_DIR:+PUBLIC_DIR=${PUBLIC_DIR} }"
    _DBGMSG+="${SP_API_HTTP_HOST:+SP_API_HTTP_HOST=${SP_API_HTTP_HOST} }"
    _DBGMSG+="${SP_API_HTTP_PORT:+SP_API_HTTP_PORT=${SP_API_HTTP_PORT} }"
    _DBGMSG+="${SP_AUTH_TOKEN:+SP_AUTH_TOKEN=available }"
    splog "[D][oneMarketDriverAction] ${_DBGMSG}"
}

function oneImageQc()
{
    local _IMAGE_ID="$1"
    local _IMAGE_LIST_FILE="" _IMAGE_CACHE_FILE="" _errmsg="" _ret=1
    _IMAGE_LIST_FILE="${TMPDIR:-/tmp}/oneimage-list.XML"
    _IMAGE_CACHE_FILE="${TMPDIR:-/tmp}/oneImageQc.cache"
    if [[ ! -f "${_IMAGE_LIST_FILE}" ]]; then
        oneCallXml oneimage list "" "${_IMAGE_LIST_FILE}"
        _ret=$?
        if [[ ${_ret} -ne 0 ]]; then
            _errmsg="Error: Can't get image list! (ret:${_ret})"
            _errmsg+=" //input:$(head -n 1 "${_IMAGE_LIST_FILE}")"
            log_error "${_errmsg}"
            splog "${_errmsg}"
            exit "${_ret}"
        fi
        xmlstarlet sel -t -m '//IMAGE' \
            -o 'img;' -v 'ID' \
            -o ';' -v "DATASTORE_ID" \
            -o ';' -v "PERSISTENT" \
            -o ';' -v "TEMPLATE/SP_QOSCLASS" \
            -o ';' -v "VMS/ID" \
            -n "${_IMAGE_LIST_FILE}" >"${_IMAGE_CACHE_FILE}"
        _ret=$?
        if [[ ${_ret} -ne 0 ]]; then
            _errmsg="Error: Can't process image list! (ret:${_ret})"
            _errmsg+=" //input:$(head -n 1 "${_IMAGE_LIST_FILE}")"
            _errmsg+=" //stdout:$(head -n 1 "${_IMAGE_CACHE_FILE}")"
            log_error "${_errmsg}"
            splog "${_errmsg}"
            exit "${_ret}"
        fi
    fi
    IFS=';' read -r -a _IMAGE_DATA_A <<< "$(grep "img;${_IMAGE_ID};" "${_IMAGE_CACHE_FILE}" | head -n 1 || true)"
    if [[ ${#_IMAGE_DATA_A[@]} -eq 0 ]]; then
        unset IMAGE_QC_ID
        unset IMAGE_QC_DATASTORE_ID
        unset IMAGE_QC_PERSISTENT
        unset IMAGE_SP_QOSCLASS
    else
        export IMAGE_QC_ID="${_IMAGE_DATA_A[1]}"
        export IMAGE_QC_DATASTORE_ID="${_IMAGE_DATA_A[2]}"
        export IMAGE_QC_PERSISTENT="${_IMAGE_DATA_A[3]}"
        export IMAGE_SP_QOSCLASS="${_IMAGE_DATA_A[4]}"
    fi
    if boolTrue "DEBUG_oneImageQc"; then
        splog "[D][oneImageQc] (${_IMAGE_ID}) IMAGE_SP_QOSCLASS=${IMAGE_SP_QOSCLASS} [${_IMAGE_DATA_A[*]}]"
    fi
}

function oneVmVolumes()
{
    local VM_ID="$1" VM_POOL_FILE="$2" VM_XML_FILE="$3"
    local _tmpXML="" _errmsg="" _ret=1 _XPATH="" _element="" xfh=""
    if boolTrue "DEBUG_oneVmVolumes"; then
        splog "[D][oneVmVolumes] VM_ID:${VM_ID} vmPoolFile:${VM_POOL_FILE}${VM_XML_FILE:+ VM_XML_FILE:${VM_XML_FILE}}"
    fi

    if [[ -z "${VM_XML_FILE}" ]]; then
        _tmpXML="${TMPDIR:-/tmp}/oneVmVolumes-${VM_ID}.XML"
        if [[ -f "${VM_POOL_FILE}" ]]; then
            xmllint -xpath "/VM_POOL/VM[ID=${VM_ID}]" "${VM_POOL_FILE}" >"${_tmpXML}"
            _ret=$?
        else
            oneCallXml onevm show "${VM_ID}" "${_tmpXML}"
            _ret=$?
        fi
        if [[ ${_ret} -ne 0 ]]; then
            _errmsg="(oneVmVolumes) Error: Can't get VM info! $(head -n 1 "${_tmpXML}") (ret:${_ret})"
            log_error "${_errmsg}"
            splog "${_errmsg}"
            exit "${_ret}"
        fi
        VM_XML_FILE="${_tmpXML}"
    fi

    _XPATH="$(lookup_file "datastore/xpath-sp.rb")"
    declare -a _XPATH_A _XPATH_QUERY
    _XPATH_A=("${_XPATH}" "-s")
    _XPATH_QUERY=(
        "/VM/STATE"
        "/VM/LCM_STATE"
    )

    unset XPATH_ELEMENTS i
    while IFS='' read -r -u "${xfh}" -d '' _element; do
        XPATH_ELEMENTS[i++]="${_element}"
    done {xfh}< <("${_XPATH_A[@]}" <"${VM_XML_FILE}" "${_XPATH_QUERY[@]}" || true)
    exec {xfh}<&-

    unset i
    VM_STATE=${XPATH_ELEMENTS[i++]}
    # shellcheck disable=SC2034
    VM_LCM_STATE=${XPATH_ELEMENTS[i++]}

    _XPATH="$(lookup_file "datastore/xpath_multi.py")"
    declare -a _XPATH_A _XPATH_QUERY
    _XPATH_A=("${_XPATH}" "-s")
    _XPATH_QUERY=(
        "/VM/HISTORY_RECORDS/HISTORY[last()]/DS_ID"
        "/VM/TEMPLATE/CONTEXT/DISK_ID"
        "/VM/TEMPLATE/DISK/DISK_ID"
        "/VM/TEMPLATE/DISK/CLONE"
        "/VM/TEMPLATE/DISK/SAVE"
        "/VM/TEMPLATE/DISK/FORMAT"
        "/VM/TEMPLATE/DISK/TYPE"
        "/VM/TEMPLATE/DISK/SHAREABLE"
        "/VM/TEMPLATE/DISK/READONLY"
        "/VM/TEMPLATE/DISK/TM_MAD"
        "/VM/TEMPLATE/DISK/TARGET"
        "/VM/TEMPLATE/DISK/IMAGE_ID"
        "/VM/TEMPLATE/DISK/DATASTORE_ID"
        "/VM/TEMPLATE/SNAPSHOT/SNAPSHOT_ID"
        "/VM/USER_TEMPLATE/VMSNAPSHOT_LIMIT"
        "/VM/USER_TEMPLATE/DISKSNAPSHOT_LIMIT"
        "/VM/USER_TEMPLATE/T_OS_NVRAM"
        "/VM/USER_TEMPLATE/VMSNAPSHOT_WITH_CHECKPOINT"
        "/VM/USER_TEMPLATE/SP_QOSCLASS"
        "/VM/USER_TEMPLATE/VC_POLICY"
        "/VM/BACKUPS/BACKUP_CONFIG/BACKUP_VOLATILE"
        "/VM/BACKUPS/BACKUP_CONFIG/FS_FREEZE"
        "/VM/BACKUPS/BACKUP_CONFIG/MODE"
        "/VM/TEMPLATE/TPM/MODEL"
    )
    unset XPATH_ELEMENTS i
    while read -r -u "${xfh}" _element; do
        XPATH_ELEMENTS[i++]="${_element}"
    done {xfh}< <("${_XPATH_A[@]}" <"${VM_XML_FILE}" "${_XPATH_QUERY[@]}" || true)
    exec {xfh}<&-

    unset i
    VM_DS_ID="${XPATH_ELEMENTS[i++]}"
    local CONTEXT_DISK_ID="${XPATH_ELEMENTS[i++]}"
    local DISK_ID="${XPATH_ELEMENTS[i++]}"
    local CLONE="${XPATH_ELEMENTS[i++]}"
    local SAVE="${XPATH_ELEMENTS[i++]}"
    local FORMAT="${XPATH_ELEMENTS[i++]}"
    local TYPE="${XPATH_ELEMENTS[i++]}"
    local SHAREABLE="${XPATH_ELEMENTS[i++]}"
    local READONLY="${XPATH_ELEMENTS[i++]}"
    local TM_MAD="${XPATH_ELEMENTS[i++]}"
    local TARGET="${XPATH_ELEMENTS[i++]}"
    local IMAGE_ID="${XPATH_ELEMENTS[i++]}"
    local DATASTORE_ID="${XPATH_ELEMENTS[i++]}"
    local SNAPSHOT_ID="${XPATH_ELEMENTS[i++]}"
    local _TMP=""
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [[ -n "${_TMP}" ]] && [[ -z "${_TMP//[[:digit:]]/}" ]]; then
        export VM_VMSNAPSHOT_LIMIT="${_TMP}"
    fi
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [[ -n "${_TMP}" ]] && [[ -z "${_TMP//[[:digit:]]/}" ]]; then
        export DISKSNAPSHOT_LIMIT="${_TMP}"
    fi
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [[ -n "${_TMP}" ]] && [[ -z "${_TMP//[[:digit:]]/}" ]]; then
        export T_OS_NVRAM="${_TMP}"
    fi
    export VMSNAPSHOT_WITH_CHECKPOINT="${XPATH_ELEMENTS[i++]}" # TBD: check if this is needed
    SP_QOSCLASS_LINE="${XPATH_ELEMENTS[i++]}"
    VC_POLICY="${XPATH_ELEMENTS[i++]}"
    BACKUP_VOLATILE="${XPATH_ELEMENTS[i++]}"
    BACKUP_FS_FREEZE="${XPATH_ELEMENTS[i++]}"
    BACKUP_MODE="${XPATH_ELEMENTS[i++]}"
    TPM_MODEL="${XPATH_ELEMENTS[i++]}"
    IFS=';' read -r -a DISK_ID_A <<< "${DISK_ID}"
    IFS=';' read -r -a CLONE_A <<< "${CLONE}"
    IFS=';' read -r -a SAVE_A <<< "${SAVE}"
    IFS=';' read -r -a FORMAT_A <<< "${FORMAT}"
    IFS=';' read -r -a TYPE_A <<< "${TYPE}"
    IFS=';' read -r -a SHAREABLE_A <<< "${SHAREABLE}"
    IFS=';' read -r -a READONLY_A <<< "${READONLY}"
    IFS=';' read -r -a TM_MAD_A <<< "${TM_MAD}"
    IFS=';' read -r -a TARGET_A <<< "${TARGET}"
    IFS=';' read -r -a IMAGE_ID_A <<< "${IMAGE_ID}"
    IFS=';' read -r -a DATASTORE_ID_A <<< "${DATASTORE_ID}"
    IFS=';' read -r -a SNAPSHOT_ID_A <<< "${SNAPSHOT_ID}"
    IFS=';' read -r -a SP_QOSCLASS_A <<< "${SP_QOSCLASS_LINE}"
    local oneName=""
    vmVolumes=""  # oneName
    vmDisksMap=""  # oneName:DISK_ID
    vmDisksQcMap=""  # oneName:VM_DISK_QOSCLASS
    vmDisksDsMap=""  # oneName:DATASTORE_ID
    vmDisksTypeMap=""  # oneName:DISK_TYPE
    persistentDisksQcMap=""  # oneName:PERSISTENT_IMAGE_QOSCLASS
    vmDisksReadOnlyMap=""  # oneName:READONLY
    unset DISKS_QC_A VM_SP_QOSCLASS oneVmVolumesNotStorPool
    declare -gA DISKS_QC_A  # DISKS_QC_A[DISK_ID]=DISK_QOSCLASS
    for qosclass in "${SP_QOSCLASS_A[@]}"; do
        IFS=':' read -r -a arr <<< "${qosclass}"
        if [[ ${#arr[*]} -eq 1 ]]; then
            if [[ -z "${VM_SP_QOSCLASS}" ]]; then
                VM_SP_QOSCLASS="${qosclass}"
            fi
        elif [[ ${#arr[*]} -eq 2 ]]; then
            did="${arr[0]//[^[:digit:]]/}"
            if [[ -n "${did}" ]]; then
                DISKS_QC_A[${did}]="${arr[1]}"
            fi
        fi
    done
    for idx in "${!DISK_ID_A[@]}"; do
        IMAGE_ID="${IMAGE_ID_A[${idx}]}"
        DATASTORE_ID="${DATASTORE_ID_A[${idx}]}"
        CLONE="${CLONE_A[${idx}]}"
        SAVE="${SAVE_A[${idx}]}"
        FORMAT="${FORMAT_A[${idx}]}"
        TYPE="${TYPE_A[${idx}]}"
        SHAREABLE="${SHAREABLE_A[${idx}]}"
        READONLY="${READONLY_A[${idx}]^^}"
        TM_MAD="${TM_MAD_A[${idx}]}"
        TARGET="${TARGET_A[${idx}]}"
        DISK_ID="${DISK_ID_A[${idx}]}"
        SNAPSHOT_ID="${SNAPSHOT_ID_A[${idx}]}"
        if [[ "${TM_MAD:0:8}" != "storpool" ]]; then
            if ! boolTrue "SYSTEM_COMPATIBLE_DS[${TM_MAD}]"; then
                export oneVmVolumesNotStorPool="${TM_MAD}:disk.${DISK_ID}"
                continue
            fi
        fi
        oneName="${ONE_PX}-img-${IMAGE_ID}"
        xTYPE="PERS"
        if [[ -n "${IMAGE_ID}" ]]; then
            IMMUTABLE="$(isImmutable "${CLONE}" "${SAVE}" "${READONLY}")"
            if boolTrue "CLONE"; then
                oneName+="-${VM_ID}-${DISK_ID}"
                xTYPE="NPERS"
            fi
            if boolTrue "READONLY"; then
                if boolTrue "VMSNAPSHOT_EXCLUDE_READONLY"; then
                    _DBGMSG="Image ${IMAGE_ID} excluded because it is READONLY"
                    _DBGMSG+=" (VMSNAPSHOT_EXCLUDE_READONLY=${VMSNAPSHOT_EXCLUDE_READONLY:-false})"
                    splog "${_DBGMSG}"
                    continue
                fi
                if [[ "${TYPE}" == "CDROM" ]]; then
                    oneName+="-${VM_ID}-${DISK_ID}"
                    xTYPE="CDROM"
                elif boolTrue "IMMUTABLE" "${IMMUTABLE}"; then
                    xTYPE="IMMUT"
                else
                    xTYPE+="RO"
                fi
            fi
        else
            xTYPE="VOL"
            case "${TYPE}" in
                swap)
                    oneName="${ONE_PX}-sys-${VM_ID}-${DISK_ID}"
                    xTYPE+="SWAP"
                    ;;
                *)
                    oneName="${ONE_PX}-sys-${VM_ID}-${DISK_ID}"
            esac
            if boolTrue "READONLY"; then
                xTYPE+="RO"
            fi
        fi
        if boolTrue "DEBUG_oneVmVolumes"; then
            splog "[D] VM ${VM_ID} disk.${DISK_ID} ${oneName} type:${xTYPE} RO:${READONLY_A[${idx}]}"
        fi
        vmDisksDsMap+="${oneName}:${DATASTORE_ID:-${VM_DS_ID}} "
        vmVolumes+="${oneName} "
        if [[ -n "${DISKS_QC_A[${DISK_ID}]+found}" ]]; then
            vmDisksQcMap+="${oneName}:${DISKS_QC_A[${DISK_ID}]} "
        elif [[ "${CLONE^^}" == "NO" ]]; then
            oneImageQc "${IMAGE_ID}"
            if [[ -n "${IMAGE_SP_QOSCLASS}" ]]; then
                persistentDisksQcMap+="${oneName}:${IMAGE_SP_QOSCLASS} "
            fi
        fi
        vmDisks=$(( vmDisks+1 ))
        vmDisksMap+="${oneName}:${DISK_ID} "
        vmDisksTypeMap+="${oneName}:${xTYPE} "
        vmDisksReadOnlyMap+="${oneName}:${READONLY} "
        if boolTrue "SHAREABLE"; then
            oneVmVolumesShareable+="${oneName}:${DISK_ID} "
        fi
    done
    if [[ -n "${T_OS_NVRAM}" ]]; then
        oneName="${ONE_PX}-sys-${VM_ID}-NVRAM"
        vmVolumes+="${oneName} "
        vmDisksMap+="${oneName}: "
        vmDisksTypeMap+="${oneName}:NVRAM "
        vmDisksReadOnlyMap+="${oneName}: "
    fi
    DISK_ID="${CONTEXT_DISK_ID}"
    if [[ -n "${DISK_ID}" ]]; then
        oneName="${ONE_PX}-sys-${VM_ID}-${DISK_ID}"
        vmVolumes+="${oneName} "
        vmDisksMap+="${oneName}:${DISK_ID} "
        vmDisksTypeMap+="${oneName}:CNTXT "
        vmDisksReadOnlyMap+="${oneName}:YES "
        vmDisksDsMap+="${oneName}:${VM_DS_ID} "
        if boolTrue "DEBUG_oneVmVolumes"; then
            splog "[D] VM ${VM_ID} disk.${DISK_ID} ${oneName} //CONTEXT"
        fi
    fi
    if [[ ${VM_STATE} -eq 4 ]] || [[ ${VM_STATE} -eq 5 ]]; then
        oneName="${ONE_PX}-sys-${VM_ID}-rawcheckpoint"
        vmVolumes+="${oneName} "
        vmDisksMap+="${oneName}: "
        vmDisksTypeMap+="${oneName}:CHKPNT "
    fi
    if boolTrue "DEBUG_oneVmVolumes"; then
        local _DBGMSG=""
        _DBGMSG="[oneVmVolumes] VM_ID:${VM_ID} STATE:${VM_STATE} VM_DS_ID:${VM_DS_ID}"
        _DBGMSG+=" vmDisks:${vmDisks} ${VMSNAPSHOT_LIMIT:+ VMSNAPSHOT_LIMIT:${VMSNAPSHOT_LIMIT}}"
        _DBGMSG+="${DISKSNAPSHOT_LIMIT:+ DISKSNAPSHOT_LIMIT:${DISKSNAPSHOT_LIMIT}}"
        _DBGMSG+="${T_OS_NVRAM:+ T_OS_NVRAM=${T_OS_NVRAM}}${VM_SP_QOSCLASS:+ VM_SP_QOSCLASS=${VM_SP_QOSCLASS}}"
        _DBGMSG+="${VC_POLICY:+ VC_POLICY=${VC_POLICY}}"
        _DBGMSG+="${VMSNAPSHOT_WITH_CHECKPOINT:+ VMSNAPSHOT_WITH_CHECKPOINT=${VMSNAPSHOT_WITH_CHECKPOINT}}"
        _DBGMSG+="${BACKUP_VOLATILE:+ BACKUP_VOLATILE=${BACKUP_VOLATILE}}"
        _DBGMSG+="${BACKUP_FS_FREEZE:+ BACKUP_FS_FREEZE=${BACKUP_FS_FREEZE}}"
        _DBGMSG+="${BACKUP_MODE:+ BACKUP_MODE=${BACKUP_MODE}}"
        _DBGMSG+="${TPM_MODEL:+ TPM_MODEL=${TPM_MODEL}}"
        _DBGMSG+="${oneVmVolumesNotStorPool:+ oneVmVolumesNotStorPool=${oneVmVolumesNotStorPool}}"
        splog "[D]${_DBGMSG}"
    fi
    if boolTrue "DDDEBUG_oneVmVolumes"; then
        splog "[DDD][oneVmVolumes] VM_ID:${VM_ID} VM_DS_ID:${VM_DS_ID}"
        splog "[DDD][oneVmVolumes] vmVolumes:'${vmVolumes}'"
        splog "[DDD][oneVmVolumes] vmDisksMap:'${vmDisksMap}'"
        splog "[DDD][oneVmVolumes] vmDisksQcMap:'${vmDisksQcMap}'"
        splog "[DDD][oneVmVolumes] vmDisksDsMap:'${vmDisksDsMap}'"
        splog "[DDD][oneVmVolumes] vmDisksTypeMap:'${vmDisksTypeMap}'"
        splog "[DDD][oneVmVolumes] vmDisksReadOnlyMap:'${vmDisksReadOnlyMap}'"
        splog "[DDD][oneVmVolumes] persistentDisksQcMap:'${persistentDisksQcMap}'"
        if [[ ${#SNAPSHOT_ID_A[*]} -gt 0 ]]; then
            splog "[DDD][oneVmVolumes] SNAPSHOT_ID_A:'${SNAPSHOT_ID_A[*]}'"
        fi
        if [[ -n "${oneVmVolumesShareable}" ]]; then
            splog "[DDD][oneVmVolumes] oneVmVolumesShareable:'${oneVmVolumesShareable}'"
        fi
    fi
    if boolTrue "DDEBUG_oneVmVolumes"; then
        splog "[DD][oneVmVolumes] VM_ID:${VM_ID} DISKS_QC:'${!DISKS_QC_A[*]}'='${DISKS_QC_A[*]}' SP_QOSCLASS_LINE:'${SP_QOSCLASS_LINE}'"
    fi
}

function oneVmDiskSnapshots()
{
    local VM_ID="$1" DISK_ID="$2"
    local _tmpXML="" _errmsg="" _XPATH="" _ret=1 _element="" xfh=""

    if boolTrue "DDEBUG_oneVmDiskSnapshots"; then
        splog "[DD][oneVmDiskSnapshots] VM ${VM_ID} DISK_ID=${DISK_ID}"
    fi

    _tmpXML="${TMPDIR:-/tmp}/oneVmDiskSnapshots-${VM_ID}-${DISK_ID}.xml"

    oneCallXml onevm show "${VM_ID}" "${_tmpXML}"
    _ret=$?
    if [[ ${_ret} -ne 0 ]]; then
        _errmsg="[E][oneVmDiskSnapshots] Error: Can't get info for ${VM_ID}! $(head -n 1 "${_tmpXML}") (ret:${_ret})"
        log_error "${_errmsg}"
        splog "${_errmsg}"
        exit "${_ret}"
    fi

    _XPATH="$(lookup_file "datastore/xpath.rb" || true)"
    declare -a _XPATH_A _XPATH_QUERY
    _XPATH_A=("${_XPATH}" "--stdin")
    _XPATH_QUERY=(
        "%m%/VM/SNAPSHOTS[DISK_ID=${DISK_ID}]/SNAPSHOT/ID"
    )

    unset i XPATH_ELEMENTS
    while IFS='' read -r -u "${xfh}" -d '' _element; do
        XPATH_ELEMENTS[i++]="${_element}"
    done {xfh}< <("${_XPATH_A[@]}" < "${_tmpXML}" "${_XPATH_QUERY[@]}" || true)
    exec {xfh}<&-
    rm -f "${_tmpXML}"

    unset i
    local _DISK_SNAPSHOTS="${XPATH_ELEMENTS[i++]}"
    read -g -r -a DISK_SNAPSHOTS_A <<< "${_DISK_SNAPSHOTS}"
    if boolTrue "DEBUG_oneVmDiskSnapshots"; then
        splog "[D][oneVmDiskSnapshots] VM ${VM_ID} DISK ${DISK_ID}, ${#DISK_SNAPSHOTS_A[*]} snapshots, SNAPSHOT_IDs:[${DISK_SNAPSHOTS_A[*]}]"
    fi
}

function oneVmSnapshots()
{
    local VM_ID="$1" snapshot_id="$2" disk_id="$3"
    local _tmpXML="" _errmsg="" _ret=1 _XPATH="" xfh=""

    if boolTrue "DDEBUG_oneVmSnapshots"; then
        splog "[DD][oneVmSnapshots] VM ${VM_ID} snapshot_id=${snapshot_id} disk_id=${disk_id}"
    fi

    if [[ -z "${VM_ID}" ]]; then
        splog "[E][oneVmSnapshots] No VM_ID(${VM_ID})! snapshot_id=${snapshot_id} disk_id=${disk_id}"
        return 1
    fi

    _tmpXML="${TMPDIR:-/tmp}/oneVmSnapshots-${VM_ID}-${snapshot_id}-${disk_id}.xml"

    oneCallXml onevm show "${VM_ID}" "${_tmpXML}"
    _ret=$?
    if [[ ${_ret} -ne 0 ]]; then
        _errmsg="[E][oneVmSnapshots] Error: Can't get info for ${VM_ID}! $(head -n 1 "${_tmpXML}") (ret:${_ret})"
        log_error "${_errmsg}"
        splog "${_errmsg}"
        exit "${_ret}"
    fi
    _XPATH="$(lookup_file "datastore/xpath.rb" || true)"
    declare -a _XPATH_A _XPATH_QUERY
    _XPATH_A=("${_XPATH}" "--stdin")
    _XPATH_QUERY=(
        "/VM/UID"
        "/VM/GID"
        "/VM/TEMPLATE/CONTEXT/DISK_ID"
    )
    if [[ -n "${snapshot_id}" ]]; then
        _XPATH_QUERY+=(
            "/VM/TEMPLATE/SNAPSHOT[SNAPSHOT_ID=${snapshot_id}]/SNAPSHOT_ID"
            "/VM/TEMPLATE/SNAPSHOT[SNAPSHOT_ID=${snapshot_id}]/HYPERVISOR_ID"
        )
    else
        _XPATH_QUERY+=(
            "%m%/VM/TEMPLATE/SNAPSHOT/SNAPSHOT_ID"
            "%m%/VM/TEMPLATE/SNAPSHOT/HYPERVISOR_ID"
        )
    fi
    if [[ -n "${disk_id}" ]]; then
        _XPATH_QUERY+=(
            "/VM/TEMPLATE/DISK[DISK_ID=${disk_id}]/DATASTORE_ID"
            "/VM/TEMPLATE/DISK[DISK_ID=${disk_id}]/DISK_TYPE"
            "/VM/TEMPLATE/DISK[DISK_ID=${disk_id}]/TYPE"
            "/VM/TEMPLATE/DISK[DISK_ID=${disk_id}]/SOURCE"
            "/VM/TEMPLATE/DISK[DISK_ID=${disk_id}]/CLONE"
            "/VM/TEMPLATE/DISK[DISK_ID=${disk_id}]/FORMAT"
        )
    fi
    unset i XPATH_ELEMENTS
    while IFS='' read -r -u "${xfh}" -d '' element; do
        XPATH_ELEMENTS[i++]="${element}"
    done {xfh}< <("${_XPATH_A[@]}" < "${_tmpXML}" "${_XPATH_QUERY[@]}" || true)
    exec {xfh}<&-
    rm -f "${_tmpXML}"

    unset i
    VM_UID="${XPATH_ELEMENTS[i++]}"
    VM_GID="${XPATH_ELEMENTS[i++]}"
    CONTEXT_DISK_ID="${XPATH_ELEMENTS[i++]}"
    local _SNAPSHOT_ID="${XPATH_ELEMENTS[i++]}"
    local _HYPERVISOR_ID="${XPATH_ELEMENTS[i++]}"
    read -g -r -a SNAPSHOT_IDS_A <<< "${_SNAPSHOT_ID}"
    read -g -r -a HYPERVISOR_IDS_A <<< "${_HYPERVISOR_ID}"
    if [[ -n "${disk_id}" ]]; then
        export DISK_A="${XPATH_ELEMENTS[i++]}"
        export DISK_B="${XPATH_ELEMENTS[i++]}"
        export DISK_C="${XPATH_ELEMENTS[i++]}"
        export DISK_D="${XPATH_ELEMENTS[i++]}"
        export DISK_E="${XPATH_ELEMENTS[i++]}"
        export DISK_F="${XPATH_ELEMENTS[i++]}"
    else
        unset DISK_A DISK_B DISK_C DISK_D DISK_E DISK_F
    fi
    if boolTrue "DEBUG_oneVmSnapshots"; then
        local _DBGMSG=""
        _DBGMSG="VM_ID:${VM_ID} (U:${VM_UID}/G:${VM_GID}) vmsnap=${snapshot_id} disk:${disk_id}"
        _DBGMSG+=" SNAPSHOT_IDs:${SNAPSHOT_IDS_A[*]} HYPERVISOR_IDs:${HYPERVISOR_IDS_A[*]}"
        _DBGMSG+=" ${CONTEXT_DISK_ID} A:${DISK_A} B:${DISK_B} C:${DISK_C} D:${DISK_D} E:${DISK_E} F:${DISK_F}"
        splog "[D][oneVmSnapshots] ${_DBGMSG}"
    fi
}

function oneSnapshotLookup()
{
    #VM:51-DISK:0-VMSNAP:0
    local _input="$1"
    local volumeName="" _entry=""
    declare -A _snap_a  # snap_a[KEY]=VALUE
    declare -a _arr_a  # arr_a[KEY]=VALUE
    read -r -a _arr_a <<< "${_input//-/ }"
    for _entry in "${_arr_a[@]}"; do
       _snap_a["${_entry%%:*}"]="${_entry#*:}"
    done
    if boolTrue "DEBUG_oneSnapshotLookup"; then
        splog "[D][oneSnapshotLookup] snap_a[${!_snap_a[*]}]=[${_snap_a[*]}]"
    fi
    # SPSNAPSHOT:<StorPool snashotName>
    if [[ -n "${_snap_a["SPSNAPSHOT"]}" ]]; then
        SNAPSHOT_NAME="${_input#*SPSNAPSHOT:}"
        if boolTrue "DEBUG_oneSnapshotLookup"; then
            splog "[D][oneSnapshotLookup] (${_input}): full SNAPSHOT_NAME:${SNAPSHOT_NAME}"
        fi
        return 0
    fi
    oneVmSnapshots "${_snap_a["VM"]}" "${_snap_a["VMSNAP"]}" "${_snap_a["DISK"]}"
    if [[ "${DISK_B^^}" == "BLOCK" ]] && [[ "${DISK_C^^}" == "BLOCK" ]]; then
        volumeName="${DISK_D#*/}"
        if [[ "${DISK_E^^}" == "YES" ]]; then
            volumeName+="-${_snap_a["VM"]}-${_snap_a["DISK"]}"
        fi
    elif [[ "${DISK_B^^}" == "FILE" ]] && [[ "${DISK_C^^}" == "FS" ]]; then
        volumeName="${ONE_PX}-sys-${_snap_a["VM"]}-${_snap_a["DISK"]}"
    elif [[ "${CONTEXT_DISK_ID}" == "${_snap_a["DISK"]}" ]]; then
        # ONE can't register image with size less than 1MB
        # but it is possible to have bigger contextualization
        volumeName="${ONE_PX}-sys-${_snap_a["VM"]}-${_snap_a["DISK"]}"
    fi
    if [[ -n "${volumeName}" ]] && [[ ${#HYPERVISOR_IDS_A[*]} -gt 0 ]]; then
        SNAPSHOT_NAME="${volumeName}-${HYPERVISOR_IDS_A[0]}"
        if boolTrue "DEBUG_oneSnapshotLookup"; then
            splog "[D][oneSnapshotLookup](${_input}): VM SNAPSHOT_NAME:${SNAPSHOT_NAME}"
        fi
        return 0
    fi
    return 1
}

function storpoolVmVolumes()
{
    local _vmTag="$1" _vmTagVal="$2" _locTag="${LOC_TAG:-nloc}"
    local _vol="" _loctagval="" xfh=""
    vmVolumes=
    vmVolumeIds=
    if DO_MULTICLUSTER=1 DO_ALLCLUSTERS=1 storpoolRetry VolumesList; then
        while read -r -u "${xfh}" name tag_img tag_vmsnaprevert loctagval; do
            [[ "${loctagval}" == "${LOC_TAG_VAL}" ]] || continue
            [[ -z "${tag_img%"${ONE_PX}"*}" ]] || continue
            [[ "${tag_vmsnaprevert}" == "null" ]] || continue
            [[ "${name:0:1}" == "~" ]] || continue
            vmVolumes+="${tag_img} "
            vmVolumeIds+="${name} "
        done {xfh}< <(jq -r --arg tag "${_vmTag}" --arg val "${_vmTagVal}" --arg loctag "${_locTag}" \
            '.data.clusters[].response.data[]|select(.tags[$tag]==$val)|"\(.name) \(.tags.img|tostring) \(.tags.vmsnaprevert|tostring) \(.tags[$loctag]|tostring)"' \
            "${TMPDIR}/VolumesList.json" || true)
        exec {xfh}<&-
    fi
    splog "storpoolVmVolumes(${_vmTag},${_vmTagVal}) ${vmVolumes} || ${vmVolumeIds} ($?)"
}

function forceDetachOther()
{
    local VM_ID="$1" DST_HOST="$2" VOLUME="$3"
    local _json="" volume_name=""
    local DO_MULTICLUSTER=1
    oneHostInfo "${DST_HOST}"
    local DO_REMOTE="~${HOST_SP_CLUSTER_ID:-${SP_CLUSTER_ID}}"
    if [[ -z "${HOST_SP_OURID}" ]]; then
        splog "Error: HOST_SP_OURID is empty!"
        return 1
    fi
    if [[ -n "${VOLUME}" ]]; then
        vmVolumes="${VOLUME}"
    else
        if boolTrue "FORCE_DETACH_BY_TAG"; then
            storpoolVmVolumes "${VM_TAG}" "${VM_ID}"
        else
            oneVmVolumes "${VM_ID}"
        fi
    fi
    if boolTrue "DEBUG_forceDetachOther"; then
        splog "forceDetachOther($1,$2${3:+,$3}) ${vmVolumes}"
    fi
    if [[ -z "${vmVolumes}" ]]; then
        splog "Error: vmVolumes list is empty!"
        return 1
    fi
    for volume_name in ${vmVolumes}; do
        kvGetUid "${volume_name}" fatal
        [[ -z "${_json}" ]] || _json+=","
        _json+="{\"volume\":\"${SP_UID}\",\"rw\":[${HOST_SP_OURID}],\"detach\":\"all\",\"force\":true}"
    done
    if [[ -n "${_json}" ]]; then
        storpoolRetry VolumesReassignWait "\"reassign\":[${_json}]"
    fi
}

# disable sp checkpoint transfer from file to block device
# when the new code is enabled
if boolTrue "SP_CHECKPOINT_BD"; then
    export SP_CHECKPOINT=""
fi

# backward compatibility
type -t multiline_exec_and_log >/dev/null || function multiline_exec_and_log(){ exec_and_log "$@"; }

if type -t ssh_forward >/dev/null; then
    if [[ -z "${SSH_AUTH_SOCK}" && -S /var/run/one/ssh-agent.sock ]]; then
        SSH_AUTH_SOCK="/var/run/one/ssh-agent.sock"
    fi
    export SSH_AUTH_SOCK

    if boolTrue "DEBUG_COMMON"; then
        splog "[D][ssh_forward] upstream SSH_AUTH_SOCK:${SSH_AUTH_SOCK}"
    fi
else
    if boolTrue "DEBUG_COMMON"; then
        splog "[D][ssh_forward] wrapper"
    fi
    function ssh_forward(){ "$@"; }
fi

function hostReachable()
{
    local _host="$1"
    ping -i 0.3 -c "${PING_COUNT:-2}" "${_host}" >/dev/null
}

function oneIsStandalone()
{
    if grep -q -i 'MODE=STANDALONE' "${ONE_HOME:-/var/lib/one}/config" &>/dev/null; then
        if boolTrue "DEBUG_oneIsStandalone"; then
            splog "[D][oneIsStandalone] YES"
        fi
        return 0
    else
        splog "oneIsStandalone: NO (fedarated?$(grep FEDERATION= "${ONE_HOME:-/var/lib/one}/config" || true))"
        return 1
    fi
}

function isRaftLeader()
{
    local _ret=1 _one_config="${ONE_HOME:-/var/lib/one}/config"
    local _tmp="" _raft_ip=""
    # try detecting RAFT_LEADER_IP from opennebula's config
    if [[ -z "${RAFT_LEADER_IP}" && -f "${_one_config}" ]]; then
        #RAFT_LEADER_HOOK=ARGUMENTS=leader vlan11 10.163.1.250,COMMAND=raft/vip.sh
        _raft_ip="$(awk '$0 ~ /^RAFT_LEADER_HOOK/{print $3}' "${_one_config}" | tail -n 1 || true)"
        if [[ -n "${_raft_ip}" ]]; then
            RAFT_LEADER_IP="${_raft_ip%%/*}"
            RAFT_LEADER_IP="${RAFT_LEADER_IP%%,*}"
        fi
    fi
    if [[ -n "${RAFT_LEADER_IP#disabled}" ]]; then
        _tmp="$(ip route get "${RAFT_LEADER_IP}" 2>/dev/null | head -n 1 || true)"
        if [[ "${_tmp:0:5}" == "local" ]]; then
            if boolTrue "DEBUG_isRaftLeader"; then
                splog "[D][isRaftLeader] Found leader IP (${RAFT_LEADER_IP})."
            fi
            _ret=0
        else
            if boolTrue "DEBUG_isRaftLeader"; then
                splog "[D][isRaftLeader] There is no leader IP found (${RAFT_LEADER_IP})."
            fi
        fi
    else
        if boolTrue "DDEBUG_isRaftLeader"; then
            splog "[DD][isRaftLeader] RAFT_LEADER_IP:${RAFT_LEADER_IP}"
        fi
        if oneIsStandalone; then
            _ret=0
        fi
    fi
    if boolTrue "DDEBUG_isRaftLeader"; then
        splog "[DD][isRaftLeader](${RAFT_LEADER_IP}): ${_ret}"
    fi
    return "${_ret}"
}

# redefine own version of ssh_make_path()
function ssh_make_path
{
    local _host="$1" _path="$2" _monitor="$3"
    local SSH_EXEC_ERR="" SSH_EXEC_RC=""
    [[ -z "${_monitor}" ]] || splog "ssh_make_path(${_host}, ${_path}, ${_monitor})"
    # shellcheck disable=SC2154
    SSH_EXEC_ERR=$(${SSH:-ssh} "${_host}" "bash -s 2>/tmp/rbash.err 1>/tmp/rbash.out" <<EOF
set -e -o pipefail
if [[ ! -d "${_path}" ]]; then
   mkdir -p "${_path}"
   logger -t "${0##*/}[$$]" -- "ssh_make_path_r: mkdir -p ${_path} (\$?)"
fi
if [[ -n "${_monitor}" ]]; then
   monitor_file="$(dirname "${_path}")/.monitor"
   if [[ -f "\${monitor_file}" ]]; then
       monitor_remote="\$(<"\${monitor_file}" 2>/dev/null)"
   fi
   if [[ "\${monitor_remote}" != "${_monitor}" ]]; then
       echo "${_monitor}" > "\${monitor_file}" 2>&1
       logger -t "${0##*/}[$$]" -- "ssh_make_path_r '${_monitor}' to \${monitor_file} (\$?)"
   fi
fi
EOF
)
    SSH_EXEC_RC=$?
    if [[ ${SSH_EXEC_RC} -ne 0 ]]; then
        splog "ssh_make_path(${_host}, ${_path}${_monitor:+, ${_monitor}}) (${SSH_EXEC_RC}) SSH_EXEC_ERR:'${SSH_EXEC_ERR}'"
        error_message "Error creating directory ${2:-} at ${1:-}: ${SSH_EXEC_ERR}"
        exit "${SSH_EXEC_RC}"
    fi
}

# Override the non-working upstream function
function remove_off_hosts {
    local hst="" state="" _RET=1 xfh=""
    declare -a LOOKUP_HOSTS_ARRAY
    read -r -a LOOKUP_HOSTS_ARRAY <<< "$1"
    unset HOSTS_ARRAY
    declare -A HOSTS_ARRAY
    for hst in "${LOOKUP_HOSTS_ARRAY[@]}"; do
        HOSTS_ARRAY["${hst//\./}"]="1"
    done
    while IFS=',' read -r -u "${xfh}" hst state; do
        [[ -n ${state} ]] || continue
        if [[ ${state} -lt 1 ]] || [[ ${state} -gt 2 ]]; then
            continue
        fi
        [[ -n "${HOSTS_ARRAY["${hst//\./}"]}" ]] || continue
        echo -ne "${hst} "
        _RET=0
    done {xfh}< <(oneCallXml onehost list | \
        xmlstarlet sel -t -m '//HOST' -v NAME -o ',' -v STATE -n 2>/dev/null \
        || true)
    exec {xfh}<&-
    if [[ ${_RET} -ne 0 ]]; then
        splog "remove_off_hosts($1) Error: Can't filter hosts!"
        echo "${LOOKUP_HOSTS_ARRAY[*]}"
    fi
    return "${_RET}"
}

function debug_sp_qosclass()
{
    local msg=""
    if boolTrue "DEBUG_SP_QOSCLASS"; then
        msg="${SP_QOSCLASS:+SP_QOSCLASS=${SP_QOSCLASS} >>} "
        msg+="${VM_DISK_SP_QOSCLASS:+VM_DISK_SP_QOSCLASS=${VM_DISK_SP_QOSCLASS} }"
        msg+="${IMAGE_SP_QOSCLASS:+IMAGE_SP_QOSCLASS=${IMAGE_SP_QOSCLASS} }"
        msg+="${VM_SP_QOSCLASS:+VM_SP_QOSCLASS=${VM_SP_QOSCLASS} }"
        msg+="${SYSTEM_DS_SP_QOSCLASS:+SYSTEM_DS_SP_QOSCLASS=${SYSTEM_DS_SP_QOSCLASS} }"
        msg+="${IMAGE_DS_SP_QOSCLASS:+IMAGE_DS_SP_QOSCLASS=${IMAGE_DS_SP_QOSCLASS} }"
        if [[ -z "${SYSTEM_DS_SP_QOSCLASS}${IMAGE_DS_SP_QOSCLASS}" ]]; then
            msg+="${DS_SP_QOSCLASS:+DS_SP_QOSCLASS=${DS_SP_QOSCLASS} }"
        fi
        msg+="${DEFAULT_QOSCLASS:+DEFAULT_QOSCLASS=${DEFAULT_QOSCLASS} }"
        splog "[D][debug_sp_qosclass] ${msg}"
    fi
}

function isImmutable()
{
    local CLONE="$1" SAVE="$2" READONLY="$3"
    local _IMMUTABLE="NO"
    if [[ "${CLONE}" == "NO" && "${SAVE}" == "NO" && "${READONLY}" == "YES" ]]; then
        # IMAGE/TEMPLATE/PERSISTENT_TYPE="IMMUTABLE"
        _IMMUTABLE="YES"
    fi
    echo "${_IMMUTABLE}"
}

function image_info()
{
    local _img="$1" _host="$2"
    local _tmpjson="${TMPDIR:-/tmp}/qemu-img-info-${_img##*/}.json" ret=1
    declare -a CMD
    unset QEMU_IMG_VIRTUAL_SIZE QEMU_IMG_ACTUAL_SIZE QEMU_IMG_FORMAT STAT_IMAGE_SIZE
    CMD=("${QEMU_IMG:-qemu-img}" info --output json "${_img}")
    if [[ -n "${_host}" ]]; then
        CMD=("${SSH:-ssh}" "${_host}" "${CMD[@]}")
    fi
    if [[ -f "${_img}" ]]; then
        STAT_IMAGE_SIZE=$(${STAT:-stat} --printf="%s" "${_img}" || true)
        "${CMD[@]}" > "${_tmpjson}" || true
        if [[ -s "${_tmpjson}" ]]; then
            IFS=";" read -r QEMU_IMG_VIRTUAL_SIZE QEMU_IMG_ACTUAL_SIZE QEMU_IMG_FORMAT <<< "$(jq -r '"\(."virtual-size"|tostring);\(."actual-size"|tostring);\(.format|tostring)"' "${_tmpjson}" || true)"
            ret=0
            splog "[I][qemu_img_info](${_img}${_host:+:,${_host}}): virtual-size:${QEMU_IMG_VIRTUAL_SIZE} actual-size:${QEMU_IMG_ACTUAL_SIZE} format:${QEMU_IMG_FORMAT} stat size:${STAT_IMAGE_SIZE}"
        else
            splog "[E][qemu_img_info](${_img}${_host:+:,${_host}}): Error: Can't get image info! (stat size:${STAT_IMAGE_SIZE})"
        fi
        rm -f "${_tmpjson}"
    fi
    return "${ret}"
}

function tpmSave()
{
    local _VM_ID="$1" _VM_PATH="$2" _RHOST="$3"
    local _SP_VOL="${ONE_PX}-sys-${_VM_ID}-SWTPM"
    local _SP_LINK="/dev/storpool/${_SP_VOL}"
    local _remote_cmd=""

    if boolTrue "DEBUG_tpm"; then
        splog "[D] VM ${_VM_ID} ${_VM_PATH} ${_RHOST}"
    fi
    if ! storpoolVolumeExists "${_SP_VOL}" byName; then
        if boolTrue "DEBUG_tpm"; then
            splog "[D] Creating StorPool volume ${_SP_VOL}"
        fi
        storpoolVolumeCreate "${_SP_VOL}" "4M"
    else
        if boolTrue "DEBUG_tpm"; then
            splog "[D] StorPool volume ${SP_UID} ${_SP_VOL} already exists"
        fi
    fi
    storpoolVolumeAttach "${SP_UID}" "${_RHOST}"
    _SP_LINK="/dev/storpool-byid/${SP_UID#*~}"
    _remote_cmd=$(cat <<EOF
    #
    if [[ -d "${_VM_PATH}/tpm" ]]; then
        splog "tar czf ${_SP_LINK} -C ${_VM_PATH} tpm"
        tar czf "${_SP_LINK}" -C "${_VM_PATH}" tpm
    else
        splog "VM ${_VM_ID} No tpm data to save"
    fi
EOF
)
    splog "VM ${_VM_ID} Saving TPM data to ${SP_UID} ${_SP_VOL} on host ${_RHOST}"
    ssh_exec_and_log "${_RHOST}" "${REMOTE_HDR}${_remote_cmd}${REMOTE_FTR}" \
                "Error saving TPM data to ${SP_UID} ${_SP_VOL} on host ${_RHOST}"

    storpoolVolumeDetach "${SP_UID}" "" "${_RHOST}" "all"

    storpoolVolumeTag "${SP_UID}" "virt;${LOC_TAG:-nloc};${VM_TAG:-nvm};${VC_POLICY:+vc-policy};${SP_QOSCLASS:+qc};type" "one;${LOC_TAG_VAL};${_VM_ID};${VC_POLICY};${SP_QOSCLASS};SWTPM"

    if boolTrue "DEBUG_tpm"; then
        splog "[D] VM ${_VM_ID} END"
    fi
}

function tpmRestore()
{
    local _VM_ID="$1" _VM_PATH="$2" _RHOST="$3"
    local _SP_VOL="${ONE_PX}-sys-${_VM_ID}-SWTPM" _remote_cmd=""
    local _SP_LINK="/dev/storpool/${_SP_VOL}"
    local _remote_cmd=""
    if boolTrue "DEBUG_tpm"; then
        splog "[D] VM ${_VM_ID} ${_VM_PATH} ${_RHOST} ${_SP_VOL}"
    fi
    if storpoolVolumeExists "${_SP_VOL}" byName; then
        if boolTrue "DEBUG_tpm"; then
            splog "[D] Attaching StorPool volume ${SP_UID} ${_SP_VOL} to host ${_RHOST}"
        fi
        storpoolVolumeAttach "${SP_UID}" "${_RHOST}"
        _SP_LINK="/dev/storpool-byid/${SP_UID#*~}"
        _remote_cmd=$(cat <<EOF
    #
    splog "tar xzf ${_SP_LINK} -C ${_VM_PATH}"
    tar xzf "${_SP_LINK}" -C "${_VM_PATH}"
EOF
)
        splog "VM ${_VM_ID} Restoring TPM data from ${SP_UID} ${_SP_VOL} on host ${_RHOST}"
        ssh_exec_and_log "${_RHOST}" "${REMOTE_HDR}${_remote_cmd}${REMOTE_FTR}" \
                    "Error restoring TPM data from ${SP_UID} ${_SP_VOL} on host ${_RHOST}"
        storpoolVolumeDetach "${SP_UID}" "" "${_RHOST}" "all"
    fi
    if boolTrue "DEBUG_tpm"; then
        splog "[D] VM ${_VM_ID} END"
    fi
}

function oneTpmBackup()
{
    local _VM_ID="$1" _VM_PATH="$2" _RHOST="$3" _B_DIR="$4"
    local _remote_cmd=""
    if boolTrue "DEBUG_tpm"; then
        splog "[D] VM ${_VM_ID} ${_VM_PATH} ${_RHOST}"
    fi

    _remote_cmd=$(cat <<EOF
    #
    source /var/tmp/one/etc/vmm/kvm/kvmrc
    XPATH_RB="/var/tmp/one/datastore/xpath.rb"
    domxml="\$(virsh --connect "\${LIBVIRT_URI:-qemu:///system}" dumpxml "one-${_VM_ID}")"
    if echo "\${domxml}" | "\${XPATH_RB}" -t '/domain/devices/tpm/backend[@type="emulator"]' > /dev/null 2>&1; then
        DOM_UUID="\$(echo "\${domxml}" | "\${XPATH_RB}" '/domain/uuid')"
        if sudo -l | grep -q vtpm_setup; then
            splog "VM ${_VM_ID} Backing up vTPM data to ${_VM_PATH} DOM_UUID=\${DOM_UUID}"
            sudo /var/tmp/one/vtpm_setup backup "\${DOM_UUID}" "${_VM_PATH}"
            if [[ -n "${_B_DIR}" ]]; then
                mkdir -p "${_B_DIR}"
                tar zcvf "${_B_DIR}/disk.tpm.0" -C "${_VM_PATH}" tpm
                splog "VM ${_VM_ID} vTPM data backed up to ${_B_DIR}/disk.tpm.0"
            fi
        else
            splog "VM ${_VM_ID} No sudo privileges to backup vTPM data to ${_VM_PATH} DOM_UUID=\${DOM_UUID}"
        fi
    fi
EOF
)
    splog "VM ${_VM_ID} ${_VM_PATH} ${_RHOST}"
    if boolTrue "DEBUG_tpm"; then
        splog "[D] VM ${_VM_ID} ${_RHOST} remote ..."
    fi
    ssh_exec_and_log "${_RHOST}" "${REMOTE_HDR}${_remote_cmd}${REMOTE_FTR}" \
                    "Error backing up vTPM data to ${_VM_PATH} on host ${_RHOST}"
    if boolTrue "DEBUG_tpm"; then
        splog "[D] VM ${_VM_ID} END ${_RHOST}:${_B_DIR}/disk.tpm.0"
    fi
}

if boolTrue "STORPOOL_COMMON_FUNC_EXEC" ; then
    declare -A DECLARED_FUNCTIONS
    while read -r -u "${xfh}" -a _array; do
        DECLARED_FUNCTIONS["${_array[2]}"]="${_array[2]}"
    done {xfh}< <(declare -F || true)
    exec {xfh}<&-

    if [[ -n "${DECLARED_FUNCTIONS["${0##*/}"]}" ]]; then
        "${0##*/}" "${@}"
    fi
fi
