#!/usr/bin/env python3
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("stage-canary-app.sh")


class StageCanaryAppTests(unittest.TestCase):
    """`actions/upload-artifact` replaces a symlink with a copy of its target and
    roots its archive at the uploaded path, both without failing, so an unstaged
    upload arrives with an invalid signature or as a bare `Contents/` folder.
    These tests pin that the script refuses the first and prevents the second."""

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        root = Path(self.temporary_directory.name)
        self.export_path = root / "export"
        self.release_path = root / "release"
        self.output_path = root / "github-output"
        self.bundle = self.export_path / "Alveary.app"
        (self.bundle / "Contents" / "MacOS").mkdir(parents=True)
        (self.bundle / "Contents" / "Info.plist").write_text("plist\n", encoding="utf-8")
        executable = self.bundle / "Contents" / "MacOS" / "Alveary"
        executable.write_text("binary\n", encoding="utf-8")
        executable.chmod(0o755)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def run_script(self) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment["EXPORT_PATH"] = str(self.export_path)
        environment["RELEASE_PATH"] = str(self.release_path)
        environment["GITHUB_OUTPUT"] = str(self.output_path)
        environment["APP_NAME"] = "Alveary"
        return subprocess.run(
            [str(SCRIPT_PATH)],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )

    def staged_path(self) -> Path:
        """The staging directory is named freshly on every run, so the script's
        own `app_dir` output is the only place the upload path exists."""
        outputs = dict(
            line.split("=", 1) for line in self.output_path.read_text(encoding="utf-8").splitlines()
        )
        return Path(outputs["app_dir"])

    def test_accepts_a_bundle_without_symlinks(self) -> None:
        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_a_symlink_nested_in_the_bundle(self) -> None:
        (self.bundle / "Contents" / "Frameworks").symlink_to("MacOS")

        result = self.run_script()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("flatten symlinks", result.stderr)
        self.assertIn("Frameworks", result.stderr)
        self.assertFalse(self.output_path.exists())

    def test_fails_when_the_bundle_is_missing(self) -> None:
        for entry in sorted(self.bundle.rglob("*"), reverse=True):
            entry.unlink() if entry.is_file() else entry.rmdir()
        self.bundle.rmdir()

        result = self.run_script()

        self.assertNotEqual(result.returncode, 0)

    def test_stages_the_bundle_as_the_only_entry_at_the_staging_root(self) -> None:
        result = self.run_script()

        stage_path = self.staged_path()
        self.assertEqual(result.returncode, 0, result.stderr)
        # The upload roots its archive here, so anything else at this level would
        # become a second top-level entry and stop macOS expanding the bundle.
        self.assertEqual([entry.name for entry in stage_path.iterdir()], ["Alveary.app"])
        self.assertTrue((stage_path / "Alveary.app" / "Contents" / "MacOS" / "Alveary").is_file())

    def test_preserves_the_executable_bit(self) -> None:
        self.run_script()

        staged = self.staged_path() / "Alveary.app" / "Contents" / "MacOS" / "Alveary"
        self.assertTrue(staged.stat().st_mode & stat.S_IXUSR)

    def test_excludes_what_earlier_steps_left_in_the_release_path(self) -> None:
        self.release_path.mkdir(parents=True)
        (self.release_path / "Alveary.dSYMs.zip").write_text("zip\n", encoding="utf-8")

        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([entry.name for entry in self.staged_path().iterdir()], ["Alveary.app"])

    def test_reports_the_staging_directory_as_the_upload_path(self) -> None:
        self.run_script()

        self.assertTrue(self.staged_path().is_relative_to(self.release_path))


if __name__ == "__main__":
    unittest.main()
