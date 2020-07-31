# -------------------------------------------------------------------------- #
# Copyright 2015-2020, StorPool (storpool.com)                               #
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
PATH="/bin:/sbin:/usr/bin:/usr/sbin:$PATH"

#-------------------------------------------------------------------------------
# syslog logger function
#-------------------------------------------------------------------------------

function splog()
{
    logger -t "${LOG_PREFIX:-tm}_sp_${0##*/}[$$]" "$(date +%s.%N) ${DEBUG_LINENO:+[${BASH_LINENO[-2]}]}$*"
}

#-------------------------------------------------------------------------------
# Set up the environment to source common tools
#-------------------------------------------------------------------------------

if [ -n "${ONE_LOCATION}" ]; then
    PATH="$PATH:$ONE_LOCATION"
    TMCOMMON="$ONE_LOCATION/var/remotes/tm/tm_common.sh"
else
    TMCOMMON=/var/lib/one/remotes/tm/tm_common.sh
fi

for f in "$TMCOMMON" /var/tmp/one/tm/tm_common.sh; do
    if [ -f "$f" ]; then
        source "$TMCOMMON"
        break
    fi
done

#-------------------------------------------------------------------------------
# load local configuration parameters
#-------------------------------------------------------------------------------

DEBUG_COMMON=
DEBUG_TRAPS=
DEBUG_SP_RUN_CMD=1
DDEBUG_SP_RUN_CMD=
DEBUG_oneVmInfo=
DEBUG_oneDatastoreInfo=
DEBUG_oneTemplateInfo=
DEBUG_oneDsDriverAction=

# Manage StorPool templates from the DATASTORE variables (not recommended)
AUTO_TEMPLATE=0
# Propagate the changes to the template to the volumes in the template
# Require AUTO_TEMPLATE=1
SP_TEMPLATE_PROPAGATE=1

# enable the alternate VM Snapshot function to do atomic snapshots
VMSNAPSHOT_OVERRIDE=1
# the common tag of the snapshots created by the alternate VM Snapshot interface
VMSNAPSHOT_TAG="ONESNAP"
# (obsolete) used for the alternate VM snapshot interface before atomic snapshotting was implemented
VMSNAPSHOT_FSFREEZE=0
# Delete VM snapshots when terminating a VM
VMSNAPSHOT_DELETE_ON_TERMINATE=1
# block creating new VM Snapshots when the limit is reached
VMSNAPSHOT_LIMIT=
# alter the SYSTEM snapshot behavior depending on the underlying file system
SP_SYSTEM="ssh"
# update Disk size in OpenNebula when reverting a snapshot
UPDATE_ONE_DISK_SIZE=1
# Do not enforce the datastore template on the StorPool volumes
NO_VOLUME_TEMPLATE=
# save the VM's checkpoint file directly to a block device, require qemu-kvm-ev
SP_CHECKPOINT_BD=0
# clasify the import process to a given cgroup(s)
SP_IMPORT_CGROUPS=
# override datastore bridge list for datastore/export script
EXPORT_BRIDGE_LIST=
# do no copy th eVM home back to sunstone on undeploy
SKIP_UNDEPLOY_SSH=0
# cleanup the VM home on undeploy
CLEAN_SRC_ON_UNDEPLOY=1
# block creation of new disk snapshots when the limit is reached
DISKSNAPSHOT_LIMIT=
# update image template's variables DRIVER=raw and FORMAT=raw during import
UPDATE_IMAGE_ON_IMPORT=1
# Tag all VM disks with tag $VM_TAG=$VM_ID
# Empty string will disable the tagging
VM_TAG=nvm
# common opennebula tools args
ONE_ARGS=
#
PROPAGATE_YES=1
#
FORCE_DETACH_BY_TAG=1
#
FORCE_DETACH_OTHER_MV=1
#
FORCE_DETACH_OTHER_CONTEXT=1

declare -A SYSTEM_COMPATIBLE_DS
SYSTEM_COMPATIBLE_DS["ceph"]=1

function lookup_file()
{
    local _FILE="$1" _CWD="${2:-$PWD}"
    local _PATH=
    for _PATH in "$_CWD/"{,../,../../,../../../,remotes/}; do
        if [ -f "${_PATH}${_FILE}" ]; then
#            splog "lookup_file($_FILE,$_CWD) FOUND:${_PATH}${_FILE}"
            echo "${_PATH}${_FILE}"
            return
#        else
#            splog "lookup_file($_FILE,$_CWD) NOT FOUND:${_PATH}${_FILE}"
        fi
    done
}

ONE_PX="${ONE_PX:-one}"

DRIVER_PATH="$(dirname $0)"
sprcfile="$(lookup_file "addon-storpoolrc" "$DRIVER_PATH")"

if [ -f "$sprcfile" ]; then
    source "$sprcfile"
else
    splog "File '$sprcfile' NOT FOUND!"
fi

if [ -f "/etc/storpool/addon-storpool.conf" ]; then
    source "/etc/storpool/addon-storpool.conf"
fi

ADDON_RELEASE="20.07.0"

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
        PROLOG_MIGRATE_UNKNOWN_FAILURE DISK_RESIZE DISK_RESIZE_POWEROFF DISK_RESIZE_UNDEPLOYED)

function boolTrue()
{
   case "${!1^^}" in
       1|Y|YES|TRUE|ON)
           return 0
           ;;
       *)
           return 1
   esac
}

function getFromConf()
{
    local cfgFile="$1" varName="$2" first="$3"
    local response
    if [ -n "$first" ]; then
        response="$(grep "^$varName" "$cfgFile" | head -n 1)"
    else
        response="$(grep "^$varName" "$cfgFile" | tail -n 1)"
    fi
    response="${response#*=}"
    if boolTrue "DEBUG_COMMON"; then
        splog "getFromConf($cfgFile,$varName,$first): $response"
    fi
    echo "${response//\"/}"
}

#-------------------------------------------------------------------------------
# trap handling functions
#-------------------------------------------------------------------------------
function trapReset()
{
    TRAP_CMD="-"
    if boolTrue "DEBUG_TRAPS"; then
        splog "trapReset"
    fi

    trap "$TRAP_CMD" TERM INT QUIT HUP EXIT
}
function trapAdd()
{
    local _trap_cmd="$1"
    if boolTrue "DEBUG_TRAPS"; then
        splog "trapAdd:$*"
    fi

    [ -n "$TRAP_CMD" ] || TRAP_CMD="-"

    if [ "$TRAP_CMD" = "-" ]; then
        TRAP_CMD="${_trap_cmd};"
    else
        if [ "$_trap_cmd" = "APPEND" ]; then
            _trap_cmd="$2"
            TRAP_CMD="${_trap_cmd};${TRAP_CMD}"
        else
            TRAP_CMD="${TRAP_CMD}${_trap_cmd};"
        fi
    fi

#    splog "trapAdd:$TRAP_CMD"
    trap "$TRAP_CMD" TERM INT QUIT HUP EXIT
}
function trapDel()
{
    local _trap_cmd="$1"
    if boolTrue "DEBUG_TRAPS"; then
        splog "trapDel:$*"
    fi
    TRAP_CMD="${TRAP_CMD/${_trap_cmd};/}"
    if [ -n "$TRAP_CMD" ]; then
        if boolTrue "DEBUG_TRAPS"; then
            splog "trapDel:$TRAP_CMD"
        fi
        trap "$TRAP_CMD" TERM INT QUIT HUP EXIT
    else
        trapReset
    fi
}

REMOTE_HDR=$(cat <<EOF
    #_REMOTE_HDR
    set -e
    export PATH=/bin:/usr/bin:/sbin:/usr/sbin:\$PATH
    splog(){ logger -t "${LOG_PREFIX:-tm}_sp_${0##*/}_r" "\$*"; }
EOF
)
REMOTE_FTR=$(cat <<EOF
    #_END
    splog "END \$endmsg"
EOF
)

function oneHostInfo()
{
    local _name="$1"
    local _self="$(dirname $0)"
    local _XPATH="$(lookup_file "datastore/xpath.rb" "$_self")"

    local tmpXML="$(mktemp -t oneHostInfo-${_name}-XXXXXX)"
    local ret=$? errmsg=
    if [ $ret -ne 0 ]; then
        errmsg="(oneHostInfo) Error: Can't create temp file! (ret:$ret)"
        log_error "$errmsg"
        splog "$errmsg"
        exit $ret
    fi
    onehost show $ONE_ARGS -x "$_name" >"$tmpXML"
    ret=$?
    if [ $ret -ne 0 ]; then
        errmsg="(oneHostInfo) Error: Can't get info! $(head -n 1 "$tmpXML") (ret:$ret)"
        log_error "$errmsg"
        splog "$errmsg"
        exit $ret
    fi

    unset XPATH_ELEMENTS i
    while IFS= read -r -d '' element; do
        XPATH_ELEMENTS[i++]="$element"
    done < <(cat "$tmpXML" | sed '/\/>$/d' | "$_XPATH" --stdin \
                            /HOST/ID \
                            /HOST/NAME \
                            /HOST/STATE \
                            /HOST/TEMPLATE/SP_OURID \
                            /HOST/TEMPLATE/HOSTNAME 2>/dev/null)
    rm -f "$tmpXML"
    unset i
    HOST_ID="${XPATH_ELEMENTS[i++]}"
    HOST_NAME="${XPATH_ELEMENTS[i++]}"
    HOST_STATE="${XPATH_ELEMENTS[i++]}"
    HOST_SP_OURID="${XPATH_ELEMENTS[i++]}"
    HOST_HOSTNAME="${XPATH_ELEMENTS[i++]}"

    boolTrue "DEBUG_oneHostInfo" || return 0
    splog "oneHostInfo($_name): ID:$HOST_ID NAME:$HOST_NAME STATE:$HOST_STATE HOSTNAME:${HOST_HOSTNAME}${HOST_SP_OURID:+ HOST_SP_OURID=$HOST_SP_OURID}"
}

function storpoolGetId()
{
    local hst="$1"
    if [ "$result" = "" ]; then
        result=$(/usr/sbin/storpool_confget -s "$hst" | grep SP_OURID | cut -d '=' -f 2 | tail -n 1)
        if [ "$result" = "" ]; then
            if [ -n "$COMMON_DOMAIN" ]; then
                result=$(/usr/sbin/storpool_confget -s "${hst}.${COMMON_DOMAIN}" | grep SP_OURID | cut -d '=' -f 2 | tail -n 1)
                if [ -n "$result" ] && boolTrue "DEBUG_SP_OURID"; then
                    splog "storpoolGetId(${hst}.${COMMON_DOMAIN}) SP_OURID=$result"
                fi
            fi
        elif boolTrue "DEBUG_SP_OURID"; then
            splog "storpoolGetId($hst) SP_OURID=$result (local storpool.conf)"
        fi
    fi
    if [ "$result" = "" ]; then
        for bridge in $BRIDGE_LIST; do
            result=$(ssh "$bridge" /usr/sbin/storpool_confget -s "$hst" | grep SP_OURID | cut -d '=' -f 2 | tail -n 1)
            if [ -n "$result" ]; then
                if boolTrue "DEBUG_SP_OURID"; then
                    splog "storpoolGetId($hst) SP_OURID=$result via $bridge"
                fi
                break
            fi
            if [ -n "$COMMON_DOMAIN" ]; then
                result=$(ssh "$bridge" /usr/sbin/storpool_confget -s "${hst}.${COMMON_DOMAIN}" | grep SP_OURID | cut -d '=' -f 2 | tail -n 1)
                if [ -n "$result" ]; then
                    if boolTrue "DEBUG_SP_OURID"; then
                        splog "storpoolGetId(${hst}.${COMMON_DOMAIN}) SP_OURID=$result via $bridge"
                    fi
                    break
                fi
            fi
        done
        if [ "$result" = "" ] && [ -n "$CLONE_GW" ]; then
            result=$(ssh "$CLONE_GW" /usr/sbin/storpool_confget -s "\$(hostname)" | grep SP_OURID | cut -d '=' -f 2 | tail -n 1) #"
            splog "storpoolGetId($CLONE_GW) SP_OURID=$result (CLONE_GW)"
        fi
        if [ "$result" = "" ]; then
            result=$(ssh "$hst" /usr/sbin/storpool_confget | grep SP_OURID | cut -d '=' -f 2 | tail -n 1)
            if [ -n "$result" ]; then
                if boolTrue "DEBUG_SP_OURID"; then
                    splog "storpoolGetId($hst) SP_OURID=$result (remote storpool.conf)"
                fi
            fi
        fi
    fi
}

function storpoolClientId()
{
    local hst="$1" COMMON_DOMAIN="${2:-$COMMON_DOMAIN}"
    local result= bridge=
    storpoolGetId "$hst"
    if [ "$result" = "" ]; then
        oneHostInfo "$hst"
        if [ -n "$HOST_HOSTNAME" ]; then
            if [ "$hst" != "$HOST_HOSTNAME" ] || boolTrue "DEBUG_COMMON"; then
                splog "storpoolClientId($hst): Found '$HOST_HOSTNAME'"
            fi
            hst="$HOST_HOSTNAME"
        fi
        if [ -n "$HOST_SP_OURID" ]; then
            if [ "${HOST_SP_OURID//[[:digit:]]/}" = "" ]; then
                result="$HOST_SP_OURID"
                splog "$hst CLIENT_ID=$result"
            else
                splog "HOST $hst has HOST_SP_OURID but not only digits:'$HOST_SP_OURID'"
            fi
        fi
        storpoolGetId "$hst"
    fi
    if boolTrue "DEBUG_SP_OURID"; then
        splog "storpoolClientId($1): SP_OURID:${result}${bridge:+ BRIDGE_HOST:$bridge}${COMMON_DOMAIN:+ COMMON_DOMAIN=$COMMON_DOMAIN}${HOST_HOSTNAME:+ HOST_HOSTNAME=$HOST_HOSTNAME}${HOST_SP_OURID:+ HOST_SP_OURID=$HOST_SP_OURID}"
    fi
    echo $result
}

function storpoolApi()
{
    if [ -z "$SP_API_HTTP_HOST" ]; then
        if [ -x /usr/sbin/storpool_confget ]; then
            eval `/usr/sbin/storpool_confget -S`
        fi
        if [ -z "$SP_API_HTTP_HOST" ]; then
            splog "storpoolApi: ERROR! SP_API_HTTP_HOST is not set!"
            return 1
        fi
    fi
    if boolTrue "NO_PROXY_API";then
        export NO_PROXY="${NO_PROXY:+${NO_PROXY},}$SP_API_HTTP_HOST"
    fi
    if boolTrue "DDEBUG_SP_RUN_CMD"; then
        splog "SP_API_HTTP_HOST=$SP_API_HTTP_HOST SP_API_HTTP_PORT=$SP_API_HTTP_PORT SP_AUTH_TOKEN=${SP_AUTH_TOKEN:+available} ${NO_PROXY:+NO_PROXY=${NO_PROXY}}"
    fi
    curl -s -S -q -N -H "Authorization: Storpool v1:$SP_AUTH_TOKEN" \
    --connect-timeout "${SP_API_CONNECT_TIMEOUT:-1}" \
    --max-time "${3:-300}" ${2:+-d "$2"} \
    "$SP_API_HTTP_HOST:${SP_API_HTTP_PORT:-81}/ctrl/1.0/$1" 2>/dev/null
    splog "storpoolApi $1 $2 ret:$?"
}

function storpoolWrapper()
{
	local json= res= ret=
	case "$1" in
		groupSnapshot)
			shift
            tags=
            while [ ${1:0:4} = "tag:" ]; do
                tg="${1#tag:}"
                [ -z "$tags" ] || tags+=","
                tags+="\"${tg%%=*}\":\"${tg#*=}\""
                shift
            done
			while [ -n "$2" ]; do
				[ -z "$json" ] || json+=","
				json+="{\"volume\":\"$1\",\"name\":\"$2\"}"
				shift 2
			done
			if [ -n "$json" ]; then
				res="$(storpoolApi "VolumesGroupSnapshot" "{\"volumes\":[$json]${tags:+,\"tags\":{$tags}}}")"
				ret=$?
				if [ $ret -ne 0 ]; then
					splog "API communication error:$res ($ret)"
					return $ret
				else
					ok="$(echo "$res"|jq -r ".data|.ok" 2>&1)"
					if [ "$ok" = "true" ]; then
						if boolTrue "DDEBUG_SP_RUN_CMD"; then
							splog "API response:$res"
						fi
					else
						splog "API Error:$res info:$ok"
						return 1
					fi
				fi
			else
				splog "storpoolWrapper: Error: Empty volume list!"
				return 1
			fi
			;;
		groupAttach)
			shift
			if [ -n "$1" ]; then
				res="$(storpoolApi "VolumesReassignWait" "{\"reassign\":[$1]}")"
				ret=$?
				if [ $ret -ne 0 ]; then
					splog "API communication error:$res ($ret)"
					return $ret
				else
					ok="$(echo "$res"|jq -r ".data|.ok" 2>&1)"
					if [ "$ok" = "true" ]; then
						if boolTrue "DDEBUG_SP_RUN_CMD"; then
							splog "API response:$res"
						fi
					else
						splog "API Error:$res info:$ok"
						return 1
					fi
				fi
			else
				splog "storpoolWrapper: Error: Empty json!"
				return 1
			fi
			;;
		groupDetach)
			shift
			if [ -n "$1" ]; then
				res="$(storpoolApi "VolumesReassignWait" "{\"reassign\":[$1]}")"
				ret=$?
				if [ $ret -ne 0 ]; then
					splog "API communication error:$res ($ret)"
					return $ret
				else
					ok="$(echo "$res"|jq -r ".data|.ok" 2>&1)"
					if [ "$ok" = "true" ]; then
						if boolTrue "DDEBUG_SP_RUN_CMD"; then
							splog "API response:$res"
						fi
					else
						splog "API Error:$res info:$ok"
						return 1
					fi
				fi
			else
				splog "storpoolWrapper: Error: Empty volume list!"
				return 1
			fi
			;;
		*)
			storpool -B "$@"
			;;
	esac
}

function storpoolRetry() {
    if boolTrue "DEBUG_SP_RUN_CMD"; then
        if boolTrue "DDEBUG_SP_RUN_CMD"; then
            splog "${SP_API_HTTP_HOST:+$SP_API_HTTP_HOST:}storpool $*"
        else
            for _last_cmd;do :;done
            if [ "${_last_cmd}" != "list" ]; then
                splog "${SP_API_HTTP_HOST:+$SP_API_HTTP_HOST:}storpool $*"
            fi
        fi
    fi
    t=${STORPOOL_RETRIES:-10}
    while true; do
        if storpoolWrapper "$@"; then
            break
        fi
        if boolTrue "_SOFT_FAIL"; then
            splog "storpool $* SOFT_FAIL"
            break
        fi
        t=$((t - 1))
        if [ "$t" -lt 1 ]; then
            splog "storpool $* FAILED ($t::$?)"
            exit 1
        fi
        sleep .1
        splog "retry $t storpool $*"
    done
}

function storpoolTemplate()
{
    local _SP_TEMPLATE="$1" _SP_PROPAGATE=
    if ! boolTrue "AUTO_TEMPLATE"; then
        return 0
    fi
    if [ "$SP_PLACEALL" = "" ]; then
        splog "Datastore template $_SP_TEMPLATE missing 'SP_PLACEALL' attribute."
        exit -1
    fi
    if [ "$SP_PLACETAIL" = "" ]; then
        splog "Datastore template $_SP_TEMPLATE missing 'SP_PLACETAIL' attribute. Using SP_PLACEALL"
        SP_PLACETAIL="$SP_PLACEALL"
    fi
    if [ -n "${SP_REPLICATION/[123]/}" ] || [ -n "${SP_REPLICATION/[[:digit:]]/}" ]; then
        splog "Datastore template $_SP_TEMPLATE with unknown value for SP_REPLICATION attribute=${SP_REPLICATION}"
        exit -1
    fi
    if boolTrue "SP_TEMPLATE_PROPAGATE"; then
        _SP_PROPAGATE=1
	fi
    if [ -n "$_SP_TEMPLATE" ] && [ -n "$SP_REPLICATION" ] && [ -n "$SP_PLACEALL" ] && [ -n "$SP_PLACETAIL" ]; then
        storpoolRetry template "$_SP_TEMPLATE" replication "$SP_REPLICATION" \
		              placeAll "$SP_PLACEALL" placeTail "$SP_PLACETAIL" \
					  ${SP_PLACEHEAD:+ placeHead $SP_PLACEHEAD} \
					  ${SP_IOPS:+iops "$SP_IOPS"} ${SP_BW:+bw "$SP_BW"} \
					  ${_SP_PROPAGATE:+propagate ${PROPAGATE_YES:+yes}} >/dev/null
    fi
}

function storpoolVolumeInfo()
{
    local _SP_VOL="$1"
    STORPOOL_RETRIES_OLD="$STORPOOL_RETRIES"
    [ -z "$2" ] || STORPOOL_RETRIES="$2"
    V_SIZE=
    V_PARENT_NAME=
    V_TEMPLATE_NAME=
    V_TYPE=
    while IFS=, read -u 5 V_SIZE V_PARENT_NAME V_TEMPLATE_NAME V_TYPE; do
        V_PARENT_NAME="${V_PARENT_NAME//\"/}"
        V_TEMPLATE_NAME="${V_TEMPLATE_NAME//\"/}"
        V_TYPE="${V_TYPE//\"/}"
        break
    done 5< <(storpoolRetry -j volume "$_SP_VOL" info|jq -r ".data|[.size,.parentName,.templateName,.tags.type]|@csv")
    if boolTrue "DEBUG_storpoolVolumeInfo"; then
        splog "storpoolVolumeInfo($_SP_VOL) size:$V_SIZE parentName:$V_PARENT_NAME templateName:$V_TEMPLATE_NAME tags.type:$V_TYPE"
    fi
    STORPOOL_RETRIES="$STORPOOL_RETRIES_OLD"
}

function storpoolVolumeExists()
{
    local _SP_VOL="$1" _RET=1
    if [ -n "$(storpoolRetry -j volume list | jq -r ".data[]|select(.name == \"$_SP_VOL\")")" ]; then #"
        _RET=0
    fi
    #splog "storpoolVolumeExists($_SP_VOL): $_RET"
    return ${_RET}
}

storpoolVolumeCheck()
{
    local SP_VOL="$1"
    if storpoolVolumeExists "$SP_VOL"; then
        errmsg="Error: StorPool volume $SP_VOL exists"
        splog "$errmsg"
        log_error "$errmsg"
        exit 1
    fi
}

function storpoolVolumeCreate()
{
    local _SP_VOL="$1" _SP_SIZE="$2" _SP_TEMPLATE="$3"
    storpoolRetry volume "$_SP_VOL" size "${_SP_SIZE}" ${_SP_TEMPLATE:+template "$_SP_TEMPLATE"} >/dev/null
}

function storpoolVolumeStartswith()
{
    local _SP_VOL="$1" vName
    while read vName; do
        echo "${vName//\"/}"
    done < <(storpoolRetry -j volume list | jq -r ".data|map(select(.name|startswith(\"${_SP_VOL}\")))|.[]|[.name]|@csv")
}

function storpoolVolumeSnapshotsDelete()
{
    local _SP_VOL_SNAPSHOTS="$1"
    if boolTrue "DEBUG_storpoolVolumeSnapshotsDelete"; then
        splog "storpoolVolumeSnapshotsDelete $_SP_VOL_SNAPSHOTS"
    fi
    storpoolRetry -j snapshot list | \
        jq -r --arg n "$_SP_VOL_SNAPSHOTS" '.data|map(select(.name|contains($n)))|.[]|[.name]|@csv' | \
        while read name; do
            name="${name//\"/}"
            storpoolSnapshotDelete "$name"
        done
}

function storpoolVolumeDelete()
{
    local _SP_VOL="$1" _FORCE="$2" _SNAPSHOTS="$3" _REMOTE_LOCATION="$4"
    if storpoolVolumeExists "$_SP_VOL"; then

        storpoolVolumeDetach "$_SP_VOL" "$_FORCE" "" "all"

        if [ -n "${_REMOTE_LOCATION}" ]; then
			local _REMOTE_LOCATION_ARGS="${_REMOTE_LOCATION#*:}"
			_REMOTE_LOCATION="${_REMOTE_LOCATION%:*}"
			storpoolRetry volume "$_SP_VOL" backup "$_REMOTE_LOCATION" ${_REMOTE_LOCATION_ARGS} >/dev/null
			local RET=$?
			if [ $RET -ne 0 ]; then
				storpoolVolumeRename "${_SP_VOL}" "${_SP_VOL}-"$(date +%s) "tag del=y" >/dev/null
				return $?
			fi
		fi
		storpoolRetry volume "$_SP_VOL" delete "$_SP_VOL" >/dev/null
    else
        splog "volume $_SP_VOL not found "
    fi
    if [ "${_SNAPSHOTS:0:5}" = "snaps" ]; then
        storpoolVolumeSnapshotsDelete "${_SP_VOL}-snap"
    fi
}

function storpoolVolumeRename()
{
    local _SP_OLD="$1" _SP_NEW="$2" _SP_TEMPLATE="$3" _SP_TAG="$4"
    storpoolRetry volume "$_SP_OLD" rename "$_SP_NEW" ${_SP_TEMPLATE:+template "$_SP_TEMPLATE"} >/dev/null
}

function storpoolVolumeClone()
{
    local _SP_PARENT="$1" _SP_VOL="$2" _SP_TEMPLATE="$3"

    storpoolRetry volume "$_SP_VOL" baseOn "$_SP_PARENT" ${_SP_TEMPLATE:+template "$_SP_TEMPLATE"} >/dev/null
}

function storpoolVolumeResize()
{
    local _SP_VOL="$1" _SP_SIZE="$2" _SP_SHRINKOK="$3"

    storpoolRetry volume "$_SP_VOL" size "${_SP_SIZE}"${_SP_SHRINKOK:+ shrinkOk} >/dev/null
}

function storpoolVolumeAttach()
{
    local _SP_VOL="$1" _SP_HOST="$2" _SP_MODE="${3:-rw}" _SP_TARGET="${4:-volume}"
    local _SP_CLIENT
    if [ -n "$_SP_HOST" ]; then
        _SP_CLIENT="$(storpoolClientId "$_SP_HOST" "$COMMON_DOMAIN")"
        if [ -n "$_SP_CLIENT" ]; then
           _SP_CLIENT="client $_SP_CLIENT"
        else
            splog "Error: Can't get remote CLIENT_ID from $_SP_HOST"
            exit -1
        fi
    fi
    storpoolRetry attach ${_SP_TARGET} "$_SP_VOL" ${_SP_MODE:+mode "$_SP_MODE"} ${_SP_CLIENT:-here} >/dev/null
}

function storpoolVolumeJsonHelper()
{
    local _SP_VOL="$1" _SP_CLIENT="$2" _SP_MODE="${3:-rw}" _FORCE="$4" _SOFT_FAIL="$5"
    if [ -z "$_SP_CLIENT" ]; then
        splog "Error: Unknown CLIENT_ID"
        exit 1
    fi
    if boolTrue "_SOFT_FAIL"; then
        _FORCE=
    fi
    echo "{\"volume\":\"$_SP_VOL\",\"$_SP_MODE\":[\"$_SP_CLIENT\"]${_FORCE:+,\"force\":true}}"
}

function storpoolVolumeDetach()
{
    local _SP_VOL="$1" _FORCE="$2" _SP_HOST="$3" _DETACH_ALL="$4" _SOFT_FAIL="$5" _VOLUMES_GROUP="$6"
    local _SP_CLIENT volume client
    if boolTrue "DEBUG_storpoolVolumeDetach"; then
        splog "storpoolVolumeDetach(_SP_VOL=$1 _FORCE=$2 _SP_HOST=$3 _DETACH_ALL=$4 _SOFT_FAIL=$5 _VOLUMES_GROUP=$6)"
    fi
    if [ "$_DETACH_ALL" = "all" ] && [ -z "$_VOLUMES_GROUP" ] ; then
        _SP_CLIENT="all"
    else
        if [ -n "$_SP_HOST" ]; then
            _SP_CLIENT="$(storpoolClientId "$_SP_HOST" "$COMMON_DOMAIN")"
            if [ "$_SP_CLIENT" = "" ]; then
                splog "Error: Can't get SP_OURID for host $_SP_HOST"
                exit -1
            fi
        fi
    fi
    if [ -n "$_VOLUMES_GROUP" ] && [ -n "$_SP_CLIENT" ]; then
        local _JSON=
        for volume in $_VOLUMES_GROUP; do
            [ -z "$_JSON" ] || _JSON+=","
            _JSON+="$(storpoolVolumeJsonHelper "$volume" "$_SP_CLIENT" "detach" "force")"
        done
        storpoolRetry groupDetach "${_JSON}"
        splog "detachGroup '$_JSON' ($?)"
    fi
    if [ "$_DETACH_ALL" = "all" ]; then
        _SP_CLIENT="all"
    fi
    while IFS=',' read volume client snapshot; do
        if boolTrue "_SOFT_FAIL" "_SOFT_FAIL"; then
            _FORCE=
        fi
        if [ $snapshot = "true" ]; then
            type="snapshot"
        else
            type="volume"
        fi
        volume="${volume//\"/}"
        client="${client//\"/}"
        case "$_SP_CLIENT" in
            all)
                storpoolRetry detach $type "$volume" all ${_FORCE:+force yes} >/dev/null
                break
                ;;
             '')
                storpoolRetry detach $type "$volume" here ${_FORCE:+force yes} >/dev/null
                break
                ;;
              *)
                if [ "$_SP_CLIENT" = "$client" ]; then
                    storpoolRetry detach $type "$volume" client "$client" ${_FORCE:+force yes} >/dev/null
                fi
                ;;
        esac
    done < <(storpoolRetry -j attach list|jq -r ".data|map(select(.volume==\"${_SP_VOL}\"))|.[]|[.volume,.client,.snapshot]|@csv")
}

function storpoolVolumeTemplate()
{
    local _SP_VOL="$1" _SP_TEMPLATE="$2"
    storpoolRetry volume "$_SP_VOL" template "$_SP_TEMPLATE" >/dev/null
}

function storpoolSnapshotInfo()
{
    SNAPSHOT_INFO=($(storpoolRetry -j snapshot "$1" info | jq -r '.data|[.size,.templateName]|@csv' | tr '[,"]' ' '  ))
    if boolTrue "DEBUG_storpoolSnapshotInfo"; then
        splog "storpoolSnapshotInfo($1):${SNAPSHOT_INFO[@]}"
    fi
}

function storpoolSnapshotCreate()
{
    local _SP_SNAPSHOT="$1" _SP_VOL="$2"

    storpoolRetry volume "$_SP_VOL" snapshot "$_SP_SNAPSHOT" >/dev/null
}

function storpoolSnapshotDelete()
{
    local _SP_SNAPSHOT="$1"

    storpoolRetry snapshot "$_SP_SNAPSHOT" delete "$_SP_SNAPSHOT" >/dev/null
}

function storpoolSnapshotClone()
{
    local _SP_SNAP="$1" _SP_VOL="$2" _SP_TEMPLATE="$3"

    storpoolRetry volume "$_SP_VOL" parent "$_SP_SNAP" ${_SP_TEMPLATE:+template "$_SP_TEMPLATE"} >/dev/null
}

function storpoolSnapshotRevert()
{
    local _SP_SNAPSHOT="$1" _SP_VOL="$2" _SP_TEMPLATE="$3"
    local _SP_TMP="$(date +%s)-$(mktemp --dry-run XXXXXXXX)"

    storpoolRetry volume "$_SP_VOL" rename "${_SP_VOL}-${_SP_TMP}" >/dev/null

    trapAdd "storpool volume \"$_SP_TMP\" rename \"$_SP_VOL\""

    storpoolSnapshotClone "$_SP_SNAPSHOT" "$_SP_VOL" "$_SP_TEMPLATE"

    trapReset

    storpoolVolumeDelete "${_SP_VOL}-$_SP_TMP"
}

function storpoolVolumeTag()
{
    local _SP_VOL="$1" _TAG_VAL="$2" _TAG_KEY="${3:-$VM_TAG}"
    local _OFS=$IFS tagCmd=
    IFS=\;
    tagVals=(${_TAG_VAL})
    tagKeys=(${_TAG_KEY})
    IFS=$_OFS
    local tagCmd=
    for i in ${!tagKeys[*]}; do
        tagKey="${tagKeys[i]//[[:space:]]/}"
        [ -n "$tagKey" ] || continue
        tagCmd+="tag ${tagKey}=${tagVals[i]//[[:space:]]/} "
    done
    if [ -n "$tagCmd" ]; then
        storpoolRetry volume "$_SP_VOL" $tagCmd >/dev/null
    fi
}

function storpoolSnapshotTag()
{
    local _SP_SNAP="$1" _TAG_VAL="$2" _TAG_KEY="${3:-$VM_TAG}"
    local _OFS=$IFS tagCmd=
    IFS=\;
    tagVals=(${_TAG_VAL})
    tagKeys=(${_TAG_KEY})
    IFS=$_OFS
    local tagCmd=
    for i in ${!tagKeys[*]}; do
        tagKey="${tagKeys[i]//[[:space:]]/}"
        [ -n "$tagKey" ] || continue
        tagCmd+="tag ${tagKey}=${tagVals[i]//[[:space:]]/} "
    done
    if [ -n "$tagCmd" ]; then
        storpoolRetry snapshot "$_SP_SNAP" $tagCmd >/dev/null
    fi
}

function oneSymlink()
{
    local _host="$1" _src="$2"
    shift 2
    local _dst="$*"
    splog "symlink $_src -> ${_host}:{${_dst//[[:space:]]/,}}${MONITOR_TM_MAD:+ (.monitor=$MONITOR_TM_MAD)}"
    local remote_cmd=$(cat <<EOF
    #_SYMLINK
    for dst in $_dst; do
        dst_dir=\$(dirname \$dst)
        if [ -d "\$dst_dir" ]; then
            true
        else
            splog "mkdir -p \$dst_dir (for:\$(basename "\$dst"))"
            trap "splog \"Can't create destination dir \$dst_dir (\$?)\"" TERM INT QUIT HUP EXIT
            splog "mkdir -p \$dst_dir"
            mkdir -p "\$dst_dir"
            trap - TERM INT QUIT HUP EXIT
        fi
        if [ -n "$MONITOR_TM_MAD" ]; then
            monitor_mad=
            if [ -f "\$dst_dir/../.monitor" ]; then
                monitor_mad=\$(<"\$dst_dir/../.monitor")
            fi
            if [ "\$monitor_mad" != "$MONITOR_TM_MAD" ]; then
                echo "$MONITOR_TM_MAD" >"\$dst_dir/../.monitor"
                splog "Wrote '$MONITOR_TM_MAD' to \$dst_dir/../.monitor (\$?)\${monitor_mad:+ was \$monitor_mad}"
            fi
        fi
        ln -sf "$_src" "\$dst"
        splog "ln -sf $_src \$dst (\$?)"
        echo "storpool" >"\$dst".monitor
    done
EOF
)
    ssh_exec_and_log "$_host" "${REMOTE_HDR}${remote_cmd}${REMOTE_FTR}" \
                 "Error creating symlink from $_src to ${_dst//[[:space:]]/,} on host $_host"
}

function oneFsfreeze()
{
    local _host="$1" _domain="$2"
    SCRIPTS_REMOTE_DIR="${SCRIPTS_REMOTE_DIR:-$(getFromConf "/etc/one/oned.conf" "SCRIPTS_REMOTE_DIR")}"

    local remote_cmd=$(cat <<EOF
    #_FSFREEZE
    if [ -n "$_domain" ]; then
        [ -f "${SCRIPTS_REMOTE_DIR}/etc/vmm/kvm/kvmrc" ] && source "${SCRIPTS_REMOTE_DIR}/etc/vmm/kvm/kvmrc" || source "${SCRIPTS_REMOTE_DIR}/vmm/kvm/kvmrc"
        if virsh --connect \$LIBVIRT_URI qemu-agent-command "$_domain" "{\"execute\":\"guest-fsfreeze-freeze\"}" 2>&1 >/dev/null; then
            splog "fsfreeze domain $_domain \$(virsh --connect \$LIBVIRT_URI qemu-agent-command "$_domain" "{\"execute\":\"guest-fsfreeze-status\"}")"
        else
            splog "($?) $_domain fsfreeze failed! snapshot not consistent!"
        fi
    fi

EOF
)
    ssh_exec_and_log "$_host" "${REMOTE_HDR}${remote_cmd}${REMOTE_FTR}" \
                 "Error in fsfreeze of domain $_domain on host $_host"
}

function oneFsthaw()
{
    local _host="$1" _domain="$2"
    SCRIPTS_REMOTE_DIR="${SCRIPTS_REMOTE_DIR:-$(getFromConf "/etc/one/oned.conf" "SCRIPTS_REMOTE_DIR")}"

    local remote_cmd=$(cat <<EOF
    #_FSTHAW
    if [ -n "$_domain" ]; then
        [ -f "${SCRIPTS_REMOTE_DIR}/etc/vmm/kvm/kvmrc" ] && source "${SCRIPTS_REMOTE_DIR}/etc/vmm/kvm/kvmrc" || source "${SCRIPTS_REMOTE_DIR}/vmm/kvm/kvmrc"
        if virsh --connect \$LIBVIRT_URI qemu-agent-command "$_domain" "{\"execute\":\"guest-fsfreeze-thaw\"}" 2>&1 >/dev/null; then
            splog "fsthaw domain $_domain \$(virsh --connect \$LIBVIRT_URI qemu-agent-command "$_domain" "{\"execute\":\"guest-fsfreeze-status\"}")"
        else
            splog "($?) $_domain fsthaw failed! VM fs freezed?"
        fi
    fi

EOF
)
    ssh_exec_and_log "$_host" "${REMOTE_HDR}${remote_cmd}${REMOTE_FTR}" \
                 "Error in fsthaw of domain $_domain on host $_host"
}

function oneCheckpointSave()
{
    local _host=${1%%:*}
    local _path="${1#*:}"
    local _vmid="$(basename "$_path")"
    local _dsid="$(basename $(dirname "$_path"))"
    local checkpoint="${_path}/checkpoint"
    local template="${ONE_PX}-ds-$_dsid"
    local volume="${ONE_PX}-sys-${_vmid}-checkpoint"
    local sp_link="/dev/storpool/$volume"

    SP_COMPRESSION="${SP_COMPRESSION:-lz4}"

    local remote_cmd=$(cat <<EOF
    # checkpoint Save
    if [ -f "$checkpoint" ]; then
        if tar --no-seek --use-compress-program="$SP_COMPRESSION" --create --file="$sp_link" "$checkpoint"; then
            splog "rm -f $checkpoint"
            rm -f "$checkpoint"
        else
            splog "Checkpoint import failed! $checkpoint ($?)"
            exit 1
        fi
    else
        splog "Checkpoint file not found! $checkpoint"
    fi

EOF
)
    local file_size=$($SSH "$_host" "du -b \"$checkpoint\" | cut -f 1")
    if [ -n "$file_size" ]; then
        local volume_size=$(( (file_size *2 +511) /512 *512 ))
        volume_size=$((volume_size/1024/1024))
    else
        splog "Checkpoint file not found! $checkpoint"
        return 0
    fi
    splog "checkpoint_size=${file_size} volume_size=${volume_size}M"

    if storpoolVolumeExists "$volume"; then
        storpoolVolumeDelete "$volume" "force"
    fi

    storpoolVolumeCreate "$volume" "$volume_size"M "$template"

    trapAdd "storpoolVolumeDelete \"$volume\" \"force\""

    storpoolVolumeAttach "$volume" "${_host}"

    splog "Saving $checkpoint to $volume"
    ssh_exec_and_log "${_host}" "${REMOTE_HDR}${remote_cmd}${REMOTE_FTR}" \
                 "Error in checkpoint save of VM ${_vmid} on host ${_host}"

    trapReset

    storpoolVolumeDetach "$volume" "" "${_host}" "all"
}

function oneCheckpointRestore()
{
    local _host=${1%%:*}
    local _path="${1#*:}"
    local _vmid="$(basename "$_path")"
    local checkpoint="${_path}/checkpoint"
    local volume="${ONE_PX}-sys-${_vmid}-checkpoint"
    local sp_link="/dev/storpool/$volume"

    SP_COMPRESSION="${SP_COMPRESSION:-lz4}"

    local remote_cmd=$(cat <<EOF
    # checkpoint Restore
    if [ -f "$checkpoint" ]; then
        splog "file exists $checkpoint"
    else
        mkdir -p "$_path"

        if [ -n "$2" ]; then
            [ -f "$_path/.monitor" ] || echo "storpool" >"$_path/.monitor"
        fi

        if tar --no-seek --use-compress-program="$SP_COMPRESSION" --to-stdout --extract --file="$sp_link" >"$checkpoint"; then
            splog "RESTORED $volume $checkpoint"
        else
            splog "Error: Failed to export $checkpoint"
            exit 1
        fi
    fi
EOF
)
    if storpoolVolumeExists "$volume"; then
        storpoolVolumeAttach "$volume" "${_host}"

        trapAdd "storpoolVolumeDetach \"$volume\" \"force\" \"${_host}\" \"all\""

        splog "Restoring $checkpoint from $volume"
        ssh_exec_and_log "$_host" "${REMOTE_HDR}${remote_cmd}${REMOTE_FTR}" \
                 "Error in checkpoint save of VM $_vmid on host $_host"

        trapReset

        storpoolVolumeDelete "$volume" "force"
    else
        splog "Checkpoint volume $volume not found"
    fi
}

function oneVmInfo()
{
    local _VM_ID="$1" _DISK_ID="$2"
    local _XPATH="$(lookup_file "datastore/xpath.rb" "${TM_PATH}")"

    local tmpXML="$(mktemp -t oneVmInfo-${_VM_ID}-XXXXXX)"
    local ret=$? errmsg=
    if [ $ret -ne 0 ]; then
        errmsg="(oneVmInfo) Error: Can't create temp file! (ret:$ret)"
        log_error "$errmsg"
        splog "$errmsg"
        exit $ret
    fi
    onevm show $ONE_ARGS -x "$_VM_ID" >"$tmpXML"
    ret=$?
    if [ $ret -ne 0 ]; then
        errmsg="(oneVmInfo) Error: Can't get info! $(head -n 1 "$tmpXML") (ret:$ret)"
        log_error "$errmsg"
        splog "$errmsg"
        exit $ret
    fi

    unset i XPATH_ELEMENTS
    while IFS= read -r -d '' element; do
        XPATH_ELEMENTS[i++]="$element"
        done < <(cat "$tmpXML" | sed '/\/>$/d' | "$_XPATH" --stdin \
                            /VM/DEPLOY_ID \
                            /VM/STATE \
                            /VM/PREV_STATE \
                            /VM/LCM_STATE \
                            /VM/CONTEXT/DISK_ID \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/SOURCE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/IMAGE_ID \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/IMAGE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/CLONE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/SAVE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/TYPE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/DRIVER \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/FORMAT \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/READONLY \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/PERSISTENT \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/HOTPLUG_SAVE_AS \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/HOTPLUG_SAVE_AS_ACTIVE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/HOTPLUG_SAVE_AS_SOURCE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/SIZE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/ORIGINAL_SIZE \
                            /VM/HISTORY_RECORDS/HISTORY[last\(\)]/TM_MAD \
                            /VM/HISTORY_RECORDS/HISTORY[last\(\)]/DS_ID \
                            /VM/USER_TEMPLATE/VMSNAPSHOT_LIMIT \
                            /VM/USER_TEMPLATE/DISKSNAPSHOT_LIMIT \
                            /VM/USER_TEMPLATE/VC_POLICY)
    rm -f "$tmpXML"
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
    HOTPLUG_SAVE_AS="${XPATH_ELEMENTS[i++]}"
    HOTPLUG_SAVE_AS_ACTIVE="${XPATH_ELEMENTS[i++]}"
    HOTPLUG_SAVE_AS_SOURCE="${XPATH_ELEMENTS[i++]}"
    SIZE="${XPATH_ELEMENTS[i++]}"
    ORIGINAL_SIZE="${XPATH_ELEMENTS[i++]}"
    VM_TM_MAD="${XPATH_ELEMENTS[i++]}"
    VM_DS_ID="${XPATH_ELEMENTS[i++]}"
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [ -n "$_TMP" ] && [ "${_tmp//[[:digit:]]/}" = "" ] ; then
        VMSNAPSHOT_LIMIT="${_TMP}"
    fi
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [ -n "$_TMP" ] && [ "${_tmp//[[:digit:]]/}" = "" ] ; then
        DISKSNAPSHOT_LIMIT="${_TMP}"
    fi
    VC_POLICY="${XPATH_ELEMENTS[i++]}"

    boolTrue "DEBUG_oneVmInfo" || return 0

    splog "[oneVmInfo]\
${VMSTATE:+VMSTATE=$VM_STATE(${VmState[$VMSTATE]}) }\
${LCM_STATE:+LCM_STATE=$LCM_STATE(${LcmState[$LCM_STATE]}) }\
${VMPREVSTATE:+VMPREVSTATE=$VMPREVSTATE(${VmState[$VMPREVSTATE]}) }\
${CONTEXT_DISK_ID:+CONTEXT_DISK_ID=$CONTEXT_DISK_ID }\
${SOURCE:+SOURCE=$SOURCE }\
${IMAGE_ID:+IMAGE_ID=$IMAGE_ID }\
${CLONE:+CLONE=$CLONE }\
${SAVE:+SAVE=$SAVE }\
${TYPE:+TYPE=$TYPE }\
${DRIVER:+DRIVER=$DRIVER }\
${FORMAT:+FORMAT=$FORMAT }\
${READONLY:+READONLY=$READONLY }\
${PERSISTENT:+PERSISTENT=$PERSISTENT }\
${IMAGE:+IMAGE='$IMAGE' }\
${SIZE:+SIZE='$SIZE' }\
${ORIGINAL_SIZE:+ORIGINAL_SIZE='$ORIGINAL_SIZE' }\
${VM_TM_MAD:+VM_TM_MAD=$VM_TM_MAD }\
${VM_DS_ID:+VM_DS_ID=$VM_DS_ID }\
${VMSNAPSHOT_LIMIT:+VMSNAPSHOT_LIMIT='$VMSNAPSHOT_LIMIT' }\
${DISKSNAPSHOT_LIMIT:+DISKSNAPSHOT_LIMIT='$DISKSNAPSHOT_LIMIT' }\
${VC_POLICY:+VC_POLICY='$VC_POLICY' }\
"
    _MSG="${HOTPLUG_SAVE_AS:+HOTPLUG_SAVE_AS=$HOTPLUG_SAVE_AS }${HOTPLUG_SAVE_AS_ACTIVE:+HOTPLUG_SAVE_AS_ACTIVE=$HOTPLUG_SAVE_AS_ACTIVE }${HOTPLUG_SAVE_AS_SOURCE:+HOTPLUG_SAVE_AS_SOURCE=$HOTPLUG_SAVE_AS_SOURCE }"
    [ -n "$_MSG" ] && splog "$_MSG"
}

function oneDatastoreInfo()
{
    local _DS_ID="$1" local _DS_POOL_FILE="$2"
    local _XPATH="$(lookup_file "datastore/xpath.rb" "${TM_PATH}")"

    local tmpXML="$(mktemp -t oneDatastoreInfo-${_DS_ID}-XXXXXX)"
    local ret=$? errmsg=
    if [ $ret -ne 0 ]; then
        errmsg="(oneDatastoreInfo) Error: Can't create temp file! (ret:$ret)"
        log_error "$errmsg"
        splog "$errmsg"
        exit $ret
    fi
    trapAdd "rm -f '$tmpXML'"

    if [ -n "$_DS_POOL_FILE" ]; then
        if [ ! -f "$_DS_POOL_FILE" ]; then
            onedatastore list $ONE_ARGS -x >"$_DS_POOL_FILE"
            ret=$?
            if boolTrue "DEBUG_oneDatastoreInfo"; then
                splog "($?) onedatastore list $ONE_ARGS -x >$_DS_POOL_FILE" 
            fi
            if [ $ret -ne 0 ]; then
                errmsg="(oneDatastoreInfo) Error: Can't get info! $(head -n 1 "$tmpXML") (ret:$ret)"
                splog "$errmsg"
                exit $ret
            fi
        fi
        xmllint -xpath "/DATASTORE_POOL/DATASTORE[ID=$_DS_ID]" "$_DS_POOL_FILE" >"$tmpXML"
        ret=$?
    else
        onedatastore show $ONE_ARGS -x "$_DS_ID" >"$tmpXML"
        ret=$?
    fi

    ret=$?
    if [ $ret -ne 0 ]; then
        errmsg="(oneDatastoreInfo) Error: Can't get info! $(head -n 1 "$tmpXML") (ret:$ret)"
        log_error "$errmsg"
        splog "$errmsg"
        exit $ret
    fi

    unset i XPATH_ELEMENTS
    while IFS= read -r -d '' element; do
        XPATH_ELEMENTS[i++]="$element"
        done < <(cat "$tmpXML" | sed '/\/>$/d' | "$_XPATH" --stdin \
                            /DATASTORE/NAME \
                            /DATASTORE/TYPE \
                            /DATASTORE/DISK_TYPE \
                            /DATASTORE/TM_MAD \
                            /DATASTORE/BASE_PATH \
                            /DATASTORE/CLUSTER_ID \
                            /DATASTORE/TEMPLATE/SHARED \
                            /DATASTORE/TEMPLATE/TYPE \
                            /DATASTORE/TEMPLATE/BRIDGE_LIST \
                            /DATASTORE/TEMPLATE/EXPORT_BRIDGE_LIST \
                            /DATASTORE/TEMPLATE/SP_REPLICATION \
                            /DATASTORE/TEMPLATE/SP_PLACEALL \
                            /DATASTORE/TEMPLATE/SP_PLACETAIL \
                            /DATASTORE/TEMPLATE/SP_PLACEHEAD \
                            /DATASTORE/TEMPLATE/SP_IOPS \
                            /DATASTORE/TEMPLATE/SP_BW \
                            /DATASTORE/TEMPLATE/SP_SYSTEM \
                            /DATASTORE/TEMPLATE/SP_TEMPLATE_PROPAGATE \
                            /DATASTORE/TEMPLATE/SP_API_HTTP_HOST \
                            /DATASTORE/TEMPLATE/SP_API_HTTP_PORT \
                            /DATASTORE/TEMPLATE/SP_AUTH_TOKEN \
                            /DATASTORE/TEMPLATE/SP_CLONE_GW \
                            /DATASTORE/TEMPLATE/VMSNAPSHOT_LIMIT \
                            /DATASTORE/TEMPLATE/DISKSNAPSHOT_LIMIT \
                            /DATASTORE/TEMPLATE/REMOTE_BACKUP_DELETE)
    rm -f "$tmpXML"
    trapDel "rm -f '$tmpXML'"
    unset i
    DS_NAME="${XPATH_ELEMENTS[i++]}"
    DS_TYPE="${XPATH_ELEMENTS[i++]}"
    DS_DISK_TYPE="${XPATH_ELEMENTS[i++]}"
    DS_TM_MAD="${XPATH_ELEMENTS[i++]}"
    DS_BASE_PATH="${XPATH_ELEMENTS[i++]}"
    DS_CLUSTER_ID="${XPATH_ELEMENTS[i++]}"
    DS_SHARED="${XPATH_ELEMENTS[i++]}"
    DS_TEMPLATE_TYPE="${XPATH_ELEMENTS[i++]}"
    BRIDGE_LIST="${XPATH_ELEMENTS[i++]}"
    EXPORT_BRIDGE_LIST="${XPATH_ELEMENTS[i++]}"
    SP_REPLICATION="${XPATH_ELEMENTS[i++]}"
    SP_PLACEALL="${XPATH_ELEMENTS[i++]}"
    SP_PLACETAIL="${XPATH_ELEMENTS[i++]}"
    SP_PLACEHEAD="${XPATH_ELEMENTS[i++]}"
    SP_IOPS="${XPATH_ELEMENTS[i++]:--}"
    SP_BW="${XPATH_ELEMENTS[i++]:--}"
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [ -n "$_TMP" ] ; then
        SP_SYSTEM="${_TMP}"
    fi
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [ -n "$_TMP" ] ; then
        SP_TEMPLATE_PROPAGATE="${_TMP}"
    fi
    SP_API_HTTP_HOST="${XPATH_ELEMENTS[i++]}"
    SP_API_HTTP_PORT="${XPATH_ELEMENTS[i++]}"
    SP_AUTH_TOKEN="${XPATH_ELEMENTS[i++]}"
    SP_CLONE_GW="${XPATH_ELEMENTS[i++]}"
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [ -n "$_TMP" ] && [ "${_tmp//[[:digit:]]/}" = "" ] ; then
        VMSNAPSHOT_LIMIT="${_TMP}"
    fi
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [ -n "$_TMP" ] && [ "${_tmp//[[:digit:]]/}" = "" ] ; then
        DISKSNAPSHOT_LIMIT="${_TMP}"
    fi
    REMOTE_BACKUP_DELETE="${XPATH_ELEMENTS[i++]}"

    [ -n "$SP_API_HTTP_HOST" ] && export SP_API_HTTP_HOST || unset SP_API_HTTP_HOST
    [ -n "$SP_API_HTTP_PORT" ] && export SP_API_HTTP_PORT || unset SP_API_HTTP_PORT
    [ -n "$SP_AUTH_TOKEN" ] && export SP_AUTH_TOKEN || unset SP_AUTH_TOKEN

    boolTrue "DEBUG_oneDatastoreInfo" || return 0

    _MSG="[oneDatastoreInfo]${DS_TYPE:+DS_TYPE=$DS_TYPE }${DS_TEMPLATE_TYPE:+TEMPLATE_TYPE=$DS_TEMPLATE_TYPE }"
    _MSG+="${DS_DISK_TYPE:+DISK_TYPE=$DS_DISK_TYPE }${DS_TM_MAD:+DS_TM_MAD=$DS_TM_MAD }"
    _MSG+="${DS_BASE_PATH:+BASE_PATH=$DS_BASE_PATH }${DS_CLUSTER_ID:+CLUSTER_ID=$DS_CLUSTER_ID }"
    _MSG+="${DS_SHARED:+SHARED=$DS_SHARED }"
    _MSG+="${SP_SYSTEM:+SP_SYSTEM=$SP_SYSTEM }${SP_CLONE_GW:+SP_CLONE_GW=$SP_CLONE_GW }"
    _MSG+="${EXPORT_BRIDGE_LIST:+EXPORT_BRIDGE_LIST=$EXPORT_BRIDGE_LIST }"
    _MSG+="${DS_NAME:+NAME='$DS_NAME' }${VMSNAPSHOT_LIMIT:+VMSNAPSHOT_LIMIT=$VMSNAPSHOT_LIMIT} ${DISKSNAPSHOT_LIMIT:+DISKSNAPSHOT_LIMIT=$DISKSNAPSHOT_LIMIT }"
    _MSG+="${SP_REPLICATION:+SP_REPLICATION=$SP_REPLICATION }"
    _MSG+="${SP_PLACEALL:+SP_PLACEALL=$SP_PLACEALL }${SP_PLACETAIL:+SP_PLACETAIL=$SP_PLACETAIL }${SP_PLACEHEAD:+SP_PLACEHEAD=$SP_PLACEHEAD }"
    _MSG+="${REMOTE_BACKUP_DELETE:+REMOTE_BACKUP_DELETE=$REMOTE_BACKUP_DELETE }"
    splog "$_MSG"
}

function dumpTemplate()
{
    local _TEMPLATE="$1"
    echo "$_TEMPLATE" | base64 -d | xmllint --format - > "/tmp/${LOG_PREFIX:-tm}_${0##*/}-$$.xml"
}

function oneTemplateInfo()
{
    local _TEMPLATE="$1"
#    dumpTemplate "$_TEMPLATE"
    local _XPATH="$(lookup_file "datastore/xpath-sp.rb" "${TM_PATH}")"
    if [ -z "$_TEMPLATE" ]; then
        _TEMPLATE="$(mktemp -t oneTemplateInfo-XXXXXXXXXX)"
        trapAdd "rm -f \"$_TEMPLATE\""
        onevm show -x "$VM_ID" |base64 -w0 >"$_TEMPLATE"
    fi
    if [ -f "$_TEMPLATE" ]; then
        _XPATH="$_XPATH -b yes -f"
    else
        _XPATH="$_XPATH -b"
    fi

    unset i XPATH_ELEMENTS
    while IFS= read -r -d '' element; do
        XPATH_ELEMENTS[i++]="$element"
        done < <($_XPATH "$_TEMPLATE" \
                    /VM/ID \
                    /VM/STATE \
                    /VM/LCM_STATE \
                    /VM/PREV_STATE \
                    /VM/TEMPLATE/CONTEXT/DISK_ID \
					/VM/USER_TEMPLATE/VC_POLICY)
    unset i
    _VM_ID=${XPATH_ELEMENTS[i++]}
    _VM_STATE=${XPATH_ELEMENTS[i++]}
    _VM_LCM_STATE=${XPATH_ELEMENTS[i++]}
    _VM_PREV_STATE=${XPATH_ELEMENTS[i++]}
    _CONTEXT_DISK_ID=${XPATH_ELEMENTS[i++]}
    VC_POLICY="${XPATH_ELEMENTS[i++]}"
    if boolTrue "DEBUG_oneTemplateInfo"; then
        splog "VM_ID=$_VM_ID VM_STATE=$_VM_STATE(${VmState[$_VM_STATE]}) VM_LCM_STATE=$_VM_LCM_STATE(${LcmState[$_VM_LCM_STATE]}) VM_PREV_STATE=$_VM_PREV_STATE(${VmState[$_VM_PREV_STATE]}) CONTEXT_DISK_ID=$_CONTEXT_DISK_ID VC_POLICY=$VC_POLICY"
    fi

    _XPATH="$(lookup_file "datastore/xpath_multi.py" "${TM_PATH}")"
    if [ -f "$_TEMPLATE" ]; then
        _XPATH="$_XPATH -b -f"
    else
        _XPATH="$_XPATH -b"
    fi
    unset i XPATH_ELEMENTS
    while read -r element; do
        XPATH_ELEMENTS[i++]="$element"
    done < <($_XPATH "$_TEMPLATE" \
                    /VM/TEMPLATE/DISK/TM_MAD \
                    /VM/TEMPLATE/DISK/DATASTORE_ID \
                    /VM/TEMPLATE/DISK/DISK_ID \
                    /VM/TEMPLATE/DISK/CLUSTER_ID \
                    /VM/TEMPLATE/DISK/SOURCE \
                    /VM/TEMPLATE/DISK/PERSISTENT \
                    /VM/TEMPLATE/DISK/TYPE \
                    /VM/TEMPLATE/DISK/CLONE \
                    /VM/TEMPLATE/DISK/READONLY \
                    /VM/TEMPLATE/DISK/FORMAT)
    unset i
    _DISK_TM_MAD=${XPATH_ELEMENTS[i++]}
    _DISK_DATASTORE_ID=${XPATH_ELEMENTS[i++]}
    _DISK_ID=${XPATH_ELEMENTS[i++]}
    _DISK_CLUSTER_ID=${XPATH_ELEMENTS[i++]}
    _DISK_SOURCE=${XPATH_ELEMENTS[i++]}
    _DISK_PERSISTENT=${XPATH_ELEMENTS[i++]}
    _DISK_TYPE=${XPATH_ELEMENTS[i++]}
    _DISK_CLONE=${XPATH_ELEMENTS[i++]}
    _DISK_READONLY=${XPATH_ELEMENTS[i++]}
    _DISK_FORMAT=${XPATH_ELEMENTS[i++]}

    _OLDIFS=$IFS
    IFS=";"
    DISK_TM_MAD_ARRAY=($_DISK_TM_MAD)
    DISK_DATASTORE_ID_ARRAY=($_DISK_DATASTORE_ID)
    DISK_ID_ARRAY=($_DISK_ID)
    DISK_CLUSTER_ID_ARRAY=($_DISK_CLUSTER_ID)
    DISK_SOURCE_ARRAY=($_DISK_SOURCE)
    DISK_PERSISTENT_ARRAY=($_DISK_PERSISTENT)
    DISK_TYPE_ARRAY=($_DISK_TYPE)
    DISK_CLONE_ARRAY=($_DISK_CLONE)
    DISK_READONLY_ARRAY=($_DISK_READONLY)
    DISK_FORMAT_ARRAY=($_DISK_FORMAT)
    IFS=$_OLDIFS

    boolTrue "DEBUG_oneTemplateInfo" || return 0

    splog "[oneTemplateInfo] disktm:$_DISK_TM_MAD ds:$_DISK_DATASTORE_ID disk:$_DISK_ID cluster:$_DISK_CLUSTER_ID src:$_DISK_SOURCE persistent:$_DISK_PERSISTENT type:$_DISK_TYPE clone:$_DISK_CLONE readonly:$_DISK_READONLY format:$_DISK_FORMAT"
#    echo $_TEMPLATE | base64 -d >/tmp/${ONE_PX}-template-${_VM_ID}-${0##*/}-${_VM_STATE}.xml
}



function oneDsDriverAction()
{
    local _DRIVER_PATH="$1"
    local _XPATH="$(lookup_file "datastore/xpath.rb" "${_DRIVER_PATH}") -b $DRV_ACTION"

    unset i XPATH_ELEMENTS

    while IFS= read -r -d '' element; do
        XPATH_ELEMENTS[i++]="$element"
    done < <($_XPATH     /DS_DRIVER_ACTION_DATA/DATASTORE/BASE_PATH \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/ID \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/STATE \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/UID \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/GID \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/CLUSTER_ID \
                    %m%/DS_DRIVER_ACTION_DATA/DATASTORE/CLUSTERS/ID \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TM_MAD \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/BRIDGE_LIST \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/EXPORT_BRIDGE_LIST \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_REPLICATION \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_PLACEALL \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_PLACETAIL \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_PLACEHEAD \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_IOPS \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_BW \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_API_HTTP_HOST \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_API_HTTP_PORT \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_AUTH_TOKEN \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_CLONE_GW \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_SYSTEM \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_TEMPLATE_PROPAGATE \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/NO_DECOMPRESS \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/LIMIT_TRANSFER_BW \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/TYPE \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/REMOTE_BACKUP_DELETE \
                    /DS_DRIVER_ACTION_DATA/IMAGE/TEMPLATE/MD5 \
                    /DS_DRIVER_ACTION_DATA/IMAGE/TEMPLATE/SHA1 \
                    /DS_DRIVER_ACTION_DATA/IMAGE/TEMPLATE/DRIVER \
                    /DS_DRIVER_ACTION_DATA/IMAGE/TEMPLATE/FORMAT \
                    /DS_DRIVER_ACTION_DATA/IMAGE/PATH \
                    /DS_DRIVER_ACTION_DATA/IMAGE/PERSISTENT \
                    /DS_DRIVER_ACTION_DATA/IMAGE/FSTYPE \
                    /DS_DRIVER_ACTION_DATA/IMAGE/SOURCE \
                    /DS_DRIVER_ACTION_DATA/IMAGE/TYPE \
                    /DS_DRIVER_ACTION_DATA/IMAGE/CLONE \
                    /DS_DRIVER_ACTION_DATA/IMAGE/SAVE \
                    /DS_DRIVER_ACTION_DATA/IMAGE/DISK_TYPE \
                    /DS_DRIVER_ACTION_DATA/IMAGE/STATE \
                    /DS_DRIVER_ACTION_DATA/IMAGE/CLONING_ID \
                    /DS_DRIVER_ACTION_DATA/IMAGE/CLONING_OPS \
                    /DS_DRIVER_ACTION_DATA/IMAGE/TARGET_SNAPSHOT \
                    /DS_DRIVER_ACTION_DATA/IMAGE/SIZE \
                    /DS_DRIVER_ACTION_DATA/IMAGE/UID \
                    /DS_DRIVER_ACTION_DATA/IMAGE/GID \
                    /DS_DRIVER_ACTION_DATA/MONITOR_VM_DISKS)


    unset i
    BASE_PATH="${XPATH_ELEMENTS[i++]}"
    DATASTORE_ID="${XPATH_ELEMENTS[i++]}"
    DATASTORE_STATE="${XPATH_ELEMENTS[i++]}"
    DATASTORE_UID="${XPATH_ELEMENTS[i++]}"
    DATASTORE_GID="${XPATH_ELEMENTS[i++]}"
    CLUSTER_ID="${XPATH_ELEMENTS[i++]}"
    CLUSTERS_ID="${XPATH_ELEMENTS[i++]}"
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
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [ -n "$_TMP" ] ; then
        SP_SYSTEM="${_TMP}"
    fi
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [ -n "$_TMP" ] ; then
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
    IMAGE_PATH="${XPATH_ELEMENTS[i++]}"
    PERSISTENT="${XPATH_ELEMENTS[i++]}"
    FSTYPE="${XPATH_ELEMENTS[i++]}"
    SOURCE="${XPATH_ELEMENTS[i++]}"
    TYPE="${XPATH_ELEMENTS[i++]}"
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

    [ -n "$SP_API_HTTP_HOST" ] && export SP_API_HTTP_HOST || unset SP_API_HTTP_HOST
    [ -n "$SP_API_HTTP_PORT" ] && export SP_API_HTTP_PORT || unset SP_API_HTTP_PORT
    [ -n "$SP_AUTH_TOKEN" ] && export SP_AUTH_TOKEN || unset SP_AUTH_TOKEN

    boolTrue "DEBUG_oneDsDriverAction" || return 0

    _MSG="[oneDsDriverAction]\
${ID:+ID=$ID }\
${IMAGE_UID:+IMAGE_UID=$IMAGE_UID }\
${IMAGE_GID:+IMAGE_GID=$IMAGE_GID }\
${DATASTORE_ID:+DATASTORE_ID=$DATASTORE_ID }\
${DATASTORE_STATE:+DATASTORE_STATE=$DATASTORE_STATE }\
${CLUSTER_ID:+CLUSTER_ID=$CLUSTER_ID }\
${CLUSTERS_ID:+CLUSTERS_ID=$CLUSTERS_ID }\
${STATE:+STATE=$STATE }\
${SIZE:+SIZE=$SIZE }\
${SP_API_HTTP_HOST:+SP_API_HTTP_HOST=$SP_API_HTTP_HOST }\
${SP_API_HTTP_PORT:+SP_API_HTTP_PORT=$SP_API_HTTP_PORT }\
${SP_AUTH_TOKEN:+SP_AUTH_TOKEN=DEFINED }\
${SP_CLONE_GW:+SP_CLONE_GW=$SP_CLONE_GW }\
${SOURCE:+SOURCE=$SOURCE }\
${PERSISTENT:+PERSISTENT=$PERSISTENT }\
${DRIVER:+DRIVER=$DRIVER }\
${FORMAT:+FORMAT=$FORMAT }\
${FSTYPE:+FSTYPE=$FSTYPE }\
${TYPE:+TYPE=$TYPE }\
${CLONE:+CLONE=$CLONE }\
${SAVE:+SAVE=$SAVE }\
${DISK_TYPE:+DISK_TYPE=$DISK_TYPE }\
${CLONING_ID:+CLONING_ID=$CLONING_ID }\
${CLONING_OPS:+CLONING_OPS=$CLONING_OPS }\
${IMAGE_PATH:+IMAGE_PATH=$IMAGE_PATH }\
${BRIDGE_LIST:+BRIDGE_LIST=$BRIDGE_LIST }\
${EXPORT_BRIDGE_LIST:+EXPORT_BRIDGE_LIST=$EXPORT_BRIDGE_LIST }\
${BASE_PATH:+BASE_PATH=$BASE_PATH }\
${SP_REPLICATION:+SP_REPLICATION=$SP_REPLICATION }\
${SP_PLACEALL:+SP_PLACEALL=$SP_PLACEALL }\
${SP_PLACETAIL:+SP_PLACETAIL=$SP_PLACETAIL }\
${SP_PLACEHEAD:+SP_PLACEHEAD=$SP_PLACEHEAD }\
${SP_IOPS:+SP_IOPS=$SP_IOPS }\
${SP_BW:+SP_BW=$SP_BW }\
${SP_SYSTEM:+SP_SYSTEM=$SP_SYSTEM }\
${SP_TEMPLATE_PROPAGATE:+SP_TEMPLATE_PROPAGATE=$SP_TEMPLATE_PROPAGATE }\
${REMOTE_BACKUP_DELETE:+REMOTE_BACKUP_DELETE=$REMOTE_BACKUP_DELETE }\
${MONITOR_VM_DISKS:+MONITOR_VM_DISKS=$MONITOR_VM_DISKS }\
"
    splog "$_MSG"
}

function oneMarketDriverAction()
{
    local _DRIVER_PATH="$1"
    local _XPATH="$(lookup_file "datastore/xpath.rb" "${_DRIVER_PATH}") -b $DRV_ACTION"

    unset i XPATH_ELEMENTS

    while IFS= read -r -d '' element; do
        XPATH_ELEMENTS[i++]="$element"
    done < <($_XPATH     /MARKET_DRIVER_ACTION_DATA/IMPORT_SOURCE \
                    /MARKET_DRIVER_ACTION_DATA/FORMAT \
                    /MARKET_DRIVER_ACTION_DATA/DISPOSE \
                    /MARKET_DRIVER_ACTION_DATA/SIZE \
                    /MARKET_DRIVER_ACTION_DATA/MD5 \
                    /MARKET_DRIVER_ACTION_DATA/MARKETPLACE/TEMPLATE/BASE_URL \
                    /MARKET_DRIVER_ACTION_DATA/MARKETPLACE/TEMPLATE/BRIDGE_LIST \
                    /MARKET_DRIVER_ACTION_DATA/MARKETPLACE/TEMPLATE/PUBLIC_DIR \
                    /MARKET_DRIVER_ACTION_DATA/MARKETPLACE/TEMPLATE/SP_API_HTTP_HOST \
                    /MARKET_DRIVER_ACTION_DATA/MARKETPLACE/TEMPLATE/SP_API_HTTP_PORT \
                    /MARKET_DRIVER_ACTION_DATA/MARKETPLACE/TEMPLATE/SP_AUTH_TOKEN)

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

    [ -n "$SP_API_HTTP_HOST" ] && export SP_API_HTTP_HOST || unset SP_API_HTTP_HOST
    [ -n "$SP_API_HTTP_PORT" ] && export SP_API_HTTP_PORT || unset SP_API_HTTP_PORT
    [ -n "$SP_AUTH_TOKEN" ] && export SP_AUTH_TOKEN || unset SP_AUTH_TOKEN

    boolTrue "DEBUG_oneMarketDriverAction" || return 0

    splog "\
${IMPORT_SOURCE:+IMPORT_SOURCE=$IMPORT_SOURCE }\
${FORMAT:+FORMAT=$FORMAT }\
${DISPOSE:+DISPOSE=$DISPOSE }\
${SIZE:+SIZE=$SIZE }\
${MD5:+MD5=$MD5 }\
${BASE_URL:+BASE_URL=$BASE_URL }\
${BRIDGE_LIST:+BRIDGE_LIST=$BRIDGE_LIST }\
${PUBLIC_DIR:+PUBLIC_DIR=$PUBLIC_DIR }\
${SP_API_HTTP_HOST:+SP_API_HTTP_HOST=$SP_API_HTTP_HOST }\
${SP_API_HTTP_PORT:+SP_API_HTTP_PORT=$SP_API_HTTP_PORT }\
${SP_AUTH_TOKEN:+SP_AUTH_TOKEN=available }\
"
}

oneVmVolumes()
{
    local VM_ID="$1" VM_POOL_FILE="$2"
    if boolTrue "DEBUG_oneVmVolumes"; then
        splog "oneVmVolumes() VM_ID:$VM_ID vmPoolFile:$VM_POOL_FILE"
    fi

    local tmpXML="$(mktemp -t oneVmVolumes-${VM_ID}-XXXXXX)"
    local ret=$? errmsg=
    if [ $ret -ne 0 ]; then
        errmsg="(oneVmVolumes) Error: Can't create temp file! (ret:$ret)"
        log_error "$errmsg"
        splog "$errmsg"
        exit $ret
    fi
    trapAdd "rm -f \"$tmpXML\""
    if [ -f "$VM_POOL_FILE" ]; then
        xmllint -xpath "/VM_POOL/VM[ID=$VM_ID]" "$VM_POOL_FILE" >"$tmpXML"
        ret=$?
    else
        onevm show $ONE_ARGS -x "$VM_ID" >"$tmpXML"
        ret=$?
    fi
    if [ $ret -ne 0 ]; then
        errmsg="(oneVmVolumes) Error: Can't get VM info! $(head -n 1 "$tmpXML") (ret:$ret)"
        log_error "$errmsg"
        splog "$errmsg"
        exit $ret
    fi

    unset XPATH_ELEMENTS i
    while read element; do
        XPATH_ELEMENTS[i++]="$element"
    done < <(cat "$tmpXML" |\
        ${DRIVER_PATH}/../../datastore/xpath_multi.py -s \
        /VM/HISTORY_RECORDS/HISTORY[last\(\)]/DS_ID \
        /VM/TEMPLATE/CONTEXT/DISK_ID \
        /VM/TEMPLATE/DISK/DISK_ID \
        /VM/TEMPLATE/DISK/CLONE \
        /VM/TEMPLATE/DISK/FORMAT \
        /VM/TEMPLATE/DISK/TYPE \
        /VM/TEMPLATE/DISK/TM_MAD \
        /VM/TEMPLATE/DISK/TARGET \
        /VM/TEMPLATE/DISK/IMAGE_ID \
        /VM/TEMPLATE/SNAPSHOT/SNAPSHOT_ID \
        /VM/USER_TEMPLATE/VMSNAPSHOT_LIMIT \
        /VM/USER_TEMPLATE/DISKSNAPSHOT_LIMIT \
        /VM/USER_TEMPLATE/VC_POLICY)
    rm -f "$tmpXML"
    trapDel "rm -f \"$tmpXML\""
    unset i
    VM_DS_ID="${XPATH_ELEMENTS[i++]}"
    local CONTEXT_DISK_ID="${XPATH_ELEMENTS[i++]}"
    local DISK_ID="${XPATH_ELEMENTS[i++]}"
    local CLONE="${XPATH_ELEMENTS[i++]}"
    local FORMAT="${XPATH_ELEMENTS[i++]}"
    local TYPE="${XPATH_ELEMENTS[i++]}"
    local TM_MAD="${XPATH_ELEMENTS[i++]}"
    local TARGET="${XPATH_ELEMENTS[i++]}"
    local IMAGE_ID="${XPATH_ELEMENTS[i++]}"
    local SNAPSHOT_ID="${XPATH_ELEMENTS[i++]}"
    local _TMP=
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [ -n "$_TMP" ] && [ "${_tmp//[[:digit:]]/}" = "" ]; then
        VM_VMSNAPSHOT_LIMIT="${_TMP}"
    fi
    _TMP="${XPATH_ELEMENTS[i++]}"
    if [ -n "$_TMP" ] && [ "${_tmp//[[:digit:]]/}" = "" ]; then
        DISKSNAPSHOT_LIMIT="${_TMP}"
    fi
    VC_POLICY="${XPATH_ELEMENTS[i++]}"
    local IMG=
    _OFS=$IFS
    IFS=';'
    DISK_ID_A=($DISK_ID)
    CLONE_A=($CLONE)
    FORMAT_A=($FORMAT)
    TYPE_A=($TYPE)
    TM_MAD_A=($TM_MAD)
    TARGET_A=($TARGET)
    IMAGE_ID_A=($IMAGE_ID)
    SNAPSHOT_ID_A=($SNAPSHOT_ID)
    IFS=$_OFS
    for ID in ${!DISK_ID_A[@]}; do
        IMAGE_ID="${IMAGE_ID_A[$ID]}"
        CLONE="${CLONE_A[$ID]}"
        FORMAT="${FORMAT_A[$ID]}"
        TYPE="${TYPE_A[$ID]}"
        TM_MAD="${TM_MAD_A[$ID]}"
        TARGET="${TARGET_A[$ID]}"
        DISK_ID="${DISK_ID_A[$ID]}"
        if [ "${TM_MAD:0:8}" != "storpool" ]; then
            splog "DISK_ID:$DISK_ID TYPE:$TYPE TM_MAD:$TM_MAD "
            if ! boolTrue "SYSTEM_COMPATIBLE_DS[$TM_MAD]"; then
                oneVmVolumesNotStorPool="$TM_MAD:disk.$DISK_ID"
                continue
            fi
        fi
        IMG="${ONE_PX}-img-$IMAGE_ID"
        if [ -n "$IMAGE_ID" ]; then
            if boolTrue "CLONE"; then
                IMG+="-$VM_ID-$DISK_ID"
            elif [ "$TYPE" = "CDROM" ]; then
                IMG+="-$VM_ID-$DISK_ID"
            fi
        else
            case "$TYPE" in
                swap)
                    IMG="${ONE_PX}-sys-${VM_ID}-${DISK_ID}-swap"
                    ;;
                *)
                    IMG="${ONE_PX}-sys-${VM_ID}-${DISK_ID}-${FORMAT:-raw}"
            esac
        fi
        vmVolumes+="$IMG "
        if boolTrue "DEBUG_oneVmVolumes"; then
            splog "oneVmVolumes() VM_ID:$VM_ID disk.$DISK_ID $IMG"
        fi
        vmDisks=$((vmDisks+1))
        vmDisksMap+="$IMG:$DISK_ID "
    done
    DISK_ID="$CONTEXT_DISK_ID"
    if [ -n "$DISK_ID" ]; then
        IMG="${ONE_PX}-sys-${VM_ID}-${DISK_ID}-iso"
        vmVolumes+="$IMG "
        if boolTrue "DEBUG_oneVmVolumes"; then
            splog "oneVmVolumes() VM_ID:$VM_ID disk.$DISK_ID $IMG"
        fi
    fi
    if boolTrue "DEBUG_oneVmVolumes"; then
        splog "oneVmVolumes() VM_ID:$VM_ID VM_DS_ID=$VM_DS_ID${VMSNAPSHOT_LIMIT:+ VMSNAPSHOT_LIMIT=$VMSNAPSHOT_LIMIT}${DISKSNAPSHOT_LIMIT:+ DISKSNAPSHOT_LIMIT=$DISKSNAPSHOT_LIMIT}${VC_POLICY:+ VC_POLICY=$VC_POLICY}"
    fi
}

oneVmDiskSnapshots()
{
    local VM_ID="$1" DISK_ID="$2"
    if boolTrue "DDEBUG_oneVmDiskSnapshots"; then
        splog "oneVmDiskSnapshots() VM_ID:$VM_ID DISK_ID=$DISK_ID"
    fi

    local tmpXML="$(mktemp -t oneVmDiskSnapshots-${VM_ID}-XXXXXX)"
    local ret=$? errmsg=
    if [ $ret -ne 0 ]; then
        errmsg="(oneVmDiskSnapshots) Error: Can't create temp file! (ret:$ret)"
        log_error "$errmsg"
        splog "$errmsg"
        exit $ret
    fi
    onevm show $ONE_ARGS -x "$VM_ID" >"$tmpXML"
    ret=$?
    if [ $ret -ne 0 ]; then
        errmsg="(oneVmDiskSnapshots) Error: Can't get info for ${VM_ID}! $(head -n 1 "$tmpXML") (ret:$ret)"
        log_error "$errmsg"
        splog "$errmsg"
        exit $ret
    fi

    unset XPATH_ELEMENTS i
    while read element; do
        XPATH_ELEMENTS[i++]="$element"
    done < <(cat "$tmpXML" |\
        ${DRIVER_PATH}/../../datastore/xpath.rb \
        %m%/VM/SNAPSHOTS[DISK_ID="$DISK_ID"]/SNAPSHOT/ID)
    rm -f "$tmpXML"
    unset i
    local _DISK_SNAPSHOTS="${XPATH_ELEMENTS[i++]}"
    DISK_SNAPSHOTS=(${_DISK_SNAPSHOTS})
    if boolTrue "DEBUG_oneVmDiskSnapshots"; then
        splog "oneVmDiskSnapshots() VM_ID:$VM_ID DISK_ID=$DISK_ID SNAPSHOTS:${#DISK_SNAPSHOTS[@]} SNAPSHOT_IDs:$_DISK_SNAPSHOTS "
    fi
}

oneVmSnapshots()
{
    local VM_ID="$1" snapshot_id="$2" disk_id="$3"
    if boolTrue "DDEBUG_oneVmSnapshots"; then
        splog "oneVmSnapshots() VM_ID:$VM_ID snapshot_id=$snapshot_id disk_id=$disk_id"
    fi
    
    if [ -z "$VM_ID" ]; then
        splog "oneVmSnapshots: No VM_ID! VM_ID:$VM_ID snapshot_id=$snapshot_id disk_id=$disk_id"
        return 1
    fi

    local tmpXML="$(mktemp -t oneVmSnapshots-${VM_ID}-XXXXXX)"
    local ret=$? errmsg=
    if [ $ret -ne 0 ]; then
        errmsg="(oneVmSnapshots) Error: Can't create temp file! (ret:$ret)"
        log_error "$errmsg"
        splog "$errmsg"
        exit $ret
    fi
    onevm show $ONE_ARGS -x "$VM_ID" >"$tmpXML"
    ret=$?
    if [ $ret -ne 0 ]; then
        errmsg="(oneVmSnapshots) Error: Can't get info for ${VM_ID}! $(head -n 1 "$tmpXML") (ret:$ret)"
        log_error "$errmsg"
        splog "$errmsg"
        exit $ret
    fi

    local query="
        /VM/UID
        /VM/GID
        /VM/TEMPLATE/CONTEXT/DISK_ID
        %m%/VM/TEMPLATE/SNAPSHOT/SNAPSHOT_ID
        %m%/VM/TEMPLATE/SNAPSHOT/HYPERVISOR_ID"
    [ -n "$snapshot_id" ] && query="
        /VM/UID
        /VM/GID
        /VM/TEMPLATE/CONTEXT/DISK_ID
        /VM/TEMPLATE/SNAPSHOT[SNAPSHOT_ID="$snapshot_id"]/SNAPSHOT_ID
        /VM/TEMPLATE/SNAPSHOT[SNAPSHOT_ID="$snapshot_id"]/HYPERVISOR_ID"
    [ -n "$disk_id" ] && query+=" /VM/TEMPLATE/DISK[DISK_ID=\"$disk_id\"]/DATASTORE_ID
        /VM/TEMPLATE/DISK[DISK_ID=\"$disk_id\"]/DISK_TYPE
        /VM/TEMPLATE/DISK[DISK_ID=\"$disk_id\"]/TYPE
        /VM/TEMPLATE/DISK[DISK_ID=\"$disk_id\"]/SOURCE
        /VM/TEMPLATE/DISK[DISK_ID=\"$disk_id\"]/CLONE
        /VM/TEMPLATE/DISK[DISK_ID=\"$disk_id\"]/FORMAT"
    unset XPATH_ELEMENTS i
    while IFS= read -r -d '' element; do
        XPATH_ELEMENTS[i++]="$element"
    done < <(cat "$tmpXML" |\
        ${DRIVER_PATH}/../../datastore/xpath.rb $query)
    rm -f "$tmpXML"
    unset i
    VM_UID="${XPATH_ELEMENTS[i++]}"
    VM_GID="${XPATH_ELEMENTS[i++]}"
    CONTEXT_DISK_ID="${XPATH_ELEMENTS[i++]}"
    local _SNAPSHOT_ID="${XPATH_ELEMENTS[i++]}"
    local _HYPERVISOR_ID="${XPATH_ELEMENTS[i++]}"
    SNAPSHOT_IDS=(${_SNAPSHOT_ID})
    HYPERVISOR_IDS=(${_HYPERVISOR_ID})
    if [ -n "$disk_id" ]; then
        DISK_A="${XPATH_ELEMENTS[i++]}"
        DISK_B="${XPATH_ELEMENTS[i++]}"
        DISK_C="${XPATH_ELEMENTS[i++]}"
        DISK_D="${XPATH_ELEMENTS[i++]}"
        DISK_E="${XPATH_ELEMENTS[i++]}"
        DISK_F="${XPATH_ELEMENTS[i++]}"
    fi
    if boolTrue "DEBUG_oneVmSnapshots"; then
        splog "oneVmSnapshots() VM_ID:$VM_ID (U:$VM_UID/G:$VM_GID) vmsnap=$snapshot_id disk:$disk_id SNAPSHOT_IDs:${SNAPSHOT_IDS[@]} HYPERVISOR_IDs:${HYPERVISOR_IDS[@]}"
        splog "$CONTEXT_DISK_ID A:$DISK_A B:$DISK_B C:$DISK_C D:$DISK_D E:$DISK_E F:$DISK_F"
    fi
}

oneSnapshotLookup()
{
    #VM:51-DISK:0-VMSNAP:0
    local arr=(${1//-/ }) volumeName=
    declare -A snap
    for e in ${arr[@]}; do
       snap["${e%%:*}"]="${e#*:}"
    done
    # SPSNAPSHOT:<StorPool snashotName>
    if [ -n "${snap["SPSNAPSHOT"]}" ]; then
        SNAPSHOT_NAME="${1#*SPSNAPSHOT:}"
        if boolTrue "DEBUG_oneSnapshotLookup"; then
            splog "oneSnapshotLookup($1): full SNAPSHOT_NAME:$SNAPSHOT_NAME"
        fi
        return 0
    fi
    oneVmSnapshots "${snap["VM"]}" "${snap["VMSNAP"]}" "${snap["DISK"]}"
    if [ "${DISK_B^^}" = "BLOCK" ] && [ "${DISK_C^^}" = "BLOCK" ]; then
        volumeName="${DISK_D#*/}"
        if [ "${DISK_E^^}" = "YES" ]; then
            volumeName+="-${snap["VM"]}-${snap["DISK"]}"
        fi
    elif [ "${DISK_B^^}" = "FILE" ] && [ "${DISK_C^^}" = "FS" ]; then
        volumeName="${ONE_PX}-sys-${snap["VM"]}-${snap["DISK"]}-raw"
    elif [ "${CONTEXT_DISK_ID}" = "${snap["DISK"]}" ]; then
        # ONE can't register image with size less than 1MB
        # but it is possible to have bigger contextualization
        volumeName="${ONE_PX}-sys-${snap["VM"]}-${snap["DISK"]}-iso"
    fi
    if [ -n "$volumeName" ] && [ ${#HYPERVISOR_IDS[@]} -gt 0 ]; then
        SNAPSHOT_NAME="${volumeName}-${HYPERVISOR_IDS[0]}"
        if boolTrue "DEBUG_oneSnapshotLookup"; then
            splog "oneSnapshotLookup($1): VM SNAPSHOT_NAME:$SNAPSHOT_NAME"
        fi
        return 0
    fi
    return 1
}

storpoolVmVolumes()
{
    vmVolumes=
    while read -u 7 vol; do
        vmVolumes+="$vol "
    done 7< <(storpoolRetry -j volume list |\
        jq -r --arg t "$1" --arg v "$2" '.data[]|select(.tags[$t]==$v)|.name'
    )
    splog "storpoolVmVolumes($1,$2) $vmVolumes"
}


forceDetachOther()
{
    local VM_ID="$1" DST_HOST="$2" VOLUME="$3"
    local SP_CLIENT="$(storpoolClientId "$DST_HOST" "$COMMON_DOMAIN")"
    if [ -z "$SP_CLIENT" ]; then
        splog "Error: SP_CLIENT is empty!"
        return 1
    fi
    if [ -n "$VOLUME" ]; then
        vmVolumes="$VOLUME"
    else
        if boolTrue "FORCE_DETACH_BY_TAG"; then
            storpoolVmVolumes "$VM_TAG" "$VM_ID"
        else
            oneVmVolumes "$VM_ID"
        fi
    fi
    if [ -z "$vmVolumes" ]; then
        splog "Error: vmVolumes is empty!"
        return 1
    fi
    if boolTrue "DEBUG_forceDetachOther"; then
        splog "forceDetachOther($1,$2${3:+,$3}) $vmVolumes"
    fi
    local jqStr=
    for vol in $vmVolumes; do
        [ -z "$jqStr" ] || jqStr+=" or "
        jqStr+=".volume==\"$vol\""
    done
    while read -u 6 client volume; do
        if [ $client -ne $SP_CLIENT ]; then
            storpoolRetry detach volume "$volume" client "$client" force yes >/dev/null
        fi
    done 6< <(storpoolRetry -j attach list |\
        jq -r ".data[]|select($jqStr)|(.client|tostring) + \" \" + .volume")
}

# disable sp checkpoint transfer from file to block device
# when the new code is enabled
if boolTrue "SP_CHECKPOINT_BD"; then
    SP_CHECKPOINT=
fi

# backward compatibility
type -t multiline_exec_and_log >/dev/null || function multiline_exec_and_log(){ exec_and_log "$@"; }

if type -t ssh_forward >/dev/null; then
    export SSH_AUTH_SOCK
    if boolTrue "DEBUG_COMMON"; then
        splog "ssh_forward upstream"
    fi
else
    if boolTrue "DEBUG_COMMON"; then
        splog "ssh_forward wrapper"
    fi
    function ssh_forward(){ "$@"; }
fi
# redefine own version of ssh_make_path()
function ssh_make_path
{
    [ -z "$3" ] || splog "ssh_make_path($1, $2, $3)"
    SSH_EXEC_ERR=`$SSH "$1" bash -s 2>&1 1>/dev/null <<EOF
set -e -o pipefail
if [ ! -d "$2" ]; then
   mkdir -p "$2"
fi
if [ -n "$3" ]; then
   monitor_file="$(dirname $2)/.monitor"
   if [ -f "\\$monitor_file" ]; then
       monitor="\\$(<"\\$monitor_file" 2>/dev/null)"
   fi
   [ "\\$monitor" = "$3" ] || echo "$3" > "\\$monitor_file" 2>&1
fi
EOF`
    SSH_EXEC_RC=$?
    if [ $SSH_EXEC_RC -ne 0 ]; then
        error_message "Error creating directory $2 at $1: $SSH_EXEC_ERR"
        exit $SSH_EXEC_RC
    fi
}

hostReachable()
{
    ping -i 0.3 -c ${PING_COUNT:-2} "$1" >/dev/null
}

