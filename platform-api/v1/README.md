# Astraform Platform API Contract

Canonical partner-facing APIs for configuring customer agents, discovering domain
and MCP capabilities, launching simulations, and retrieving their results and
evidence. The same document includes experiment registry and Scenario Lab APIs;
individual deployments determine which routes their gateway exposes.

- Entry point: `openapi/platform/experiment/experiments.yaml`.
- Shared request/response schemas: `openapi/core/common.yaml`.
- Evaluation APIs: `openapi/platform/experiment/evaluation.yaml`.
- Tool and MCP server management APIs: `openapi/core/mcp-management.yaml`.

The initial partner SDK generates from the Experiment entry point only; including
other public API documents does not expand the SDK's supported operation surface.
- Local source contract version: `1.2.1`, an unreleased development candidate.
  The published baseline remains `1.2.0`, tag `v1.2.0`. Both source bundles share
  the repository-root `VERSION` and ship together after reviewed publication.
- Release asset: `platform-api.zip`, containing top-level `platform-api/`.

This bundle contains API definitions, not platform implementation or deployment
credentials. Internal runtime endpoints and their authentication scheme are not
included. The runtime and public API use the same shared payload definitions;
OpenAPI generators consume the entry point and its relative schema references.

The platform repository and both language SDKs consume the same checksum-pinned
release. Edit these canonical files here and publish a new immutable contract
version before updating consumers. The published `v1.2.0` asset is the normal
build input; explicit local ZIP builds are for development only.

## Local typed finalization parity — 14 October 2026

The current source adds optional `runId`, `operationId`, `inputDigest` and
`providerRevision` string fields to `SimulationRunUpdateRequest`. Existing
Scenario Lab providers already send these values in lifecycle completion
requests; this makes the typed contract preserve their recorded correlation
without a sample JSON injection or manual HTTP fallback. They remain optional
for ordinary status/metadata updates. The endpoint path selects the run; these
fields do not create a new execution or publication authority.

This change is local and unreleased under #131/#470. Published contract 1.2.0
and Java0.4.2/Python0.3.2 models do not contain these fields. Local generated
SDK verification uses an explicit `LOCAL_PRERELEASE` archive and distinct local
candidate identities. Root/bundle source metadata now targets shared 1.2.1;
published 1.2.0 consumer locks, checksums and artifacts stay unchanged. A sample must reject a typed update that drops configured fields
before writing, keep its pending same-operation notification, and use a
supporting client rather than patching serialized JSON. This is separate from
strict `completionPolicy.requireCustomerFinish` parity.

## Local strict customer completion — 14 October 2026

`AgentJourneyGoalCompletionPolicy.requireCustomerFinish` is an optional non-null
Boolean with no wire default. Omission or false preserves receipt-qualified
stopping; true requires accepted customer FINISH plus matching receipt evidence.
Explicit null, strings and numbers are invalid and must not be omitted or coerced
by SDK binding. Existing safety limits and retained-participation semantics remain.
The 1.2.1 candidate must be selected explicitly through local ZIP generation;
published 1.2.0 and its current SDK clients do not establish this capability.
