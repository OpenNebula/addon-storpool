#!/bin/bash
#

# -------------------------------------------------------------------------- #
# Copyright 2015-2016, StorPool (storpool.com)                               #
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

# This script is working with the following environment variables:
#
# FT_ACTION={FENCE|THAW}
# FT_HOSTNAME={kvm node hostname}
#

PATH=/usr/sbin:/usr/bin:$PATH

[ "`whoami`" = "root" ] && SUDO= || SUDO=sudo

case "$FT_ACTION" in
    FENCE)
        # ssh
        $SUDO iptables -I OUTPUT -j REJECT --reject-with tcp-reset -p tcp --dport 22 -d "$FT_HOSTNAME"
        # collectd
        $SUDO iptables -I INPUT -j REJECT --reject-with icmp-port-unreachable -p udp --dport 4124 -s "$FT_HOSTNAME"
        ;;
    THAW)
        # ssh
        $SUDO iptables -D OUTPUT -j REJECT --reject-with tcp-reset -p tcp --dport 22 -d "$FT_HOSTNAME"
        # collectd
        $SUDO iptables -D INPUT -j REJECT --reject-with icmp-port-unreachable -p udp --dport 4124 -s "$FT_HOSTNAME"
        ;;
esac
