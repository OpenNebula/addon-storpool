#!/usr/bin/env python2
#
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
#
from __future__ import print_function

import sys
import os
from xml.etree.ElementTree import ElementTree
from xml.etree import ElementTree as ET

ns = {'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
       'one': "http://opennebula.org/xmlns/libvirt/1.0"
     }

if len(sys.argv) <= 2 or sys.argv[2] != "migrate":
    sys.exit(0)

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

tree = ET.parse(sys.stdin)
root = tree.getroot()

for disk in root.findall('.//disk'):
    try:
        source = disk.find('./source')
        if 'file' in source.attrib:
            diskPath = os.path.realpath(source.attrib['file'])
        elif 'dev' in source.attrib:
            diskPath = os.path.realpath(source.attrib['dev'])
        else:
            diskPath = None
        if diskPath and diskPath[0:8] == '/dev/sp-':
            driver = disk.find('./driver')
            driver.attrib['cache'] = 'none'
            driver.attrib['io'] = 'native'
    except Exception as e:
        print("Error: {e}".format(e=e), file=stderr)

tree.write(sys.stdout)

sys.stdout.flush()
