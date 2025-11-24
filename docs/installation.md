# Installation and upgrade

The installation instructions are for OpenNebula 6.4+.

If you are upgrading addon-storpool please read first the Upgrade notes section below!

## Prerequisites

See the *Requirements* section in [StorPool storage driver](../README.md).

## Pre-installation steps

### Front-end dependencies

```bash
 CentOS 7 front-end
yum -y install --enablerepo=epel jq xmlstarlet nmap-ncat pigz tar xmllint python36-lxml
```

```bash
 AlmaLinux 8 front-end
dnf -y install --enablerepo=epel jq xmlstarlet nmap-ncat pigz tar libxml2 python3-lxml
```

```bash
 Ubuntu 22.04/24.04 front-end
apt -y install tar jq xmlstarlet netcat pigz python3-lxml libxml2-utils
```

### Node dependencies

Also use when adding new hosts:

```bash
 CentOS 7 node-kvm
yum -y install --enablerepo=epel jq pigz python36-lxml xmlstarlet tar
```

```bash
 AlmaLinux 8 node-kvm
dnf -y install --enablerepo=epel jq pigz python3-lxml xmlstarlet tar
```

```bash
 Ubuntu 22.04/24.04 node-kvm
apt -y install jq xmlstarlet pigz python3-lxml libxml2-utils tar
```

## Getting the addon from GitHub

```bash
cd ~
git clone https://github.com/OpenNebula/addon-storpool
```

## Automated installation

The automated installation is best suitable for new deployments. The install script will try to do an upgrade if it detects that addon-storpool is already installed but it is possible to have errors due to non expected changes

If oned and sunstone services are on different servers it is possible to install only part of the integration:

* Set environment variable AUTOCONF=1 to enable the automatic configuration of driver defaults in the opennebula configuration.
* Run the install script as 'root' user and check for any reported errors or warnings:

```bash
cd addon-storpool
bash install.sh 2>&1 | tee install.log
```

## Manual installation

The following commands are related to latest Stable version of OpenNebula.

### oned related pieces

1. Copy the DATASTORE_MAD driver files.

   ```bash
   cp -a ~/addon-storpool/datastore/storpool /var/lib/one/remotes/datastore/
   
   # copy xpath_multi.py
   cp ~/addon-storpool/datastore/xpath_multi.py  /var/lib/one/remotes/datastore/
   ```

2. Copy the TM_MAD driver files.

   ```bash
   cp -a ~/addon-storpool/tm/storpool /var/lib/one/remotes/tm/
   ```

3. Copy the VM_MAD driver files.

   ```bash
   cp -a ~/addon-storpool/vmm/kvm/snapshot_* /var/lib/one/remotes/vmm/kvm/
   ```

4. Prepare the fix for the volatile disks (needs to be enabled in _/etc/one/oned.conf_).

   ```bash
   # copy the helper for deploy-tweaks
   cp -a ~/addon-storpool/vmm/kvm/deploy-tweaks* /var/lib/one/remotes/vmm/kvm/
   mkdir -p /var/lib/one/remotes/vmm/kvm/deploy-tweaks.d
   cd /var/lib/one/remotes/vmm/kvm/deploy-tweaks.d
   cp ../deploy-tweaks.d.example/volatile2dev.py .
   
   # the local attach_disk script
   cp -a ~/addon-storpool/vmm/kvm/attach_disk.storpool /var/lib/one/remotes/vmm/kvm/
   
   # the tmsave/tmrestore scripts
   cp -L ~/addon-storpool/vmm/kvm/tm* /var/lib/one/remotes/vmm/kvm/
   ```

5. Copy _reserved.sh_ helper tool to _/var/lib/one/remotes/_.

   ```bash
   cp -a ~/addon-storpool/misc/reserved.sh /var/lib/one/remotes/
   ```

6. Copy _storpool_probe.sh_ tool to _/var/lib/one/remotes/im/kvm-probes.d/host/system/_.

   ```bash
   cp -a ~/addon-storpool/misc/storpool_probe.sh /var/lib/one/remotes/im/kvm-probes.d/host/system/
   ```

7. Fix ownership of the files in _/var/lib/one/remotes/_.

   ```bash
   chown -R oneadmin.oneadmin /var/lib/one/remotes/vmm/kvm
   ```

8. Create `tmpfiles` configuration to create `/var/cache/addon-storpool-monitor`.

   ```bash
   cp -v addon-storpool/misc/etc/tmpfiles.d/addon-storpool-monitor.conf /etc/tmpfiles.d/
   systemd-tmpfiles --create
   ```

9. Create a systemd timer for stats polling (alter the file paths if needed)

   ```bash
   cp -v addon-storpool/misc/systemd/system/monitor_helper-sync* /etc/systemd/system/
   
   systemctl daemon-reload
   
   systemctl enable --now monitor_helper-sync.timer
   ```

## addon-storpool configuration

The global configuration of addon-storpool is in `/var/lib/one/remotes/addon-storpoolrc` file.

1. Edit `/etc/one/oned.conf` and add `storpool` to the `TM_MAD` arguments:

   ```
   TM_MAD = [
       executable = "one_tm",
       arguments = "-t 15 -d dummy,lvm,shared,fs_lvm,qcow2,ssh,vmfs,ceph,dev,storpool"
   ]
   ```

2. Edit `/etc/one/oned.conf` and add `storpool` to the `DATASTORE_MAD` arguments:

   ```
   DATASTORE_MAD = [
       executable = "one_datastore",
       arguments  = "-t 15 -d dummy,fs,vmfs,lvm,ceph,dev,storpool  -s shared,ssh,ceph,fs_lvm,qcow2,storpool"
   ]
   ```

3. When `storpool` backed SYSTEM datastore is used, edit `/etc/one/oned.conf` and update the ARGUMENTS of the `VM_MAD` for `KVM` to enable the deploy-tweaks script:

   ```
   VM_MAD = [
       NAME           = "kvm",
       SUNSTONE_NAME  = "KVM",
       EXECUTABLE     = "one_vmm_exec",
       ARGUMENTS      = "-l deploy=deploy-tweaks -t 15 -r 0 -p kvm",
       ...
   ```
   Optionally, add _attach_disk_, _tmsave_ and _tmrestore_:

   ```
   VM_MAD = [
       NAME           = "kvm",
       SUNSTONE_NAME  = "KVM",
       EXECUTABLE     = "one_vmm_exec",
       ARGUMENTS      = "-l deploy=deploy-tweaks,attach_disk=attach_disk.storpool,save=tmsave,restore=tmrestore -t 15 -r 0 -p kvm",
       ...
   ```

4. Edit `/etc/one/oned.conf` and append `TM_MAD_CONF` definition for StorPool:

   ```
   TM_MAD_CONF = [ NAME = "storpool", LN_TARGET = "NONE", CLONE_TARGET = "SELF", SHARED = "yes", DS_MIGRATE = "yes", DRIVER = "raw", ALLOW_ORPHANS = "yes", TM_MAD_SYSTEM = "" ]
   ```

5. Edit `/etc/one/oned.conf` and append `DS_MAD_CONF` definition for StorPool:

   ```
   DS_MAD_CONF = [ NAME = "storpool", REQUIRED_ATTRS = "DISK_TYPE", PERSISTENT_ONLY = "NO", MARKETPLACE_ACTIONS = "export" ]
   ```

6. Edit `/etc/one/oned.conf` and append the following _VM_RESTRICTED_ATTR_:

   ```bash
   cat >>/etc/one/oned.conf <<_EOF_
   VM_RESTRICTED_ATTR = "VMSNAPSHOT_LIMIT"
   VM_RESTRICTED_ATTR = "DISKSNAPSHOT_LIMIT"
   VM_RESTRICTED_ATTR = "VC_POLICY"
   VM_RESTRICTED_ATTR = "SP_QOSCLASS"
   _EOF_
   ```

7. Enable live disk snapshots support for StorPool by adding `kvm-storpool` to the `LIVE_DISK_SNAPSHOTS` variable in `/etc/one/vmm_exec/vmm_execrc`:

   ```
   LIVE_DISK_SNAPSHOTS="kvm-qcow2 kvm-ceph kvm-storpool"
   ```

8. `RAFT_LEADER_IP`

   The driver will try to autodetect the leader IP address from oned configuration; if it fails, set it manually in `addon-storpoolrc`:
   
   ```bash
   echo "RAFT_LEADER_IP=1.2.3.4" >> /var/lib/one/remotes/addon-storpoolrc
   ```

9. If you plan to do live disk snapshots with _fsfreeze_ via _qemu-guest-agent_ but `SCRIPTS_REMOTE_DIR` is not the default one (if it is changed in `/etc/one/oned.conf`), define `SCRIPTS_REMOTE_DIR` in the drivers configuration.


## Post-installation steps

1. Restart the `opennebula` service:

   ```bash
   systemctl restart opennebula
   ```
   
2. As oneadmin user (re)sync the remote scripts to the hosts:

   ```bash
   su - oneadmin -c 'onehost sync --force'
   ```

3. Add _oneadmin_ user to the _mysyslog_ group if available:

   ```bash
   grep -q mysyslog /etc/group && usermod -a -G mysyslog oneadmin
   ```

Follow the addon configuration steps in [OpenNebula configuration](one_configuration.md) to configure the driver.

## Upgrade

The suggested upgrade procedure is as follows:

1. Stop all opennebula services.
2. Upgrade the opennebula packages - but do *not* reconfigure anything yet.
3. Upgrade the addon (checkout/clone latest from github and run _AUTOCONF=1 bash install.sh_)
4. Follow the addon configuration steps in [OpenNebula configuration](one_configuration.md) to (re)configure the driver.
5. Continue (re)configuring OpenNebula following the upstream docs.

After upgrade:

1. Run `misc/tagVolumes.sh` to update/apply the common tags for volumes/snapshots.
2. Remove old _cron_ configuration files `/etc/cron.d/vc-policy`, `/etc/cron.d/addon-storpool`
3. Run the following code to update the StorPool volume tags

   ```bash
   source /var/lib/one/remotes/addon-storpoolrc && while read -r -u 4 volume; do storpool volume "${volume}" update tag nloc=${ONE_PX:-one} tag virt=one; done 4< <(storpool -B -j volume list | jq -r --arg onepx "${ONE_PX:-one}" '.data[]|select(.name|startswith($onepx))|.name')
   ```
