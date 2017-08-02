### Upgrade to 5.2.1

It is highly recommended to install `qemu-kvm-ev` package from `centos-release-kvm-ev` reposytory.

When the addon is run on clean opennebula configuration, the essential defaults will be applied. So the suggested upgrade procedure is as follow

The suggested upgrade procedure is as follow

1. Stop all opennebula services
1. Upgrade the opennebula packages. But not reconfigure anything yet
1. Upgrade the addon (checkout/clone latest from github and run install.sh)
2. Follow the addon configuration chapter in [README.md](../READMEmd)  if there are extras needed to be configured
1. Continue with the configuration of OpenNebula

#### Changed default variables

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
