from __future__ import annotations
from typing import Dict, Any
import argparse
import os


def parse_arguments(defaults: Dict[str, Any] = {}) -> argparse.Namespace:
    """Parse and validate command line arguments"""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-v",
        "--verbose",
        action="count",
        default=0,
        help="be verbose",
    )
    parser.add_argument(
        "-N",
        "--dry-run",
        action="store_true",
        help="do nothing",
    )
    parser.add_argument(
        "-p",
        "--one-px",
        action="store",
        default=defaults.get("ONE_PX", os.getenv("ONE_PX", "one")),  # type: ignore[attr-defined] # noqa: E501
        nargs="?",
        type=str,
        help="Object preffix in StorPool, string",
    )
    parser.add_argument(
        "-t",
        "--one-token",
        action="store",
        default=defaults.get("ONE_TOKEN", os.getenv("ONE_TOKEN")),  # type: ignore[attr-defined] # noqa: E501
        nargs="?",
        type=str,
        help="Object preffix in StorPool, string",
    )
    parser.add_argument(
        "-X",
        "--execute",
        action="store_true",
        help="execute changes, bool",
    )
    parser.add_argument(
        "-d",
        "--dummy-etcd",
        action="count",
        default=0,
        help="-d disable etcd, -dd disable ssh to host",
    )

    args: argparse.Namespace = parser.parse_args()
    if args.verbose > 0:
        print(f"parse_arguments() {args=}")
    if args.execute and args.dummy_etcd > 0:
        print("Warning! --execute is disabled when --dummy-etcd is defined!")
        args.execute = False
    return args
