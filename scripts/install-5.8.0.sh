#!/bin/bash

# -------------------------------------------------------------------------- #
# Copyright 2015-2018, Storpool (storpool.com)                               #
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

# install xpath_multi.py
XPATH_MULTI="$ONE_VAR/remotes/datastore/xpath_multi.py"
echo "*** Installing ${XPATH_MULTI##*/} ..."
cp $CP_ARG datastore/xpath_multi.py "$XPATH_MULTI"
chown "$ONE_USER" "$XPATH_MULTI"
chmod a+x "$XPATH_MULTI"

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

# Enable StorPool in oned.conf
if grep -q -i storpool /etc/one/oned.conf >/dev/null 2>&1; then
    echo "*** StorPool is already enabled in /etc/one/oned.conf"
else
    echo "*** enabling StorPool plugin in /etc/one/oned.conf"
    cp $CP_ARG /etc/one/oned.conf /etc/one/oned.conf.bak;

    sed -i -e 's|ceph,dev|ceph,dev,storpool|g' /etc/one/oned.conf

    sed -i -e 's|shared,ssh,ceph,|shared,ssh,ceph,storpool,|g' /etc/one/oned.conf

    cat <<_EOF_ >>/etc/one/oned.conf
# StorPool related config
TM_MAD_CONF = [ NAME = "storpool", LN_TARGET = "NONE", CLONE_TARGET = "SELF", SHARED = "yes", DS_MIGRATE = "yes", DRIVER = "raw", ALLOW_ORPHANS = "yes", TM_MAD_SYSTEM = "ssh,shared", LN_TARGET_SSH = "NONE", CLONE_TARGET_SSH = "SELF", DISK_TYPE_SSH = "BLOCK", LN_TARGET_SHARED = "NONE", CLONE_TARGET_SHARED = "SELF", DISK_TYPE_SHARED = "BLOCK"  ]
DS_MAD_CONF = [ NAME = "storpool", REQUIRED_ATTRS = "DISK_TYPE", PERSISTENT_ONLY = "NO", MARKETPLACE_ACTIONS = "" ]
_EOF_
fi

for e in DISKSNAPSHOT_LIMIT VMSNAPSHOT_LIMIT T_CPU_THREADS T_CPU_SOCKETS T_CPU_FEATURES \
         T_CPU_MODE T_CPU_MODEL T_CPU_VENDOR T_CPU_CHECK T_CPU_MATCH \
         T_VF_MACS; do
    if grep -q -i "$e" /etc/one/oned.conf >/dev/null 2>&1; then
        echo "*** $e found in /etc/one/oned.conf"
    else
        echo "*** Appending VM_RESTRICTED_ATTR = $e in /etc/one/oned.conf"
        echo "VM_RESTRICTED_ATTR = \"$e\"" >> /etc/one/oned.conf
    fi
done

# Enable snap_create_live in vmm_exec/vmm_execrc
LIVE_DISK_SNAPSHOTS_LINE=$(grep -e '^LIVE_DISK_SNAPSHOTS' /etc/one/vmm_exec/vmm_execrc | tail -n 1)
if [ "x${LIVE_DISK_SNAPSHOTS_LINE/kvm-storpool/}" = "x$LIVE_DISK_SNAPSHOTS_LINE" ]; then
    if [ -n "$LIVE_DISK_SNAPSHOTS_LINE" ]; then
        echo "*** adding StorPool to LIVE_DISK_SNAPSHOTS in /etc/one/vmm_exec/vmm_execrc"
#        eval $LIVE_DISK_SNAPSHOTS_LINE
        sed -i -e 's|kvm-qcow2|kvm-qcow2 kvm-storpool|g' /etc/one/vmm_exec/vmm_execrc
    else
        echo "*** LIVE_DISK_SNAPSHOTS not defined in /etc/one/vmm_exec/vmm_execrc"
        echo "*** to enable StorPool add the following line to /etc/one/vmm_exec/vmm_execrc"
        echo "LIVE_DISK_SNAPSHOTS=\"kvm-storpool\""
    fi
else
    echo "*** StorPool is already enabled for LIVE_DISK_SNAPSHOTS in /etc/one/vmm_exec/vmm_execrc"
fi

if [ -n "$OLD_TWEAKS" ]; then
    echo "*** Copy VM tweaks to ${ONE_VAR}/remotes/vmm/kvm/ ..."
    cp $CP_ARG "$CWD/vmm/kvm/"vmTweak* "${ONE_VAR}/remotes/vmm/kvm/"
    chmod a+x "${ONE_VAR}/remotes/vmm/kvm/"vmTweak*
fi

echo "*** Copy deploy-tweaks* ${ONE_VAR}/remotes/vmm/kvm/ ..."
cp -a $CP_ARG "$CWD/vmm/kvm/"deploy-tweaks* "${ONE_VAR}/remotes/vmm/kvm/"
chmod  a+x "${ONE_VAR}/remotes/vmm/kvm/"deploy-tweaks
mkdir -p "${ONE_VAR}/remotes/vmm/kvm/deploy-tweaks.d"
cp $CP_ARG "$CWD/vmm/kvm/"deploy-tweaks.d.example/volatile2dev.py "${ONE_VAR}/remotes/vmm/kvm/deploy-tweaks.d"/

echo "*** Copy VM snapshot scripts to ${ONE_VAR}/remotes/vmm/kvm/ ..."
cp $CP_ARG "$CWD/vmm/kvm/"snapshot_*-storpool "${ONE_VAR}/remotes/vmm/kvm/"
chmod a+x "${ONE_VAR}/remotes/vmm/kvm/"snapshot_*-storpool

echo "*** Copy VM checkpoint helpers to ${ONE_VAR}/remotes/vmm/kvm/ ..."
cp $CP_ARG "$CWD/vmm/kvm/"{save,restore}.storpool* "${ONE_VAR}/remotes/vmm/kvm/"
chmod a+x "${ONE_VAR}/remotes/vmm/kvm/"{save,restore}.storpool*

echo "*** VMM checkpoint to block device patch ..."
pushd "$ONE_VAR"
    do_patch "$CWD/patches/vmm/${ONE_VER}/save.patch" "backup"
    do_patch "$CWD/patches/vmm/${ONE_VER}/restore.patch" "backup"
    do_patch "$CWD/patches/vmm/${ONE_VER}/attach_disk.patch" "backup"
popd

echo "*** im/kvm-probe.d/monitor_ds.sh patch ..."
pushd "$ONE_VAR" >/dev/null
    do_patch "$CWD/patches/im/$ONE_VER/00-monitor_ds.patch"
popd >/dev/null

echo "*** tm/shared/monitor patch ..."
pushd "$ONE_VAR" >/dev/null
    do_patch "$CWD/patches/tm/$ONE_VER/00-shared-monitor.patch" "backup"
popd >/dev/null

echo "*** tm/ssh/monitor patch ..."
pushd "$ONE_VAR" >/dev/null
    do_patch "$CWD/patches/tm/$ONE_VER/00-ssh-monitor_ds.patch" "backup"
popd >/dev/null

echo -n "*** addon-storpoolrc "
if [ -f "${ONE_VAR}/remotes/addon-storpoolrc" ]; then
    echo "(found)"
else
    cp $CP_ARG addon-storpoolrc "${ONE_VAR}/remotes/addon-storpoolrc"
fi
grep -q "MKSWAP=" "${ONE_VAR}/remotes/addon-storpoolrc" || echo 'MKSWAP="sudo /sbin/mkswap"' >> "${ONE_VAR}/remotes/addon-storpoolrc"
grep -q "MKFS=" "${ONE_VAR}/remotes/addon-storpoolrc" || echo 'MKFS="sudo /sbin/mkfs"' >> "${ONE_VAR}/remotes/addon-storpoolrc"

echo "*** copying misc/reserved.sh to .../remotes"
cp -vf misc/reserved.sh "${ONE_VAR}/remotes/"

echo "*** Checking for deploy-tweaks in /etc/one/oned.conf ..."
if ! grep -q 'deploy=deploy-tweaks' /etc/one/oned.conf; then
    echo "!!! Please enable deploy-tweaks in the VM_MAD configuration for proper working of volatile disks"
fi

echo "*** Please sync hosts (onehost sync --force)"

echo "*** Please restart opennebula${end_msg:+ and $end_msg} service${end_msg:+s}"

if [ -n "$SUNSTONE_BACKUP" ] && [ -d "$SUNSTONE_BACKUP" ] ; then
    echo "*** There is a backup of the sunstone interface that could be removed in case of no issues"
    echo "*** (rm -rf $SUNSTONE_BACKUP)"
fi

echo "*** Please update RESERVED_CPU and RESERVED_MEM with the values from '/var/tmp/one/reserved.sh' run on each host"
