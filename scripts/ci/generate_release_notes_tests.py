#!/usr/bin/env python3
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Optional


SCRIPT_PATH = Path(__file__).with_name("generate-release-notes.sh")
REPOSITORY = "afollestad/alveary"
PREVIOUS_TAG = "v0.1.0"
TAG_NAME = "v0.1.1"
FULL_CHANGELOG = (
    f"**Full Changelog**: https://github.com/{REPOSITORY}/compare/"
    f"{PREVIOUS_TAG}...{TAG_NAME}"
)


class GenerateReleaseNotesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.fake_directory = tempfile.TemporaryDirectory()
        self.repo = Path(self.temporary_directory.name)
        self.git("init", "-b", "main")
        self.git("config", "user.email", "tests@example.com")
        self.git("config", "user.name", "Release Tests")
        self.base_commit = self.commit("Initial")

    def tearDown(self) -> None:
        self.fake_directory.cleanup()
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

    def run_generator(
        self,
        generated_notes: Optional[str] = None,
        create_unexpected_file: bool = False,
        release_notes_base: Optional[str] = None,
    ) -> subprocess.CompletedProcess[str]:
        fake_copilot = Path(self.fake_directory.name) / "copilot"
        fake_copilot.write_text(
            "#!/bin/bash\n"
            "set -eu\n"
            "printf '%s' \"$FAKE_RELEASE_NOTES\" > \"$RELEASE_NOTES_PATH\"\n"
            "if [[ \"${CREATE_UNEXPECTED_FILE:-false}\" == \"true\" ]]; then\n"
            "  printf 'unexpected\\n' > unexpected.txt\n"
            "fi\n",
            encoding="utf-8",
        )
        fake_copilot.chmod(0o755)

        environment = os.environ.copy()
        environment.update(
            {
                "COPILOT_EXECUTABLE": str(fake_copilot),
                "CREATE_UNEXPECTED_FILE": str(create_unexpected_file).lower(),
                "FAKE_RELEASE_NOTES": generated_notes or "",
                "GITHUB_REPOSITORY": REPOSITORY,
                "PREVIOUS_TAG": PREVIOUS_TAG,
                "RELEASE_NOTES_BASE": release_notes_base or self.base_commit,
                "TAG_NAME": TAG_NAME,
                "RELEASE_NOTES_PATH": str(self.repo / ".release-notes.md"),
            }
        )
        return subprocess.run(
            [str(SCRIPT_PATH)],
            cwd=self.repo,
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )

    def test_accepts_header_free_bullets_and_footer(self) -> None:
        self.commit("Add update history")
        notes = f"- Add update history ([`abc123`](https://example.com)) by @author.\n\n{FULL_CHANGELOG}\n"

        result = self.run_generator(generated_notes=notes)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.repo / ".release-notes.md").read_text(encoding="utf-8"), notes)

    def test_zero_candidate_commits_writes_only_footer(self) -> None:
        result = self.run_generator(release_notes_base="HEAD")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            (self.repo / ".release-notes.md").read_text(encoding="utf-8"),
            f"{FULL_CHANGELOG}\n",
        )

    def test_rejects_whats_changed_heading(self) -> None:
        self.commit("Add update history")
        notes = f"## What's changed\n\n- Add update history\n\n{FULL_CHANGELOG}\n"

        result = self.run_generator(generated_notes=notes)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the required Markdown format", result.stderr)

    def test_rejects_nonempty_range_without_bullets(self) -> None:
        self.commit("Add update history")

        result = self.run_generator(generated_notes=f"{FULL_CHANGELOG}\n")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the required Markdown format", result.stderr)

    def test_rejects_duplicate_footer(self) -> None:
        self.commit("Add update history")
        notes = f"- Add update history\n\n{FULL_CHANGELOG}\n{FULL_CHANGELOG}\n"

        result = self.run_generator(generated_notes=notes)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the required Markdown format", result.stderr)

    def test_rejects_unexpected_workspace_modification(self) -> None:
        self.commit("Add update history")
        notes = f"- Add update history\n\n{FULL_CHANGELOG}\n"

        result = self.run_generator(
            generated_notes=notes,
            create_unexpected_file=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("modified unexpected workspace files", result.stderr)


if __name__ == "__main__":
    unittest.main()
