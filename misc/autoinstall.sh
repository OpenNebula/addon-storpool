#!/bin/bash
#

# -------------------------------------------------------------------------- #
# Copyright 2015-2017, StorPool (storpool.com)                               #
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

#
# bash autoinstall.sh [branch_or_tag_name]
#
# Script that automate the download and installation of addon-storpool.
# By default the script fetches latest 'release' tag. If there is a need to
# install older release or current master branch provide the tag or branch name
# as first argument.

set -o pipefail

PATH=/bin:/usr/bin:/sbin:/usr/sbin:$PATH

if [ -n "$1" ]; then
    TAG_NAME="$1"
    NAME="addon-storpool-$TAG_NAME"
else
    echo "+ Lookup for latest release ..."
    API_URL="https://api.github.com/repos/OpenNebula/addon-storpool/releases/latest"
    JSON="$(mktemp -t sp-tmp-XXXXXXXX)"
    trap "rm -f \"${JSON}\"" EXIT QUIT INT HUP KILL
    if curl --silent --location -o "$JSON" "$API_URL"; then
        TAG_NAME=$(jq -r .tag_name "$JSON")
        NAME=$(jq -r .name "$JSON")
    else
        echo " ! Error: reacing $API_URL"
        exit 1
    fi
fi

URL="https://github.com/OpenNebula/addon-storpool/archive/${TAG_NAME}.tar.gz"
echo "+ Downloading $NAME"
if curl --silent --location -o "${TAG_NAME}.tar.gz" "$URL"; then
    mv "${TAG_NAME}.tar.gz" "${NAME}.tar.gz"
    [ -d "$NAME" ] && rm -rf "$NAME"
    echo "+ Unpacking   ${NAME}.tar.gz"
    if tar xf "${NAME}.tar.gz"; then
        if cd "$NAME"; then
            echo "+ Installing dependencies ..."
            yum -y --enablerepo=epel install patch git jq lz4 npm
            LOG="${NAME}-install-$(date +%s).log"
            echo "+ Installing  $NAME"
            if bash install.sh 2>&1 | tee "../$LOG"; then
                echo "+ DONE"
                cd -
                rm -fr "$NAME"
            else
                echo " ! Error: Installation failed! Search for details in $LOG"
                cd -
            fi
        else
           echo " ! Error: Can't cd $NAME"
           exit 1
       fi
    else
        echo " ! Error: Can't unpack ${NAME}.tar.gz"
        exit 1
    fi
else
    echo " ! Error: getting $URL"
    exit 1
fi
