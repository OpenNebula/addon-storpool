#!/usr/bin/env python

# -------------------------------------------------------------------------- #
# Copyright 2015-2019, StorPool (storpool.com)                               #
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
from sys import argv, exit, stderr
from xml.etree import ElementTree as ET

ns = {'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
       'one': "http://opennebula.org/xmlns/libvirt/1.0"
     }

def indent(elem, level=0):
    i = "\n" + level*"\t"
    if elem is not None:
#        if not elem.text or not elem.text.strip():
#            elem.text = i + "\t"
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
        for elem in elem:
            indent(elem, level+1)
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
    else:
        if level and (not elem.tail or not elem.tail.strip()):
            elem.tail = i

xmlVm = argv[2]
vm_element = ET.parse(xmlVm)
vm = vm_element.getroot()


xmlDomain = argv[1]
doc = ET.parse(xmlDomain)
root = doc.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)


try:
    memory = int(root.find('./memory').text)
except Exception as e:
    print('Cant get memory info from domain XML "{0}"'.format(e), file=stderr)
    exit(1)


vcpu_element = root.find('./vcpu')
if vcpu_element is None:
    vcpu_element = ET.SubElement(root, 'vcpu')
    vcpu_element.text = '1'
vcpu = int(vcpu_element.text)

#if vcpu%2 > 0:
#    print("VCPU % 2 = {v} != 0".format(v=vcpu%2), file=stderr)
#    exit(1)

cpu = root.find('./cpu')
if cpu is None:
    cpu = ET.SubElement(root, 'cpu', {
            'mode' : 'host-passthrough',
        })

threads = 1
cpu_threads = vm.find('.//USER_TEMPLATE/CPU_THREADS')
if cpu_threads is not None:
    try:
        threads = int(cpu_threads.text)
        if threads < 1:
            threads = 1
    except Exception as e:
        print("USER_TEMPLATE/CPU_THREADS is '{0}' Error:{1}".format(cpu_threads.text,e))
        exit(1)

sockets = 0
cpu_sockets = vm.find('.//USER_TEMPLATE/CPU_SOCKETS')
if cpu_sockets is not None:
    try:
        sockets = int(cpu_sockets.text)
    except Exception as e:
        print("USER_TEMPLATE/CPU_SOCKETS is '{0}' Error:{1}".format(cpu_sockets.text,e),file=stderr)

if sockets > 0:
    socket_cpu_threads = int(vcpu / sockets)
    socket_cores = int(socket_cpu_threads / threads)

    topology = ET.SubElement(cpu, 'topology', {
            'sockets' : '{0}'.format(sockets),
              'cores' : '{0}'.format(socket_cores),
            'threads' : '{0}'.format(threads),
        })

    numa = ET.SubElement(cpu, 'numa')
    for i in range(sockets):
        cpuStart = socket_cpu_threads * i
        cpuEnd = (socket_cpu_threads * (i+1)) -1
        cpuMem = memory / sockets
        cell = ET.SubElement(numa, 'cell', {
                'id' : '{0}'.format(i),
              'cpus' : '{0}-{1}'.format(cpuStart, cpuEnd),
            'memory' : '{0}'.format(cpuMem),
            })

cpu_features = vm.find('.//USER_TEMPLATE/CPU_FEATURES')
if cpu_features is not None:
    features = cpu_features.text
    for f in features.split(','):
        arr = f.split(':')
        policy = 'optional'
        name = arr[0]
        if len(arr) > 1:
            policy = arr[1]
        feature = ET.SubElement(cpu, 'feature' , {
                'policy' : policy,
                'name' : name
            })

cpu_model = vm.find('.//USER_TEMPLATE/CPU_MODEL')
if cpu_model is not None:
    model = cpu.find('./model')
    if cpu_model.text is not None:
        m = cpu_model.text.split(':')
        cpu_model = m[0]
        fallback = None
        if len(m) > 1:
            fallback = m[1]
        if model is None:
            model = ET.SubElement(cpu, 'model')
        if fallback is not None:
            model.set('fallback', fallback)
        if cpu_model:
            model.text = cpu_model
        else:
            model.text = ''
    else:
        cpu.remove(model)

cpu_vendor = vm.find('.//USER_TEMPLATE/CPU_VENDOR')
if cpu_vendor is not None:
    vendor = cpu.find('.//vendor')
    if vendor is None:
        vendor = ET.SubElement(cpu, 'vendor')
    vendor.text = cpu_vendor.text

cpu_check = vm.find('.//USER_TEMPLATE/CPU_CHECK')
if cpu_check is not None:
    check = cpu_check.text
    if check in [ '', None ]:
        if cpu.get('check') is not None:
            del cpu.attrib['check']
    else:
        cpu.set('check', check)

cpu_match = vm.find('.//USER_TEMPLATE/CPU_MATCH')
if cpu_match is not None:
    match = cpu_match.text
    if match in [ '', None ]:
        if cpu.get('match') is not None:
            del cpu.attrib['match']
    else:
        cpu.set('match', match)

cpu_mode = vm.find('.//USER_TEMPLATE/CPU_MODE')
if cpu_mode is not None:
    mode = cpu_mode.text
    if mode in [ '', None]:
        if cpu.get('match') is not None:
            del cpu.attrib['mode']
    else:
        cpu.set('mode', mode)

indent(root)
doc.write(xmlDomain)
