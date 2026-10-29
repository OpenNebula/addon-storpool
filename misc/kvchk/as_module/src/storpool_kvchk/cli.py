"""Command-line interface implementation."""

from typing import Dict, Any, Callable
import os
import sys
import pprint
import argparse
import traceback

from .managers.base_manager import BaseManager
from .managers.ssh_manager import SshManager
from .managers.one_manager import oneManager
from .managers.storpool_manager import spManager
from .managers.etcd_manager import etcdManager
from .processors.data_processing import DataProcessing
from .utils.report_writer import ReportWriter
from .models.exceptions import ClusterConfigError


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
                if line.startswith("export "):
                    line = line[len("export "):].lstrip()
                if '=' in line:
                    key, value = line.split("=", 1)
                    value = value.strip('"\'')
                    defaults[key.strip()] = value
    return defaults


def bool_true(value: Any) -> bool:
    """Interpret a bool-like addon-storpoolrc value the same way
    as boolTrue() in tm/storpool/storpool_common.sh"""
    return str(value).upper() in ("1", "Y", "YES", "T", "TRUE", "ON")


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
        "--vm-tag",
        action="store",
        default=defaults.get("VM_TAG", os.getenv("VM_TAG", "nvm")),  # type: ignore[attr-defined] # noqa: E501
        type=str,
        help="VM_TAG from addon-storpoolrc - the StorPool tag holding"
             " the VM ID on VM disks, empty string disables it"
             " (default nvm)",
    )
    parser.add_argument(
        "--loc-tag",
        action="store",
        default=defaults.get("LOC_TAG", os.getenv("LOC_TAG", "nloc")),  # type: ignore[attr-defined] # noqa: E501
        type=str,
        help="LOC_TAG from addon-storpoolrc - the StorPool tag marking"
             " the OpenNebula instance (default nloc)",
    )
    parser.add_argument(
        "--loc-tag-val",
        action="store",
        default=defaults.get("LOC_TAG_VAL", os.getenv("LOC_TAG_VAL")),  # type: ignore[attr-defined] # noqa: E501
        type=str,
        help="LOC_TAG_VAL from addon-storpoolrc - the value of the"
             " LOC_TAG tag (default ONE_PX)",
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
    parser.add_argument(
        "--skip-undeploy-ssh",
        action="store",
        default=defaults.get("SKIP_UNDEPLOY_SSH", os.getenv("SKIP_UNDEPLOY_SSH")),  # type: ignore[attr-defined] # noqa: E501
        nargs="?",
        type=str,
        help="SKIP_UNDEPLOY_SSH from addon-storpoolrc - the VM home"
             " is not moved to the frontend on stop/undeploy,"
             " bool-like string",
    )
    parser.add_argument(
        "--sp-checkpoint-bd",
        action="store",
        default=defaults.get("SP_CHECKPOINT_BD", os.getenv("SP_CHECKPOINT_BD")),  # type: ignore[attr-defined] # noqa: E501
        nargs="?",
        type=str,
        help="SP_CHECKPOINT_BD from addon-storpoolrc - tm/mv"
             " auto-enables SKIP_UNDEPLOY_SSH for VMs with all"
             " disks on StorPool TMs, bool-like string",
    )
    parser.add_argument(
        "--tag-context-iso",
        action="store",
        default=defaults.get("TAG_CONTEXT_ISO", os.getenv("TAG_CONTEXT_ISO", "1")),  # type: ignore[attr-defined] # noqa: E501
        nargs="?",
        type=str,
        help="TAG_CONTEXT_ISO from addon-storpoolrc - tm/context tags"
             " the context ISO volume with qc and vc-policy only when"
             " enabled (the addon default), bool-like string",
    )

    parser.add_argument(
        "-R",
        "--report",
        action="store_true",
        default=True,
        help="log the reported issues to YYYYmmdd-HHMM-<category>.txt"
             " files in the current folder (clusters, kv, vm-disks,"
             " images, volumes, hanging, foreign, duplicates, symlinks,"
             " updates, errors), the default",
    )
    parser.add_argument(
        "--no-report",
        dest="report",
        action="store_false",
        help="do not write the report files",
    )
    parser.add_argument(
        "-F",
        "--report-foreign",
        action="store_true",
        help="report all StorPool volumes/snapshots not related to"
             " this OpenNebula instance (inventory of the entities"
             " outside the VM lifecycle)",
    )
    parser.add_argument(
        "--hanging-min-age",
        action="store",
        default=defaults.get("HANGING_MIN_AGE", os.getenv("HANGING_MIN_AGE", "3600")),  # type: ignore[attr-defined] # noqa: E501
        nargs="?",
        type=int,
        help="Minimum age in seconds before a StorPool volume or"
             " snapshot is reported as hanging (default 3600)",
    )

    args = parser.parse_args()
    args.skip_undeploy_ssh = bool_true(args.skip_undeploy_ssh)
    args.sp_checkpoint_bd = bool_true(args.sp_checkpoint_bd)
    args.tag_context_iso = bool_true(args.tag_context_iso)
    args.hanging_min_age = int(args.hanging_min_age)
    # storpool_common.sh: LOC_TAG_VAL="${LOC_TAG_VAL:-${ONE_PX}}"
    if not args.loc_tag_val or args.loc_tag_val == "${ONE_PX}":
        args.loc_tag_val = args.one_px
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

        if arguments.report:
            BaseManager.reporter = ReportWriter(argv=sys.argv)

        ssh_manager = SshManager(arguments)
        one_manager = oneManager(arguments, ssh_manager)
        sp_manager = spManager(arguments, one_manager.one_datastores)
        etcd_manager = etcdManager(arguments)

        data_processing = DataProcessing(
            arguments, etcd_manager, sp_manager, one_manager, ssh_manager
        )

        # the StorPool cluster configuration gate - nothing else runs
        # (and the upgrade around this check stops) when it fails
        data_processing.analyze_clusters()

        data_processing.analyze_kv_by_name()
        data_processing.analyze_kv_by_uid()

        data_processing.analyze_vm_disks()
        data_processing.analyze_one_images()

        data_processing.analyze_storpool()

        data_processing.analyze_duplicates()

        data_processing.analyze_hanging()

        data_processing.analyze_host_symlinks()

        data_processing.process_updates()

        return 0
    except ClusterConfigError as error:
        BaseManager(arguments).err(f"{error}. Stopping.")
        return 2
    except Exception:
        print(f"Error: {traceback.format_exc()}", file=sys.stderr)
        return 1
    finally:
        if BaseManager.reporter is not None:
            report_files = BaseManager.reporter.close()
            BaseManager.reporter = None
            base = BaseManager(arguments)
            if report_files:
                for report_file in report_files:
                    base.dbg(0, f"report file: {report_file}")
            else:
                base.dbg(0, "no issues reported, no report files written")


if __name__ == "__main__":
    sys.exit(main())
