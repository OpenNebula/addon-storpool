#!/bin/bash

# -------------------------------------------------------------------------- #
# Copyright 2015-2018, StorPool (storpool.com)                               #
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

#-------------------------------------------------------------------------------
# This file should be sourced in im/*-probes.d/monitor_ds.sh before 'echo "DS = ["'
# Example:
#     source ../../datastore/storpool/monitor_ds.sh
#     echo "DS = ["
#     echo "  ID = $ds,"
#-------------------------------------------------------------------------------

function splog() { logger -t "im_sp_monitor_ds[$$]" "$*"; }

SP_MONITOR_DS="../../datastore/storpool/monitor"
ONE_VERSION="$(<../../VERSION)"

SP_JSON_PATH="/tmp"
SP_VOLUME_SPACE_JSON="storpool_volume_usedSpace.json"
SP_CMD_VOLUME_SPACE="cat _SP_JSON_PATH_/_SP_VOLUME_SPACE_JSON_"
SP_SNAPSHOT_SPACE_JSON="storpool_snapshot_space.json"
SP_CMD_SNAPSHOT_SPACE="cat _SP_JSON_PATH_/_SP_SNAPSHOT_SPACE_JSON_"


if [ -f "../../addon-storpoolrc" ]; then
    source "../../addon-storpoolrc"
fi
if [ -f "/etc/storpool/addon-storpool.conf" ]; then
    source "/etc/storpool/addon-storpool.conf"
fi

function boolTrue()
{
   case "${1^^}" in
       1|Y|YES|TRUE|ON)
           return 0
           ;;
       *)
           return 1
   esac
}


if [ -f "$SP_MONITOR_DS" ]; then
#    if [ "$IM_MONITOR_DS_DEBUG" = "1" ]; then
#        splog "[DBG]$PWD $0 $* (ds:$ds)"
#    fi
    if [ -d "$SP_DS_TMP" ]; then
        if boolTrue "$IM_MONITOR_DS_DEBUG_VERBOSE"; then
            splog "found SP_DS_TMP:$SP_DS_TMP"
        fi
    else
        SP_DS_TMP="$(mktemp -d -t sp-tmp-XXXXXXXX)"
        _ret=$?
        export SP_DS_TMP
        if boolTrue "$IM_MONITOR_DS_DEBUG"; then
            START_TIME="$(date +%s)"
            export START_TIME
            splog "mktemp $SP_DS_TMP returned $_ret, START_TIME=$START_TIME"
        fi
        function sp_trap()
        {
            local _ret=$?
            if [ $_ret -ne 0 ]; then
                splog "(${_ret}) $0 $*"
            fi
            if [ -d "$SP_DS_TMP" ]; then
                rm -rf "$SP_DS_TMP"
            fi
            if [ -n "$START_TIME" ]; then
                local end_time="$(date +%s)"
                splog "'$0' runtime:$((end_time - START_TIME))sec"
            fi
            exit $_ret
        }
        trap sp_trap TERM INT QUIT HUP

        if [ $_ret -eq 0 ]; then
            if boolTrue "$IM_MONITOR_DS_DEBUG"; then
                splog "generating disk space data cache $SP_DS_TMP/sizes"
            fi
            SP_CMD_VOLUME_SPACE="${SP_CMD_VOLUME_SPACE//_SP_VOLUME_SPACE_JSON_/$SP_VOLUME_SPACE_JSON}"
            SP_CMD_VOLUME_SPACE="${SP_CMD_VOLUME_SPACE//_SP_JSON_PATH_/$SP_JSON_PATH}"
            SP_CMD_VOLUME_SPACE="${SP_CMD_VOLUME_SPACE//_CLUSTER_ID_/$CLUSTER_ID}"
            #splog "eval $SP_CMD_VOLUME_SPACE"
            eval $SP_CMD_VOLUME_SPACE 2>"$SP_DS_TMP/ERROR-volume-eval" |\
              jq -r ".data[]|[.name,.storedSize,.spaceUsed]|@csv" 2>"$SP_DS_TMP/ERROR-volume" |\
                sort >"$SP_DS_TMP/sizes"
            SP_CMD_SNAPSHOT_SPACE="${SP_CMD_SNAPSHOT_SPACE//_SP_SNAPSHOT_SPACE_JSON_/$SP_SNAPSHOT_SPACE_JSON}"
            SP_CMD_SNAPSHOT_SPACE="${SP_CMD_SNAPSHOT_SPACE//_SP_JSON_PATH_/$SP_JSON_PATH}"
            SP_CMD_SNAPSHOT_SPACE="${SP_CMD_SNAPSHOT_SPACE//_CLUSTER_ID_/$CLUSTER_ID}"
            #splog "eval $SP_CMD_SNAPSHOT_SPACE"
            eval $SP_CMD_SNAPSHOT_SPACE 2>"$SP_DS_TMP/ERROR-snapshot-eval" |\
              jq -r ".data[]|[.name,.storedSize,.spaceUsed]|@csv" 2>"$SP_DS_TMP/ERROR-snapshot" |\
                sort >>"$SP_DS_TMP/sizes"
        fi
    fi

    SP_DS_SIZES="$(bash $SP_MONITOR_DS system $ds 2>/dev/null)"

    if [ -n "$SP_DS_SIZES" ]; then
        if boolTrue "$IM_MONITOR_DS_DEBUG"; then
            splog "SP_DS_SIZES=$SP_DS_SIZES"
        fi

        SP_SIZES=($SP_DS_SIZES)
        SP_USED_MB=${SP_SIZES["0"]:-0}
        SP_TOTAL_MB=${SP_SIZES["1"]:-0}
        SP_FREE_MB=${SP_SIZES["2"]:-0}

        if [ $SP_USED_MB -gt 0 ] && [ $SP_FREE_MB -gt 0 ]; then

            if boolTrue "$IM_MONITOR_DS_DEBUG"; then
                if boolTrue "$IM_MONITOR_DS_DEBUG_VERBOSE"; then
                    splog "DS_ID $ds (StorPool) SPUSED=$SP_USED_MB SPTOTAL=$SP_TOTAL_MB SPFREE=$SP_FREE_MB USED=$USED_MB TOTAL=$TOTAL_MB FREE=$FREE_MB $dir"
                else
                    splog "DS ID=$ds USED_MB=$SP_USED_MB TOTAL_MB=$SP_TOTAL_MB FREE_MB=$SP_FREE_MB"
                fi
            fi

            echo "DS = ["
            echo "  ID = $ds,"
            echo "  USED_MB = $SP_USED_MB,"
            echo "  TOTAL_MB = $SP_TOTAL_MB,"
            echo "  FREE_MB = $SP_FREE_MB"
            echo "]"

            if [ "${ONE_VERSION:0:1}" = "4" ]; then
                # hijacking the loop in im/monitor_ds.sh
                continue
            fi

            # Report VM DISKS if marked for remote monitoring
            if [ -e "${dir}/.monitor" ]; then
                DRIVER=$(<"${dir}/.monitor")
                # default tm DRIVER is ssh
                SCRIPT_PATH="${REMOTES_DIR}/tm/${DRIVER:-ssh}/monitor_ds"
                if [ -e "$SCRIPT_PATH" ]; then
                    if boolTrue "$IM_MONITOR_DS_DEBUG"; then
                        splog "run $SCRIPT_PATH $dir (set DEBUG_TM_MONITOR_DS=1)"
                        export DEBUG_TM_MONITOR_DS=1
                    fi
                    "$SCRIPT_PATH" "$dir"
                else
                    splog "$SCRIPT_PATH Not found!"
                fi
            else
                if boolTrue "$IM_MONITOR_DS_DEBUG_VERBOSE"; then
                    splog "${dir}/.monitor not found. Shared filesystem?"
                fi
            fi
            # hijacking the loop in im/monitor_ds.sh
            continue
        fi
    else
        if boolTrue "$IM_MONITOR_DS_DEBUG_VERBOSE"; then
            splog "Datastore $ds is not on StorPool"
        fi
    fi
else
    splog "$SP_MONITOR_DS not found"
fi
