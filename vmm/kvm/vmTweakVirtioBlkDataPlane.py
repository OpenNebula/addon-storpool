#!/usr/bin/env python

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

# vmTweakVirtioBlkDataPlane.py <XMLfile>

from sys import argv
import syslog

dbg = 1

if dbg:
	syslog.openlog('vmTweakVirtioBlkDataPlane.py', syslog.LOG_PID)

try:
	import lxml.etree as ET
except ImportError:
	raise RuntimeError("lxml Python module not found! Install from distribution package or pip install lxml")

xmlFile = argv[1]

et = ET.parse(xmlFile, ET.XMLParser(strip_cdata=False,remove_blank_text=True))

# ugly but working
domain = et.getroot()[0].getparent()

vm_name = et.find(".//name").text

qemu_namespace = "{{http://libvirt.org/schemas/domain/qemu/1.0}}{0}"
qemu_args = ["device.virtio-disk{0}.scsi=off","device.virtio-disk{0}.x-data-plane=on"]
qemu_args.append("device.virtio-disk{0}.config-wce=off")

diskId = 0
for disk in et.findall(".//disk"):
	if disk.get('device') == 'disk':
		if disk.get('type') == 'block':
			#<disk><target/>
			target_dev = ''
			for e in disk.findall(".//target"):
				target_dev = e.get('dev')
				if target_dev[0:2] == 'vd':
					#<target dev="vda" bus="virtio"/>
					e.set("bus","virtio")
			if target_dev[0:2] != 'vd':
				if dbg:
					syslog.syslog(syslog.LOG_INFO, "VM {0} not virtio-blk {1} (diskId:{2})".format(vm_name,target_dev,diskId))
				continue
			#<disk><driver/>
			for e in disk.findall(".//driver"):
				if e.get('type') == 'raw' and e.get("name") == 'qemu':
					if dbg:
						syslog.syslog(syslog.LOG_INFO, "VM {0} enabling virtio-blk-data-plane on {1} (diskId:{2})".format(vm_name,target_dev,diskId))
					# Enable native IO
					e.set("io","native")
					# Disable cache
					e.set("cache","none")
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
					for value in qemu_args:
						cmdLine = ET.Element(qemu_namespace.format("commandline"))
						child = ET.Element(qemu_namespace.format("arg"))
						child.set("value","-set")
						cmdLine.append(child)
						child = ET.Element(qemu_namespace.format("arg"))
						child.set("value",value.format(diskId))
						cmdLine.append(child)
						domain.append(cmdLine)
					diskId += 1

et.write(xmlFile,pretty_print=True)
