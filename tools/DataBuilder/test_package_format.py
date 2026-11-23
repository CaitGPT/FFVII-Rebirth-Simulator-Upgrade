"""Checks DataBuilder against both package formats the game has shipped.

The 2024 Steam build cooks DataObject tables with versioned properties (the export's frozen size at +0x0c); the Epic
1.005 build is re-cooked with unversioned properties (PKG_UnversionedProperties in the summary, frozen size at +0x06).
A UTF-16 name is 2-byte aligned inside the name batch in both. Real tables cannot be committed here, so each test
builds the smallest package DataBuilder will accept and drives the built tool over it.

    python -m unittest discover Tools/ff7r-databuilder

Needs the .NET 8 SDK; the tests skip without it.
"""

from __future__ import annotations

import json
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

SRC = Path(__file__).resolve().parent / "src"

SUMMARY_SIZE = 0x40
PACKAGE_FLAGS = 0x80800200
PKG_UNVERSIONED_PROPERTIES = 0x2000
INT32_TYPE = 6          # DataTable's type code for a 4-byte scalar
ASSET = "DataObject/Test/Table.uasset"


def _align(value: int, alignment: int) -> int:
    return (value + alignment - 1) // alignment * alignment


def export_start(data: bytes) -> int:
    """Where the export begins: the package's graph data ends there."""
    return struct.unpack_from("<i", data, 0x34)[0] + struct.unpack_from("<i", data, 0x38)[0]


def name_batch(names: list[str]) -> tuple[bytes, int]:
    """The name batch, and how many UTF-16 names needed a padding byte to start 2-byte aligned."""
    out = bytearray()
    padded = 0
    for name in names:
        wide = any(ord(c) > 0xFF for c in name)
        out.append((0x80 if wide else 0) | (len(name) >> 8))
        out.append(len(name) & 0xFF)
        if wide and len(out) % 2:
            out.append(0)
            padded += 1
        out += name.encode("utf-16-le" if wide else "latin-1")
    return bytes(out), padded


def frozen_image(row_names: list[int], properties: list[int], values: list[int]) -> tuple[bytes, dict[int, int]]:
    """The frozen UE memory image for a table of one int32 property per row, and its {offset: name index} patches.

    Blocks are laid out exactly as DataTable.WriteExport allocates them, so a round-trip can be byte for byte.
    """
    rows, props = len(row_names), len(properties)
    stride = 4                       # one int32 property
    bits_max = _align(rows, 32)
    keys = 0x58
    bits = keys + 20 * rows
    buckets = bits + 4 * (bits_max // 32)
    records = buckets + 4            # one bucket: DataTable.BucketCount is 1 below four rows
    entries = records + 12 * props
    image = bytearray(_align(entries + stride * rows, 16))

    def ptr(at: int, target: int) -> None:
        struct.pack_into("<q", image, at, ((target - at) << 1) | 1)

    def i32(at: int, value: int) -> None:
        struct.pack_into("<i", image, at, value)

    ptr(0x00, keys), i32(0x08, rows), i32(0x0C, rows)
    ptr(0x10, bits), i32(0x18, rows), i32(0x1C, bits_max), i32(0x20, -1), i32(0x24, 0)
    ptr(0x28, buckets), i32(0x30, 1)
    ptr(0x38, records), i32(0x40, props), i32(0x44, props)
    ptr(0x48, entries), i32(0x50, rows), i32(0x54, rows)

    patches = {}
    for i in range(rows):
        patches[keys + 20 * i] = row_names[i]       # the FName itself is zero and named by the patch table
        i32(keys + 20 * i + 8, i)                   # entry index
        i32(keys + 20 * i + 12, i - 1)              # next in the bucket chain, newest first
        i32(keys + 20 * i + 16, 0)                  # the only bucket
        image[bits + i // 8] |= 1 << (i % 8)
    i32(buckets, rows - 1)
    for p, name in enumerate(properties):
        patches[records + 12 * p] = name
        i32(records + 12 * p + 8, INT32_TYPE)
    for i, value in enumerate(values):
        i32(entries + stride * i, value)
    return bytes(image), patches


def export_blob(frozen: bytes, patches: dict[int, int], none_name: int, unversioned: bool) -> bytes:
    """The export: a property prefix holding the frozen size, the frozen image, then the name patch table."""
    prefix = bytearray(0x20)
    if unversioned:
        prefix[0:2] = b"\x00\x01"                   # FUnversionedHeader
        struct.pack_into("<i", prefix, 0x06, len(frozen))
        prefix[0x0A:0x12] = bytes.fromhex("0000010010000e00")
    else:
        struct.pack_into("<ii", prefix, 0x00, none_name, 0)   # the tagged "None" that ends the property list
        struct.pack_into("<i", prefix, 0x0C, len(frozen))
        prefix[0x10:0x18] = bytes.fromhex("0000010010000800")

    out = bytearray(prefix)
    out += frozen
    out += bytes(8)                                 # the 8 bytes between the image and the patch table
    groups: dict[int, list[int]] = {}
    for offset, name in sorted(patches.items()):
        groups.setdefault(name, []).append(offset)
    out += struct.pack("<i", len(groups))
    for name in sorted(groups):
        out += struct.pack("<iii", name, 0, len(groups[name]))
        out += b"".join(struct.pack("<i", o) for o in sorted(groups[name]))
    out += bytes(4)                                 # trailing bytes, carried over untouched
    return bytes(out)


def package(names: list[str], row_names: list[int], properties: list[int], values: list[int], unversioned: bool) -> bytes:
    """A zen package holding one DataObject table, in either of the two formats the game ships."""
    batch, _ = name_batch(names)
    hashes_off = _align(SUMMARY_SIZE + len(batch), 8)
    hashes_size = 8 + 8 * len(names)
    imports_off = hashes_off + hashes_size
    exports_off = imports_off + 24                  # three imports
    bundles_off = exports_off + 72                  # one export map entry
    graph_off = bundles_off + 24
    graph_size = 16

    export = export_blob(*frozen_image(row_names, properties, values), none_name=names.index("None"), unversioned=unversioned)

    summary = bytearray(SUMMARY_SIZE)
    struct.pack_into("<I", summary, 0x10, PACKAGE_FLAGS | (PKG_UNVERSIONED_PROPERTIES if unversioned else 0))
    struct.pack_into("<iiiiiiiiii", summary, 0x18, SUMMARY_SIZE, len(batch), hashes_off, hashes_size,
                     imports_off, exports_off, bundles_off, graph_off, graph_size, 0)

    out = bytearray(summary)
    out += batch
    out += bytes(hashes_off - SUMMARY_SIZE - len(batch))
    out += bytes(8)                                 # hash algorithm id
    out += bytes(8 * len(names))                    # per-name CityHash64; DataBuilder only checks the count here
    out += bytes(exports_off - imports_off)
    entry = bytearray(72)
    struct.pack_into("<Q", entry, 8, len(export))   # cooked serial size
    out += entry
    out += bytes(graph_off + graph_size - bundles_off)
    out += export
    return bytes(out)


# Index 0 is the class the roundtrip command looks for; "None" ends a versioned export's property list.
NAMES = ["/Script/EndDataObject", "None", "Id", "Alpha", "Beta"]
WIDE_NAMES = NAMES + ["Odd", "テスト"]   # "Odd" makes the batch odd, so the UTF-16 name needs padding


def table(unversioned: bool, *, wide: bool = False, values: list[int] | None = None, extra_row: bool = False) -> bytes:
    names = WIDE_NAMES if wide else NAMES
    rows = [3, 4] + ([6] if wide else [])
    if extra_row:
        names = names + ["Gamma"]
        rows = rows + [names.index("Gamma")]
    values = values or list(range(10, 10 + len(rows)))
    return package(names, rows, [NAMES.index("Id")], values, unversioned)


@unittest.skipUnless(shutil.which("dotnet"), "needs the .NET 8 SDK")
class PackageFormatTest(unittest.TestCase):
    tool: list[str]

    @classmethod
    def setUpClass(cls):
        cls._build = tempfile.mkdtemp()
        built = subprocess.run(["dotnet", "build", str(SRC), "-c", "Release", "-o", cls._build, "--nologo", "-v", "quiet"],
                               capture_output=True, text=True)
        if built.returncode:
            raise AssertionError(f"dotnet build failed:\n{built.stdout}{built.stderr}")
        cls.tool = ["dotnet", str(Path(cls._build) / "DataBuilder.dll")]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls._build, ignore_errors=True)

    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)

    def run_tool(self, *args) -> subprocess.CompletedProcess:
        return subprocess.run([*self.tool, *map(str, args)], capture_output=True, text=True)

    def write(self, name: str, data: bytes) -> Path:
        path = self.root / name / "End" / "Content" / ASSET
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def assertRoundTrips(self, folder: Path, count: int = 1):
        result = self.run_tool("roundtrip", folder)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"{count} byte-identical, 0 with identical rows, 0 failed, 0 skipped", result.stdout)

    def test_versioned_table_round_trips(self):
        self.write("versioned", table(unversioned=False))
        self.assertRoundTrips(self.root / "versioned")

    def test_unversioned_table_round_trips(self):
        self.write("epic", table(unversioned=True))
        self.assertRoundTrips(self.root / "epic")

    def test_wide_name_is_two_byte_aligned_in_both_formats(self):
        # The Epic build's ResidentStateChange, and seven tables in the 2026-07 export, hit this padding byte.
        self.assertEqual(name_batch(WIDE_NAMES)[1], 1, "the fixture must need a padding byte to test for one")
        self.write("versioned", table(unversioned=False, wide=True))
        self.write("epic", table(unversioned=True, wide=True))
        self.assertRoundTrips(self.root / "versioned")
        self.assertRoundTrips(self.root / "epic")

    def test_wide_name_is_read_at_the_right_offset(self):
        # Proof the padding byte is read and not merely written: the characters after it are the row's name.
        source = self.write("epic", table(unversioned=True, wide=True))
        csv = self.root / "rows.csv"
        result = self.run_tool("export", source, csv)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(WIDE_NAMES[-1], csv.read_text(encoding="utf-8"))

    def test_an_edited_table_keeps_the_format_it_was_read_in(self):
        for unversioned, size_at, other_at in ((False, 0x0C, 0x06), (True, 0x06, 0x0C)):
            with self.subTest(unversioned=unversioned):
                name = f"build-{unversioned}"
                source = self.write(name, table(unversioned))
                spec = self.root / f"{name}.json"
                spec.write_text(json.dumps({"tables": [{"asset": ASSET, "rows": [
                    {"name": "Gamma", "cloneFrom": "Alpha", "set": {"Id": 99}}]}]}))
                out = self.root / f"{name}-out"
                result = self.run_tool("build", spec, self.root / name, out)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

                before, after = source.read_bytes(), (out / "End" / "Content" / ASSET).read_bytes()
                size, written = (export_start(before) + size_at, export_start(after) + size_at)
                self.assertGreater(struct.unpack_from("<i", after, written)[0], struct.unpack_from("<i", before, size)[0],
                                   "the extra row must grow the frozen size, where this format keeps it")
                other, other_written = export_start(before) + other_at, export_start(after) + other_at
                self.assertEqual(after[other_written:other_written + 4], before[other:other + 4],
                                 "the other format's size field must be left alone")

    def test_diff_matches_rows_and_properties_by_name(self):
        a = self.write("a", table(unversioned=False))
        b = self.write("b", table(unversioned=True, values=[10, 21, 12], extra_row=True))
        result = self.run_tool("diff", a, b)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("unversioned properties: False vs True", result.stdout)
        self.assertIn("schema SAME", result.stdout)
        self.assertIn("rows added: 1", result.stdout)
        self.assertIn("+ Gamma", result.stdout)
        self.assertIn("rows changed: 1", result.stdout)
        self.assertIn("~ Beta: Id: '11' -> '21'", result.stdout)
        self.assertIn("RESULT: different", result.stdout)

    def test_diff_reports_the_same_table_in_two_formats_as_unchanged(self):
        # The question after a game update: same tables re-cooked, or actually different content?
        a = self.write("steam", table(unversioned=False))
        b = self.write("epic", table(unversioned=True))
        result = self.run_tool("diff", a, b)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("RESULT: same schema and rows", result.stdout)


if __name__ == "__main__":
    unittest.main()
