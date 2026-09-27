# Native pure opaque-state transformation profile v1

This unreleased opt-in profile reuses `remote-domain.v1` manifest, prepare, domain-system-work-window and read-only execute-work operations. It does not add a loop, global clock, provider context service or receipt endpoint. Providers advertise `capabilities.nativeSimulation`; exact metadata is in [the profile schema](schemas/native-state-transform.schema.json).

## Ownership and replay

`PURE_STATE_TRANSFORM` means the complete business state is the supplied opaque checkpoint; an operation has no external side effects, hidden mutable business state or wall-clock-dependent output. Identical request bytes against the pinned provider revision produce the same response data. The platform persists the exact request, input checkpoint/context version, response and canonical digests before advancing. An uncertain transport result may replay that identical request, including historical timestamps/deadline; transport timeout is bounded independently. A changed request is a new operation. Stable business work/occurrence identities prevent duplicate application to an already advanced checkpoint. This is not an exactly-once external-effect guarantee.

Domain business rules remain provider-owned. For example, the existing Marketing
Ops provider carries per-persona campaign and review state in an opaque checkpoint
and applies its own review/escalation rules. That state model fits this profile;
native execution still requires the advertised capability, pinned revision,
bounded windows and accepted timing/version metadata described below. It does not
by itself make legacy tools native-compatible or establish a partner-owned database.

Choose the [reference-state profile](../native-reference-state/README.md) when
the partner's backend owns authoritative mutable business data. Such a provider
returns a reference checkpoint and transactional receipts; sending that backend's
complete data snapshot through this pure-state profile would change the ownership
model and would not authorize independent backend mutations.

The manifest response advertises `providerRevision` and returns `X-Astraform-Provider-Revision`. Native operation requests send `X-Astraform-Expected-Provider-Revision`; responses must echo exactly the pinned revision, and a mismatch is HTTP 412. A deployment binding also pins the manifest digest. Changing implementation semantics requires a new immutable revision. Deployment must preserve that revision's code while accepted operations reconcile.

## Existing wire locations

- Prepare: `payload.initialProjectionHints.nativeSimulation` uses `prepareHints`; the platform supplies context identity, logical start/horizon and expected version 0. `payload.personaConfiguration` remains provider-owned business input.
- Window: `payload.context.nativeSimulation` uses `windowContext`; `state.data.nativeSimulation` uses `stateMetadata`. The expected version/context/horizon must match that checkpoint. Existing `payload.timeWindow` gives `(previousTimeEpochMs,currentTimeEpochMs]`; `previous` must equal the checkpoint's processed-through time, `current` must be later and no later than horizon or the earliest authoritative provider boundary. Work kinds must be a supported subset with maxWorkItems no greater than the manifest limit.
- Result: `result.projection.runtimeMetadata.nativeSimulation` uses `resultMetadata`; `nextState.data.nativeSimulation` contains the matching state metadata without duplicating observation. Successful prepare produces version 1; each window increments version once, including an empty window. `processedThroughEpochMs` equals the accepted start/window end. The platform binds its receipt to the input and output versions.
- Actual work results, events and triggers remain in existing `result.domainSystemWork` and `result.evidenceEvents`. Prepare may return these existing optional fields for start-boundary work.

## Customer-selected read-only tools

A native tool uses the existing `capabilities.tools` descriptor with all fields in
the profile's `readOnlyToolDescriptor`: `name`, `description`, `inputSchema`,
`outputSchema`, `revision`, `effectClass: READ_ONLY`, and
`scope: CUSTOMER_CONTEXT`. Input and output are closed inline JSON Schemas.
Legacy descriptors stay valid for their existing consumers; missing native fields
do not grant model-selectable native execution. The host pins the complete descriptor,
both schema digests and provider/binding identities in the published customer grant.

The host persists the exact SDK `execute-work` request before dispatch. Its
`payload` uses `readOnlyToolPayload`: one `TOOL_CALL` work item, `attemptNumber: 1`,
and `payload: {kind: "tool-call", toolName, arguments}`. The time window's two
boundaries and the work item's `scheduledForEpochMs` equal the accepted checkpoint's
`processedThroughEpochMs`. The host validates that checkpoint against its frozen
context/version; no model-authored customer selector or checkpoint is accepted.

A read returns the actual value in `result.toolResult` and read evidence in
`result.evidenceEvents`. `nextState` must equal the supplied checkpoint canonically;
context version, processed-through time and projection remain unchanged. The receipt
binds the exact response, and its previous/result context versions are equal. Reads
consume the frozen tool-call and domain-operation budgets. A repeated transport
attempt uses the same request and does not create a new logical tool call. Mutations
are not authorized by this read-only contract.

For example, the Java banking pure-state sample's `get_customer_accounts` accepts
`{}` and reads the current customer's accounts (including actual limits) and latest
statement from the supplied accepted checkpoint. It cannot select another customer
or access an independent partner-side backend. This checkpoint-backed example is
distinct from the banking reference-state provider's guarded backend reads.

## Time and observation

`PREPARE_INCLUDES_START` means preparation establishes state at the start and applies any events due exactly at that instant, emitting their evidence/triggers. Subsequent elapsed windows exclude their start. Each response supplies exactly one of `nextDueEpochMs` or `noWorkBeforeEpochMs`, strictly after processed-through. The latter is an exclusive promise that no domain work can occur before that bound in the unchanged checkpoint, not an empty-list inference. A provider may set it to horizon+1 after checking no work remains through horizon. The coordinator must not cross an earlier unresolved customer/partner decision and must settle domain state before exposing dependent observations.

Observation contains only customer-visible facts true at processed-through time. It must not reveal future scenario changes, hidden provider state, prompts or proposed customer decisions. Domain triggers are facts, never scripted customer responses. Preparation, work and observations are bounded; unsupported policies or oversized checkpoints fail explicitly.

The initial Java banking pure-state implementation supports only automatic monthly credit-card statement close, at most one initial account, no persona scheduledWork, one work item per window and a 262144-byte checkpoint. It reuses the existing statement calculations and trigger policy. These sample limits do not narrow the generic profile or retire broader domain capabilities; broader legacy operations retain their previous contract.

The currently published Java SDK 0.2.0 does not generate the optional nativeSimulation capability or enriched native tool descriptor yet. The sample uses narrow capabilities and descriptor DTO subclasses through its existing SDK controller. Regenerating SDK models from this canonical OpenAPI removes these temporary extensions; it does not require a parallel endpoint.

The Java banking pure-state sample enables this development capability only with `--astraform.native-simulation.enabled=true` (default `false`). The manifest is stable for that deployment configuration; it never changes by caller or request header. Default-mode published SDK conformance and native-enabled current-contract validation are separate checks. SDK 0.2.0's bundled closed manifest schema does not validate the new capability.
