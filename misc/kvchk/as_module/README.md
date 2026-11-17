# StorPool consistency check

## Building as package

```
cd kvchk/as_module
/opt/storpool/python3/bin/python3 -m build
cp dist/storpool_kvchk*tar.gz ~oneadmin
```

## Installing in a virtual environment

```
sudo -i -u oneadmin
mkdir -p kvchk
cd kvchk
/opt/storpool/python3/bin/python3 -m venv .venv --system-site-packages
.venv/bin/python3 -m pip install -U pip
.venv/bin/python3 -m pip install -U ../storpool_kvchk-0.1.0.tar.gz

```

## Running

```
sudo -i -u oneadmin
kvchk/.venv/bin/sp-kvchk              # report only
kvchk/.venv/bin/sp-kvchk --execute    # also apply the repairs it queues
```

The settings default to the values in `addon-storpoolrc`. The findings are
printed and written to `YYYYmmdd-HHMM-<category>.txt` files in the current
directory (`--no-report` turns the files off); `sp-kvchk --help` lists the
options and the categories.

## Backup checks

Backup leftovers are only reported, never removed. StorPool objects younger
than `--hanging-min-age` seconds (3600 by default) are not reported as
hanging, so a backup in progress is not mistaken for a leftover.

* `hanging`: a snapshot of a StorPool backup datastore backup that no backup
  image refers to, while its VM is not in a backup state; a service volume
  that outlived its backup; a snapshot of an interactive (OneBEX) backup
  whose VM has left the backup state or has a later backup snapshot.
* KV records of the StorPool backup datastore that no backup image refers to,
  or whose snapshot ids differ from the backup image, are reported as issues.
