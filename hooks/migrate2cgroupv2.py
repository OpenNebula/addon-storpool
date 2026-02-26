#!/usr/bin/env python3
"""libvirt hook to help live migration from cgroupv1 host to cgroupv2 host"""

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
# -------------------------------------------------------------------------- #

#
# mkdir -p /etc/libvirt/hooks/qemu.d
# cp migrate2cgroupv2.py /etc/libvirt/hooks/qemu.d/
# systemctl restart libvirtd
#

import sys
import subprocess
from xml.etree import ElementTree as ET
import syslog

V1_SHARES_BASE = 1024
V2_SHARES_BASE = 100
V2_SHARES_MAX = 10000
V2_SHARES_MIN = 1

ns = {
    "qemu": "http://libvirt.org/schemas/domain/qemu/1.0",
    "one": "http://opennebula.org/xmlns/libvirt/1.0",
}


def indent(elem, level=0, ind="  "):
    """Indent XML elements"""
    i = "\n" + level * ind
    if len(elem):
        if not elem.text or not elem.text.strip():
            elem.text = i + ind
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
        for element in elem:
            indent(element, level + 1, ind)
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
    else:
        if not level:
            return
        if not elem.text or not elem.text.strip():
            elem.text = None
        if not elem.tail or not elem.tail.strip():
            elem.tail = i


def get_cg_version(cg_path="/sys/fs/cgroup"):
    """Get cgroup version"""
    ret = 1
    cmd = ["stat", "-fc", "%T", cg_path]
    res = subprocess.run(
        cmd, encoding="utf-8", stdout=subprocess.PIPE, check=True
    )
    answer = res.stdout.strip()
    if answer == "cgroup2fs":
        ret = 2
    return ret


syslog.syslog(syslog.LOG_INFO, f"_sp_ argv={sys.argv}")

doc = ET.parse(sys.stdin)

root = doc.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

CG_VERSION = get_cg_version()

for shares_e in root.findall("./cputune/shares"):
    if CG_VERSION == 2:
        shares = int(shares_e.text)
        if shares > V2_SHARES_MAX:
            cpu = -(-shares // V1_SHARES_BASE)
            v2_shares = cpu * V2_SHARES_BASE
            if v2_shares > V2_SHARES_MAX:
                v2_shares = V2_SHARES_MAX
            elif v2_shares < V2_SHARES_MIN:
                v2_shares = V2_SHARES_MIN
            msg = f"_sp_ cputune/{shares=}, {cpu=} to {v2_shares}"
            syslog.syslog(syslog.LOG_INFO, msg)
            shares_e.text = str(v2_shares)

indent(root)
print(ET.tostring(root).decode("utf-8"))
