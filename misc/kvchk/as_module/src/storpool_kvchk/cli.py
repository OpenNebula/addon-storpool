"""Command-line interface implementation."""

from typing import Dict, Any, Callable
import os
import sys
import pprint
import argparse
import traceback

from .managers.ssh_manager import SshManager
from .managers.one_manager import oneManager
from .managers.storpool_manager import spManager
from .managers.etcd_manager import etcdManager
from .processors.data_processing import DataProcessing


def parse_addon_storpoolrc() -> Dict[str, str]:
    """Parse the addon storpoolrc file."""
    addon_storpoolrc: str = os.getenv(  # type: ignore[attr-defined]
        "ADDON_STORPOOLRC",
        "/var/lib/one/remotes/addon-storpoolrc",
    )
    defaults: Dict[str, str] = {}
    if os.path.exists(addon_storpoolrc):  # type: ignore[attr-defined]
        with open(addon_storpoolrc, "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("#") or not line:
                    continue
                if '=' in line:
                    key, value = line.split("=", 1)
                    value = value.strip('"\'')
                    defaults[key.strip()] = value
    return defaults


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
    parser.add_argument(
        "--default-qosclass",
        action="store",
        default=defaults.get("DEFAULT_QOSCLASS", os.getenv("DEFAULT_QOSCLASS")),  # type: ignore[attr-defined] # noqa: E501
        nargs="?",
        type=str,
        help="Default QoS class, string",
    )

    args = parser.parse_args()
    if args.verbose > 0:
        print(f"parse_arguments() {args=}")
    if args.execute and args.dummy_etcd > 0:
        print("Warning! --execute is disabled when --dummy-etcd is defined!")
        args.execute = False
    return args


def process_updates(
    args: argparse.Namespace,
    update_data: Dict[str, Dict[str, Any]],
    actions: Dict[str, Callable[..., None]],
) -> None:
    """Process the pending updates."""
    for xname, xdata in update_data.items():
        print(f"#>>Update {xname}")
        pprint.pprint(xdata)

        for do_action in xdata["action"]:
            if do_action in actions:
                if args.verbose > 0:
                    print(f"do_action({xname}): {do_action=} {xdata['data']=}")
                actions[do_action](xdata["data"], do_action)


def main() -> int:
    """Main entry point."""
    try:
        defaults = parse_addon_storpoolrc()
        arguments = parse_arguments(defaults)

        ssh_manager = SshManager(arguments)
        one_manager = oneManager(arguments, ssh_manager)
        sp_manager = spManager(arguments)
        etcd_manager = etcdManager(arguments)

        data_processing = DataProcessing(
            arguments, etcd_manager, sp_manager, one_manager, ssh_manager
        )

        data_processing.analyze_kv_by_name()
        data_processing.analyze_kv_by_uid()

        data_processing.analyze_vm_disks()
        data_processing.analyze_one_images()

        data_processing.analyze_storpool()

        data_processing.process_updates()

        return 0
    except Exception:
        print(f"Error: {traceback.format_exc()}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
