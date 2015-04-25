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
# syslog logger function
#-------------------------------------------------------------------------------

function splog() { logger -t "tm_sp_${0##*/}" "$*"; }

if [ -n "${ONE_LOCATION}" ]; then
    TMCOMMON="$ONE_LOCATION/var/remotes/tm/tm_common.sh"
else
    TMCOMMON=/var/lib/one/remotes/tm/tm_common.sh
fi

DRIVER_PATH="$(dirname $0)"

source "$TMCOMMON"

function storpoolAction()
{
    local _SRC_HOST="$1" _DST_HOST="$2" _SP_VOL="$3" _DST_PATH="$4" _ACTION="$5" _SP_PARENT="$6" _SP_TEMPLATE="$7" _SP_SIZE="$8"
    local _SP_LINK="/dev/storpool/$_SP_VOL"
    local _DST_DIR="${_DST_PATH%%disk*}"
    splog "SRC_HOST=$_SRC_HOST DST_HOST=$_DST_HOST SP_VOL=$_SP_VOL DST_PATH=$_DST_PATH $_ACTION"
    splog "SP_LINK=$_SP_LINK DST_DIR=$_DST_DIR"
    local _MSG="${_SP_PARENT:+SP_PARENT=$_SP_PARENT }${_SP_TEMPLATE:+SP_TEMPLATE=$_SP_TEMPLATE }${_SP_SIZE:+SP_SIZE=$_SP_SIZE}"
    [ -n "$_MSG" ] && splog "$_MSG"

    local _BEGIN=$(cat <<EOF
    set -e
    export PATH=/bin:/usr/bin:/sbin:/usr/sbin:\$PATH
    splog(){ logger -t "tm_sp_${0##*/}_${_ACTION}" "\$*"; }
EOF
)
    local _END=$(cat <<EOF

    splog "END $_ACTION"
EOF
)
    local _DETACH=$(cat <<EOF

    if storpool attach list | grep -q " $_SP_VOL " &>/dev/null; then
        splog "detach volume $_SP_VOL all"
        storpool detach volume "$_SP_VOL" all
    else
        splog "volume not attached $_SP_VOL"
    fi
EOF
)
    local _ATTACH=$(cat <<EOF

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

    if storpool volume "$_SP_VOL" info &>/dev/null; then
        splog "delete $_SP_VOL"
        storpool volume "$_SP_VOL" delete "$SP_VOL"
    fi
EOF
)
    local _CREATE=$(cat <<EOF

    if [ -n "$SP_REPLICATION" ] && [ -n "$SP_PLACEALL" ] && [ -n "$SP_PLACE_TAIL" ]; then
        splog "template $_SP_TEMPLATE replication $SP_REPLICATION placeAll $SP_PLACEALL placeTail $SP_PLACETAIL"
        storpool template "$_SP_TEMPLATE" replication "$SP_REPLICATION" placeAll "$SP_PLACEALL" placeTail "$SP_PLACETAIL"
    fi

    splog "volume $_SP_VOL size "${_SP_SIZE}" template $_SP_TEMPLATE"
    storpool volume "$_SP_VOL" size "${_SP_SIZE}" template "$_SP_TEMPLATE"
EOF
)
    local _CLONE=$(cat <<EOF

    splog "volume $_SP_VOL baseOn $_SP_PARENT template $_SP_TEMPLATE"
    storpool volume "$_SP_VOL" baseOn "$_SP_PARENT" template "$_SP_TEMPLATE"
EOF
)
    local _RENAME=$(cat <<EOF

    splog "volume $_SP_PARENT rename $_SP_VOL template $_SP_TEMPLATE"
    storpool volume "$_SP_PARENT" rename "$_SP_VOL" template "$_SP_TEMPLATE"
EOF
)
    local _EXTRA=$(cat <<EOF

    splog "EXTRA_CMD:$EXTRA_CMD"
    $EXTRA_CMD
EOF
)
    local _CMD= _HOST=
    case "$_ACTION" in
        ATTACH)
            _HOST="$_DST_HOST"
            _CMD="$_COMMON$_ATTACH$_SYMLINK"
        ;;
        DETACH)
            _HOST="$_SRC_HOST"
            _CMD="$_COMMON$_DETACH"
        ;;
        ATTACHDETACH)
            attachdetach "$_SRC_HOST" "$_DST_HOST" "$_SP_VOL" "$_DST_PATH" "ATTACH"
            attachdetach "$_SRC_HOST" "$_DST_HOST" "$_SP_VOL" "$_DST_PATH" "DETACH"
        ;;
        CLONE)
            _HOST="$_DST_HOST"
            _CMD="$_COMMON$_DELVOL$_CLONE$_ATTACH$_SYMLINK"
        ;;
        *)
        MKIMAGE)
            _HOST="$_DST_HOST"
            _CMD="$_COMMON$_CREATE$_ATTACH$_SYMLINK$_EXTRA"
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
        splog "END"
    fi
}
