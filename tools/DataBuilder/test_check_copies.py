import contextlib
import io
import tempfile
import unittest
from pathlib import Path

import check_copies


class CheckCopiesTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.shared = self.root / "shared"
        self.copy = self.root / "copy"
        for folder in (self.shared, self.copy):
            folder.mkdir()
            (folder / "DataTable.cs").write_bytes(b"class A {}\n")
            (folder / "DataBuilder.csproj").write_bytes(b"<Project />\n")
            (folder / "notes.txt").write_text("ignored")

    def run_main(self, *copies):
        with contextlib.redirect_stdout(io.StringIO()) as out:
            code = check_copies.main([*map(str, copies), "--shared", str(self.shared)])
        return code, out.getvalue()

    def test_same_copy_passes_and_ignores_line_endings(self):
        (self.copy / "DataTable.cs").write_bytes(b"class A {}\r\n")
        code, out = self.run_main(self.copy)
        self.assertEqual(code, 0)
        self.assertIn("same as the shared copy", out)

    def test_reports_each_kind_of_drift(self):
        (self.copy / "DataTable.cs").write_bytes(b"class B {}\n")
        (self.copy / "DataBuilder.csproj").unlink()
        (self.copy / "Extra.cs").write_bytes(b"")
        self.assertEqual(
            check_copies.compare(self.shared, self.copy),
            {"differ": ["DataTable.cs"], "missing": ["DataBuilder.csproj"], "extra": ["Extra.cs"]},
        )
        code, out = self.run_main(self.copy)
        self.assertEqual(code, 1)
        self.assertIn("differ: DataTable.cs", out)

    def test_missing_folder_fails(self):
        code, out = self.run_main(self.root / "absent")
        self.assertEqual(code, 1)
        self.assertIn("not found", out)


if __name__ == "__main__":
    unittest.main()
