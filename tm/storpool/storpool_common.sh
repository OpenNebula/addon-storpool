# -------------------------------------------------------------------------- #
# Copyright 2015, StorPool (storpool.com)                                    #
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
PATH=/bin:/sbin:/usr/bin:/usr/sbin:$PATH

#-------------------------------------------------------------------------------
# Set up the environment to source common tools
#-------------------------------------------------------------------------------

if [ -n "${ONE_LOCATION}" ]; then
    TMCOMMON="$ONE_LOCATION/var/remotes/tm/tm_common.sh"
else
    TMCOMMON=/var/lib/one/remotes/tm/tm_common.sh
fi

source "$TMCOMMON"

#-------------------------------------------------------------------------------
# syslog logger function
#-------------------------------------------------------------------------------

function splog()
{
    logger -t "tm_sp_${0##*/}" "$*"
}

function storpoolAction()
{
    local _ACTION="$1" _SRC_HOST="$2" _DST_HOST="$3" _SP_VOL="$4" _DST_PATH="$5"  _SP_PARENT="$6" _SP_TEMPLATE="$7" _SP_SIZE="$8"
    splog "$_ACTION $_SRC_HOST $_DST_HOST $_SP_VOL $_DST_PATH $_SP_PARENT $_SP_TEMPLATE $_SP_SIZE"
    local _SP_LINK="/dev/storpool/$_SP_VOL"
    local _DST_DIR="${_DST_PATH%%disk*}"
    local _SP_TMP=$(date +%s)-$(mktemp --dry-run XXXXXXXX)
#    splog "SP_LINK=$_SP_LINK DST_DIR=$_DST_DIR"
    _SP_TEMPLATE="${_SP_TEMPLATE:+template $_SP_TEMPLATE}"

    local _BEGIN=$(cat <<EOF
    #_BEGIN
    set -e
    export PATH=/bin:/usr/bin:/sbin:/usr/sbin:\$PATH
    splog(){ logger -t "tm_sp_${0##*/}_${_ACTION}" "\$*"; }
EOF
)
    local _END=$(cat <<EOF
    #_END
    splog "END $_ACTION"
EOF
)
    local _TEMPLATE=$(cat <<EOF
    #_TEMPLATE
    if [ -n "$_SP_TEMPLATE" ] && [ -n "$SP_REPLICATION" ] && [ -n "$SP_PLACEALL" ] && [ -n "$SP_PLACETAIL" ]; then
        splog "$_SP_TEMPLATE replication $SP_REPLICATION placeAll $SP_PLACEALL placeTail $SP_PLACETAIL"
        storpool $_SP_TEMPLATE replication "$SP_REPLICATION" placeAll "$SP_PLACEALL" placeTail "$SP_PLACETAIL"
    fi
EOF
)
    local _CREATE=$(cat <<EOF
    #_CREATE
    splog "volume $_SP_VOL size ${_SP_SIZE} $_SP_TEMPLATE"
    storpool volume "$_SP_VOL" size "${_SP_SIZE}" $_SP_TEMPLATE
EOF
)
    local _RMLINK=$(cat <<EOF
    #_RMLINK
    if [ -L "$_DST_PATH" ]; then
        splog "rm -f $_DST_PATH"
        rm -f "$_DST_PATH"
    fi
EOF
)
    local _DETACH_ALL=$(cat <<EOF
    #_DETACH_ALL
    if storpool attach list | grep -q " $_SP_VOL " &>/dev/null; then
        splog "detach volume $_SP_VOL all"
        storpool detach volume "$_SP_VOL" all
    else
        splog "volume not attached $_SP_VOL"
    fi
EOF
)
    local _DETACH_HERE=$(cat <<EOF
    #_DETACH_HERE
    splog "detach volume $_SP_VOL here"
    storpool detach volume "$_SP_VOL" here
EOF
)
    local _ATTACH=$(cat <<EOF
    #_ATTACH
    splog "attach volume $_SP_VOL here"
    storpool attach volume "$_SP_VOL" here

    trap 'storpool detach volume "$_SP_VOL" here' EXIT TERM INT HUP

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

    trap - EXIT TERM INT HUP
EOF
)
    local _SYMLINK=$(cat <<EOF
    #_SYMLINK
    if [ -d "$_DST_DIR" ]; then
        splog "rm -f $_DST_PATH"
        rm -f "$_DST_PATH"
    else
        splog "mkdir -p $_DST_DIR"
        mkdir -p "$_DST_DIR"
    fi

    splog "ln -s $_SP_LINK $_DST_PATH"
    ln -s "$_SP_LINK" "$_DST_PATH"
EOF
)
    local _DELVOL=$(cat <<EOF
    #_DELVOL
    if storpool volume "$_SP_VOL" info &>/dev/null; then
        splog "delete $_SP_VOL"
        storpool volume "$_SP_VOL" delete "$SP_VOL"
    fi
EOF
)
    local _DELVOL_NONPERSISTENT=$(cat <<EOF
    #_DELVOL_NONPERSISTENT
    if [ "$_SP_PARENT" != "YES" ]; then
        if storpool volume "$_SP_VOL" info &>/dev/null; then
            splog "delete volume $_SP_VOL"
            storpool volume "$_SP_VOL" delete "$_SP_VOL"
        fi
    fi
EOF
)
    local _DELVOL_DETACH=$(cat <<EOF
    #_DELVOL_DETACH
    if storpool volume "$SP_VOL" info &>/dev/null; then
        if storpool attach list | grep "$SP_VOL"; then
            splog "detach volume $SP_VOL"
            storpool detach volume "$SP_VOL" all
        fi
        splog "delete $SP_VOL"
        storpool volume "$SP_VOL" delete "$SP_VOL"
    fi

EOF
)
    local _CLONE=$(cat <<EOF
    #_CLONE
    if [ "$_DST_PATH" = "-1" ]; then
        splog "volume $_SP_VOL parent $_SP_PARENT $_SP_TEMPLATE"
        storpool volume "$_SP_VOL" parent "$_SP_PARENT" $_SP_TEMPLATE
    else
        splog "volume $_SP_VOL baseOn $_SP_PARENT $_SP_TEMPLATE"
        storpool volume "$_SP_VOL" baseOn "$_SP_PARENT" $_SP_TEMPLATE
    fi

EOF
)
    local _RESIZE=$(cat <<EOF
    #_RESIZE
    if [ -n "$SIZE" ]; then
        ORIGINAL_SIZE=${ORIGINAL_SIZE:-0}
        if [ "$SIZE" -ge "$ORIGINAL_SIZE" ]; then
            splog "volume $_SP_VOL size ${SIZE}M"
            storpool volume "$_SP_VOL" size "${SIZE}M"
        fi
    fi

EOF
)
    local _RENAME=$(cat <<EOF
    #_RENAME
    splog "volume $_SP_PARENT rename $_SP_VOL $_SP_TEMPLATE"
    storpool volume "$_SP_PARENT" rename "$_SP_VOL" $_SP_TEMPLATE
EOF
)
    local _RENAME_COND=$(cat <<EOF
    #_RENAME_COND
    if [ -n "$_SP_SIZE" ]; then
        splog "volume $_SP_VOL rename $_SP_PARENT $_SP_TEMPLATE"
        storpool volume "$_SP_VOL" rename "$_SP_PARENT" $_SP_TEMPLATE
    fi
EOF
)
    local _EXTRA=$(cat <<EOF
    #_EXTRA
    splog "EXTRA_CMD:$EXTRA_CMD"
    $EXTRA_CMD
EOF
)
    local _SNAPSHOT=$(cat <<EOF
    #_SNAPSHOT
    splog "volume $_SP_VOL snapshot $_SP_PARENT"
    storpool volume "$_SP_VOL" snapshot "$_SP_PARENT"
EOF
)
    local _SNAPREVERT=$(cat <<EOF
    #_SNAPREVERT
    SP_TMP=\$(date +%s)-\$(mktemp --dry-run XXXXXXXX)
    splog "volume $_SP_VOL rename $_SP_VOL-\$SP_TMP"
    storpool volume "$_SP_VOL" rename "$_SP_VOL-\$SP_TMP"

    trap 'storpool volume "$_SP_VOL-\$SP_TMP" rename "$_SP_VOL"' EXIT TERM INT HUP

    splog "volume $_SP_VOL parent $_SP_PARENT"
    storpool volume "$_SP_VOL" parent "$_SP_PARENT"

    trap - EXIT TERM INT HUP

    splog "volume $_SP_VOL-\$SP_TMP delete $_SP_VOL-\$SP_TMP"
    storpool volume "$_SP_VOL-\$SP_TMP" delete "$_SP_VOL-\$SP_TMP"
EOF
)
    local _CMD= _HOST=
    case "$_ACTION" in
        CLONE)
            _HOST="$_DST_HOST"
            _CMD="$_BEGIN$_DELVOL$_CLONE$_RESIZE$_ATTACH$_SYMLINK"
        ;;
        CPDS)
            _HOST="$_SRC_HOST"
            _CMD="$_BEGIN$_DELVOL$_CLONE"
        ;;
        DELETE)
            _HOST="$_DST_HOST"
            _CMD="$_BEGIN$_DETACH_ALL$_DELVOL_NONPERSISTENT$_RMLINK"
        ;;
        LN)
            _HOST="$_DST_HOST"
            _CMD="$_BEGIN$_RESIZE$_ATTACH$_SYMLINK"
        ;;
        DETACH)
            _HOST="$_SRC_HOST"
            _CMD="$_BEGIN$_DETACH_ALL"
        ;;
        ATTACH)
            _HOST="$_DST_HOST"
            _CMD="$_BEGIN$_ATTACH$_SYMLINK"
        ;;
        MVDS)
            _HOST="$_SRC_HOST"
            _CMD="$_BEGIN$_RMLINK$_DETACH_ALL$_RENAME_COND"
        ;;
        DETACH_HERE)
            _HOST="$_SRC_HOST"
            _CMD="$_BEGIN$_DETACH_HERE"
        ;;
        ATTACHDETACH)
            attachdetach "$_SRC_HOST" "$_DST_HOST" "$_SP_VOL" "$_DST_PATH" "ATTACH"
            attachdetach "$_SRC_HOST" "$_DST_HOST" "$_SP_VOL" "$_DST_PATH" "DETACH"
        ;;
        MKIMAGE)
            _HOST="$_DST_HOST"
            _CMD="$_BEGIN$_TEMPLATE$_CREATE$_ATTACH$_SYMLINK$_EXTRA"
        ;;
        PRE_CONTEXT)
            _HOST="$_DST_HOST"
            _CMD="$_BEGIN$_DELVOL_DETACH$_TEMPLATE$_CREATE$_ATTACH$_SYMLINK$_EXTRA"
        ;;
        SNAPSHOT)
            _HOST="$_DST_HOST"
            _CMD="$_BEGIN$_SNAPSHOT"
        ;;
        DELSNAP)
            _HOST="$_DST_HOST"
            _CMD="$_BEGIN$_DELSNAP"
        ;;
        SNAPREVERT)
            _HOST="$_DST_HOST"
            _CMD="$_BEGIN$_DELSNAP"
        ;;
        *)
    esac
    if [ -n "$_CMD" ]; then
#        echo "$_CMD" >/tmp/tm_${0##*/}_${_ACTION}-$(date +%s).sh
        if [ -n "$_HOST" ]; then
            splog "run $_ACTION on $_HOST ($_DST_PATH)"
            ssh_exec_and_log "$_HOST" "$_CMD$_END" \
                 "Error processing $_ACTION on $_HOST($_DST_PATH)"
        else
            splog "run $_ACTION ($_DST_PATH)"
            exec_and_log "$_CMD$_END" \
                 "Error processing $_ACTION on $_HOST($_DST_PATH)"
        fi
    fi
}

function lookup_file()
{
    local _FILE="$1" _CWD="${2:-$PWD}"
    local _PATH=
    for _PATH in "$_CWD/"{,../,../../,../../../}; do
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
                            /VM/STATE \
                            /VM/LCM_STATE \
                            /VM/CONTEXT/DISK_ID \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/SOURCE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/IMAGE_ID \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/IMAGE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/CLONE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/PERSISTENT \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/HOTPLUG_SAVE_AS \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/HOTPLUG_SAVE_AS_ACTIVE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/HOTPLUG_SAVE_AS_SOURCE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/SIZE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/ORIGINAL_SIZE)

    unset i
    VMSTATE="${XPATH_ELEMENTS[i++]}"
    LCM_STATE="${XPATH_ELEMENTS[i++]}"
    CONTEXT_DISK_ID="${XPATH_ELEMENTS[i++]}"
    SOURCE="${XPATH_ELEMENTS[i++]}"
    IMAGE_ID="${XPATH_ELEMENTS[i++]}"
    IMAGE="${XPATH_ELEMENTS[i++]}"
    CLONE="${XPATH_ELEMENTS[i++]}"
    PERSISTENT="${XPATH_ELEMENTS[i++]}"
    HOTPLUG_SAVE_AS="${XPATH_ELEMENTS[i++]}"
    HOTPLUG_SAVE_AS_ACTIVE="${XPATH_ELEMENTS[i++]}"
    HOTPLUG_SAVE_AS_SOURCE="${XPATH_ELEMENTS[i++]}"
    SIZE="${XPATH_ELEMENTS[i++]}"
    ORIGINAL_SIZE="${XPATH_ELEMENTS[i++]}"

#    splog "\
#${VMSTATE:+VMSTATE=$VMSTATE }\
#${LCM_STATE:+LCM_STATE=$LCM_STATE }\
#${CONTEXT_DISK_ID:+CONTEXT_DISK_ID=$CONTEXT_DISK_ID }\
#${SOURCE:+SOURCE=$SOURCE }\
#${IMAGE_ID:+IMAGE_ID=$IMAGE_ID }\
#${CLONE:+CLONE=$CLONE }\
#${PERSISTENT:+PERSISTENT=$PERSISTENT }\
#${IMAGE:+IMAGE=$IMAGE }\
#"
#    msg="${HOTPLUG_SAVE_AS:+HOTPLUG_SAVE_AS=$HOTPLUG_SAVE_AS }${HOTPLUG_SAVE_AS_ACTIVE:+HOTPLUG_SAVE_AS_ACTIVE=$HOTPLUG_SAVE_AS_ACTIVE }${HOTPLUG_SAVE_AS_SOURCE:+HOTPLUG_SAVE_AS_SOURCE=$HOTPLUG_SAVE_AS_SOURCE }"
#    [ -n "$msg" ] && splog "$msg"
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
                            /DATASTORE/TEMPLATE/SP_REPLICATION \
                            /DATASTORE/TEMPLATE/SP_PLACEALL \
                            /DATASTORE/TEMPLATE/SP_PLACETAIL \
                            /DATASTORE/TEMPLATE/SP_SYSTEM)
    unset i
    DS_TYPE="${XPATH_ELEMENTS[i++]}"
    DS_DISK_TYPE="${XPATH_ELEMENTS[i++]}"
    DS_TM_MAD="${XPATH_ELEMENTS[i++]}"
    DS_BASE_PATH="${XPATH_ELEMENTS[i++]}"
    DS_CLUSTER_ID="${XPATH_ELEMENTS[i++]}"
    DS_SHARED="${XPATH_ELEMENTS[i++]}"
    DS_TEMPLATE_TYPE="${XPATH_ELEMENTS[i++]}"
    SP_REPLICATION="${XPATH_ELEMENTS[i++]}"
    SP_PLACEALL="${XPATH_ELEMENTS[i++]}"
    SP_PLACETAIL="${XPATH_ELEMENTS[i++]}"
    SP_SYSTEM="${XPATH_ELEMENTS[i++]}"

#    _MSG="${DS_TYPE:+DS_TYPE=$DS_TYPE }${DS_TEMPLATE_TYPE:+TEMPLATE_TYPE=$DS_TEMPLATE_TYPE }"
#    _MSG+="${DS_DISK_TYPE:+DISK_TYPE=$DS_DISK_TYPE }${DS_TM_MAD:+TM_MAD=$DS_TM_MAD }"
#    _MSG+="${DS_BASE_PATH:+BASE_PATH=$DS_BASE_PATH }${DS_CLUSTER_ID:+CLUSTER_ID=$DS_CLUSTER_ID }"
#    _MSG+="${DS_SHARED:+SHARED=$DS_SHARED }${SP_REPLICATION:+SP_REPLICATION=$SP_REPLICATION }"
#    _MSG+="${SP_PLACEALL:+SP_PLACEALL=$SP_PLACEALL }${SP_PLACETAIL:+SP_PLACETAIL=$SP_PLACETAIL }"
#    _MSG+="${SP_SYSTEM:+SP_SYSTEM=$SP_SYSTEM }"
#    splog "$_MSG"
}

function dumpTemplate()
{
    local _TEMPLATE="$1"
    echo "$_TEMPLATE" | base64 -d | xmllint --format - > "/tmp/tm_${0##*/}-$$.xml"
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
#    splog "VM_ID=$_VM_ID VM_STATE=$_VM_STATE VM_LCM_STATE=$_VM_LCM_STATE VM_PREV_STATE=$_VM_PREV_STATE CONTEXT_DISK_ID=$_CONTEXT_DISK_ID"

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
                    /VM/TEMPLATE/DISK/FORMAT)
    unset i
    _DISK_TM_MAD=${XPATH_ELEMENTS[i++]}
    _DISK_DATASTORE_ID=${XPATH_ELEMENTS[i++]}
    _DISK_ID=${XPATH_ELEMENTS[i++]}
    _DISK_CLUSTER_ID=${XPATH_ELEMENTS[i++]}
    _DISK_SOURCE=${XPATH_ELEMENTS[i++]}
    _DISK_PERSISTENT=${XPATH_ELEMENTS[i++]}
    _DISK_TYPE=${XPATH_ELEMENTS[i++]}
    _DISK_FORMAT=${XPATH_ELEMENTS[i++]}
#    splog "[oneTemplateInfo] $_DISK_TM_MAD $_DISK_DATASTORE_ID $_DISK_ID $_DISK_CLUSTER_ID $_DISK_SOURCE $_DISK_PERSISTENT $_DISK_TYPE $_DISK_FORMAT"

    _OLDIFS=$IFS
    IFS=";"
    DISK_TM_MAD_ARRAY=($_DISK_TM_MAD)
    DISK_DATASTORE_ID_ARRAY=($_DISK_DATASTORE_ID)
    DISK_ID_ARRAY=($_DISK_ID)
    DISK_CLUSTER_ID_ARRAY=($_DISK_CLUSTER_ID)
    DISK_SOURCE_ARRAY=($_DISK_SOURCE)
    DISK_PERSISTENT_ARRAY=($_DISK_PERSISTENT)
    DISK_TYPE_ARRAY=($_DISK_TYPE)
    DISK_FORMAT_ARRAY=($_DISK_FORMAT)
    IFS=$_OLDIFS
}
