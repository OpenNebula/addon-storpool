(*
Module: Oneserver
To parse /etc/one/*-server.conf

Note: onegate-server.conf still is not supported due to not parseable yaml

Author: Anton Todorov <a.todorov@storpool.com>
*)
module Oneserver =
  autoload xfm

(* Version: 0.1 *)

(* Group: helpers *)
let colon = Sep.colon
let space = Sep.space
let dashspace = del /-[ \t]*/ "- "
let eol = Util.eol
let el = del /\n/ "\n"
let indent = del /[ \t]+/ "  "
let value = store (Rx.word|Rx.integer|Rx.fspath)

let empty = [ label "#empty" . eol ]

let comment = [ label "#comment" . del /#[ \t]*/ "# " .  store /([^ \t\n][^\n]*)?/ . del /\n/ "\n" ]

let entry = [ colon . key Rx.word . colon . (space . value)?  . el ] 

let option = [ label "#option" . indent . dashspace . value . el ]

let lns =  (comment | empty | entry | option)*

let filter = incl "/etc/one/sunstone-server.conf"
             . incl "/etc/one/onevnc-server.conf"
             . incl "/etc/one/oneflow-server.conf"
             . incl "/etc/one/onehem-server.conf"
             (*. incl "/etc/one/onegate-server.conf"*)
             . Util.stdexcl

let xfm = transform lns filter
