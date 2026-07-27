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
COMMIT_LINK = f"[`abc1234`](https://github.com/{REPOSITORY}/commit/abc1234)"
SECOND_COMMIT_LINK = f"[`def5678`](https://github.com/{REPOSITORY}/commit/def5678)"
# A well-formed group, for cases where something other than the bullet shape is under test.
VALID_GROUP = (
    "- **App updates**\n"
    f"  - *Update history is shown for every newer release* ({COMMIT_LINK}) by @author\n"
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

    def test_accepts_grouped_bullets_and_footer(self) -> None:
        self.commit("Add update history")
        notes = (
            "- **App updates**\n"
            f"  - *Update history is shown for every newer release* ({COMMIT_LINK}, {SECOND_COMMIT_LINK}) by @author\n"
            f"  - *Release notes keep their repository links interactive* ({COMMIT_LINK}) by @author\n"
            f"\n{FULL_CHANGELOG}\n"
        )

        result = self.run_generator(generated_notes=notes)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.repo / ".release-notes.md").read_text(encoding="utf-8"), notes)

    def test_accepts_multiple_groups(self) -> None:
        self.commit("Add update history")
        notes = (
            "- **App updates**\n"
            f"  - *Update history is shown for every newer release* ({COMMIT_LINK}) by @author\n"
            "- **Other**\n"
            f"  - *Internal maintenance and build improvements* ({SECOND_COMMIT_LINK}) by @author\n"
            f"\n{FULL_CHANGELOG}\n"
        )

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
        notes = f"## What's changed\n\n{VALID_GROUP}\n{FULL_CHANGELOG}\n"

        result = self.run_generator(generated_notes=notes)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the required Markdown format", result.stderr)

    def test_rejects_nonempty_range_without_bullets(self) -> None:
        self.commit("Add update history")

        result = self.run_generator(generated_notes=f"{FULL_CHANGELOG}\n")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the required Markdown format", result.stderr)

    def test_rejects_flat_ungrouped_bullet(self) -> None:
        self.commit("Add update history")
        notes = f"- Add update history ({COMMIT_LINK}) by @author\n\n{FULL_CHANGELOG}\n"

        result = self.run_generator(generated_notes=notes)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the required Markdown format", result.stderr)
        # Rejections happen after the release is already signed and notarized, so the
        # diagnostics have to say what was actually generated.
        self.assertIn("groups: 0, children: 0", result.stderr)
        self.assertIn("- Add update history", result.stderr)

    def test_rejects_child_before_group(self) -> None:
        self.commit("Add update history")
        notes = (
            f"  - *Update history is shown* ({COMMIT_LINK}) by @author\n"
            "- **App updates**\n"
            f"  - *Release notes stay interactive* ({SECOND_COMMIT_LINK}) by @author\n"
            f"\n{FULL_CHANGELOG}\n"
        )

        result = self.run_generator(generated_notes=notes)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the required Markdown format", result.stderr)

    def test_rejects_group_without_children(self) -> None:
        self.commit("Add update history")
        notes = f"- **App updates**\n\n{FULL_CHANGELOG}\n"

        result = self.run_generator(generated_notes=notes)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the required Markdown format", result.stderr)

    def test_rejects_empty_group_before_next_group(self) -> None:
        self.commit("Add update history")
        notes = f"- **App updates**\n{VALID_GROUP}\n{FULL_CHANGELOG}\n"

        result = self.run_generator(generated_notes=notes)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the required Markdown format", result.stderr)

    def test_rejects_non_italic_child(self) -> None:
        self.commit("Add update history")
        notes = (
            "- **App updates**\n"
            f"  - Update history is shown ({COMMIT_LINK}) by @author\n"
            f"\n{FULL_CHANGELOG}\n"
        )

        result = self.run_generator(generated_notes=notes)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the required Markdown format", result.stderr)

    def test_rejects_child_without_commit_link(self) -> None:
        self.commit("Add update history")
        notes = (
            "- **App updates**\n"
            "  - *Update history is shown* by @author\n"
            f"\n{FULL_CHANGELOG}\n"
        )

        result = self.run_generator(generated_notes=notes)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the required Markdown format", result.stderr)

    def test_rejects_duplicate_footer(self) -> None:
        self.commit("Add update history")
        notes = f"{VALID_GROUP}\n{FULL_CHANGELOG}\n{FULL_CHANGELOG}\n"

        result = self.run_generator(generated_notes=notes)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the required Markdown format", result.stderr)

    def test_rejects_unexpected_workspace_modification(self) -> None:
        self.commit("Add update history")
        notes = f"{VALID_GROUP}\n{FULL_CHANGELOG}\n"

        result = self.run_generator(
            generated_notes=notes,
            create_unexpected_file=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("modified unexpected workspace files", result.stderr)


if __name__ == "__main__":
    unittest.main()
