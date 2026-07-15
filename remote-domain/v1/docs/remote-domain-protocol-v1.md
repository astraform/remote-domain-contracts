# Remote Domain Protocol v1

Status: v1 source of truth for issue `#230`, with live Java banking, Python
banking, and Marketing Ops sample implementations now owned by
`astraform/remote-domain-samples`.

This note defines the first versioned out-of-process domain contract for the
Astraform platform.

Product framing: buyers should first understand Astraform as customer outcome
simulation. This protocol becomes relevant when a team needs to bring its own
business state, actions, and evidence projections into that simulation.
The buyer-facing trust boundary is summarized in
[Customer Outcome Platform Boundary](./customer-outcome-platform-boundary.md).

Brutal truth: if this protocol just serializes half of `agent-runtime` over
HTTP, we do not have a platform. We have a distributed monolith with better
marketing. The whole point of this spec is to keep the host kernel honest while
letting non-Java domains participate as first-class runtime modules.

## Why This Exists

The current Java SPI is now clean enough to expose the real next constraint:
polyglot domain support.

If Python, TypeScript, Go, or any non-JVM domain is real product intent, the
platform needs a protocol boundary that preserves host ownership of runtime
control while letting domains own domain semantics out of process.

This document is that boundary for v1.

## V1 Scope

V1 remote domains are:

- synchronous HTTP/JSON services
- registered separately from this protocol spec
- called only by the runtime host
- responsible for domain semantics and domain projections
- not responsible for canonical runtime persistence

V1 remote domains are **not**:

- independent simulation kernels
- owners of clock or replay control
- owners of MCP or A2A routing policy
- owners of the shared `AgentEngine`
- generic async workflow engines

## Host Ownership Boundaries

The host keeps ownership of the things that make the platform a platform.

| Concern | Owner | Why |
| --- | --- | --- |
| Clock and replay contract | Host | There must be one time authority. |
| Agent lifecycle and registration | Host | Public runtime identity and lifecycle events are kernel concerns. |
| Scheduling and due-work dispatch | Host | Work queues must stay deterministic and replay-aware. |
| Canonical runtime persistence | Host | Remote domains do not become hidden databases. |
| Stable memory keys | Host | Memory scoping is a platform concern. |
| MCP and A2A allow-list policy | Host | Tool and external-agent policy must stay centralized. |
| Telemetry and operator visibility | Host | Observability cannot depend on domain-specific side channels. |
| Shared `AgentEngine` execution shell | Host | The kernel owns the turn loop in v1. |
| Domain validation, domain state evolution, domain projections | Remote domain | This is the whole reason the remote boundary exists. |

## Remote Domain Responsibilities

The remote domain may own:

- persona validation and normalization
- runtime identity suggestion
- opaque domain-state initialization
- opaque domain-state evolution during host-driven work cycles
- domain-specific status projection
- domain-specific inspection projection
- domain-specific schedule shaping expressed through generic host contracts
- creator-only UI metadata through `uiProfile`

The remote domain may **not** assume:

- direct access to host internals
- direct access to `AgentEngine`
- direct database writes as part of canonical correctness
- direct control over retries, deadlines, or scheduling order
- direct MCP or A2A execution in v1
- direct execution of domain-supplied frontend code inside the shared dashboard

## Creator UI Metadata

`remote-domain.v1` allows a remote domain to publish optional `uiProfile`
metadata in its manifest.

That metadata exists so the shared dashboard can render deterministic
domain-specific setup fields and write them into `domainConfig`.

It does **not** mean the remote domain can ship executable UI bundles or remote
frontend code for the dashboard to mount dynamically. In v1:

- the domain may describe creator UI
- the platform dashboard owns renderer implementation
- renderer support is limited to platform-approved kinds

## Manifest Capabilities

The manifest is also the place where a remote domain tells the host which shared
authoring surfaces are valid for that domain. For dashboard-backed simulation,
be explicit:

- `supportsInitialAccounts`: true only when the domain accepts the platform
  `initialAccounts` persona shape during `prepare`
- `supportsScheduledWork`: true only when the domain publishes supported
  `scheduledWorkKinds`
- `supportsDomainSystemWorkWindow`: true only when the domain can evaluate and
  execute institution-side work over a simulated time window
- `domainSystemWorkKinds`: the business/system work kinds owned by the domain,
  such as interest accrual, statement close, fees, SLA expiry, or policy refresh
- `tools`: the persona-mountable tools the remote domain actually implements.
  The host mounts these as local callbacks and routes calls through
  `execute-work` as `TOOL_CALL` work items. Tool effect classification is not a
  `remote-domain.v1` manifest field. Hosts that execute tools asynchronously
  must supply that classification through a separate platform registration and
  conformance profile.

Do not set these as aspirational flags. If the dashboard exposes a field because
the manifest claims support, the remote service must actually accept and execute
that payload.

## Protocol Versioning

The protocol identifier for this phase is:

- `remote-domain.v1`

Breaking changes require a new major protocol identifier such as
`remote-domain.v2`.

Additive optional fields may be introduced within `remote-domain.v1` so long as:

- existing required fields remain unchanged
- existing field semantics do not change
- old clients can safely ignore the new fields

Recommended media type:

- `application/vnd.astraform.remote-domain.v1+json`

The body must still carry `protocolVersion` explicitly. Media types alone are
too easy to lose in proxies, logs, and test harnesses.

## Lifecycle

The published v1 contract exposes five baseline lifecycle operations, one
optional domain-system work operation, and named payload schemas:

- `manifest`: capability declaration and endpoint discovery
- `prepare`: validate persona input and produce initial opaque state
- `execute-work`: apply one host-owned work cycle and return the next domain state
- `domain-system-work-window`: optionally evaluate and execute domain-owned
  business/system work over a bounded simulated time window
- `status`: return the public runtime status projection
- `inspection`: return the detailed inspection projection
- `turn-context`: the execute-work payload shape that carries host-owned time and due-work context

The host calls the remote domain through these lifecycle operations:

| Operation | Purpose | Mutates opaque state |
| --- | --- | --- |
| `prepare` | Validate persona input and produce initial remote-domain state | Yes |
| `execute-work` | Apply one host-owned work cycle and return the next domain state | Yes |
| `domain-system-work-window` | Apply domain-owned institution/system work due within a simulated time window | Yes |
| `status` | Return domain-owned status projection for public runtime surfaces | No |
| `inspection` | Return domain-owned inspection projection for operator/debug surfaces | No |
| `shutdown` | Best-effort runtime teardown notification | No |

`domain-system-work-window` is optional but first-class. If the manifest sets
`supportsDomainSystemWorkWindow=true`, the operation descriptor must be present
and the service must accept the request shape published in the contract samples.
If a domain does not own institution-side time progression, keep the flag false.

### Customer decision triggers

`domain-system-work-window.result.domainSystemWork.decisionTriggers` contains
sanitized domain facts that may create customer decision opportunities. A
trigger is never a prompt, model response, or chain-of-thought container. The
field names `prompt`, `systemPrompt`, `rawProviderText`, and `chainOfThought`
are prohibited recursively through every nested object and array.

The platform owns scheduling priority through the additive
`schedulingPriority` field: `CRITICAL`, `HIGH`, `NORMAL`, or `LOW`.
Aliases and domain-defined values are invalid in this field. An invalid explicit
`schedulingPriority` becomes rejected-trigger reconciliation debt. The required
`priority` string from the originally published v1 trigger remains a deprecated
compatibility hint: legacy `URGENT` normalizes to `CRITICAL`, other known values
retain their meaning, and every unknown value maps to `NORMAL` rather than
creating a domain-owned queue rank. Domain-specific severity belongs in the
fact payload.

For backwards compatibility, these limits do not narrow the published
`remote-domain.v1` JSON language. Platform admission is deliberately bounded:
at most 1,000 triggers per work window; identifiers up to 255 Unicode code
points without U+0000; reason text up to 1,024 code points without U+0000; at
most 64 evidence references of 512 code points each; scheduled times from
`0001-01-01T00:00:00Z` through `9999-12-31T23:59:59.999Z`; and a non-empty
payload no larger than 64 KiB encoded JSON, 12 levels, 4,096 nodes, 256 entries
per object/array, 255-code-point property names, and 4,096-code-point strings.
All admitted text must be a valid Unicode scalar sequence and must not contain
U+0000; unpaired UTF-16 surrogates and PostgreSQL-unsafe null characters are
rejected before normalization, hashing, or persistence. Numeric payload values
must survive RFC 8785/ECMAScript binary64 canonicalization exactly, remain finite and
non-underflowing, and must not become integers outside
`-9007199254740991..9007199254740991`. Domain facts requiring greater decimal
precision use a declared canonical string encoding, such as
`canonical_decimal_string.v1`, rather than a JSON number.
Provider responses must contain exactly one JSON value and unique property
names at every object level. Duplicate properties and trailing JSON values are
rejected before contract or admission validation.
Input that is wire-valid but outside platform admission becomes durable
rejected-trigger reconciliation debt. A malformed entry is rejected
independently so one provider mistake does not roll back valid peers.

The host may skip `shutdown` if the runtime crashes or the process is killed.
Remote domains must not rely on it for correctness.

## Request Envelope

Every operation uses the same top-level request envelope.

```json
{
  "protocolVersion": "remote-domain.v1",
  "requestId": "1e2c2d27-8a25-4f74-b9ea-9c2f7d5bf8d1",
  "operation": "execute-work",
  "idempotencyKey": "agent-42:execute-work:request:22222222-2222-4222-8222-222222222222",
  "sentAtEpochMs": 1776175200000,
  "deadlineEpochMs": 1776175204000,
  "host": {
    "service": "agent-runtime",
    "instanceId": "agent-runtime-7f9c5",
    "platformVersion": "0.1.1"
  },
  "domain": {
    "domainId": "marketing-ops"
  },
  "agent": {
    "agentId": "agent-42",
    "conversationId": "conv-42",
    "runtimeIdentity": "campaign-approver-42",
    "personaName": "Campaign Approver",
    "agentType": "Operator",
    "traits": [
      "risk-aware",
      "approval-gated"
    ],
    "interactionMode": "HYBRID"
  },
  "replay": {
    "seed": 20260414,
    "simulationStartEpochMs": 1776171600000,
    "playback": {
      "rate": 60,
      "paused": false
    },
    "deterministic": {
      "enabled": true,
      "resetStateOnClockRewind": true,
      "strictClock": true
    },
    "contractVersion": 7,
    "updatedAtEpochMs": 1776175199000
  },
  "state": {
    "schemaVersion": "marketing-ops.state.v1",
    "data": {
      "pendingApprovals": [
        {
          "approvalId": "apr-100"
        }
      ]
    }
  },
  "payload": {
    "turnContext": {
      "timeWindow": {
        "previousTimeEpochMs": 1776175140000,
        "currentTimeEpochMs": 1776175200000
      },
      "dueWork": [
        {
          "workId": "work-100",
          "workType": "SCHEDULED_ACTION",
          "occurrenceKey": "campaign-review|2026-04-14T14:00:00Z",
          "scheduledForEpochMs": 1776175200000,
          "attemptNumber": 1,
          "description": "Campaign review reminder",
          "payload": {
            "actionType": "REVIEW_CAMPAIGN",
            "campaignId": "cmp-901"
          }
        }
      ]
    }
  }
}
```

## Success Envelope

Every successful response uses the same top-level shape.

```json
{
  "protocolVersion": "remote-domain.v1",
  "requestId": "1e2c2d27-8a25-4f74-b9ea-9c2f7d5bf8d1",
  "operation": "execute-work",
  "result": {
    "runtimeIdentity": "campaign-approver-42",
    "projection": {
      "runtimeMetadata": {
        "queueDepth": 3,
        "approvalState": "REVIEWING"
      },
      "lifecycleSchedule": [
        {
          "description": "Campaign review reminder",
          "type": "SCHEDULED_ACTION",
          "frequency": "DAILY",
          "amount": null
        }
      ],
      "inspectionSchedule": [
        {
          "description": "Campaign review reminder",
          "type": "SCHEDULED_ACTION",
          "nextExecution": "2026-04-15T14:00:00Z",
          "amount": null
        }
      ],
      "statusView": {
        "pendingApprovals": 1,
        "lastDecision": "ESCALATED"
      },
      "inspectionView": {
        "pendingApprovals": [
          {
            "approvalId": "apr-100",
            "campaignId": "cmp-901",
            "state": "ESCALATED"
          }
        ]
      }
    },
    "evidenceEvents": [
      {
        "eventId": "evt-domain-apr-100-escalated",
        "category": "domain",
        "eventType": "approval-escalated",
        "severity": "WARN",
        "outcome": "ESCALATED",
        "payload": {
          "approvalId": "apr-100",
          "reason": "capacity threshold exceeded"
        }
      }
    ]
  },
  "nextState": {
    "schemaVersion": "marketing-ops.state.v1",
    "data": {
      "pendingApprovals": [
        {
          "approvalId": "apr-100",
          "state": "ESCALATED"
        }
      ]
    }
  },
  "warnings": []
}
```

`result.evidenceEvents[]` is optional and additive within `remote-domain.v1`.
The host captures request/response metadata and state checkpoints even when the
domain emits no evidence events. Use `evidenceEvents[]` for provider-owned
activity that the platform cannot observe directly, such as internal policy
checks, private third-party calls, or writes to a domain-owned system.

## Error Envelope

All non-success responses must return JSON with the same top-level structure.

```json
{
  "protocolVersion": "remote-domain.v1",
  "requestId": "1e2c2d27-8a25-4f74-b9ea-9c2f7d5bf8d1",
  "operation": "prepare",
  "error": {
    "code": "UNSUPPORTED_PERSONA_CONFIGURATION",
    "category": "domain_rejected",
    "message": "marketing-ops personas require a campaign approval queue seed",
    "retryable": false,
    "details": {
      "field": "payload.persona.configuration.approvalQueue"
    }
  }
}
```

## Operation Semantics

### `prepare`

Purpose:

- validate the incoming persona for the remote domain
- normalize remote-domain-specific configuration
- produce initial opaque state
- suggest runtime identity and initial projection fragments

Rules:

- the host sends persona context plus any domain-specific configuration payload
- the remote domain returns the first `nextState`
- the host persists that opaque state atomically with the runtime record if and only if the request succeeds
- the host remains the owner of final registration, stable memory key derivation, and public lifecycle emission

### `execute-work`

Purpose:

- apply one host-owned work cycle to the current opaque domain state
- consume host-scheduled due work
- produce the next opaque state and latest projection fragments

Rules:

- the host owns scheduling order and due-work selection
- the remote domain must treat `payload.turnContext.dueWork` as the authoritative work set for that call
- the remote domain must not assume it can reorder or reschedule host work by side effect
- the remote domain may propose updated generic schedule projections in the response, but the host remains the scheduler of record

### `status`

Purpose:

- return the domain-owned fragment for public runtime status surfaces

Rules:

- this is read-only
- the host decorates the domain fragment with host-owned fields such as `agentId`, `domainId`, replay metadata, and runtime timestamps
- the response should be cheap enough for operator-facing read surfaces

### `inspection`

Purpose:

- return the domain-owned fragment for detailed inspection/debug surfaces

Rules:

- this is read-only
- the host may call this more sparingly than `status`
- the response may be richer than `statusView`, but it must still be bounded and serializable

### `shutdown`

Purpose:

- notify the remote domain that the host is intentionally ending the active runtime session

Rules:

- this is advisory only
- failure to receive `shutdown` must not corrupt correctness
- remote domains must not depend on shutdown to flush canonical state, because canonical state is host-owned

## Opaque Domain State

Opaque domain state is the heart of this protocol.

The host stores it.
The remote domain defines it.
Nobody else gets to reinterpret it.

Rules:

- `state.data` and `nextState.data` are JSON objects owned entirely by the remote domain
- the host persists the blob without semantic merging
- the host may log size, schema version, and checksum, but not parse domain semantics out of it
- the remote domain should include its own schema/version discipline inside `schemaVersion`
- remote domains should keep the blob bounded; v1 target budget is `<= 256 KiB` per agent unless explicitly justified

If a domain needs more than that routinely, it is probably trying to turn the
protocol into a hidden persistence backplane. That is the wrong architecture.

## Idempotency

The protocol is idempotent by contract, not by hope.

Rules:

- every mutating request (`prepare`, `execute-work`) must carry `idempotencyKey`
- retries of the same logical operation must reuse the same `idempotencyKey`
- a retried request with the same `idempotencyKey` must use the same request body
- the remote domain must treat repeated delivery of the same mutating request as safe
- the remote domain must not require its own durable idempotency store for correctness

Opportunity-worker execution adds stronger transport/effect guarantees through
an explicit out-of-band profile. Those guarantees do not change baseline v1
conformance. See
[Opportunity Worker Conformance Profile](./opportunity-worker-conformance-profile.md).

For `execute-work`, a mutating due-work item carries a stable `workId`. The host
keeps that `workId` stable across retries of the same business command, even
when a later worker attempt uses a new request body and transport
`idempotencyKey`. The remote domain must consult the supplied canonical state
and return an idempotent replay result when that `workId` has already been
applied. That replay must not append another business mutation or emit a second
effect-applied evidence event.

A conforming replay reports:

- `result.toolResult.idempotentReplay: true`
- one `result.evidenceEvents[]` item with
  `eventType: remote_domain_tool_effect_replayed`, `outcome: NOOP`, and the
  stable `workId`
- `nextState` canonically equal to the replay request's supplied `state`

A non-opportunity command uses a unique core-owned turn/command identity so two
legitimate commands at the same simulated instant cannot collide.

That last rule matters.

Because canonical state is host-owned and supplied on every mutating request,
the remote service should behave like a deterministic state-transition
function over:

- request envelope
- current opaque state
- due work
- replay/time context

The host commits `nextState` only after a successful response. If that commit is
followed by a worker crash, the next attempt receives the committed canonical
state and can suppress the stable `workId` without turning the remote domain
into another database coordinator.

Each business transition must be atomic inside the response. Validate and stage
all legs before changing `nextState`; a rejected multi-leg command must not
return partial mutation, and replaying that rejected `workId` must not compound
an earlier partial effect.

If a remote implementation chooses to cache responses by idempotency key for
efficiency, fine. But correctness must not depend on that cache.

## Timeout And Deadline Semantics

The host is the authority on request deadlines.

Rules:

- every request carries `deadlineEpochMs`
- the remote domain must stop work once the deadline is no longer satisfiable
- the remote domain must not continue background mutation after the deadline
- the host treats local transport timeout as an unknown outcome and may retry
  that same immutable request with the same body and `idempotencyKey`; a new
  worker attempt builds a new request and transport key

Recommended initial host budgets:

- `prepare`: `10s`
- `execute-work`: `5s`
- `status`: `2s`
- `inspection`: `3s`
- `shutdown`: `2s`

Those are starting points, not sacred numbers. But they force the right design
pressure: remote domains must be synchronous and bounded.

## Error Contract

Error categories:

| Category | Meaning | Typical HTTP status | Retryable |
| --- | --- | --- | --- |
| `invalid_request` | Envelope malformed, required fields missing, bad JSON | `400` | No |
| `unsupported_protocol_version` | Host and remote do not agree on protocol | `400` or `426` | No |
| `domain_rejected` | Persona/config/state rejected by domain semantics | `422` | No |
| `deadline_exceeded` | Remote saw the deadline and could not complete in time | `408` or `504` | Usually yes |
| `transient_failure` | Temporary downstream or capacity problem | `429` or `503` | Yes |
| `internal_error` | Unexpected remote failure | `500` | Usually yes |

Rules:

- every error must include machine-readable `code`
- every error must explicitly declare `retryable`
- the host must decide retry policy from both HTTP status and the error body
- domain validation failures must not masquerade as transport failures

## Scheduling Contract

V1 separates customer/persona scheduling from domain-system progression.

Customer/persona scheduled work remains host-owned in the current v1 endpoint
shape.

That means:

- the host stores the customer/persona due-work queue
- the host decides when customer/persona work is due
- the host passes the due customer/persona work set into `execute-work`
- the remote domain may shape customer schedule projections, but not rely on
  private host schedulers

The protocol therefore carries only generic due-work envelopes, not Java
executors or host callbacks.

Domain-system work is different. It covers institution-side rules such as
interest accrual, statement close, fees, SLA expiry, and policy refresh. The
host must not encode those rule schedules as core logic. Domains declare support
with `supportsDomainSystemWorkWindow` and `domainSystemWorkKinds`.

The E27 target shape is:

```text
simulated time window
  -> remote domain evaluates due business/system work
  -> remote domain executes a bounded batch
  -> remote domain returns state deltas, evidence events, checkpoint refs,
     warnings/errors, and next-due hints
```

Kafka clock topics remain internal to the platform. A remote domain should never
need to subscribe to raw platform topics to implement business rules.

## Read Surface Contract

The host owns public APIs.
The remote domain owns domain fragments inserted into them.

V1 read surfaces therefore follow this rule:

- host fields stay host-shaped and cross-domain
- domain fragments stay domain-shaped and opaque to the kernel

Examples of host-owned public fields:

- `agentId`
- `domainId`
- `runtimeIdentity`
- replay/timestamp metadata
- host lifecycle timestamps

Examples of remote-domain fragments:

- `statusView`
- `inspectionView`
- domain-specific `runtimeMetadata`

This prevents the host from becoming banking-shaped again while still letting
domains expose useful read models.

## Mapping To The Current Java SPI

This protocol is conceptually aligned with the current internal Java SPI, but it is **not** a
method-for-method RPC mirror.

| Current concept | Remote protocol expression |
| --- | --- |
| `domainId()` | registration/manifest concern, not per-call behavior |
| `provisionRuntimeIdentity()` / `preparedRuntimeIdentity()` | `prepare.result.runtimeIdentity` |
| `initializeRuntimeState()` | `prepare.nextState` |
| `lifecycleSchedule()` | `result.projection.lifecycleSchedule` |
| `inspectionSchedule()` | `result.projection.inspectionSchedule` |
| `runtimeMetadata()` | `result.projection.runtimeMetadata` |
| `executionPlan()` | host-side runtime binding choice, not remote-owned engine control |
| `turnHandler()` | remains host-owned in v1; remote domains do not get direct engine hooks through this protocol |

That distinction is deliberate. A remote protocol should preserve stable
meaning, not fossilize the current Java package structure.

## Non-Goals For V1

These are explicitly out of scope:

- remote ownership of canonical runtime persistence
- remote ownership of the replay clock or scheduling loop
- remote-driven MCP or A2A execution
- async callbacks, webhooks, or long-running server jobs
- UI manifest contracts
- mixed-domain cross-service transaction semantics
- host-internal class parity over the wire

## Decision

For v1, the platform will treat a remote domain as a synchronous,
state-transition and projection service behind a versioned HTTP/JSON protocol.

That is the right constraint.

It is narrow enough to implement without fantasy architecture, and strong
enough to keep the kernel boundary honest while the platform moves beyond the
Java-only world.
