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
should_build = should_release or is_dry_run
if should_build and not SEMVER_PATTERN.fullmatch(version):
    raise SystemExit(f"error: version must be X.Y.Z, got {version!r}")
if should_build and not build.isdigit():
    raise SystemExit(f"error: build number must be an integer, got {build!r}")
if should_release and version_changed and previous_build and previous_build.isdigit() and int(build) <= int(previous_build):
    raise SystemExit(
        f"error: build number must increase from {previous_build} to a larger integer, got {build}"
    )

with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
    print(f"should_build={'true' if should_build else 'false'}", file=output)
    print(f"should_release={'true' if should_release else 'false'}", file=output)
    print(f"version={version}", file=output)
    print(f"build={build}", file=output)
    print(f"tag={tag}", file=output)

if is_dry_run:
    print(f"Preparing dry run for v{version} (build {build})")
elif should_release:
    print(f"Preparing release v{version} (build {build})")
else:
    print("No release build requested.")
