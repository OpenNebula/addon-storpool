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

DELETE_T_CPU_SHARES=1

source /var/lib/one/remotes/etc/vmm/kvm/kvmrc

me="${0##*/}"

function splog() { logger -t "hook_sp_$me[$$]" -- "$*"; }

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

function validate()
{
    local val="${!1}"
    if [ -z "$val" ]; then
        if boolTrue "DEBUG_resizeCpuMem"; then
            splog "validate $1='$val' Error: empty"
        fi
        return 1
    elif [ -n "${val//[0-9]/}" ]; then
        splog "validate $1='$val' Error: not number"
        return 1
    fi
    if boolTrue "DDEBUG_resizeCpuMem"; then
        splog "validate $1='$val' OK: number"
    fi
    return 0
}

if boolTrue "DDDEBUG_resizeCpuMem"; then
    splog "PWD=$PWD $0 $*"
fi

API="$(base64 -d - 2>/dev/null)"

VM_ID="$(echo "$API"|xmlstarlet sel -t -m '//PARAMETER[POSITION=2][TYPE="IN"]' -v "VALUE")"

if validate "VM_ID"; then
    VMXML="$(onevm show -x "$VM_ID")"
    if [ -n "$VMXML" ]; then
        DOMAIN="one-$VM_ID"
    fi
else
    splog "Error: VM_ID is empty"
    exit 1
fi

state="$(echo "$VMXML"|xmlstarlet sel -t -m "/VM" -v "STATE")"
if validate "state"; then
    if [ $state -ne "3" ]; then
        lcm_state="$(echo "$VMXML"|xmlstarlet sel -t -m "/VM" -v "LCM_STATE")"
        splog "VM $VM_ID STATE/LCM_STATE:$state/$lcm_state (Exit 0)"
        exit 0
    fi
fi

kvmhost="$(echo "$VMXML"|xmlstarlet sel -t -m "//HISTORY_RECORDS/HISTORY[last()]" -v "HOSTNAME")"

vcpu="$(echo "$VMXML"|xmlstarlet sel -t -m "//TEMPLATE" -v "VCPU")"
if ! validate "vcpu"; then
    vcpu="${vcpu:-1}"
fi

declare -A t_var
for e in T_VCPU_MAX T_VCPU_NEW T_CPU_SHARES T_MEMORY_MAX T_MEMORY_NEW; do
    t_var[$e]="$(echo "$VMXML"|xmlstarlet sel -t -m '//USER_TEMPLATE' -v "$e")"
    if boolTrue "DDEBUG_resizeCpuMem"; then
        splog "VM=$VM_ID VCPU=$vcpu $e=${t_var[$e]} @$kvmhost"
    fi
done
VCPU_MAX=${t_var[T_VCPU_MAX]}
VCPU_NEW=${t_var[T_VCPU_NEW]}
CPU_SHARES="${t_var[T_CPU_SHARES]}"
MEMORY_MAX=${t_var[T_MEMORY_MAX]}
MEMORY_NEW=${t_var[T_MEMORY_NEW]}

if validate "VCPU_MAX"; then
    if validate "VCPU_NEW"; then
        if [ $vcpu -ne $VCPU_NEW ]; then
            if [ $VCPU_NEW -le $VCPU_MAX ]; then
                if [ $VCPU_NEW -ge 1 ]; then
                    cmd="virsh --connect $LIBVIRT_URI setvcpus $DOMAIN $VCPU_NEW --live"
                    ssh -t "$kvmhost" "$cmd"
                    ret=$?
                    splog "($ret) $kvmhost $cmd"
                    if [ $ret -eq 0 ]; then
                        onedb change-body vm --id $VM_ID "/VM/TEMPLATE/VCPU" $VCPU_NEW
                        ret=$?
                        splog "($ret) onedb change-body vm --id $VM_ID /VM/TEMPLATE/VCPU $VCPU_NEW"
                        onedb change-body vm --id $VM_ID "/VM/USER_TEMPLATE/T_VCPU_NEW" --delete
                        ret=$?
                        splog "($ret) onedb change-body vm --id $VM_ID /VM/USER_TEMPLATE/T_VCPU_NEW --delete"
                        if [ -n "CPU_SHARES" ]; then
                            shares=$(awk "BEGIN {printf(\"%.f\", (1024*$CPU_SHARES)+0.5)}")
                            cmd="virsh --connect $LIBVIRT_URI schedinfo $DOMAIN --live cpu_shares=$shares"
                            ssh -t "$kvmhost" "$cmd"
                            ret=$?
                            splog "($ret) $kvmhost $cmd #CPU_SHARES=$CPU_SHARES"
                            if [ $ret -eq 0 ]; then
                                onedb change-body vm --id $VM_ID "/VM/TEMPLATE/CPU" "$CPU_SHARES"
                                ret=$?
                                splog "($ret) onedb change-body vm --id $VM_ID /VM/TEMPLATE/CPU $CPU_SHARES"
                                if [ $ret -eq 0 ]; then
                                    if boolTrue "DELETE_T_CPU_SHARES"; then
                                        onedb change-body vm --id $VM_ID "/VM/USER_TEMPLATE/T_CPU_SHARES" --delete
                                        ret=$?
                                        splog "($ret) onedb change-body vm --id $VM_ID /VM/USER_TEMPLATE/T_CPU_SHARES --delete"
                                    fi
                                fi
                            fi
                        fi
                    fi
                else
                    splog "VCPU current $VCPU_NEW < 1"
                fi
            else
                splog "VCPU current > max $VCPU_NEW > $VCPU_MAX"
            fi
        else
            if boolTrue "DEBUG_resizeCpuMem"; then
                splog "VM $VM_ID VCPU $vcpu = $VCPU_NEW"
            fi
        fi
    fi
fi

memory="$(echo "$VMXML"|xmlstarlet sel -t -m "//TEMPLATE" -v "MEMORY")"
if ! validate "memory"; then
    exit 1
fi

if validate "MEMORY_MAX"; then
    if validate "MEMORY_NEW"; then
        if [ $memory -ne $MEMORY_NEW ]; then
            if [ $MEMORY_NEW -le $MEMORY_MAX ]; then
                cmd="virsh --connect $LIBVIRT_URI setmem $DOMAIN $((MEMORY_NEW*1024)) --live"
                ssh -t "$kvmhost" "$cmd"
                ret=$?
                splog "($ret) $kvmhost $cmd"
                if [ $ret -eq 0 ]; then
                    onedb change-body vm --id $VM_ID "/VM/TEMPLATE/MEMORY" $MEMORY_NEW
                    ret=$?
                    splog "($ret) onedb change-body vm --id $VM_ID /VM/TEMPLATE/MEMORY $MEMORY_NEW"
                    if [ $ret -eq 0 ]; then
                        onedb change-body vm --id $VM_ID "/VM/USER_TEMPLATE/T_MEMORY_NEW" --delete
                        ret=$?
                        splog "($ret) onedb change-body vm --id $VM_ID /VM/USER_TEMPLATE/T_MEMORY_NEW --delete"
                    fi
                fi
            else
                splog "VM $VM_ID MEMORY $memory > $MEMORY_MAX"
            fi
        else
            splog "VM $VM_ID MEMORY $memory = $MEMORY_NEW"
        fi
    fi
fi
