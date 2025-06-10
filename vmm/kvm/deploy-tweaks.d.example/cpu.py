#!/usr/bin/env python3

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

xmlVm = argv[2]
vm_element = ET.parse(xmlVm)
vm = vm_element.getroot()


xmlDomain = argv[1]
doc = ET.parse(xmlDomain)
root = doc.getroot()

changed = 0

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)


try:
    memory = int(root.find('./memory').text)
except Exception as e:
    print('Cant get memory info from domain XML "{0}"'.format(e), file=stderr)
    exit(1)

cpu_alt_numa = os.getenv('T_CPU_ALT_NUMA', None)
t_cpu_alt_numa = vm.find('.//USER_TEMPLATE/T_CPU_ALT_NUMA')
if t_cpu_alt_numa is not None:
    cpu_alt_numa = t_cpu_alt_numa.text

yes_list = ['1', 'y', 'yes', 'on', 'enable', 'enabled']
if cpu_alt_numa is not None and cpu_alt_numa.lower() in yes_list:
    cpu_alt_numa = True
else:
    cpu_alt_numa = False

vcpu_element = root.find('./vcpu')
if vcpu_element is None:
    vcpu_element = ET.SubElement(root, 'vcpu')
    vcpu_element.text = '1'
vcpu = int(vcpu_element.text)

vcpu_current = int(vcpu_element.text)
if vcpu_element.get('current') is not None:
    vcpu_current = int(vcpu_element.attrib['current'])

cpu_element = root.find('./cpu')
if cpu_element is None:
    cpu_element = ET.SubElement(root, 'cpu')

threads = int(os.getenv('T_CPU_THREADS', 1))
vm_cpu_threads = vm.find('.//USER_TEMPLATE/T_CPU_THREADS')
if vm_cpu_threads is not None:
    try:
        threads = int(vm_cpu_threads.text)
        if threads < 1:
            threads = 1
    except Exception as e:
        print("USER_TEMPLATE/T_CPU_THREADS is '{0}' Error:{1}".format(
                                        vm_cpu_threads.text, e), file=stderr)
        exit(1)

sockets = int(os.getenv('T_CPU_SOCKETS', 0))
vm_cpu_sockets = vm.find('.//USER_TEMPLATE/T_CPU_SOCKETS')
if vm_cpu_sockets is not None:
    try:
        sockets = int(vm_cpu_sockets.text)
    except Exception as e:
        print("USER_TEMPLATE/CPU_SOCKETS is '{0}' Error:{1}".format(
                                        vm_cpu_sockets.text,e),file=stderr)

if sockets > 0:
    socket_cpu_threads = int(vcpu / sockets)
    socket_cores = int(socket_cpu_threads / threads)

    topology_element = cpu_element.find('./topology')
    if topology_element is not None:
        cpu_element.remove(topology_element)
    topology_element = ET.SubElement(cpu_element, 'topology', {
            'sockets' : '{0}'.format(sockets),
              'cores' : '{0}'.format(socket_cores),
            'threads' : '{0}'.format(threads),
        })

    changed = 1
    numa_element = cpu_element.find('./numa')
    if numa_element is not None:
        cpu_element.remove(numa_element)
    numa_element = ET.SubElement(cpu_element, 'numa')
    cpumap = {}
    vcpus_element = ET.SubElement(root, 'vcpus')
    scount=0
    vcpu_enabled = 'yes'
    vcpu_hotpluggable = 'no'
    for idx in range(vcpu):
        if idx >= vcpu_current:
            vcpu_enabled = 'no'
        vcpu_sub_element = ET.SubElement(vcpus_element, 'vcpu', {
            'id' : str(idx),
            'enabled' : vcpu_enabled,
            'hotpluggable' : vcpu_hotpluggable
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
        cpus = '{0}-{1}'.format(cpuStart, cpuEnd)
        if cpu_alt_numa and threads == 1 and cpumap[idx]:
            cpus = ','.join(cpumap[idx])
        cell = ET.SubElement(numa_element, 'cell', {
                'id' : '{0}'.format(idx),
              'cpus' : '{0}'.format(cpus),
            'memory' : '{0}'.format(cpuMem),
            })

cpu_features = os.getenv('T_CPU_FEATURES', None)
vm_cpu_features = vm.find('.//USER_TEMPLATE/T_CPU_FEATURES')
if vm_cpu_features is not None:
    cpu_features = vm_cpu_features.text
if cpu_features is not None:
    for feature in cpu_features.split(','):
        arr = feature.split(':')
        name = arr[0]
        feature_element = cpu_element.find("./feature[@name='{}']".format(name))
        if feature_element is not None:
            cpu_element.remove(feature_element)
        feature_element = ET.SubElement(cpu_element, 'feature' , {
                'name' : name
            })
        if len(arr) > 1:
            if arr[1] in ['force', 'require', 'optional', 'disable', 'forbid']:
                feature_element.set('policy', arr[1])
        changed = 1

cpu_model = os.getenv('T_CPU_MODEL', None)
vm_cpu_model = vm.find('.//USER_TEMPLATE/T_CPU_MODEL')
if vm_cpu_model is not None:
    cpu_model = vm_cpu_model.text
if cpu_model is not None:
    model_element = cpu_element.find('./model')
    if cpu_model.lower() == 'delete':
        # T_CPU_MODEL=delete
        if model_element is not None:
            cpu_element.remove(model_element)
            changed = 1
    else:
        # T_CPU_MODEL=model:fallback
        model_split = cpu_model.split(':')
        model = model_split[0]
        fallback = None
        if model_element is None:
            model_element = ET.SubElement(cpu_element, 'model')
        model_element.text = model
        if len(model_split) > 1:
            fallback = model_split[1]
        if fallback is not None:
            model_element.set('fallback', fallback)
        else:
            if model_element.get('fallback') is not None:
                del model_element.atrrib['fallback']
        changed = 1

cpu_vendor = os.getenv('T_CPU_VENDOR', None)
vm_cpu_vendor = vm.find('.//USER_TEMPLATE/T_CPU_VENDOR')
if vm_cpu_vendor is not None:
    cpu_vendor = vm_cpu_vendor.text
if cpu_vendor is not None:
    model_element = cpu_element.find('./model')
    if model_element is not None:
        vendor_element = cpu_element.find('.//vendor')
        if vendor_element is None:
            vendor_element = ET.SubElement(cpu_element, 'vendor')
        vendor_element.text = cpu_vendor
        changed = 1

cpu_check = os.getenv('T_CPU_CHECK', None)
vm_cpu_check = vm.find('.//USER_TEMPLATE/T_CPU_CHECK')
if vm_cpu_check is not None:
    cpu_check = vm_cpu_check.text
if cpu_check is not None:
    if cpu_check.lower() == 'delete':
        if cpu_element.get('check') is not None:
            del cpu_element.attrib['check']
            changed = 1
    else:
        if cpu_check in ['none', 'partial', 'full']:
            cpu_element.set('check', cpu_check)
            changed = 1

cpu_match = os.getenv('T_CPU_MATCH', None)
vm_cpu_match = vm.find('.//USER_TEMPLATE/T_CPU_MATCH')
if vm_cpu_match is not None:
    cpu_match = vm_cpu_match.text
if cpu_match is not None:
    if cpu_match.lower() == 'delete':
        if cpu_element.get('match') is not None:
            del cpu_element.attrib['match']
            changed = 1
    else:
        if cpu_match in ['minimum', 'exact', 'strict']:
            cpu_element.set('match', cpu_match)
            changed = 1

cpu_mode = os.getenv('T_CPU_MODE', None)
vm_cpu_mode = vm.find('.//USER_TEMPLATE/T_CPU_MODE')
if vm_cpu_mode is not None:
    cpu_mode = vm_cpu_mode.text
if cpu_mode is not None:
    if cpu_mode.lower() == 'delete':
        if cpu_element.get('mode') is not None:
            del cpu_element.attrib['mode']
            changed = 1
    else:
        if cpu_match in ['custom', 'host-model', 'host-passthrough']:
            cpu_element.set('mode', cpu_mode)
            changed = 1

if changed:
    indent(root)
    doc.write(xmlDomain)
