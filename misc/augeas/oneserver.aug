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
let val = store (Rx.word|Rx.integer|Rx.fspath)
let eol = Util.eol
let emptyold = Util.empty
let empty = [ label "#empty" . eol ]
let comment = [ label "#comment" . del /#[ \t]*/ "# " .  store /([^ \t\n][^\n]*)?/ . del /\n/ "\n" ]


let entry = [ colon . key Rx.word . colon . space . val . eol ]

let eol_only = del "\n" "\n"
let indent = del /[ \t]+/ "  "
let dash = del /-[ \t]*/ "- "
let indented_list_suffix = [label "-" . eol . (
                              [ label "value" . indent . dash  . val] . eol
                              )+
                           ]
(*
let indented_entry =  eol . [ 
                           label ( indent . val ) . eol. (
                                [indent . entry])+
                              ]
*)
let nested_entry = [ colon . key Rx.word . colon . (
                                indented_list_suffix
                                (* | indented_entry*)
                              )
                   ]

let lns =  (comment | empty | entry | nested_entry)*

let filter = incl "/etc/one/sunstone-server.conf"
             . incl "/etc/one/onevnc-server.conf"
             . incl "/etc/one/oneflow-server.conf"
             . incl "/etc/one/onehem-server.conf"
             (*. incl "/etc/one/onegate-server.conf"*)
             . Util.stdexcl

let xfm = transform lns filter
