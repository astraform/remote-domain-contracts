#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bundle="remote-domain"
if [ "${1:-}" = "--bundle" ]; then
  bundle="${2:-}"
  shift 2
fi
case "$bundle" in
  remote-domain) source_path="remote-domain/v1"; bundle_id="remote-domain.v1"; output_name="remote-domain-contract" ;;
  platform-api) source_path="platform-api/v1"; bundle_id="platform-api"; output_name="platform-api-contract" ;;
  *) echo "Usage: scripts/package-remote-domain-contract.sh [--bundle remote-domain|platform-api] [output-directory]" >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
  echo "Expected at most one output directory" >&2
  exit 2
fi
SOURCE_DIR="$ROOT_DIR/$source_path"
OUT_DIR="${1:-$ROOT_DIR/build/$output_name}"
BUNDLE_DIR="$OUT_DIR/$bundle_id"
ZIP_PATH="$OUT_DIR/$bundle_id.zip"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to create the contract archive" >&2
  exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
  echo "Missing contract source directory: $SOURCE_DIR" >&2
  exit 1
fi

rm -rf "$BUNDLE_DIR" "$ZIP_PATH"
mkdir -p "$BUNDLE_DIR"
cp -R "$SOURCE_DIR"/. "$BUNDLE_DIR"/

python3 - "$BUNDLE_DIR" "$ZIP_PATH" <<'PY'
from __future__ import annotations

import sys
import zipfile
from pathlib import Path

bundle_dir = Path(sys.argv[1])
zip_path = Path(sys.argv[2])
root_name = bundle_dir.name
fixed_timestamp = (1980, 1, 1, 0, 0, 0)

with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(bundle_dir.rglob("*")):
        # Workstation metadata is not part of the portable contract.
        if not path.is_file() or path.name == ".DS_Store":
            continue
        relative_path = path.relative_to(bundle_dir).as_posix()
        info = zipfile.ZipInfo(f"{root_name}/{relative_path}", fixed_timestamp)
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = (0o644 & 0xFFFF) << 16
        archive.writestr(info, path.read_bytes())
PY

echo "Wrote $BUNDLE_DIR"
echo "Wrote $ZIP_PATH"
