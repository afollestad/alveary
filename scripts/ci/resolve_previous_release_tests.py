#!/usr/bin/env python3
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("resolve-previous-release.py")


class ResolvePreviousReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.repo = Path(self.temporary_directory.name)
        self.git("init", "-b", "main")
        self.git("config", "user.email", "tests@example.com")
        self.git("config", "user.name", "Release Tests")

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

    def commit(self, subject: str) -> str:
        marker = self.repo / "history.txt"
        previous = marker.read_text(encoding="utf-8") if marker.exists() else ""
        marker.write_text(f"{previous}{subject}\n", encoding="utf-8")
        self.git("add", "history.txt")
        self.git("commit", "-m", subject)
        return self.git("rev-parse", "HEAD")

    def resolve(self, current_tag: str) -> tuple[subprocess.CompletedProcess[str], dict[str, str]]:
        output_path = self.repo / "github-output.txt"
        environment = os.environ.copy()
        environment["TAG_NAME"] = current_tag
        environment["GITHUB_OUTPUT"] = str(output_path)
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

    def test_uses_highest_lower_semantic_version_tag_on_linear_history(self) -> None:
        self.commit("Initial")
        self.git("tag", "v0.1.9")
        self.commit("Release Alveary v0.1.10")
        self.git("tag", "v0.1.10")
        self.git("tag", "not-a-release")
        self.commit("Next change")

        result, outputs = self.resolve("v0.1.11")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(outputs["tag"], "v0.1.10")
        self.assertEqual(outputs["notes_base"], "v0.1.10")

    def test_uses_current_history_release_commit_when_tag_is_not_ancestor(self) -> None:
        self.commit("Initial")
        self.git("tag", "v0.1.0")
        base_branch = self.git("branch", "--show-current")
        self.git("switch", "-c", "old-release-history")
        self.commit("Old v0.1.1 release")
        self.git("tag", "v0.1.1")
        self.commit("Old v0.1.2 release")
        self.git("tag", "v0.1.2")
        self.git("switch", base_branch)
        self.commit("Release Alveary v0.1.1")
        expected_notes_base = self.commit("Release Alveary v0.1.2")
        self.commit("Current patch change")

        result, outputs = self.resolve("v0.1.3")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(outputs["tag"], "v0.1.2")
        self.assertEqual(outputs["notes_base"], expected_notes_base)

    def test_ignores_current_tag_when_it_already_exists(self) -> None:
        self.commit("Initial")
        self.git("tag", "v1.0.0")
        self.commit("Current release")
        self.git("tag", "v1.0.1")

        result, outputs = self.resolve("v1.0.1")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(outputs["tag"], "v1.0.0")

    def test_fails_when_divergent_tag_has_no_current_history_release_commit(self) -> None:
        self.commit("Initial")
        self.git("switch", "-c", "old-release-history")
        self.commit("Old release")
        self.git("tag", "v2.0.0")
        self.git("switch", "main")
        self.commit("Current change")

        result, outputs = self.resolve("v2.0.1")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(outputs, {})
        self.assertIn("is not an ancestor of HEAD", result.stderr)


if __name__ == "__main__":
    unittest.main()
