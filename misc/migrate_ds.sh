#!/bin/bash
#
# -------------------------------------------------------------------------- #
# Copyright 2015-2026, StorPool (storpool.com)                               #
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
#

TMPDIR=$(mktemp -d)
trap "rm -rf ${TMPDIR}" EXIT QUIT KILL HUP

function splog()
{
    echo "$*" >&2
}

function xpathGet()
{
    local xpath=$1 xmlFile=$2
    xmlstarlet sel -t -m "/" -v "${xpath}" -n "$xmlFile"
}

VM_ID=$1
DST_DS_ID=${2:-${DEFAULT_DST_DS_ID:-101}}

DST_DS_XML="${TMPDIR}/ds-${DST_DS_ID}.xml"
VM_XML="${TMPDIR}/vm-${VM_ID}.xml"

if [[ -z ${VM_ID} ]]; then
    echo "$0 VM_ID [DS_ID]" >&2
    exit 1
fi

onedatastore show -x "${DST_DS_ID}" > "$DST_DS_XML"

splog DS_ID=$DST_DS_ID
DST_DS_NAME=$(xpathGet "DATASTORE/NAME" "$DST_DS_XML")
DST_DS_ID=$(xpathGet "DATASTORE/ID" "$DST_DS_XML")

splog "DESTINATION DATASTORE $DST_DS_NAME $DST_DS_ID"

onevm show -x "$VM_ID" > "${VM_XML}"

declare -a did_a image_id_a image_name_a datastore_name_a datastore_id image_source_a
while read -ru 4 did; do
	image=$(xpathGet "VM/TEMPLATE/DISK[DISK_ID=$did]/IMAGE" "${VM_XML}")
	image_id=$(xpathGet "VM/TEMPLATE/DISK[DISK_ID=$did]/IMAGE_ID" "${VM_XML}")
	image_source=$(xpathGet "VM/TEMPLATE/DISK[DISK_ID=$did]/SOURCE" "${VM_XML}")
	datastore=$(xpathGet "VM/TEMPLATE/DISK[DISK_ID=$did]/DATASTORE" "${VM_XML}")
	datastore_id=$(xpathGet "VM/TEMPLATE/DISK[DISK_ID=$did]/DATASTORE_ID" "${VM_XML}")
	did_a+=($did)
	image_name_a+=("$image")
	image_id_a+=($image_id)
	image_source_a+=("$image_source")
	datastore_name_a+=("$datastore")
	datastore_id_a+=($datastore_id)

done 4< <(xpathGet "VM/TEMPLATE/DISK/DISK_ID" "${VM_XML}")

splog "DISK_ID ${!did_a[*]}=${did_a[*]}"
splog "IMAGE_ID ${!image_id_a[*]}=${image_id_a[*]}"
splog "IMAGE_NAME ${!image_name_a[*]}=${image_name_a[*]}"
splog "IMAGE_SOURCE ${!image_source_a[*]}=${image_source_a[*]}"
splog "DATASTORE_ID ${!datastore_id_a[*]}=${datastore_id_a[*]}"
splog "DATASTORE_NAME ${!datastore_name_a[*]}=${datastore_name_a[*]}"

for idx in ${!did_a[*]}; do
	did="${did_a[$idx]}"
	i_id="${image_id_a[$idx]}"
	i_name="${image_name_a[$idx]}"
	i_source="${image_source_a[$idx]}"
	d_name="${datastore_name_a[idx]}"
	d_id="${datastore_id_a[idx]}"
	IFS='/' read -ra source_a <<<"$i_source"
	NEW_SOURCE="${source_a[0]%-*}"
	NEW_SOURCE+="-${DST_DS_ID}/${source_a[1]}"

	splog "DISK_ID:'$did' I_NAME='$i_name' I_ID='$i_id' I_SOURCE='$i_source' D_NAME='$d_name' D_ID='$d_id' ${source_a[*]}"
	splog "# Delete image $i_id from Image datastore $d_id ($d_name)..."
	echo "onedb change-body datastore --id=$d_id \"//IMAGES/ID[text()=$i_id]\" --delete"
	splog "# Add image $i_id to Image datastore $DST_DS_ID ($DST_DS_NAME)"
	echo "onedb change-body datastore --id=$DST_DS_ID \"//IMAGES/ID\" \"$i_id\" --append"
        splog "update image $i_id DATASATORE_ID to $DST_DS_ID"        
	echo "onedb change-body image --id=$i_id \"/IMAGE/DATASTORE_ID\" \"$DST_DS_ID\""
        splog "update image $i_id DATASATORE to '$DST_DS_NAME'"        
	echo "onedb change-body image --id=$i_id \"/IMAGE/DATASTORE\" \"$DST_DS_NAME\""
	splog "update image $i_id SOURCE '${i_source}' to '$NEW_SOURCE'"
	echo "onedb change-body image --id=$i_id \"/IMAGE/SOURCE\" \"$NEW_SOURCE\"" 
        splog "update vm $VM_ID disk $did DATASTORE to '$DST_DS_NAME'"
	echo "onedb change-body vm --id=$VM_ID \"//TEMPLATE/DISK[DISK_ID=$did]/DATASTORE\" \"$DST_DS_NAME\""
        splog "update vm $VM_ID disk $did DATASTORE_ID to $DST_DS_ID"
	echo "onedb change-body vm --id=$VM_ID \"//TEMPLATE/DISK[DISK_ID=$did]/DATASTORE_ID\" \"$DST_DS_ID\""
	splog "update vm $VM_ID disk $did SOURCE to '$NEW_SOURCE'"
	echo "onedb change-body vm --id=$VM_ID \"//TEMPLATE/DISK[DISK_ID=$did]/SOURCE\" \"$NEW_SOURCE\""
        splog "# # # # # # # #"
done
