#!/bin/bash
#
# -------------------------------------------------------------------------- #
# Copyright 2015-2025, StorPool (storpool.com)                               #
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
# Usage: ./fix_namespace_symlinks.sh [domain_name]
#  When the <domain_name> is omitted, all OpenNebula started domains are processed
#

set -e -o pipefail

me="${0##*/}"

NOOP="${NOOP:-}"

VMNAME="$1"

tools=(nsenter xmlstarlet)

for tool in "${tools[@]}"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "Error: ${tool} is not installed" 1>&2
        exit 1
    fi
done

function do_symlink()
{
    local pid="$1" disk="$2"
    local target="" spdev=""
    [[ -n "${disk}" ]] || return 0
    target="$(readlink "${disk}" || true)"
    if [[ "${target}" =~ "storpool" ]]; then
        spdev="$(realpath "${target}")"
        if [[ -n "$spdev" ]]; then
            ${NOOP:+echo} nsenter -m -t "${pid}" ln -vsf "${spdev}" "${target}"
            logger -t "${me}" "PID ${pid} DISK ${disk} ln ${target} -> ${spdev} ($?)"
        else
            echo "[!] PID ${pid} disk ${disk} target ${target} can't get realpath!"
        fi
    else
        echo "[!] PID ${pid} Disk ${disk} with target ${target} not on storpool!"
    fi
}

if [[ ${EUID} -ne 0 ]]; then
   echo "Error: The script must be run as root" 1>&2
   exit 1
fi

if [[ -z "${VMNAME}" ]]; then
    COUNT=0
    while read -ru "${lvt}" lid lname lstate; do
        if [[ "${lname}" =~ "one-" ]]; then
            COUNT=$((COUNT+1))
            echo "[I][${COUNT}] processing ${lname} state: ${lstate}"
            if ! "$0" "${lname}"; then
                echo "[E][${COUNT}] failed ${lname} ($?)"
            fi
        fi
    done {lvt}< <(virsh list)
    exit 0
fi

PID="$(pgrep -f "guest=${VMNAME}," )"

if [[ -z "$PID" ]]; then
    echo "Guest with name ${VMNAME} not found!"
    exit 1
fi

${NOOP:+echo} nsenter -m -t "${PID}" mkdir -vp /dev/storpool-byid

DOMXML=$(mktemp "/var/run/${me}-XXXXXXX")
trap "rm -f ${DOMXML}" EXIT QUIT TERM

virsh dumpxml "${VMNAME}" >"${DOMXML}"

while read -r -u "${dfh}" diskpath; do
    do_symlink "${PID}" "$diskpath"
done {dfh}< <(xmlstarlet sel -t -m '//devices/disk/source' -v '@dev' -n "${DOMXML}" 2>/dev/null || true)

while read -r -u "${dfh}" diskpath; do
    do_symlink "${PID}" "$diskpath"
done {dfh}< <(xmlstarlet sel -t -m '//devices/disk/source' -v '@file' -n "${DOMXML}" 2>/dev/null || true)
