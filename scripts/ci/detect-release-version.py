#!/usr/bin/env python3
import os
import re
import subprocess

VERSION_KEY = "MARKETING_VERSION"
BUILD_KEY = "CURRENT_PROJECT_VERSION"
VERSION_PATTERN = re.compile(rf'^\s*{VERSION_KEY}:\s*"?([^"\n]+)"?\s*$', re.MULTILINE)
BUILD_PATTERN = re.compile(rf'^\s*{BUILD_KEY}:\s*"?([^"\n]+)"?\s*$', re.MULTILINE)
SEMVER_PATTERN = re.compile(r"^\d+\.\d+\.\d+$")


def read_project_at(ref: str) -> str:
    if not ref or set(ref) == {"0"}:
        return ""
    result = subprocess.run(
        ["git", "show", f"{ref}:project.yml"],
        check=False,
        capture_output=True,
        text=True,
    )
    return result.stdout if result.returncode == 0 else ""


def release_tag_exists(tag: str) -> bool:
    result = subprocess.run(
        ["git", "ls-remote", "--exit-code", "--tags", "origin", f"refs/tags/{tag}"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if result.returncode == 0:
        return True
    if result.returncode == 2:
        return False
    raise SystemExit(f"error: failed to check release tag {tag}")


def extract(pattern: re.Pattern[str], text: str, name: str) -> str:
    match = pattern.search(text)
    if not match:
        raise SystemExit(f"error: project.yml is missing {name}")
    return match.group(1).strip()


current = open("project.yml", encoding="utf-8").read()
previous = read_project_at(os.environ.get("BEFORE_SHA", ""))
version = extract(VERSION_PATTERN, current, VERSION_KEY)
build = extract(BUILD_PATTERN, current, BUILD_KEY)
is_dry_run = os.environ.get("IS_DRY_RUN", "").lower() == "true"
tag = f"v{version}"
has_release_tag = False

previous_version = None
previous_build = None
if previous:
    previous_match = VERSION_PATTERN.search(previous)
    previous_version = previous_match.group(1).strip() if previous_match else None
    previous_build_match = BUILD_PATTERN.search(previous)
    previous_build = previous_build_match.group(1).strip() if previous_build_match else None

# Manual workflow runs are release dry runs even when this commit introduces
# version keys, so never allow workflow_dispatch to reach tag/release steps.
# Push-triggered releases require an existing previous version. This prevents
# publishing on the first commit that adds version keys, while still allowing a
# later push to publish the current version when its tag does not exist.
version_changed = previous_version is not None and previous_version != version
if not is_dry_run:
    has_release_tag = release_tag_exists(tag)
can_publish_current_version = previous_version is not None and not has_release_tag
if not is_dry_run and version_changed and has_release_tag:
    raise SystemExit(f"error: release tag {tag} already exists")

should_release = not is_dry_run and can_publish_current_version
# Every run builds. A push that cannot publish still produces a canary artifact
# so any commit on main can be downloaded and run, and it skips notarization
# because a notarytool round trip on every merge costs more than Gatekeeper
# acceptance is worth for a build that is never shipped.
mode = "dry-run" if is_dry_run else "release" if should_release else "canary"
# No mode skips the build anymore, so version validation is unconditional: a
# malformed value fails the push that introduced it rather than waiting for the
# bump that first tried to publish it.
if not SEMVER_PATTERN.fullmatch(version):
    raise SystemExit(f"error: version must be X.Y.Z, got {version!r}")
if not build.isdigit():
    raise SystemExit(f"error: build number must be an integer, got {build!r}")
if should_release and version_changed and previous_build and previous_build.isdigit() and int(build) <= int(previous_build):
    raise SystemExit(
        f"error: build number must increase from {previous_build} to a larger integer, got {build}"
    )

# Releases publish their ZIP as a release asset and upload no artifact. Canaries
# upload the bundle itself, and `actions/upload-artifact` roots the archive at
# the uploaded files' common ancestor, dropping the enclosing `.app` directory —
# so the artifact name is what re-wraps `Contents/` into a runnable bundle on
# download, and must be exactly the bundle name. That leaves the run as the only
# thing identifying a canary, which is why dry runs still carry version and
# commit: they upload a ZIP, whose name is free to describe it.
short_sha = os.environ.get("GITHUB_SHA", "")[:7]
if mode == "release":
    artifact_name = ""
elif mode == "canary":
    artifact_name = "Alveary.app"
else:
    artifact_name = f"Alveary-{mode}-{version}-{build}-{short_sha}"

# dSYMs are a plain ZIP in every mode, so their artifact name is free to describe
# the run. A release has none: it attaches them to the GitHub Release instead.
dsym_artifact_name = "" if mode == "release" else f"Alveary-{mode}-{version}-{build}-{short_sha}-dSYMs"

with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
    print(f"mode={mode}", file=output)
    print(f"version={version}", file=output)
    print(f"build={build}", file=output)
    print(f"tag={tag}", file=output)
    print(f"artifact_name={artifact_name}", file=output)
    print(f"dsym_artifact_name={dsym_artifact_name}", file=output)

if mode == "dry-run":
    print(f"Preparing dry run for v{version} (build {build})")
elif mode == "release":
    print(f"Preparing release v{version} (build {build})")
else:
    print(f"Preparing canary build for v{version} (build {build})")
