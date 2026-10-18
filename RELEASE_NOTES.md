Version 1.2.2 extends the shared provider and platform API contracts with
cross-domain run discovery, domain-aware MCP bindings, domain-owned assessments,
captured-result presentation and opt-in authoritative request metadata.
The provider protocol remains `remote-domain.v1`.

These bundles contain API definitions, schemas, documentation and examples.
Using a new contract requires a supporting platform and SDK implementation;
contract publication does not deploy features or update installed SDKs.

## Highlights

### Find simulations across domains

- Adds optional `AgentJourneyLaunchRequest.domainId` to record an explicit run
  classification, including journeys without a native domain provider. When a
  native provider is selected, the classification must match that provider.
  The value is frozen with the launch identity; it does not activate a provider
  or grant tenant, project or tool permissions.
- Extends `GET /api/simulation-runs` with literal name/run-ID search, domain,
  known/unknown classification, execution-status and creation-time filters.
- Adds opaque cursor continuation, `hasMore`, nullable `nextCursor`, a retained
  creation-time boundary, declared sort order and optional exact totals through
  `includeTotal`. Repeat the original filters when following a cursor. Existing
  runs can still change; pagination does not provide an immutable data snapshot.
- Changes omitted `experimentId` to select runs across experiments. Send an
  explicit `experimentId` to retain the former experiment-specific scope.

### Select MCP bindings by domain

- Adds `GET /api/simulation-events/mcp-bindings` and the typed
  `CustomerMcpBindings` / `CustomerMcpBinding` inventory with bounded pagination
  and optional domain filtering. It describes deployment-configured bindings
  without contacting MCP endpoints or publishing their URLs or credentials.
- Adds `allowedDomainIds` to binding/capability metadata and a frozen `domainId`
  on restricted tool grants. Restricted bindings require an eligible run domain
  before discovery and retain that domain for enforcement before transport.
- Preserves unrestricted legacy behavior when the inventory allowlist is empty
  or a legacy capability omits it. Domain classification and eligibility do not
  establish departmental ownership, authentication or tenant isolation.

### Assess results with domain-owned criteria

- Adds `domain_assessment.v1` with domain, evaluator, rubric and configuration
  identities; evidence run/scenario identity and digest; references, timestamps,
  rationale, native structured results and arbitrary metric IDs.
- Defines `evaluation.v2` reports with explicit `PASS`, `WARN`, `FAIL`,
  `NOT_ASSESSED` and `ERROR` assessment states. Summary/scenario scores are
  nullable; missing or errored assessment results do not imply zero or success.
  Execution status remains separate from assessment outcome.
- Retains an open source-suite object on the existing evaluation request while
  publishing typed suite/scenario schemas. Optional native-result containers
  distinguish omission, explicit null and empty values. Normalized scores use a
  declared higher-is-better meaning; arbitrary tool scores are not automatically
  interchangeable or averaged.
- Adds comparison status/reasons, nullable deltas and custom metric comparison
  records. Compatible qualitative assessments can be compared without numeric
  scores. Missing, unassessed and incompatible metrics retain an explanation
  rather than an invented delta. Historical `evaluation.v1` report fields and
  legacy dimension definitions remain available.
- Defines the evidence digest as SHA-256 of RFC 8785 canonical JSON for the
  decoded suite with its root and immediate scenario assessment annotations
  removed. Compute it after final source serialization. This identifies the
  decoded snapshot, not original HTTP/file bytes; represent exact values beyond
  binary64 precision as strings.

The six evaluation routes already exist; this version extends their payloads.
An attributed assessment does not authenticate its submitter, append immutable
native simulation evidence or change customer-goal completion. Managed evaluator
adapters, independent multi-tool history and native export integration require
separate implementation.

### Show domain labels and formats

- Adds `astraform.result-presentation.v1` as an optional `presentation` annotation
  in captured A2A JSON responses or MCP `structuredContent`, with a shared schema,
  provider guide and banking/marketing examples.
- Supports bounded labels and pointers into the same captured result, with
  `text`, `currency` and `date` formats. Original values, JSON types and evidence
  remain intact; invalid annotations fall back to generic presentation.
- Defines text escaping, no network lookup, decoded-pointer uniqueness and an
  8,192-byte annotation bound. MCP output-schema publication requires an inline,
  self-contained schema. Presentation confers no execution, permission, goal or
  business-verdict authority. As part of a recorded reply, annotations may also
  be visible to the customer model; identical subsequent decisions are not
  guaranteed.

### Resolve authoritative request metadata

- Adds optional non-null `completionPolicy.requestFactBindingMode` with values
  `VALIDATE` and `RESOLVE_TRUSTED`, without a wire default. Omission or `VALIDATE`
  preserves existing equality validation without request repair.
- `RESOLVE_TRUSTED` copies configured bound fields from already admitted
  authoritative observations into the outgoing request. It preserves the
  original model proposal, chosen action, instruction and unbound facts. The
  validated resolved request is frozen before dispatch and retry.
- Missing/null sources, reserved or overlapping targets, incompatible containers,
  unsupported paths and size violations block dispatch. Model memory and future
  observations cannot supply authoritative values; partner output is not repaired.

## Upgrade notes

Update consumers for the new assessment states, nullable scores/deltas and
pagination fields. Preserve omitted versus explicit-null values. Use supporting
Java/Python author-kit releases or their updated generators built against these
contracts. Changing an archive pin alone does not update installed clients or
add previously ungenerated operations. SDK package versions remain independent
of contract version 1.2.2.

Use a matching platform implementation and gateway for the selected operations.
Existing strict customer FINISH and finalization-correlation fields from 1.2.1
remain available. Provider routes, protocol/profile identifiers and published
historical release assets remain unchanged.

## Downloads

Both bundles share root version 1.2.2 and ship together with separate checksums:

- `remote-domain.v1.zip` and `remote-domain.v1.zip.sha256`, rooted at
  `remote-domain.v1/`.
- `platform-api.zip` and `platform-api.zip.sha256`, rooted at `platform-api/`.

After publication, pin the shared `v1.2.2` tag and verify each asset's own
checksum before regenerating consumers. Until publication, use only explicitly
selected development ZIPs with `LOCAL_PRERELEASE` provenance. Local rebuilds do
not replace immutable published archives. See [CHANGELOG.md](CHANGELOG.md) for
historical releases and [README.md](README.md#release) for the release procedure.
