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

Public SDKs should pin a release tag such as `remote-domain-v1.0.1` and verify
the checksum before using the bundle for code generation or conformance tests.

## Local Packaging

Run the public verifier from a clean checkout with one command:

```bash
scripts/verify-all.sh
```

The runner creates an isolated Python 3.12+ environment under `.venv/` and
installs the complete dependency set pinned in `requirements-verify.txt`.
It verifies contract metadata, schemas, signed profile samples, and all current
wire fixtures against the published `remote-domain-v1.0.0` schema. The baseline
tag must therefore be available in the local clone.

Then package the verified contract:

```bash
scripts/package-remote-domain-contract.sh
cd build/remote-domain-contract
shasum -a 256 remote-domain.v1.zip
```

To validate unreleased contract changes against local SDK snapshots before
publishing a GitHub Release:

```bash
(cd ../remote-domain-sdk-java && ./scripts/sync-remote-domain-contract.sh --check --zip ../remote-domain-contracts/build/remote-domain-contract/remote-domain.v1.zip)
(cd ../remote-domain-sdk-python && ./scripts/sync-remote-domain-contract.sh --check --zip ../remote-domain-contracts/build/remote-domain-contract/remote-domain.v1.zip)
```

Run the same commands without `--check` to sync the SDK snapshots from the local
zip during pre-release development. Published SDK releases should still pin and
verify the GitHub Release artifact through each SDK's lock file.

## Release Process

1. Update `remote-domain/v1/`.
2. Verify `remote-domain/v1/VERSION` and `remote-domain/v1/manifest.json`
   agree.
3. Run `scripts/verify-all.sh`.
4. Run `scripts/package-remote-domain-contract.sh`.
5. Trigger `.github/workflows/release.yml` with the matching version.

Use additive optional changes within `remote-domain.v1` only when old clients
can safely ignore them. Breaking wire changes require a new protocol directory,
for example `remote-domain/v2/`.
