# Quick integration test


## Operations

The test is in `misc/integration-test.sh`. It performs a basic integration test to verify the basic functionality of StorPool's add-on for OpenNebula. It must be run on the front-end node of the OpenNebula deployment 

The following tasks are peformed:

* A test template is downloaded from the marketplace in a StorPool datastore;
  * This can be skipped by providing a template to the script.
* A VM is instantiated from this template on a StorPool datastore and waited to become running;
* The VM is migrated live to another host and then back. In both cases it's waited to become running before proceeding;
* The VM is powered off, moved again to another host, and powered on;
* The VM is again powered off, moved back, and powered on;
* An extra image is created in the StorPool datastore;
* The image is attached live to the VM;
* The image is detached live from the VM;
* The image is removed;
* The VM is removed.

All tasks wait for completion and bail out if they don't happen in a specific time frame.

Please note that all test are related to the operations of the storage and add-on. No tests on the network or other VM functionality are performed.

## Usage


```
Usage: integration-test.sh host1 host2 [template]
```

`host1` and `host2` are two hosts used to perform the migration. Their names (names, *not* ids) must be taken from `onehost list` and must be running hosts with StorPool enabled and running.

`template` is optional and is the name of a template to instantiate the VM, as seen in `onetemplate list`. If not provided, the script will create one called `t-SPTEST.fadCarlarr-tmpl` by downloading the last listed CentOS 7 KVM one available in the marketplace.

## Example output


```
[oneadmin@hci-storpool01 misc]$ bash integration-test.sh hv01.example.com hv01.example.com t-SPTEST.fadCarlarr-tmpl
Using datastore: 1 (default)
Creating VM SPTEST.fadCarlarr...VM ID: 4
done, id 4 host hci-storpool02.
Migrating live to hci-storpool01...done, now on hci-storpool01.
Migrating live back to hci-storpool02...done, now on hci-storpool02.
Powering off...done.
Moving to hci-storpool01...done, now on hci-storpool01.
Powering up...done.
Powering off again...done.
Moving back to hci-storpool02... done, now on hci-storpool02.
Powering up...done.
Creating test image...done, id 5.
Attaching image 5 to vm 4...done.
Detaching disk 2 from vm 4...done.
Removing image 5...done.
Removing SPTEST.fadCarlarr...done.
Validation passed.
```
