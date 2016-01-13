#!/bin/bash

# -------------------------------------------------------------------------- #
# Copyright 2015-2016, StorPool (storpool.com)                               #
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

function splog() { logger -t "ds_sp_monitor_ds" "$*"; }

SP_MONITOR_DS="../../datastore/storpool/monitor"

if [ -f "$SP_MONITOR_DS" ]; then

    SP_DS_SIZES="$(bash $SP_MONITOR_DS system $ds)"

    if [ -n "$SP_DS_SIZES" ]; then

        SP_SIZES=($SP_DS_SIZES)

        SP_USED_MB=${SP_SIZES["0"]:-0}
        SP_TOTAL_MB=${SP_SIZES["1"]:-0}
        SP_FREE_MB=${SP_SIZES["2"]:-0}

        CALC_USED_MB=$((USED_MB + SP_USED_MB))
        if [ $SP_FREE_MB -lt $FREE_MB ]; then
            CALC_FREE_MB=$SP_FREE_MB
        else
            CALC_FREE_MB=$FREE_MB
        fi
        CALC_TOTAL_MB=$((CALC_USED_MB + CALC_FREE_MB))
#        splog "DS_ID $ds is on StorPool, SPUSED=$SP_USED_MB SPTOTAL=$SP_TOTAL_MB SPFREE=$SP_FREE_MB USED=$USED_MB TOTAL=$TOTAL_MB FREE=$FREE_MB"

        echo "DS = ["
        echo "  ID = $ds,"
        echo "  USED_MB = $CALC_USED_MB,"
        echo "  TOTAL_MB = $CALC_TOTAL_MB,"
        echo "  FREE_MB = $CALC_FREE_MB,"
        # look like this is not used...
        echo "  VOLATILE_USED_MB = $SP_USED_MB,"
        echo "  VOLATILE_TOTAL_MB = $SP_TOTAL_MB,"
        echo "  VOLATILE_FREE_MB = $SP_FREE_MB"
        echo "]"

        continue
#    else
#        splog "DS_ID $ds is not on StorPool"
    fi
else
    splog "$SP_MONITOR_DS not found"
fi
