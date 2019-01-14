#!/bin/bash
#

# -------------------------------------------------------------------------- #
# Copyright 2015-2020, StorPool (storpool.com)                               #
#                                                                            #
# Portions copyright OpenNebula Project (OpenNebula.org), CG12 Labs          #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #

# The scrpt must be run from OpenNebula's front-end server as oneadmin user.
# The oneadmin user must have passwordless ssh access to the KVM nodes.

#set -x

DRY_RUN=${DRY_RUN+echo }
ONE_LOCATION=${ONE_LOCATION:-/var/lib/one}
ONE_PX="${ONE_PX:-one}"

unset i XPATH_ELEMENTS
while read -u 5 -r element; do
    XPATH_ELEMENTS[i++]="$element"
done 5< <(onevm list -x | ${ONE_LOCATION}/remotes/datastore/xpath_multi.py -s \
                    /VM_POOL/VM/ID \
                    /VM_POOL/VM/NAME \
                    /VM_POOL/VM/DEPLOY_ID \
                    /VM_POOL/VM/STATE \
                    /VM_POOL/VM/TEMPLATE/CONTEXT/DISK_ID \
                    /VM_POOL/VM/HISTORY_RECORDS/HISTORY/HOSTNAME \
                    /VM_POOL/VM/HISTORY_RECORDS/HISTORY/DS_LOCATION \
                    /VM_POOL/VM/HISTORY_RECORDS/HISTORY/DS_ID)
unset i
_VM_ID=${XPATH_ELEMENTS[i++]}
_VM_NAME=${XPATH_ELEMENTS[i++]}
_VM_DEPLOY_ID=${XPATH_ELEMENTS[i++]}
_VM_STATE=${XPATH_ELEMENTS[i++]}
_VM_CONTEXT_DISK_ID=${XPATH_ELEMENTS[i++]}
_VM_HISTORY_HOSTNAME=${XPATH_ELEMENTS[i++]}
_VM_HISTORY_DS_LOCATION=${XPATH_ELEMENTS[i++]}
_VM_HISTORY_DS_ID=${XPATH_ELEMENTS[i++]}

_OLDIFS=$IFS
IFS=";"
VM_ID_ARRAY=($_VM_ID)
VM_NAME_ARRAY=($_VM_NAME)
VM_DEPLOY_ID_ARRAY=($_VM_DEPLOY_ID)
VM_STATE_ARRAY=($_VM_STATE)
VM_CONTEXT_DISK_ID_ARRAY=($_VM_CONTEXT_DISK_ID)
VM_HISTORY_HOSTNAME_ARRAY=($_VM_HISTORY_HOSTNAME)
VM_HISTORY_DS_LOCATION_ARRAY=($_VM_HISTORY_DS_LOCATION)
VM_HISTORY_DS_ID_ARRAY=($_VM_HISTORY_DS_ID)
IFS=$_OLDIFS

for i in ${!VM_ID_ARRAY[@]}; do
    VM_ID=${VM_ID_ARRAY[i]}
    VM_NAME=${VM_NAME_ARRAY[i]}
    DEPLOY_ID=${VM_DEPLOY_ID_ARRAY[i]}
    DISK_ID=${VM_CONTEXT_DISK_ID_ARRAY[i]}
    HOST=${VM_HISTORY_HOSTNAME_ARRAY[i]}
    DS_LOCATION=${VM_HISTORY_DS_LOCATION_ARRAY[i]}
    DS_ID=${VM_HISTORY_DS_ID_ARRAY[i]}
    STATE=${VM_STATE_ARRAY[i]}
    DISK=${DS_LOCATION}/${DS_ID}/${VM_ID}/disk.${DISK_ID}
    if [ $STATE -eq 9 ]; then
        HOST=$HOSTNAME
    fi
    echo "$VM_ID $DEPLOY_ID '$VM_NAME' CONTEXT_DISK_ID:$CONTEXT_DISK_ID $HOST:${DISK}"
    SP_VOL="${ONE_PX}-sys-${VM_ID}-${DISK_ID}-iso"
    SP_LINK="/dev/storpool/$SP_VOL"
    SP_TEMPLATE="${ONE_PX}-ds-$DS_ID"
    SP_SIZE=$(ssh $HOST "[ -f $DISK ] && du -b $DISK | cut -f1")
    SP_SIZE=$(( (SP_SIZE +511) /512 *512 ))
    if [ $SP_SIZE -eq 0 ]; then
        echo "Can't get size of $HOST:$DISK"
        continue
    fi
    $DRY_RUN ssh $HOST "export PATH=/usr/sbin:\$PATH && storpool volume $SP_VOL template $SP_TEMPLATE size $SP_SIZE"
    $DRY_RUN ssh $HOST "export PATH=/usr/sbin:\$PATH && storpool attach volume $SP_VOL here"
    sleep 3 # udevd sometimes is lagging
    $DRY_RUN ssh $HOST "set -x && [ -L \"$SP_LINK\" ] && [ -f $DISK ] && dd if=$DISK of=$SP_LINK && mv $DISK $DISK.backup && ln -s $SP_LINK $DISK"
    if [ $STATE -eq 9 ]; then
        $DRY_RUN ssh $HOST "export PATH=/usr/sbin:\$PATH && storpool detach volume $SP_VOL here"
    fi
 done
