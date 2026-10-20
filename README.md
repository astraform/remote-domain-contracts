# Astraform Public Contracts

Canonical public API definitions for partner services, SDK generation and the
Astraform platform. Implementation code stays in the platform and SDK
repositories. The existing repository name remains `remote-domain-contracts`.

## Prepared 1.2.3 — unreleased

Source metadata targets shared contract 1.2.3. It adds owner-scoped connection
registration, discovery, approval and activation, plus opt-in Agent Journey
`connectionSelection: REGISTERED`. Approved active revisions can be selected
without restarting Runtime; accepted runs retain their exact frozen revisions.
This requires a matching platform implementation, deployment-configured operator
permissions and generated SDK support. Published Java 0.4.4 and Python 0.3.4 do
not include these operations. See the
[platform guide](platform-api/v1/README.md#governed-connection-registry-123-prepared).

Select both development bundles explicitly as `LOCAL_PRERELEASE` inputs when
generating local SDKs. Published 1.2.2 remains the normal pinned dependency;
its archives and all earlier archives/checksums remain immutable. Preparing or
packaging these sources does not publish a contract, deploy a platform or release
an SDK.

## Contract bundles

| Bundle | Purpose | Shared release |
| --- | --- | --- |
| `remote-domain/v1/` | Astraform Runtime calls partner-hosted domain services | [`1.2.2`, tag `v1.2.2`](https://github.com/astraform/remote-domain-contracts/releases/tag/v1.2.2) |
| `platform-api/v1/` | Partner applications and authorized operators call Astraform-hosted APIs | [`1.2.2`, tag `v1.2.2`](https://github.com/astraform/remote-domain-contracts/releases/tag/v1.2.2) |

The repository-root `VERSION` owns one release version for both bundles. Each
bundle's `VERSION`, manifest and OpenAPI `info.version` must match it. One GitHub
release publishes both ZIP assets and their SHA-256 checksums together. Separate
archives preserve existing SDK and platform dependency paths; they are not
separate releases. SDK package and protocol versions remain separate.

The latest published shared release is
[`v1.2.2`](https://github.com/astraform/remote-domain-contracts/releases/tag/v1.2.2).
Its archives and checksums, and all earlier releases, remain immutable.

The provider bundle contains its OpenAPI, JSON schemas, protocol documentation
and sample payloads. The platform bundle contains:

- `openapi/platform/experiment/experiments.yaml`: customer authoring, capability
  discovery, Agent Journey, simulation results, experiment registry and Scenario Lab APIs.
- `openapi/core/common.yaml`: shared payload schemas without operations.
- `openapi/platform/experiment/evaluation.yaml`: evaluation APIs.
- `openapi/core/mcp-management.yaml`: tool and MCP server management APIs.
- `openapi/platform/experiment/domain-connections.yaml`: governed connection
  registry APIs, also referenced by the Experiment entry point in prepared 1.2.3.

Public customer and simulation payload schemas belong to this repository.
Internal runtime commands and authentication declarations remain in the private
platform repository; the runtime consumes these same shared public schemas.
Including a public API definition does not imply that every deployment gateway
exposes every route.
The current partner SDK still generates from the Experiment entry point only.
Use native Java/Python SDK clients for partner applications and samples. A
contract definition alone does not add operations to an installed SDK.

## Verify and package

Use Python 3.12 or newer:

```bash
scripts/verify-all.sh
scripts/package-remote-domain-contract.sh
scripts/package-remote-domain-contract.sh --bundle platform-api
```

The verifier creates an isolated `.venv/` using `requirements-verify.txt`. It
checks the shared version, both bundle manifests, current provider schemas and fixtures, all public
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

Normal builds consume the published `v1.2.2` assets with their pinned checksums;
a local contract checkout or ZIP is not required. Only for explicit contract
development, package the bundles above and supply their absolute ZIP paths.
For the platform API development input:

- Java SDK/platform: `-Dplatform.api.contract.zip=/absolute/path/platform-api.zip`.
- Python SDK: `ASTRAFORM_PLATFORM_API_ZIP=/absolute/path/platform-api.zip`.

Published archives are immutable snapshots. Later source documentation corrections
do not update those archives or their checksums; a rebuilt local ZIP is a
development input, not a replacement for the published asset.

Use clean builds when switching contract inputs. Local ZIP artifacts are marked
`LOCAL_PRERELEASE`; publication rejects them. Normal builds do not silently select
local archives or sibling repositories. They require the pinned release to exist.

For provider contract development, Java accepts
`-Dremote-domain.contract.zip=/absolute/path/remote-domain.v1.zip`; each SDK's
`scripts/sync-remote-domain-contract.sh --zip /absolute/path/remote-domain.v1.zip`
can explicitly inspect that local input. Use the SDK build guides for its local
selection; resolving a local archive does not change normal release selection.

## Release

See the root [release notes](RELEASE_NOTES.md) for the current release and
[changelog](CHANGELOG.md) for release history. The workflow uses the entire root
release-notes file as the body of the single GitHub release.

1. Update the root `VERSION`, both bundled `VERSION` files, both manifests and
   all OpenAPI `info.version` fields together, even when only one API changes.
   Select a new unused version; never change an already published asset.
2. Update the root `RELEASE_NOTES.md` and changelog. Verify and package both bundles
   from the final revision.
3. Merge reviewed changes to `main`.
4. Run **Public Contract Release** (`.github/workflows/release.yml`) from `main`
   with the matching new unused version. There is no bundle selector or dry-run
   mode. This workflow publishes; CI is the non-publishing verification path.
5. Verify both GitHub Release ZIPs and checksums, then update platform and SDK
   pins to the same release tag and their respective asset checksums.
6. Publish new SDK versions and verify registry availability before upgrading
   partner samples. Green local builds do not establish release availability.

The workflow checks that release commits belong to `main`, verifies tag identity,
rejects an existing release, and verifies both uploaded archives and checksums
before publishing its draft. Tag-triggered publication is also supported for
`v<version>` at a commit on `main`, provided the `contract-release` environment
permits `v*` tags. With a branch-only environment policy, use manual publication
from `main`. Historical `remote-domain-v*` tags remain available
but no longer trigger publication. New releases use only the shared `v*` track.
