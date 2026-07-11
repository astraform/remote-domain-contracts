#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQUIREMENTS_FILE="$ROOT_DIR/requirements-verify.txt"
VENV_DIR="${REMOTE_DOMAIN_VERIFY_VENV:-$ROOT_DIR/.venv/remote-domain-verifier}"
MODE="${1:-all}"

if [ "$MODE" != "all" ] && [ "$MODE" != "--contract-only" ]; then
  echo "Usage: scripts/verify-all.sh [--contract-only]" >&2
  exit 2
fi

if [ ! -f "$REQUIREMENTS_FILE" ]; then
  echo "Missing verifier dependency lock: $REQUIREMENTS_FILE" >&2
  exit 1
fi

if [ -n "${REMOTE_DOMAIN_VERIFY_BOOTSTRAP_PYTHON:-}" ]; then
  BOOTSTRAP_PYTHON="$REMOTE_DOMAIN_VERIFY_BOOTSTRAP_PYTHON"
elif command -v python3.12 >/dev/null 2>&1; then
  BOOTSTRAP_PYTHON="python3.12"
else
  BOOTSTRAP_PYTHON="python3"
fi

"$BOOTSTRAP_PYTHON" -c '
import sys
if sys.version_info < (3, 12):
    raise SystemExit("Remote-domain contract verification requires Python 3.12 or newer")
'

if [ ! -x "$VENV_DIR/bin/python" ]; then
  "$BOOTSTRAP_PYTHON" -m venv "$VENV_DIR"
fi

REQUIREMENTS_FINGERPRINT=$("$BOOTSTRAP_PYTHON" - "$REQUIREMENTS_FILE" <<'PY'
import hashlib
import pathlib
import sys

print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)
STAMP_FILE="$VENV_DIR/.requirements-verify.sha256"
INSTALLED_FINGERPRINT=""
if [ -f "$STAMP_FILE" ]; then
  INSTALLED_FINGERPRINT="$(tr -d '[:space:]' < "$STAMP_FILE")"
fi

if [ "$INSTALLED_FINGERPRINT" != "$REQUIREMENTS_FINGERPRINT" ] || \
   ! "$VENV_DIR/bin/python" -c 'import cryptography, jsonschema, rfc8785' >/dev/null 2>&1; then
  "$VENV_DIR/bin/python" -m pip install \
    --disable-pip-version-check \
    --requirement "$REQUIREMENTS_FILE"
  printf '%s\n' "$REQUIREMENTS_FINGERPRINT" > "$STAMP_FILE"
fi

REMOTE_DOMAIN_VERIFY_BOOTSTRAPPED=true \
REMOTE_DOMAIN_VERIFY_PYTHON="$VENV_DIR/bin/python" \
  "$ROOT_DIR/scripts/verify-remote-domain-contract.sh"

if [ "$MODE" = "all" ]; then
  "$VENV_DIR/bin/python" "$ROOT_DIR/scripts/verify-v1-backward-compatibility.py"
fi
