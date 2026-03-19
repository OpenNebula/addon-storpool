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
"""

from typing import Optional, List, Dict
import os
import sys
from xml.etree import ElementTree as ET

ns = {
    'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
    'one': "http://opennebula.org/xmlns/libvirt/1.0",
}


def indent(elem: ET.Element, level: int = 0, ind: str = "  ") -> None:
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
vm_e: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_e.getroot()

changed: bool = False

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

memory_e: Optional[ET.Element] = root.find('./memory')
if (memory_e is not None and
        memory_e.text is not None and
        memory_e.text.isnumeric()):
    memory: int = int(memory_e.text)
else:
    print("Cant get memory info from domain XML", file=sys.stderr)
    sys.exit(1)

cpu_alt_numa: bool = False
cpu_alt_numa_str: Optional[str] = os.getenv('T_CPU_ALT_NUMA', None)  # type: ignore[attr-defined] # noqa: E501
xpath: str = './/USER_TEMPLATE/T_CPU_ALT_NUMA'
t_cpu_alt_numa: Optional[ET.Element] = vm.find(xpath)
if t_cpu_alt_numa is not None and t_cpu_alt_numa.text is not None:
    cpu_alt_numa_str = t_cpu_alt_numa.text

yes_list: List[str] = ['1', 'y', 'yes', 'on', 'enable', 'enabled']
if cpu_alt_numa_str is not None and cpu_alt_numa_str.lower() in yes_list:
    cpu_alt_numa = True

vcpu_e: Optional[ET.Element] = root.find('./vcpu')
if vcpu_e is None:
    vcpu_e = ET.SubElement(root, 'vcpu')
    vcpu_e.text = '1'
vcpu: int = int(vcpu_e.text or '1')

vcpu_current: int = int(vcpu_e.text or '0')
if vcpu_e.get('current') is not None:
    vcpu_current = int(vcpu_e.attrib['current'])

cpu_e: Optional[ET.Element] = root.find('./cpu')
if cpu_e is None:
    cpu_e = ET.SubElement(root, 'cpu')

threads: int = int(os.getenv('T_CPU_THREADS', 1))  # type: ignore[attr-defined]
xpath = './/USER_TEMPLATE/T_CPU_THREADS'
vm_cpu_threads_e: Optional[ET.Element] = vm.find(xpath)
if (vm_cpu_threads_e is not None and
        vm_cpu_threads_e.text is not None and
        vm_cpu_threads_e.text.isnumeric()):
    threads = int(vm_cpu_threads_e.text)
if threads < 1:
    threads = 1

sockets: int = int(os.getenv('T_CPU_SOCKETS', 0))  # type: ignore[attr-defined]
xpath = './/USER_TEMPLATE/T_CPU_SOCKETS'
vm_cpu_sockets_e: Optional[ET.Element] = vm.find(xpath)
if (vm_cpu_sockets_e is not None and
        vm_cpu_sockets_e.text is not None and
        vm_cpu_sockets_e.text.isnumeric()):
    sockets = int(vm_cpu_sockets_e.text)

if sockets > 0:
    socket_cpu_threads = int(vcpu / sockets)
    socket_cores = int(socket_cpu_threads / threads)

    topology_e_r: Optional[ET.Element] = cpu_e.find('./topology')
    if topology_e_r is not None:
        cpu_e.remove(topology_e_r)
    topology_e: ET.Element = ET.SubElement(cpu_e, 'topology', {
            'sockets': '{0}'.format(sockets),
            'cores': '{0}'.format(socket_cores),
            'threads': '{0}'.format(threads),
        })
    changed = True

    numa_e_r: Optional[ET.Element] = cpu_e.find('./numa')
    if numa_e_r is not None:
        cpu_e.remove(numa_e_r)
    numa_e: ET.Element = ET.SubElement(cpu_e, 'numa')

    cpumap: Dict[int, List[str]] = {}
    vcpus_e: ET.Element = ET.SubElement(root, 'vcpus')
    scount: int = 0
    vcpu_enabled: str = 'yes'
    vcpu_hotpluggable: str = 'no'
    for idx in range(vcpu):
        if idx >= vcpu_current:
            vcpu_enabled = 'no'
        vcpu_sub_e: ET.Element = ET.SubElement(vcpus_e, 'vcpu', {
            'id': str(idx),
            'enabled': vcpu_enabled,
            'hotpluggable': vcpu_hotpluggable,
            })
        vcpu_hotpluggable = 'yes'
        if scount not in cpumap:
            cpumap[scount] = []
        cpumap[scount].append(str(idx))
        scount = (scount + 1) % sockets
    for idx in range(sockets):
        cpuStart = socket_cpu_threads * idx
        cpuEnd = (socket_cpu_threads * (idx + 1)) - 1
        cpuMem = int(memory / sockets)
        cpus = f"{cpuStart}-{cpuEnd}"
        if cpu_alt_numa and threads == 1 and cpumap[idx]:
            cpus = ','.join(cpumap[idx])
        cell_e: ET.Element = ET.SubElement(numa_e, 'cell', {
            'id': f"{idx}",
            'cpus': f"{cpus}",
            'memory': f"{cpuMem}",
            })

# cpu/feature[@policy]
cpu_features: Optional[str] = os.getenv('T_CPU_FEATURES', None)  # type: ignore[attr-defined] # noqa: E501
xpath = './/USER_TEMPLATE/T_CPU_FEATURES'
vm_cpu_features_e: Optional[ET.Element] = vm.find(xpath)  # noqa: E501
if vm_cpu_features_e is not None and vm_cpu_features_e.text is not None:
    cpu_features = vm_cpu_features_e.text
if cpu_features is not None:
    for feature in cpu_features.split(','):
        arr = feature.split(':')
        name = arr[0]
        feature_e_r: Optional[ET.Element] = cpu_e.find(
            f"./feature[@name='{name}']")
        if feature_e_r is not None:
            cpu_e.remove(feature_e_r)
        feature_e: ET.Element = ET.SubElement(cpu_e, 'feature', {
                'name': name,
            })
        if len(arr) > 1:
            if arr[1] in ['force', 'require', 'optional', 'disable', 'forbid']:
                feature_e.set('policy', arr[1])
        changed = True

cpu_model: Optional[str] = os.getenv('T_CPU_MODEL', None)  # type: ignore[attr-defined] # noqa: E501
xpath = './/USER_TEMPLATE/T_CPU_MODEL'
vm_cpu_model_e: Optional[ET.Element] = vm.find(xpath)
if vm_cpu_model_e is not None and vm_cpu_model_e.text is not None:
    cpu_model = vm_cpu_model_e.text
if cpu_model is not None:
    model_e: Optional[ET.Element] = cpu_e.find('./model')
    if cpu_model.lower() == 'delete':
        # T_CPU_MODEL=delete
        if model_e is not None:
            cpu_e.remove(model_e)
            changed = True
    else:
        # T_CPU_MODEL=model:fallback
        model_split = cpu_model.split(':')
        model = model_split[0]
        fallback = None
        if model_e is None:
            model_e = ET.SubElement(cpu_e, 'model')
        model_e.text = model
        if len(model_split) > 1:
            fallback = model_split[1]
        if fallback is not None:
            model_e.set('fallback', fallback)
        else:
            if model_e.get('fallback') is not None:
                del model_e.attrib['fallback']
        changed = True

cpu_vendor: Optional[str] = os.getenv('T_CPU_VENDOR', None)  # type: ignore[attr-defined] # noqa: E501
xpath = './/USER_TEMPLATE/T_CPU_VENDOR'
vm_cpu_vendor: Optional[ET.Element] = vm.find(xpath)
if vm_cpu_vendor is not None and vm_cpu_vendor.text is not None:
    cpu_vendor = vm_cpu_vendor.text
if cpu_vendor is not None:
    model_e = cpu_e.find('./model')
    if model_e is not None:
        vendor_e = cpu_e.find('.//vendor')
        if vendor_e is None:
            vendor_e = ET.SubElement(cpu_e, 'vendor')
        vendor_e.text = cpu_vendor
        changed = True

cpu_check: Optional[str] = os.getenv('T_CPU_CHECK', None)  # type: ignore[attr-defined] # noqa: E501
xpath = './/USER_TEMPLATE/T_CPU_CHECK'
vm_cpu_check: Optional[ET.Element] = vm.find(xpath)
if vm_cpu_check is not None and vm_cpu_check.text is not None:
    cpu_check = vm_cpu_check.text
if cpu_check is not None:
    if cpu_check.lower() == 'delete':
        if cpu_e.get('check') is not None:
            del cpu_e.attrib['check']
            changed = True
    else:
        if cpu_check in ['none', 'partial', 'full']:
            cpu_e.set('check', cpu_check)
            changed = True

cpu_match: Optional[str] = os.getenv('T_CPU_MATCH', None)  # type: ignore[attr-defined] # noqa: E501
xpath = './/USER_TEMPLATE/T_CPU_MATCH'
vm_cpu_match_e: Optional[ET.Element] = vm.find(xpath)
if vm_cpu_match_e is not None and vm_cpu_match_e.text is not None:
    cpu_match = vm_cpu_match_e.text
if cpu_match is not None:
    if cpu_match.lower() == 'delete':
        if cpu_e.get('match') is not None:
            del cpu_e.attrib['match']
            changed = True
    else:
        if cpu_match in ['minimum', 'exact', 'strict']:
            cpu_e.set('match', cpu_match)
            changed = True

cpu_mode: Optional[str] = os.getenv('T_CPU_MODE', None)  # type: ignore[attr-defined] # noqa: E501
xpath = './/USER_TEMPLATE/T_CPU_MODE'
t_cpu_mode_e: Optional[ET.Element] = vm.find(xpath)
if t_cpu_mode_e is not None and t_cpu_mode_e.text is not None:
    cpu_mode = t_cpu_mode_e.text
if cpu_mode is not None:
    if cpu_mode.lower() == 'delete':
        if cpu_e.get('mode') is not None:
            del cpu_e.attrib['mode']
            changed = True
    else:
        if cpu_match in ['custom', 'host-model', 'host-passthrough']:
            cpu_e.set('mode', cpu_mode)
            changed = True

if changed:
    indent(root)
    doc.write(xmlDomain)
