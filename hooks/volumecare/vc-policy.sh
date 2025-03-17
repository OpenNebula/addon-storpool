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

ONE_HOME="${ONE_HOME:-/var/lib/one}"

XML="$(base64 -d - 2>/dev/null)"

VMID=$(echo "${XML}" | xmllint -xpath '/CALL_INFO/PARAMETERS/PARAMETER[TYPE="IN" and POSITION=2]/VALUE/text()' - || true)

if [[ -z "${VMID}" ]]; then
    logger -t vc_sp_vc-policy.sh -- "Error! Can't get VM id!"
    exit 1
fi

logger -t vc_sp_vc-policy.sh -- "${ONE_HOME}/remotes/hooks/volumecare/volumecare ${VMID}"

"${ONE_HOME}/remotes/hooks/volumecare/volumecare" "${VMID}"
