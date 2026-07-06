# remote-domain.v1 Partner Contract Bundle

This directory is the source of the partner-facing `remote-domain.v1` handoff.
It is intentionally about the wire contract, not the monorepo implementation.

## What Partners Receive

- `openapi/remote-domain.yaml`: HTTP/JSON API contract.
- `schemas/remote-domain.schema.json`: JSON Schema bundle for lifecycle payload validation.
- `schemas/*.v1.schema.json`: language-neutral schema source for reusable
  remote-domain documents such as scorecards, Wind Tunnel metadata, cohort
  bundles, population catalogs, and evidence exports.
- `docs/remote-domain-protocol-v1.md`: rendered protocol guide and ownership boundary.
- `samples/`: canonical request and response payloads for every lifecycle operation.
- `manifest.json`: bundle metadata, source provenance, and release artifact name.

## Code Generation Direction

Astraform should not let Java become the real contract by accident. The schema
source in this bundle is the cross-language source of truth.

- Java: use `openapi-generator-maven-plugin` for OpenAPI model generation.
- Python: use `datamodel-code-generator` to generate Pydantic v2 models from
  OpenAPI/JSON Schema.
- SDK author kits may add builders, adapters, and conformance helpers around
  generated models.
- Contract generation must not generate domain business behavior, CEL execution,
  scorecard execution, Spring/FastAPI adapters, or private platform internals.

## Build The Handoff Artifact

From the repository root:

```sh
scripts/package-remote-domain-contract.sh
```

The script writes `build/remote-domain-contract/remote-domain.v1/` and
`build/remote-domain-contract/remote-domain.v1.zip`.

## Versioning Rules

- `remote-domain.v1` is the protocol identifier and compatibility boundary.
- `VERSION` is the bundle release version for partner handoff.
- Breaking protocol changes require `remote-domain.v2`.
- Additive optional fields may stay in `remote-domain.v1` when old clients can ignore them safely.

## Partner Handoff

Give partner engineering teams the generated `remote-domain.v1.zip`. They should
not need to browse this repository to understand the protocol, validate payloads,
or implement the lifecycle endpoints.
