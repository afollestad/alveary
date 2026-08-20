#!/usr/bin/env python3
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("detect-release-version.py")
# GitHub sends this instead of a parent commit when a push creates a ref, so the
# previous project.yml is unreadable and the run cannot know what changed.
ALL_ZEROS_SHA = "0" * 40


class DetectReleaseVersionTests(unittest.TestCase):
    """Drives the real script against a work repo whose origin is a bare repo,
    so tag lookups exercise `git ls-remote` rather than a stub."""

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        root = Path(self.temporary_directory.name)
        self.origin = root / "origin.git"
        self.repo = root / "work"
        subprocess.run(
            ["git", "init", "--quiet", "--bare", "-b", "main", str(self.origin)],
            check=True,
            capture_output=True,
        )
        self.repo.mkdir()
        self.git("init", "--quiet", "-b", "main")
        self.git("config", "user.email", "tests@example.com")
        self.git("config", "user.name", "Release Tests")
        self.git("remote", "add", "origin", str(self.origin))

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def git(self, *arguments: str) -> str:
        result = subprocess.run(
            ["git", *arguments],
            cwd=self.repo,
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip()

    def commit_version(self, version: str, build: str) -> str:
        """Writes the two keys the script reads and appends to a marker file, so
        recommitting an unchanged version still produces a distinct commit."""
        project = self.repo / "project.yml"
        project.write_text(
            "targets:\n"
            "  Alveary:\n"
            "    settings:\n"
            "      base:\n"
            f"        MARKETING_VERSION: {version}\n"
            f"        CURRENT_PROJECT_VERSION: {build}\n",
            encoding="utf-8",
        )
        marker = self.repo / "history.txt"
        previous = marker.read_text(encoding="utf-8") if marker.exists() else ""
        marker.write_text(f"{previous}{version} {build}\n", encoding="utf-8")
        self.git("add", "project.yml", "history.txt")
        self.git("commit", "--quiet", "-m", f"Set version {version} ({build})")
        return self.git("rev-parse", "HEAD")

    def publish_tag(self, tag: str) -> None:
        self.git("tag", tag)
        self.git("push", "--quiet", "origin", tag)

    def detect(
        self,
        before_sha: str = "",
        is_dry_run: bool = False,
    ) -> tuple[subprocess.CompletedProcess[str], dict[str, str]]:
        output_path = self.repo / "github-output.txt"
        environment = os.environ.copy()
        environment["BEFORE_SHA"] = before_sha
        environment["IS_DRY_RUN"] = "true" if is_dry_run else "false"
        environment["GITHUB_OUTPUT"] = str(output_path)
        environment["GITHUB_SHA"] = self.git("rev-parse", "HEAD")
        result = subprocess.run(
            [str(SCRIPT_PATH)],
            cwd=self.repo,
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )
        outputs = {}
        if output_path.exists():
            for line in output_path.read_text(encoding="utf-8").splitlines():
                key, value = line.split("=", 1)
                outputs[key] = value
        return result, outputs

    def test_builds_a_canary_when_the_release_tag_already_exists(self) -> None:
        previous = self.commit_version("0.2.2", "11")
        self.publish_tag("v0.2.2")
        head = self.commit_version("0.2.2", "11")

        result, outputs = self.detect(before_sha=previous)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(outputs["mode"], "canary")
        self.assertEqual(outputs["version"], "0.2.2")
        self.assertEqual(outputs["build"], "11")
        self.assertEqual(outputs["tag"], "v0.2.2")
        # Naming the artifact anything else would download as a directory that is
        # not a bundle, because the enclosing `.app` is not in the archive.
        self.assertEqual(outputs["artifact_name"], "Alveary.app")
        # The bundle name leaves the canary's own artifact unidentifiable, so the
        # dSYM ZIP beside it is what carries the version and commit.
        self.assertEqual(outputs["dsym_artifact_name"], f"Alveary-canary-0.2.2-11-{head[:7]}-dSYMs")

    def test_builds_a_canary_when_the_previous_project_file_is_unreadable(self) -> None:
        for before_sha in ("", ALL_ZEROS_SHA):
            with self.subTest(before_sha=before_sha or "<empty>"):
                self.commit_version("0.2.2", "11")

                result, outputs = self.detect(before_sha=before_sha)

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(outputs["mode"], "canary")

    def test_releases_when_the_version_is_bumped_and_its_tag_is_missing(self) -> None:
        previous = self.commit_version("0.2.2", "11")
        self.publish_tag("v0.2.2")
        self.commit_version("0.2.3", "12")

        result, outputs = self.detect(before_sha=previous)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(outputs["mode"], "release")
        self.assertEqual(outputs["tag"], "v0.2.3")
        self.assertEqual(outputs["artifact_name"], "")
        # Both payloads become GitHub Release assets, so neither needs an artifact.
        self.assertEqual(outputs["dsym_artifact_name"], "")

    def test_releases_an_unchanged_version_whose_tag_is_missing(self) -> None:
        previous = self.commit_version("0.2.3", "12")
        self.commit_version("0.2.3", "12")

        result, outputs = self.detect(before_sha=previous)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(outputs["mode"], "release")

    def test_manual_runs_are_dry_runs_even_when_the_version_is_publishable(self) -> None:
        previous = self.commit_version("0.2.2", "11")
        head = self.commit_version("0.2.3", "12")

        result, outputs = self.detect(before_sha=previous, is_dry_run=True)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(outputs["mode"], "dry-run")
        self.assertEqual(outputs["artifact_name"], f"Alveary-dry-run-0.2.3-12-{head[:7]}")
        self.assertEqual(outputs["dsym_artifact_name"], f"Alveary-dry-run-0.2.3-12-{head[:7]}-dSYMs")

    def test_fails_when_bumping_to_a_version_that_is_already_tagged(self) -> None:
        previous = self.commit_version("0.2.2", "11")
        self.commit_version("0.2.3", "12")
        self.publish_tag("v0.2.3")

        result, outputs = self.detect(before_sha=previous)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(outputs, {})
        self.assertIn("release tag v0.2.3 already exists", result.stderr)

    def test_fails_a_canary_whose_version_is_not_semantic(self) -> None:
        self.commit_version("0.2", "11")

        result, outputs = self.detect(before_sha=ALL_ZEROS_SHA)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(outputs, {})
        self.assertIn("version must be X.Y.Z", result.stderr)

    def test_fails_when_the_build_number_is_not_an_integer(self) -> None:
        previous = self.commit_version("0.2.2", "11")
        self.commit_version("0.2.3", "beta")

        result, outputs = self.detect(before_sha=previous)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(outputs, {})
        self.assertIn("build number must be an integer", result.stderr)

    def test_fails_when_a_release_does_not_increase_the_build_number(self) -> None:
        previous = self.commit_version("0.2.2", "11")
        self.commit_version("0.2.3", "11")

        result, outputs = self.detect(before_sha=previous)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(outputs, {})
        self.assertIn("build number must increase from 11", result.stderr)


if __name__ == "__main__":
    unittest.main()
