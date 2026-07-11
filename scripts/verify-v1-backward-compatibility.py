#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[1]
CONTRACT_DIR = ROOT / "remote-domain" / "v1"
BASELINE_TAG = "remote-domain-v1.0.0"
BASELINE_SCHEMA_PATH = "remote-domain/v1/schemas/remote-domain.schema.json"

FIXTURES = {
    "samples/manifest.response.json": "manifest",
    "samples/prepare.request.json": "prepareRequest",
    "samples/prepare.response.json": "prepareResponse",
    "samples/execute-work.request.json": "executeWorkRequest",
    "samples/execute-work.response.json": "executeWorkResponse",
    "profiles/opportunity-worker/samples/execute-work.replay.request.json": "executeWorkRequest",
    "profiles/opportunity-worker/samples/execute-work.replay.response.json": "executeWorkResponse",
    "samples/domain-system-work-window.request.json": "domainSystemWorkWindowRequest",
    "samples/domain-system-work-window.response.json": "domainSystemWorkWindowResponse",
    "samples/control-action.request.json": "controlActionRequest",
    "samples/control-action.response.json": "controlActionResponse",
    "samples/status.request.json": "statusRequest",
    "samples/status.response.json": "statusResponse",
    "samples/inspection.request.json": "inspectionRequest",
    "samples/inspection.response.json": "inspectionResponse",
    "samples/shutdown.request.json": "shutdownRequest",
    "samples/shutdown.response.json": "shutdownResponse",
    "samples/error-envelope.response.json": "errorEnvelope",
}


def tagged_schema() -> dict:
    try:
        payload = subprocess.check_output(
            ["git", "show", f"{BASELINE_TAG}:{BASELINE_SCHEMA_PATH}"],
            cwd=ROOT,
            text=True,
            stderr=subprocess.PIPE,
        )
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() if error.stderr else str(error)
        raise SystemExit(
            f"Could not read {BASELINE_SCHEMA_PATH} from {BASELINE_TAG}: {detail}. "
            "CI checkout must fetch tags."
        ) from error
    return json.loads(payload)


def main() -> int:
    schema = tagged_schema()
    Draft202012Validator.check_schema(schema)
    failures: list[str] = []
    for relative_path, definition in FIXTURES.items():
        fixture_path = CONTRACT_DIR / relative_path
        value = json.loads(fixture_path.read_text(encoding="utf-8"))
        fixture_schema = {
            "$schema": schema["$schema"],
            "$ref": f"#/$defs/{definition}",
            "$defs": schema["$defs"],
        }
        errors = sorted(
            Draft202012Validator(fixture_schema).iter_errors(value),
            key=lambda error: list(error.absolute_path),
        )
        failures.extend(
            f"{relative_path} is not backward-compatible with {BASELINE_TAG}: "
            f"{error.message} at /{'/'.join(map(str, error.absolute_path))}"
            for error in errors
        )

    if failures:
        for failure in failures:
            print(failure)
        return 1
    print(
        f"Verified {len(FIXTURES)} current remote-domain.v1 wire fixtures "
        f"against {BASELINE_TAG}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
