#!/bin/bash

# -------------------------------------------------------------------------- #
# Copyright 2015-2026, Storpool (storpool.com)                               #
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

# shellcheck source=SCRIPTDIR/../install.sh

# OpenNebula 7.5 syncs the remotes to the fixed /var/lib/one-remotes on the
# hypervisors and oned.conf has no SCRIPTS_REMOTE_DIR any more (OpenNebula/one#7899).
# The addon scripts take the directory from SCRIPTS_REMOTE_DIR in addon-storpoolrc.
ONE_REMOTES_DIR_7_5="/var/lib/one-remotes"
export SCRIPTS_REMOTE_DIR="${ONE_REMOTES_DIR_7_5}"

# shellcheck source=scripts/install-6.4.sh
source "${CWD:-.}/scripts/install-7.4.sh"

RC_FILE="${ONE_VAR:-/var/lib/one}/remotes/addon-storpoolrc"
RC_REMOTES_DIR="$(grep -E '^SCRIPTS_REMOTE_DIR=' "${RC_FILE}" | tail -n 1)"
RC_REMOTES_DIR="${RC_REMOTES_DIR#SCRIPTS_REMOTE_DIR=}"
RC_REMOTES_DIR="${RC_REMOTES_DIR//[\"\']/}"
if [[ -z "${RC_REMOTES_DIR}" ]]; then
    echo "*** Setting SCRIPTS_REMOTE_DIR=${ONE_REMOTES_DIR_7_5} in ${RC_FILE}"
    cat >>"${RC_FILE}" <<_EOF_

# OpenNebula 7.5: the remotes directory on the hypervisors (scripts/install-7.5.sh)
SCRIPTS_REMOTE_DIR=${ONE_REMOTES_DIR_7_5}
_EOF_
elif [[ "${RC_REMOTES_DIR}" == "${ONE_REMOTES_DIR_7_5}" ]]; then
    echo "*** SCRIPTS_REMOTE_DIR=${RC_REMOTES_DIR} already set in ${RC_FILE}"
else
    echo "*** WARNING: SCRIPTS_REMOTE_DIR=${RC_REMOTES_DIR} in ${RC_FILE} is not the OpenNebula 7.5 remotes directory, replacing it with ${ONE_REMOTES_DIR_7_5}"
    sed -i -e "s|^SCRIPTS_REMOTE_DIR=.*|SCRIPTS_REMOTE_DIR=${ONE_REMOTES_DIR_7_5}|" "${RC_FILE}"
fi
