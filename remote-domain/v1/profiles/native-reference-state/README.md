# Native transactional reference-state profile v1

This opt-in profile, introduced in contract bundle 1.1.0, reuses the
`remote-domain.v1` manifest, prepare and domain-system-work-window operations. It adds no clock, polling loop or receipt
endpoint. The manifest advertises `profile: remote-domain.native-reference-state.v1`,
`mutationMode: TRANSACTIONAL_REFERENCE_STATE`, `stateScope: AGENT` and
`initialBoundaryMode: ATTACH_PREPOPULATED_STATE`. The existing pure-state profile
keeps its original behavior. Exact shapes are in
[the profile schema](schemas/native-reference-state.schema.json).

## State ownership and attachment

The partner prepopulates its authoritative database before launch, including all
work due through the inclusive initial logical instant. Preparation attaches the
native context to that existing customer state; it does not recreate resources or
apply the start-boundary work a second time. A start that disagrees with the
stored processed-through time is rejected. The provider binds the native
`contextId` immutably to the host-selected `{contextRef, subjectRef}` and prevents
another native context from advancing that resource concurrently. This initial
profile does not promise historical reads or shared-context scheduling.

The existing `payload.initialProjectionHints.nativeSimulation` uses `prepareHints`:
`profile`, `contextId`, `expectedStateVersion: 0`, `logicalTimeEpochMs`,
`logicalHorizonEpochMs`, and `customerContext: {contextRef, subjectRef}`. These
references come from frozen host configuration, outside model arguments.
Preparation returns native `stateVersion: 1` and the existing positive provider
`resourceVersion`; those versions are separate and need not be equal.

Every next checkpoint is exactly `{schemaVersion, data: {nativeSimulation}}`.
Its `nativeSimulation` uses `stateMetadata`: profile, contextId, stateVersion,
processedThroughEpochMs, logicalHorizonEpochMs, customerContext, resourceVersion,
and exactly one of nextDueEpochMs/noWorkBeforeEpochMs. It contains no business-state
snapshot. The projection's `runtimeMetadata.nativeSimulation` contains exactly
the same metadata plus customer-visible `observation`. `checkpointDigest` hashes
this reference checkpoint; it is not a hash of all backend business data.

Window `payload.context.nativeSimulation` uses `windowContext`: profile,
contextId, expectedStateVersion, logicalHorizonEpochMs, customerContext and
resourceVersion. It must agree with the supplied reference checkpoint and the
provider's persisted attachment. The existing `(previousTimeEpochMs,
currentTimeEpochMs]` window starts at accepted processed-through time and ends no
later than the next due/no-work-before boundary or horizon. A successful window
increments native stateVersion once, even when empty. Provider resourceVersion is
positive and cannot regress; the provider advances it with its authoritative
resource state. Work, evidence and triggers use existing result fields.

## Banking schedule observation

The existing Java banking reference provider's `observation` includes `domainId`,
`observedAtEpochMs`, and a `notifications` array. When the accepted metadata has
`nextDueEpochMs` for its supported monthly statement work, the observation also
contains `nextStatementAtEpochMs` with that same integer value. It is omitted
when there is no statement boundary through the accepted horizon. This is a
customer-visible banking schedule fact, not an account snapshot, a promise of
payment, or an instruction to wait/contact/finish. The model chooses its action.

## Transactional effects and recovery

This explicitly selected profile is an exception to baseline v1's host-canonical
business-state/no-required-provider-idempotency-store rules. The provider owns
durable business state and a durable operation receipt store. In one transaction
it locks the native context and customer resource, validates identity, versions,
logical time and bounds, executes the work once, advances the state, and stores
the exact successful response together with the canonical request digest and
idempotency key. A rollback must leave neither partial effects nor a receipt.

Before rejecting stale versions or an expired deadline, the provider checks the
operation identity. The same key and canonical request returns the stored exact
response without another mutation, including after restart or after the original
deadline. The same key with a different request is rejected. New work after its
deadline must not mutate state. A transport timeout is an unknown outcome: the
host preserves and resends the exact frozen request with bounded transport time,
including its original timestamps/deadline. It never invents a new key to repair
an uncertain operation. There is no general exactly-once external-system promise
beyond the provider's transactional database boundary.

Pinned provider revision/header and manifest digest checks remain identical to
the pure-state profile. Accepted revisions and receipts must remain available
for reconciliation. There is no automatic resource rewind, context takeover or
receipt eviction policy in this initial slice.

## Causally guarded reads

After an accepted reference receipt the host carries
`readContext: {contextId, resourceVersion, logicalTimeEpochMs}` with its frozen
customer references. The logical time equals the customer event's logical time;
the version is the accepted provider resource version. The MCP `_meta` entry
`astraform.customerContext` is therefore
`{contextRef, subjectRef, readContext?}`. Model-selected tool arguments remain
unchanged. Legacy unguarded reads remain available for the fixed-state profile.

The provider validates guarded reads against the persisted native attachment,
resource version and processed-through time. A mismatch is an explicit read error,
not a latest-state result relabeled with the requested time. Partner agents use
the same guard through their own connection to the domain backend. Host-injected
`facts.astraformCustomerContexts` entries add optional readContext alongside
bindingKey/contextRef/subjectRef; these references are not model-authored facts.
This profile authorizes scheduled domain work, not customer-selected write tools.
The current platform launch selects MCP grants for this profile and rejects
legacy `DOMAIN` tool grants; those remain supported with the pure-state profile.
