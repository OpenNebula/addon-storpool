from setuptools import setup, find_packages  # type: ignore
from pathlib import Path
import re

# Read version from version.py without importing
version_file = Path(__file__).parent / "src" / "storpool_kvchk" / "version.py"
version_content = version_file.read_text()
version_match = re.search(
    r'__version__\s*:\s*str\s*=\s*"([^"]+)"', version_content
)
if version_match:
    __version__ = version_match.group(1)
else:
    raise RuntimeError("Unable to find version string in version.py")

setup(
    name="storpool-kvchk",
    version=__version__,
    packages=find_packages(where="src"),
    package_dir={"": "src"},
    install_requires=[
        "pytest",
        "protobuf<=3.20.3",
        "pyone",
        "etcd3",
        "storpool"
        # Add other dependencies here
    ],
    package_data={"storpool_kvchk": ["py.typed"]},
)
