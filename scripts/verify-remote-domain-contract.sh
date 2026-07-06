#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT_DIR="$ROOT_DIR/remote-domain/v1"

if [ ! -d "$CONTRACT_DIR" ]; then
  echo "Missing contract directory: $CONTRACT_DIR" >&2
  exit 1
fi

python3 - "$CONTRACT_DIR" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

contract_dir = Path(sys.argv[1]).resolve()
version = (contract_dir / "VERSION").read_text(encoding="utf-8").strip()
manifest_path = contract_dir / "manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

expected = {
    "bundleId": "remote-domain.v1",
    "version": version,
    "releaseArtifact": "remote-domain.v1.zip",
}
failures = [
    f"{key}={manifest.get(key)!r}, expected {expected_value!r}"
    for key, expected_value in expected.items()
    if manifest.get(key) != expected_value
]

required_paths = [
    "README.md",
    "VERSION",
    "manifest.json",
    "openapi/remote-domain.yaml",
    "schemas/remote-domain.schema.json",
    "docs/remote-domain-protocol-v1.md",
]
missing_paths = [path for path in required_paths if not (contract_dir / path).exists()]
if missing_paths:
    failures.append("missing required path(s): " + ", ".join(missing_paths))

blocked_fragments = [
    "platform-contracts",
    "docs/architecture",
    "astraform/platform",
    "digital-twin-platform",
]

def manifest_list(name: str) -> list[str]:
    value = manifest.get(name)
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        failures.append(f"{name} must be a list of strings")
        return []
    return value

def stays_under_contract_dir(path: Path) -> bool:
    try:
        path.resolve().relative_to(contract_dir)
    except ValueError:
        return False
    return True

def resolve_manifest_path(path: str) -> list[Path]:
    if path.startswith("remote-domain/v1/"):
        relative = path.removeprefix("remote-domain/v1/")
    else:
        failures.append(f"manifest path must start with remote-domain/v1/: {path}")
        return []

    relative_path = Path(relative)
    if relative_path.is_absolute() or ".." in relative_path.parts:
        failures.append(f"manifest path must stay under remote-domain/v1/: {path}")
        return []

    if "*" in relative:
        matches = sorted(contract_dir.glob(relative))
        if not matches:
            failures.append(f"manifest glob did not match any files: {path}")
            return []
        for match in matches:
            if not stays_under_contract_dir(match):
                failures.append(f"manifest glob resolved outside remote-domain/v1/: {path} -> {match}")
        return matches

    resolved = contract_dir / relative_path
    if not stays_under_contract_dir(resolved):
        failures.append(f"manifest path resolved outside remote-domain/v1/: {path}")
        return []
    if not resolved.exists():
        failures.append(f"manifest path does not exist: {path}")
        return []
    return [resolved]

for field_name in ["canonicalSources", "partnerContents"]:
    for entry in manifest_list(field_name):
        for fragment in blocked_fragments:
            if fragment in entry:
                failures.append(f"{field_name} contains private/internal path fragment {fragment!r}: {entry}")
        resolve_manifest_path(entry)

for json_path in sorted(contract_dir.rglob("*.json")):
    try:
        json.loads(json_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        failures.append(f"{json_path.relative_to(contract_dir)} is invalid JSON: {error}")

if failures:
    for failure in failures:
        print(failure, file=sys.stderr)
    raise SystemExit(1)

print(f"Verified remote-domain.v1 contract metadata for {version}")
PY
