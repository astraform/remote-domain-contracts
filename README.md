# Astraform Remote Domain Contracts

Public machine-readable contracts for Astraform remote-domain integrations.

This repository is the public API-contract boundary for external service
authors and SDK generation. It contains protocol documents, OpenAPI, JSON
Schema, and sample payloads only. Astraform platform implementation code stays
private.

## Contents

- `remote-domain/v1/`: the public `remote-domain.v1` contract.
- `remote-domain/v1/openapi/remote-domain.yaml`: HTTP API contract.
- `remote-domain/v1/schemas/`: JSON Schema contracts for lifecycle payloads
  and reusable domain payloads.
- `remote-domain/v1/samples/`: valid example request/response payloads.
- `remote-domain/v1/docs/`: human-readable protocol guide.

## Releases

GitHub Releases publish the partner handoff bundle:

```text
remote-domain.v1.zip
remote-domain.v1.zip.sha256
```

The zip contains a top-level `remote-domain.v1/` directory with the versioned
contract, docs, schemas, and samples.

Public SDKs should pin a release tag such as `remote-domain-v1.0.0` and verify
the checksum before using the bundle for code generation or conformance tests.

## Local Packaging

```bash
scripts/package-remote-domain-contract.sh
cd build/remote-domain-contract
shasum -a 256 remote-domain.v1.zip
```

## Release Process

1. Update `remote-domain/v1/`.
2. Verify `remote-domain/v1/VERSION` and `remote-domain/v1/manifest.json`
   agree.
3. Run `scripts/package-remote-domain-contract.sh`.
4. Trigger `.github/workflows/release.yml` with the matching version.

Use additive optional changes within `remote-domain.v1` only when old clients
can safely ignore them. Breaking wire changes require a new protocol directory,
for example `remote-domain/v2/`.
