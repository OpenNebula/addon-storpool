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
    splog "SP_LINK=$_SP_LINK DST_DIR=$_DST_DIR"
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
    if [ -n "$_SP_TEMPLATE" ] && [ -n "$SP_REPLICATION" ] && [ -n "$SP_PLACEALL" ] && [ -n "$SP_PLACE_TAIL" ]; then
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
    splog "volume $_SP_VOL baseOn $_SP_PARENT $_SP_TEMPLATE"
    storpool volume "$_SP_VOL" baseOn "$_SP_PARENT" $_SP_TEMPLATE
EOF
)
    local _RENAME=$(cat <<EOF
    #_RENAME
    splog "volume $_SP_PARENT rename $_SP_VOL $_SP_TEMPLATE"
    storpool volume "$_SP_PARENT" rename "$_SP_VOL" $_SP_TEMPLATE
EOF
)
    local _EXTRA=$(cat <<EOF
    #_EXTRA
    splog "EXTRA_CMD:$EXTRA_CMD"
    $EXTRA_CMD
EOF
)
    local _RENAME_COND=$(cat <<EOF
    #_RENAME_COND
    if [ -n "$_SP_SIZE" ]; then
        splog "volume $_SP_VOL rename $_SP_SNAP $_SP_TEMPLATE"
        storpool volume "$_SP_PARENT" rename "$_SP_VOL" $_SP_TEMPLATE
    fi
EOF
)
    local _CMD= _HOST=
    case "$_ACTION" in
        CLONE)
            _HOST="$_DST_HOST"
            _CMD="$_BEGIN$_DELVOL$_CLONE$_ATTACH$_SYMLINK"
        ;;
        CPDS)
            _HOST="$_SRC_HOST"
            _CMD="$_BEGIN$_DELVOL$_CLONE$_ATTACH$_SYMLINK"
        ;;
        DELETE)
            _HOST="$_DST_HOST"
            _CMD="$_BEGIN$_DETACH_ALL$_DELVOL_NONPERSISTENT$_RMLINK"
        ;;
        LN)
            _HOST="$_DST_HOST"
            _CMD="$_BEGIN$_ATTACH$_SYMLINK"
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
        *)
    esac
    if [ -n "$_CMD" ]; then
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

function oneVmInfo()
{
    local _VM_ID="$1" _DISK_ID="$2"
    local _XPATH="${TM_PATH}/../../datastore/xpath.rb --stdin"

    unset i XPATH_ELEMENTS

    while IFS= read -r -d '' element; do
        XPATH_ELEMENTS[i++]="$element"
        done < <(onevm show -x $_VM_ID| $_XPATH  \
                            /VM/STATE \
                            /VM/LCM_STATE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/SOURCE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/IMAGE_ID \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/IMAGE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/CLONE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/PERSISTENT \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/HOTPLUG_SAVE_AS \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/HOTPLUG_SAVE_AS_ACTIVE \
                            /VM/TEMPLATE/DISK[DISK_ID=$_DISK_ID]/HOTPLUG_SAVE_AS_SOURCE)

    unset i
    VMSTATE="${XPATH_ELEMENTS[i++]}"
    LCM_STATE="${XPATH_ELEMENTS[i++]}"
    SOURCE="${XPATH_ELEMENTS[i++]}"
    IMAGE_ID="${XPATH_ELEMENTS[i++]}"
    IMAGE="${XPATH_ELEMENTS[i++]}"
    CLONE="${XPATH_ELEMENTS[i++]}"
    PERSISTENT="${XPATH_ELEMENTS[i++]}"
    HOTPLUG_SAVE_AS="${XPATH_ELEMENTS[i++]}"
    HOTPLUG_SAVE_AS_ACTIVE="${XPATH_ELEMENTS[i++]}"
    HOTPLUG_SAVE_AS_SOURCE="${XPATH_ELEMENTS[i++]}"

    #onevm show -x $VM_ID 2>&1 >/tmp/tm_sp_${0##*/}-${VM_ID}-${DISK_ID}.xml
    splog "\
${VMSTATE:+VMSTATE=$VMSTATE }\
${LCM_STATE:+LCM_STATE=$LCM_STATE }\
${SOURCE:+SOURCE=$SOURCE }\
${IMAGE_ID:+IMAGE_ID=$IMAGE_ID }\
${CLONE:+CLONE=$CLONE }\
${PERSISTENT:+PERSISTENT=$PERSISTENT }\
${IMAGE:+IMAGE=$IMAGE }\
"
    msg="${HOTPLUG_SAVE_AS:+HOTPLUG_SAVE_AS=$HOTPLUG_SAVE_AS }${HOTPLUG_SAVE_AS_ACTIVE:+HOTPLUG_SAVE_AS_ACTIVE=$HOTPLUG_SAVE_AS_ACTIVE }${HOTPLUG_SAVE_AS_SOURCE:+HOTPLUG_SAVE_AS_SOURCE=$HOTPLUG_SAVE_AS_SOURCE }"
    [ -n "$msg" ] && splog "$msg"
}

function oneDatastoreInfo()
{
    local _DS_ID="$1"
    local _XPATH="${TM_PATH}/../../datastore/xpath.rb --stdin"

    unset i XPATH_ELEMENTS

    while IFS= read -r -d '' element; do
        XPATH_ELEMENTS[i++]="$element"
        done < <(onedatastore show -x $DS_ID | $XPATH  \
                            /DATASTORE/TYPE \
                            /DATASTORE/DISK_TYPE \
                            /DATASTORE/TM_MAD \
                            /DATASTORE/BASE_PATH \
                            /DATASTORE/CLUSTER_ID \
                            /DATASTORE/TEMPLATE/SHARED \
                            /DATASTORE/TEMPLATE/SP_REPLICATION \
                            /DATASTORE/TEMPLATE/SP_PLACEALL \
                            /DATASTORE/TEMPLATE/SP_PLACETAIL)
    unset i
    DS_TYPE="${XPATH_ELEMENTS[i++]}"
    DS_DISK_TYPE="${XPATH_ELEMENTS[i++]}"
    DS_TM_MAD="${XPATH_ELEMENTS[i++]}"
    DS_BASE_PATH="${XPATH_ELEMENTS[i++]}"
    DS_CLUSTER_ID="${XPATH_ELEMENTS[i++]}"
    DS_SHARED="${XPATH_ELEMENTS[i++]}"
    SP_REPLICATION="${XPATH_ELEMENTS[i++]}"
    SP_PLACEALL="${XPATH_ELEMENTS[i++]}"
    SP_PLACETAIL="${XPATH_ELEMENTS[i++]}"

    splog "${DS_TYPE:+TYPE=$DS_TYPE }\
${DS_DISK_TYPE:+DISK_TYPE=$DS_DISK_TYPE }\
${DS_TM_MAD:+TM_MAD=$DS_TM_MAD }\
${DS_BASE_PATH:+BASE_PATH=$DS_BASE_PATH }\
${DS_CLUSTER_ID:+CLUSTER_ID=$DS_CLUSTER_ID }\
${DS_SHARED:+SHARED=$DS_SHARED }\
${SP_REPLICATION:+SP_REPLICATION=$SP_REPLICATION }\
${SP_PLACEALL:+SP_PLACEALL=$SP_PLACEALL }\
${SP_PLACETAIL:+SP_PLACETAIL=$SP_PLACETAIL }\
"
}
