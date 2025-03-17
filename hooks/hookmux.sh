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

###############################################################################
# Usage
#
# cp hookmux.sh /var/lib/one/remotes/hooks/
#
# cd /var/lib/one/remotes/hooks
#
# ln -s hookmux.sh active-hotplug_nic
#
# mkdir /var/lib/one/remotes/hooks/active-hotplug_nic.d
#
# cp calledlocally /var/lib/one/remotes/hooks/active-hotplug_nic.d/calledlocally
#
## The script that should be called remotely should have name anding '*.remote'
# cp calledremote /var/lib/one/remotes/hooks/active-hotplug_nic.d/calledremote.remote
#
# su - oneadmin -c 'onehost sync --force --rsync'
#
## Define a hook in the hook manager that is executed locally and have the VM template passed to stdin
#...
#COMMAND="active-hotplug_nic"
#ARGUMENTS="$TEMPLATE"
#ARGUMENTS_STDIN="YES"
#REMOTE="NO"
#...
###############################################################################

#set -e -o pipefail

me="$(basename "$0")"
hookdir="$(dirname "$0")/${me}.d"

haveStdin=

if [[ ! -t 0 ]]; then
  stdin="$(cat)"
  haveStdin=1
fi

if [[ -d "${hookdir}" ]]; then
  while read -r -u 4 hook; do
    if [[ "${hook%.remote}" == "${hook}" ]]; then
      echo "Running ${hook} $* ${haveStdin:+(with stdin)}" >&2
      if [[ -n "${haveStdin}" ]]; then
        echo "${stdin}" | "${hook}" "$@"
      else
        "${hook}" "$@"
      fi
    else
      if [[ -n "${haveStdin}" ]]; then
        hookRemote="${hook/\/var\/lib\/one\/remotes//var/tmp/one}"
        if [[ -z "${REMOTEHOST}" ]]; then
          REMOTEHOST="$(echo "${stdin}" | base64 -i -d | xmllint -xpath '//HISTORY[last()]/HOSTNAME/text()' - || true)"
        fi
        echo "Running ${REMOTEHOST}:${hookRemote} $* (with stdin)" >&2
        echo "${stdin}" | "${SSH:-ssh}" "${REMOTEHOST}" "${hookRemote}" "$@"
      else
        echo "Error calling ${hook}: Remote hook require \$TEMPLATE on STDIN!" >&2
      fi
    fi
  done 4< <(find "${hookdir}" -maxdepth 1 -executable -type f -o -type l || true)
else
  echo "Error: Missing ${hookdir}" >&2
  exit 1
fi
