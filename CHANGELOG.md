# Changelog

Notable changes to the public contract bundles are recorded here. Bundle
release versions are separate from the `remote-domain.v1` protocol, native profile
identifiers and Java/Python SDK versions. Unreleased changes are not a published
contract dependency.

## Platform API 0.1.1 — Unreleased

- Adds the canonical public platform API bundle alongside the independently
  versioned provider contract. It includes Experiment/Simulation, evaluation and
  MCP management APIs with shared public schemas, without internal runtime routes
  or deployment authentication declarations.
- Preserves existing operation IDs and payload validation while moving shared
  simulation schemas out of the internal runtime OpenAPI document.
- Extends the existing packaging, verification and immutable release workflow to
  select either bundle. Planned platform tag: `platform-api-v0.1.1`.
- Consolidates both bundles' release notes in the root `RELEASE_NOTES.md`;
  publication selects the section matching the release tag.

## Remote Domain 1.1.0 — Published

Prepared on 2026-09-27 and published as `remote-domain-v1.1.0`. The unchanged
bundle remains independent of the new platform API artifact.

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

Published as `remote-domain-v1.1.0`, preserving the existing 1.0.4 release.
See [the 1.1.0 release notes](RELEASE_NOTES.md#remote-domain-v110) for scope
and upgrade instructions.

## 1.0.4 — 2026-07-24

Published baseline preceding 1.1.0. Earlier releases retain
their original GitHub release history.

- [Published 1.0.4 release](https://github.com/astraform/remote-domain-contracts/releases/tag/remote-domain-v1.0.4)
- [Earlier releases](https://github.com/astraform/remote-domain-contracts/releases)
