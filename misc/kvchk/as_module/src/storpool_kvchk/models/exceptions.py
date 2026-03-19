class UnknownApiCall(Exception):
    """Custom exception when unknown StorPool API call is issued"""

    def __init__(self, api_call: str):
        self.api_call: str = api_call

    def __str__(self) -> str:
        return f"Unknown StorPool API call: {self.api_call}"


class UnhandledCase(Exception):
    """Custom exception when unhandled case is encountered"""

    def __init__(self, case: str):
        self.case: str = case

    def __str__(self) -> str:
        return f"Unhandled case: {self.case}"


class KvByNameError(Exception):
    """Custom exception raised when a value is not in kv/ByName"""

    def __init__(self, name: str):
        self.name: str = name

    def __str__(self) -> str:
        return f"Value not in kv/ByName: {self.name}"


class KvByUidError(Exception):
    """Custom exception raised when a value is not in kv/ByUid"""

    def __init__(self, uid: str):
        self.uid: str = uid

    def __str__(self) -> str:
        return f"Value not in kv/ByUid: {self.uid}"


class SshManagerError(Exception):
    """Custom exception raised when SSH manager encounters an error"""

    def __init__(self, msg: str, host: str = "", cmd: str = ""):
        self.msg: str = msg
        self.host: str = host
        self.cmd: str = cmd

    def __str__(self) -> str:
        err_msg: str = self.msg
        if self.host:
            err_msg += f" {self.host=}"
        if self.cmd:
            err_msg += f" {self.cmd=}"
        return err_msg
