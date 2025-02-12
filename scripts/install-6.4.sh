#!/bin/bash

# -------------------------------------------------------------------------- #
# Copyright 2015-2024, Storpool (storpool.com)                               #
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

AUGEAS_LENSES="${AUGEAS_LENSES:-/usr/share/augeas/lenses}"

AUTOCONF="${AUTOCONF:-0}"

ONED="${ONED:-1}"

SUNSTONE="${SUNSTONE:-0}"

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

if ! boolTrue "ONED"; then
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
    chmod u+x -R "${M_DIR}/storpool"
done

# install xpath_multi.py and xpath-sp.rb
for f in xpath_multi.py xpath-sp.rb; do
    XPATH_MULTI="$ONE_VAR/remotes/datastore/$f"
    echo "*** Installing $f ..."
    cp $CP_ARG "datastore/$f" "$XPATH_MULTI"
    chmod a+x "$XPATH_MULTI"
done

# volumecare hook files
echo "*** Installing volumecare hook files..."
volumecarePath="${ONE_VAR}/remotes/hooks/volumecare"
mkdir -p "${volumecarePath}"
for vFile in volumecare vc-policy.sh; do
    cp ${CP_ARG} "hooks/volumecare/${vFile}" "${volumecarePath}"/
done

# Periodic task
echo "*** Clean up old style crontab jobs ..."
(crontab -u oneadmin -l | grep -v monitor_helper-sync | crontab -u oneadmin -)||:
(crontab -u root -l | grep -v "storpool -j " | crontab -u root -)||:

for cronfile in "/etc/cron.d/addon-storpool" "/etc/cron.d/vc-policy"; do
    if [[ -f "${cronfile}" ]]; then
        echo "*** Deleting ${cronfile}"
        rm -vf "${cronfile}"
    fi
done

echo "*** Create tmpfiles.d configuration to handle /var/cache/addon-storpoolrc-monitor folder"
cp -v "${CWD}/misc/etc/tmpfiles.d/addon-storpool-monitor.conf" /etc/tmpfiles.d/
systemd-tmpfiles --create

echo "*** Processing the systemd timers"
for sName in monitor_helper-sync vc-policy; do
    for sType in service timer; do
        sFile="/etc/systemd/system/${sName}.${sType}"
        if [[ ! -f "${sFile}" ]]; then
            cp -v "${CWD}/misc${sFile}" /etc/systemd/system/
        fi
    done
done

systemctl daemon-reload

echo "*** Activating systemd timers ..."
systemctl enable monitor_helper-sync.timer --now
systemctl enable vc-policy.timer --now

echo "*** Copy deploy-tweaks* ${ONE_VAR}/remotes/vmm/kvm/ ..."
cp -a $CP_ARG "$CWD/vmm/kvm/"deploy-tweaks* "${ONE_VAR}/remotes/vmm/kvm/"
chmod  a+x "${ONE_VAR}/remotes/vmm/kvm/"deploy-tweaks
mkdir -p "${ONE_VAR}/remotes/vmm/kvm/deploy-tweaks.d"
pushd "${ONE_VAR}/remotes/vmm/kvm/deploy-tweaks.d"
for tweak in volatile2dev.py persistent-cdrom.py; do
    [[ -L "./${tweak}" ]] && rm -vf "./${tweak}" || true
    cp ${CP_ARG} "../deploy-tweaks.d.example/${tweak}" "./${tweak}"
done
popd

echo "*** Copy {attach,detach}_disk.{storpool,cdrom} to ${ONE_VAR}/remotes/vmm/kvm/ ..."
for vmm in {attach,detach}_disk.{storpool,cdrom}; do
    cp -a $CP_ARG "$CWD/vmm/kvm/${vmm}" "${ONE_VAR}/remotes/vmm/kvm/"
    chmod  a+x "${ONE_VAR}/remotes/vmm/kvm/${vmm}"
done

echo "*** Copy tmsaverestore script and symlinks to ${ONE_VAR}/remotes/vmm/kvm/ ..."
cp $CP_ARG "$CWD/vmm/kvm/"tm* "${ONE_VAR}/remotes/vmm/kvm/"
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

for mad in im vmm vnm; do
    [ -d "patches/${mad}" ] || continue
    for ver in ${ONE_VER} ${ONE_MAJOR}.${ONE_MINOR}; do
        patchdir="${PWD}/patches/${mad}/${ver}"
        [ -d "$patchdir" ] || continue
        echo "*** Applying patches found in ${patchdir} ..."
        pushd "${ONE_VAR}"
        while read -u 5 patchfile; do
            do_patch "$patchfile" "backup"
        done 5< <(ls -1 $patchdir/*.patch)
        popd
        break 1
    done
done

echo -n "*** addon-storpoolrc "
if [ -f "${ONE_VAR}/remotes/addon-storpoolrc" ]; then
    echo "(found)"
else
    cp $CP_ARG addon-storpoolrc "${ONE_VAR}/remotes/addon-storpoolrc"
fi

echo "*** copying misc/reserved.sh to .../remotes"
cp -vf misc/reserved.sh "${ONE_VAR}/remotes/"

if [ -d "${ONE_VAR}/remotes/im/kvm-probes.d/host/system" ]; then
    echo "*** copying misc/storpool_probe.sh to .../remotes/im/kvm-probes.d/host/system/"
    cp -vf misc/storpool_probe.sh "${ONE_VAR}/remotes/im/kvm-probes.d/host/system/"
fi

if ! boolTrue "AUTOCONF" ; then
    echo "NOTICE: Configuration skipped!"
    echo "Hint: export AUTOCONF=1; bash install.sh"
    echo
else
    # Prepare and use autoconf.rb
    echo "*** Copy augeas lenses ..."
    cp -vf "$CWD/misc/augeas"/*.aug "${AUGEAS_LENSES}"/
    mkdir -p "${AUGEAS_LENSES}/tests"
    cp -vf "$CWD/misc/augeas/tests"/*.aug "${AUGEAS_LENSES}/tests"/
    AUTOCONF=
    for yaml in ${DEFAULT_AUTOCONF:-/etc/one/addon-storpool.autoconf "$CWD/misc/autoconf-${ONE_MAJOR}.${ONE_MINOR}.yaml"}; do
        if [ -f "$yaml" ]; then
            echo "  - including: $yaml"
            AUTOCONF+="-m $yaml "
        fi
    done
    $CWD/misc/autoconf.rb -v -w $AUTOCONF
fi

if [[ -f /var/lib/one/remotes/addon-storpoolrc ]]; then
    source /var/lib/one/remotes/addon-storpoolrc
fi

echo "*** Refresh deploy-tweaks"
read -ra DEPLOY_TWEAKS_A <<<"${DEPLOY_TWEAKS} $(ls -1 "${ONE_VAR}/remotes/vmm/kvm/deploy-tweaks.d/" | tr '\n' ' ')";
declare -A KNOWN_TWEAKS
for tweak in "${DEPLOY_TWEAKS_A[@]}"; do
    [[ -z "${KNOWN_TWEAKS[${tweak//[^[:alnum:]]/}]}" ]] || continue
    KNOWN_TWEAKS[${tweak//[^[:alnum:]]/}]="${tweak}"
    if [[ -L "${ONE_VAR}/remotes/vmm/kvm/deploy-tweaks.d/${tweak}" ]]; then
        rm -vf "${ONE_VAR}/remotes/vmm/kvm/deploy-tweaks.d/${tweak}"
    fi
    src_tweak="${ONE_VAR}/remotes/vmm/kvm/deploy-tweaks.d.example/${tweak}"
    if [[ -f "${src_tweak}" ]]; then
        cp ${CP_ARG} "${src_tweak}" "${ONE_VAR}/remotes/vmm/kvm/deploy-tweaks.d/"
    fi
done

echo "*** chown -R ${ONE_USER}:${ONE_GROUP} ${ONE_VAR}/remotes ..."
chown -R "${ONE_USER}:${ONE_GROUP}" "${ONE_VAR}/remotes"

if boolTrue "STORPOOL_EXTRAS"; then
    if ! grep -q 'deploy=deploy-tweaks' /etc/one/oned.conf; then
        echo "!!! Please enable deploy-tweaks in the VM_MAD configuration"
    fi
fi

echo "*** Registering the vc-policy hook"
if onehook list -x >"${TMPDIR}/onehook.xml" 2>/dev/null; then
    vc_policy="$(xmlstarlet sel -t -m //HOOK -v NAME -o " COMMAND=" -v TEMPLATE/COMMAND -n "${TMPDIR}/onehook.xml" | grep vc-policy || true)"
    if [[ -n "${vc_policy}" ]]; then
        echo "--- already registered HOOK=${vc_policy}"
    else
        onehook create "${CWD}/misc/volumecare.hook"
    fi
else
    echo "Can't get hooks list. Is the opennebula service running?"
    echo "Please check the existance of the vc-policy hook"
    echo "and register it if missing 'onehook create ${CWD}/misc/volumecare.hook'"
fi

echo "*** Please sync hosts (onehost sync --force)"

echo "*** Please restart opennebula${end_msg:+ and $end_msg} service${end_msg:+s}"

if [ -n "$SUNSTONE_BACKUP" ] && [ -d "$SUNSTONE_BACKUP" ] ; then
    echo "*** There is a backup of the sunstone interface that could be removed in case of no issues"
    echo "*** (rm -rf $SUNSTONE_BACKUP)"
fi

echo "*** Please update RESERVED_CPU and RESERVED_MEM with the values from '/var/tmp/one/reserved.sh' run on each host"
