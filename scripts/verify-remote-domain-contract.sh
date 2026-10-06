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
if ! "$PYTHON_BIN" -c 'import cryptography, jsonschema, referencing, rfc8785, yaml' >/dev/null 2>&1; then
  echo "Verifier dependencies are unavailable in $PYTHON_BIN" >&2
  exit 1
fi

"$PYTHON_BIN" - "$CONTRACT_DIR" <<'PY'
from __future__ import annotations

import json
import hashlib
import base64
import copy
import math
import re
import rfc8785
import yaml
from decimal import Decimal
from cryptography.hazmat.primitives import serialization
from jsonschema import Draft202012Validator
from referencing import Registry, Resource
import sys
from pathlib import Path

contract_dir = Path(sys.argv[1]).resolve()
version = (contract_dir.parents[1] / "VERSION").read_text(encoding="utf-8").strip()
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
    raise SystemExit("Root VERSION must be an exact semantic version")
if (contract_dir / "VERSION").read_text(encoding="utf-8").strip() != version:
    raise SystemExit("Provider bundle VERSION must match root VERSION")
openapi = yaml.safe_load((contract_dir / "openapi/remote-domain.yaml").read_text())
if openapi.get("info", {}).get("version") != version:
    raise SystemExit("Provider OpenAPI info.version must match root VERSION")
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

# Keep specific files covered only by manifest globs: a glob still matches when one is missing.
required_paths = [
    "schemas/domain-outcome-scorecard-roles.v1.schema.json",
    "schemas/policy-wind-tunnel-pack.v1.schema.json",
    "samples/policy-wind-tunnel-pack.sample.json",
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
policy_wind_tunnel_pack_path = contract_dir / "samples/policy-wind-tunnel-pack.sample.json"
policy_wind_tunnel_pack_schema_path = contract_dir / "schemas/policy-wind-tunnel-pack.v1.schema.json"
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

SCORECARD_ID_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,254}", re.ASCII)

def canonically_equal_json(left: object, right: object) -> bool:
    try:
        require_interoperable_numbers(left)
        require_interoperable_numbers(right)
        return (
            rfc8785.dumps(normalize_interoperable_numbers(left))
            == rfc8785.dumps(normalize_interoperable_numbers(right))
        )
    except Exception:
        return False

def policy_pack_semantic_errors(pack: object) -> list[str]:
    errors: list[str] = []
    if not isinstance(pack, dict):
        return errors

    catalog = pack.get("outcomeScorecards")
    scorecard_ids: list[str] = []
    if isinstance(catalog, list):
        for index, scorecard in enumerate(catalog):
            if not isinstance(scorecard, dict):
                continue
            scorecard_id = scorecard.get("scorecardId")
            if not isinstance(scorecard_id, str) or SCORECARD_ID_PATTERN.fullmatch(scorecard_id) is None:
                errors.append(f"outcomeScorecards[{index}].scorecardId is not canonical")
                continue
            scorecard_ids.append(scorecard_id)
        duplicate_scorecard_ids = sorted({
            scorecard_id
            for scorecard_id in scorecard_ids
            if scorecard_ids.count(scorecard_id) > 1
        })
        if duplicate_scorecard_ids:
            errors.append(
                "outcomeScorecards contains duplicate scorecardId value(s): "
                + ", ".join(duplicate_scorecard_ids)
            )

    if "outcomeScorecard" in pack:
        primary = pack.get("outcomeScorecard")
        if not isinstance(catalog, list) or not any(
            canonically_equal_json(primary, member)
            for member in catalog
        ):
            errors.append("outcomeScorecard must exactly equal one outcomeScorecards member")

    capabilities = pack.get("capabilities")
    role_catalog = (
        capabilities.get("domainOutcomeScorecardRoles")
        if isinstance(capabilities, dict)
        else None
    )
    if role_catalog is None:
        return errors
    if not isinstance(role_catalog, dict):
        return errors

    roles = role_catalog.get("roles")
    if not isinstance(roles, list):
        return errors

    declared_ids: list[str] = []
    for index, declaration in enumerate(roles):
        if not isinstance(declaration, dict):
            continue
        scorecard_id = declaration.get("scorecardId")
        if not isinstance(scorecard_id, str) or SCORECARD_ID_PATTERN.fullmatch(scorecard_id) is None:
            errors.append(f"domainOutcomeScorecardRoles.roles[{index}].scorecardId is not canonical")
            continue
        declared_ids.append(scorecard_id)

    duplicate_declared_ids = sorted({
        scorecard_id
        for scorecard_id in declared_ids
        if declared_ids.count(scorecard_id) > 1
    })
    if duplicate_declared_ids:
        errors.append(
            "domainOutcomeScorecardRoles contains duplicate scorecardId value(s): "
            + ", ".join(duplicate_declared_ids)
        )

    scorecard_id_set = set(scorecard_ids)
    declared_id_set = set(declared_ids)
    if scorecard_id_set != declared_id_set:
        missing = sorted(scorecard_id_set - declared_id_set)
        extra = sorted(declared_id_set - scorecard_id_set)
        if missing:
            errors.append(
                "domainOutcomeScorecardRoles is missing scorecardId value(s): "
                + ", ".join(missing)
            )
        if extra:
            errors.append(
                "domainOutcomeScorecardRoles contains extra scorecardId value(s): "
                + ", ".join(extra)
            )
    return errors

def positive_business_scorecard_ids(pack: object) -> set[str]:
    if not isinstance(pack, dict):
        return set()
    capabilities = pack.get("capabilities")
    if not isinstance(capabilities, dict):
        return set()
    role_catalog = capabilities.get("domainOutcomeScorecardRoles")
    if not isinstance(role_catalog, dict):
        return set()
    roles = role_catalog.get("roles")
    if not isinstance(roles, list):
        return set()
    return {
        declaration["scorecardId"]
        for declaration in roles
        if isinstance(declaration, dict)
        and declaration.get("role") == "BUSINESS_OUTCOME"
        and isinstance(declaration.get("scorecardId"), str)
    }

def build_local_schema_registry() -> Registry:
    registry = Registry()
    for local_schema_path in sorted((contract_dir / "schemas").glob("*.schema.json")):
        local_schema = strict_json_loads(
            local_schema_path.read_bytes(),
            local_schema_path.relative_to(contract_dir).as_posix(),
        )
        try:
            Draft202012Validator.check_schema(local_schema)
        except Exception as error:
            failures.append(
                f"{local_schema_path.relative_to(contract_dir)} is not a valid Draft 2020-12 schema: {error}"
            )
            continue
        schema_id = local_schema.get("$id") if isinstance(local_schema, dict) else None
        if not isinstance(schema_id, str) or not schema_id:
            failures.append(f"{local_schema_path.relative_to(contract_dir)} must declare a nonblank $id")
            continue
        try:
            registry = registry.with_resource(schema_id, Resource.from_contents(local_schema))
        except Exception as error:
            failures.append(
                f"{local_schema_path.relative_to(contract_dir)} cannot enter the local schema registry: {error}"
            )
    return registry

if policy_wind_tunnel_pack_path.is_file() and policy_wind_tunnel_pack_schema_path.is_file():
    policy_pack = strict_json_loads(
        policy_wind_tunnel_pack_path.read_bytes(),
        policy_wind_tunnel_pack_path.name,
    )
    policy_pack_schema = strict_json_loads(
        policy_wind_tunnel_pack_schema_path.read_bytes(),
        policy_wind_tunnel_pack_schema_path.name,
    )
    policy_pack_validator = Draft202012Validator(
        policy_pack_schema,
        registry=build_local_schema_registry(),
    )

    def policy_pack_errors(candidate: object) -> list[str]:
        candidate_errors: list[str] = []
        try:
            candidate_errors.extend(
                f"{'/'.join(map(str, error.absolute_path)) or '$'}: {error.message}"
                for error in policy_pack_validator.iter_errors(candidate)
            )
        except Exception as error:
            candidate_errors.append(f"schema resolution failed: {error}")
        candidate_errors.extend(policy_pack_semantic_errors(candidate))
        return candidate_errors

    def expect_policy_pack_valid(label: str, candidate: object) -> None:
        candidate_errors = policy_pack_errors(candidate)
        if candidate_errors:
            failures.append(
                f"Policy Wind Tunnel pack must accept {label}: "
                + "; ".join(candidate_errors)
            )

    def expect_policy_pack_invalid(label: str, candidate: object) -> None:
        if not policy_pack_errors(candidate):
            failures.append(f"Policy Wind Tunnel pack must reject {label}")

    expect_policy_pack_valid("the canonical role-bound sample", policy_pack)
    if positive_business_scorecard_ids(policy_pack) != {"demo.customer-impact.v1"}:
        failures.append("canonical Policy Wind Tunnel sample must grant positive authority to its business scorecard")

    legacy_pack = copy.deepcopy(policy_pack)
    legacy_pack["capabilities"].pop("domainOutcomeScorecardRoles")
    expect_policy_pack_valid("a legacy pack without scorecard-role capability", legacy_pack)
    if positive_business_scorecard_ids(legacy_pack):
        failures.append("a missing scorecard-role capability must grant no positive business authority")

    proof_only_pack = copy.deepcopy(policy_pack)
    proof_only_pack["capabilities"]["domainOutcomeScorecardRoles"]["roles"][0]["role"] = "PROOF_GATE"
    expect_policy_pack_valid("a proof-only scorecard catalog", proof_only_pack)
    if positive_business_scorecard_ids(proof_only_pack):
        failures.append("a proof-only scorecard catalog must grant no positive business authority")

    multiple_scorecards_pack = copy.deepcopy(policy_pack)
    second_scorecard = copy.deepcopy(multiple_scorecards_pack["outcomeScorecards"][0])
    second_scorecard["scorecardId"] = "demo.evidence-readiness.v1"
    second_scorecard["label"] = "Evidence readiness scorecard"
    multiple_scorecards_pack["outcomeScorecards"].append(second_scorecard)
    multiple_scorecards_pack["capabilities"]["domainOutcomeScorecardRoles"]["roles"] = [
        {
            "scorecardId": "demo.evidence-readiness.v1",
            "role": "PROOF_GATE",
        },
        {
            "scorecardId": "demo.customer-impact.v1",
            "role": "BUSINESS_OUTCOME",
        },
    ]
    expect_policy_pack_valid("multiple scorecards in independent role-array order", multiple_scorecards_pack)

    primary_pack = copy.deepcopy(multiple_scorecards_pack)
    primary_pack["outcomeScorecard"] = copy.deepcopy(primary_pack["outcomeScorecards"][0])
    expect_policy_pack_valid("an exact singular scorecard catalog pointer", primary_pack)

    equivalent_number_primary_pack = copy.deepcopy(policy_pack)
    equivalent_number_primary_pack["outcomeScorecards"][0]["numericProbe"] = 1
    equivalent_number_primary_pack["outcomeScorecard"] = copy.deepcopy(
        equivalent_number_primary_pack["outcomeScorecards"][0]
    )
    equivalent_number_primary_pack["outcomeScorecard"]["numericProbe"] = Decimal("1.0")
    expect_policy_pack_valid(
        "an RFC 8785-equivalent singular numeric value",
        equivalent_number_primary_pack,
    )

    invalid_role_catalogs: dict[str, object] = {}
    missing_role_schema_version = copy.deepcopy(policy_pack)
    missing_role_schema_version["capabilities"]["domainOutcomeScorecardRoles"].pop("schemaVersion")
    invalid_role_catalogs["a missing role schema version"] = missing_role_schema_version

    wrong_role_schema_version = copy.deepcopy(policy_pack)
    wrong_role_schema_version["capabilities"]["domainOutcomeScorecardRoles"]["schemaVersion"] = "domain_outcome_scorecard_roles.v2"
    invalid_role_catalogs["a wrong role schema version"] = wrong_role_schema_version

    empty_roles = copy.deepcopy(policy_pack)
    empty_roles["capabilities"]["domainOutcomeScorecardRoles"]["roles"] = []
    invalid_role_catalogs["an empty roles array"] = empty_roles

    non_array_roles = copy.deepcopy(policy_pack)
    non_array_roles["capabilities"]["domainOutcomeScorecardRoles"]["roles"] = {}
    invalid_role_catalogs["a non-array roles value"] = non_array_roles

    for label, role in {
        "an unknown role": "APPROVAL",
        "a lowercase role": "business_outcome",
        "a padded role": " BUSINESS_OUTCOME",
        "a blank role": "",
    }.items():
        candidate = copy.deepcopy(policy_pack)
        candidate["capabilities"]["domainOutcomeScorecardRoles"]["roles"][0]["role"] = role
        invalid_role_catalogs[label] = candidate

    for label, scorecard_id in {
        "a blank role scorecard ID": "",
        "a padded role scorecard ID": " demo.customer-impact.v1",
        "a malformed role scorecard ID": "demo/customer-impact",
        "an overlong role scorecard ID": "a" * 256,
    }.items():
        candidate = copy.deepcopy(policy_pack)
        candidate["capabilities"]["domainOutcomeScorecardRoles"]["roles"][0]["scorecardId"] = scorecard_id
        invalid_role_catalogs[label] = candidate

    for label, scorecard_id in {
        "a blank outcome scorecard ID": "",
        "a padded outcome scorecard ID": "demo.customer-impact.v1 ",
        "a malformed outcome scorecard ID": "demo/customer-impact",
        "an overlong outcome scorecard ID": "a" * 256,
    }.items():
        candidate = copy.deepcopy(policy_pack)
        candidate["outcomeScorecards"][0]["scorecardId"] = scorecard_id
        candidate["capabilities"]["domainOutcomeScorecardRoles"]["roles"][0]["scorecardId"] = scorecard_id
        invalid_role_catalogs[label] = candidate

    extra_role_catalog_field = copy.deepcopy(policy_pack)
    extra_role_catalog_field["capabilities"]["domainOutcomeScorecardRoles"]["authority"] = "provider"
    invalid_role_catalogs["an extra role-catalog field"] = extra_role_catalog_field

    extra_role_entry_field = copy.deepcopy(policy_pack)
    extra_role_entry_field["capabilities"]["domainOutcomeScorecardRoles"]["roles"][0]["label"] = "Business"
    invalid_role_catalogs["an extra role-entry field"] = extra_role_entry_field

    duplicate_role = copy.deepcopy(policy_pack)
    duplicate_role["capabilities"]["domainOutcomeScorecardRoles"]["roles"].append(
        copy.deepcopy(duplicate_role["capabilities"]["domainOutcomeScorecardRoles"]["roles"][0])
    )
    invalid_role_catalogs["a duplicate scorecard ID with the same role"] = duplicate_role

    conflicting_role = copy.deepcopy(policy_pack)
    conflicting_declaration = copy.deepcopy(
        conflicting_role["capabilities"]["domainOutcomeScorecardRoles"]["roles"][0]
    )
    conflicting_declaration["role"] = "PROOF_GATE"
    conflicting_role["capabilities"]["domainOutcomeScorecardRoles"]["roles"].append(
        conflicting_declaration
    )
    invalid_role_catalogs["a duplicate scorecard ID with a different role"] = conflicting_role

    missing_role_declaration = copy.deepcopy(multiple_scorecards_pack)
    missing_role_declaration["capabilities"]["domainOutcomeScorecardRoles"]["roles"].pop(0)
    invalid_role_catalogs["a missing role declaration"] = missing_role_declaration

    extra_role_declaration = copy.deepcopy(policy_pack)
    extra_role_declaration["capabilities"]["domainOutcomeScorecardRoles"]["roles"].append({
        "scorecardId": "demo.unpublished.v1",
        "role": "PROOF_GATE",
    })
    invalid_role_catalogs["an extra role declaration"] = extra_role_declaration

    duplicate_scorecard = copy.deepcopy(policy_pack)
    duplicate_scorecard["outcomeScorecards"].append(
        copy.deepcopy(duplicate_scorecard["outcomeScorecards"][0])
    )
    invalid_role_catalogs["a duplicate outcome scorecard"] = duplicate_scorecard

    conflicting_duplicate_scorecard = copy.deepcopy(policy_pack)
    conflicting_scorecard = copy.deepcopy(conflicting_duplicate_scorecard["outcomeScorecards"][0])
    conflicting_scorecard["label"] = "Conflicting customer impact scorecard"
    conflicting_duplicate_scorecard["outcomeScorecards"].append(conflicting_scorecard)
    invalid_role_catalogs["a duplicate outcome scorecard ID with different content"] = conflicting_duplicate_scorecard

    singular_only_pack = copy.deepcopy(policy_pack)
    singular_only_pack["capabilities"].pop("domainOutcomeScorecardRoles")
    singular_only_pack["outcomeScorecard"] = singular_only_pack["outcomeScorecards"][0]
    singular_only_pack.pop("outcomeScorecards")
    invalid_role_catalogs["a singular-only scorecard catalog"] = singular_only_pack

    mismatched_primary_pack = copy.deepcopy(policy_pack)
    mismatched_primary_pack["outcomeScorecard"] = copy.deepcopy(
        mismatched_primary_pack["outcomeScorecards"][0]
    )
    mismatched_primary_pack["outcomeScorecard"]["label"] = "Different primary scorecard"
    invalid_role_catalogs["a singular scorecard differing from its plural member"] = mismatched_primary_pack

    true_number_primary_pack = copy.deepcopy(policy_pack)
    true_number_primary_pack["outcomeScorecards"][0]["typeProbe"] = 1
    true_number_primary_pack["outcomeScorecard"] = copy.deepcopy(
        true_number_primary_pack["outcomeScorecards"][0]
    )
    true_number_primary_pack["outcomeScorecard"]["typeProbe"] = True
    invalid_role_catalogs["a singular true differing from plural 1"] = true_number_primary_pack

    false_number_primary_pack = copy.deepcopy(policy_pack)
    false_number_primary_pack["outcomeScorecards"][0]["typeProbe"] = 0
    false_number_primary_pack["outcomeScorecard"] = copy.deepcopy(
        false_number_primary_pack["outcomeScorecards"][0]
    )
    false_number_primary_pack["outcomeScorecard"]["typeProbe"] = False
    invalid_role_catalogs["a singular false differing from plural 0"] = false_number_primary_pack

    for label, invalid_role_catalog in invalid_role_catalogs.items():
        expect_policy_pack_invalid(label, invalid_role_catalog)

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
    expected_invalid_legacy_v1_request = {
        "action": "FINALIZE",
        "operationId": expected_operation_id,
    }
    if legacy_v1_recovery.get("requestWithV2OperationId") != expected_invalid_legacy_v1_request:
        failures.append("Scenario Lab V1 rejection vector must add the derived V2 operationId")
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
    # Earlier sample validation records failures; only mutate a valid fixture.
    if finalization_vectors_schema_path.is_file() and not failures:
        vectors_schema = strict_json_loads(
            finalization_vectors_schema_path.read_bytes(),
            finalization_vectors_schema_path.name,
        )
        vectors_validator = Draft202012Validator(vectors_schema)
        fixture_cases = finalization_vectors["expectations"]
        fixture_requirements = finalization_vectors["executionRequirements"]
        wrong_outcome = "RETURN_EXISTING" if fixture_cases[0]["outcome"] == "REJECT" else "REJECT"
        adversarial_expectations = {
            "wrong vector outcome": [
                {**fixture_cases[0], "outcome": wrong_outcome},
                *fixture_cases[1:],
            ],
            "duplicate vector case": [*fixture_cases[:-1], fixture_cases[0]],
            "missing vector case": fixture_cases[:-1],
            "extra vector case": [*fixture_cases, fixture_cases[0]],
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
                **fixture_requirements,
                "durableStorageCapabilityProbe": {
                    **fixture_requirements["durableStorageCapabilityProbe"],
                    "mustExecuteBeforePassed": False,
                },
            },
            "terminal recovery without process restart": {
                **fixture_requirements,
                "terminalPrecedenceProbe": {
                    **fixture_requirements["terminalPrecedenceProbe"],
                    "distinctRestartedOsProcessRequired": False,
                },
            },
            "notification retry caused by FINALIZE replay": {
                **fixture_requirements,
                "notificationRetryProbe": {
                    **fixture_requirements["notificationRetryProbe"],
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
