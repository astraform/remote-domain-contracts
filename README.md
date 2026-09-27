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

See the [changelog](CHANGELOG.md) and [1.1.0 release notes](RELEASE_NOTES.md).
This checkout targets contract bundle `1.1.0`, with release tag
`remote-domain-v1.1.0`. The bundle metadata and OpenAPI document version agree.
Version preparation does not publish a release: verify that the matching GitHub
Release and checksum exist before pinning it as an SDK dependency. Native profile
additions are new since the published 1.0.4 baseline.

CI verifies and packages changes pushed to any branch, plus pull requests and
manual runs. Release publication remains separate: it runs on a
`remote-domain-v*` tag or a manual dispatch and requires a commit on `main`.

After publication, public SDKs should pin the new release tag and verify its
checksum before using the bundle for code generation or conformance tests.

## Local Packaging

Run the public verifier from a clean checkout with one command:

```bash
scripts/verify-all.sh
```

The runner creates an isolated Python 3.12+ environment under `.venv/` and
installs the complete dependency set pinned in `requirements-verify.txt`.
It verifies contract metadata, schemas, signed profile samples, and all current
wire fixtures against the latest published baseline, `remote-domain-v1.0.4`.
That tag must be available in the local clone. It also verifies that selected
old-valid customer-trigger payloads remain valid under the current schema.
During active development, compatibility checks retain this baseline rather
than a matrix of older releases. These fixture checks protect legacy usage;
they do not make new native capabilities compatible with older closed manifest
schemas or prove complete SDK/runtime compatibility.

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

1. Update `remote-domain/v1/` and assign a new, unused bundle version in
   `remote-domain/v1/VERSION`, `remote-domain/v1/manifest.json` and OpenAPI
   `info.version`. Protocol and profile identifiers retain their own versions.
2. Update `RELEASE_NOTES.md` and the version entry in `CHANGELOG.md`. The workflow
   uses the notes file for the GitHub release body without a separate release-note
   validation step.
3. Run `scripts/verify-all.sh` and `scripts/package-remote-domain-contract.sh`
   against the final revision.
4. Merge the reviewed changes to `main`, then trigger
   `.github/workflows/release.yml` from `main` with the matching version, or push
   its matching release tag pointing at a commit already on `main`.
5. Verify the published ZIP and checksum before updating downstream SDK locks.

`RELEASE_NOTES.md` holds the current release's detailed notes. GitHub Releases
retain the published copies; `CHANGELOG.md` retains the version history.

Use additive optional changes within `remote-domain.v1` only when old clients
can safely ignore them. Breaking wire changes require a new protocol directory,
for example `remote-domain/v2/`.

## Cross-Repository Release Train

Contract, SDK, provider, and runtime releases are separate immutable artifacts.
Publish them in dependency order; a green local snapshot is not a substitute for
a published upstream release.

The next release train starts with contract `1.1.0`. Java SDK `0.3.0` is being
prepared separately; SDK package versions do not need to equal the contract
bundle version.

1. Publish the updated `remote-domain.v1` bundle and verify its release checksum.
2. Update both SDK release locks to that tag/checksum and resync their contract
   snapshots. Run each SDK's remote `sync-remote-domain-contract.sh --check` and
   package validation, then publish its new Java or Python package version.
3. Verify the SDK packages from Maven Central and PyPI before changing provider
   dependencies or generating new signed conformance attestations.
4. Upgrade sample/provider builds, run the relevant provider conformance and
   native behavior checks, and deploy the resulting artifacts and any required
   attestations together.
5. Where runtime trust uses an SDK allowlist, explicitly permit the validated new
   version during rollout. Retire the previous entry only after every authorized
   provider has been rebuilt and its new attestation is live.

SDK release workflows deliberately use the remote `--check` path. They must
fail before step 1 exists; bypassing that failure would publish SDK metadata for
an unavailable contract artifact.
