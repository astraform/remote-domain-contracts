# Astraform Public Contracts

Canonical public API definitions for partner services, SDK generation and the
Astraform platform. Implementation code stays in the platform and SDK
repositories. The existing repository name remains `remote-domain-contracts`.

## Contract bundles

| Bundle | Purpose | Version and release |
| --- | --- | --- |
| `remote-domain/v1/` | Astraform calls partner domain services | Published `1.1.0`, tag `remote-domain-v1.1.0` |
| `platform-api/v1/` | Partner applications call Astraform; shared platform API schemas | Prepared `0.1.1`, planned tag `platform-api-v0.1.1`, **unpublished** |

Each bundle has its own `VERSION`, manifest, immutable ZIP and SHA-256 checksum.
Their versions are independent of SDK package versions.

The provider bundle contains its OpenAPI, JSON schemas, protocol documentation
and sample payloads. The platform bundle contains:

- `openapi/platform/experiment/experiments.yaml`: customer authoring, capability
  discovery, Agent Journey, simulation results, experiment registry and Scenario Lab APIs.
- `openapi/core/common.yaml`: shared payload schemas without operations.
- `openapi/platform/experiment/evaluation.yaml`: evaluation APIs.
- `openapi/core/mcp-management.yaml`: tool and MCP server management APIs.

Internal runtime commands and authentication declarations remain in the platform
repository. Its runtime uses the same shared public schemas. Including a public
API definition does not imply that every deployment gateway exposes every route.
The current partner SDK still generates from the Experiment entry point only.

## Verify and package

Use Python 3.12 or newer:

```bash
scripts/verify-all.sh
scripts/package-remote-domain-contract.sh
scripts/package-remote-domain-contract.sh --bundle platform-api
```

The verifier creates an isolated `.venv/` using `requirements-verify.txt`. It
checks both bundle manifests, current provider schemas and fixtures, all public
platform OpenAPI references, and the existing provider compatibility baseline
`remote-domain-v1.0.4`. That tag must be available locally for the compatibility
check. `scripts/verify-all.sh --contract-only` omits that historical check.

The package command retains its existing optional output-directory argument.
It emits deterministic archives:

```text
build/remote-domain-contract/remote-domain.v1.zip  -> remote-domain.v1/
build/platform-api-contract/platform-api.zip      -> platform-api/
```

CI verifies and packages both bundles on every branch, pull request and manual
run. No platform or SDK sibling checkout is required to verify or package them.

## Use in platform and SDK builds

Consumers pin a published tag, asset and checksum and resolve the dependency into
an ignored build cache. They do not maintain editable contract copies. Validation
schemas needed at runtime are still included in built SDK artifacts.

The initial platform API bundle is not published yet. For local development,
package it above and explicitly supply its absolute ZIP path to each build:

- Java SDK/platform: `-Dplatform.api.contract.zip=/absolute/path/platform-api.zip`.
- Python SDK: `ASTRAFORM_PLATFORM_API_ZIP=/absolute/path/platform-api.zip`.

Use clean builds when switching contract inputs. Local ZIP artifacts are marked
`LOCAL_PRERELEASE`; publication rejects them. Normal builds do not silently select
local archives or sibling repositories. They require the pinned release to exist.

For provider contract development, Java accepts
`-Dremote-domain.contract.zip=/absolute/path/remote-domain.v1.zip`; each SDK's
`scripts/sync-remote-domain-contract.sh --zip /absolute/path/remote-domain.v1.zip`
can explicitly inspect that local input. Use the SDK build guides for its local
selection; resolving a local archive does not change normal release selection.

## Release

See the root [release notes](RELEASE_NOTES.md) and [changelog](CHANGELOG.md).
Both bundles share one release-notes file; the workflow publishes only the
section whose heading matches the release tag (`## <bundle>-v<version>`).

1. Update the owning bundle's sources, `VERSION`, manifest and OpenAPI versions.
   Select a new unused version; never change an already published asset.
2. Add or update its section in the root `RELEASE_NOTES.md` and the changelog.
   Verify and package the final revision.
3. Merge reviewed changes to `main`.
4. Run `.github/workflows/release.yml` from `main`, selecting `remote-domain` or
   `platform-api` and its matching version, or push the matching bundle release
   tag at a commit already on `main`. This workflow publishes; CI is the
   non-publishing verification path.
5. Verify the GitHub Release ZIP and checksum, then update platform and SDK pins.
6. Publish new SDK versions and verify registry availability before upgrading
   partner samples. Green local builds do not establish release availability.

The workflow checks that release commits belong to `main`, verifies tag identity,
rejects an existing release, and verifies uploaded archive/checksum bytes before
publishing its draft. The existing provider release remains unchanged when
publishing the separate platform API bundle.
