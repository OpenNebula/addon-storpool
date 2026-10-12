#!/usr/bin/env python3
# -------------------------------------------------------------------------- #
# Copyright 2015-2026, StorPool (storpool.com)                               #
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
# -------------------------------------------------------------------------- #
"""XML query and edit tool for the addon shell drivers.

One command replaces OpenNebula's xpath.rb, the addon's xpath-sp.rb and
xpath_multi.py, xmlstarlet and xmllint. Every subcommand reads the document
from stdin unless -f FILE is given; -b decodes base64 input first.

  get  XPATH...        xpath.rb: one NUL-terminated value per XPath, the first
                       text node of the first match; a %m% prefix joins the
                       text of every match with a space; -t prints the matched
                       subtree instead; exit 1 when a path has no match
  list XPATH...        xpath_multi.py: one line per XPath, the values of the
                       last step under every match of the preceding steps,
                       joined with -S (default ';'), '' for a missing child
  sel  -t TEMPLATE     xmlstarlet sel: -m XPATH iterates the matches, -v XPATH
                       prints a string value, -c XPATH copies nodes, -o TEXT
                       prints text, -n a newline; -N prefix=uri names a
                       namespace; exit 1 when -m matched nothing
  ed   -u XPATH -v VALUE | -d XPATH ...
                       xmlstarlet ed: update the text of, or delete, every
                       match, then print the document
  sub  XPATH           xmllint --xpath: print the matched nodes; exit 1 on an
                       empty result
  fo                   xmllint --format: pretty print
  val                  xmllint --noout: exit 1 when the input is not XML

Runs under lxml. Without lxml it re-executes itself with the StorPool Python
and, failing that, serves the simple expressions with ElementTree.
"""

# pylint: disable=unexpected-keyword-arg,no-member,c-extension-no-member

from __future__ import print_function

import argparse
import base64
import os
import re
import sys

SP_PYTHON = "/opt/storpool/python3/bin/python3"
REEXEC_GUARD = "SPXML_REEXEC"

NUMERIC_PREDICATE = re.compile(r"\[((?:[\w.-]+/)*[\w.-]+)=([^'\"\]]+)\]")


class SpxmlError(Exception):
    """A usage or document error reported on stderr with exit code 1."""


def load_engine():
    """Return (name, module) for lxml, or ElementTree after trying the StorPool Python."""
    wanted = os.environ.get("SPXML_ENGINE", "")
    if wanted != "etree":
        try:
            from lxml import etree  # pylint: disable=import-outside-toplevel

            return "lxml", etree
        except ImportError:
            if wanted == "lxml":
                raise
        if (
            os.path.exists(SP_PYTHON)
            and os.environ.get(REEXEC_GUARD) != "1"
            and os.path.realpath(sys.executable) != os.path.realpath(SP_PYTHON)
        ):
            os.environ[REEXEC_GUARD] = "1"
            os.execv(SP_PYTHON, [SP_PYTHON, os.path.abspath(__file__)] + sys.argv[1:])
    import xml.etree.ElementTree as etree  # pylint: disable=import-outside-toplevel

    return "etree", etree


ENGINE, ET = load_engine()


# ---------------------------------------------------------------------------
# document access shared by the subcommands
# ---------------------------------------------------------------------------


def read_input(args):
    """The document bytes from -f FILE or stdin, base64 decoded with -b."""
    if getattr(args, "file", None):
        with open(args.file, "rb") as handle:
            data = handle.read()
    else:
        data = sys.stdin.buffer.read()
    if getattr(args, "base64", False):
        data = base64.b64decode(b"".join(data.split()))
    return data


def parse(data):
    """The root element of the document, or SpxmlError."""
    try:
        if ENGINE == "lxml":
            return ET.fromstring(data, ET.XMLParser(remove_blank_text=False))
        return ET.fromstring(data)
    except Exception as exc:  # pylint: disable=broad-except
        raise SpxmlError("not an XML document: {0}".format(exc)) from exc


def namespaces(args):
    """The -N prefix=uri options as a dict."""
    nsmap = {}
    for item in getattr(args, "namespace", None) or []:
        if "=" not in item:
            raise SpxmlError("bad namespace '{0}', expected prefix=uri".format(item))
        prefix, uri = item.split("=", 1)
        nsmap[prefix] = uri
    return nsmap


def is_element(node):
    """True for an element node, False for strings and numbers."""
    return hasattr(node, "tag") and not isinstance(node, str)


def first_text(node):
    """The first text node of an element, '' when empty."""
    if is_element(node):
        return node.text or ""
    return "" if node is None else str(node)


def string_value(node):
    """The XPath string value: all descendant text of an element."""
    if is_element(node):
        return "".join(node.itertext())
    return "" if node is None else str(node)


def serialize(node):
    """The node as XML text without its tail, or the string result itself."""
    if not is_element(node):
        return "" if node is None else str(node)
    if ENGINE == "lxml":
        return ET.tostring(node, encoding="unicode", with_tail=False)
    tail = node.tail
    node.tail = None
    try:
        return ET.tostring(node, encoding="unicode")
    finally:
        node.tail = tail


# ---------------------------------------------------------------------------
# XPath evaluation
# ---------------------------------------------------------------------------


DOCUMENT = "document"


def _etree_normalize(root, context, expr):
    """Rewrite an XPath into the ElementTree subset; return (path, attr, want_text)."""
    if context is DOCUMENT:
        context = root
        if not expr.startswith("/") and not expr.startswith("."):
            expr = "/" + expr
    want_text = False
    attr = None
    if expr.endswith("/text()"):
        want_text = True
        expr = expr[: -len("/text()")]
    tail = expr.rsplit("/", 1)[-1]
    if tail.startswith("@") and tail[1:].isidentifier():
        attr = tail[1:]
        expr = expr[: -(len(tail) + 1)] or "."
    if " and " in expr or " or " in expr:
        raise SpxmlError("'{0}' needs lxml: boolean predicates".format(expr))
    if re.search(r"\[[^\]]*/[^\]]*\]", expr):
        raise SpxmlError("'{0}' needs lxml: nested path predicates".format(expr))
    expr = NUMERIC_PREDICATE.sub(lambda m: "[{0}='{1}']".format(m.group(1), m.group(2).strip()), expr)
    if expr.startswith("//"):
        expr = "." + expr
    elif expr.startswith("/"):
        head, _, rest = expr[1:].partition("/")
        head_tag = head.split("[", 1)[0]
        if context is not root or head_tag != root.tag:
            return None, attr, want_text
        if "[" in head:
            # a predicate on the root element: keep it only when the root satisfies it
            probe = ET.Element("probe")
            probe.append(root)
            if not probe.findall("./" + head):
                return None, attr, want_text
        expr = "." if not rest else "./" + rest
    return expr, attr, want_text


def evaluate(root, context, expr, nsmap):
    """The XPath result as a list of nodes or strings, in document order."""
    if ENGINE == "lxml":
        try:
            if context is DOCUMENT:
                if not expr.startswith("/") and not expr.startswith("."):
                    expr = "/" + expr
                result = root.xpath(expr, namespaces=nsmap or None)
            else:
                result = context.xpath(expr, namespaces=nsmap or None)
        except ET.XPathError as exc:
            raise SpxmlError("bad XPath '{0}': {1}".format(expr, exc)) from exc
        if isinstance(result, list):
            return result
        if isinstance(result, bool):
            return [str(result).lower()]
        if isinstance(result, float) and result.is_integer():
            return [str(int(result))]
        return [str(result)]
    path, attr, want_text = _etree_normalize(root, context, expr)
    if path is None:
        return []
    if context is DOCUMENT:
        context = root
    try:
        nodes = context.findall(path, nsmap or None)
    except SyntaxError as exc:
        raise SpxmlError("bad XPath '{0}': {1}".format(expr, exc)) from exc
    if attr is not None:
        return [node.get(attr) for node in nodes if node.get(attr) is not None]
    if want_text:
        return [node.text for node in nodes if node.text]
    return nodes


def split_last_step(expr):
    """('/A/B', 'C') for '/A/B/C'; the parent is '.' for a single step."""
    if "/" not in expr.strip("/"):
        return ".", expr.lstrip("/")
    parent, _, last = expr.rpartition("/")
    return parent or "/", last


# ---------------------------------------------------------------------------
# subcommands
# ---------------------------------------------------------------------------


def cmd_get(args, out):
    root = parse(read_input(args))
    nsmap = namespaces(args)
    missing = 0
    for expr in args.xpath:
        if expr.startswith("%m%"):
            nodes = evaluate(root, root, expr[3:], nsmap)
            value = " ".join(first_text(node) for node in nodes)
        else:
            nodes = evaluate(root, root, expr, nsmap)
            if not nodes:
                missing += 1
                value = ""
            elif args.subtree:
                value = serialize(nodes[0])
            else:
                value = first_text(nodes[0])
        out.write(value.encode("utf-8") + b"\0")
    return 1 if missing else 0


def cmd_list(args, out):
    root = parse(read_input(args))
    nsmap = namespaces(args)
    for expr in args.xpath:
        parent, last = split_last_step(expr)
        values = []
        for node in evaluate(root, root, parent, nsmap):
            if not is_element(node):
                continue
            children = evaluate(root, node, last, nsmap)
            if len(children) > 1:
                values.extend(first_text(child) for child in children)
            elif children:
                values.append(first_text(children[0]))
            else:
                values.append("")
        out.write((args.separator.join(values) + "\n").encode("utf-8"))
    return 0


class TemplateOp(argparse.Action):
    """Collect the sel template operations in command line order."""

    def __call__(self, parser, ns, values, option_string=None):
        ops = getattr(ns, "ops", None) or []
        ops.append((self.dest, values))
        setattr(ns, "ops", ops)


def cmd_sel(args, out):
    root = parse(read_input(args))
    nsmap = namespaces(args)
    ops = getattr(args, "ops", None) or []
    if not ops:
        raise SpxmlError("sel: no template, use -m/-v/-c/-o/-n")
    head = []
    body = []
    match_expr = None
    for op, value in ops:
        if op == "match":
            if match_expr is not None:
                raise SpxmlError("sel: only one -m per template")
            match_expr = value
        elif match_expr is None:
            head.append((op, value))
        else:
            body.append((op, value))

    def run(context, template):
        for op, value in template:
            if op == "value":
                nodes = evaluate(root, context, value, nsmap)
                out.write(string_value(nodes[0]).encode("utf-8") if nodes else b"")
            elif op == "copy":
                for node in evaluate(root, context, value, nsmap):
                    out.write(serialize(node).encode("utf-8"))
            elif op == "text":
                out.write(value.encode("utf-8"))
            elif op == "newline":
                out.write(b"\n")

    run(DOCUMENT, head)
    if match_expr is None:
        return 0
    matches = [node for node in evaluate(root, DOCUMENT, match_expr, nsmap) if is_element(node)]
    for node in matches:
        run(node, body)
    return 0 if matches else 1


def cmd_ed(args, out):
    root = parse(read_input(args))
    nsmap = namespaces(args)
    ops = getattr(args, "ops", None) or []
    index = 0
    while index < len(ops):
        op, expr = ops[index]
        index += 1
        nodes = [node for node in evaluate(root, root, expr, nsmap) if is_element(node)]
        if op == "update":
            if index >= len(ops) or ops[index][0] != "value":
                raise SpxmlError("ed: -u {0} needs a following -v VALUE".format(expr))
            value = ops[index][1]
            index += 1
            for node in nodes:
                for child in list(node):
                    node.remove(child)
                node.text = value
        elif op == "delete":
            for node in nodes:
                parent = node.getparent() if ENGINE == "lxml" else _etree_parent(root, node)
                if parent is not None:
                    parent.remove(node)
        else:
            raise SpxmlError("ed: -v without a preceding -u")
    out.write(serialize(root).encode("utf-8") + b"\n")
    return 0


def _etree_parent(root, node):
    for parent in root.iter():
        if node in list(parent):
            return parent
    return None


def cmd_sub(args, out):
    root = parse(read_input(args))
    nodes = evaluate(root, root, args.xpath, namespaces(args))
    for node in nodes:
        out.write(serialize(node).encode("utf-8"))
    if not nodes:
        sys.stderr.write("XPath set is empty\n")
        return 1
    return 0


def cmd_fo(args, out):
    data = read_input(args)
    if ENGINE == "lxml":
        try:
            root = ET.fromstring(data, ET.XMLParser(remove_blank_text=True))
        except Exception as exc:  # pylint: disable=broad-except
            raise SpxmlError("not an XML document: {0}".format(exc)) from exc
        out.write(ET.tostring(root, pretty_print=True, xml_declaration=True, encoding="UTF-8"))
        return 0
    from xml.dom import minidom  # pylint: disable=import-outside-toplevel

    try:
        doc = minidom.parseString(data)
    except Exception as exc:  # pylint: disable=broad-except
        raise SpxmlError("not an XML document: {0}".format(exc)) from exc
    pretty = doc.toprettyxml(indent="  ", encoding="UTF-8")
    out.write(b"\n".join(line for line in pretty.split(b"\n") if line.strip()) + b"\n")
    return 0


def cmd_val(args, out):  # pylint: disable=unused-argument
    parse(read_input(args))
    return 0


# ---------------------------------------------------------------------------
# command line
# ---------------------------------------------------------------------------


def add_input_options(parser, with_namespace=True):
    parser.add_argument("-s", "--stdin", action="store_true", help="read the document from stdin (the default)")
    parser.add_argument("-f", "--file", metavar="FILE", help="read the document from FILE")
    parser.add_argument("-b", "--base64", action="store_true", help="the input is base64 encoded")
    if with_namespace:
        parser.add_argument(
            "-N", "--namespace", action="append", metavar="PREFIX=URI", help="bind a namespace prefix for the XPaths"
        )


def build_parser():
    parser = argparse.ArgumentParser(
        prog="spxml.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--engine", action="store_true", help="print the XML engine in use and exit")
    sub = parser.add_subparsers(dest="command")

    p_get = sub.add_parser("get", help="values of XPaths, NUL terminated (xpath.rb)")
    add_input_options(p_get)
    p_get.add_argument("-t", "--subtree", action="store_true", help="print the matched subtree instead of its text")
    p_get.add_argument("xpath", nargs="+")
    p_get.set_defaults(func=cmd_get)

    p_list = sub.add_parser("list", help="joined values per XPath, one line each (xpath_multi.py)")
    add_input_options(p_list)
    p_list.add_argument("-S", "--separator", default=";", help="join the values with this string (default ';')")
    p_list.add_argument("xpath", nargs="+")
    p_list.set_defaults(func=cmd_list)

    p_sel = sub.add_parser("sel", help="template output (xmlstarlet sel)")
    add_input_options(p_sel)
    p_sel.add_argument(
        "-t", "--template", action="store_true", help="start the template (accepted for xmlstarlet compatibility)"
    )
    p_sel.add_argument("-m", dest="match", action=TemplateOp, metavar="XPATH", help="iterate over the matches")
    p_sel.add_argument("-v", dest="value", action=TemplateOp, metavar="XPATH", help="print the string value")
    p_sel.add_argument("-c", dest="copy", action=TemplateOp, metavar="XPATH", help="print the matched nodes")
    p_sel.add_argument("-o", dest="text", action=TemplateOp, metavar="TEXT", help="print TEXT")
    p_sel.add_argument("-n", dest="newline", action=TemplateOp, nargs=0, help="print a newline")
    p_sel.add_argument("positional_file", nargs="?", metavar="FILE", help="the document, instead of stdin")
    p_sel.set_defaults(func=cmd_sel)

    p_ed = sub.add_parser("ed", help="update or delete nodes and print the document (xmlstarlet ed)")
    add_input_options(p_ed)
    p_ed.add_argument("-u", dest="update", action=TemplateOp, metavar="XPATH", help="set the text of the matches")
    p_ed.add_argument("-v", dest="value", action=TemplateOp, metavar="VALUE", help="the text for the preceding -u")
    p_ed.add_argument("-d", dest="delete", action=TemplateOp, metavar="XPATH", help="delete the matches")
    p_ed.add_argument("positional_file", nargs="?", metavar="FILE", help="the document, instead of stdin")
    p_ed.set_defaults(func=cmd_ed)

    p_sub = sub.add_parser("sub", help="print the matched nodes (xmllint --xpath)")
    add_input_options(p_sub)
    p_sub.add_argument("xpath")
    p_sub.add_argument("positional_file", nargs="?", metavar="FILE", help="the document, instead of stdin")
    p_sub.set_defaults(func=cmd_sub)

    p_fo = sub.add_parser("fo", help="pretty print (xmllint --format)")
    add_input_options(p_fo, with_namespace=False)
    p_fo.add_argument("positional_file", nargs="?", metavar="FILE", help="the document, instead of stdin")
    p_fo.set_defaults(func=cmd_fo)

    p_val = sub.add_parser("val", help="check well-formedness (xmllint --noout)")
    add_input_options(p_val, with_namespace=False)
    p_val.add_argument("positional_file", nargs="?", metavar="FILE", help="the document, instead of stdin")
    p_val.set_defaults(func=cmd_val)
    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.engine:
        print(ENGINE)
        return 0
    if not args.command:
        parser.print_usage(sys.stderr)
        return 2
    positional = getattr(args, "positional_file", None)
    if positional and positional != "-":
        if args.file:
            raise SpxmlError("both -f and a FILE argument given")
        args.file = positional
    return args.func(args, sys.stdout.buffer)


if __name__ == "__main__":
    try:
        RC = main()
    except SpxmlError as err:
        sys.stderr.write("spxml: {0}\n".format(err))
        RC = 1
    except BrokenPipeError:
        RC = 0
    sys.stdout.flush()
    sys.exit(RC)
