### Migrate with postcopy

#### Installation

```bash
cd /var/lib/one/
patch -p1 path/to/addon-storpool/misc/MigrateTimeout.patch
```

#### Configuration

```bash
echo "MIGRATE_OPTIONS=\"--postcopy --postcopy-after-precopy\"" >>/var/lib/one/remotes/etc/vmm/kvm/kvmrc
```

