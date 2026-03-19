#!/usr/bin/env python3
"""
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
# noqa: E501
# with T_VF_MACS=1e:68:63:c5:ba:be
# From
# ---
#<devices>
#  <hostdev mode='subsystem' type='pci' managed='yes'>
#    <source>
#      <address  domain='0x0000' bus='0xd8' slot='0x00' function='0x5'/>
#    </source>
#    <address type='pci' domain='0x0000' bus='0x01' slot='0x01' function='0'/>
#  </hostdev>
#</devices>
#
# To
# ---
#<devices>
#  <interface managed="yes" type="hostdev">
#    <driver name="vfio" />
#    <mac address="1e:68:63:c5:ba:be" />
#    <source>
#      <address bus="0xd8" domain="0x0000" function="0x5" slot="0x00" type="pci" />
#    </source>
#    <address type='pci' domain='0x0000' bus='0x01' slot='0x01' function='0'/>
#  </interface>
#</devices>
"""

from typing import Optional, List
import sys
from xml.etree import ElementTree as ET

ns = {
    'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
    'one': "http://opennebula.org/xmlns/libvirt/1.0",
}


def indent(elem: ET.Element, level: int = 0, ind: str = "  "):
    i: str = "\n" + level * ind
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


xmlDomain: str = sys.argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

xmlVm: str = sys.argv[2]
vm_et: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_et.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

xpath: str = './/USER_TEMPLATE/T_VF_MACS'
vf_macs: Optional[ET.Element] = vm.find(xpath)
macs: List[str] = []
changed: bool = False
hit: bool = False
if vf_macs is None:
    for t_pci_e in vm.findall('.//TEMPLATE/PCI'):
        mac_e: Optional[ET.Element] = t_pci_e.find('./MAC')
        if mac_e is not None and mac_e.text is not None:
            macs.append(mac_e.text)
            hit = True
        else:
            macs.append('')
    if hit:
        vf_macs = ET.Element('T_VF_MACS')
        vf_macs.text = ','.join(macs)

if vf_macs is not None and vf_macs.text is not None:
    i: int = 0
    macs = vf_macs.text.split(",")
    for device_e in root.findall("./devices"):
        for hostdev_e in device_e.findall("./hostdev[@type='pci']"):
            try:
                if macs[i] != '':
                    interface_e: ET.Element = ET.Element(
                        'interface', {'type': 'hostdev', 'managed': 'yes'}
                    )
                    driver_e: ET.Element = ET.SubElement(
                        interface_e, 'driver', {'name': 'vfio'}
                    )
                    tmp_e: ET.Element = ET.SubElement(
                        interface_e, 'mac', {'address': macs[i]}
                    )
                    source_e: Optional[ET.Element] = hostdev_e.find("./source")
                    if source_e is not None:
                        interface_e.append(source_e)
                        sourceAddress_e: Optional[ET.Element] = source_e.find(
                            "./address"
                        )
                        if sourceAddress_e is not None:
                            sourceAddress_e.set("type", "pci")
                    pciaddress_e: Optional[ET.Element] = hostdev_e.find(
                        "./address"
                    )
                    if pciaddress_e is not None:
                        interface_e.append(pciaddress_e)
                    device_e.remove(hostdev_e)
                    device_e.append(interface_e)
                    changed = True
            except Exception:
                pass
            i += 1

if changed:
    indent(root)
    doc.write(xmlDomain)
