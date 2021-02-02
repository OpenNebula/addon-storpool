#!/usr/bin/env python2

# -------------------------------------------------------------------------- #
# Copyright 2015-2020, StorPool (storpool.com)                               #
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

from __future__ import print_function
import os
from sys import argv, exit, stderr
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

def get_attributes(attr):
    ret = {}
    for a in attr.split():
        k,v = a.split('=')
        ret[k] = v
    return ret


xmlVm = argv[2]
vm_element = ET.parse(xmlVm)
vm = vm_element.getroot()

xmlDomain = argv[1]
doc = ET.parse(xmlDomain)
root = doc.getroot()

changed = 0

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)


one_px = os.getenv('ONE_PX', 'one')
os_attr = {}
loader_attr = {}
nvram_attr = {}

t_os_e = vm.find('.//USER_TEMPLATE/T_OS')
if t_os_e is not None:
    os_attr = get_attributes(t_os_e.text)

os_e = root.find('./os')
if os_e is None:
    os_e = ET.SubElement(root, 'os', os_attr)

os_loader_e = vm.find('.//USER_TEMPLATE/T_OS_LOADER')
if os_loader_e is not None:
    arr = os_loader_e.text.split(':')
    loader_file = arr[0]
    if len(arr) > 1:
        loader_attr = get_attributes(arr[1])

    loader_e = os_e.find('./loader')
    if loader_e is not None:
        os_e.remove(loader_e)
    loader_e = ET.SubElement(os_e, 'loader', loader_attr)
    loader_e.text = '{}'.format(loader_file)
    changed = 1

os_nvram_e = vm.find('.//USER_TEMPLATE/T_OS_NVRAM')
if os_nvram_e is not None:
    arr = os_nvram_e.text.split(':')
    nvram_file = arr[0]
    if len(arr) > 1:
        nvram_attr = get_attributes(arr[1])

    if nvram_file == 'storpool':
        nvram_attr = {}

    if 'template' in nvram_attr:
        # expand relative path
        if len(nvram_attr['template'].split('/')) == 1:
            template_path = os.getenv(
                                'OVMF_PATH', '/var/tmp/one/OVMF')
            nvram_attr['template'] = '{}/{}'.format(
                                    template_path, nvram_attr['template'])

    nvram_e = os_e.find('./nvram')
    if nvram_e is not None:
        os_e.remove(nvram_e)
    nvram_e = ET.SubElement(os_e, 'nvram', nvram_attr)
    if len(nvram_file) > 0:
        if nvram_file == 'storpool':
            vm_id = vm.find('./ID').text
            nvram_e.text = '/dev/storpool/{}-sys-{}-NVRAM'.format(
                                one_px, vm_id)
            changed = 1
        else: 
            system_ds = root.find('.//one:vm/one:system_datastore', ns).text
            if nvram_file == '':
                if 'template' not in nvram_attr:
                    print('Error in <T_OS_NVRAM>: empty nvram file and missing "template" attribute', file=stderr)
                    changed = 0
                nvram_file = nvram_attr['template'].split('/')[-1]
            nvram_e.text = '{}/{}'.format(system_ds, nvram_file.split('')[-1])


if changed:
    indent(root)
    doc.write(xmlDomain)
