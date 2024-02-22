#!/bin/bash

# -------------------------------------------------------------------------- #
# Copyright 2015-2021, Storpool (storpool.com)                               #
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

set -e

PATH="/bin:/usr/bin:/sbin:/usr/sbin:$PATH"

CP_ARG=${CP_ARG:--uv}

ONE_ETC=${ONE_ETC:-/etc/one}
ONE_USER=${ONE_USER:-oneadmin}
ONE_VAR=${ONE_VAR:-/var/lib/one}
ONE_LIB=${ONE_LIB:-/usr/lib/one}
ONE_DS=${ONE_DS:-/var/lib/one/datastores}

if [ -n "$ONE_LOCATION" ]; then
    ONE_ETC="$ONE_LOCATION/etc"
    ONE_VAR="$ONE_LOCATION/var"
    ONE_LIB="$ONE_LOCATION/lib"
    ONE_DS="$ONE_LOCATION/var/datastores"
fi


#----------------------------------------------------------------------------#

[ "${0/\//}" != "$0" ] && cd ${0%/*}

CWD=$(pwd)

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
            if [ -n "$_backup" ]; then
                _backup="--backup --version-control=numbered"
            else
                _backup="--no-backup-if-mismatch"
            fi
            if patch ${_backup} --strip=0 --forward --input="${_patch}"; then
                DO_PATCH="done"
            else
                DO_PATCH="failed"
                patch_err="${_patch}"
            fi
        else
            echo "   *** Note! Can't apply patch ${_patch}! Please merge manually."
            patch_err="${_patch}"
        fi
    fi
}

function patch_hook()
{
    local _hook="$1"
    local _hook_line="[ -d \"\${0}.d\" ] \&\& for hook in \"\${0}.d\"/* ; do source \"\$hook\"; done"
    local _is_sh=0 _is_patched=0 _backup= _is_bash=
    grep -E '^#!/bin/sh$' "${_hook}" &>/dev/null && _is_sh=1
    grep  "${_hook_line}" "${_hook}" &>/dev/null && _is_patched=1
    if [ "$(grep -v -E '^#|^$' "${_hook}")" = "exit 0" ]; then
        if [ "${_is_patched}" = "1" ]; then
            echo "*** ${_hook} already patched"
        else
            _backup="${_hook}.backup$(date +%s)"
            echo "*** Create backup of ${_hook} as ${_backup}"
            cp $CP_ARG "${_hook}" "${_backup}"
            if [ "${_is_sh}" = "1" ]; then
                grep -E '^#!/bin/bash$' "${_hook}" &>/dev/null && _is_bash=1
                if [ "${_is_bash}" = "1" ]; then
                    echo "*** ${_hook} already bash script"
                else
                    sed -i -e 's|^#!/bin/sh$|#!/bin/bash|' "${_hook}"
                fi
            fi
            sed -i -e "s|^exit 0|$_hook_line\nexit 0|" "${_hook}"
        fi
    else
        echo "*** ${_hook} file not empty!"
        echo " ** Note! Please merge the following line to ${_hook}"
        echo " **"
        echo " ** ${_hook_line//\\&/&}"
        echo " **"
        if [ "${_is_sh}" = "1" ]; then
            echo " ** Note! Set script to bash:"
            echo " **   sed -i -e 's|^#!/bin/sh\$|#!/bin/bash|' \"${_hook}\""
        fi
    fi
}

function findFile()
{
    local c f d="$1" csum="$2"
    while read -u 5 c f; do
        if [ "$c" = "$csum" ]; then
            echo $f
            break
        fi
    done 5< <(md5sum $d/* 2>/dev/null)
}

function tmResetMigrate()
{
    local current_csum=$(md5sum "${M_DIR}/${MIGRATE}" | awk '{print $1}')
    local csum comment found orig_csum
    while read -u 5 csum comment; do
        [ "$comment" = "orig" ] && orig_csum="$csum"
        if [ "$current_csum" = "$csum" ]; then
            found="$comment"
            break;
        fi
    done 5< <(cat "tm/${TM_MAD}-${MIGRATE}.md5sums")
    case "$found" in
         orig)
            ;;
         4.10)
            true
            ;&
         4.14)
            orig=$(findFile "$M_DIR" "$orig_csum" )
            if [ -n "$orig" ]; then
                echo "***   $found variant of $TM_MAD/$MIGRATE"
                mv "${M_DIR}/${MIGRATE}" "${M_DIR}/${MIGRATE}.backup$(date +%s)"
                echo "***   restoring from original ${orig##*/}"
                cp $CP_ARG "$orig" "${M_DIR}/${MIGRATE}"
            fi
            ;;
         5.00)
            continue
            ;;
            *)
            echo " ** Can't determine the variant of $TM_MAD/$MIGRATE"
    esac
}

oneVersion(){
    local arr=(${1//\./ })
    export ONE_MAJOR="${arr[0]}"
    export ONE_MINOR="${arr[1]}"
    export ONE_VERSION=$((arr[0]*10000 + arr[1]*100 + arr[2]))
    if [ ${#arr[*]} -eq 4 ] || [ $ONE_VERSION -lt 51200 ]; then
        export ONE_EDITION="CE${arr[3]}"
    else
        export ONE_EDITION="EE"
    fi
}

if [ -f "$ONE_VAR/remotes/VERSION" ]; then
    [ -n "$ONE_VER" ] || ONE_VER="$(< "$ONE_VAR/remotes/VERSION")"
fi

oneVersion "$ONE_VER"

TMPDIR="$(mktemp -d addon-storpool-install-XXXXXXXX)"
export TMPDIR
trap "rm -rf \"${TMPDIR}\"" EXIT QUIT TERM

if [ -f "scripts/install-${ONE_VER}.sh" ]; then
    source "scripts/install-${ONE_VER}.sh"
elif [ -f "scripts/install-${ONE_MAJOR}.${ONE_MINOR}.sh" ]; then
    source "scripts/install-${ONE_MAJOR}.${ONE_MINOR}.sh"
else
    echo "ERROR: Unknown OpenNebula version '$ONE_VER' detected!"
    echo "Please contact StorPool support for assistance"
    echo
fi
