#!/usr/bin/env python3

# -------------------------------------------------------------------------- #
# Copyright 2015-2024, StorPool (storpool.com)                               #
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

# Global env: PERSISTENT_CDROM=4
# .//USER_TEMPLATE/T_PERSISTENT_CDROM = 4

from __future__ import print_function
import os
from sys import argv, stderr
from xml.etree import ElementTree as ET
import syslog

ns = {'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
       'one': "http://opennebula.org/xmlns/libvirt/1.0"
     }

def indent(elem, level=0, ind="  "):
    i = "\n" + level * ind
    if len(elem):
        if not elem.text or not elem.text.strip():
            elem.text = i + ind
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
        for elem in elem:
            indent(elem, level+1, ind)
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
    else:
        if not level:
            return
        if not elem.text or not elem.text.strip():
            elem.text = None
        if not elem.tail or not elem.tail.strip():
            elem.tail = i

def log_inf(logmsg):
    if test_env is None:
        syslog.syslog(syslog.LOG_INFO, "[I]vmm_sp_deploy: " + logmsg)
    else:
        print("[I]" + logmsg, file=stderr)

def log_err(logmsg):
    if test_env is None:
        syslog.syslog(syslog.LOG_ERR, "[E]vmm_sp_deploy: " + logmsg)
    print("[E]" + logmsg, file=stderr)

def log_dbg(logmsg):
    if test_env is None:
        syslog.syslog(syslog.LOG_DEBUG, "[D]vmm_sp_deploy: " + logmsg)
    else:
        print("[D]" + logmsg, file=stderr)


test_env = os.getenv('TEST_ENV', None)
# The pc type has 1 IDE controller so 4 devices max
max_cdrom_devices = int(os.getenv('MAX_CDROM_DEVICES', '4'))

xmlDomain = argv[1]
doc = ET.parse(xmlDomain)
root = doc.getroot()

xmlVm = argv[2]
vm_element = ET.parse(xmlVm)
vm_root = vm_element.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

used_ide_devices = []
dom_cdroms = {}
cdrom_elements = root.findall('.//devices/disk[@device="cdrom"]')
for cdrom_element in cdrom_elements:
    info = { "element": cdrom_element }
    source_element = cdrom_element.find('./source')
    info["source_entry"] = "file"
    if cdrom_element.get('type') == 'block':
        info["source_entry"] = "dev"
    info["source"] = source_element.get(info["source_entry"])
    info["disk_id"] = int(info["source"].rsplit('disk.')[1])
    target_element = cdrom_element.find('./target')
    
    target_dev = target_element.get('dev')
    info["target_dev"] = target_dev
    if target_dev[0:2] == 'hd':
       used_ide_devices.append(info["target_dev"])
    info["target_bus"] = target_element.get('bus')
    dom_cdroms[info["disk_id"]] = info

dom_cdroms_count = len(dom_cdroms)

#find devices element
devices_element = root.findall('.//devices')[0]

pers_cdroms_count = 0
pers_cdroms_count_env = os.getenv('T_PERSISTENT_CDROM', '0')
if pers_cdroms_count_env.isnumeric():
    pers_cdroms_count = int(pers_cdroms_count_env)
t_pers_cdrom_element = vm_root.find('.//USER_TEMPLATE/T_PERSISTENT_CDROM')
if t_pers_cdrom_element is not None:
    if t_pers_cdrom_element.text.isnumeric():
        pers_cdroms_count = int(t_pers_cdrom_element.text)    

disk_cdrom_type = "block"
t_pers_cdrom_type_element = vm_root.find('.//USER_TEMPLATE/T_PERSISTENT_CDROM_TYPE')
if t_pers_cdrom_type_element is not None:
    if t_pers_cdrom_type_element.text.lower() in ['file', 'block']:
        disk_cdrom_type = t_pers_cdrom_type_element.text.lower()

pers_cdroms = []
changed = 0
if pers_cdroms_count > 0:
    if pers_cdroms_count > max_cdrom_devices:
        log_inf(f"persistent cdroms count {pers_cdroms_count} > {max_cdrom_devices}! Setting {max_cdrom_devices} devices.")
        pers_cdroms_count = max_cdrom_devices

    if dom_cdroms_count > max_cdrom_devices - 1:
        msg = f"already have {dom_cdroms_count} >0. nothing to do"
        print(msg, file=stderr)
        log_inf(msg)
        exit(0)

    cdroms_count = max_cdrom_devices - dom_cdroms_count
    if cdroms_count < 1:
        msg = f"{cdroms_count} < 1. nothing to do"
        print(msg, file=stderr)
        log_inf(msg)
        exit(0)

    if cdroms_count > pers_cdroms_count:
        cdroms_count = pers_cdroms_count

    for idx in range(cdroms_count):
        # get free target_dev
        dev = None
        for i in range(max_cdrom_devices):
            dev = "hd" + chr(97 + i)
            if dev in used_ide_devices:
                dev = None
                continue
            used_ide_devices.append(dev)
            break
        disk_element = ET.SubElement(
                devices_element,
                'disk',
                {
                "type": disk_cdrom_type, 
                "device": "cdrom",
                },
            )
        target_element = ET.SubElement(
            disk_element,
            "target",
            {
                "dev": dev,
                "bus": "ide",
            },
        )
        driver_element = ET.SubElement(
            disk_element,
            "driver",
            {
                "name": "qemu",
                "type": "raw",
                "cache": "none",
                "io": "native",
            },
        )
        readolny_element = ET.SubElement(disk_element, "readonly", {})
        changed = 1
        log_inf(f"added cdrom device: {dev} type:{disk_cdrom_type}")

if changed:
    indent(root)
    doc.write(xmlDomain)
