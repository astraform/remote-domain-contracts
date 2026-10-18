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
- Local source contract version: `1.2.2`, an unreleased development candidate.
  The latest published release is `1.2.1`, tag `v1.2.1`. Both source bundles share
  the repository-root `VERSION` and ship together after reviewed publication.
- Release asset: `platform-api.zip`, containing top-level `platform-api/`.

This bundle contains API definitions, not platform implementation or deployment
credentials. Internal runtime endpoints and their authentication scheme are not
included. The runtime and public API use the same shared payload definitions;
OpenAPI generators consume the entry point and its relative schema references.

The platform repository and both language SDKs consume the same checksum-pinned
release. Edit these canonical files here and publish a new immutable contract
version before updating consumers. The published `v1.2.1` asset is the normal
build input; explicit local ZIP builds are for development only.

## Typed completion updates

Published contract 1.2.1 includes optional `runId`, `operationId`, `inputDigest`
and `providerRevision` string fields on `SimulationRunUpdateRequest`. They
preserve lifecycle completion correlation through native SDK clients and remain
optional for ordinary status/metadata updates. The endpoint path selects the run;
these fields do not create a new execution or publication authority.

Use a client generated from contract 1.2.1 or newer. It must preserve configured
correlation fields before sending an update; do not inject serialized JSON or
bypass the SDK. Keep pending same-operation notifications when recovering an
uncertain completion request.

## Strict customer completion

`AgentJourneyGoalCompletionPolicy.requireCustomerFinish` is an optional non-null
Boolean with no wire default. Omission or false preserves receipt-qualified
stopping; true requires accepted customer FINISH plus matching receipt evidence.
Explicit null, strings and numbers are invalid and must not be omitted or coerced
by SDK binding. Existing safety limits and retained-participation semantics remain.
This field is included in published contract 1.2.1. Use a client generated from
contract 1.2.1 or newer that preserves omitted, false and true values.

## Authoritative request metadata (1.2.2 candidate)

The 1.2.2 candidate adds optional `completionPolicy.requestFactBindingMode` with
`VALIDATE` and `RESOLVE_TRUSTED`. Omission preserves existing equality validation;
there is no wire default, and null or an unknown value is invalid. Existing
accepted runs keep their frozen behavior. This field must survive native SDK
serialization before a launcher performs any writes; published Java 0.4.3 and
Python 0.3.3 cannot select the new mode. Generate a local SDK from both explicit
1.2.2 ZIPs for development; published release locks remain unchanged.

With `RESOLVE_TRUSTED`, configured bound fields are platform-owned request
metadata, separate from the model's decision, instruction and unbound facts.
The platform resolves every binding from admitted authoritative observations,
ignores model duplicates at those exact targets, records the untouched original
proposal, and freezes the validated resolved command before transport/retry.
Missing/null sources, reserved or overlapping target paths, incompatible
containers and request limits fail closed. No partner reply is repaired, and
this mode does not select a business action or prescribe a customer question.
Resolution can change what a partner receives and consequently its response;
it does not guarantee identical model decisions.
