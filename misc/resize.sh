#!/bin/bash
#
# -------------------------------------------------------------------------- #
# Copyright 2015-2018, StorPool (storpool.com)                               #
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

VM_ID="$1"
DISK_ID="$2"
DISK_SIZE="$3"
DB="$4"

if [ "$DB" = "" ]; then
  DB="sqlite3:/var/lib/one/one.db"
fi

usage()
{
  [ -n "$1" ] && echo -e "ee\nee Error: $*\nee\n"
  echo "$0 <VM_ID> <DISK_ID> <SIZE> <DBconn>"
  echo
  echo "Note: the SIZE should be in MiB"
  echo "DBconn could be eny of"
  echo "  'sqlite3:/path/to/one.db'"
  echo "  'mysql:<dbUser>:<dbPassword>:<dbHost>:<dbName>'"
  echo
  exit 1
}

if [ -n "$VM_ID" ]; then
  if [ -n "${VM_ID//[[:digit:]]/}" ]; then
    usage "VM_ID '$VM_ID' should be a numer!"
  fi
else
  usage "VM_ID is empty! Please provide VM id"
fi
if [ -n "$DISK_ID" ]; then
  if [ -n "${DISK_ID//[[:digit:]]/}" ]; then
    usage "DISK_ID '$DISK_ID' should be a numer!"
  fi
else
  usage "DISK_ID is empty! Please provide disk id"
fi
if [ -n "$DISK_SIZE" ]; then
  if [ -n "${DISK_SIZE//[[:digit:]]/}" ]; then
    usage "SIZE '$DISK_SIZE' should be a numer!"
  fi
else
  usage "SIZE is empty! Please provide the size in MiB"
fi

DRIVER_PATH="${DRIVER_PATH:-"/var/lib/one/remotes"}"

XPATH="${DRIVER_PATH}/datastore/xpath.rb --stdin"

unset i j XPATH_ELEMENTS

while IFS= read -r -d '' element; do
    XPATH_ELEMENTS[i++]="$element"
done < <(onevm show -x $VM_ID |tee vm-${VM_ID}.xml| $XPATH \
                    /VM/DEPLOY_ID \
                    /VM/LCM_STATE \
                    /VM/TEMPLATE/DISK[DISK_ID=$DISK_ID]/SIZE \
                    /VM/TEMPLATE/DISK[DISK_ID=$DISK_ID]/ORIGINAL_SIZE \
                    /VM/TEMPLATE/DISK[DISK_ID=$DISK_ID]/SOURCE \
                    /VM/TEMPLATE/DISK[DISK_ID=$DISK_ID]/CLONE \
                    /VM/HISTORY_RECORDS/HISTORY[last\(\)]/HOSTNAME)

DEPLOY_ID="${XPATH_ELEMENTS[j++]}"
LCM_STATE="${XPATH_ELEMENTS[j++]}"
SIZE="${XPATH_ELEMENTS[j++]}"
ORIGINAL_SIZE="${XPATH_ELEMENTS[j++]}"
SOURCE="${XPATH_ELEMENTS[j++]}"
CLONE="${XPATH_ELEMENTS[j++]}"
VMHOST="${XPATH_ELEMENTS[j++]}"

if [ -n "$CLONE" ]; then
  SP_VOL="${SOURCE##*/}"
  if [ "$CLONE" = "YES" ]; then
    SP_VOL+="-$VM_ID-$DISK_ID"
  fi
else
  echo "ee Can't get disk info from OpenNebula for DISK_ID:$DISK_ID on VM with ID:$VM_ID!"
  exit 1
fi
if [ -n "$DEBUG" ]; then
  echo "LCM_STATE:$LCM_STATE SIZE:$SIZE ORIGINAL_SIZE:$SIZE VMHOST:$VMHOST"
  #echo "CLONE:$CLONE SOURCE:$SOURCE"
  echo "DEPLOY_ID:$DEPLOY_ID SP_VOL=$SP_VOL"
fi

# resize the StorPool volume
echo "ii Resizing $SP_VOL to ${DISK_SIZE}M ..."
storpool volume "$SP_VOL" size ${DISK_SIZE}M >/dev/null
ret=$?
if [ $ret -ne 0 ]; then
  echo "ee Failed to resize the StorPool volume $SP_VOL (exit status:$ret)"
  exit $ret
else
  echo "ii $SP_VOL resized"
fi

source "${DRIVER_PATH}/vmm/kvm/kvmrc"

while IFS=',' read -r device drv filename; do
  device=${device//\"/}
  drv=${drv//\"/}
  filename=${filename//\"/}
  if [ "${filename##*\.}" = "$DISK_ID" ]; then
    qemu_device="$device"
    qemu_file="$filename"
    break
  fi
  if [ -n "$DEBUG" ]; then
    echo "$device | $drv | $filename"
  fi
done < <(su - oneadmin -c "ssh $VMHOST \"virsh --connect $LIBVIRT_URI qemu-monitor-command \\\"$DEPLOY_ID\\\"  '{\\\"execute\\\":\\\"query-block\\\"}'\"" 2>/dev/null \
| jq -r ".return[]|[.device,.inserted.drv,.inserted.image.filename]|@csv")

if [ -n "$qemu_device" ]; then
  echo "ii Found $qemu_device >>> $device | $drv | $filename"
  if [ -n "$DEBUG" ]; then
    set -x
  fi
#    su - oneadmin -c "ssh $VMHOST 'virsh --connect $LIBVIRT_URI qemu-monitor-command \"$DEPLOY_ID\" --hmp \"block_resize $qemu_device ${DISK_SIZE}M\"'"
  su - oneadmin -c "ssh $VMHOST 'virsh --connect $LIBVIRT_URI blockresize \"$DEPLOY_ID\" --path $qemu_file --size ${DISK_SIZE}M'"
  ret=$?
  if [ $ret -eq 0 ]; then
    su - oneadmin -c "ssh $VMHOST 'virsh --connect $LIBVIRT_URI qemu-monitor-command \"$DEPLOY_ID\" --hmp \"info block\"'"
    su - oneadmin -c "ssh $VMHOST 'virsh --connect $LIBVIRT_URI qemu-monitor-command \"$DEPLOY_ID\" --hmp \"info blockstats\"'"
  else
    echo "ww Warning: virsh blockresize $DEPLOY_ID --path $qemu_file --size ${DISK_SIZE}M ($ret)"
    echo "ww The VM needs a power cycle to recognize the new size"
  fi
else
  echo "ww Can't find the qemu device. Is the VM running?"
  echo "ww The VM needs a power cycle to recognize the new size"
fi

echo "ii Stopping opennebula"
systemctl stop opennebula

slp=5
echo "ii waiting $slp seconds..."
sleep $slp

echo "ii Updating the disk size in the database"
./resize.py "$VM_ID" "$DISK_ID" "$DISK_SIZE" "$DB"

echo "ii Starting opennebula"
systemctl start opennebula

echo "ii Done."
