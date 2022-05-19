#!/usr/bin/env python

# -------------------------------------------------------------------------- #
# Copyright 2015-2021, StorPool (storpool.com)                               #
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


from sys import argv
from xml.etree import ElementTree as ET

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

xmlVm = argv[2]
vm_element = ET.parse(xmlVm)
vm = vm_element.getroot()

xmlDomain = argv[1]

doc = ET.parse(xmlDomain)
root = doc.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

vf_macs = vm.find('.//USER_TEMPLATE/T_VF_MACS')

hit = 0
if vf_macs is None:
    macs = []
    for pci in vm.findall('.//TEMPLATE/PCI'):
        mac_e = pci.find('./MAC')
        if mac_e is not None:
            macs.append(mac_e.text)
            hit = 1
        else:
            macs.append('')
    if hit:
        vf_macs = ET.Element('T_VF_MACS')
        vf_macs.text = ','.join(macs)

if vf_macs is not None:
    i = 0
    changed = 0
    macs = vf_macs.text.split(",")
    for device in root.findall("./devices"):
        for hostdev in device.findall("./hostdev[@type='pci']"):
            try:
                if macs[i] != '':
                    interface = ET.Element('interface',{
                                             'type': 'hostdev',
                                             'managed': 'yes',
                                             })
                    driver = ET.SubElement(interface,'driver',{
                                                     'name':'vfio',
                                                     })
                    tmp = ET.SubElement(interface,'mac',{
                                                  'address': macs[i],
                                                  })
                    source = hostdev.find("./source")
                    sourceAddress = source.find("./address")
                    sourceAddress.set('type', 'pci')
                    interface.append(source)
                    pciaddress = hostdev.find("./address")
                    interface.append(pciaddress)
                    device.remove(hostdev)
                    device.append(interface)
                    changed = 1
            except Exception as e:
                pass
            i += 1
    if changed:
        indent(root)
        doc.write(xmlDomain)
