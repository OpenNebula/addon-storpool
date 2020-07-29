#!/bin/bash

# -------------------------------------------------------------------------- #
# Copyright 2015-2020, Storpool (storpool.com)                               #
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

function patch_hook()
{
    local _hook="$1"
    local _hook_line="[ -d \"\${0}.d\" ] \&\& for hook in \"\${0}.d\"/* ; do source \"\$hook\"; done"
    local _is_sh=0 _is_patched=0 _backup= _is_bash=
    grep -E '^#!/bin/sh$' "${_hook}" &>/dev/null && _is_sh=1
    if grep  "${_hook_line}" "${_hook}" &>/dev/null; then
        echo "*** ${_hook} already patched"
    else
        _backup="${_hook}.backup$(date +%s)"
        echo "*** Create backup of ${_hook} as ${_backup}"
        cp $CP_ARG "${_hook}" "${_backup}"
        if grep -E '^#!/bin/sh$' "${_hook}" &>/dev/null; then
            echo "*** Replacing #!/bin/sh with #!/bin/bash in ${_hook}"
            sed -i -e 's|^#!/bin/sh$|#!/bin/bash|' "${_hook}"
            echo "*** Inserting the hook in ${_hook}"
            sed -i -e "s|^exit 0|$_hook_line\nexit 0|" "${_hook}"
        else
            echo "*** Inserting the hook in ${_hook}"
            sed -i -e "s|#!/bin/bash|#!/bin/bash\n$_hook_line\n|" "${_hook}"
        fi
    fi
}

AUGEAS_LENSES="${AUGEAS_LENSES:-/usr/share/augeas/lenses}"

SKIP_SUNSTONE="${SKIP_SUNSTONE:-1}"

if fgrep -qR "storpool" -- "${SUNSTONE_PUBLIC:-$ONE_LIB/sunstone/public}"; then
    SKIP_SUNSTONE=1
fi

end_msg=
if [ "$SKIP_SUNSTONE" = "1" ]; then
    echo "*** Skipping opennebula-sunstone integration patch"
else
    # patch sunstone's datastores-tab.js
    SUNSTONE_PUBLIC=${SUNSTONE_PUBLIC:-$ONE_LIB/sunstone/public}
    patch_err=
    set +e
    pushd "$SUNSTONE_PUBLIC" &>/dev/null
    ts="$(date "+%Y%m%d%H%M%S")"
    SUNSTONE_BACKUP="${SUNSTONE_PUBLIC}-bak-${ts}"
    echo "*** Backing up sunstone/public to $SUNSTONE_BACKUP ..."
    cp -a "$SUNSTONE_PUBLIC" "$SUNSTONE_BACKUP"
    if [ -d ${CWD}/patches/sunstone/${ONE_VER} ]; then
        for p in `ls ${CWD}/patches/sunstone/${ONE_VER}/*.patch`; do
            do_patch "$p" "backup"
            if [ -n "$DO_PATCH" ] && [ "$DO_PATCH" = "done" ]; then
                REBUILD_JS=1
            fi
        done
    else
        echo "*** No sunstone patches available."
        REBUILD_JS=
    fi
    bin_err=
    if [ -n "$REBUILD_JS" ]; then
        if [ -L dist/main.js ]; then
            echo "*** Backing up dist/main.js ..."
            mv -vf dist/main.js main.js-tmp
        fi
        echo "*** Running ./build.sh -d ..."
        ./build.sh -d
        export PATH=$PATH:$PWD/node_modules/.bin
        echo "*** Running ./build.sh ..."
        ./build.sh
        if [ -L main.js-tmp ]; then
            if [ -L dist/main.js ]; then
                echo "*** Removing backup of dist/main.js ..."
                rm -vf main.js-tmp
            else
                echo "*** Restoring dist/main.js ..."
                mv -vf main.js-tmp dist/main.js
            fi
        fi
        end_msg="opennebula-sunstone"
    fi
    popd &>/dev/null
    set -e
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

# install xpath_multi.py and xpath-sp.rb
for f in xpath_multi.py xpath-sp.rb; do
    XPATH_MULTI="$ONE_VAR/remotes/datastore/$f"
    echo "*** Installing $f ..."
    cp $CP_ARG "datastore/$f" "$XPATH_MULTI"
    chown "$ONE_USER" "$XPATH_MULTI"
    chmod a+x "$XPATH_MULTI"
done

echo "*** Clean up old style crontab jobs"
(crontab -u oneadmin -l | grep -v monitor_helper-sync | crontab -u oneadmin -)
(crontab -u root -l | grep -v "storpool -j " | crontab -u root -)

########################

if [ -f "/etc/cron.d/addon-storpool" ]; then
   echo "*** File exists. /etc/cron.d/addon-storpool"
else
   echo "*** Creating /etc/cron.d/addon-storpool"
   cat >>/etc/cron.d/addon-storpool <<_EOF_
# addon-storpool jobs
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=oneadmin
_EOF_
fi

if grep monitor_helper-sync /etc/cron.d/addon-storpool 2>/dev/null; then
    echo "*** job exist for monitor_helper-sync"
else
    echo "*** Adding job for monitor_helper-sync"
    cat >>/etc/cron.d/addon-storpool <<_EOF_
*/4 * * * * oneadmin ${ONE_VAR}/remotes/datastore/storpool/monitor_helper-sync 2>&1 >/tmp/monitor_helper_sync.err
_EOF_
fi

echo "*** Copy deploy-tweaks* ${ONE_VAR}/remotes/vmm/kvm/ ..."
cp -a $CP_ARG "$CWD/vmm/kvm/"deploy-tweaks* "${ONE_VAR}/remotes/vmm/kvm/"
chmod  a+x "${ONE_VAR}/remotes/vmm/kvm/"deploy-tweaks
mkdir -p "${ONE_VAR}/remotes/vmm/kvm/deploy-tweaks.d"
cp $CP_ARG "$CWD/vmm/kvm/"deploy-tweaks.d.example/volatile2dev.py "${ONE_VAR}/remotes/vmm/kvm/deploy-tweaks.d"/

echo "*** Copy attach_disk.storpool to ${ONE_VAR}/remotes/vmm/kvm/ ..."
cp -a $CP_ARG "$CWD/vmm/kvm/attach_disk.storpool" "${ONE_VAR}/remotes/vmm/kvm/"
chmod  a+x "${ONE_VAR}/remotes/vmm/kvm/attach_disk.storpool"

echo "*** Copy tmsaverestore script ant symlinks to ${ONE_VAR}/remotes/vmm/kvm/ ..."
cp -a $CP_ARG "$CWD/vmm/kvm/"tm* "${ONE_VAR}/remotes/vmm/kvm/"
chmod  a+x "${ONE_VAR}/remotes/vmm/kvm/"tm*

echo "*** Copy VM snapshot scripts to ${ONE_VAR}/remotes/vmm/kvm/ ..."
cp $CP_ARG "$CWD/vmm/kvm/"snapshot_*-storpool "${ONE_VAR}/remotes/vmm/kvm/"
chmod a+x "${ONE_VAR}/remotes/vmm/kvm/"snapshot_*-storpool

echo "*** remove VM checkpoint helpers from ${ONE_VAR}/remotes/vmm/kvm/ ..."
for f in {save,restore}.storpool{,-pre,-post}; do
    if [ -f "${ONE_VAR}/remotes/vmm/kvm/$f" ]; then
        rm -vf "${ONE_VAR}/remotes/vmm/kvm/$f"
    fi
done

echo -n "*** addon-storpoolrc "
if [ -f "${ONE_VAR}/remotes/addon-storpoolrc" ]; then
    echo "(found)"
else
    cp $CP_ARG addon-storpoolrc "${ONE_VAR}/remotes/addon-storpoolrc"
fi

echo "*** copying misc/reserved.sh to .../remotes"
cp -vf misc/reserved.sh "${ONE_VAR}/remotes/"

if [ -z "$SKIP_CONFIGURATION" ]; then
    # Prepare and use autoconf.rb
    echo "*** Copy augeas lenses ..."
    cp -vf "$CWD/misc/augeas"/*.aug "${AUGEAS_LENSES}"/
    mkdir -p "${AUGEAS_LENSES}/tests"
    cp -vf "$CWD/misc/augeas/tests"/*.aug "${AUGEAS_LENSES}/tests"/
    AUTOCONF=
    for yaml in ${DEFAULT_AUTOCONF:-/etc/one/addon-storpool.autoconf}; do
        if [ -f "$yaml" ]; then
            AUTOCONF+="-m $yaml "
        fi
    done
    $CWD/misc/autoconf.rb -v -w $AUTOCONF

    chown -R "$ONE_USER" "${ONE_VAR}/remotes"
else
    echo "!!! Configuration skipped"
fi

if [ -n "$STORPOOL_EXTRAS" ]; then
    if ! grep -q 'deploy=deploy-tweaks' /etc/one/oned.conf; then
        echo "!!! Please enable deploy-tweaks in the VM_MAD configuration"
    fi
fi

echo "*** Please sync hosts (onehost sync --force)"

echo "*** Please restart opennebula${end_msg:+ and $end_msg} service${end_msg:+s}"

if [ -n "$SUNSTONE_BACKUP" ] && [ -d "$SUNSTONE_BACKUP" ] ; then
    echo "*** There is a backup of the sunstone interface that could be removed in case of no issues"
    echo "*** (rm -rf $SUNSTONE_BACKUP)"
fi

echo "*** Please update RESERVED_CPU and RESERVED_MEM with the values from '/var/tmp/one/reserved.sh' run on each host"
