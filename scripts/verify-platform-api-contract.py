#!/usr/bin/env python3
"""Verify the public platform bundle and resolve every local OpenAPI reference."""
from __future__ import annotations

import json
from pathlib import Path
from urllib.parse import unquote
import yaml

root = Path(__file__).resolve().parents[1] / "platform-api/v1"
manifest = json.loads((root / "manifest.json").read_text())
version = (root / "VERSION").read_text().strip()
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
