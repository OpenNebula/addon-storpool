from __future__ import annotations
import sys
import argparse


class BaseManager:
    """Base manager class"""

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

    def err(self, msg: str, tag: str = "Error") -> None:
        """Error message"""
        caller: str = sys._getframe(1).f_code.co_name
        lineno: int = sys._getframe(1).f_lineno
        print(f"[{tag}] {self._cls_name()}.{caller}:{lineno}: {msg}")
