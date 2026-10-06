# Astraform Public Contracts 1.2.0

The provider and platform API contracts now share one version and one release:
`v1.2.0`. The repository-root `VERSION` owns that version, and CI verifies it
against both bundle manifests, bundled version files and OpenAPI documents.

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

After publication, pin both inputs to `v1.2.0` with their respective verified ZIP
checksums and regenerate/build the SDKs. The Java and Python author kits each
package the provider adapter and platform client together; their package versions
remain separate from this contract release version. Platform implementation
versions also remain separate.

Local ZIP builds are development inputs. They do not establish that this release
or a new SDK version is available to partners. See [CHANGELOG.md](CHANGELOG.md)
for historical release details.
