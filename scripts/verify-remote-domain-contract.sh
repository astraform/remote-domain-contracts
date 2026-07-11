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
from cryptography.hazmat.primitives import serialization
from jsonschema import Draft202012Validator
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
manifest_sample_path = contract_dir / "samples/manifest.response.json"
schema_path = contract_dir / "schemas/remote-domain.schema.json"
if schema_path.is_file():
    contract_schema = json.loads(schema_path.read_text(encoding="utf-8"))
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
if manifest_sample_path.is_file():
    manifest_sample = json.loads(manifest_sample_path.read_text(encoding="utf-8"))
    for index, tool in enumerate(manifest_sample.get("capabilities", {}).get("tools", [])):
        if not isinstance(tool, dict) or "effectType" in tool:
            failures.append(f"manifest sample tool[{index}] must remain remote-domain.v1 compatible")
if (
    first_request_path.is_file()
    and first_response_path.is_file()
    and replay_request_path.is_file()
    and replay_response_path.is_file()
):
    first_request = json.loads(first_request_path.read_text(encoding="utf-8"))
    first_response = json.loads(first_response_path.read_text(encoding="utf-8"))
    replay_request = json.loads(replay_request_path.read_text(encoding="utf-8"))
    replay_response = json.loads(replay_response_path.read_text(encoding="utf-8"))
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
    canonical = rfc8785.dumps(value)
    return "sha256:" + hashlib.sha256(canonical).hexdigest()

if number_vectors_path.is_file():
    number_vectors = json.loads(number_vectors_path.read_text(encoding="utf-8"))
    for vector in number_vectors.get("vectors", []):
        try:
            digest = canonical_digest(vector.get("value"))
            if vector.get("outcome") != "ACCEPT":
                failures.append(f"number vector {vector.get('name')} should be rejected")
            elif digest != vector.get("digest"):
                failures.append(f"number vector {vector.get('name')} digest does not match")
        except (ValueError, rfc8785.IntegerDomainError):
            if vector.get("outcome") != "REJECT":
                failures.append(f"number vector {vector.get('name')} should be accepted")

def validate_sample(path: Path, schema_path: Path) -> None:
    value = json.loads(path.read_text(encoding="utf-8"))
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    for error in Draft202012Validator(schema).iter_errors(value):
        location = "/".join(map(str, error.absolute_path))
        failures.append(f"{path.relative_to(contract_dir)} fails its schema at /{location}: {error.message}")

for sample_path, sample_schema_path in [
    (worker_profile_path, worker_profile_schema_path),
    (worker_report_path, worker_report_schema_path),
    (worker_attestation_path, worker_attestation_schema_path),
]:
    if sample_path.is_file() and sample_schema_path.is_file():
        validate_sample(sample_path, sample_schema_path)

if worker_profile_schema_path.is_file():
    worker_profile_schema = json.loads(worker_profile_schema_path.read_text(encoding="utf-8"))
    unicode_profile = {
        "schemaVersion": "remote_domain_opportunity_worker_conformance_profile.v1",
        "toolEffects": {"tool_😀": "READ_ONLY"},
        "toolProbes": [{"toolName": "tool_😀", "arguments": {}}],
    }
    if not list(Draft202012Validator(worker_profile_schema).iter_errors(unicode_profile)):
        failures.append("opportunity-worker profile schema must reject non-ASCII tool identifiers")

if worker_report_schema_path.is_file() and worker_report_path.is_file():
    worker_report_schema = json.loads(worker_report_schema_path.read_text(encoding="utf-8"))
    unicode_report = json.loads(worker_report_path.read_text(encoding="utf-8"))
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
    worker_profile = json.loads(worker_profile_path.read_text(encoding="utf-8"))
    worker_report = json.loads(worker_report_path.read_text(encoding="utf-8"))
    worker_attestation = json.loads(worker_attestation_path.read_text(encoding="utf-8"))
    manifest_sample = json.loads(manifest_sample_path.read_text(encoding="utf-8"))
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
        statement = json.loads(payload)
        public_key = serialization.load_der_public_key(base64.b64decode(
            worker_public_key_path.read_text(encoding="utf-8").strip(),
            validate=True,
        ))
        public_key.verify(signature, dsse_pae(worker_attestation["payloadType"], payload))
        if payload != rfc8785.dumps(statement):
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
