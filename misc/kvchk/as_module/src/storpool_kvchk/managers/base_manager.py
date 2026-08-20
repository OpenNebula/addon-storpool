from __future__ import annotations
from typing import Optional
import sys
import argparse

from ..utils.report_writer import ReportWriter


class BaseManager:
    """Base manager class"""

    # set from cli.main() when --report is given; shared by all
    # managers so every reported issue lands in the report files
    reporter: Optional[ReportWriter] = None

    def __init__(self, args: argparse.Namespace) -> None:
        """Initialize the manager"""
        self.args: argparse.Namespace = args

    @classmethod
    def _cls_name(cls) -> str:
        """Class name"""
        return cls.__name__

    def dbg(self, lvl: int, msg: str) -> None:
        """Debug message"""
        if self.args.verbose >= lvl:
            caller: str = sys._getframe(1).f_code.co_name
            lineno: int = sys._getframe(1).f_lineno
            print(f"#[{lvl}] {self._cls_name()}.{caller}:{lineno}: {msg}")
            if lvl == 0 and BaseManager.reporter is not None:
                # the level-0 lines of the analyze passes are the
                # cleanup hints of the reported issues - keep them
                # next to the issue; the level-0 execution chatter
                # of the managers has no category and stays out
                category: Optional[str] = (
                    BaseManager.reporter.category(caller)
                )
                if category is not None:
                    BaseManager.reporter.write(category, msg)

    def err(self, msg: str, tag: str = "Error") -> None:
        """Error message"""
        caller: str = sys._getframe(1).f_code.co_name
        lineno: int = sys._getframe(1).f_lineno
        print(f"[{tag}] {self._cls_name()}.{caller}:{lineno}: {msg}")
        if BaseManager.reporter is not None:
            category: str = (
                BaseManager.reporter.category(caller) or "errors"
            )
            BaseManager.reporter.write(category, f"[{tag}] {msg}")
