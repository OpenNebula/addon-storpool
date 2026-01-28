#!/bin/bash
#
# -------------------------------------------------------------------------- #
# Copyright 2015-2025, StorPool (storpool.com)                               #
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

PATH="/bin:/usr/bin:/sbin:/usr/sbin:${PATH}"

cgroup="${1:-machine.slice}"
cgpath="/sys/fs/cgroup"

if [[ -f /var/tmp/one/addon-storpoolrc ]]; then
    # shellcheck source=addon-storpoolrc
    source /var/tmp/one/addon-storpoolrc
fi

function count_cpus()
{
	local _list="$1" _cpu=0 _c="" _arr=()
	for _c in ${_list//,/ }; do
		read -r -a _arr <<< "${_c//-/ }"
		if [[ ${#_arr[@]} -eq 2 ]]; then
			_cpu=$((_cpu + _arr[1] - _arr[0]))
		fi
		_cpu=$((_cpu + 1))
	done
	echo "${_cpu}"
}

function exclude_cpus()
{
	local _root_cpuset="$1" _cg_cpuset="$2"
    local set="" cg_map=() root_map=()
	declare -i i end
	for _c in ${_root_cpuset//,/ }; do
		read -r -a _arr <<< "${_c//-/ }"
		i="${_arr[0]}"
		[[ ${#_arr[@]} -eq 2 ]] && end=${_arr[1]} || end=${i}
		while [[ ${i} -le ${end} ]]; do
			root_map[i]=1
			i=$((i+1))
		done
	done
	for _c in ${_cg_cpuset//,/ }; do
		read -r -a _arr <<< "${_c//-/ }"
		i="${_arr[0]}"
		[[ ${#_arr[@]} -eq 2 ]] && end=${_arr[1]} || end=${i}
		while [[ ${i} -le ${end} ]]; do
			cg_map[i]=1
			i=$((i+1))
		done
	done
	i=0
	while [[ ${i} -lt ${#root_map[*]} ]]; do
		if [[ -n "${root_map[${i}]}" ]]; then
			if [[ -z "${cg_map[${i}]}" ]]; then
                set+="${set:+,}${i}"
			fi
		fi
		i=$((i+1))
	done
	[[ -z "${set}" ]] || echo "${set}"
}

read -r -a mem_arr <<< "$(free -b | grep -i "mem:" || true)"
root_mem="${mem_arr[1]}"

read -r -a cgmount <<<"$(grep cgroup /proc/mounts)"
#cgroup2 /sys/fs/cgroup cgroup2 rw,nosuid,nodev,noexec,relatime,nsdelegate,memory_recursiveprot 0 0
if [[ "${cgmount[2]}" == "cgroup2" ]]; then
    cgver="2"
    cg_mem="$(<"${cgpath}/${cgroup}/memory.max")"
    cg_cpuset="$(<"${cgpath}/${cgroup}/cpuset.cpus.effective")"
    root_cpuset="$(<"${cgpath}/cpuset.cpus.effective")"
else
    cgver="1"
    cg_mem="$(<"${cgpath}/memory/${cgroup}/memory.limit_in_bytes")"
    cg_cpuset="$(<"${cgpath}/cpuset/${cgroup}/cpuset.cpus")"
    root_cpuset="$(<"${cgpath}/cpuset/cpuset.cpus")"
fi

cg_cpus="$(count_cpus "${cg_cpuset}")"
root_cpus="$(count_cpus "${root_cpuset}")"

[[ -n "${SKIP_RESERVED_CPU}" ]] || echo "RESERVED_CPU=$(((root_cpus-cg_cpus)*100))"

echo "RESERVED_MEM=$(( (root_mem - cg_mem) / 1024 ))"

storpool_confshow SP_OURID 2>/dev/null

isolcpus=$(exclude_cpus "${root_cpuset}" "${cg_cpuset}")
[[ -z ${DEBUG:-} ]] || echo "#CGROUPv${cgver} root_cpuset '${root_cpuset}', cg_cpuset '${cg_cpuset}', cg_mem '${cg_mem}', isolcpus '${isolcpus}'" >&2
[[ -z ${isolcpus} ]] || echo "ISOLCPUS=\"${isolcpus}\""
