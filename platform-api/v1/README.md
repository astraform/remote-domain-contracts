# Astraform Platform API Contract

Canonical partner-facing APIs for configuring customer agents, discovering domain
and MCP capabilities, launching simulations, and retrieving their results and
evidence. The same document includes experiment registry and Scenario Lab APIs;
individual deployments determine which routes their gateway exposes.

- Entry point: `openapi/platform/experiment/experiments.yaml`.
- Shared request/response schemas: `openapi/core/common.yaml`.
- Evaluation APIs: `openapi/platform/experiment/evaluation.yaml`.
- Tool and MCP server management APIs: `openapi/core/mcp-management.yaml`.
- Governed connection registry APIs:
  `openapi/platform/experiment/domain-connections.yaml`, referenced by the
  Experiment entry point in prepared 1.2.3.

The initial partner SDK generates from the Experiment entry point only; including
other public API documents does not expand the SDK's supported operation surface.
- Local source contract version: `1.2.3`, prepared and unreleased.
  The latest published release is `1.2.2`, tag `v1.2.2`. Both source bundles share
  the repository-root `VERSION` and ship together after reviewed publication.
- Release asset: `platform-api.zip`, containing top-level `platform-api/`.

This bundle contains API definitions, not platform implementation or deployment
credentials. Partner applications and authorized operators call these
Astraform-hosted APIs. Astraform Runtime calls partner-hosted provider endpoints
through the separate `remote-domain.v1` protocol. Internal runtime endpoints and
their authentication scheme are not included. The runtime and public API use the
same shared payload definitions;
OpenAPI generators consume the entry point and its relative schema references.

The platform repository and both language SDKs consume the same checksum-pinned
release. Edit these canonical files here and publish a new immutable contract
version before updating consumers. The published `v1.2.2` asset is the normal
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

<a id="authoritative-request-metadata-122-candidate"></a>

## Authoritative request metadata

Published contract 1.2.2 adds optional `completionPolicy.requestFactBindingMode` with
`VALIDATE` and `RESOLVE_TRUSTED`. Omission preserves existing equality validation;
there is no wire default, and null or an unknown value is invalid. Existing
accepted runs keep their frozen behavior. This field must survive native SDK
serialization before a launcher performs any writes. Use a supporting platform
and a native SDK generated from contract 1.2.2 or newer; changing an archive pin
alone does not update an installed client. Do not bypass the SDK with raw
platform HTTP or serialized JSON injection.

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

## Governed connection registry (1.2.3 prepared)

The prepared contract adds the
[Domain Connection Registry API](openapi/platform/experiment/domain-connections.yaml)
for owner-scoped immutable `A2A`, `NATIVE_DOMAIN` and `CUSTOMER_MCP` revisions.
It requires a matching platform implementation and Java/Python SDKs containing
`DomainConnectionsApi` and registered-selection launch models. Published contract
1.2.2, Java SDK 0.4.4 and Python SDK 0.3.4 do not contain these operations.
For development, generate compatible SDKs from both explicitly selected local
1.2.3 ZIPs with `LOCAL_PRERELEASE` provenance. Use their native clients and request
models in applications and samples; do not substitute raw platform HTTP.

### Configure authority before registration

This is trusted deployment-operator access. Operator bearer tokens map to
server-configured owner scopes, independent operation permissions, permitted
origins and credential references. Clients cannot choose an owner in a request
or header. Dashboard roles do not supply this authority; department self-service
identity and enterprise RBAC are not provided by this contract.

Enable the registry in both Experiment Service (`domain.connections.enabled`)
and Runtime (`simulation.event.runtime.connections.enabled`). Configure operator
tokens and grants in Experiment Service, and approved destination origins,
credential references and the reachable Experiment resolver in Runtime. Keep
the management origin private and use HTTPS for operator traffic. Operator,
partner-provider and internal Experiment-to-Runtime tokens are separate secrets;
only an authorized `credentialRef`, currently supported for A2A, crosses the
public API boundary. A2A execution also needs the existing Runtime A2A transport
enabled.

Hot registration is bounded by preapproved deployment policy. Both the operator
and Runtime must permit the destination's exact scheme, host and effective port.
Adding an unapproved origin, secret reference, model or embedding binding still
requires deployment configuration. Endpoints cannot contain URL credentials,
queries or fragments; native-domain endpoints contain only an origin. Execution
grants must explicitly permit the connection keys and Catalog agent IDs used by
the launcher. Registration and discovery grant no customer tools or backend access.

### Register and activate an exact revision

Use the generated `DomainConnectionsApi` operations with the appropriate operator
bearer credential. Supply a caller-owned UUID `requestId` and nonnegative
`expectedVersion` for every mutation: zero for a new connection, otherwise the
latest returned `stateVersion`. Save the response before the next operation.

| Operation | Required permission | Effect |
| --- | --- | --- |
| List/read | `READ` | Inspect owner-scoped connections and retained revisions. |
| Register | `REGISTER` | Store immutable deployment-permitted material without contacting the provider. |
| Probe | `PROBE` | Discover an A2A Agent Card, native manifest or MCP tools; no business execution or model inference. |
| Approve | `APPROVE` | Approve the current successful probe using its exact `expectedProbeDigest`. |
| Activate | `ACTIVATE` | Select the approved revision for future `REGISTERED` launches. |
| Capabilities | `EXECUTE` | Inspect the active approved revision permitted to the launcher. |
| Retire | `RETIRE` | Prevent new selection while retaining the revision for accepted runs. |
| Revoke | `REVOKE` | Prevent new selection and subsequent governed dispatch using the revision. |

Changed material requires a new `bindingRevision`; a connection's kind is
immutable. A changed probe invalidates approval. Retirement and revocation clear
approval and any active pointer; those revisions cannot be probed, approved or
reactivated. Historical records remain available, with no hard-delete operation.
If a mutation response is uncertain, retry with the same request ID and identical
body, including `expectedVersion`; completed requests replay the saved result.
For a genuine version conflict, read the latest state before deciding on a new
operation. Follow returned keyset cursors when listing further pages.

### Launch and recover with frozen revisions

Set `AgentJourneyLaunchRequest.connectionSelection` to `REGISTERED` and supply a
configured launcher bearer with `EXECUTE` permission. Use the existing selectors:
`partnerTargetAgentKey` for A2A, `domain.bindingKey` for native-domain work and
`toolContexts[].bindingKey` for customer MCP. The server derives ownership and
exact revision pins; do not submit endpoints, credentials, owner fields or pins.
Explicit null and unknown selection modes are invalid; omission retains existing
startup-configured binding selection.

Admission selects approved active revisions and checks matching published Catalog
tool/schema grants. A concurrent lifecycle or activation change causes a conflict
rather than silently changing selection. Accepted runs freeze the exact revisions,
including across restart; activating another revision affects new launches.
Retry an uncertain launch with the same request ID and identical body under the
same configured launcher identity. Replay retains the saved selection and still
requires current authentication and Catalog execution authority. A 202 response
confirms durable acceptance, not successful provider preparation or goal completion.

Retired revisions remain usable by accepted runs under current execution policy.
Revocation blocks subsequent governed provider requests, but cannot cancel an
already authorized in-flight request or establish its remote outcome. Preserve
durable intents and receipts for reconciliation; consuming a committed A2A receipt
during recovery does not resend the operation. Runtime rechecks current authority
before outbound requests and fails closed when exact-revision resolution is
unavailable; it does not fall back to a startup binding with the same key.

Registry controls apply to `REGISTERED` runs. Startup-selected runs retain their
original path; stopping all access to a destination also requires deployment
network and credential controls. Contract publication alone neither enables this
registry in a deployment nor updates installed SDKs.
