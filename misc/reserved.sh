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

function count_cpus()
{
        local _cpu=0 _c=""
        declare -a _arr_a _list_a
        IFS=',' read -r -a _list_a <<< "$1"
        for _c in "${_list_a[@]}"; do
                IFS='-' read -r -a _arr_a <<< "${_c}"
                if [[ ${#_arr_a[@]} -gt 1 ]]; then
                        _cpu=$((_cpu + _arr_a[1] - _arr_a[0]))
                fi
                _cpu=$((_cpu + 1))
        done
        echo "${_cpu}"
}

function exclude_cpus()
{
	local _root_cpuset="$1" _cg_cpuset="$2"
    local i=0 end="" _c="" set=""
	declare -A cg_map_a
	declare -A root_map_a
    declare -a _r_cpuset_a
    IFS=',' read -r -a _r_cpuset_a <<< "${_root_cpuset}"
	for _c in "${_r_cpuset_a[@]}"; do
		IFS='-' read -r -a _arr_a <<< "${_c}"
		i="${_arr_a[0]}"
		[[ ${#_arr_a[@]} -gt 1 ]] && end="${_arr_a[1]}" || end="${i}"
		while [[ ${i} -le ${end} ]]; do
			root_map_a[${i}]=1
			i=$((i+1))
		done
	done
	for _c in ${_cg_cpuset//,/ }; do
		IFS='-' read -r -a _arr_a <<< "${_c}"
		i="${_arr_a[0]}"
		[[ ${#_arr_a[@]} -gt 1 ]] && end="${_arr_a[1]}" || end=${i}
		while [[ ${i} -le ${end} ]]; do
			cg_map_a[${i}]=1
			i=$((i+1))
		done
	done
	i=0
	while [[ ${i} -lt ${#root_map_a[*]} ]]; do
		if [[ -n "${root_map_a[${i}]}" ]]; then
			if [[ -z "${cg_map_a[${i}]}" ]]; then
				[[ -z "${set}" ]] || set+=","
                set+="${i}"
			fi
		fi
		i=$((i+1))
	done
	[[ -z ${set} ]] || echo "${set}"
}

read -r -a mem_arr <<< "$(free -b | grep -i "mem:" || true)"
read -r -a cg_arr <<< "$(cgget -v -n -r memory.limit_in_bytes -r cpuset.cpus "${cgroup}" | tr '\n' ' ' || true)"
read -r -a root_arr <<< "$(cgget -v -n -r memory.limit_in_bytes -r cpuset.cpus "" | tr '\n' ' ' || true)"
cg_cpuset="${cg_arr[1]}"
root_cpuset="${root_arr[1]}"
cg_cpus="$(count_cpus "${cg_cpuset}")"
root_cpus="$(count_cpus "${root_cpuset}")"

if [[ -f /var/tmp/one/addon-storpoolrc ]]; then
    # shellcheck source=/dev/null
    source /var/tmp/one/addon-storpoolrc
fi

[[ -n "${SKIP_RESERVED_CPU}" ]] || echo "RESERVED_CPU=$(((root_cpus-cg_cpus)*100))"

echo "RESERVED_MEM=$(((mem_arr[1]-cg_arr[0])/1024))"

storpool_confshow SP_OURID 2>/dev/null

isolcpus=$(exclude_cpus "${root_cpuset}" "${cg_cpuset}")
[[ -z ${DEBUG:-} ]] || echo "root_cpuset '${root_cpuset}', cg_cpuset '${cg_cpuset}', isolcpus '${isolcpus}'" >&2
[[ -z ${isolcpus} ]] || echo "ISOLCPUS=\"${isolcpus}\""
