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
