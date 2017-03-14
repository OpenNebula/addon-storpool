# -------------------------------------------------------------------------- #
# Copyright 2015-2016, StorPool (storpool.com)                               #
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
    logger -t "${LOG_PREFIX:-tm}_sp_${0##*/}[$$]" "${DEBUG_LINENO:+[${BASH_LINENO[-2]}]}$*"
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

if [ -f "$TMCOMMON" ]; then
	source "$TMCOMMON"
fi

#-------------------------------------------------------------------------------
# load local configuration parameters
#-------------------------------------------------------------------------------

DEBUG_COMMON=
DEBUG_TRAPS=
DEBUG_SP_RUN_CMD=1
DEBUG_SP_RUN_CMD_VERBOSE=
DEBUG_oneVmInfo=
DEBUG_oneDatastoreInfo=
DEBUG_oneTemplateInfo=
DEBUG_oneDsDriverAction=

sprcfile="${TMCOMMON%/*}/../addon-storpoolrc"

if [ -f "$sprcfile" ]; then
    source "$sprcfile"
fi
if [ -f "/etc/storpool/addon-storpool.conf" ]; then
    source "/etc/storpool/addon-storpool.conf"
fi

function boolTrue()
{
   case "$1" in
       1|y|Y|yes|Yes|YES|true|True|TRUE|on|On|ON)
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
    if boolTrue "$DEBUG_COMMON"; then
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
    if boolTrue "$DEBUG_TRAPS"; then
        splog "trapReset"
    fi

    trap "$TRAP_CMD" EXIT TERM INT HUP
}
function trapAdd()
{
    local _trap_cmd="$1"
    if boolTrue "$DEBUG_TRAPS"; then
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
    trap "$TRAP_CMD" EXIT TERM INT HUP
}
function trapDel()
{
    local _trap_cmd="$1"
    if boolTrue "$DEBUG_TRAPS"; then
        splog "trapDel:$*"
    fi
    TRAP_CMD="${TRAP_CMD/${_trap_cmd};/}"
    if [ -n "$TRAP_CMD" ]; then
        if boolTrue "$DEBUG_TRAPS"; then
            splog "trapDel:$TRAP_CMD"
        fi
        trap "$TRAP_CMD" EXIT TERM INT HUP
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

function getHostHostname()
{
	local _name="$1"
	local _self="$(dirname $0)"
	local _XPATH="$(lookup_file "datastore/xpath.rb" "$_self")"
	
	unset XPATH_ELEMENTS i
	while IFS= read -r -d '' element; do
		XPATH_ELEMENTS[i++]="$element"
	done < <(onehost show "$_name" -x | "$_XPATH" --stdin \
                            /HOST/ID \
                            /HOST/NAME \
                            /HOST/STATE \
                            /HOST/TEMPLATE/HOSTNAME 2>/dev/null)
	unset i
	HOST_ID="${XPATH_ELEMENTS[i++]}"
	HOST_NAME="${XPATH_ELEMENTS[i++]}"
	HOST_STATE="${XPATH_ELEMENTS[i++]}"
	HOST_HOSTNAME="${XPATH_ELEMENTS[i++]}"
	if boolTrue "$DEBUG_COMMON"; then
		splog "getHostHostname($_name): ID:$HOST_ID NAME:$HOST_NAME STATE:$HOST_STATE HOSTNAME:$HOST_HOSTNAME"
	fi
	if [ -n "$HOST_HOSTNAME" ]; then
		if [ "$_name" != "$HOST_HOSTNAME" ] || boolTrue "$DEBUG_COMMON"; then
			splog "getHostHostname($_name): Found '$HOST_HOSTNAME'"
		fi
		echo $HOST_HOSTNAME
	else
		splog "getHostHostname($_name): Not Found."
		echo $_name
	fi
}

function storpoolClientId()
{
    local hst="$1" COMMON_DOMAIN="${2:-$COMMON_DOMAIN}"
    local result bridge
    hst="$(getHostHostname "$hst")"
    result=$(/usr/sbin/storpool_confget -s "$hst" | grep SP_OURID | cut -d '=' -f 2 | tail -n 1)
    if [ "$result" = "" ]; then
        if [ -n "$COMMON_DOMAIN" ]; then
            result=$(/usr/sbin/storpool_confget -s "${hst}.${COMMON_DOMAIN}" | grep SP_OURID | cut -d '=' -f 2 | tail -n 1)
        fi
    fi
    if [ "$result" = "" ]; then
        for bridge in $BRIDGE_LIST; do
            result=$(ssh "$bridge" /usr/sbin/storpool_confget -s "$hst" | grep SP_OURID | cut -d '=' -f 2 | tail -n 1)
            if [ -n "$result" ]; then
                break
            fi
            if [ -n "$COMMON_DOMAIN" ]; then
                result=$(ssh "$bridge" /usr/sbin/storpool_confget -s "${hst}.${COMMON_DOMAIN}" | grep SP_OURID | cut -d '=' -f 2 | tail -n 1)
                if [ -n "$result" ]; then
                    break
                fi
            fi
        done
        if [ "$result" = "" ] && [ -n "$CLONE_GW" ]; then
            result=$(ssh "$CLONE_GW" /usr/sbin/storpool_confget -s "\$(hostname)" | grep SP_OURID | cut -d '=' -f 2 | tail -n 1) #"
            splog "CLONE_GW=$CLONE_GW CLIENT_ID=$result"
        fi
        if [ "$result" = "" ]; then
            result=$(ssh "$hst" /usr/sbin/storpool_confget | grep SP_OURID | cut -d '=' -f 2 | tail -n 1)
            splog "$hst CLIENT_ID=$result"
        fi
    fi
    if boolTrue "$DEBUG_COMMON"; then
        splog "storpoolClientId($1): SP_OURID:${result}${bridge:+ BRIDGE_HOST:$bridge}${COMMON_DOMAIN:+ COMMON_DOMAIN=$COMMON_DOMAIN}"
    fi
    echo $result
}

function storpoolRetry() {
    if boolTrue "$DEBUG_COMMON"; then
        splog "SP_API_HTTP_HOST=$SP_API_HTTP_HOST"
    fi
    if boolTrue "$DEBUG_SP_RUN_CMD"; then
        if boolTrue "$DEBUG_SP_RUN_CMD_VERBOSE"; then
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
        if storpool "$@"; then
            break
        fi
        if boolTrue "$_SOFT_FAIL" ]; then
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

function storpoolWaitLink()
{
    local _SP_LINK="$1" _SP_HOST="$2"
    local _REMOTE=$(cat <<EOF
    # storpoolWaitLink
    t=15
    while [ ! -L "$_SP_LINK" ]; do
        if [ \$t -lt 1 ]; then
            splog "Timeout waiting for $_SP_LINK"
            echo "Timeout waiting for $_SP_LINK" >&2
            exit -1
        fi
        sleep .5
        t=\$((t-1))
    done

    endmsg="storpoolWaitLink $_SP_LINK (\$t)"
EOF
)
#    splog "storpoolWaitLink $_SP_LINK${_SP_HOST:+ on $_SP_HOST}"
    if [ -n "$_SP_HOST" ]; then
        ssh_exec_and_log "$_SP_HOST" "${REMOTE_HDR}${_REMOTE}$REMOTE_FTR" \
            "Error symlink '$_SP_LINK' not found. Giving up"
    else
        t=15
        while [ ! -L "$_SP_LINK" ]; do
            if [ $t -lt 1 ]; then
                splog "Timeout waiting for $_SP_LINK"
                echo "Timeout waiting for $_SP_LINK" >&2
                exit -1
            fi
            sleep .5
            t=$((t-1))
        done
        splog "END storpoolWaitLink $_SP_LINK ($t)"
    fi
}

function storpoolTemplate()
{
    local _SP_TEMPLATE="$1"
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

    if [ -n "$_SP_TEMPLATE" ] && [ -n "$SP_REPLICATION" ] && [ -n "$SP_PLACEALL" ] && [ -n "$SP_PLACETAIL" ]; then
        storpoolRetry template "$_SP_TEMPLATE" replication "$SP_REPLICATION" placeAll "$SP_PLACEALL" placeTail "$SP_PLACETAIL" ${SP_IOPS:+iops "$SP_IOPS"} ${SP_BW:+bw "$SP_BW"} >/dev/null
    fi
}

function storpoolVolumeExists()
{
    local _SP_VOL="$1"
    if [ -n "$(storpoolRetry -j volume list | jq -r ".data[]|select(.name == \"$_SP_VOL\")")" ]; then #"
        return 0
    fi
    return 1
}

function storpoolVolumeCreate()
{
    local _SP_VOL="$1" _SP_SIZE="$2" _SP_TEMPLATE="$3"
    storpoolRetry volume "$_SP_VOL" size "${_SP_SIZE}" ${_SP_TEMPLATE:+template "$_SP_TEMPLATE"} >/dev/null
}

function storpoolVolumeContains()
{
    local _SP_VOL="$1" vName
    while read vName; do
        echo "${vName//\"/}"
    done < <(storpoolRetry -j volume list | jq -r ".data|map(select(.name|contains(\"${_SP_VOL}\")))|.[]|[.name]|@csv")
}

function storpoolVolumeSnapshotsDelete()
{
    local _SP_VOL_SNAPSHOTS="$1"
    storpoolRetry -j snapshot list | \
        jq -r ".data|map(select(.name|contains(\"${_SP_VOL_SNAPSHOTS}\")))|.[]|[.name]|@csv" | \
        while read name; do
            name="${name//\"/}"
            storpoolSnapshotDelete "$name"
        done
}

function storpoolVolumeDelete()
{
    local _SP_VOL="$1" _FORCE="$2" _SNAPSHOTS="$3"
    if storpoolVolumeExists "$_SP_VOL"; then

        storpoolVolumeDetach "$_SP_VOL" "$_FORCE" "" "all"

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
    local _SP_OLD="$1" _SP_NEW="$2" _SP_TEMPLATE="$3"
    storpoolRetry volume "$_SP_OLD" rename "$_SP_NEW" ${_SP_TEMPLATE:+template "$_SP_TEMPLATE"} >/dev/null
}

function storpoolVolumeClone()
{
    local _SP_PARENT="$1" _SP_VOL="$2" _SP_TEMPLATE="$3"

    storpoolRetry volume "$_SP_VOL" baseOn "$_SP_PARENT" ${_SP_TEMPLATE:+template "$_SP_TEMPLATE"} >/dev/null
}

function storpoolVolumeResize()
{
    local _SP_VOL="$1" _SP_SIZE="$2"

    storpoolRetry volume "$_SP_VOL" size "${_SP_SIZE}M" >/dev/null
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

    trapAdd "storpoolRetry detach ${_SP_TARGET} \"$_SP_VOL\" ${_SP_CLIENT:-here}"

    storpoolWaitLink "/dev/storpool/$_SP_VOL" "$_SP_HOST"

    trapDel "storpoolRetry detach ${_SP_TARGET} \"$_SP_VOL\" ${_SP_CLIENT:-here}"
}

function storpoolVolumeDetach()
{
    local _SP_VOL="$1" _FORCE="$2" _SP_HOST="$3" _DETACH_ALL="$4" _SOFT_FAIL="$5"
    local _SP_CLIENT volume client
#    splog "storpoolVolumeDetach($*)"
    if [ "$_DETACH_ALL" = "all" ]; then
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
    while IFS=',' read volume client snapshot; do
        if [ "$_SOFT_FAIL" = "YES" ]; then
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

function storpoolVolumeGetParent()
{
    local _SP_VOL="$1" parentName
    parentName=$(storpoolRetry -j volume list | jq -r ".data|map(select(.name==\"$_SP_VOL\"))|.[]|[.parentName]|@csv") #"
    echo "${parentName//\"/}"
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

function storpoolSnapshotRevert()
{
    local _SP_SNAPSHOT="$1" _SP_VOL="$2"
    local _SP_TMP="$(date +%s)-$(mktemp --dry-run XXXXXXXX)"

    storpoolRetry volume "$_SP_VOL" rename "${_SP_VOL}-${_SP_TMP}" >/dev/null

    trapAdd "storpool volume \"$_SP_TMP\" rename \"$_SP_VOL\""

    storpoolRetry volume "$_SP_VOL" parent "$_SP_SNAPSHOT" >/dev/null

    trapReset

    storpoolVolumeDelete "${_SP_VOL}-$_SP_TMP"
}

function storpoolSnapshotClone()
{
    local _SP_SNAP="$1" _SP_VOL="$2" _SP_TEMPLATE="$3"

    storpoolRetry volume "$_SP_VOL" parent "$_SP_SNAP" ${_SP_TEMPLATE:+template "$_SP_TEMPLATE"} >/dev/null
}


function oneSymlink()
{
    local _host="$1" _src="$2"
    shift 2
    local _dst="$*"
    splog "symlink $_src -> ${_host}:{${_dst//[[:space:]]/,}}"
    local remote_cmd=$(cat <<EOF
    #_SYMLINK
    for dst in $_dst; do
        dst_dir=\$(dirname \$dst)
        if [ -d "\$dst_dir" ]; then
            true
        else
            splog "mkdir -p \$dst_dir"
            trap "splog \"Can't create destination dir \$dst_dir (\$?)\"" EXIT TERM INT HUP
            splog "mkdir -p \$dst_dir"
            mkdir -p "\$dst_dir"
            trap - EXIT TERM INT HUP
        fi
        if [ -n "$MONITOR_TM_MAD" ]; then
            [ -f "\$dst_dir/../.monitor" ] || echo "storpool" >"\$dst_dir/../.monitor"
        fi
        splog "ln -sf $_src \$dst"
        ln -sf "$_src" "\$dst"
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
        . "${SCRIPTS_REMOTE_DIR}/vmm/kvm/kvmrc"
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
        . "${SCRIPTS_REMOTE_DIR}/vmm/kvm/kvmrc"
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
    local template="one-ds-$_dsid"
    local volume="one-sys-${_vmid}-checkpoint"
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
    local volume="one-sys-${_vmid}-checkpoint"
    local sp_link="/dev/storpool/$volume"

    SP_COMPRESSION="${SP_COMPRESSION:-lz4}"

    local remote_cmd=$(cat <<EOF
    # checkpoint Restore
    if [ -f "$checkpoint" ]; then
        splog "file exists $checkpoint"
    else
        mkdir -p "$_path"

        [ -f "$_path/.monitor" ] || echo "storpool" >"$_path/.monitor"

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

function lookup_file()
{
    local _FILE="$1" _CWD="${2:-$PWD}"
    local _PATH=
    for _PATH in "$_CWD/"{,../,../../,../../../,remotes/}; do
        if [ -f "${_PATH}${_FILE}" ]; then
            echo "${_PATH}${_FILE}"
            break;
        fi
    done
}

function oneVmInfo()
{
    local _VM_ID="$1" _DISK_ID="$2"
    local _XPATH="$(lookup_file "datastore/xpath.rb" "${TM_PATH}")"

    unset i XPATH_ELEMENTS
    while IFS= read -r -d '' element; do
        XPATH_ELEMENTS[i++]="$element"
        done < <(onevm show -x "$_VM_ID" | "$_XPATH" --stdin \
                            /VM/DEPLOY_ID \
                            /VM/STATE \
                            /VM/LCM_STATE \
                            /VM/CONTEXT/DISK_ID \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/SOURCE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/IMAGE_ID \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/IMAGE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/CLONE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/SAVE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/TYPE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/READONLY \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/PERSISTENT \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/HOTPLUG_SAVE_AS \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/HOTPLUG_SAVE_AS_ACTIVE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/HOTPLUG_SAVE_AS_SOURCE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/SIZE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/ORIGINAL_SIZE)

    unset i
    DEPLOY_ID="${XPATH_ELEMENTS[i++]}"
    VMSTATE="${XPATH_ELEMENTS[i++]}"
    LCM_STATE="${XPATH_ELEMENTS[i++]}"
    CONTEXT_DISK_ID="${XPATH_ELEMENTS[i++]}"
    SOURCE="${XPATH_ELEMENTS[i++]}"
    IMAGE_ID="${XPATH_ELEMENTS[i++]}"
    IMAGE="${XPATH_ELEMENTS[i++]}"
    CLONE="${XPATH_ELEMENTS[i++]}"
    SAVE="${XPATH_ELEMENTS[i++]}"
    TYPE="${XPATH_ELEMENTS[i++]}"
    READONLY="${XPATH_ELEMENTS[i++]}"
    PERSISTENT="${XPATH_ELEMENTS[i++]}"
    HOTPLUG_SAVE_AS="${XPATH_ELEMENTS[i++]}"
    HOTPLUG_SAVE_AS_ACTIVE="${XPATH_ELEMENTS[i++]}"
    HOTPLUG_SAVE_AS_SOURCE="${XPATH_ELEMENTS[i++]}"
    SIZE="${XPATH_ELEMENTS[i++]}"
    ORIGINAL_SIZE="${XPATH_ELEMENTS[i++]}"

    boolTrue "$DEBUG_oneVmInfo" || return

    splog "\
${VMSTATE:+VMSTATE=$VMSTATE }\
${LCM_STATE:+LCM_STATE=$LCM_STATE }\
${CONTEXT_DISK_ID:+CONTEXT_DISK_ID=$CONTEXT_DISK_ID }\
${SOURCE:+SOURCE=$SOURCE }\
${IMAGE_ID:+IMAGE_ID=$IMAGE_ID }\
${CLONE:+CLONE=$CLONE }\
${SAVE:+SAVE=$SAVE }\
${TYPE:+TYPE=$TYPE }\
${READONLY:+READONLY=$READONLY }\
${PERSISTENT:+PERSISTENT=$PERSISTENT }\
${IMAGE:+IMAGE=$IMAGE }\
"
    msg="${HOTPLUG_SAVE_AS:+HOTPLUG_SAVE_AS=$HOTPLUG_SAVE_AS }${HOTPLUG_SAVE_AS_ACTIVE:+HOTPLUG_SAVE_AS_ACTIVE=$HOTPLUG_SAVE_AS_ACTIVE }${HOTPLUG_SAVE_AS_SOURCE:+HOTPLUG_SAVE_AS_SOURCE=$HOTPLUG_SAVE_AS_SOURCE }"
    [ -n "$msg" ] && splog "$msg"
}

function oneDatastoreInfo()
{
    local _DS_ID="$1"
    local _XPATH="$(lookup_file "datastore/xpath.rb" "${TM_PATH}")"

    unset i XPATH_ELEMENTS
    while IFS= read -r -d '' element; do
        XPATH_ELEMENTS[i++]="$element"
        done < <(onedatastore show -x "$_DS_ID" | "$_XPATH" --stdin \
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
                            /DATASTORE/TEMPLATE/SP_IOPS \
                            /DATASTORE/TEMPLATE/SP_BW \
                            /DATASTORE/TEMPLATE/SP_SYSTEM \
                            /DATASTORE/TEMPLATE/SP_API_HTTP_HOST \
                            /DATASTORE/TEMPLATE/SP_API_HTTP_PORT \
                            /DATASTORE/TEMPLATE/SP_AUTH_TOKEN \
                            /DATASTORE/TEMPLATE/SP_CLONE_GW)
    unset i
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
    SP_IOPS="${XPATH_ELEMENTS[i++]:--}"
    SP_BW="${XPATH_ELEMENTS[i++]:--}"
    SP_SYSTEM="${XPATH_ELEMENTS[i++]}"
    SP_API_HTTP_HOST="${XPATH_ELEMENTS[i++]}"
    SP_API_HTTP_PORT="${XPATH_ELEMENTS[i++]}"
    SP_AUTH_TOKEN="${XPATH_ELEMENTS[i++]}"
    SP_CLONE_GW="${XPATH_ELEMENTS[i++]}"

    [ -n "$SP_API_HTTP_HOST" ] && export SP_API_HTTP_HOST || unset SP_API_HTTP_HOST
    [ -n "$SP_API_HTTP_PORT" ] && export SP_API_HTTP_PORT || unset SP_API_HTTP_PORT
    [ -n "$SP_AUTH_TOKEN" ] && export SP_AUTH_TOKEN || unset SP_AUTH_TOKEN

    boolTrue "$DEBUG_oneDatastoreInfo" || return

    _MSG="${DS_TYPE:+DS_TYPE=$DS_TYPE }${DS_TEMPLATE_TYPE:+TEMPLATE_TYPE=$DS_TEMPLATE_TYPE }"
    _MSG+="${DS_DISK_TYPE:+DISK_TYPE=$DS_DISK_TYPE }${DS_TM_MAD:+TM_MAD=$DS_TM_MAD }"
    _MSG+="${DS_BASE_PATH:+BASE_PATH=$DS_BASE_PATH }${DS_CLUSTER_ID:+CLUSTER_ID=$DS_CLUSTER_ID }"
    _MSG+="${DS_SHARED:+SHARED=$DS_SHARED }${SP_REPLICATION:+SP_REPLICATION=$SP_REPLICATION }"
    _MSG+="${SP_PLACEALL:+SP_PLACEALL=$SP_PLACEALL }${SP_PLACETAIL:+SP_PLACETAIL=$SP_PLACETAIL }"
    _MSG+="${SP_SYSTEM:+SP_SYSTEM=$SP_SYSTEM }${SP_CLONE_GW:+SP_CLONE_GW=$SP_CLONE_GW }"
    _MSG+="${EXPORT_BRIDGE_LIST:+EXPORT_BRIDGE_LIST=$EXPORT_BRIDGE_LIST }"
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
    local _XPATH="$(lookup_file "datastore/xpath.rb" "${TM_PATH}")"

    unset i XPATH_ELEMENTS
    while IFS= read -r -d '' element; do
        XPATH_ELEMENTS[i++]="$element"
        done < <("$_XPATH" -b "$_TEMPLATE" \
                    /VM/ID \
                    /VM/STATE \
                    /VM/LCM_STATE \
                    /VM/PREV_STATE \
                    /VM/TEMPLATE/CONTEXT/DISK_ID)
    unset i
    _VM_ID=${XPATH_ELEMENTS[i++]}
    _VM_STATE=${XPATH_ELEMENTS[i++]}
    _VM_LCM_STATE=${XPATH_ELEMENTS[i++]}
    _VM_PREV_STATE=${XPATH_ELEMENTS[i++]}
    _CONTEXT_DISK_ID=${XPATH_ELEMENTS[i++]}
    if boolTrue "$DEBUG_oneTemplateInfo"; then
        splog "VM_ID=$_VM_ID VM_STATE=$_VM_STATE VM_LCM_STATE=$_VM_LCM_STATE VM_PREV_STATE=$_VM_PREV_STATE CONTEXT_DISK_ID=$_CONTEXT_DISK_ID"
    fi

    _XPATH="$(lookup_file "datastore/xpath_multi.py" "${TM_PATH}")"
    unset i XPATH_ELEMENTS
    while read -r element; do
        XPATH_ELEMENTS[i++]="$element"
    done < <("$_XPATH" -b "$_TEMPLATE" \
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

    boolTrue "$DEBUG_oneTemplateInfo" || return

    splog "[oneTemplateInfo] disktm:$_DISK_TM_MAD ds:$_DISK_DATASTORE_ID disk:$_DISK_ID cluster:$_DISK_CLUSTER_ID src:$_DISK_SOURCE persistent:$_DISK_PERSISTENT type:$_DISK_TYPE clone:$_DISK_CLONE readonly:$_DISK_READONLY format:$_DISK_FORMAT"
#    echo $_TEMPLATE | base64 -d >/tmp/one-template-${_VM_ID}-${0##*/}-${_VM_STATE}.xml
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
                    /DS_DRIVER_ACTION_DATA/DATASTORE/CLUSTER_ID \
                    %m%/DS_DRIVER_ACTION_DATA/DATASTORE/CLUSTERS/ID \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TM_MAD \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/BRIDGE_LIST \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/EXPORT_BRIDGE_LIST \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_REPLICATION \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_PLACEALL \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_PLACETAIL \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_IOPS \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_BW \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_API_HTTP_HOST \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_API_HTTP_PORT \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_AUTH_TOKEN \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/SP_CLONE_GW \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/NO_DECOMPRESS \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/LIMIT_TRANSFER_BW \
                    /DS_DRIVER_ACTION_DATA/DATASTORE/TEMPLATE/TYPE \
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
                    /DS_DRIVER_ACTION_DATA/IMAGE/CLONES \
                    /DS_DRIVER_ACTION_DATA/IMAGE/TARGET_SNAPSHOT \
                    /DS_DRIVER_ACTION_DATA/IMAGE/SIZE)


    unset i
    BASE_PATH="${XPATH_ELEMENTS[i++]}"
    DATASTORE_ID="${XPATH_ELEMENTS[i++]}"
    CLUSTER_ID="${XPATH_ELEMENTS[i++]}"
    CLUSTERS_ID="${XPATH_ELEMENTS[i++]}"
    TM_MAD="${XPATH_ELEMENTS[i++]}"
    BRIDGE_LIST="${XPATH_ELEMENTS[i++]}"
    EXPORT_BRIDGE_LIST="${XPATH_ELEMENTS[i++]}"
    SP_REPLICATION="${XPATH_ELEMENTS[i++]:-2}"
    SP_PLACEALL="${XPATH_ELEMENTS[i++]}"
    SP_PLACETAIL="${XPATH_ELEMENTS[i++]}"
    SP_IOPS="${XPATH_ELEMENTS[i++]:--}"
    SP_BW="${XPATH_ELEMENTS[i++]:--}"
    SP_API_HTTP_HOST="${XPATH_ELEMENTS[i++]}"
    SP_API_HTTP_PORT="${XPATH_ELEMENTS[i++]}"
    SP_AUTH_TOKEN="${XPATH_ELEMENTS[i++]}"
    SP_CLONE_GW="${XPATH_ELEMENTS[i++]}"
    NO_DECOMPRESS="${XPATH_ELEMENTS[i++]}"
    LIMIT_TRANSFER_BW="${XPATH_ELEMENTS[i++]}"
    DS_TYPE="${XPATH_ELEMENTS[i++]}"
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
    CLONES="${XPATH_ELEMENTS[i++]}"
    TARGET_SNAPSHOT="${XPATH_ELEMENTS[i++]}"
    SIZE="${XPATH_ELEMENTS[i++]}"

    [ -n "$SP_API_HTTP_HOST" ] && export SP_API_HTTP_HOST || unset SP_API_HTTP_HOST
    [ -n "$SP_API_HTTP_PORT" ] && export SP_API_HTTP_PORT || unset SP_API_HTTP_PORT
    [ -n "$SP_AUTH_TOKEN" ] && export SP_AUTH_TOKEN || unset SP_AUTH_TOKEN

    boolTrue "$DEBUG_oneDsDriverAction" || return

    splog "\
${ID:+ID=$ID }\
${DATASTORE_ID:+DATASTORE_ID=$DATASTORE_ID }\
${CLUSTER_ID:+CLUSTER_ID=$CLUSTER_ID }\
${CLUSTERS_ID:+CLUSTERS_ID=$CLUSTERS_ID }\
${STATE:+STATE=$STATE }\
${SIZE:+SIZE=$SIZE }\
${SP_REPLICATION+SP_REPLICATION=$SP_REPLICATION }\
${SP_PLACEALL+SP_PLACEALL=$SP_PLACEALL }\
${SP_PLACETAIL+SP_PLACETAIL=$SP_PLACETAIL }\
${SP_IOPS+SP_IOPS=$SP_IOPS }\
${SP_BW+SP_BW=$SP_BW }\
${SP_API_HTTP_HOST+SP_API_HTTP_HOST=$SP_API_HTTP_HOST }\
${SP_API_HTTP_PORT+SP_API_HTTP_PORT=$SP_API_HTTP_PORT }\
${SP_AUTH_TOKEN+SP_AUTH_TOKEN=DEFINED }\
${SP_CLONE_GW+SP_CLONE_GW=$SP_CLONE_GW }\
${SOURCE:+SOURCE=$SOURCE }\
${PERSISTENT:+PERSISTENT=$PERSISTENT }\
${FSTYPE:+FSTYPE=$FSTYPE }\
${TYPE:+TYPE=$TYPE }\
${CLONE:+CLONE=$CLONE }\
${SAVE:+SAVE=$SAVE }\
${FORMAT:+FORMAT=$FORMAT }\
${DISK_TYPE:+DISK_TYPE=$DISK_TYPE }\
${CLONING_ID:+CLONING_ID=$CLONING_ID }\
${CLONING_OPS:+CLONING_OPS=$CLONING_OPS }\
${CLONES:+CLONES=$CLONES }\
${IMAGE_PATH:+IMAGE_PATH=$IMAGE_PATH }\
${BRIDGE_LIST:+BRIDGE_LIST=$BRIDGE_LIST }\
${EXPORT_BRIDGE_LIST:+EXPORT_BRIDGE_LIST=$EXPORT_BRIDGE_LIST }\
${DRIVER:+DRIVER=$DRIVER }\
${BASE_PATH:+BASE_PATH=$BASE_PATH }\
"
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

    boolTrue "$DEBUG_oneMarketDriverAction" || return

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
