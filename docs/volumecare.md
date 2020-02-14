# StorPool Volumecare

StorPool Volumecare is a framework to schedule and maintain recovery snapshots in StorPool. This integration allows specifying snapshot policies per VM from within the ONE interface by introducing new VM template variable _VC_POLICY_.


## Installation

The following commands should be applied on all frontend controllers.

```bash
# copy the hook files
cp -a addon-storpool/hooks/volumecare /var/lib/one/remotes/hooks/

# fix ownership
chown -R oneadmin.oneadmin /var/lib/one/remotes

# register the hook
onehook create addon-storpool/misc/volumecare.hook

# create crontab file
cat >/etc/cron.d/vc-policy <<EOF
# addon-storpool vc-policy safeguard
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=oneadmin
0 */2 * * * oneadmin /var/lib/one/remotes/hooks/volumecare/volumecare 2>&1 >/tmp/volumecare_cron.err
EOF
```

## Configuration

```bash
# restrict the VC_POLICY variable to the 'oneadmin' group only
echo 'VM_RESTRICTED_ATTR = "VC_POLICY"' >>/etc/one/oned.conf

# restart the opennebula service
systemctl restart opennebula.service
```

## Usage

Set the _VC_POLICY_ variable in the VM's _USER_TEMPLATE_ with the corresponding volumecare policy.
To disable the volumecare delete the _VC_POLICY_ variable from the VM's _USER_TEMPLATE_(or set to an empty string).

## Troubleshooting

* Monitor the hook events logged in the Hook Manager

```bash
$ onehook list
  ID NAME                TYPE    
   1 vc-policy           api
   0 vnm_filter          state

$ onehook  show 1
HOOK 1 INFORMATION                                                              
ID                : 1                   
NAME              : vc-policy           
TYPE              : api                 
LOCK              : None                

HOOK TEMPLATE                                                                   
ARGUMENTS="$API"
ARGUMENTS_STDIN="YES"
CALL="one.vm.update"
COMMAND="volumecare/vc-policy.sh"
REMOTE="NO"

EXECUTION LOG
   ID       TIMESTAMP    RC EXECUTION
   10     01/21 16:28     0 SUCCESS
   11     01/21 16:29     0 SUCCESS
   12     01/21 16:31     0 SUCCESS
   13     01/21 16:32     0 SUCCESS
   14     01/21 16:33     0 SUCCESS
   15     01/21 16:35     0 SUCCESS
   16     01/21 16:39     0 SUCCESS
   17     01/21 16:40     0 SUCCESS
   18     01/21 16:42   127   ERROR
   19     01/21 16:44     0 SUCCESS
   20     01/21 16:50     0 SUCCESS
   21     01/21 17:09     0 SUCCESS
   22     01/22 15:01   127   ERROR
   23     01/22 15:02   127   ERROR
   24     01/22 15:09   127   ERROR
   25     01/22 15:11     0 SUCCESS
   26     01/22 15:18     0 SUCCESS
   27     01/22 17:40     0 SUCCESS
   28     01/22 17:40     0 SUCCESS
   29     01/22 17:42     0 SUCCESS

$ onehook show 1 -e 18
HOOK 1 INFORMATION                                                              
ID                : 1                   
NAME              : vc-policy           
TYPE              : api                 
LOCK              : None                

HOOK EXECUTION RECORD                                                           
EXECUTION ID      : 18                  
TIMESTAMP         : 01/21 16:42:47      
COMMAND           : /var/lib/one/remotes/hooks/volumecare/vc-policy.sh
ARGUMENTS         : <CALL_INFO>
  <RESULT>1</RESULT>
  <PARAMETERS>
    <PARAMETER>
      <POSITION>1</POSITION>
      <TYPE>IN</TYPE>
      <VALUE>****</VALUE>
    </PARAMETER>
    <PARAMETER>
      <POSITION>2</POSITION>
      <TYPE>IN</TYPE>
      <VALUE>59</VALUE>
    </PARAMETER>
    <PARAMETER>
      <POSITION>3</POSITION>
      <TYPE>IN</TYPE>
      <VALUE>INPUTS_ORDER = ""
LOGO = "images/logos/centos.png"
MEMORY_UNIT_COST = "MB"
VC_POLICY = "cust-main-remote1"
</VALUE>
    </PARAMETER>
    <PARAMETER>
      <POSITION>4</POSITION>
      <TYPE>IN</TYPE>
      <VALUE>0</VALUE>
    </PARAMETER>
    <PARAMETER>
      <POSITION>1</POSITION>
      <TYPE>OUT</TYPE>
      <VALUE>true</VALUE>
    </PARAMETER>
    <PARAMETER>
      <POSITION>2</POSITION>
      <TYPE>OUT</TYPE>
      <VALUE>59</VALUE>
    </PARAMETER>
    <PARAMETER>
      <POSITION>3</POSITION>
      <TYPE>OUT</TYPE>
      <VALUE>0</VALUE>
    </PARAMETER>
  </PARAMETERS>
  <EXTRA/>
</CALL_INFO> 
EXIT CODE         : 127                 

EXECUTION STDOUT                                                                


EXECUTION STDERR                                                                

```

* monitor the messages logged in the system logs

```bash
$ grep vc_sp_ /var/log/messages
Jan 22 17:42:22 vs04 vc_sp_vc-policy.sh: /var/lib/one/remotes/hooks/volumecare/volumecare '185'
Jan 22 17:42:23 vs04 vc_sp_volumecare[20066]: (0) onedatastore list  -x >/tmp/tmp.4sUnQoi7ll/datastorePool.xml
Jan 22 17:42:24 vs04 vc_sp_volumecare[20066]: volume:one-img-24-185-0 current vc-policy: new:monthly
Jan 22 17:42:24 vs04 vc_sp_volumecare[20066]: storpool volume one-img-24-185-0 tag vc-policy=monthly
Jan 22 17:42:24 vs04 vc_sp_volumecare[20066]: volume:one-img-26-185-1 current vc-policy: new:monthly
Jan 22 17:42:24 vs04 vc_sp_volumecare[20066]: storpool volume one-img-26-185-1 tag vc-policy=monthly
```
