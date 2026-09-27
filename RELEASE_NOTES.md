# Remote Domain Contract — Upcoming Release

Status: Draft

These notes describe changes since published bundle 1.0.4. The next bundle
version is not assigned yet: `remote-domain/v1/VERSION` and `manifest.json` still
contain 1.0.4. No new contract release is claimed. Assign a new version and update
this heading, the changelog and release status before publishing. The existing
1.0.4 release is immutable.

## What changes

The contract adds two optional native simulation profiles through existing
`remote-domain.v1` operations. The bundle now includes their JSON Schemas and
profile documentation, and OpenAPI exposes `capabilities.nativeSimulation` as
a discriminated choice between the two profile models.

- **Pure state transformation** (`remote-domain.native-state-transform.v1`): the
  host persists the complete opaque checkpoint and accepted operation receipts.
  Providers apply business rules without external effects or hidden mutable
  state. Replaying the exact request against the pinned provider revision must
  reproduce the response data.
- **Transactional reference state** (`remote-domain.native-reference-state.v1`):
  the partner owns authoritative records. Preparation attaches a customer context
  to prepopulated state. Checkpoints hold references and version metadata rather
  than business-state snapshots. Providers must atomically commit domain effects,
  version changes and replayable receipts within their transactional boundary.

Both profiles define preparation, bounded logical-time work windows, state and
provider versions, customer-visible observations, and `nextDueEpochMs` or
`noWorkBeforeEpochMs` boundaries. Preparation and subsequent windows have explicit
start-boundary semantics. These are provider/host obligations, not a scheduling
engine delivered by this repository.

The pure-state profile adds customer-scoped read-only tool declarations with
input/output schemas, revision, `READ_ONLY` effects and `CUSTOMER_CONTEXT` scope.
Calls use the existing execute-work operation and must preserve the accepted
checkpoint. The reference-state profile defines causally guarded reads through
partner-owned services, including the context, accepted resource version and
logical time carried outside model-selected arguments.

Contract packaging excludes `.DS_Store` files. CI verifies and packages pushes to
any branch, and retains pull-request/manual triggers. Release publication retains
its main-branch ancestry, immutable-tag and downloaded-asset checksum checks and
uses this file as its GitHub release body.

## Compatibility and upgrade

The protocol remains `remote-domain.v1`; native profile identifiers are separately
versioned. Existing valid payloads without native capabilities retain their
existing behavior. Opting into native fields requires upgraded SDKs and validators:
published 1.0.4 manifest schemas are closed and do not accept the new capabilities.
The OpenAPI tool descriptor now explicitly closes extra properties, consistent
with the existing JSON Schema restriction; custom undocumented fields are not
portable contract extensions.

After the new contract is published:

1. Pin its immutable release tag and verified ZIP checksum in each SDK's contract
   lock, then resync/regenerate SDK sources and packaged schemas.
2. Run each SDK's published-contract check and build validation before publishing
   its own new package version. Java SDK 0.3.0 is being prepared; this contract
   release does not publish it or the Python SDK.
3. Upgrade provider dependencies and replace temporary native metadata subclasses
   with the generated types/helpers when available. Pin the provider revision and
   manifest digest, implement the selected profile's obligations, and verify the
   provider against the matching contract before enabling native execution.

Schema validation establishes payload shape. Providers and hosts must separately
verify customer isolation, replay, transaction and logical-time behavior.

## Scope and limitations

This repository supplies contracts and documentation. It does not implement a
partner database, customer tools, a coordinator, a platform API client or a runtime
deployment. There is no new global clock, tick broadcast or polling endpoint.

The initial profiles use agent-scoped state. They do not promise shared-context
scheduling, historical reads, resource rewind or customer-selected write tools.
Reference-state replay guarantees apply within the provider's transactional
boundary; there is no general exactly-once guarantee across external systems.
Publishing these schemas does not certify complete banking/marketing workflows
or capacity for 1,000+ customers.

## Before publication

Choose a new bundle version and align `VERSION` with `manifest.json`. Finalize
these notes, date/version the changelog entry, and remove `Status: Draft` after
verification. Run `scripts/verify-all.sh` and package the bundle from the final
revision. Publish through the existing workflow from an eligible `main` commit,
then verify the immutable ZIP and checksum before updating SDK locks.
