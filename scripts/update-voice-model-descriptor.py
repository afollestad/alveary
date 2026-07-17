#!/usr/bin/env python3
"""Regenerate Alveary's pinned voice-model descriptor from an exact HF commit."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path


REPOSITORY = "FluidInference/parakeet-unified-en-0.6b-coreml"
ENCODER = "parakeet_unified_encoder_streaming_70_2_2_int8.mlmodelc"
MODEL_DIRECTORIES = (
    "parakeet_unified_decoder.mlmodelc",
    ENCODER,
    "parakeet_unified_joint_decision_single_step.mlmodelc",
)
MODEL_FILES = (
    "analytics/coremldata.bin",
    "coremldata.bin",
    "model.mil",
    "weights/weight.bin",
)
REQUIRED_PATHS = tuple(
    sorted(
        ("metadata.json", "vocab.json")
        + tuple(f"{directory}/{filename}" for directory in MODEL_DIRECTORIES for filename in MODEL_FILES)
    )
)
REVISION_PATTERN = re.compile(r"^[0-9a-f]{40}$")
HEX_PATTERNS = {
    "gitBlobSHA1": re.compile(r"^[0-9a-f]{40}$"),
    "sha256": re.compile(r"^[0-9a-f]{64}$"),
}


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", required=True, help="Exact 40-character Hugging Face commit")
    parser.add_argument(
        "--output",
        type=Path,
        default=repo_root / "Alveary/Resources/VoiceInputModelDescriptor.json",
    )
    parser.add_argument(
        "--digest-output",
        type=Path,
        default=repo_root / "Config/VoiceInputModelDescriptor.sha256",
    )
    return parser.parse_args()


def fetch_metadata(revision: str) -> dict[str, object]:
    quoted_repository = urllib.parse.quote(REPOSITORY, safe="/")
    quoted_revision = urllib.parse.quote(revision, safe="")
    url = f"https://huggingface.co/api/models/{quoted_repository}/revision/{quoted_revision}?blobs=true"
    request = urllib.request.Request(url, headers={"User-Agent": "Alveary-voice-model-maintenance"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def artifact_from_sibling(sibling: dict[str, object]) -> dict[str, object]:
    path = sibling.get("rfilename")
    if not isinstance(path, str):
        raise ValueError("Hugging Face returned an artifact without a path")
    lfs = sibling.get("lfs")
    lfs_metadata = lfs if isinstance(lfs, dict) else {}
    size = sibling.get("size") or lfs_metadata.get("size")
    if not isinstance(size, int) or size <= 0:
        raise ValueError(f"{path}: missing or invalid size")

    lfs_digest = lfs_metadata.get("sha256") or lfs_metadata.get("oid")
    blob_digest = sibling.get("blobId")
    if isinstance(lfs_digest, str) and HEX_PATTERNS["sha256"].fullmatch(lfs_digest):
        digest_type = "sha256"
        digest = lfs_digest
    elif isinstance(blob_digest, str) and HEX_PATTERNS["gitBlobSHA1"].fullmatch(blob_digest):
        digest_type = "gitBlobSHA1"
        digest = blob_digest
    else:
        raise ValueError(f"{path}: missing a supported immutable digest")
    return {
        "digest": digest,
        "digestType": digest_type,
        "path": path,
        "size": size,
    }


def make_descriptor(metadata: dict[str, object], revision: str) -> dict[str, object]:
    observed_revision = metadata.get("sha")
    if observed_revision != revision:
        raise ValueError(f"Hugging Face resolved {revision} to unexpected revision {observed_revision}")
    siblings = metadata.get("siblings")
    if not isinstance(siblings, list):
        raise ValueError("Hugging Face returned no artifact inventory")

    selected: dict[str, dict[str, object]] = {}
    for raw_sibling in siblings:
        if not isinstance(raw_sibling, dict) or raw_sibling.get("rfilename") not in REQUIRED_PATHS:
            continue
        artifact = artifact_from_sibling(raw_sibling)
        path = str(artifact["path"])
        if path in selected:
            raise ValueError(f"Hugging Face returned duplicate artifact path {path}")
        selected[path] = artifact
    missing = sorted(set(REQUIRED_PATHS) - set(selected))
    unexpected = sorted(set(selected) - set(REQUIRED_PATHS))
    if missing or unexpected:
        raise ValueError(f"Artifact inventory mismatch; missing={missing}, unexpected={unexpected}")

    return {
        "artifacts": [selected[path] for path in REQUIRED_PATHS],
        "configuration": {
            "chunkFrames": 2,
            "encoder": ENCODER,
            "encoderPrecision": "int8",
            "leftFrames": 70,
            "rightFrames": 2,
        },
        "formatVersion": 1,
        "repository": REPOSITORY,
        "revision": revision,
    }


def main() -> int:
    args = parse_args()
    if not REVISION_PATTERN.fullmatch(args.revision):
        print("error: --revision must be an exact lowercase 40-character commit", file=sys.stderr)
        return 2
    try:
        descriptor = make_descriptor(fetch_metadata(args.revision), args.revision)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    data = (json.dumps(descriptor, indent=2, sort_keys=True) + "\n").encode()
    digest = hashlib.sha256(data).hexdigest()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.digest_output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    args.digest_output.write_text(f"{digest}\n", encoding="utf-8")
    print(f"wrote {args.output} ({len(descriptor['artifacts'])} artifacts, sha256 {digest})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
