#!/bin/bash

# -------------------------------------------------------------------------- #
# Copyright 2015, Storpool (storpool.com)                                    #
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

set -e

PATH="/bin:/usr/bin:/sbin:/usr/sbin:$PATH"

CP_ARG=${CP_ARG:--uv}

ONE_USER=${ONE_USER:-oneadmin}
ONE_VAR=${ONE_VAR:-/var/lib/one}
ONE_LIB=${ONE_LIB:-/usr/lib/one}
ONE_DS=${ONE_DS:-/var/lib/one/datastores}

if [ -n "$ONE_LOCATION" ]; then
    ONE_VAR="$ONE_LOCATION/var"
    ONE_LIB="$ONE_LOCATION/lib"
    ONE_DS="$ONE_LOCATION/var/datastores"
fi


#----------------------------------------------------------------------------#

[ "${0/\//}" != "$0" ] && cd ${0%/*}

CWD=$(pwd)


end_msg=
if [ -n "$SKIP_SUNSTONE" ]; then
    echo "*** Skipping opennebula-sunstone integration patch"
else
    SUNSTONE_PUBLIC=${SUNSTONE_PUBLIC:-$ONE_LIB/sunstone/public}
    if [ -f "$SUNSTONE_PUBLIC/js/plugins/datastores-tab.js" ]; then
        SS_VER=4.10
    fi
    if [ -f "$SUNSTONE_PUBLIC/app/tabs/datastores-tab/form-panels/create.js" ]; then
        SS_VER=4.14
    fi
    ONE_VER=${ONE_VER:-$SS_VER}

    # patch sunstone's datastores-tab.js
    if [ -n "$ONE_VER" ]; then
        patch_err=
        set +e
        pushd "$SUNSTONE_PUBLIC" &>/dev/null
        for p in `ls ${CWD}/patches/${ONE_VER}/*.patch`; do
            #check if patch is applied
            patch --dry-run --reverse --forward --strip=0 --input=${p}
            RET=$?
            if [ $RET == 0 ]; then
                echo "*** Patch file ${p##*/} already applied?"
            else
                patch --dry-run --forward --strip=0 --input=${p}
                RET=$?
                if [ $RET == 0 ]; then
                    echo "*** Apply patch ${p##*/}"
                    patch --backup --version-control=numbered --strip=0 --forward --input="${p}"
                else
                    echo " ** Note! Can't apply patch $p! Please merge manually."
                    patch_err="$p"
                fi
            fi
        done
        if [ "$ONE_VER" = "4.14" ]; then
            bin_err=
            for b in node npm bower grunt; do
                which $b
                if [ $? != 0 ]; then
                    bin_err=$b
                    echo " ** Note! $b binary not found! Can't rebuild susnstone interface!"
                fi
            done
            if [ "$bin_err" = "" ]; then
                npm install
                bower --allow-root install
                grunt sass
                grunt requirejs
            fi
        fi
        popd &>/dev/null
        set -e
        end_msg="opennebula-sunstone"
    else
        echo " ** Can't determine version fron ${SUNSTONE_PUBLIC}. Wrong path or opennebula-sunstone not installed."
        echo " ** Note! StorPool integration to sunstone not installed."
    fi
fi

if [ -n "$SKIP_ONED" ]; then
    echo "*** Skipping oned integration"
    [ -n "$end_msg" ] && echo "*** Please restart $end_msg service"
    exit;
fi


# install datastore and tm MAD
for MAD in datastore tm; do
    echo "*** Installing $ONE_VAR/remotes/${MAD}/storpool ..."
    mkdir -pv "$ONE_VAR/remotes/${MAD}/storpool"
    cp $CP_ARG ${MAD}/storpool/* "$ONE_VAR/remotes/${MAD}/storpool/"
    chown -R "$ONE_USER" "$ONE_VAR/remotes/${MAD}/storpool"
    chmod u+x -R "$ONE_VAR/remotes/${MAD}/storpool"
done

# install xpath_multi.py
XPATH_MULTI="$ONE_VAR/remotes/datastore/xpath_multi.py"
echo "*** Installing $XPATH_MULTI ..."
cp $CP_ARG datastore/xpath_multi.py "$XPATH_MULTI"
chown "$ONE_USER" "$XPATH_MULTI"
chmod u+x "$XPATH_MULTI"

function patch_hook()
{
    local _hook="$1"
    local _hook_line="[ -d \"\${0}.d\" ] \&\& for hook in \"\${0}.d\"/* ; do source \"\$hook\"; done"
    local _is_sh=0 _is_patched=0 _backup= _is_bash=
    grep -E '^#!/bin/sh$' "${_hook}" &>/dev/null && _is_sh=1
    grep  "${_hook_line}" "${_hook}" &>/dev/null && _is_patched=1
    if [ "$(grep -v -E '^#|^$' "${_hook}")" = "exit 0" ]; then
        if [ "${_is_patched}" = "1" ]; then
            echo "*** ${_hook} already patched"
        else
            _backup="${_hook}.backup$(date +%s)"
            echo "*** Create backup of ${_hook} as ${_backup}"
            cp $CP_ARG "${_hook}" "${_backup}"
            if [ "${_is_sh}" = "1" ]; then
                grep -E '^#!/bin/bash$' "${_hook}" &>/dev/null && _is_bash=1
                if [ "${_is_bash}" = "1" ]; then
                    echo "*** ${_hook} already bash script"
                else
                    sed -i -e 's|^#!/bin/sh$|#!/bin/bash|' "${_hook}"
                fi
            fi
            sed -i -e "s|^exit 0|$_hook_line\nexit 0|" "${_hook}"
        fi
    else
        echo "*** ${_hook} file not empty!"
        echo " ** Note! Please merge the following line to ${_hook}"
        echo " **"
        echo " ** ${_hook_line//\\&/&}"
        echo " **"
        if [ "${_is_sh}" = "1" ]; then
            echo " ** Note! Set script to bash:"
            echo " **   sed -i -e 's|^#!/bin/sh\$|#!/bin/bash|' \"${_hook}\""
        fi
    fi
}

# install premigrate and postmigrate hooks in shared and ssh
for TM_MAD in shared ssh; do
    for MIGRATE in premigrate postmigrate; do
        M_DIR="$ONE_VAR/remotes/tm/${TM_MAD}"
        mkdir -p "$M_DIR/${MIGRATE}.d"
        pushd "$M_DIR/${MIGRATE}.d" &>/dev/null
        ln -sf "../../storpool/${MIGRATE}" "${MIGRATE}-storpool"
        popd &>/dev/null
        chown -R "$ONE_USER" "${M_DIR}/${MIGRATE}.d"
        patch_hook "${M_DIR}/${MIGRATE}"
    done
done

# Enable StorPool in oned.conf
if grep -q -i storpool /etc/one/oned.conf &>/dev/null; then
    echo "*** StorPool is already enabled in /etc/one/oned.conf"
else
    echo "*** enabling StorPool plugin in /etc/one/oned.conf"
    cp /etc/one/oned.conf /etc/one/oned.conf.bak;

    sed -i -e 's|ceph,dev|ceph,dev,storpool|g' /etc/one/oned.conf

    cat <<_EOF_ >>/etc/one/oned.conf
# StorPool
TM_MAD_CONF = [
    name = "storpool", ln_target = "NONE", clone_target = "SELF", shared = "yes"
]
_EOF_
fi

echo "*** Please restart opennebula${end_msg:+ and $end_msg} service${end_msg:+s}"
