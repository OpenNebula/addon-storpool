#!/bin/bash
#
# -------------------------------------------------------------------------- #
# Copyright 2015-2024, StorPool (storpool.com)                               #
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

# To install just drop the file in '/var/lib/one/remotes/im/kvm-probes.d/'
# and re-sync the hosts with 'su - oneadmin -c "onehost sync --force"'
#
# The script will inject per interface network stats in the oned.log
# The oned log could be regularly parsed and nics stats pushed to an external db
# for further processing

PATH=/bin:/sbin/:/usr/bin:/usr/sbin:${PATH}

if [[ -f "../../addon-storpoolrc" ]]; then
    # shellcheck source=addon-storpoolrc
    source "../../addon-storpoolrc"
fi

function boolTrue()
{
   case "${!1^^}" in
       1|Y|YES|T|TRUE|ON)
           return 0
           ;;
       *)
           return 1
   esac
}

function splog()
{
   logger -t "nic_sp_${0##*/}" -- "[$$] $*"
}

function report()
{
    local _vmid="$1" _poll="$2"
    [[ -n "${_poll}" ]] || return 0
    if [[ -d "${0%/*}/../../kvm-probes.d" ]]; then
        echo "VM=[ID=${_vmid},MONITOR=\"$(echo "${_poll}" | tr ' ' '\n' | base64 -w 0 || true)\"]"
        if boolTrue "DEBUG_NICSTATS"; then
            splog "[D] VM=[ID=${_vmid},MONITOR=\"$(echo "${_poll}" | tr ' ' '\n' | base64 -w 0 || true)\"]"
        fi
    else
        echo "VM=[ID=${_vmid},POLL=\"${_poll}\"]"
        if boolTrue "DEBUG_NICSTATS"; then
            splog "[D] VM=[ID=${_vmid},POLL=\"${_poll}\"]"
        fi
    fi
}

#27: one-135-0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast master onebr.616 state UNKNOWN mode DEFAULT group default qlen 1000\    link/ether fe:00:70:30:4a:06 brd ff:ff:ff:ff:ff:ff\    RX: bytes  packets  errors  dropped overrun mcast   \    179604395  177435   0       0       0       0       \    TX: bytes  packets  errors  dropped carrier collsns \    135264059  1235572  0       0       0       0
poll=""
vmidOld=""
while read -r -u "${nicfh}" line; do
	IFS=' ' read -r -a array <<< "${line}"
	nic="${array[1]%:}"
	read -r -a nica <<< "${nic//-/ }"
	vmid="${nica[1]}"
	nicid="${nica[2]}"
	if [[ "${vmid}" != "${vmidOld}" ]]; then
        report "${vmidOld}" "${poll}"
		poll=""
	fi
	vmidOld="${vmid}"
    [[ -z "${poll}" ]] || poll+=" "
	poll+="NIC_STATS=[ID=${nicid:-0},RX=${array[41]:-0},TX=${array[28]:-0}]"
done {nicfh}< <(ip -o -s link | grep one- | sort -k 2 || true)
exec {nicfh}<&-

if [[ -n "${vmidOld}" ]] && [[ -n "${poll}" ]]; then
    report "${vmidOld}" "${poll}"
fi
