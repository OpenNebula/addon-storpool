#!/bin/bash

# -------------------------------------------------------------------------- #
# Copyright 2015-2024, StorPool (storpool.com)                               #
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

# Manage StorPool templates from the DATASTORE variables (not recommended)
export AUTO_TEMPLATE=0
# Propagate the changes to the template to the volumes in the template
# Require AUTO_TEMPLATE=1
export SP_TEMPLATE_PROPAGATE=1

# enable the alternate VM Snapshot function to do atomic snapshots
export VMSNAPSHOT_OVERRIDE=1
# the common tag of the snapshots created by the alternate VM Snapshot interface
export VMSNAPSHOT_TAG="ONESNAP"
# (obsolete) used for the alternate VM snapshot interface before atomic snapshotting was implemented
export VMSNAPSHOT_FSFREEZE=0
# Delete VM snapshots when terminating a VM
export VMSNAPSHOT_DELETE_ON_TERMINATE=1
# block creating new VM Snapshots when the limit is reached
export VMSNAPSHOT_LIMIT=
# alter the SYSTEM snapshot behavior depending on the underlying file system
export SP_SYSTEM="ssh"
# update Disk size in OpenNebula when reverting a snapshot
export UPDATE_ONE_DISK_SIZE=1
# Do not enforce the datastore template on the StorPool volumes
export NO_VOLUME_TEMPLATE=""
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

ONE_PX="${ONE_PX:-one}"

DEFAULT_QOSCLASS=""

export ADDON_RELEASE="25.04.1"

declare -A SYSTEM_COMPATIBLE_DS
SYSTEM_COMPATIBLE_DS["ceph"]=1
export SYSTEM_COMPATIBLE_DS

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

DRIVER_PATH="$(dirname "$0")"
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

LOC_TAG="${LOC_TAG:-nloc}"
LOC_TAG_VAL="${LOC_TAG_VAL:-${ONE_PX}}"

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
        HOST_HOSTNAME="${XPATH_ELEMENTS[i++]}"
    fi
    boolTrue "DEBUG_oneHostInfo" || return 0
    local _dbgmsg="ID:${HOST_ID} NAME:${HOST_NAME} STATE:${HOST_STATE}(${HostState[${HOST_STATE}]})"
    _dbgmsg+=" HOSTNAME:${HOST_HOSTNAME}"
    _dbgmsg+="${HOST_SP_OURID:+ HOST_SP_OURID=${HOST_SP_OURID}}"
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
                    return 0
                else
                    splog "storpoolClientId${_method}(${_hst}${_common_domain:+,${_common_domain}}) CLIENT_OURID has incorrect format '${CLIENT_OURID}'"
                fi
            fi
        else
            splog "storpoolClientId(${_hst}${_common_domain:+,${_common_domain}}) unknown function storpoolGetId${_method}"
        fi
    done
    return 1
}

function storpoolApi()
{
    local _method="$1" _data="$2" _max_time="$3"
    local _apiCmd="" _ret=1
    if [[ -z "${SP_API_HTTP_HOST}" ]]; then
        if [[ -x "/usr/sbin/storpool_confget" ]]; then
            # shellcheck disable=SC2046
            eval $(/usr/sbin/storpool_confget -S || true)
        fi
        if [[ -z "${SP_API_HTTP_HOST}" ]]; then
            splog "storpoolApi: ERROR! SP_API_HTTP_HOST is not set!"
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
        splog "[DDD] $0 $1 $2 $3"
    fi

    if boolTrue "storpoolApiCmdline"; then
        # shellcheck disable=2016
        _apiCmd="curl -s -S -q -N -H 'Authorization: Storpool v1:${SP_AUTH_TOKEN}' \
        --connect-timeout '${SP_API_CONNECT_TIMEOUT:-1}' \
        --max-time '${_max_time:-300}' ${_data:+-d '${_data}'} \
        '${SP_API_HTTP_HOST}:${SP_API_HTTP_PORT:-81}/ctrl/1.0/${_method}'"
        echo "${_apiCmd}"
        _ret=0
    else
        curl -s -S -q -N -H "Authorization: Storpool v1:${SP_AUTH_TOKEN}" \
        --connect-timeout "${SP_API_CONNECT_TIMEOUT:-1}" \
        --max-time "${_max_time:-300}" ${_data:+-d "${_data}"} \
        "${SP_API_HTTP_HOST}:${SP_API_HTTP_PORT:-81}/ctrl/1.0/${_method}" 2>/dev/null
        _ret=$?
        if [[ ${_ret} -ne 0 ]]; then
            splog "${_method} ${_data}${_max_time:+ max-time:${_max_time}} ret:${_ret}"
        fi
    fi
    return "${_ret}"
}

function volumesGroupSnapshotJson()
{
    local _json="" _tags="" _tg="" _res=""
    while [[ ${1:0:4} = "tag:" ]]; do
        _tg="${1#tag:}"
        [[ -z "${_tags}" ]] || _tags+=","
        _tags+="\"${_tg%%=*}\":\"${_tg#*=}\""
        shift
    done
    while [[ -n "$2" ]]; do
        [[ -z "${_json}" ]] || _json+=","
        _json+="{\"volume\":\"$1\",\"name\":\"$2\"}"
        shift 2
    done
    if [[ -n "${_json}" ]]; then
        _res="{\"volumes\":[${_json}]${_tags:+,\"tags\":{${_tags}}}}"
        echo "${_res}"
    fi
}

function storpoolWrapper()
{
	local _json="" _res="" _ret=1
	case "$1" in
		groupSnapshot)
			shift
            local _tags="" _tg=""
            while [[ ${1:0:4} = "tag:" ]]; do
                _tg="${1#tag:}"
                [[ -z "${_tags}" ]] || _tags+=","
                _tags+="\"${_tg%%=*}\":\"${_tg#*=}\""
                shift
            done
			while [[ -n "$2" ]]; do
				[[ -z "${_json}" ]] || _json+=","
				_json+="{\"volume\":\"$1\",\"name\":\"$2\"}"
				shift 2
			done
			if [[ -n "${_json}" ]]; then
				_res="$(storpoolApi "VolumesGroupSnapshot" "{\"volumes\":[${_json}]${_tags:+,\"tags\":{${_tags}}}}")"
				_ret=$?
				if [[ ${_ret} -ne 0 ]]; then
					splog "API communication error:${_res} (${_ret})"
					return "${_ret}"
				else
					ok="$(echo "${_res}"|jq -r ".data|.ok" 2>&1)"
					if [[ "${ok}" == "true" ]]; then
						if boolTrue "DDEBUG_SP_RUN_CMD"; then
							splog "[DD] API response:${_res}"
						fi
					else
						splog "API Error:$(echo "${_res}" | tr '\n' ' ' || true) info:${ok}"
                        _ret=1
					fi
				fi
			else
				splog "storpoolWrapper: Error: Empty volume list!"
                _ret=1
			fi
            return "${_ret}"
			;;
		groupAttach)
			shift
			if [[ -n "$1" ]]; then
				_res="$(storpoolApi "VolumesReassignWait" "{\"attachTimeout\":${ATTACH_TIMEOUT},\"reassign\":[$1]}")"
				_ret=$?
				if [[ ${_ret} -ne 0 ]]; then
					splog "API communication error:${_res} (${_ret})"
					return "${_ret}"
				else
					ok="$(echo "${_res}"|jq -r ".data|.ok" 2>&1)"
					if [[ "${ok}" == "true" ]]; then
						if boolTrue "DDEBUG_SP_RUN_CMD"; then
							splog "[DD] API response:${_res}"
						fi
					else
						splog "API Error:$(echo "${_res}" | tr '\n' ' ' || true) info:${ok}"
                        _ret=1
					fi
				fi
			else
				splog "storpoolWrapper: Error: Empty json!"
                _ret=1
			fi
            return "${_ret}"
			;;
		groupDetach)
			shift
			if [[ -n "$1" ]]; then
				_res="$(storpoolApi "VolumesReassignWait" "{\"reassign\":[$1]}")"
				_ret=$?
				if [[ ${_ret} -ne 0 ]]; then
					splog "API communication error:${_res} (${_ret})"
					return "${_ret}"
				else
					ok="$(echo "${_res}"|jq -r ".data|.ok" 2>&1)"
					if [[ "${ok}" == "true" ]]; then
						if boolTrue "DDEBUG_SP_RUN_CMD"; then
							splog "[DD] API response:${_res}"
						fi
					else
						splog "API Error:$(echo "${_res}" | tr '\n' ' ' || true) info:${ok}"
                        _ret=1
					fi
				fi
			else
				splog "storpoolWrapper: Error: Empty volume list!"
                _ret=1
			fi
            return "${_ret}"
			;;
		*)
			storpool -B "$@"
			_ret=$?
			return "${_ret}"
			;;
	esac
}

function splogFile() {
    local _logfile="$1" _line="" logfh=""
    if boolTrue "DEBUG_splogFile"; then
        splog "[D][splogFile] $*"
    fi
    while read -r -u "${logfh}" _line; do
        splog "splogFile: ${_line}"
    done {logfh}< <(cat "${_logfile}" 2>&1 || true)
    exec {logfh}<&-
    [[ -z "${2:-}" ]] || rm -f "${_logfile}"
}

function storpoolRetry() {
    local t=${STORPOOL_RETRIES:-10}
    local errfile="" err=
    errfile="$(mktemp)"
    if boolTrue "DEBUG_SP_RUN_CMD"; then
        if boolTrue "DDEBUG_SP_RUN_CMD"; then
            splog "[DD] ${SP_API_HTTP_HOST:+${SP_API_HTTP_HOST}:}storpool $* #${errfile}"
        else
            for _last_cmd;do :;done
            if [[ "${_last_cmd}" != "list" ]]; then
                splog "[D] ${SP_API_HTTP_HOST:+${SP_API_HTTP_HOST}:}storpool $*"
            fi
        fi
    fi
    while true; do
        if storpoolWrapper "$@" 2>"${errfile}"; then
            if boolTrue "DEBUG_SP_RUN_CMD"; then
                splogFile "${errfile}" clean
            fi
            break
        fi
        err=$?
        if boolTrue "_SOFT_FAIL"; then
            splog "storpool $* SOFT_FAIL"
            splogFile "${errfile}" clean
            break
        fi
        t=$((t - 1))
        if [[ ${t} -lt 1 ]]; then
            splog "storpool $* FAILED (try:${t}, err:${err})"
            splogFile "${errfile}" clean
            exit 1
        fi
        splogFile "${errfile}"
        sleep .1
        splog "retry ${t} storpool $* (err:${err})"
    done
    if [[ -f "${errfile}" ]]; then
        rm -f "${errfile}"
    fi
}

function storpoolTemplate()
{
    local _SP_TEMPLATE="$1" _SP_PROPAGATE=
    if ! boolTrue "AUTO_TEMPLATE"; then
        return 0
    fi
    if [[ "${SP_PLACEALL}" == "" ]]; then
        splog "Datastore template ${_SP_TEMPLATE} missing 'SP_PLACEALL' attribute."
        exit 255
    fi
    if [[ "${SP_PLACETAIL}" == "" ]]; then
        splog "Datastore template ${_SP_TEMPLATE} missing 'SP_PLACETAIL' attribute. Using SP_PLACEALL"
        SP_PLACETAIL="${SP_PLACEALL}"
    fi
    if [[ -n "${SP_REPLICATION/[123]/}" || -n "${SP_REPLICATION/[[:digit:]]/}" ]]; then
        splog "Datastore template ${_SP_TEMPLATE} with unknown value for SP_REPLICATION attribute=${SP_REPLICATION}"
        exit 255
    fi
    if boolTrue "SP_TEMPLATE_PROPAGATE"; then
        _SP_PROPAGATE=1
	fi
    if [[ -n "${_SP_TEMPLATE}" && -n "${SP_REPLICATION}" && -n "${SP_PLACEALL}" && -n "${SP_PLACETAIL}" ]]; then
        storpoolRetry template "${_SP_TEMPLATE}" replication "${SP_REPLICATION}" \
		              placeAll "${SP_PLACEALL}" placeTail "${SP_PLACETAIL}" \
					  ${SP_PLACEHEAD:+ placeHead "${SP_PLACEHEAD}"} \
					  ${SP_IOPS:+iops "${SP_IOPS}"} ${SP_BW:+bw "${SP_BW}"} \
					  ${_SP_PROPAGATE:+propagate ${PROPAGATE_YES:+yes}} >/dev/null
    fi
}

function storpoolVolumeInfo()
{
    local _SP_VOL="$1" _retries="$2"
    local STORPOOL_RETRIES_OLD="${STORPOOL_RETRIES}" xfh=""
    [[ -z "${_retries}" ]] || STORPOOL_RETRIES="${_retries}"
    V_SIZE=
    V_PARENT_NAME=
    V_TEMPLATE_NAME=
    V_TYPE=
    while IFS=',' read -r -u "${xfh}" V_SIZE V_PARENT_NAME V_TEMPLATE_NAME V_TYPE; do
        V_PARENT_NAME="${V_PARENT_NAME//\"/}"
        V_TEMPLATE_NAME="${V_TEMPLATE_NAME//\"/}"
        V_TYPE="${V_TYPE//\"/}"
        break
    done {xfh}< <(storpoolRetry -j volume "${_SP_VOL}" info|jq -r ".data|[.size,.parentName,.templateName,.tags.type]|@csv" || true)
    exec {xfh}<&-
    export V_SIZE V_PARENT_NAME V_TEMPLATE_NAME V_TYPE
    if boolTrue "DEBUG_storpoolVolumeInfo"; then
        splog "[D] storpoolVolumeInfo(${_SP_VOL}) size:${V_SIZE} parentName:${V_PARENT_NAME} templateName:${V_TEMPLATE_NAME} tags.type:${V_TYPE}"
    fi
    STORPOOL_RETRIES="${STORPOOL_RETRIES_OLD}"
}

function storpoolVolumeExists()
{
    local _SP_VOL="$1" _RET=1
    if [[ -n "$(storpoolRetry -j volume list | jq -r ".data[]|select(.name == \"${_SP_VOL}\")" || true)" ]]; then
        _RET=0
    fi
    if boolTrue "DEBUG_storpoolVolumeExists"; then
        splog "[D] storpoolVolumeExists(${_SP_VOL}): ${_RET}"
    fi
    return "${_RET}"
}

function storpoolVolumeCheck()
{
    local _SP_VOL="$1" _errmsg=""
    if storpoolVolumeExists "${_SP_VOL}"; then
        _errmsg="Error: StorPool volume ${_SP_VOL} exists"
        splog "${_errmsg}"
        log_error "${_errmsg}"
        exit 1
    fi
}

function storpoolVolumeCreate()
{
    local _SP_VOL="$1" _SP_SIZE="$2" _SP_TEMPLATE="$3"
    storpoolRetry volume "${_SP_VOL}" size "${_SP_SIZE}" ${_SP_TEMPLATE:+template "${_SP_TEMPLATE}"} create >/dev/null
}

function storpoolVolumeStartswith()
{
    local _SP_VOL="$1" vName="" xfh=""
    while read -r -u "${xfh}" vName; do
        echo "${vName//\"/}"
    done {xfh}< <(storpoolRetry -j volume list | \
                  jq -r ".data|map(select(.name|startswith(\"${_SP_VOL}\")))|.[]|[.name]|@csv" || true)  # TBD use cache files
    exec {xfh}<&-
}

function storpoolVolumeSnapshotsDelete()
{
    local _SP_VOL_SNAPSHOTS="$1" xfh=""
    if boolTrue "DEBUG_storpoolVolumeSnapshotsDelete"; then
        splog "[D] storpoolVolumeSnapshotsDelete ${_SP_VOL_SNAPSHOTS}"
    fi
    while read -r -u "${xfh}" name; do
        name="${name//\"/}"
        [[ "${name:0:1}" == "*" ]] && continue
        storpoolSnapshotDelete "${name}"
    done {xfh}< <(storpoolRetry -j snapshot list | \
                jq -r --arg n "${_SP_VOL_SNAPSHOTS}" '.data|map(select(.name|contains($n)))|.[]|[.name]|@csv' || true)
    exec {xfh}<&-
}

function storpoolVolumeDelete()
{
    local _SP_VOL="$1" _FORCE="$2" _SNAPSHOTS="$3" _REMOTE_LOCATION="$4"
    local _ret=0 _msg="" _newName="" _REMOTE_LOCATION_ARGS=""
    if storpoolVolumeExists "${_SP_VOL}"; then
        if boolTrue "DEBUG_storpoolVolumeDelete"; then
            splog "[D] storpoolVolumeDelete(${_SP_VOL},${_FORCE},${_SNAPSHOTS},${_REMOTE_LOCATION})"
        fi

        storpoolVolumeDetach "${_SP_VOL}" "${_FORCE}" "" "all"
        _ret=$?

        if [[ -n "${_REMOTE_LOCATION}" ]]; then
			_REMOTE_LOCATION_ARGS="${_REMOTE_LOCATION#*:}"
			_REMOTE_LOCATION="${_REMOTE_LOCATION%:*}"
            # shellcheck disable=SC2086
			storpoolRetry volume "${_SP_VOL}" backup "${_REMOTE_LOCATION}" ${_REMOTE_LOCATION_ARGS} >/dev/null
			_ret=$?
			if [[ ${_ret} -ne 0 ]]; then
				storpoolVolumeRename "${_SP_VOL}" "${_SP_VOL}-$(date +%s||true)" "tag del=y" >/dev/null
				return $?
			fi
		fi
        if [[ -n "${DELAY_DELETE}" ]]; then
            local DELAY_DELETE_tmp="${DELAY_DELETE//[[:digit:]]/}"
            if [[ -n "${DELAY_DELETE_tmp}" ]] && [[ -z "${DELAY_DELETE_tmp/[smhd]/}" ]]; then
                storpoolRetry volume "${_SP_VOL}" snapshot deleteAfter "${DELAY_DELETE}" >/dev/null
                _ret=$?
                if [[ ${_ret} -eq 0 ]]; then
                    storpoolRetry volume "${_SP_VOL}" delete "${_SP_VOL}" >/dev/null
                    _ret=$?
                else
                   splog "Can't create anonymous snapshot for ${_SP_VOL}!"
                fi
            else
                _msg="Unsupported format in DELAY_DELETE='${DELAY_DELETE}'!"
                _newName="${_SP_VOL}_DELETE$(date +%s)"
                storpoolRetry volume "${_SP_VOL}" rename "${_newName}" update >/dev/null
                _ret=$?
                if [[ ${_ret} -ne 0 ]]; then
                    storpoolRetry volume "${_newName}" freeze >/dev/null
                    _ret=$?
                    if [[ ${_ret} -eq 0 ]]; then
                        _msg+=" ${_SP_VOL} converted to snapshot ${_newName}"
                    else
                        _msg+=" Unable to convert ${_SP_VOL} as snapshot ${_newName}"
                    fi
                else
                    _msg+=" Unable to rename ${_SP_VOL} to ${_newName}."
                fi
                splog "${_msg}"
            fi
        else
            storpoolRetry volume "${_SP_VOL}" delete "${_SP_VOL}" >/dev/null
            _ret=$?
        fi
    else
        splog "storpoolVolumeDelete: volume ${_SP_VOL} not found"
    fi
    if [[ ${_ret} -eq 0 ]]; then
        if [[ "${_SNAPSHOTS:0:5}" == "snaps" ]]; then
            storpoolVolumeSnapshotsDelete "${_SP_VOL}-snap"
        fi
    else
        splog "Volume snapshots not deleted due to registered error (${_ret})!"
    fi
    return "${_ret}"
}

function storpoolVolumeRename()
{
    local _SP_OLD="$1" _SP_NEW="$2" _SP_TEMPLATE="$3" _SP_TAG="$4"
    # shellcheck disable=SC2086
    storpoolRetry volume "${_SP_OLD}" rename "${_SP_NEW}" ${_SP_TEMPLATE:+template "${_SP_TEMPLATE}"} ${_SP_TAG} update >/dev/null
}

function storpoolVolumeClone()
{
    local _SP_PARENT="$1" _SP_VOL="$2" _SP_TEMPLATE="$3"

    storpoolRetry volume "${_SP_VOL}" baseOn "${_SP_PARENT}" ${_SP_TEMPLATE:+template "${_SP_TEMPLATE}"} create >/dev/null
}

function storpoolVolumeResize()
{
    local _SP_VOL="$1" _SP_SIZE="$2" _SP_SHRINKOK="$3"

    storpoolRetry volume "${_SP_VOL}" size "${_SP_SIZE}"${_SP_SHRINKOK:+ shrinkOk} update >/dev/null
}

function storpoolVolumeAttach()
{
    local _SP_VOL="$1" _SP_HOST="$2" _SP_MODE="${3:-rw}" _SP_TARGET="${4:-volume}"
    local _SP_CLIENT
    if [[ -n "${_SP_HOST}" ]]; then
        _SP_CLIENT="$(storpoolClientId "${_SP_HOST}" "${COMMON_DOMAIN}")"
        if [[ -n "${_SP_CLIENT}" ]]; then
           _SP_CLIENT="client ${_SP_CLIENT}"
        else
            splog "Error: Can't get remote CLIENT_ID from ${_SP_HOST}"
            exit 255
        fi
    fi
    storpoolRetry attach "${_SP_TARGET}" "${_SP_VOL}" ${_SP_MODE:+mode "${_SP_MODE}"} "${_SP_CLIENT:-here}" timeout "${ATTACH_TIMEOUT}" >/dev/null
}

function storpoolVolumeJsonHelper()
{
    local _SP_VOL="$1" _SP_CLIENT="$2" _SP_MODE="${3:-rw}" _FORCE="$4" _SOFT_FAIL="$5"
    if [[ -z "${_SP_CLIENT}" ]]; then
        splog "Error: Unknown CLIENT_ID"
        exit 1
    fi
    if boolTrue "_SOFT_FAIL"; then
        _FORCE=
    fi
    if boolTrue "DEBUG_storpoolVolumeJsonHelper"; then
        splog "[D] storpoolVolumeJsonHelper(${_SP_VOL},${_SP_CLIENT},${_SP_MODE},${_FORCE})"
    fi
    echo "{\"volume\":\"${_SP_VOL}\",\"${_SP_MODE}\":[\"${_SP_CLIENT}\"]${_FORCE:+,\"force\":true}}"
}

function storpoolVolumeDetach()
{
    local _SP_VOL="$1" _FORCE="$2" _SP_HOST="$3" _DETACH_ALL="$4" _SOFT_FAIL="$5" _VOLUMES_GROUP="$6"
    local _SP_CLIENT="" volume="" client="" xfh=""
    if boolTrue "DEBUG_storpoolVolumeDetach"; then
        splog "[D] storpoolVolumeDetach(_SP_VOL=$1 _FORCE=$2 _SP_HOST=$3 _DETACH_ALL=$4 _SOFT_FAIL=$5 _VOLUMES_GROUP=$6)"
    fi
    if [[ "${_DETACH_ALL}" == "all" ]] && [[ -z "${_VOLUMES_GROUP}" ]]; then
        _SP_CLIENT="all"
    else
        if [[ -n "${_SP_HOST}" ]]; then
            _SP_CLIENT="$(storpoolClientId "${_SP_HOST}" "${COMMON_DOMAIN}")"
            if [[ "${_SP_CLIENT}" == "" ]]; then
                splog "Error: Can't get SP_OURID for host ${_SP_HOST}"
                exit 255
            fi
        fi
    fi
    if [[ -n "${_VOLUMES_GROUP}" ]] && [[ -n "${_SP_CLIENT}" ]]; then
        local _JSON=
        for volume in ${_VOLUMES_GROUP}; do
            [[ -z "${_JSON}" ]] || _JSON+=","
            _JSON+="$(storpoolVolumeJsonHelper "${volume}" "${_SP_CLIENT}" "detach" "force")"
        done
        storpoolRetry groupDetach "${_JSON}"
        splog "detachGroup '${_JSON}' ($?)"
    fi
    if [[ "${_DETACH_ALL}" == "all" ]]; then
        _SP_CLIENT="all"
    fi
    while IFS=',' read -r -u "${xfh}" volume client snapshot; do
        if boolTrue "_SOFT_FAIL" "_SOFT_FAIL"; then
            _FORCE=
        fi
        if [[ "${snapshot}" == "true" ]]; then
            type="snapshot"
        else
            type="volume"
        fi
        volume="${volume//\"/}"
        client="${client//\"/}"
        case "${_SP_CLIENT}" in
            all)
                storpoolRetry detach "${type}" "${volume}" all ${_FORCE:+force yes} >/dev/null
                break
                ;;
             '')
                storpoolRetry detach "${type}" "${volume}" here ${_FORCE:+force yes} >/dev/null
                break
                ;;
              *)
                if [[ "${_SP_CLIENT}" == "${client}" ]]; then
                    storpoolRetry detach "${type}" "${volume}" client "${client}" ${_FORCE:+force yes} >/dev/null
                fi
                ;;
        esac
    done {xfh}< <(storpoolRetry -j attach list|jq -r ".data|map(select(.volume==\"${_SP_VOL}\"))|.[]|[.volume,.client,.snapshot]|@csv"||true)
    exec {xfh}<&-
}

function storpoolVolumeTemplate()
{
    local _SP_VOL="$1" _SP_TEMPLATE="$2"
    if [[ -z "${_SP_VOL}" ]]; then
        splog "[E]storpoolVolumeTemplate($*): volume is empty"
        exit 1
    fi
    if [[ -z "${_SP_TEMPLATE}" ]]; then
        splog "[E]storpoolVolumeTemplate($*): template is empty"
        exit 1
    fi
    storpoolRetry volume "${_SP_VOL}" template "${_SP_TEMPLATE}" update >/dev/null
}

function storpoolSnapshotInfo()
{
    local _SP_SNAPSHOT="$1"
    read -r -a SNAPSHOT_INFO <<< "$(storpoolRetry -j snapshot "${_SP_SNAPSHOT}" info | jq -r '.data|[.size,.templateName]|@csv' | tr ',"' ' '  || true)"
    if boolTrue "DEBUG_storpoolSnapshotInfo"; then
        splog "[D] storpoolSnapshotInfo(${_SP_SNAPSHOT}):${SNAPSHOT_INFO[*]}"
    fi
}

function storpoolSnapshotCreate()
{
    local _SP_SNAPSHOT="$1" _SP_VOL="$2"

    storpoolRetry volume "${_SP_VOL}" snapshot "${_SP_SNAPSHOT}" >/dev/null
}

function storpoolSnapshotDelete()
{
    local _SP_SNAPSHOT="$1"

    storpoolRetry snapshot "${_SP_SNAPSHOT}" delete "${_SP_SNAPSHOT}" >/dev/null
}

function storpoolSnapshotClone()
{
    local _SP_SNAP="$1" _SP_VOL="$2" _SP_TEMPLATE="$3"

    storpoolRetry volume "${_SP_VOL}" parent "${_SP_SNAP}" ${_SP_TEMPLATE:+template "${_SP_TEMPLATE}"} create >/dev/null
}

function storpoolSnapshotRevert()
{
    local _SP_SNAPSHOT="$1" _SP_VOL="$2" _SP_TEMPLATE="$3"
    local _SP_TMP="" _SP_VOL_TMP=""
    _SP_TMP="$(date +%s||true)-$(mktemp --dry-run XXXXXXXX||true)"
    _SP_VOL_TMP="${_SP_VOL}-${_SP_TMP}"

    storpoolRetry volume "${_SP_VOL}" rename "${_SP_VOL_TMP}" update >/dev/null

    trapAdd "storpool volume \"${_SP_VOL_TMP}\" rename \"${_SP_VOL}\""

    storpoolSnapshotClone "${_SP_SNAPSHOT}" "${_SP_VOL}" "${_SP_TEMPLATE}"

    trapReset

    storpoolVolumeDelete "${_SP_VOL_TMP}"
}

function storpoolVolumeTag()
{
    local _SP_VOL="$1" _TAG_KEY="${2:-${VM_TAG:-nvm}}" _TAG_VAL="$3"
    local _tagCmd="" _tagKey=""
    declare -a _tagVal_array _tagKey_array
    IFS=';' read -r -a _tagVal_array <<< "${_TAG_VAL}"
    IFS=';' read -r -a _tagKey_array <<< "${_TAG_KEY}"
    if boolTrue "DEBUG_storpoolVolumeTag"; then
        splog "[D] storpoolVolumeTag(${_SP_VOL},${_TAG_VAL},${_TAG_KEY})"
    fi
    for i in "${!_tagKey_array[@]}"; do
        _tagKey="${_tagKey_array[i]//[[:space:]]/}"
        [[ -n "${_tagKey}" ]] || continue
        _tagCmd+="tag ${_tagKey}=${_tagVal_array[i]//[[:space:]]/} "
    done
    if [[ -n "${_tagCmd}" ]]; then
        storpoolRetry volume "${_SP_VOL}" "${_tagCmd}" update >/dev/null
    fi
}

function storpoolSnapshotTag()
{
    local _SP_SNAP="$1" _TAG_KEY="${2:-${VM_TAG:-nvm}}" _TAG_VAL="$3"
    local _tagCmd="" _tagKey=""
    declare -a _tagVal_array _tagKey_array
    IFS=';' read -r -a _tagVal_array <<< "${_TAG_VAL}"
    IFS=';' read -r -a _tagKey_array <<< "${_TAG_KEY}"
    for i in "${!_tagKey_array[@]}"; do
        _tagKey="${_tagKey_array[i]//[[:space:]]/}"
        [[ -n "${_tagKey}" ]] || continue
        _tagCmd+="tag ${_tagKey}=${_tagVal_array[i]//[[:space:]]/} "
    done
    if [[ -n "${_tagCmd}" ]]; then
        storpoolRetry snapshot "${_SP_SNAP}" "${_tagCmd}" >/dev/null
    fi
}

function oneSymlink()
{
    local _host="$1" _src="$2"
    shift 2
    local _dst="$*" _remote_cmd=""
    splog "${VM_ID:+VM ${VM_ID} }symlink ${_src} -> ${_host}:{${_dst//[[:space:]]/,}}${MONITOR_TM_MAD:+ (.monitor=${MONITOR_TM_MAD})}"
    _remote_cmd=$(cat <<EOF
    #_SYMLINK
    for dst in ${_dst}; do
        dst_dir=\$(dirname "\${dst}")
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
    local _host="${1%%:*}"
    local _path="${1#*:}"
    local _vmid="" _dsid="" _checkpoint="" _template="" _volume="" _sp_link=""
    local _DELAY_DELETE="${DELAY_DELETE}" _SP_COMPRESSION="${SP_COMPRESSION:-lz4}"
    local _remote_cmd="" _file_size=0 _volume_size=0
    _vmid="$(basename "${_path}")"
    _dsid="$(basename "$(dirname "${_path}")")"
    _checkpoint="${_path}/checkpoint"
    _template="${ONE_PX:-one}-ds-${_dsid}"
    _volume="${ONE_PX:-one}-sys-${_vmid}-checkpoint"
    _sp_link="/dev/storpool/${_volume}"
    _file_size=$(${SSH:-ssh} "${_host}" "du -b \"${_checkpoint}\" | cut -f 1" || true)
    if [[ -n "${_file_size}" ]]; then
        _volume_size=$(( ((_file_size *2 +511) /512) *512 ))
        _volume_size=$(( _volume_size/1024/1024 ))
    else
        splog "Checkpoint file not found! ${_checkpoint}"
        return 0
    fi
    splog "checkpoint_size=${_file_size} volume_size=${_volume_size}M"

    DELAY_DELETE=
    if storpoolVolumeExists "${_volume}"; then
        storpoolVolumeDelete "${_volume}" "force"
    fi

    storpoolVolumeCreate "${_volume}" "${_volume_size}M" "${_template}"

    trapAdd "storpoolVolumeDelete \"${_volume}\" \"force\""

    storpoolVolumeAttach "${_volume}" "${_host}"

    _remote_cmd=$(cat <<EOF
    # checkpoint Save
    if [[ -f "${_checkpoint}" ]]; then
        if tar --no-seek --use-compress-program="${_SP_COMPRESSION}" \
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
    splog "Saving ${_checkpoint} to ${_volume}"
    ssh_exec_and_log "${_host}" "${REMOTE_HDR}${_remote_cmd}${REMOTE_FTR}" \
                 "Error in checkpoint save of VM ${_vmid} on host ${_host}"

    trapReset
    DELAY_DELETE="${_DELAY_DELETE}"

    storpoolVolumeDetach "${_volume}" "" "${_host}" "all"
}

function oneCheckpointRestore()
{
    local _host="${1%%:*}"
    local _path="${1#*:}"
    local _vmid="" _checkpoint="" _volume="" _sp_link=""
    local _remote_cmd="" _SP_COMPRESSION="${SP_COMPRESSION:-lz4}"
    _vmid="$(basename "${_path}")"
    _checkpoint="${_path}/checkpoint"
    _volume="${ONE_PX:-one}-sys-${_vmid}-checkpoint"
    _sp_link="/dev/storpool/${_volume}"

    _remote_cmd=$(cat <<EOF
    # checkpoint Restore
    if [[ -f "${_checkpoint}" ]]; then
        splog "file exists ${_checkpoint}"
    else
        mkdir -p "${_path}"

        if [[ -n "$2" ]]; then
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
    if storpoolVolumeExists "${_volume}"; then
        storpoolVolumeAttach "${_volume}" "${_host}"

        trapAdd "storpoolVolumeDetach \"${_volume}\" \"force\" \"${_host}\" \"all\""

        splog "Restoring ${_checkpoint} from ${_volume}"
        ssh_exec_and_log "${_host}" "${REMOTE_HDR}${_remote_cmd}${REMOTE_FTR}" \
                 "Error in checkpoint restore of VM ${_vmid} on host ${_host}"

        trapReset

        storpoolVolumeDelete "${_volume}" "force"
    else
        splog "Checkpoint volume ${_volume} not found"
    fi
}

function oneBackupImageInfo()
{
    local _image_id="$1"
    local _XPATH="" _element="" i=0 xfh=""
    local _tmpXML="${TMPDIR:-/tmp}/oneimage-${_image_id}.XML"

    oneCallXml oneimage show "${_image_id}" "${_tmpXML}"

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
    if boolTrue "DEBUG_oneTemplateInfo"; then
        _DBGMSG="VM_ID=${VM_ID} VM_STATE=${VM_STATE}(${VmState[${VM_STATE}]})"
        _DBGMSG+=" VM_LCM_STATE=${VM_LCM_STATE}(${LcmState[${VM_LCM_STATE}]})"
        _DBGMSG+=" VM_PREV_STATE=${VM_PREV_STATE}(${VmState[${VM_PREV_STATE}]})"
        _DBGMSG+=" CONTEXT_DISK_ID=${CONTEXT_DISK_ID}"
        _DBGMSG+=" VC_POLICY=${VC_POLICY}"
        _DBGMSG+=" VM_SP_QOSCLASS=${VM_SP_QOSCLASS}"
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
                    oneName="${ONE_PX}-sys-${VM_ID}-${DISK_ID}-swap"
                    ;;
                *)
                    oneName="${ONE_PX}-sys-${VM_ID}-${DISK_ID}-${FORMAT:-raw}"
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
        oneName="${ONE_PX}-sys-${VM_ID}-${DISK_ID}-iso"
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
        volumeName="${ONE_PX}-sys-${_snap_a["VM"]}-${_snap_a["DISK"]}-raw"
    elif [[ "${CONTEXT_DISK_ID}" == "${_snap_a["DISK"]}" ]]; then
        # ONE can't register image with size less than 1MB
        # but it is possible to have bigger contextualization
        volumeName="${ONE_PX}-sys-${_snap_a["VM"]}-${_snap_a["DISK"]}-iso"
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
    while read -r -u "${xfh}" _vol _loctagval; do
        [[ "${_loctagval}" == "${LOC_TAG_VAL}" ]] || continue
        [[ -n "${_vol%"${ONE_PX:-one}"*}" ]] || continue
        vmVolumes+="${_vol} "
    done {xfh}< <(storpoolRetry -j volume list |\
        jq -r --arg vmtag "${_vmTag}" --arg vmtagval "${_vmTagVal}" --arg loctag "${_locTag}" \
            '.data[]|select(.tags[$vmtag]==$vmtagval)|"\(.name) \(.tags[$loctag])"' || true)  # TBD: rework to use cache file...
    exec {xfh}<&-
    splog "storpoolVmVolumes(${_vmTag},${_vmTagVal}) ${vmVolumes}"
}

function forceDetachOther()
{
    local VM_ID="$1" DST_HOST="$2" VOLUME="$3"
    local SP_CLIENT="" xfh=""
    SP_CLIENT="$(storpoolClientId "${DST_HOST}" "${COMMON_DOMAIN}")"
    if [[ -z "${SP_CLIENT}" ]]; then
        splog "Error: SP_CLIENT is empty!"
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
    if [[ -z "${vmVolumes}" ]]; then
        splog "forceDetachOther(${VM_ID},${DST_HOST}${VOLUME:+,${VOLUME}}): vmVolumes is empty!"
        return 1
    fi
    local jqStr="" _client="" _volume=""
    for _volume in ${vmVolumes}; do
        [[ -z "${jqStr}" ]] || jqStr+=" or "
        jqStr+=".volume==\"${_volume}\""
    done
    if boolTrue "DEBUG_forceDetachOther"; then
        splog "[D][forceDetachOther](${VM_ID},${DST_HOST}${VOLUME:+,${VOLUME}}) ${vmVolumes}"
    fi
    while read -r -u "${xfh}" _client _volume; do
        if boolTrue "DDEBUG_forceDetachOther"; then
            splog "[DD][forceDetachOther]($*) DST=${SP_CLIENT} ${_client} ${_volume}"
        fi
        if [[ "${_client}" -ne "${SP_CLIENT}" ]]; then
            storpoolRetry detach volume "${_volume}" client "${_client}" force yes >/dev/null
        fi
    done {xfh}< <(storpoolRetry -j attach list |\
        jq -r ".data[]|select(${jqStr})|(.client|tostring) + \" \" + .volume" || true)  # TBD: rework to use cache file...
    exec {xfh}<&-
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
