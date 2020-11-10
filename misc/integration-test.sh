#!/bin/bash
#
# -------------------------------------------------------------------------- #
# Copyright 2015-2020, StorPool (storpool.com)                               #
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

set -e

SLP=1

# nobody else will create this.
# hopefuly.
VM_NAME=SPTEST.fadCarlarr

function xmlget()
{
    local XPATH="$1" ENTRY="$2"
    xmlstarlet sel -t -m "$XPATH" -v "$ENTRY" $3
}

function do_waitfor() {
	local NAME="$1" CMD="$2" STATE="$3" TIMEOUT="${4:-60}"
	local SEC=0 CSTATE= DO_CMD="$CMD list --list STAT,ID,NAME --csv"

	while [ $SEC -lt $TIMEOUT ]; do
		CSTATE=$($DO_CMD | grep -E ",$NAME\$"|cut -d, -f1)
        [ -z "$DEBUG" ] || echo "  $NAME $CSTATE waiting for $STATE #$SEC::$TIMEOUT //$DO_CMD" 
		if [ "$CSTATE" = "$STATE" ]; then
			return 0
		fi
		sleep $SLP
		SEC=$((SEC + SLP))
	done
    return 1
}

function waitforimg() {
	do_waitfor "$1" oneimage "$2" "$3"
}

function waitforvm() {
	do_waitfor "$1" onevm "$2" "$3"
}

function die() {
	echo "ERROR: $1"
	exit 5
}

if ! which storpool &>/dev/null; then
	echo "storpool cli not installed?"
	exit 2
fi

if ! which onevm &>/dev/null; then
	echo "ONE cli not installed?"
	exit 2
fi

if ! [ -d /var/lib/one/remotes/datastore/storpool ] ||\
   ! [ -d /var/lib/one/remotes/tm/storpool ] ; then
	echo "addon-storpool not installed?"
	exit 2
fi

if [ -z "$2" ]; then
	echo "Usage: $0 host1 host2 '[templateid]'"
	echo 
	onehost list
	exit 2
fi

DATA_DIR="$0.DATA"
mkdir -p "$DATA_DIR"

HOST1="$1"
HOST2="$2"

CLUSTER_ID1="$(onehost show "$HOST1" --xml |\
    tee "${DATA_DIR}/host-${HOST1}.XML" |\
    xmlget '//HOST' 'CLUSTER_ID')"
CLUSTER_ID2="$(onehost show "$HOST2" --xml |\
    tee "${DATA_DIR}/host-${HOST2}.XML" |\
    xmlget '//HOST' 'CLUSTER_ID')"

if [ "$HOST_ID_1" != "$HOST_ID_2" ] ; then
	echo cluster IDs of both hosts do not match, exiting.
	exit 2
fi

IMAGE_DS_ID="$(onedatastore list --xml |\
    xmlget "//DATASTORE[TM_MAD=\"storpool\" and TYPE=0 and CLUSTERS[ID=$CLUSTER_ID1]]" "ID" -n |\
    tail -n 1)"
if [ -z "$IMAGE_DS_ID" ]; then
    die "Can't find IMAGE datastore with TM_MAD=storpool."
fi

IMAGE_DS_NAME="$(onedatastore show "$IMAGE_DS_ID" --xml |\
    xmlget "//DATASTORE" NAME)"

if onevm list --xml | xmlget "//VM[NAME=\"$VM_NAME\"]" ID -n; then
	echo -n "* Test VM '$VM_NAME' exists, cleaning up..."
	onevm terminate --hard "$VM_NAME"
    echo " Done."
fi

echo "* Using IMAGE datastore: $IMAGE_DS_ID ($IMAGE_DS_NAME)"

if [ -n "$3" ]; then
	VM_TEMPLATE_NAME="$3"
	deltemplate=n
else
	VM_TEMPLATE_NAME="t-${VM_NAME}-tmpl"
	
	if ! onetemplate show "$VM_TEMPLATE_NAME" &> /dev/null; then
		TEMPLATE_ID="$(onemarketapp list -f NAME~'Ubuntu 18.04',TYPE=img,STAT=rdy -l ID,NAME --csv |\
            tail -n 1 | cut -d, -f 1)"
		echo "* Downloading template $TEMPLATE_ID from OpenNebula Marketplace as '$VM_TEMPLATE_NAME'..."
		onemarketapp export "$TEMPLATE_ID" "$VM_TEMPLATE_NAME" --datastore "$IMAGE_DS_ID"
	fi

	echo -n "* Waiting for template image '$VM_TEMPLATE_NAME' to become ready..."
	waitforimg "$VM_TEMPLATE_NAME" rdy 300 || die "VM Tmeplate download timed out."
	echo "-- Done."
	deltemplate=y
fi

echo "* Creating VM $VM_NAME from Template $VM_TEMPLATE_NAME ..."
onetemplate instantiate "$VM_TEMPLATE_NAME" --name "$VM_NAME"
waitforvm "$VM_NAME" runn 120 || die "Failed to instantiate VM $VM_NAME!"
VM_ID=$(onevm show "$VM_NAME" --xml | tee "${DATA_DIR}/vm-${VM_NAME}.XML" |\
    xmlget '//VM' ID)
if [ -z "$VM_ID" ]; then
    die "Can't get VM ID for $VM_NAME."
fi
CURRENT_HOST="$(onevm show "$VM_ID" --xml | xmlget '//HISTORY[last()]' HOSTNAME)"
echo " VM $VM_ID is runnung on host '$CURRENT_HOST'."

###############################################################################
# non-persistent image
NP_IMAGE_NAME="NP-$VM_NAME"
NP_IMAGE_ID=$(oneimage list --xml|tee "${DATA_DIR}/image-list1.XML" |xmlget "//IMAGE[NAME=\"$NP_IMAGE_NAME\"]" ID||true)

if [ -n "$NP_IMAGE_ID" ]; then
	echo -n "* Image $NP_IMAGE_NAME exists with ID $NP_IMAGE_ID, removing..."
	oneimage delete "$NP_IMAGE_ID"
	waitforimg "$NP_IMAGE_NAME" "" || die "Image $NP_IMAGE_NAME delete timed out."
	echo " Done."
fi

echo -n "* Creating non-persistent image '$NP_IMAGE_NAME' ..."
oneimage create --name "$NP_IMAGE_NAME" --datastore "$IMAGE_DS_ID" --size 10000 --type datablock --driver raw --prefix sd >/dev/null

waitforimg "$NP_IMAGE_NAME" rdy || die "image creation failed"

NP_IMAGE_ID=$(oneimage list --xml|tee "${DATA_DIR}/image-list2.XML" |xmlget "//IMAGE[NAME=\"$NP_IMAGE_NAME\"]" ID||true)

echo " Done, Image ID $NP_IMAGE_ID."

echo -n "* Attaching image $NP_IMAGE_ID to VM $VM_ID..."
onevm disk-attach "$VM_ID" --image "$NP_IMAGE_ID"
waitforvm "$VM_NAME" runn || die "attach $NP_IMAGE_NAME timed out"
# check attach

NP_DISK_ID=$(onevm show "$VM_ID" --xml |tee "${DATA_DIR}/disk-${NP_IMAGE_NAME}.XML" |\
    xmlget "//DISK[IMAGE=\"$NP_IMAGE_NAME\"]" DISK_ID)
if [[ -z "$NP_DISK_ID" ]]; then
	die "Attach ($NP_IMAGE_ID) $NP_IMAGE_NAME failed."
fi
echo " Done, Disk ID $NP_DISK_ID."

[ "$CURRENT_HOST" = "$HOST1" ] && HOST_TO_MOVE=$HOST2 || HOST_TO_MOVE=$HOST1

FIRST_HOST="$CURRENT_HOST"
SECOND_HOST="$HOST_TO_MOVE"

echo -n "* Migrate live '$HOST_TO_MOVE'..."
onevm migrate --live "$VM_ID" "$HOST_TO_MOVE"
waitforvm "$VM_NAME" runn || die "migration failed"
NEW_HOST=$(onevm show --xml "$VM_ID" | xmlget '//HISTORY[last()]' HOSTNAME)
if ! [ "$NEW_HOST" = "$HOST_TO_MOVE" ]; then
    die "migration failed to $HOST_TO_MOVE, BM is on '$NEW_HOST'"
fi
echo " Done."

HOST_TO_MOVE=$CURRENT_HOST

echo -n "* Migrate live to $HOST_TO_MOVE ..."
onevm migrate --live "$VM_ID" "$HOST_TO_MOVE"
waitforvm "$VM_NAME" runn || die "Migration failed"
NEW_HOST=$(onevm show --xml "$VM_ID" | xmlget '//HISTORY[last()]' HOSTNAME)
if ! [ "$NEW_HOST" = "$HOST_TO_MOVE" ]; then
	die "Did not move to '$HOST_TO_MOVE', is on '$NEW_HOST'."
fi
echo " Done."

echo -n "* Powering off ..."
onevm poweroff --hard "$VM_ID"
waitforvm "$VM_NAME" poff || die "Power off failed."
echo " Done."

echo -n "* Moving to '$SECOND_HOST' ..."
onevm migrate "$VM_ID" "$SECOND_HOST"
waitforvm "$VM_NAME" poff || die "migration broke"
NEW_HOST=$(onevm show --xml "$VM_ID" | xmlget '//HISTORY[last()]' HOSTNAME)
if ! [ "$NEW_HOST" = "$SECOND_HOST" ]; then
	die "Did not move to '$SECOND_HOST', VM is on '$NEW_HOST'"
fi
echo " Done."

echo -n "* Powering up..."
onevm resume "$VM_ID"
waitforvm "$VM_NAME" runn || die "Resume failed."
echo "-- Done."

echo -n "* Powering off (hard)..."
onevm poweroff --hard "$VM_ID"
waitforvm "$VM_NAME" poff || die "Power off failed."
echo " Done."

echo -n "* Moving back to '$FIRST_HOST'..."
onevm migrate "$VM_ID" "$FIRST_HOST"
waitforvm "$VM_NAME" poff || die "Migration failed"
CURRENT_HOST=$(onevm show --xml "$VM_ID" | xmlget '//HISTORY[last()]' HOSTNAME)
if [ "$CURRENT_HOST" != "$FIRST_HOST" ]; then
	die "did not move to '$FIRST_HOST', is on '$CURRENT_HOST'"
fi
echo " Done."

echo -n "* Powering up ($VM_ID) '$VM_NAME' ..."
onevm resume "$VM_ID"
waitforvm "$VM_NAME" runn || die "cannot power up"
echo " Done."

echo -n "* Detaching disk '$NP_DISK_ID' from VM '$VM_ID'..."
onevm disk-detach "$VM_ID" "$NP_DISK_ID"
# check detach
waitforvm "$VM_NAME" runn || die "Disk detach timed out"

NP_DISK_ID=$(onevm show "$VM_ID" --xml | xmlget "//DISK[IMAGE=\"$NP_IMAGE_NAME\"]" DISK_ID || true)
if [ -n "$NP_DISK_ID" ]; then
	die "Detachment failed"
else
    echo " Done."
fi

echo -n "* Removing image $NP_IMAGE_ID ($NP_IMAGE_NAME)..."
oneimage delete "$NP_IMAGE_NAME"
waitforimg "$NP_IMAGE_NAME" ""  || die "Image delete failed."
echo " Done."

echo -n "* Terminating (hard) VM $VM_NAME..."
onevm terminate --hard "$VM_NAME"
waitforvm  "$VM_NAME" ""
echo " Done."

if [ "$deltemplate" = "y" ]; then
    echo -n "* Deleting VM Template '$VM_TEMPLATE_NAME'..." 
	onetemplate delete "$VM_TEMPLATE_NAME" --recursive
    echo " Done."
fi

echo "Validation passed."

