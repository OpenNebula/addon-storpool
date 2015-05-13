#!/bin/bash

# -------------------------------------------------------------------------- #
# Copyright 2015, StorPool (storpool.com)                                    #
#                                                                            #
# Portions copyright OpenNebula Project (OpenNebula.org), CG12 Labs          #
#
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

SP_MONITOR_DS="../../datastore/storpool/monitor_ds"

if [ -f "$SP_MONITOR_DS" ]; then

    SP_DS_SIZES="$(python $SP_MONITOR_DS $ds)"

    if [ -n "$SP_DS_SIZES" ]; then

        SP_SIZES=($SP_DS_SIZES)

        SP_USED=${SP_SIZES["0"]}
        SP_TOTAL=${SP_SIZES["1"]}
        SP_FREE=${SP_SIZES["2"]}

        SP_USED=${SP_USED:-0}
        SP_TOTAL=${SP_TOTAL:-0}
        SP_FREE=${SP_FREE:-0}
#        splog "DS_ID $ds is on StorPool, SPUSED=$SP_USED SPTOTAL=$SP_TOTAL SPFREE=$SP_FREE USED=$USED_MB TOTAL=$TOTAL_MB FREE=$FREE_MB"

        echo "DS = ["
        echo "  ID = $ds,"
        echo "  USED_MB = $USED_MB,"
        echo "  TOTAL_MB = $TOTAL_MB,"
        echo "  FREE_MB = $FREE_MB,"

        echo "  VOLATILE_USED_MB = $SP_USED,"
        echo "  VOLATILE_TOTAL_MB = $SP_TOTAL,"
        echo "  VOLATILE_FREE_MB = $SP_FREE"

        echo "]"

        continue
#    else
#        splog "DS_ID $ds is not on StorPool"
    fi
#else
#    splog "$SP_MONITOR_DS not found"
fi
