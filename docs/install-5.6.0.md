# For OpenNebula 5.6.x-

## Installation

If you are upgrading the addon please read the [Upgrade notes](../README.md#upgrade-notes) first!

### Pre-install

#### front-end dependencies

```bash
# on the front-end
yum -y install --enablerepo=epel patch git jq lz4 npm
```

#### node dependencies

 :grey_exclamation:*use when adding new hosts too*:grey_exclamation:

```bash
yum -y install --enablerepo=epel jq lz4 python-lxml
```

### Get the addon from github
```bash
cd ~
git clone https://github.com/OpenNebula/addon-storpool
```

### automated installation
The automated installation is best suitable for new deployments. The install script will try to do an upgrade if it detects that addon-storpool is already installed but it is possible to have errors due to non expected changes

* Run the install script as 'root' user and check for any reported errors or warnings
```bash
bash ~/addon-storpool/install.sh
```
If oned and sunstone services are on different servers it is possible to install only part of the integration:
 * set environment variable SKIP_SUNSTONE=1 to skip the sunstone integration
 * set environment variable SKIP_ONED=1 to skip the oned integration

### manual installation

The following commands are related to latest OpenNebula version.

#### oned related pieces

* Copy storpool's DATASTORE_MAD driver files
```bash
cp -a ~/addon-storpool/datastore/storpool /var/lib/one/remotes/datastore/

# copy xpath_multi.py
cp ~/addon-storpool/datastore/xpath_multi.py  /var/lib/one/remotes/datastore/

# fix ownership
chown -R oneadmin.oneadmin /var/lib/one/remotes/datastore/storpool /var/lib/one/remotes/datastore/xpath_multi.py

```

* Copy storpool's TM_MAD driver files
```bash
cp -a ~/addon-storpool/tm/storpool /var/lib/one/remotes/tm/

# fix ownership
chown -R oneadmin.oneadmin /var/lib/one/remotes/tm/storpool
```

* Copy storpool's VM_MAD driver files
```bash
cp -a ~/addon-storpool/vmm/kvm/snapshot_* /var/lib/one/remotes/vmm/kvm/

# fix ownership
chown -R oneadmin.oneadmin /var/lib/one/remotes/vmm/kvm
```

* Patch IM_MAD/kvm-probes.d/monitor_ds.sh
OpenNebula collect datastore space only for integrated drivers. This patch enable reporting of datastore space from StorPool.
```bash
pushd /var/lib/one
patch -p0 <~/addon-storpool/patches/im/5.2/00-monitor_ds.patch
popd
```

* Patch TM_MAD/shared/monitor
OpenNebula collect disk stats for integrated drivers. This patch enable disks stats reporting for addon drivers.
```bash
pushd /var/lib/one
patch --backup -p0 <~/addon-storpool/patches/tm/5.0/00-shared-monitor.patch
popd
```

* Patch TM_MAD/ssh/monitor_ds
OpenNebula collect disk stats for integrated drivers. This patch enable disks stats reporting for addon drivers.
```bash
pushd /var/lib/one
patch --backup -p0 <~/addon-storpool/patches/tm/5.0/00-ssh-monitor_ds.patch
popd
```

* Create cron job for stats polling (fix the file paths if needed)
```bash
cat >>/etc/cron.d/addon-storpool <<_EOF_
# StorPool
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=oneadmin
*/4 * * * * oneadmin /var/lib/one/remotes/datastore/storpool/monitor_helper-sync 2>&1 >/tmp/monitor_helper_sync.err
_EOF_
```

If upgrading, please delete the old style cron tasks
```bash
crontab -u oneadmin -l | grep -v monitor_helper-sync | crontab -u oneadmin -
crontab -u root -l | grep -v "storpool -j " | crontab -u root -
```

#### sunstone related pieces

* Patch and rebuild the sunstone interface
```bash
# First do a backup of the sunstone/public folder
cp -a /usr/lib/one/sunstone/public{,-bak-$(date +%s)}

pushd /usr/lib/one/sunstone/public

# patch the sunstone interface to update the Datastore Wizard to support StorPool
patch -b -V numbered -N -p0 <~/addon-storpool/patches/sunstone/5.4.1/datastores-tab.patch
# patch the sunstone interface to enable VM snapshots deletion when VM is powered off
patch -b -V numbered -N -p0 <~/addon-storpool/patches/sunstone/5.4.1/vms-tab.patch

# rebuild the interface
./build.sh -d
export PATH=$PATH:$PWD/node_modules/.bin
./build.sh

popd

# Don't forget to delete the created backup after configmig that sunstone works
# rm -fr /usr/lib/one/sunstone/public-bak-*
```

### addon configuration
The global configuration of addon-storpool is in `/var/lib/one/remotes/addon-storpoolrc` file.


* Add the `oneadmin` user to group `disk` on all nodes
```bash
usermod -a -G disk oneadmin
```

* Edit `/etc/one/oned.conf` and add `storpool` to the `TM_MAD` arguments
```
TM_MAD = [
    executable = "one_tm",
    arguments = "-t 15 -d dummy,lvm,shared,fs_lvm,qcow2,ssh,vmfs,ceph,dev,storpool"
]
```

* Edit `/etc/one/oned.conf` and add `storpool` to the `DATASTORE_MAD` arguments

```
DATASTORE_MAD = [
    executable = "one_datastore",
    arguments  = "-t 15 -d dummy,fs,vmfs,lvm,ceph,dev,storpool  -s shared,ssh,ceph,fs_lvm,qcow2,storpool"
]
```

* Edit `/etc/one/oned.conf` and append `TM_MAD_CONF` definition for StorPool
```
TM_MAD_CONF = [ NAME = "storpool", LN_TARGET = "NONE", CLONE_TARGET = "SELF", SHARED = "yes", DS_MIGRATE = "yes", DRIVER = "raw", ALLOW_ORPHANS = "yes" ]
```

* Edit `/etc/one/oned.conf` and append DS_MAD_CONF definition for StorPool
```
DS_MAD_CONF = [ NAME = "storpool", REQUIRED_ATTRS = "DISK_TYPE", PERSISTENT_ONLY = "NO", MARKETPLACE_ACTIONS = "" ]
```

* Edit `/etc/one/oned.conf` and append the following _VM_RESTRICTED_ATTR_
```bash
cat >>/etc/one/oned.conf <<EOF
VM_RESTRICTED_ATTR = "VMSNAPSHOT_LIMIT"
VM_RESTRICTED_ATTR = "DISKSNAPSHOT_LIMIT"
EOF
```

* Enable live disk snapshots support for StorPool by adding `kvm-storpool` to `LIVE_DISK_SNAPSHOTS` variable in `/etc/one/vmm_exec/vmm_execrc`
```
LIVE_DISK_SNAPSHOTS="kvm-qcow2 kvm-ceph kvm-storpool"
```

* RAFT_LEADER_IP

The addon will try to autodetect the leader IP address from oned configuration but if it fail set it manually in addon-storpoolrc
```bash
echo "RAFT_LEADER_IP=1.2.3.4" >> /var/lib/one/remotes/addon-storpoolrc
```

* If you plan to do live disk snapshots with fsfreeze via qemu-guest-agent but `SCRIPTS_REMOTE_DIR` is not the default one (if it is changed in `/etc/one/oned.conf`), define `SCRIPTS_REMOTE_DIR` in the addon global configuration.

### Post-install
* Restart `opennebula` and `opennebula-sunstone` services
```bash
service opennebula restart
service opennebula-sunstone restart
```
* As oneadmin user (re)sync the remote scripts
```bash
su - oneadmin -c 'onehost sync --force'
```

* Check that Sunstone works and the _New Datastore Wizard_ is showing StorPool in the _Storage backend_. Remove the backup of sunstone/public folder.
```bash
rm -fr /usr/lib/one/sunstone/public-bak-*
```
