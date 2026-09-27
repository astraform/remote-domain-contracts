#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[1]
CONTRACT_DIR = ROOT / "remote-domain" / "v1"
BASELINE_TAGS = ("remote-domain-v1.0.4",)
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


def tagged_schema(tag: str) -> dict:
    try:
        payload = subprocess.check_output(
            ["git", "show", f"{tag}:{BASELINE_SCHEMA_PATH}"],
            cwd=ROOT,
            text=True,
            stderr=subprocess.PIPE,
        )
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() if error.stderr else str(error)
        raise SystemExit(
            f"Could not read {BASELINE_SCHEMA_PATH} from {tag}: {detail}. "
            "CI checkout must fetch tags."
        ) from error
    return json.loads(payload)


def main() -> int:
    failures: list[str] = []
    current_schema = json.loads(
        (CONTRACT_DIR / "schemas/remote-domain.schema.json").read_text(encoding="utf-8")
    )
    Draft202012Validator.check_schema(current_schema)
    checked_fixtures = 0
    for baseline_tag in BASELINE_TAGS:
        schema = tagged_schema(baseline_tag)
        Draft202012Validator.check_schema(schema)
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
                f"{relative_path} is not backward-compatible with {baseline_tag}: "
                f"{error.message} at /{'/'.join(map(str, error.absolute_path))}"
                for error in errors
            )
            checked_fixtures += 1

        if "customerDecisionTrigger" in schema.get("$defs", {}):
            legacy_trigger_validator = validator(schema, "customerDecisionTrigger")
            current_trigger_validator = validator(current_schema, "customerDecisionTrigger")
            for label, probe in legacy_trigger_probes().items():
                old_errors = list(legacy_trigger_validator.iter_errors(probe))
                if old_errors:
                    failures.append(
                        f"compatibility probe {label!r} is not valid under {baseline_tag}: "
                        f"{old_errors[0].message}"
                    )
                    continue
                new_errors = list(current_trigger_validator.iter_errors(probe))
                if new_errors:
                    failures.append(
                        f"old-valid compatibility probe {label!r} is rejected by the current v1 schema: "
                        f"{new_errors[0].message}"
                    )

    if failures:
        for failure in failures:
            print(failure)
        return 1
    print(
        f"Verified {checked_fixtures} current remote-domain.v1 fixture/tag combinations "
        f"and old-valid trigger probes against {', '.join(BASELINE_TAGS)}"
    )
    return 0


def validator(schema: dict, definition: str) -> Draft202012Validator:
    return Draft202012Validator({
        "$schema": schema["$schema"],
        "$ref": f"#/$defs/{definition}",
        "$defs": schema["$defs"],
    })


def legacy_trigger_probes() -> dict[str, dict]:
    base = {
        "schemaVersion": "customer_decision_trigger.v1",
        "triggerId": "statement-close-1",
        "triggerType": "statement_close",
        "triggerRef": "banking|statement|2026-04",
        "scheduledForEpochMs": 1_777_000_000_000,
        "priority": "NORMAL",
        "reason": "Credit card statement closed",
        "payload": {"accountId": "acct-1"},
        "evidenceRefs": ["banking|statement|2026-04"],
    }
    return {
        "256-character triggerId": {**base, "triggerId": "x" * 256},
        "65-character legacy priority": {**base, "priority": "x" * 65},
        "65 evidence references": {**base, "evidenceRefs": ["ref"] * 65},
        "257-value payload collection": {**base, "payload": {"facts": list(range(257))}},
        "extreme signed-64 timestamp": {**base, "scheduledForEpochMs": 9_223_372_036_854_775_807},
        "NUL-bearing trigger reference": {**base, "triggerRef": "statement\u0000close"},
    }


if __name__ == "__main__":
    raise SystemExit(main())
