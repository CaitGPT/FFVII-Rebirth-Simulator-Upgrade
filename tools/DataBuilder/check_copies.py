"""Compare copies of DataBuilder in mod repos with the shared one here.

Each public mod repo keeps its own copy, so players and contributors can build it without this private repo. Copies drift:
a fix made in one never reaches the others. Run this when starting or finishing a mod:

    python Tools/ff7r-databuilder/check_copies.py <mod>/tools/DataBuilder [<another copy> ...]

Line endings are ignored. It prints one line per copy and exits 1 if any copy differs, so an improvement can be brought
back here (or the copy updated) on purpose.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SHARED = Path(__file__).resolve().parent / "src"
SOURCE_SUFFIXES = {".cs", ".csproj"}


def _sources(folder: Path) -> dict[str, bytes]:
    return {
        path.name: path.read_bytes().replace(b"\r\n", b"\n")
        for path in sorted(folder.iterdir())
        if path.is_file() and path.suffix in SOURCE_SUFFIXES
    }


def compare(shared: Path, copy: Path) -> dict[str, list[str]]:
    """Return the files that differ, are missing from the copy, or exist only in the copy."""
    ours, theirs = _sources(shared), _sources(copy)
    return {
        "differ": [name for name in ours if name in theirs and ours[name] != theirs[name]],
        "missing": [name for name in ours if name not in theirs],
        "extra": [name for name in theirs if name not in ours],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("copies", nargs="+", type=Path, help="DataBuilder folders in mod repos")
    parser.add_argument("--shared", type=Path, default=SHARED, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)

    drifted = False
    for copy in args.copies:
        if not copy.is_dir():
            print(f"{copy}: not found")
            drifted = True
            continue
        result = compare(args.shared, copy)
        parts = [f"{kind}: {', '.join(names)}" for kind, names in result.items() if names]
        print(f"{copy}: {'; '.join(parts) if parts else 'same as the shared copy'}")
        drifted |= bool(parts)
    return 1 if drifted else 0


if __name__ == "__main__":
    sys.exit(main())
