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

#--------------------------------------------------------------------------- #
# xpath_mylti.py -b base64XML XPATH
#  - base64XML base64 encoded XML data
#  - XPATH path(s) to lookup elements
# Return: semicolon separated list of entries
#
# Other usage scenarios:
#  cat XMLfile | xpath_mylti.py -s XPATH
#  cat base64XMLfile | xpath_mylti.py -s -b XPATH
#--------------------------------------------------------------------------- #

from sys import argv, stdin
from base64 import b64decode
import xml.etree.ElementTree as ET
from getopt import getopt

b64 = False
stdIn = False

opts, args = getopt( argv[1:], "bs", ["--base64", "--stdin"] )

for k, v in opts:
    if k in ( "-b", "--base64" ):
        b64 = True
    elif k in ( "-s", "--stdin" ):
        stdIn = True

if stdIn:
    xmlData = stdin.read()
else:
    xmlData = args.pop( 0 )

if b64:
    xmlData = b64decode( xmlData )

eRoot = ET.fromstring( xmlData )

for arg in args:
    aList = arg.split( '/' )
    a = aList.pop()
    p = '/'.join( aList[2:] )
    out = []
    for e in eRoot.findall( ".//{0}".format( p ) ):
        eAll = e.findall( a )
        if len( eAll ) > 1:
            for entry in eAll:
                out.append( '{0}'.format( entry.text ) )
        else:
            out.append( '{0}'.format( e.findtext( a, '' ) ) )
    print ";".join( out )
