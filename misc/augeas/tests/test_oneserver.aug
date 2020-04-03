(*
Module: Oneserver
To parse /etc/one/*-server.conf

(onegate-server.conf still is not supported)

Author: Anton Todorov <a.todorov@storpool.com>
*)

module Test_oneserver = 

let conf_a =":element1: value1

:element2: 127.0.0.1
# comment
:element3: /value/3
#
:element_4: http://dir.bg
#:element: 12345
:element5: 1234
"
test Oneserver.lns get conf_a = ?
test Oneserver.lns get conf_a =
  { "element1"  = "value1" }
  { "#empty" }
  { "element2"  = "127.0.0.1" }
  { "#comment"  = "comment" }
  { "element3"  = "/value/3" }
  { "#comment" = "" }
  { "element_4"  = "http://dir.bg" }
  { "#comment" = ":element: 12345" }
  { "element5"  = "1234" }


let conf_b =":element1: value1

:element2: 127.0.0.1
# comment
:element3: /value/3
#
:element_4: http://dir.bg
#:element: 12345
:element5: 1234
:root:
  - one
  - two
"
test Oneserver.lns get conf_b = ?
test Oneserver.lns get conf_b =
  { "element1" = "value1" }
  { "#empty" }
  { "element2" = "127.0.0.1" }
  { "#comment" = "comment" }
  { "element3" = "/value/3" }
  { "#comment" = "" }
  { "element_4" = "http://dir.bg" }
  { "#comment" = ":element: 12345" }
  { "element5" = "1234" }
  { "root"
    { "-"
      { "value" = "one" }
      { "value" = "two" }
    }
  }
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

