# Astraform Public Contracts 1.2.1 — unreleased local candidate

This local candidate packages strict customer completion and the existing native
completion-update correlation fields. It has not been committed, published or
validated as a public release. Both archives share source version 1.2.1; consumers
select them explicitly as LOCAL_PRERELEASE inputs with truthful checksums and
provenance. Published 1.2.0 and earlier assets remain immutable.

The optional non-null `requireCustomerFinish` Boolean has no wire default:
omission/false preserve receipt-qualified stopping, true requires the customer
to FINISH as well as satisfy the configured receipt conditions. Explicit null or
non-Boolean values are invalid. Native updates retain `runId`, `operationId`,
`inputDigest` and `providerRevision` as optional non-null strings. SDK generation
and actual typed request/response/sample verification remain separate gates.
Protocol/profile identifiers, API paths, safety limits and existing product
restoration obligations remain unchanged. Public contract/SDK publication and
consumer pin/artifact adoption require later reviewed delivery.

## Earlier 1.2.0 release notes — preserved history

# Astraform Public Contracts 1.2.0

The provider and platform API contracts now share one version and one release:
[`v1.2.0`](https://github.com/astraform/remote-domain-contracts/releases/tag/v1.2.0),
published on 6 October 2026. The repository-root `VERSION` owns that version,
and CI verifies it against both bundle manifests, bundled version files and
OpenAPI documents.

## What changes

- Adds the public platform API bundle for customer authoring, capability
  discovery, Agent Journey, simulation results, experiment registry, Scenario
  Lab, evaluation and MCP management. Shared payloads live in the schema-only
  `core/common.yaml`; internal runtime commands and their authentication remain
  outside the public bundle.
- Preserves existing API operation IDs, routes, request/response validation and
  generated SDK namespaces. The partner SDK still generates from the Experiment
  entry point; including additional documents does not expand SDK or deployment
  gateway capabilities.
- Aligns the provider bundle metadata to `1.2.0` without changing its wire
  payloads or protocol/profile identifiers. `remote-domain.v1` remains the
  provider protocol.
- Publishes both bundles together. The previous bundle selector and separate
  release-tag tracks are removed. One root release-notes file supplies the
  entire GitHub release body.

## Release artifacts

The single `v1.2.0` release contains:

- `remote-domain.v1.zip` and `remote-domain.v1.zip.sha256`.
- `platform-api.zip` and `platform-api.zip.sha256`.

Archive roots remain `remote-domain.v1/` and `platform-api/`, preserving consumer
paths. Both archives are verified after upload before the release is published.
Existing published releases, including `remote-domain-v1.1.0`, remain unchanged.

## Consumer upgrade

Pin both inputs to the published `v1.2.0` assets with their respective verified ZIP
checksums and regenerate/build the SDKs. The Java and Python author kits each
package the provider adapter and platform client together; their package versions
remain separate from this contract release version. Platform implementation
versions also remain separate.

Local ZIP builds are explicit development inputs; normal consumers use the
published assets. Later source documentation corrections do not alter those
immutable archives or their checksums. SDK publication remains a separate step.
See [CHANGELOG.md](CHANGELOG.md) for historical release details.
