#!/usr/bin/env python

# -------------------------------------------------------------------------- #
# Copyright 2015, StorPool (storpool.com)                                    #
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

# vmTweakVirtioBlkDataPlane.py <XMLfile>


from sys import argv

try:
    import lxml.etree as ET
except ImportError:
    raise RuntimeError("lxml Python module not found! Install from distribution package ot pip install lxml")


xmlFile = argv[1]

et = ET.parse(xmlFile, ET.XMLParser(strip_cdata=False,remove_blank_text=True))

qemu_namespace = "{{http://libvirt.org/schemas/domain/qemu/1.0}}{0}"
xtra = ["device.virtio-disk{0}.scsi=off","device.virtio-disk{0}.x-data-plane=on"]
xtra.append("device.virtio-disk{0}.config-wce=off")

# ugly but working
domain = et.getroot()[0].getparent()

disks = et.findall(".//disk")
did = 0
for disk in disks:
	if disk.get('device') == 'disk':
		if disk.get('type') == 'block':
			#<disk><target/>
			target = disk.findall(".//target")
			for e in target:
				if e.get('dev')[0:2] == 'vd':
					#<target dev="vda" bus="virtio"/>
					e.set("bus","virtio")
			#<disk><driver/>
			drv = disk.findall(".//driver")
			for e in drv:
				if e.get('type') == 'raw' and e.get("name") == 'qemu':
					# Enable native IO
					e.set("io","native")
					# Disable cache
					e.set("cache","none")
#					e.set("discard","unmap")

					# Enable virtio_blk data plane...
					#<qemu:commandline>
					# <qemu:arg value='-set'/>
					# <qemu:arg value='device.virtio-disk0.scsi=off'/>
					#</qemu:commandline>
					#<qemu:commandline>
					# <qemu:arg value='-set'/>
					# <qemu:arg value='device.virtio-disk0.x-data-plane=on'/>
					#</qemu:commandline>
					#<qemu:commandline>
					# <qemu:arg value='-set'/>
					# <qemu:arg value='device.virtio-disk0.config-wce=off'/>
					#</qemu:commandline>
					for v in xtra:
						cmdLine = ET.Element(qemu_namespace.format("commandline"))
						child = ET.Element(qemu_namespace.format("arg"))
						child.set("value","-set")
						cmdLine.append(child)
						child = ET.Element(qemu_namespace.format("arg"))
						child.set("value",v.format(did))
						cmdLine.append(child)
						domain.append(cmdLine)
		did += 1

et.write(xmlFile,pretty_print=True)
