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

do_patch()
{
    local _patch="$1"
    #check if patch is applied
    echo "   Test patch ${_patch##*/}"
    if patch --dry-run --reverse --forward --strip=0 --input="${_patch}"; then
        echo "*** Patch file ${_patch##*/} already applied?"
    else
        if patch --dry-run --forward --strip=0 --input="${_patch}"; then
            echo "*** Apply patch ${_patch##*/}"
            if patch --backup --version-control=numbered --strip=0 --forward --input="${_patch}"; then
                DO_PATCH="done"
            else
                DO_PATCH="failed"
                patch_err="${_patch}"
            fi
        else
            echo " ** Note! Can't apply patch ${_patch}! Please merge manually."
            patch_err="${_patch}"
        fi
    fi
}


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
        for p in `ls ${CWD}/patches/sunstone/${ONE_VER}/*.patch`; do
            do_patch "$p"
            [ -n "$DO_PATCH" ] && [ "$DO_PATCH" = "done" ] && REBUILD_JS=1
        done
        if [ "$ONE_VER" = "4.14" ]; then
            bin_err=
            if [ -n "$REBUILD_JS" ]; then
                for b in npm bower grunt; do
                    echo "*** check for $b"
                    $b --version
                    if [ $? -ne 0 ]; then
                        echo " ** Note! $b not found!"
                        case "$b" in
                            bower)
                                npm install -g bower
                                $b --version
                                [ $? -ne 0 ] && bin_err="$bin_err $b"
                                ;;
                            grunt)
                                npm install -g grunt
                                npm install -g grunt-cli
                                $b --version
                                [ $? -ne 0 ] && bin_err="$bin_err $b"
                                ;;
                            *)
                                bin_err=$b
                                break
                                ;;
                        esac
                    fi
                done
                if [ -n "$bin_err" ]; then
                    echo " ** Can't rebuild sunstone interface (missing:$bin_err)"
                else
                    echo "*** rebuilding synstone javascripts..."
                    echo "*** npm install"
                    npm install
                    echo "*** bower install"
                    bower --allow-root install
                    echo "*** grunt sass"
                    grunt sass
                    echo "*** grunt requirejs"
                    grunt requirejs
                fi
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
    M_DIR="${ONE_VAR}/remotes/${MAD}"
    echo "*** Installing ${M_DIR}/storpool ..."
    mkdir -pv "${M_DIR}/storpool"
    cp $CP_ARG ${MAD}/storpool/* "${M_DIR}/storpool/"
    chown -R "$ONE_USER" "${M_DIR}/storpool"
    chmod u+x -R "${M_DIR}/storpool"
done

# install xpath_multi.py
XPATH_MULTI="$ONE_VAR/remotes/datastore/xpath_multi.py"
echo "*** Installing $XPATH_MULTI ..."
cp $CP_ARG datastore/xpath_multi.py "$XPATH_MULTI"
chown "$ONE_USER" "$XPATH_MULTI"
chmod u+x "$XPATH_MULTI"

# install hooks
echo "*** Install hooks ..."
cp -v -a hooks/* "$ONE_VAR/remotes/hooks/"

# fencing-script.sh
if [ -f /usr/sbin/fencing-script.sh ]; then
    echo "*** File exists: /usr/sbin/fencing-script.sh "
    echo "*** Please update /usr/sbin/fencing-script.sh using hints from misc/fencing-script.sh"
else
    cp -v misc/fencing-script.sh /usr/sbin/
fi

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

function findFile()
{
    local c f d="$1" csum="$2"
    while read c f; do
        if [ "$c" = "$csum" ]; then
            echo $f
            break
        fi
    done < <(md5sum $d/* 2>/dev/null)
}

function tmResetMigrate()
{
    local current_csum=$(md5sum "${M_DIR}/${MIGRATE}" | awk '{print $1}')
    local csum comment found orig_csum
    while read csum comment; do
        [ "$comment" = "orig" ] && orig_csum="$csum"
        if [ "$current_csum" = "$csum" ]; then
            found="$comment"
            break;
        fi
    done < <(cat "tm/${TM_MAD}-${MIGRATE}.md5sums")
    case "$found" in
         orig)
            ;;
         4.10)
            orig=$(findFile "$M_DIR" "$orig_csum" )
            if [ -n "$orig" ]; then
                echo "***   $found variant of $TM_MAD/$MIGRATE"
                mv "${M_DIR}/${MIGRATE}" "${M_DIR}/${MIGRATE}.backup$(date +%s)"
                echo "***   restoring from original ${orig##*/}"
                cp $CP_ARG "$orig" "${M_DIR}/${MIGRATE}"
            fi
            ;;
         4.14)
            continue
            ;;
            *)
            echo " ** Can't determine the variant of $TM_MAD/$MIGRATE"
    esac
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
        tmResetMigrate
        patch_hook "${M_DIR}/${MIGRATE}"
    done
done

# Enable StorPool in oned.conf
if grep -q -i storpool /etc/one/oned.conf >/dev/null 2>&1; then
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

# Enable snap_create_live in vmm_exec/vmm_execrc
LIVE_DISK_SNAPSHOTS_LINE=$(grep -e '^LIVE_DISK_SNAPSHOTS' /etc/one/vmm_exec/vmm_execrc | tail -n 1)
if [ "x${LIVE_DISK_SNAPSHOTS_LINE/kvm-storpool/}" = "x$LIVE_DISK_SNAPSHOTS_LINE" ]; then
    if [ -n "$LIVE_DISK_SNAPSHOTS_LINE" ]; then
        echo "*** adding StorPool to LIVE_DISK_SNAPSHOTS in /etc/one/vmm_exec/vmm_execrc"
        eval $LIVE_DISK_SNAPSHOTS_LINE
        sed -i -e 's|kvm-qcow2|kvm-qcow2 kvm-storpool|g' /etc/one/vmm_exec/vmm_execrc
    else
        echo "*** LIVE_DISK_SNAPSHOTS not defined in /etc/one/vmm_exec/vmm_execrc"
        echo "*** to enable StorPool add the following line to /etc/one/vmm_exec/vmm_execrc"
        echo "LIVE_DISK_SNAPSHOTS=\"kvm-storpool\""
    fi
else
    echo "*** StorPool is already enabled for LIVE_DISK_SNAPSHOTS in /etc/one/vmm_exec/vmm_execrc"
fi

echo "*** VMM poll patch for OpenNebula v4.14 ..."
pushd "$ONE_VAR"
    do_patch "$CWD/patches/vmm/4.14/01-kvm_poll.patch"
popd
cp "$CWD/vmm/kvm/"{poll_,vmTweak}* "${ONE_VAR}/remotes/vmm/kvm/"
chmod a+x "${ONE_VAR}/remotes/vmm/kvm/"{poll_,vmTweak}*

echo "*** IM monitor_ds.sh patch (for OpenNebula 4.14+) ..."
pushd "$ONE_VAR"
    do_patch "$CWD/patches/im/4.14/00-monitor_ds.patch"
popd

echo "*** Please sync hosts (onehost sync --force)"

echo "*** Please restart opennebula${end_msg:+ and $end_msg} service${end_msg:+s}"
