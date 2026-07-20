#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT_DIR="$ROOT_DIR/remote-domain/v1"
PYTHON_BIN="${REMOTE_DOMAIN_VERIFY_PYTHON:-python3}"

if [ ! -d "$CONTRACT_DIR" ]; then
  echo "Missing contract directory: $CONTRACT_DIR" >&2
  exit 1
fi

if [ "${REMOTE_DOMAIN_VERIFY_BOOTSTRAPPED:-false}" != "true" ]; then
  exec "$ROOT_DIR/scripts/verify-all.sh" --contract-only
fi
if ! "$PYTHON_BIN" -c 'import cryptography, jsonschema, rfc8785' >/dev/null 2>&1; then
  echo "Verifier dependencies are unavailable in $PYTHON_BIN" >&2
  exit 1
fi

"$PYTHON_BIN" - "$CONTRACT_DIR" <<'PY'
from __future__ import annotations

import json
import hashlib
import base64
import math
import rfc8785
from decimal import Decimal
from cryptography.hazmat.primitives import serialization
from jsonschema import Draft202012Validator
import sys
from pathlib import Path

contract_dir = Path(sys.argv[1]).resolve()
version = (contract_dir / "VERSION").read_text(encoding="utf-8").strip()
manifest_path = contract_dir / "manifest.json"

def reject_non_json_number(value: str) -> object:
    raise ValueError(f"non-JSON numeric token {value}")

def reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON object key {key!r}")
        result[key] = value
    return result

def strict_json_loads(payload: str | bytes, source: str) -> object:
    if isinstance(payload, bytes):
        payload = payload.decode("utf-8", errors="strict")
    decoder = json.JSONDecoder(
        object_pairs_hook=reject_duplicate_keys,
        parse_float=Decimal,
        parse_int=int,
        parse_constant=reject_non_json_number,
    )
    start = 0
    while start < len(payload) and payload[start] in " \t\r\n":
        start += 1
    try:
        value, end = decoder.raw_decode(payload, start)
    except json.JSONDecodeError as error:
        raise ValueError(f"{source} is invalid JSON: {error}") from error
    if any(character not in " \t\r\n" for character in payload[end:]):
        raise ValueError(f"{source} contains trailing content after its JSON value")
    return value

manifest = strict_json_loads(manifest_path.read_bytes(), "manifest.json")

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

for label, payload in {
    "duplicate keys": b'{"value":1,"value":2}',
    "trailing JSON": b'{"value":1}{"value":2}',
    "non-finite NaN": b'{"value":NaN}',
    "non-finite Infinity": b'{"value":Infinity}',
    "malformed UTF-8": b'{"value":"\xff"}',
}.items():
    try:
        strict_json_loads(payload, f"strict-loader regression: {label}")
    except (UnicodeDecodeError, ValueError):
        continue
    failures.append(f"strict JSON loader must reject {label}")

required_paths = [
    "README.md",
    "VERSION",
    "manifest.json",
    "openapi/remote-domain.yaml",
    "schemas/remote-domain.schema.json",
    "docs/remote-domain-protocol-v1.md",
    "docs/opportunity-worker-conformance-profile.md",
    "profiles/opportunity-worker/samples/execute-work.replay.request.json",
    "profiles/opportunity-worker/samples/execute-work.replay.response.json",
    "profiles/opportunity-worker/samples/opportunity-worker-profile.json",
    "profiles/opportunity-worker/samples/opportunity-worker-conformance-report.json",
    "profiles/opportunity-worker/samples/opportunity-worker-attestation.dsse.json",
    "profiles/opportunity-worker/samples/rfc8785-ijson-number-vectors.json",
    "profiles/opportunity-worker/schemas/opportunity-worker-profile.schema.json",
    "profiles/opportunity-worker/schemas/opportunity-worker-conformance-report.schema.json",
    "profiles/opportunity-worker/schemas/opportunity-worker-attestation.schema.json",
    "profiles/opportunity-worker/keys/sample-ed25519-public-key.spki.b64",
    "docs/scenario-lab-finalization-v2-profile.md",
    "profiles/scenario-lab-finalization-v2/samples/scenario-lab-finalization-profile.json",
    "profiles/scenario-lab-finalization-v2/samples/finalize.request.json",
    "profiles/scenario-lab-finalization-v2/samples/finalize.contradictory.request.json",
    "profiles/scenario-lab-finalization-v2/samples/finalization-receipt.prepared.json",
    "profiles/scenario-lab-finalization-v2/samples/finalization-receipt.published.json",
    "profiles/scenario-lab-finalization-v2/samples/finalization-receipt.cancelled.json",
    "profiles/scenario-lab-finalization-v2/samples/finalized-summary.json",
    "profiles/scenario-lab-finalization-v2/samples/conformance-vectors.json",
    "profiles/scenario-lab-finalization-v2/schemas/scenario-lab-finalization-profile.schema.json",
    "profiles/scenario-lab-finalization-v2/schemas/scenario-lab-finalization-receipt.schema.json",
    "profiles/scenario-lab-finalization-v2/schemas/scenario-lab-finalization-conformance-vectors.schema.json",
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
        strict_json_loads(
            json_path.read_bytes(),
            json_path.relative_to(contract_dir).as_posix(),
        )
    except (UnicodeDecodeError, ValueError) as error:
        failures.append(f"{json_path.relative_to(contract_dir)} is invalid JSON: {error}")

first_request_path = contract_dir / "samples/execute-work.request.json"
first_response_path = contract_dir / "samples/execute-work.response.json"
replay_request_path = contract_dir / "profiles/opportunity-worker/samples/execute-work.replay.request.json"
replay_response_path = contract_dir / "profiles/opportunity-worker/samples/execute-work.replay.response.json"
worker_profile_path = contract_dir / "profiles/opportunity-worker/samples/opportunity-worker-profile.json"
worker_report_path = contract_dir / "profiles/opportunity-worker/samples/opportunity-worker-conformance-report.json"
worker_attestation_path = contract_dir / "profiles/opportunity-worker/samples/opportunity-worker-attestation.dsse.json"
number_vectors_path = contract_dir / "profiles/opportunity-worker/samples/rfc8785-ijson-number-vectors.json"
worker_public_key_path = contract_dir / "profiles/opportunity-worker/keys/sample-ed25519-public-key.spki.b64"
worker_profile_schema_path = contract_dir / "profiles/opportunity-worker/schemas/opportunity-worker-profile.schema.json"
worker_report_schema_path = contract_dir / "profiles/opportunity-worker/schemas/opportunity-worker-conformance-report.schema.json"
worker_attestation_schema_path = contract_dir / "profiles/opportunity-worker/schemas/opportunity-worker-attestation.schema.json"
finalization_profile_path = contract_dir / "profiles/scenario-lab-finalization-v2/samples/scenario-lab-finalization-profile.json"
finalization_request_path = contract_dir / "profiles/scenario-lab-finalization-v2/samples/finalize.request.json"
contradictory_finalization_request_path = contract_dir / "profiles/scenario-lab-finalization-v2/samples/finalize.contradictory.request.json"
prepared_receipt_path = contract_dir / "profiles/scenario-lab-finalization-v2/samples/finalization-receipt.prepared.json"
published_receipt_path = contract_dir / "profiles/scenario-lab-finalization-v2/samples/finalization-receipt.published.json"
cancelled_receipt_path = contract_dir / "profiles/scenario-lab-finalization-v2/samples/finalization-receipt.cancelled.json"
finalized_summary_path = contract_dir / "profiles/scenario-lab-finalization-v2/samples/finalized-summary.json"
finalization_vectors_path = contract_dir / "profiles/scenario-lab-finalization-v2/samples/conformance-vectors.json"
finalization_profile_schema_path = contract_dir / "profiles/scenario-lab-finalization-v2/schemas/scenario-lab-finalization-profile.schema.json"
finalization_receipt_schema_path = contract_dir / "profiles/scenario-lab-finalization-v2/schemas/scenario-lab-finalization-receipt.schema.json"
finalization_vectors_schema_path = contract_dir / "profiles/scenario-lab-finalization-v2/schemas/scenario-lab-finalization-conformance-vectors.schema.json"
manifest_sample_path = contract_dir / "samples/manifest.response.json"
schema_path = contract_dir / "schemas/remote-domain.schema.json"
if schema_path.is_file():
    contract_schema = strict_json_loads(schema_path.read_bytes(), schema_path.name)
    tool_properties = (
        contract_schema.get("$defs", {})
        .get("manifest", {})
        .get("properties", {})
        .get("capabilities", {})
        .get("properties", {})
        .get("tools", {})
        .get("items", {})
        .get("properties", {})
    )
    if "effectType" in tool_properties:
        failures.append("remote-domain.v1 tool descriptors must not expose effectType")
    trigger_schema = {
        "$ref": "#/$defs/customerDecisionTrigger",
        "$defs": contract_schema.get("$defs", {}),
    }
    trigger_validator = Draft202012Validator(trigger_schema)
    valid_trigger = {
        "schemaVersion": "customer_decision_trigger.v1",
        "triggerId": "statement-close-1",
        "triggerType": "statement_close",
        "triggerRef": "banking|statement|2026-04",
        "scheduledForEpochMs": 1777000000000,
        "priority": "NORMAL",
        "schedulingPriority": "NORMAL",
        "reason": "Credit card statement closed",
        "payload": {"accountId": "acct-1"},
        "evidenceRefs": ["banking|statement|2026-04"],
    }
    if list(trigger_validator.iter_errors(valid_trigger)):
        failures.append("valid customer decision trigger must pass the public schema")
    legacy_priority_trigger = {**valid_trigger, "priority": "DOMAIN_SEVERE"}
    legacy_priority_trigger.pop("schedulingPriority", None)
    if list(trigger_validator.iter_errors(legacy_priority_trigger)):
        failures.append("legacy v1 domain priority must remain wire-compatible")
    invalid_triggers = {
        "nested prompt field": {
            **valid_trigger,
            "payload": {"facts": [[{"chainOfThought": "hidden"}]]},
        },
        "unknown scheduling priority": {**valid_trigger, "schedulingPriority": "DOMAIN_SEVERE"},
    }
    for label, invalid_trigger in invalid_triggers.items():
        if not list(trigger_validator.iter_errors(invalid_trigger)):
            failures.append(f"customer decision trigger schema must reject {label}")
    legacy_wire_compatibility_triggers = {
        "256-character trigger identifier": {**valid_trigger, "triggerId": "x" * 256},
        "65 evidence references": {**valid_trigger, "evidenceRefs": ["ref"] * 65},
        "257-value payload collection": {**valid_trigger, "payload": {"facts": list(range(257))}},
        "65-character legacy priority": {**valid_trigger, "priority": "x" * 65},
    }
    for label, legacy_trigger in legacy_wire_compatibility_triggers.items():
        legacy_trigger.pop("schedulingPriority", None)
        if list(trigger_validator.iter_errors(legacy_trigger)):
            failures.append(f"remote-domain.v1 wire compatibility must preserve {label}")
if manifest_sample_path.is_file():
    manifest_sample = strict_json_loads(manifest_sample_path.read_bytes(), manifest_sample_path.name)
    if schema_path.is_file():
        manifest_validator = Draft202012Validator({
            "$ref": "#/$defs/manifest",
            "$defs": contract_schema.get("$defs", {}),
        })
        if list(manifest_validator.iter_errors(manifest_sample)):
            failures.append("manifest sample must pass the public schema")
        blank_content_type_manifest = strict_json_loads(
            json.dumps(manifest_sample),
            "manifest sample clone",
        )
        blank_content_type_manifest["transport"]["contentType"] = ""
        if not list(manifest_validator.iter_errors(blank_content_type_manifest)):
            failures.append("manifest schema must reject a blank transport contentType")
    for index, tool in enumerate(manifest_sample.get("capabilities", {}).get("tools", [])):
        if not isinstance(tool, dict) or "effectType" in tool:
            failures.append(f"manifest sample tool[{index}] must remain remote-domain.v1 compatible")
if (
    first_request_path.is_file()
    and first_response_path.is_file()
    and replay_request_path.is_file()
    and replay_response_path.is_file()
):
    first_request = strict_json_loads(first_request_path.read_bytes(), first_request_path.name)
    first_response = strict_json_loads(first_response_path.read_bytes(), first_response_path.name)
    replay_request = strict_json_loads(replay_request_path.read_bytes(), replay_request_path.name)
    replay_response = strict_json_loads(replay_response_path.read_bytes(), replay_response_path.name)
    first_work = first_request["payload"]["turnContext"]["dueWork"][0]
    replay_work = replay_request["payload"]["turnContext"]["dueWork"][0]
    if first_request["requestId"] == replay_request["requestId"]:
        failures.append("execute-work replay sample must use a new requestId")
    if first_request["idempotencyKey"] == replay_request["idempotencyKey"]:
        failures.append("execute-work replay sample must use a new transport idempotencyKey")
    if first_work["workId"] != replay_work["workId"]:
        failures.append("execute-work replay sample must preserve the stable workId")
    if first_work["attemptNumber"] == replay_work["attemptNumber"]:
        failures.append("execute-work replay sample must use a new attemptNumber")
    if first_response.get("nextState") != replay_request.get("state"):
        failures.append(
            "execute-work replay request state must exactly equal the first response nextState"
        )
    tool_result = replay_response.get("result", {}).get("toolResult", {})
    evidence_events = replay_response.get("result", {}).get("evidenceEvents", [])
    if tool_result.get("idempotentReplay") is not True:
        failures.append("execute-work replay response must set idempotentReplay=true")
    if replay_response.get("nextState") != replay_request.get("state"):
        failures.append("execute-work replay response must preserve canonical state")
    if not any(
        event.get("eventType") == "remote_domain_tool_effect_replayed"
        and event.get("outcome") == "NOOP"
        and event.get("workId") == first_work["workId"]
        for event in evidence_events
        if isinstance(event, dict)
    ):
        failures.append("execute-work replay response must include replay NOOP evidence")

MAX_IJSON_SAFE_INTEGER = 9_007_199_254_740_991

def require_interoperable_numbers(value: object, path: str = "$") -> None:
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return
    if isinstance(value, int):
        if abs(value) > MAX_IJSON_SAFE_INTEGER:
            raise ValueError(f"unsafe I-JSON integer at {path}")
        return
    if isinstance(value, Decimal):
        binary64 = float(value)
        if not math.isfinite(binary64):
            raise ValueError(f"non-finite I-JSON number at {path}")
        if value != 0 and binary64 == 0.0:
            raise ValueError(f"underflowing I-JSON number at {path}")
        if binary64.is_integer() and abs(binary64) > MAX_IJSON_SAFE_INTEGER:
            raise ValueError(f"unsafe I-JSON integer at {path}")
        canonical_binary64 = Decimal(rfc8785.dumps(binary64).decode("utf-8"))
        if value != canonical_binary64:
            raise ValueError(f"inexact RFC 8785 binary64 number at {path}")
        return
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError(f"non-finite I-JSON number at {path}")
        if value.is_integer() and abs(value) > MAX_IJSON_SAFE_INTEGER:
            raise ValueError(f"unsafe I-JSON integer at {path}")
        return
    if isinstance(value, dict):
        for key, nested in value.items():
            require_interoperable_numbers(nested, f"{path}.{key}")
        return
    if isinstance(value, (list, tuple)):
        for index, nested in enumerate(value):
            require_interoperable_numbers(nested, f"{path}[{index}]")

def canonical_digest(value: object) -> str:
    require_interoperable_numbers(value)
    canonical = rfc8785.dumps(normalize_interoperable_numbers(value))
    return "sha256:" + hashlib.sha256(canonical).hexdigest()

def embeds_exact_finalize_fixture(vectors: object, fixture: object) -> bool:
    return isinstance(vectors, dict) and vectors.get("finalizeRequest") == fixture

def normalize_interoperable_numbers(value: object) -> object:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, dict):
        return {key: normalize_interoperable_numbers(nested) for key, nested in value.items()}
    if isinstance(value, list):
        return [normalize_interoperable_numbers(nested) for nested in value]
    return value

if number_vectors_path.is_file():
    number_vectors = strict_json_loads(number_vectors_path.read_bytes(), number_vectors_path.name)
    for vector in number_vectors.get("vectors", []):
        try:
            wire_json = vector.get("json")
            if not isinstance(wire_json, str):
                raise ValueError("number vector json must be a string")
            value = strict_json_loads(wire_json, f"number vector {vector.get('name')}")
            digest = canonical_digest(value)
            if vector.get("outcome") != "ACCEPT":
                failures.append(f"number vector {vector.get('name')} should be rejected")
            elif digest != vector.get("digest"):
                failures.append(f"number vector {vector.get('name')} digest does not match")
        except (ValueError, rfc8785.IntegerDomainError):
            if vector.get("outcome") != "REJECT":
                failures.append(f"number vector {vector.get('name')} should be accepted")

def validate_sample(path: Path, schema_path: Path) -> None:
    value = strict_json_loads(path.read_bytes(), path.name)
    schema = strict_json_loads(schema_path.read_bytes(), schema_path.name)
    for error in Draft202012Validator(schema).iter_errors(value):
        location = "/".join(map(str, error.absolute_path))
        failures.append(f"{path.relative_to(contract_dir)} fails its schema at /{location}: {error.message}")

for sample_path, sample_schema_path in [
    (worker_profile_path, worker_profile_schema_path),
    (worker_report_path, worker_report_schema_path),
    (worker_attestation_path, worker_attestation_schema_path),
    (finalization_profile_path, finalization_profile_schema_path),
    (prepared_receipt_path, finalization_receipt_schema_path),
    (published_receipt_path, finalization_receipt_schema_path),
    (cancelled_receipt_path, finalization_receipt_schema_path),
    (finalization_vectors_path, finalization_vectors_schema_path),
]:
    if sample_path.is_file() and sample_schema_path.is_file():
        validate_sample(sample_path, sample_schema_path)

if all(path.is_file() for path in (
    finalization_profile_path,
    finalization_request_path,
    contradictory_finalization_request_path,
    prepared_receipt_path,
    published_receipt_path,
    cancelled_receipt_path,
    finalized_summary_path,
    finalization_vectors_path,
)):
    finalization_profile = strict_json_loads(finalization_profile_path.read_bytes(), finalization_profile_path.name)
    finalization_request = strict_json_loads(finalization_request_path.read_bytes(), finalization_request_path.name)
    contradictory_finalization_request = strict_json_loads(
        contradictory_finalization_request_path.read_bytes(),
        contradictory_finalization_request_path.name,
    )
    prepared_receipt = strict_json_loads(prepared_receipt_path.read_bytes(), prepared_receipt_path.name)
    published_receipt = strict_json_loads(published_receipt_path.read_bytes(), published_receipt_path.name)
    cancelled_receipt = strict_json_loads(cancelled_receipt_path.read_bytes(), cancelled_receipt_path.name)
    finalization_vectors = strict_json_loads(finalization_vectors_path.read_bytes(), finalization_vectors_path.name)
    run_id = finalization_vectors.get("runId")
    provider_revision = finalization_vectors.get("providerRevision")
    expected_operation_id = "scenario-lab-finalize:" + hashlib.sha256(
        f"{run_id}{provider_revision}".encode("utf-8")
    ).hexdigest()
    if finalization_profile.get("capability") != "PLATFORM_OWNED_V2":
        failures.append("Scenario Lab finalization profile must require PLATFORM_OWNED_V2")
    if finalization_profile.get("newClockDrivenLaunchesRequireV2") is not True:
        failures.append("Scenario Lab finalization profile must require V2 for every new clock-driven launch")
    if finalization_profile.get("legacyV1RecoveryOnly") is not True:
        failures.append("Scenario Lab finalization profile must restrict V1 to legacy recovery")
    required_conformance_flags = {
        "durableSharedStoreCapabilityGateRequired": "a successful durable shared-root storage proof before V2 capability advertisement",
        "executedDurableStorageProbeRequired": "an executed durable-storage capability probe before PASSED",
        "successfulRestartProbeRequired": "separate successful restart probe",
        "independentOsProcessRestartRequired": "independent operating-system process restart",
        "originalProcessTerminationProofRequired": "a harness-distinct original provider process plus termination and endpoint-unreachability proof",
        "distinctRestartedProcessIdentityRequired": "a distinct restarted PID or process handle",
        "providerTargetIdentityBindingRequired": "canonical /pack digest, packId, domainId, and providerRevision binding to the provider under test across restart",
        "terminalPrecedenceProbeRequired": "separate terminal precedence probe",
        "terminalPrecedenceOsProcessRestartRequired": "original-process termination and distinct OS-process restart before terminal recovery",
        "preparedArtifactVerificationRequired": "PREPARED artifact verification",
        "exactVectorOutcomeValidationRequired": "exact vector/outcome validation",
        "providerExecutedAdversarialVectorsRequired": "provider-executed durable-fault adversarial vectors",
        "notificationFailureRetryWithoutFinalizeProbeRequired": "failed-acknowledgement notification retry without another FINALIZE request",
    }
    for field_name, label in required_conformance_flags.items():
        if finalization_profile.get(field_name) is not True:
            failures.append(f"Scenario Lab finalization profile must require {label}")
    if finalization_vectors.get("operationId") != expected_operation_id:
        failures.append("Scenario Lab finalization operationId does not match runId and providerRevision")
    if finalization_request.get("operationId") != expected_operation_id:
        failures.append("Scenario Lab FINALIZE request does not use the derived operationId")
    if not embeds_exact_finalize_fixture(finalization_vectors, finalization_request):
        failures.append("Scenario Lab FINALIZE request vector does not exactly match its canonical fixture")
    expected_input_digest = hashlib.sha256(
        rfc8785.dumps(normalize_interoperable_numbers(finalization_request))
    ).hexdigest()
    if finalization_vectors.get("inputDigest") != expected_input_digest:
        failures.append("Scenario Lab conformance inputDigest does not match FINALIZE request")
    expected_contradictory_digest = hashlib.sha256(
        rfc8785.dumps(normalize_interoperable_numbers(contradictory_finalization_request))
    ).hexdigest()
    if contradictory_finalization_request.get("operationId") != expected_operation_id:
        failures.append("Scenario Lab contradictory request must reuse the stable operationId")
    if expected_contradictory_digest == expected_input_digest:
        failures.append("Scenario Lab contradictory request must change the canonical input")
    if finalization_vectors.get("contradictoryFinalizeRequest") != contradictory_finalization_request:
        failures.append("Scenario Lab contradictory request vector does not match its fixture")
    if finalization_vectors.get("contradictoryInputDigest") != expected_contradictory_digest:
        failures.append("Scenario Lab contradictory request digest does not match its fixture")
    legacy_v1_recovery = finalization_vectors.get("legacyV1Recovery", {})
    expected_legacy_v1_request = {"action": "FINALIZE"}
    expected_invalid_legacy_v1_request = {
        "action": "FINALIZE",
        "operationId": expected_operation_id,
    }
    if legacy_v1_recovery.get("finalizationMode") != "PLATFORM_OWNED_V1":
        failures.append("Scenario Lab legacy recovery vector must target PLATFORM_OWNED_V1")
    if legacy_v1_recovery.get("requestWithoutV2Fields") != expected_legacy_v1_request:
        failures.append("Scenario Lab V1 recovery request must contain no V2-only fields")
    if legacy_v1_recovery.get("requestWithV2OperationId") != expected_invalid_legacy_v1_request:
        failures.append("Scenario Lab V1 rejection vector must add the derived V2 operationId")
    expected_execution_requirements = {
        "durableStorageCapabilityProbe": {
            "mustExecuteBeforePassed": True,
            "crossProcessLockExclusionAndVisibilityRequired": True,
            "atomicDurablePublicationRequired": True,
            "multiReplicaStorageSemantics": "SHARED_RWX_OR_CAS",
        },
        "terminalPrecedenceProbe": {
            "case": "prepared_then_cancelled",
            "originalProcessTerminationRequired": True,
            "distinctRestartedOsProcessRequired": True,
        },
        "notificationRetryProbe": {
            "case": "notification_retry",
            "failedDeliveryAcknowledgementRequired": True,
            "providerInitiatedRetryRequired": True,
            "retryWithoutAdditionalFinalizeRequired": True,
        },
    }
    if finalization_vectors.get("executionRequirements") != expected_execution_requirements:
        failures.append(
            "Scenario Lab finalization vectors must require the exact provider-executed storage, terminal-restart, and notification-retry probes"
        )
    for label, receipt in (("PREPARED", prepared_receipt), ("PUBLISHED", published_receipt)):
        if receipt.get("runId") != run_id:
            failures.append(f"Scenario Lab {label} receipt runId does not match the vector")
        if receipt.get("providerRevision") != provider_revision:
            failures.append(f"Scenario Lab {label} receipt providerRevision does not match the vector")
        if receipt.get("operationId") != expected_operation_id:
            failures.append(f"Scenario Lab {label} receipt operationId does not match the vector")
        if receipt.get("inputDigest") != expected_input_digest:
            failures.append(f"Scenario Lab {label} receipt inputDigest does not match the vector")
        if receipt.get("state") != label:
            failures.append(f"Scenario Lab {label} sample has the wrong receipt state")
        if receipt.get("artifactManifest") != prepared_receipt.get("artifactManifest"):
            failures.append(f"Scenario Lab {label} receipt does not preserve the frozen artifact manifest")
    artifact_vector = finalization_vectors.get("artifact", {})
    artifact_bytes = finalized_summary_path.read_bytes()
    artifact_digest = hashlib.sha256(artifact_bytes).hexdigest()
    artifact_ref = finalized_summary_path.relative_to(contract_dir).as_posix()
    expected_artifact = {
        "path": artifact_ref,
        "sha256": artifact_digest,
        "byteLength": len(artifact_bytes),
    }
    if artifact_vector != expected_artifact:
        failures.append("Scenario Lab finalization artifact vector does not match immutable sample bytes")
    expected_manifest_entry = {
        "artifactRef": artifact_ref,
        "contentType": "application/json",
        "sha256": artifact_digest,
        "byteLength": len(artifact_bytes),
    }
    if prepared_receipt.get("artifactManifest", {}).get("summary") != expected_manifest_entry:
        failures.append("Scenario Lab PREPARED receipt does not freeze the sample artifact bytes")
    if prepared_receipt.get("completionNotificationPayload") != {}:
        failures.append("Scenario Lab PREPARED receipt must not contain a completion notification")
    if cancelled_receipt.get("state") != "PUBLISHED":
        failures.append("Scenario Lab terminal-precedence receipt must be PUBLISHED")
    if cancelled_receipt.get("runSnapshot", {}).get("status") != "CANCELLED":
        failures.append("Scenario Lab terminal-precedence receipt must preserve CANCELLED")
    if cancelled_receipt.get("completionNotificationState") != "NOT_REQUIRED":
        failures.append("Scenario Lab CANCELLED receipt must not require completion notification")
    if cancelled_receipt.get("completionNotificationPayload") != {}:
        failures.append("Scenario Lab CANCELLED receipt must not contain a completion notification")
    if cancelled_receipt.get("artifactManifest") != prepared_receipt.get("artifactManifest"):
        failures.append("Scenario Lab CANCELLED receipt must retain the frozen artifact manifest")
    notification = published_receipt.get("completionNotificationPayload", {})
    run_snapshot = published_receipt.get("runSnapshot", {})
    expected_notification_owners = {
        "runId": published_receipt.get("runId"),
        "status": run_snapshot.get("status"),
        "operationId": published_receipt.get("operationId"),
        "inputDigest": published_receipt.get("inputDigest"),
        "providerRevision": published_receipt.get("providerRevision"),
    }
    for field_name, expected_value in expected_notification_owners.items():
        if notification.get(field_name) != expected_value:
            failures.append(
                f"Scenario Lab PUBLISHED notification {field_name} does not match its receipt owner"
            )
    for field_name in ("summaryPath", "bundlePath", "completedAtEpochMs", "metadata"):
        if notification.get(field_name) != run_snapshot.get(field_name):
            failures.append(
                f"Scenario Lab PUBLISHED notification {field_name} does not match runSnapshot"
            )
    expected_cases = [
        {"case": "exact_replay", "outcome": "RETURN_EXISTING"},
        {"case": "contradictory_input", "outcome": "REJECT"},
        {"case": "missing_receipt", "outcome": "REJECT"},
        {"case": "receipt_missing_state", "outcome": "REJECT"},
        {"case": "missing_artifact", "outcome": "REJECT"},
        {"case": "altered_artifact", "outcome": "REJECT"},
        {"case": "prepared_then_cancelled", "outcome": "PRESERVE_TERMINAL"},
        {"case": "notification_retry", "outcome": "RETRY_IDENTICAL_NOTIFICATION"},
        {"case": "prepared_with_terminal_status", "outcome": "REJECT"},
        {"case": "published_with_running_status", "outcome": "REJECT"},
        {"case": "artifact_path_escape", "outcome": "REJECT"},
        {"case": "ambiguous_receipt_json", "outcome": "REJECT"},
        {"case": "legacy_v1_v2_operation_id", "outcome": "REJECT"},
    ]
    actual_cases = finalization_vectors.get("expectations")
    if actual_cases != expected_cases:
        failures.append("Scenario Lab finalization conformance vectors are incomplete or contradictory")
    if finalization_vectors_schema_path.is_file():
        vectors_schema = strict_json_loads(
            finalization_vectors_schema_path.read_bytes(),
            finalization_vectors_schema_path.name,
        )
        vectors_validator = Draft202012Validator(vectors_schema)
        adversarial_expectations = {
            "wrong vector outcome": [
                {**expected_cases[0], "outcome": "REJECT"},
                *expected_cases[1:],
            ],
            "duplicate vector case": [*expected_cases[:-1], expected_cases[0]],
            "missing vector case": expected_cases[:-1],
            "extra vector case": [*expected_cases, expected_cases[0]],
        }
        for label, expectations in adversarial_expectations.items():
            mutated_vectors = {**finalization_vectors, "expectations": expectations}
            if not list(vectors_validator.iter_errors(mutated_vectors)):
                failures.append(f"Scenario Lab vector schema must reject {label}")
        alternative_finalize_request = {
            "action": "FINALIZE",
            "operationId": "scenario-lab-finalize:" + ("0" * 64),
        }
        if list(vectors_validator.iter_errors({
            **finalization_vectors,
            "finalizeRequest": alternative_finalize_request,
        })):
            failures.append(
                "Scenario Lab vector schema must leave cross-fixture FINALIZE equality to semantic verification"
            )
        if embeds_exact_finalize_fixture(
            {**finalization_vectors, "finalizeRequest": alternative_finalize_request},
            finalization_request,
        ):
            failures.append("Scenario Lab semantic verifier must reject a substituted FINALIZE fixture")
        adversarial_execution_requirements = {
            "unexecuted storage probe": {
                **expected_execution_requirements,
                "durableStorageCapabilityProbe": {
                    **expected_execution_requirements["durableStorageCapabilityProbe"],
                    "mustExecuteBeforePassed": False,
                },
            },
            "terminal recovery without process restart": {
                **expected_execution_requirements,
                "terminalPrecedenceProbe": {
                    **expected_execution_requirements["terminalPrecedenceProbe"],
                    "distinctRestartedOsProcessRequired": False,
                },
            },
            "notification retry caused by FINALIZE replay": {
                **expected_execution_requirements,
                "notificationRetryProbe": {
                    **expected_execution_requirements["notificationRetryProbe"],
                    "retryWithoutAdditionalFinalizeRequired": False,
                },
            },
        }
        for label, execution_requirements in adversarial_execution_requirements.items():
            mutated_vectors = {
                **finalization_vectors,
                "executionRequirements": execution_requirements,
            }
            if not list(vectors_validator.iter_errors(mutated_vectors)):
                failures.append(f"Scenario Lab vector schema must reject {label}")
    if finalization_receipt_schema_path.is_file():
        receipt_schema = strict_json_loads(
            finalization_receipt_schema_path.read_bytes(),
            finalization_receipt_schema_path.name,
        )
        receipt_validator = Draft202012Validator(receipt_schema)
        receipt_missing_state = {
            key: value
            for key, value in published_receipt.items()
            if key != "state"
        }
        if not list(receipt_validator.iter_errors(receipt_missing_state)):
            failures.append("Scenario Lab receipt schema must reject a receipt missing state")

if worker_profile_schema_path.is_file():
    worker_profile_schema = strict_json_loads(worker_profile_schema_path.read_bytes(), worker_profile_schema_path.name)
    unicode_profile = {
        "schemaVersion": "remote_domain_opportunity_worker_conformance_profile.v1",
        "toolEffects": {"tool_😀": "READ_ONLY"},
        "toolProbes": [{"toolName": "tool_😀", "arguments": {}}],
    }
    if not list(Draft202012Validator(worker_profile_schema).iter_errors(unicode_profile)):
        failures.append("opportunity-worker profile schema must reject non-ASCII tool identifiers")

if worker_report_schema_path.is_file() and worker_report_path.is_file():
    worker_report_schema = strict_json_loads(worker_report_schema_path.read_bytes(), worker_report_schema_path.name)
    unicode_report = strict_json_loads(worker_report_path.read_bytes(), worker_report_path.name)
    unicode_report["toolProbeResults"][0]["toolName"] = "tool_😀"
    if not list(Draft202012Validator(worker_report_schema).iter_errors(unicode_report)):
        failures.append("opportunity-worker report schema must reject non-ASCII tool identifiers")

def dsse_pae(payload_type: str, payload: bytes) -> bytes:
    payload_type_bytes = payload_type.encode("utf-8")
    return b" ".join((
        b"DSSEv1",
        str(len(payload_type_bytes)).encode("ascii"),
        payload_type_bytes,
        str(len(payload)).encode("ascii"),
        payload,
    ))

if (
    worker_profile_path.is_file()
    and worker_report_path.is_file()
    and worker_attestation_path.is_file()
    and worker_public_key_path.is_file()
    and manifest_sample_path.is_file()
):
    worker_profile = strict_json_loads(worker_profile_path.read_bytes(), worker_profile_path.name)
    worker_report = strict_json_loads(worker_report_path.read_bytes(), worker_report_path.name)
    worker_attestation = strict_json_loads(worker_attestation_path.read_bytes(), worker_attestation_path.name)
    manifest_sample = strict_json_loads(manifest_sample_path.read_bytes(), manifest_sample_path.name)
    classification_projection = {
        "schemaVersion": worker_profile.get("schemaVersion"),
        "toolEffects": worker_profile.get("toolEffects"),
    }
    if worker_report.get("profileDigest") != canonical_digest(classification_projection):
        failures.append("opportunity-worker report profileDigest does not match the profile sample")
    if worker_report.get("manifestDigest") != canonical_digest(manifest_sample):
        failures.append("opportunity-worker report manifestDigest does not match the manifest sample")
    if worker_report.get("domainId") != manifest_sample.get("domain", {}).get("domainId"):
        failures.append("opportunity-worker report domainId does not match the manifest sample")
    try:
        payload = base64.b64decode(worker_attestation["payload"], validate=True)
        signature = base64.b64decode(worker_attestation["signatures"][0]["sig"], validate=True)
        statement = strict_json_loads(payload, "opportunity-worker DSSE payload")
        public_key = serialization.load_der_public_key(base64.b64decode(
            worker_public_key_path.read_text(encoding="utf-8").strip(),
            validate=True,
        ))
        public_key.verify(signature, dsse_pae(worker_attestation["payloadType"], payload))
        if payload != rfc8785.dumps(normalize_interoperable_numbers(statement)):
            failures.append("opportunity-worker attestation payload must use RFC 8785 canonical JSON")
        predicate = statement.get("predicate", {})
        if predicate.get("conformanceReportDigest") != canonical_digest(worker_report):
            failures.append("attestation predicate does not bind the conformance report sample")
        if predicate.get("profileDigest") != worker_report.get("profileDigest"):
            failures.append("attestation predicate does not bind the profile digest")
        if predicate.get("manifestDigest") != worker_report.get("manifestDigest"):
            failures.append("attestation predicate does not bind the manifest digest")
        subject_digest = statement.get("subject", [{}])[0].get("digest", {}).get("sha256")
        if "sha256:" + str(subject_digest) != worker_report.get("providerArtifactDigest"):
            failures.append("attestation subject does not bind the provider artifact digest")
    except Exception as error:
        failures.append(f"opportunity-worker attestation signature verification failed: {error}")

if failures:
    for failure in failures:
        print(failure, file=sys.stderr)
    raise SystemExit(1)

print(f"Verified remote-domain.v1 contract metadata for {version}")
PY
