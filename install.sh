#!/bin/bash

# -------------------------------------------------------------------------- #
# Copyright 2015, Storpool (storpool.com)                                    #
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

ONE_USER=${ONE_USER:-oneadmin}
ONE_VAR=${ONE_VAR:-/var/lib/one}
ONE_LIB=${ONE_LIB:-/usr/lib/one}
ONE_DS=${ONE_DS:-/var/lib/one/datastores}

if [ -n "$ONE_LOCATION" ]; then
    ONE_VAR="$ONE_LOCATION/var"
    ONE_LIB="$ONE_LOCATION/lib"
    ONE_DS="$ONE_LOCATION/var/datastores"
fi

SUNSTONE_PLUGINS=${SUNSTONE_PLUGINS:-$ONE_LIB/sunstone/public/js/plugins/}

#----------------------------------------------------------------------------#

[ "${0/\//}" != "$0" ] && cd ${0%/*}

CWD=$(pwd)

# install datastore and tm MAD
for MAD in datastore tm; do
    echo "*** Installing $ONE_VAR/remotes/${MAD}/storpool ..."
    mkdir -pv "$ONE_VAR/remotes/${MAD}/storpool"
    cp $CP_ARG ${MAD}/storpool/* "$ONE_VAR/remotes/${MAD}/storpool/"
    chown -R "$ONE_USER" "$ONE_VAR/remotes/${MAD}/storpool"
    chmod u+x -R "$ONE_VAR/remotes/${MAD}/storpool"
done

# install xpath_multi.py
XPATH_MULTI="$ONE_VAR/remotes/datastore/xpath_multi.py"
echo "*** Installing $XPATH_MULTI ..."
cp $CP_ARG datastore/xpath_multi.py "$XPATH_MULTI"
chown "$ONE_USER" "$XPATH_MULTI"
chmod u+x "$XPATH_MULTI"

# install oremigrate and postmigrate hooks in shared
for MIGRATE in premigrate postmigrate; do
    if [ "$(egrep -v '^#|^$' $ONE_VAR/remotes/tm/shared/$MIGRATE)" = "exit 0" ]; then
        M_FILE="$ONE_VAR/remotes/tm/shared/${MIGRATE}"
        echo "*** Installing $M_FILE"
        cp $CP_ARG tm/shared/${MIGRATE}.storpool "$M_FILE"
    else
        M_FILE="$ONE_VAR/remotes/tm/shared/${MIGRATE}.storpool"
        echo "*** ${M_FILE%.storpool} file not empty!"
        echo "*** Please merge carefully ${M_FILE%.storpool} to $M_FILE"
        cp $CP_ARG tm/shared/${MIGRATE}.storpool "$M_FILE"
    fi
    chown "$ONE_USER" "$M_FILE"
    chmod u+x "$M_FILE"
done

# patch sunstone's datastores-tab.js
if [ -f "$SUNSTONE_PLUGINS/datastores-tab.js" ]; then
    if grep -q -i storpool $SUNSTONE_PLUGINS/datastores-tab.js; then
        echo "*** already applied sunstone integration in $SUNSTONE_PLUGINS/datastores-tab.js"
    else
        echo "*** enabling sunstone integration in $SUNSTONE_PLUGINS/datastores-tab.js"
        cd "$SUNSTONE_PLUGINS"
        patch -b -p 0 < "$CWD/patches/datastores-tab.js.patch"
        cd "$CWD"
    fi
else
    echo "sunstones js plugin datastores-tab.js not found in $ONE_LIB/sunstone/public/js/plugins/"
    echo "StorPool integration to sunstone not installed!"
fi

# Enable StorPool in oned.conf
if grep -q -i storpool /etc/one/oned.conf &>/dev/null; then
    echo "*** StorPool is already enabled in /etc/one/oned.conf"
else
    echo "*** enabling StorPool plugin in /etc/one/oned.conf"
    cp /etc/one/oned.conf /etc/one/oned.conf.bak;

    sed -i -e 's|ceph,dev|ceph,dev,storpool|g' /etc/one/oned.conf

    cat <<_EOF_ >>/etc/one/oned.conf
# StorPool
TM_MAD_CONF = [
    name = "storpool", ln_target = "NONE", clone_target = "SELF", shared = "yes"
]
_EOF_
fi

echo "*** Please restart opennebula and opennebula-sunstone services"
