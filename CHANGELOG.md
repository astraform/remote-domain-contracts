# Changelog

Notable changes to the remote-domain contract bundle are recorded here. Bundle
release versions are separate from the `remote-domain.v1` protocol, native profile
identifiers and Java/Python SDK versions. Unreleased changes are not a published
contract dependency.

## 1.1.0 — Unreleased

Prepared on 2026-09-27; package publication remains a separate step.

### Added

- Optional `capabilities.nativeSimulation` with two profiles: pure opaque-state
  transformation and partner-owned transactional reference state.
- Native profile schemas and documentation for preparation, bounded logical-time
  work windows, accepted state versions, observations and next-work boundaries.
- Read-only customer tool descriptors with output schema, revision, effect class
  and scope, plus their request and unchanged-checkpoint response requirements.
- Reference-state requirements for attaching prepopulated customer records,
  replayable transactional receipts and causally guarded customer/partner reads.
- OpenAPI profile discrimination for generated models and packaging metadata for
  both native profiles.

### Changed

- Bundle metadata and OpenAPI `info.version` are aligned to 1.1.0. Protocol and
  native profile identifiers remain unchanged.
- During active development, legacy v1 compatibility checks retain only the
  latest published baseline, 1.0.4, using existing fixtures and customer-trigger
  probes. Historical 1.0.0 and 1.0.1 comparisons are removed.
- Contract packaging excludes `.DS_Store` workstation metadata.
- CI verifies and packages changes pushed to any branch; GitHub Actions are
  pinned to full commit SHAs. Pull-request and manual CI triggers remain enabled.
- Release publication uses maintained release notes without a separate
  missing/empty/draft validation step.

### Compatibility and status

Native profiles are opt-in. Existing payloads that omit the new capabilities
retain their existing semantics. Native-enabled manifests require updated SDKs
and validators; older closed manifest schemas can reject the new fields.
The new OpenAPI tool descriptor closes extra properties to match the existing
JSON Schema restriction.

This entry describes the prepared 1.1.0 bundle; it does not claim that the
GitHub release has been published. Publish it under the new immutable tag
`remote-domain-v1.1.0`, preserving the existing 1.0.4 release. See
[the 1.1.0 release notes](RELEASE_NOTES.md) for scope and upgrade instructions.

## 1.0.4 — 2026-07-24

Published baseline before the unreleased changes above. Earlier releases retain
their original GitHub release history.

- [Published 1.0.4 release](https://github.com/astraform/remote-domain-contracts/releases/tag/remote-domain-v1.0.4)
- [Earlier releases](https://github.com/astraform/remote-domain-contracts/releases)
