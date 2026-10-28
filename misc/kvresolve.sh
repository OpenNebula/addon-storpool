#!/bin/bash
#

# -------------------------------------------------------------------------- #
# Copyright 2015-2026, StorPool (storpool.com)                               #
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

# Resolve the addon's etcd KV mapping: a name (one-img-N, one-sys-V-D,
# ...) returns its StorPool globalId from /byName/, a globalId (~xxx.b.yy)
# returns its name from /byUid/. A pair that does not point back at
# itself is reported on stderr.
#
# Usage: kvresolve.sh [-n|-u] [-p] [-d] NAME|GLOBALID...
#
#  -n  the arguments are names (byName lookup)
#  -u  the arguments are globalIds (byUid lookup)
#  -p  prefix lookup: list every key starting with the argument
#  -d  debug the etcdctl calls on stderr
#
# Standalone, needs the etcdctl environment of oneadmin on the front-end.
# Exit status: 0 all resolved, 1 an entry is missing, 2 etcdctl failed.

set -o pipefail

TMPDIR="${TMPDIR:-/tmp}"
DEBUG_KV="${DEBUG_KV:-0}"
DDEBUG_KV="${DDEBUG_KV:-0}"

function splog()
{
    echo "[$(date +%T || true)] ${0##*/}: $*" >&2
}

function boolTrue()
{
    case "${!1^^}" in
        1|Y|YES|T|TRUE|ON) return 0 ;;
        *) return 1 ;;
    esac
}

# copied from tm/storpool/storpool_common.sh
# shellcheck disable=SC2034
function kvGet()
{
    local _kvKey="$1" _kvName="$2" _prefix="$3" _keysAndVals="$4"
    local KVRES="" KVRET=1 _line="" _pvo="1" _DBGPX=""
    local KVKEY="/${_kvKey}/${_kvName}"
    local _errFile="${TMPDIR}/etcdctl_get_err"
    local _kvGetLogFile="${TMPDIR}/etcdctl_get"
    [[ -z "${_keysAndVals}" ]] || _pvo=""
    if boolTrue "DDEBUG_KV"; then
        splog "[D] kvGet(${_kvKey}, ${_kvName}, ${_prefix}, ${_keysAndVals}) =-> ${KVKEY}"
    fi
    ETCDCTL_API=3 etcdctl get${_pvo:+ --print-value-only}${_prefix:+ --prefix} -- "${KVKEY}" 2>"${_errFile}" | tee "${_kvGetLogFile}"
    KVRET=$?
    if boolTrue "DEBUG_KV" || [[ ${KVRET} -ne 0 ]]; then
        boolTrue "DEBUG_KV" && _DBGPX="D" || _DBGPX="W"
        splog "[${_DBGPX}] get($*) stdout:'$(tr '\n' ' ' <"${_kvGetLogFile}" || true)' (${KVRET})"
        if [[ -s "${_errFile}" ]]; then
            while read -r -u "${errfh}" _line; do
               splog "[D] kvGet(${KVKEY}) stderr:${_line}"
            done {errfh}< <(cat "${_errFile}" || true)
        fi
    fi
    return "${KVRET}"
}

function usage()
{
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

MODE="" PREFIX=""
while getopts "nupdh" opt; do
    case "${opt}" in
        n) MODE="byName" ;;
        u) MODE="byUid" ;;
        p) PREFIX="startswith" ;;
        d) DEBUG_KV=1; DDEBUG_KV=1 ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done
shift $((OPTIND - 1))
[[ $# -gt 0 ]] || usage 1

TMPDIR="$(mktemp -d "${TMPDIR}/kvresolve.XXXXXX")" || exit 2
trap 'rm -rf "${TMPDIR}"' EXIT

RET=0
for ARG in "$@"; do
    KEY="${MODE}"
    if [[ -z "${KEY}" ]]; then
        [[ "${ARG}" == "~"* ]] && KEY="byUid" || KEY="byName"
    fi
    [[ "${KEY}" == "byName" ]] && REVKEY="byUid" || REVKEY="byName"
    if [[ -n "${PREFIX}" ]]; then
        if ! kvGet "${KEY}" "${ARG}" "${PREFIX}" KeysAndVals | paste - -; then
            RET=2
        fi
        continue
    fi
    VAL="$(kvGet "${KEY}" "${ARG}")"
    KVRET=$?
    if [[ ${KVRET} -ne 0 ]]; then
        echo "${ARG}: etcdctl failed (${KVRET})" >&2
        RET=2
        continue
    fi
    if [[ -z "${VAL}" ]]; then
        echo "${ARG}: no /${KEY}/ entry" >&2
        [[ ${RET} -eq 0 ]] && RET=1
        continue
    fi
    if [[ $# -gt 1 ]]; then
        echo "${ARG} ${VAL}"
    else
        echo "${VAL}"
    fi
    BACK="$(kvGet "${REVKEY}" "${VAL}")" || continue
    if [[ "${BACK}" != "${ARG}" ]]; then
        echo "${ARG}: /${REVKEY}/${VAL} is '${BACK:-missing}', not '${ARG}'" >&2
    fi
done
exit "${RET}"
