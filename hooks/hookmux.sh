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

#set -e -o pipefail

me="$(basename "$0")"
hookdir="$(dirname "$0")/${me}.d"

haveStdin=

if [ ! -t 0 ]; then
  stdin="$(cat)"
  haveStdin=1
fi

if [ -d "$hookdir" ]; then
  while read -u 4 hook; do
    if [ "${hook%.remote}" = "$hook" ]; then
      echo "Running $hook $* ${haveStdin:+(with stdin)}" >&2
      if [ -n "$haveStdin" ]; then
        echo "$stdin" | $hook "$@"
      else
        $hook "$@"
      fi
    else
      if [ -n "$haveStdin" ]; then
        hookRemote="${hook/\/var\/lib\/one\/remotes//var/tmp/one}"
        if [ -z "$REMOTEHOST" ]; then
          REMOTEHOST="$(echo "$stdin"|base64 -i -d|xmllint -xpath '//HISTORY[last()]/HOSTNAME/text()' -)"
        fi
        echo "Running $REMOTEHOST:$hookRemote $* (with stdin)" >&2
        echo "$stdin" | ssh "$REMOTEHOST" ${hookRemote} "$@"
      else
        echo "Error calling $hook: Remote hook require \$TEMPLATE on STDIN!" >&2
      fi
    fi
  done 4< <(find "$hookdir" -maxdepth 1 -executable -type f -o -type l)
else
  echo "Error: Missing $hookdir" >&2
  exit 1
fi
