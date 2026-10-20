# Changelog

Notable changes to the public contracts are recorded here. From 1.2.0, both
bundles share the repository-root release version and ship together. Protocol,
native profile, platform application and Java/Python SDK versions remain separate.
Unreleased changes are not a published contract dependency.

## 1.2.3 — Unreleased

### Added

- Owner-scoped domain connection registry operations for immutable A2A,
  native-domain and customer MCP revisions, bounded listings, capability probes,
  approval, activation, retirement and revocation. Mutations retain request replay
  identity and use expected versions for concurrency control.
- Deployment-operator bearer authorization with separate lifecycle permissions.
  The server derives registry ownership; permitted origins and credential
  references remain deployment policy and credentials stay out of registration.
- `getDomainConnectionCapabilities` for approved active revisions, returning the
  connection head, exact revision and sanitized capability metadata through
  generated native clients.
- Optional non-null `AgentJourneyLaunchRequest.connectionSelection: REGISTERED`
  without a wire default, conditional `EXECUTE` authorization and typed launch
  `401`/`403` responses. Registered launches select permitted active approved
  revisions and retain exact accepted identities. Existing Catalog tool grants
  must match selected binding/provider/descriptor identities.

### Compatibility

- Omitting registered selection preserves startup bindings and launch identity.
  Accepted runs retain their revisions after activation changes; replay retains
  run identity and selection while operational status may advance. A supporting
  platform can consume new approved bindings without restarting Runtime.
- Retirement blocks new selection while permitting accepted work; revocation
  blocks subsequent governed dispatch. In-flight effects can remain uncertain.
  Committed A2A receipts preserve recovery identity without another send, including
  when authority is denied or unavailable. Startup-selected bindings remain a
  separate deployment path.
- This surface requires a supporting platform and regenerated SDK. It does not
  provide department identity, enterprise isolation, arbitrary hot destination or
  secret changes, or model/embedding hot swapping. Existing provider protocol and
  profile identifiers, discovery signatures and historical assets remain unchanged.
- Root version, both bundle manifests/version files and all OpenAPI metadata
  target 1.2.3. Both archives ship together with separate SHA-256 checksums.

## 1.2.2 — Published 2026-10-18

Published as [`v1.2.2`](https://github.com/astraform/remote-domain-contracts/releases/tag/v1.2.2)
with both contract ZIP assets and their SHA-256 checksums.

### Added

- Explicit optional launch `domainId`, frozen with the run identity, and
  cross-domain run discovery with name/ID, domain/classification, status and
  creation-time filters, opaque cursor pagination and optional exact totals.
- Paginated deployment-configured customer MCP binding discovery, domain
  eligibility allowlists and frozen domain identity on restricted tool grants.
  Inventory reads do not contact MCP endpoints or expose URLs/credentials.
- `domain_assessment.v1` and typed suite/scenario schemas for domain-owned
  assessments, including evaluator/rubric/configuration and decoded-evidence
  identity, native results, references and arbitrary metrics.
- `evaluation.v2` report states including `NOT_ASSESSED` and `ERROR`, nullable
  scores, coverage counts and explicit comparison status/reasons. Compatible
  qualitative results need no numeric score; missing or incompatible metrics
  retain explanations without fabricated deltas. Historical v1 report fields
  and legacy dimension definitions remain available.
- Optional `astraform.result-presentation.v1` annotations for captured A2A/MCP
  results, with bounded same-result labels/pointers, text/currency/date formats,
  a provider guide and banking/marketing examples. Presentation preserves source
  values and has no execution, permission or outcome authority.
- Opt-in `completionPolicy.requestFactBindingMode: RESOLVE_TRUSTED` for
  authoritative outgoing metadata, preserving original model proposals,
  customer-selected actions and unbound facts while freezing validated resolved
  requests for transport and retries. Omission/`VALIDATE` retains prior behavior;
  explicit null is invalid and no wire default is introduced.

### Changed and compatibility

- Omitting `experimentId` when listing runs now selects all experiments. Supply
  an explicit experiment ID to retain the former scope. Cursor continuation
  retains a creation-time boundary; updates to existing runs remain live.
- New assessment states and nullable scores/deltas require supporting readers.
  The six evaluation routes already existed; their payloads are extended.
  Evidence digests identify decoded canonical JSON rather than original bytes;
  encode exact values beyond binary64 precision as strings.
- Domain classification/MCP eligibility does not establish organizational or
  tenant authorization. Submitted assessments do not establish authenticated
  evaluator provenance or immutable native evidence. New annotations can appear
  in model-visible replies and do not guarantee identical later decisions.
- Root, both bundle manifests/version files and OpenAPI metadata aligned to 1.2.2;
  provider protocol/profile identifiers, archive roots and historical published
  assets remain unchanged. The two existing ZIPs ship together with separate
  SHA-256 checksums. Platform and SDK implementation/publication remain separate;
  regenerate compatible consumers from an explicitly selected contract release.

## 1.2.1 — Published 2026-10-14

Published as [`v1.2.1`](https://github.com/astraform/remote-domain-contracts/releases/tag/v1.2.1)
with both contract ZIP assets and their SHA-256 checksums.

- Packages the existing optional non-null `requireCustomerFinish` Boolean without
  a wire default; omission/false retain legacy completion and true requires
  customer FINISH plus configured receipt evidence. Null/non-Boolean values are
  invalid and must not be silently omitted or coerced by generated SDKs.
- Includes the existing four optional non-null completion-update correlation
  strings, preserving operation and evidence identity through native clients.
- Aligns root/both bundle metadata and every OpenAPI version to 1.2.1 while
  retaining protocol/profile identifiers and immutable earlier release assets.

## 1.2.0 — Published 2026-10-06

Published as [`v1.2.0`](https://github.com/astraform/remote-domain-contracts/releases/tag/v1.2.0)
with both contract ZIP assets and their SHA-256 checksums.

- Adds the canonical public platform API bundle alongside the provider contract,
  including Experiment/Simulation, evaluation and MCP management APIs with shared
  public schemas. Internal runtime routes and authentication remain private.
- Preserves existing operation IDs and payload validation while moving shared
  simulation schemas out of the internal runtime OpenAPI document.
- Introduces a root `VERSION`, mirrored in both bundles' version files, manifests
  and OpenAPI documents, with alignment checked by the existing verifiers.
- Replaces separate bundle release tracks with one `v1.2.0` release containing
  both existing ZIP assets and their checksums. Historical provider tags and
  artifacts are unchanged.
- Uses the complete root `RELEASE_NOTES.md` as the current release body.

## Remote Domain 1.1.0 — Published

Prepared on 2026-09-27 and published as `remote-domain-v1.1.0`. This historical
provider-only release and its assets remain unchanged.

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
See [the published 1.1.0 release notes](https://github.com/astraform/remote-domain-contracts/releases/tag/remote-domain-v1.1.0)
for scope and upgrade instructions.

## 1.0.4 — 2026-07-24

Published baseline preceding 1.1.0. Earlier releases retain
their original GitHub release history.

- [Published 1.0.4 release](https://github.com/astraform/remote-domain-contracts/releases/tag/remote-domain-v1.0.4)
- [Earlier releases](https://github.com/astraform/remote-domain-contracts/releases)
