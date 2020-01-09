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

PATH=/bin:/usr/bin:/sbin:/usr/sbin:$PATH

cgroup="${1:-machine.slice}"

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

mem=($(free -b | grep -i "mem:"))
cg_arr=($(cgget -v -n -r memory.limit_in_bytes -r cpuset.cpus "$cgroup"))
root_arr=($(cgget -v -n -r memory.limit_in_bytes -r cpuset.cpus ""))
cg_cpus=`count_cpus "${cg_arr[1]}"`
root_cpus=`count_cpus "${root_arr[1]}"`

echo "RESERVED_CPU=$(((root_cpus-cg_cpus)*100))"
echo "RESERVED_MEM=$(((mem[1]-cg_arr[0])/1024))"
storpool_confshow SP_OURID 2>/dev/null
