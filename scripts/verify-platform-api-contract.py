#!/usr/bin/env python3
"""Verify the public platform bundle and resolve every local OpenAPI reference."""
from __future__ import annotations

import json
import re
from copy import deepcopy
from datetime import datetime
from pathlib import Path
from urllib.parse import unquote
import yaml
from jsonschema import Draft7Validator, FormatChecker

root = Path(__file__).resolve().parents[1] / "platform-api/v1"
manifest = json.loads((root / "manifest.json").read_text())
version = (root.parents[1] / "VERSION").read_text().strip()
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
    raise SystemExit("Root VERSION must be an exact semantic version")
if (root / "VERSION").read_text().strip() != version:
    raise SystemExit("Platform bundle VERSION must match root VERSION")
expected = {
    "bundleId": "platform-api", "version": version,
    "releaseArtifact": "platform-api.zip",
    "entrypoint": "openapi/platform/experiment/experiments.yaml",
}
for key, value in expected.items():
    if manifest.get(key) != value:
        raise SystemExit(f"Platform manifest {key} does not match {value!r}")

class UniqueKeysLoader(yaml.SafeLoader):
    """Reject duplicate mapping keys instead of silently dropping contract fields."""
    def construct_mapping(self, node, deep=False):
        values = {}
        for key_node, value_node in node.value:
            key = self.construct_object(key_node, deep=deep)
            if key in values:
                raise ValueError(f"Duplicate YAML key {key!r}")
            values[key] = self.construct_object(value_node, deep=deep)
        return values

files = manifest["openapiFiles"]
if len(files) != len(set(files)) or sorted(files) != sorted(
        path.relative_to(root).as_posix() for path in (root / "openapi").rglob("*.yaml")):
    raise SystemExit("Platform manifest must list exactly the shipped OpenAPI documents")
if manifest["entrypoint"] not in files:
    raise SystemExit("Platform entrypoint must be a shipped OpenAPI document")
for field in ("canonicalSources", "partnerContents"):
    for value in manifest[field]:
        relative = Path(value).relative_to("platform-api/v1")
        path = (root / relative).resolve()
        path.relative_to(root.resolve())
        if not path.is_file():
            raise SystemExit(f"Platform manifest missing file: {value}")

documents = {relative: yaml.load((root / relative).read_text(), Loader=UniqueKeysLoader) for relative in files}

# The runtime defaults omission to false. A wire default would make generated
# clients inject an unsupported property into otherwise older-compatible requests.
experiment = documents["openapi/platform/experiment/experiments.yaml"]
update = experiment["components"]["schemas"]["SimulationRunUpdateRequest"]
for field in ("runId", "operationId", "inputDigest", "providerRevision"):
    definition = update.get("properties", {}).get(field, {})
    if (definition.get("type") != "string" or definition.get("nullable", False)
            or field in update.get("required", [])):
        raise SystemExit(f"SimulationRunUpdateRequest.{field} must preserve optional finalization correlation")
update_schema = {"components": experiment["components"],
                 "$ref": "#/components/schemas/SimulationRunUpdateRequest"}
update_validator = Draft7Validator(update_schema)
for field in ("runId", "operationId", "inputDigest", "providerRevision"):
    if list(update_validator.iter_errors({field: "recorded-value"})):
        raise SystemExit(f"SimulationRunUpdateRequest.{field} must accept the existing string field")
    for invalid in (None, True, 1, [], {}):
        if not list(update_validator.iter_errors({field: invalid})):
            raise SystemExit(f"SimulationRunUpdateRequest.{field} must reject non-string correlation fields")
if list(update_validator.iter_errors({"status": "COMPLETED"})):
    raise SystemExit("Existing lifecycle updates must not require finalization correlation")
policy = experiment["components"]["schemas"]["AgentJourneyGoalCompletionPolicy"]
finish = policy["properties"]["requireCustomerFinish"]
if (finish.get("type") != "boolean" or finish.get("nullable", False)
        or "default" in finish or "requireCustomerFinish" in policy["required"]):
    raise SystemExit("requireCustomerFinish must be optional, non-nullable and have no wire default")
policy_schema = {"components": experiment["components"],
                 "$ref": "#/components/schemas/AgentJourneyGoalCompletionPolicy"}
validator = Draft7Validator(policy_schema)
old_schema = deepcopy(policy_schema)
del old_schema["components"]["schemas"]["AgentJourneyGoalCompletionPolicy"]["properties"]["requireCustomerFinish"]
old_validator = Draft7Validator(old_schema)
example = {"mode": "GOAL", "goalIndex": 0,
           "partnerResponseConditions": [{"pointer": "/status", "oneOf": ["ok"]}],
           "requestFactBindings": [], "maxCustomerDecisions": 8,
           "maxWallTimeMs": 900000, "maxRepeatedExchanges": 3}
validator.validate(example)
old_validator.validate(example)
for value in (False, True):
    explicit = example | {"requireCustomerFinish": value}
    validator.validate(explicit)
    if old_validator.is_valid(explicit):
        raise SystemExit("Older goal contracts must reject explicit requireCustomerFinish")
for value in (None, "true", "false", 0, 1):
    if validator.is_valid(example | {"requireCustomerFinish": value}):
        raise SystemExit(f"requireCustomerFinish accepted a non-Boolean value: {value!r}")

for mode in ("VALIDATE", "RESOLVE_TRUSTED"):
    validator.validate(example | {"requestFactBindingMode": mode})
for invalid in (None, "", "validate", "REPAIR", True, 1, [], {}):
    if validator.is_valid(example | {"requestFactBindingMode": invalid}):
        raise SystemExit(f"requestFactBindingMode accepted an invalid mode: {invalid!r}")

# Exercise the additive launch classification through the canonical schema.
launch_validator = Draft7Validator({"components": experiment["components"],
                                   "$ref": "#/components/schemas/AgentJourneyLaunchRequest"})
launch = {"requestId": "00000000-0000-4000-8000-000000000001",
          "catalogAgentId": "00000000-0000-4000-8000-000000000002",
          "catalogRevisionId": "00000000-0000-4000-8000-000000000003",
          "catalogDefinitionDigest": "sha256:" + "a" * 64,
          "instruction": "Review the supplied information."}
launch_validator.validate(launch)
for domain_id in ("banking", "marketing-ops", "custom.domain_1", "a" * 128):
    launch_validator.validate(launch | {"domainId": domain_id})
for invalid in (None, "", "Banking", " banking", "banking/retail", "a" * 129, True, 1, [], {}):
    if launch_validator.is_valid(launch | {"domainId": invalid}):
        raise SystemExit(f"domainId accepted an invalid classification: {invalid!r}")

# Exercise run-library query values and additive response compatibility.
run_query = experiment["paths"]["/api/simulation-runs"]["get"]["parameters"]
run_formats = FormatChecker()
@run_formats.checks("date-time", raises=ValueError)
def is_offset_datetime(value):
    if not isinstance(value, str):
        return True
    return datetime.fromisoformat(value.replace("Z", "+00:00")).utcoffset() is not None

query_validator = Draft7Validator({"type": "object", "properties": {
    parameter["name"]: parameter["schema"] for parameter in run_query},
    "additionalProperties": False}, format_checker=run_formats)
for query in ({}, {"limit": 1, "includeTotal": False},
              {"q": "Review 50%_", "domainId": "banking", "domainClassification": "known",
               "status": "COMPLETED", "createdAfter": "2026-01-01T00:00:00Z",
               "createdBefore": "2026-12-31T00:00:00Z", "cursor": "opaque_123-A"},
              {"domainClassification": "unknown", "q": "a" * 160, "limit": 100}):
    query_validator.validate(query)
for query in ({"limit": 0}, {"limit": 101}, {"q": "a" * 161},
              {"domainId": "Banking"}, {"domainClassification": "missing"},
              {"status": "completed"}, {"status": "A" * 65},
              {"createdAfter": "yesterday"}, {"cursor": "not+padded="},
              {"cursor": "a" * 2049}, {"includeTotal": "false"}):
    if query_validator.is_valid(query):
        raise SystemExit(f"Run history query accepted an invalid value: {query!r}")
# OpenAPI 3 nullable is converted only for this executable JSON Schema check.
run_list_schema = deepcopy(experiment["components"]["schemas"]["SimulationRunListResponse"])
for field in run_list_schema["properties"].values():
    if field.pop("nullable", False):
        field["type"] = [field["type"], "null"]
run_list_validator = Draft7Validator(run_list_schema, format_checker=run_formats)
legacy_page = {"schemaVersion": "simulation_run_evidence.v1", "experimentId": "agent-journey", "runs": []}
run_list_validator.validate(legacy_page)
run_list_validator.validate(legacy_page | {"experimentId": "all", "scope": "all", "hasMore": False,
    "nextCursor": None, "snapshotAt": "2026-01-01T00:00:00Z", "sort": "createdAt:desc,runId:desc"})
run_list_validator.validate(legacy_page | {"hasMore": True, "nextCursor": "opaque_123-A"})
for invalid in ({"hasMore": "true"}, {"nextCursor": 1}, {"snapshotAt": "yesterday"}, {"sort": "name"}):
    if run_list_validator.is_valid(legacy_page | invalid):
        raise SystemExit(f"Run history response accepted an invalid page value: {invalid!r}")

# Domain-aware customer MCP inventory and frozen grants stay additive.
common = documents["openapi/core/common.yaml"]
def common_validator(name):
    components = deepcopy(common["components"])
    # OpenAPI nullable is a JSON null union for executable JSON Schema checks.
    continuation = components["schemas"]["CustomerMcpBindings"]["properties"]["nextBindingKey"]
    continuation["type"] = ["string", "null"]
    return Draft7Validator({"components": components, "$ref": "#/components/schemas/" + name})

binding = {"bindingKey": "customer-tools", "bindingRevision": "revision-1", "bindingDigest": "sha256:" + "a" * 64,
           "allowedDomainIds": []}
inventory_validator = common_validator("CustomerMcpBindings")
for domains in ([], ["banking"], ["banking", "marketing-ops"]):
    inventory_validator.validate({"schemaVersion": "astraform.mcp-bindings.v1", "hasMore": False, "nextBindingKey": None,
                                  "bindings": [binding | {"allowedDomainIds": domains}]})
for invalid in (None, "banking", [None], ["Banking"], ["banking", "banking"], ["a" * 129],
                ["domain-" + str(index) for index in range(65)]):
    value = {"schemaVersion": "astraform.mcp-bindings.v1", "hasMore": False, "nextBindingKey": None, "bindings": [binding | {"allowedDomainIds": invalid}]}
    if inventory_validator.is_valid(value):
        raise SystemExit(f"Customer MCP inventory accepted invalid domain restrictions: {invalid!r}")
inventory_validator.validate({"schemaVersion": "astraform.mcp-bindings.v1", "bindings": [binding],
                              "hasMore": True, "nextBindingKey": binding["bindingKey"]})
inventory_query = experiment["paths"]["/api/simulation-events/mcp-bindings"]["get"]["parameters"]
inventory_query_validator = Draft7Validator({"type": "object", "properties": {
    parameter["name"]: parameter["schema"] for parameter in inventory_query}, "additionalProperties": False})
for value in ({}, {"limit": 1, "domainId": "banking"}, {"limit": 100, "afterBindingKey": "customer-tools"}):
    inventory_query_validator.validate(value)
for value in ({"limit": 0}, {"limit": 101}, {"afterBindingKey": "Banking"}, {"domainId": "banking/retail"}):
    if inventory_query_validator.is_valid(value):
        raise SystemExit(f"Customer MCP inventory accepted an invalid page query: {value!r}")
capabilities = {"schemaVersion": "astraform.mcp-capabilities.v1", **{key: binding[key] for key in
                ("bindingKey", "bindingRevision", "bindingDigest")}, "serverInfo": {}, "tools": []}
capability_validator = common_validator("CustomerMcpCapabilities")
capability_validator.validate(capabilities)
capability_validator.validate(capabilities | {"allowedDomainIds": ["banking", "marketing-ops"]})
if capability_validator.is_valid(capabilities | {"allowedDomainIds": None}):
    raise SystemExit("Customer MCP capabilities accepted a null domain restriction")
grant = {"kind": "MCP", **{key: binding[key] for key in ("bindingKey", "bindingRevision", "bindingDigest")},
         "toolName": "read_customer", "descriptorDigest": "sha256:" + "b" * 64,
         "inputSchemaDigest": "sha256:" + "c" * 64, "outputSchemaDigest": "sha256:" + "d" * 64,
         "effectClass": "READ_ONLY", "scope": "CUSTOMER_CONTEXT", "maxCalls": 1,
         "description": "Read the selected customer.", "inputSchema": {}, "outputSchema": {}}
grant_validator = common_validator("ResolvedMcpToolGrant")
grant_validator.validate(grant)
for domain in ("banking", "marketing-ops"):
    grant_validator.validate(grant | {"domainId": domain})
for invalid in (None, "", "Banking", "banking/retail", True, 1, [], {}):
    if grant_validator.is_valid(grant | {"domainId": invalid}):
        raise SystemExit(f"Resolved MCP grant accepted invalid frozen domain identity: {invalid!r}")

reference_count = 0
operation_count = 0

def inspect(value, source):
    global reference_count
    if isinstance(value, list):
        for item in value:
            inspect(item, source)
    elif isinstance(value, dict):
        if "$ref" in value:
            reference_count += 1
            target, _, fragment = value["$ref"].partition("#")
            if ":" in target or target.startswith("/"):
                raise ValueError(f"External reference is not portable: {value['$ref']}")
            path = ((root / source).parent / target).resolve() if target else (root / source).resolve()
            relative = path.relative_to(root.resolve()).as_posix()
            if relative not in documents:
                raise ValueError(f"Reference is outside the public OpenAPI documents: {value['$ref']}")
            resolved = documents[relative]
            if fragment:
                if not fragment.startswith("/"):
                    raise ValueError(f"Reference fragment must be a JSON pointer: {value['$ref']}")
                for part in fragment[1:].split("/"):
                    resolved = resolved[unquote(part).replace("~1", "/").replace("~0", "~")]
        for item in value.values():
            inspect(item, source)

for relative, document in documents.items():
    if document.get("openapi") != "3.0.3" or document.get("info", {}).get("version") != version:
        raise SystemExit(f"OpenAPI/version mismatch in {relative}")
    if "InternalSimulationEventToken" in document.get("components", {}).get("securitySchemes", {}):
        raise SystemExit(f"Internal runtime authentication cannot enter the public bundle: {relative}")
    for path, operations in document.get("paths", {}).items():
        if not path.startswith("/api/") or "/internal/" in path:
            raise SystemExit(f"Non-public operation path in {relative}: {path}")
        operation_count += sum(key in {"get", "put", "post", "delete", "patch", "head", "options", "trace"}
                               for key in operations)
    inspect(document, relative)
if documents["openapi/core/common.yaml"]["paths"]:
    raise SystemExit("Shared schemas must not introduce operations")
print(f"Verified platform-api {version}: {len(documents)} OpenAPI files, {operation_count} operations, {reference_count} resolved references")
