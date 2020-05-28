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
#

# To install just drop the file in '/var/lib/one/remotes/im/kvm-probes.d/'
# and re-sync the hosts with 'su - oneadmin -c "onehost sync --force"'
#
# The script will inject per interface network stats in the oned.log
# The oned log could be regularly parsed and nics stats pushed to an external db
# for further processing

PATH=/bin:/sbin/:/usr/bin:/usr/sbin:$PATH

if [ -f "../../addon-storpoolrc" ]; then
    source "../../addon-storpoolrc"
fi

function boolTrue()
{
   case "${!1^^}" in
       1|Y|YES|TRUE|ON)
           return 0
           ;;
       *)
           return 1
   esac
}

function splog()
{
   logger -t "${nic_sp_0##*/}" -- "$*"
}

function report()
{
    if boolTrue "LEGACY_MONITORING"; then
        echo "VM=[ID=${1},POLL=\"$2\"]"
        if boolTrue "DEBUG_NIC_STATS"; then
            splog "VM=[ID=${1},POLL=\"$2\"]"
        fi
    else
        echo "VM=[ID=${1},MONITOR=\"$(echo "$2"|tr ' ' '\n'|base64 -w 0)\"]"
        if boolTrue "DEBUG_NIC_STATS"; then
            splog "VM=[ID=${1},MONITOR=\"$(echo "$2"|tr ' ' '\n'|base64 -w 0)\"]"
        fi
    fi
}


#27: one-135-0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast master onebr.616 state UNKNOWN mode DEFAULT group default qlen 1000\    link/ether fe:00:70:30:4a:06 brd ff:ff:ff:ff:ff:ff\    RX: bytes  packets  errors  dropped overrun mcast   \    179604395  177435   0       0       0       0       \    TX: bytes  packets  errors  dropped carrier collsns \    135264059  1235572  0       0       0       0       
poll=
while read -u 4 l; do
	a=($l)
	nic="${a[1]%:}"
	nica=(${nic//-/ })
	vid="${nica[1]}"
	nid="${nica[2]}"
	if [ "$vid" != "$vidold" ]; then
		if [ -n "$poll" ]; then
            report "$vidold" "$poll"
		fi
		poll=
	fi
	vidold="$vid"
	[ -n "$poll" ] && poll+=" "
	poll+="NIC_STATS=[ID=${nid},RX=${a[41]},TX=${a[28]}]"
done 4< <(ip -o -s link | grep one- | sort -k 2)

if [ -n "$poll" ]; then
    report "$vidold" "$poll"
fi
