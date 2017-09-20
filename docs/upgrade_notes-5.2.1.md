### Upgrade from 5.2.1 or older

##### SP_SYSTEM=ssh
When a SYSTEM datastore is with `TM_MAD=storpool` is on shared filesystem set `SP_SYSTEM=shared` in the addon configuration file

```
ONE_LOCATION=/var/lib/one
echo "SP_SYSTEM=shared" >>$ONE_LOCATION/remotes/addon-storpoolrc
```

##### AUTO_TEMPLATE=0
It was possible to manage the StorPool templates using variables in the datastore templates.
To restore this code:

```
ONE_LOCATION=/var/lib/one
echo "AUTO_TEMPLATE=1" >>$ONE_LOCATION/remotes/addon-storpoolrc
```

