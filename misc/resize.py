#!/usr/bin/env python2
#
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

from sys import exit

try:
  from lxml import etree
  #print("running with lxml.etree")
except ImportError:
  try:
    # Python 2.5
    import xml.etree.cElementTree as etree
    #print("running with cElementTree on Python 2.5+")
  except ImportError:
    try:
      # Python 2.5
      import xml.etree.ElementTree as etree
      #print("running with ElementTree on Python 2.5+")
    except ImportError:
      try:
        # normal cElementTree install
        import cElementTree as etree
        #print("running with cElementTree")
      except ImportError:
        try:
          # normal ElementTree install
          import elementtree.ElementTree as etree
          #print("running with ElementTree")
        except ImportError:
          print("Failed to import ElementTree from any known place")


def getEle(etp, name):
  for e in etp.findall(name):
    #print "getEle({0}):{1}".format(name,e.text)
    return e

import argparse
parser = argparse.ArgumentParser
parser.add_argument("vmId", help="VM's ID")
parser.add_argument("diskId", help="VM's disk ID")
parser.add_argument("diskSize", help="New size in MiB")
parser.add_argument("dbConn", help="Database connection method details")

args = parser.parse_args

print "VM:{0} DISK:{1} SIZE:{2} DB:{3}".format(args.vmId,args.diskId,args.diskSize,args.dbConn)

dbConn = args.dbConn.split(":")
if dbConn[0] == 'sqlite3':
  import sqlite3
  dbSELECT = "SELECT * FROM ? WHERE oid=?"
  dbUpdate = "UPDATE ? SET body=? WHERE oid=?"
  db = sqlite3.connect(dbConn[1])
elif dbConn[0] == 'mysql':
  import mysql.connector
  dbSELECT = "SELECT * FROM %s WHERE oid = %s"
  dbUpdate = "UPDATE %s SET body = %s WHERE oid = %s"
  dbconf = {
     'user': dbConn[1] or 'oneadmin',
     'password': dbConn[2] or '',
     'host': dbConn[3] or '127.0.0.1',
     'database': dbConn[4] or 'opennebula',
     'raise_on_warnings': True,
  }
  db = mysql.connector.connect(**dbconf)
else:
  print("Uknown connection type {0}".format(conn[0]))
  exit(1)


dbc = db.cursor()

dbc.execute(dbSELECT, ('vm_pool',args.vmId,))

res = dbc.fetchone()

if res[2]:
  xmlBody = res[2]

et = etree.XML(xmlBody, etree.XMLParser(strip_cdata=False,remove_blank_text=True))

changed = False
persistent = None

for disk in et.findall(".//DISK"):
  disk_size_et = getEle(disk,".//SIZE")
  disk_id_et = getEle(disk,".//DISK_ID")
  disk_source_et = getEle(disk,".//SOURCE")
  disk_imageId_et = getEle(disk,".//IMAGE_ID")
  disk_clone_et = getEle(disk,".//CLONE")
  txt = "DISK_ID:{0} SOURCE:{1} SIZE:{2} IMAGE_ID:{3} CLONE:{4}".format(disk_id_et.text,disk_source_et.text,disk_size_et.text,disk_imageId_et.text,disk_clone_et.text)
  if disk_id_et.text == args.diskId:
    txt = "{0} <<< size changed to {1}".format(txt,args.diskSize)
    disk_size_et.text = etree.CDATA(args.diskSize)
    changed = True
    if disk_clone_et.text == 'NO':
      persistent = disk_imageId_et.text
  print txt

#print etree.tostring(et,pretty_print=True)
dbc.execute(dbUPDATE,('vm_pool',etree.tostring(et,pretty_print=False),args.vmId,))

if persistent:
  dbc.execute(dbSELECT,('image_pool',persistent,))
  res = dbc.fetchone()
  if res[2]:
    xmlBody = res[2]
    img_et = etree.XML(xmlBody, etree.XMLParser(strip_cdata=False,remove_blank_text=True))
    img_size_et = getEle(img_et,".//SIZE")
    print "img ID:{0} SIZE:{1} <<< size changed to {2}".format(persistent,img_size_et.text,args.diskSize)
    img_size_et.text = args.diskSize
    #print etree.tostring(eti,pretty_print=True)
    dbc.execute(dbUpdate,('image_pool',etree.tostring(img_et,pretty_print=False),persistent,))

db.commit()
db.close()
