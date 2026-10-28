#!/bin/bash

# -------------------------------------------------------------------------- #
# Copyright 2015-2025, Storpool (storpool.com)                               #
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

set -e -o pipefail

PATH="/bin:/usr/bin:/sbin:/usr/sbin:${PATH}"

CP_ARG="${CP_ARG:-"-v -L -f"}"
export CP_ARG
read -r -a CP_ARGS <<< "${CP_ARG}"

export ONE_ETC=${ONE_ETC:-/etc/one}
export ONE_USER=${ONE_USER:-oneadmin}
export ONE_GROUP=${ONE_GROUP:-oneadmin}
export ONE_VAR=${ONE_VAR:-/var/lib/one}
export ONE_LIB=${ONE_LIB:-/usr/lib/one}
export ONE_DS=${ONE_DS:-/var/lib/one/datastores}

if [[ -n "${ONE_LOCATION:-}" ]]; then
    ONE_ETC="${ONE_LOCATION}/etc"
    ONE_VAR="${ONE_LOCATION}/var"
    ONE_LIB="${ONE_LOCATION}/lib"
    ONE_DS="${ONE_LOCATION}/var/datastores"
fi


#----------------------------------------------------------------------------#

[[ "${0/\//}" != "$0" ]] && cd "${0%/*}"

CWD=$(pwd)
export CWD

function boolTrue()
{
   case "${!1^^}" in
       1|Y|YES|T|TRUE|ON)
           return 0
           ;;
       *)
           return 1
   esac
}

function patch_merged()
{
    local _patch="$1" _file="" _line=""
    local -A _added=()
    while read -r _line; do
        case "${_line}" in
            ---*|@@*)
                ;;
            +++*)
                _file="${_line#+++ }"
                _file="${_file%%$'\t'*}"
                [[ -f "${_file}" ]] || return 1
                ;;
            +*)
                _line="${_line#+}"
                [[ -z "${_line//[[:space:]]/}" ]] && continue
                _added["${_line}"]=1
                grep -qxF -- "${_line}" "${_file}" || return 1
                ;;
            *)
                ;;
        esac
    done < "${_patch}"
    while read -r _line; do
        case "${_line}" in
            ---*)
                ;;
            -*)
                _line="${_line#-}"
                [[ -z "${_line//[[:space:]]/}" ]] && continue
                [[ -n "${_added["${_line}"]:-}" ]] && continue
                grep -qxF -- "${_line}" "${_file}" && return 1
                ;;
            *)
                ;;
        esac
    done < "${_patch}"
    return 0
}

function do_patch()
{
    local _patch="$1" _backup="$2"
    #check if patch is applied
    echo "*** Testing patch ${_patch##*/}"
    if patch --dry-run --reverse --forward --strip=0 --input="${_patch}" 2>/dev/null >/dev/null; then
        echo "   *** Patch file ${_patch##*/} already applied?"
    else
        if patch --dry-run --forward --strip=0 --input="${_patch}" 2>/dev/null >/dev/null; then
            echo "   *** Apply patch ${_patch##*/}"
            if [[ -n "${_backup}" ]]; then
                _backup="--backup --version-control=numbered"
            else
                _backup="--no-backup-if-mismatch"
            fi
            read -r -a _backup_a <<< "${_backup}"
            if patch "${_backup_a[@]}" --strip=0 --forward --input="${_patch}"; then
                DO_PATCH="done"
                export DO_PATCH
                return 0
            fi
            DO_PATCH="failed"
            patch_err="${_patch}"
            export DO_PATCH patch_err
            return 1
        fi
        if patch_merged "${_patch}"; then
            echo "   *** Patch file ${_patch##*/} already merged"
            return 0
        fi
        patch_err="${_patch}"
        DO_PATCH="failed"
        export patch_err DO_PATCH
        echo "   *** Note! Can't apply patch ${patch_err}! Please merge manually."
        return 1
    fi
    return 0
}

function patch_ok()
{
    local _patch="$1"
    if patch --dry-run --reverse --forward --strip=0 --input="${_patch}" >/dev/null 2>&1; then
        return 0
    fi
    if patch --dry-run --forward --strip=0 --input="${_patch}" >/dev/null 2>&1; then
        return 0
    fi
    patch_merged "${_patch}"
}

oneVersion(){
    local arr=() edition_file=""
    read -r -a arr <<< "${1//\./ }"
    export ONE_MAJOR="${arr[0]}"
    export ONE_MINOR="${arr[1]}"
    export ONE_VERSION=$((arr[0]*10000 + arr[1]*100 + arr[2]))
    ONE_EDITION="CE"
    edition_file="${ONE_VAR}/remotes/EDITION"
    if [[ -f "${edition_file}" ]]; then
        ONE_EDITION="$(head -n 1 "${edition_file}")"
    fi
    if [[ ${#arr[*]} -gt 3 ]]; then
        ONE_EDITION="CE${arr[3]}"
    fi
    export ONE_EDITION
}

if [[ -f "${ONE_VAR}/remotes/VERSION" ]]; then
    [[ -n "${ONE_VER}" ]] || ONE_VER="$(< "${ONE_VAR}/remotes/VERSION")"
fi

oneVersion "${ONE_VER}"
echo "*** OpenNebula version ${ONE_VER} edition ${ONE_EDITION}"

if [[ -f "scripts/install-${ONE_VER}.sh" ]]; then
    INSTALL_SCRIPT="scripts/install-${ONE_VER}.sh"
elif [[ -f "scripts/install-${ONE_MAJOR}.${ONE_MINOR}.sh" ]]; then
    INSTALL_SCRIPT="scripts/install-${ONE_MAJOR}.${ONE_MINOR}.sh"
else
    echo "ERROR: Unknown OpenNebula version '${ONE_VER}' detected!" >&2
    echo "Please contact StorPool support for assistance" >&2
    exit 1
fi

TMPDIR="$(mktemp -d -t addon-storpool-install.XXXXXXXX)"
export TMPDIR
# shellcheck disable=SC2064
trap "rm -rf \"${TMPDIR}\"" EXIT QUIT TERM

echo "*** Using ${INSTALL_SCRIPT}"
# shellcheck source=scripts/install-6.4.sh
source "${INSTALL_SCRIPT}"
