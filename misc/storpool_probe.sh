#!/bin/bash
#
# -------------------------------------------------------------------------- #
# Copyright 2015-2021, StorPool (storpool.com)                               #
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
# Copy to
#  frontend:/var/lib/one/remotes/im/kvm-probes.d/
#
# Change ownership
#  chown -R oneadmin.oneadmin /var/lib/one/remotes
#  
# Sync the hosts
#  su - oneadmin -c 'onehost sync --force'
#


PATH=/bin:/sbin:/usr/bin:/usr/sbin:$PATH

if [ -f ../../etc/im/kvm-probes.d/reserved_resources.conf ]; then
    source ../../etc/im/kvm-probes.d/reserved_resources.conf
fi

eval "$(storpool_confshow -e SP_CLUSTER_ID SP_CLUSTER_NAME SP_OURID 2>/dev/null)"

echo "SP_CLUSTER_ID=\"$SP_CLUSTER_ID\""
echo "SP_CLUSTER_NAME=\"$SP_CLUSTER_NAME\""
echo "SP_OURID=\"$SP_OURID\""

cgroup="${cgroup:-machine.slice}"

function count_cpus()
{
        local _list="$1" _cpu=0 _c= _arr=()
        for _c in ${_list//,/ }; do
                _arr=(${_c//-/ })
                if [ ${#_arr[@]} -eq 2 ]; then
                        _cpu=$((_cpu + _arr[1] - _arr[0]))
                fi
                _cpu=$((_cpu + 1))
        done
        echo "$_cpu"
}

cpuset_cpus="$(cgget -v -n -r cpuset.cpus "$cgroup")"
ret=$?
if [ $ret = 0 ]; then
    echo "SP_LIBVIRT_CPUS=$(count_cpus "$cpuset_cpus")"
fi
