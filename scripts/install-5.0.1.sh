#!/bin/bash

# -------------------------------------------------------------------------- #
# Copyright 2015-2016, Storpool (storpool.com)                               #
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
if [ -n "$SKIP_SUNSTONE" ]; then
    echo "*** Skipping opennebula-sunstone integration patch"
else
    # patch sunstone's datastores-tab.js
    SUNSTONE_PUBLIC=${SUNSTONE_PUBLIC:-$ONE_LIB/sunstone/public}
    patch_err=
    set +e
    pushd "$SUNSTONE_PUBLIC" &>/dev/null
    for p in `ls ${CWD}/patches/sunstone/${ONE_VER}/*.patch`; do
        do_patch "$p" "backup"
        if [ -n "$DO_PATCH" ] && [ "$DO_PATCH" = "done" ]; then
            REBUILD_JS=1
        fi
    done
    bin_err=
    if [ -n "$REBUILD_JS" ]; then
        for b in npm bower grunt; do
            echo "*** check for $b"
            $b --version
            if [ $? -ne 0 ]; then
                echo " ** Note! $b not found!"
                case "$b" in
                    bower)
                        echo " ** Note! installing $b"
                        npm install -g bower@1.6.5
                        $b --version
                        [ $? -ne 0 ] && bin_err="$bin_err $b"
                        ;;
                    grunt)
                        echo " ** Note! installing $b"
                        #npm install -g grunt
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
    popd &>/dev/null
    set -e
    end_msg="opennebula-sunstone"
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

if grep "snapshot space" /etc/cron.d/addon-storpool 2>/dev/null; then
    echo "*** job exist for 'snapshot space' command"
else
    echo "*** Adding job for 'snapshot space' command"
    cat >>/etc/cron.d/addon-storpool <<_EOF_
5 * * * * root storpool -j snapshot space > /tmp/storpool_snapshot_space.jsonN && mv -f /tmp/storpool_snapshot_space.jsonN /tmp/storpool_snapshot_spaceIN.json
_EOF_
fi

if grep "volume usedSpace" /etc/cron.d/addon-storpool 2>/dev/null; then
    echo "*** job exist for 'volume usedSpace' command"
else
    echo "*** Adding job for 'volume usedSpace' command"
    cat >>/etc/cron.d/addon-storpool <<_EOF_
10 * * * * root storpool -j volume usedSpace > /tmp/storpool_volume_usedSpace.jsonN && mv -f /tmp/storpool_volume_usedSpace.jsonN /tmp/storpool_volume_usedSpaceIN.json
_EOF_
fi

if grep "volume status" /etc/cron.d/addon-storpool 2>/dev/null; then
    echo "*** job exist for 'volume status' command"
else
    echo "*** Adding job for 'volume status' command"
    cat >>/etc/cron.d/addon-storpool <<_EOF_
15 * * * * root storpool -j volume status > /tmp/storpool_volume_status.jsonN && mv -f /tmp/storpool_volume_status.jsonN /tmp/storpool_volume_statusIN.json
_EOF_
fi

# install premigrate and postmigrate hooks in shared and ssh TM_MADs
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
if grep -q -i storpool /etc/one/oned.conf >/dev/null 2>&1; then
    echo "*** StorPool is already enabled in /etc/one/oned.conf"
else
    echo "*** enabling StorPool plugin in /etc/one/oned.conf"
    cp /etc/one/oned.conf /etc/one/oned.conf.bak;

    sed -i -e 's|ceph,dev|ceph,dev,storpool|g' /etc/one/oned.conf

    sed -i -e 's|shared,ssh,ceph,|shared,ssh,ceph,storpool,|g' /etc/one/oned.conf

    cat <<_EOF_ >>/etc/one/oned.conf
# StorPool related config
TM_MAD_CONF = [
    NAME = "storpool",
    LN_TARGET = "NONE",
    CLONE_TARGET = "SELF",
    SHARED = "yes"
]
DS_MAD_CONF = [
    NAME = "storpool",
    REQUIRED_ATTRS = "DISK_TYPE",
    PERSISTENT_ONLY = "NO",
    MARKETPLACE_ACTIONS = "export"
]
_EOF_
fi

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

echo "*** Copy VM tweaks to ${ONE_VAR}/remotes/vmm/kvm/ ..."
cp "$CWD/vmm/kvm/"vmTweak* "${ONE_VAR}/remotes/vmm/kvm/"
chmod a+x "${ONE_VAR}/remotes/vmm/kvm/"vmTweak*

echo "*** im/kvm-probe.d/monitor_ds.sh patch ..."
pushd "$ONE_VAR"
    do_patch "$CWD/patches/im/$ONE_VER/00-monitor_ds.patch"
popd

echo "*** tm/shared/monitor patch ..."
pushd "$ONE_VAR"
    do_patch "$CWD/patches/tm/$ONE_VER/00-shared-monitor.patch" "backup"
popd

echo "*** tm/ssh/monitor patch ..."
pushd "$ONE_VAR"
    do_patch "$CWD/patches/tm/$ONE_VER/00-ssh-monitor_ds.patch" "backup"
popd

echo "*** Please sync hosts (onehost sync --force)"

echo "*** Please restart opennebula${end_msg:+ and $end_msg} service${end_msg:+s}"
