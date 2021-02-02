### Migrate with postcopy

The following steps shoulc be executed on the Frontend node(s)

#### Installation

```bash
cd /var/lib/one/
patch -p1 path/to/addon-storpool/misc/MigrateTimeout.patch
```

#### Configuration

```bash
echo "MIGRATE_OPTIONS=\"--postcopy --postcopy-after-precopy\"" >>/var/lib/one/remotes/etc/vmm/kvm/kvmrc
```

#### Propagate the change

(On Frontend HA setups this step should be executed only on the _leader_ node)

```bash
su - oneadmin -c 'onehost sync --force'
```
