(*
Module: Oneserver
To parse /etc/one/*-server.conf

(onegate-server.conf still is not supported)

Author: Anton Todorov <a.todorov@storpool.com>
*)

module Test_oneserver = 

let conf_a =":key1: value1

:key2: 127.0.0.1
# comment spaced
:key3: /path/to/something/42
#
:key_4: http://dir.bg/url
#:key5: 12345
:key6:
:key6:
:key7: \"val7\"
"
test Oneserver.lns get conf_a = ?
test Oneserver.lns get conf_a =
  { "key1" = "value1" }
  { "#empty" }
  { "key2" = "127.0.0.1" }
  { "#comment" = "comment spaced" }
  { "key3" = "/path/to/something/42" }
  { "#comment" = "" }
  { "key_4" = "http://dir.bg/url" }
  { "#comment" = ":key5: 12345" }
  { "key6" }
  { "key6" }
  { "key7" = "\"val7\"" }


let conf_b =":key1: value1

:key2: 127.0.0.1
# comment spaced
:key3: /path/to/something/42
#
# 
:key_4: http://dir.bg/url
#:key5: 12345
:key6:
:key6:
:key7: \"kafter\"
:key8:
  - k8v1
  - k8v2
  - k8v3

"

test Oneserver.lns get conf_b = ?
test Oneserver.lns get conf_b =
  { "key1" = "value1" }
  { "#empty" }
  { "key2" = "127.0.0.1" }
  { "#comment" = "comment spaced" }
  { "key3" = "/path/to/something/42" }
  { "#comment" = "" }
  { "#comment" = "" }
  { "key_4" = "http://dir.bg/url" }
  { "#comment" = ":key5: 12345" }
  { "key6" }
  { "key6" }
  { "key7" = "\"kafter\"" }
  { "key8" }
  { "#option" = "k8v1" }
  { "#option" = "k8v2" }
  { "#option" = "k8v3" }
  { "#empty" }

let conf_c =":element1: value1

:element2: 127.0.0.1
# comment
:element3: /value/3
:element_4: http://dir.bg
#:element: 12345
:element5: 1234
:root:
  :one1:
    :two1:
  :one2:
    :two2:
"
test Oneserver.lns get conf_c = *

