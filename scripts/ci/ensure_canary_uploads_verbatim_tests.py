#!/usr/bin/env python3
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("ensure-canary-uploads-verbatim.sh")


class EnsureCanaryUploadsVerbatimTests(unittest.TestCase):
    """The guard exists because `actions/upload-artifact` replaces a symlink with
    a copy of its target without failing, so a bundle that verifies on the runner
    would arrive with an invalid signature. These tests pin that it refuses."""

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.export_path = Path(self.temporary_directory.name)
        self.bundle = self.export_path / "Alveary.app"
        (self.bundle / "Contents" / "MacOS").mkdir(parents=True)
        (self.bundle / "Contents" / "Info.plist").write_text("plist\n", encoding="utf-8")
        (self.bundle / "Contents" / "MacOS" / "Alveary").write_text("binary\n", encoding="utf-8")

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def run_guard(self) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment["EXPORT_PATH"] = str(self.export_path)
        environment["APP_NAME"] = "Alveary"
        return subprocess.run(
            [str(SCRIPT_PATH)],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )

    def test_accepts_a_bundle_without_symlinks(self) -> None:
        result = self.run_guard()

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_a_symlink_nested_in_the_bundle(self) -> None:
        (self.bundle / "Contents" / "Frameworks").symlink_to("MacOS")

        result = self.run_guard()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("flatten symlinks", result.stderr)
        self.assertIn("Frameworks", result.stderr)

    def test_fails_when_the_bundle_is_missing(self) -> None:
        for entry in sorted(self.bundle.rglob("*"), reverse=True):
            entry.unlink() if entry.is_file() else entry.rmdir()
        self.bundle.rmdir()

        result = self.run_guard()

        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
