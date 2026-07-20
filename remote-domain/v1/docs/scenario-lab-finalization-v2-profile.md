# Scenario Lab Finalization V2 Profile

`PLATFORM_OWNED_V2` is an out-of-band Scenario Lab provider capability. It does
not add fields to the closed `remote-domain.v1` wire objects. A provider opts in
through its Scenario Lab pack metadata and must satisfy this profile before any
new clock-driven run can launch.

## Stable Operation Identity

For a run ID and immutable provider revision, the platform derives:

```text
scenario-lab-finalize:<hex SHA-256 of UTF-8(runId + providerRevision)>
```

The operation ID is stable across attempts, replicas, and process restarts. A
provider must bind it to the canonical `FINALIZE` input. The same operation ID
with the same input is a replay; the same ID with different input is a conflict.

## Durable Receipt

Before publishing a final result, the provider writes a
`scenario_lab_provider_finalization_receipt.v2` receipt.

- `PREPARED` means every final artifact byte is already durably available and
  frozen by relative reference, media type, SHA-256, and byte length.
- `PUBLISHED` means the immutable artifact set and terminal run snapshot are
  the authoritative replay result.
- The receipt binds the immutable provider revision, operation ID, and input
  digest.
- Every replay re-reads and verifies every artifact before returning success.
  Missing or altered artifacts fail closed.

The provider must never regenerate artifact bytes after `PREPARED`.

## Capability Storage Gate

A provider may advertise `PLATFORM_OWNED_V2` only after executing a startup
probe against its configured durable receipt and artifact root. Reading
configuration or trusting the provider's capability assertion is not proof. The
probe must use separate operating-system processes to prove lock exclusion and
visibility: while one process owns the lock, the other must observe the owner
and be unable to acquire it; after release, the other process must acquire it.
The probe must also atomically publish durable bytes, terminate the writer, and
prove from another process that observers see either no artifact or the complete
artifact with the expected digest, never partial bytes. A local ephemeral
directory, process-private store, or per-pod volume does not satisfy this
requirement.

Every replica that can serve or recover a run must observe the same receipt,
lock, and artifact state. Multi-replica deployments therefore require shared
RWX storage or equivalent storage with atomic compare-and-swap semantics across
all replicas. If the proof is unavailable or fails, the provider must not
advertise V2 capability and conformance cannot report `PASSED`.

After publication, the existing Policy Wind Tunnel artifact route exposes the
strict receipt at `runs/{runId}/artifacts/finalization-receipt`. Each
`artifactManifest` key is exposed through the same route after converting its
camel-case key to lower kebab case. Conformance clients re-read those exact
bytes and verify their declared media type, SHA-256, and byte length.

## Terminal Precedence

`FAILED` and `CANCELLED` always win over a recoverable `PREPARED` snapshot. A
retry records a `PUBLISHED` terminal receipt without resurrecting the run and
without sending a completion notification.

For a successful run, the provider persists `PUBLISHED` before notifying the
platform. The notification payload and its `Idempotency-Key` are both bound to
the stable finalization operation and are retried independently until confirmed.
For a completed receipt, `completionNotificationPayload.summaryPath`,
`bundlePath`, `completedAtEpochMs`, and `metadata` must exactly equal the same
fields in `runSnapshot`. The notification run ID, status, operation ID, input
digest, and provider revision must likewise match their receipt owners.

## Conformance Execution

Conformance requires two separate runs. Results from one run cannot satisfy the
other probe.

1. The successful-restart probe crashes after observing `PREPARED`, fetches and
   verifies every artifact against the PREPARED manifest, restarts through an
   independent operating-system provider process, reaches `COMPLETED`, verifies
   the PUBLISHED receipt and artifacts, and proves identical notification
   replay. Before restart, the harness must prove that the original PID or
   process handle terminated and that its endpoint is unreachable. The
   initial provider PID or process handle must also be distinct from the
   conformance harness process itself. The restarted PID or process handle must
   be distinct from both. Constructing a new endpoint, application, controller,
   service, or identity string inside the harness or original provider process
   is not a restart.

Both the initial and restarted processes must prove that they are the provider
target under conformance. The harness must strictly read each process's `/pack`
response and bind its complete canonical digest plus `packId`, `domainId`, and
`providerRevision` to the expected target. Those four identities must match
across the restart. Substituting another provider that happens to satisfy this
profile invalidates the conformance result.
2. The terminal-precedence probe crashes after observing `PREPARED`, changes
   the run to `FAILED` or `CANCELLED`, terminates the original provider process,
   proves that process is unreachable, starts a distinct operating-system
   provider process, and only then recovers finalization. It must prove that the
   terminal state is preserved without a completion notification.

The successful-restart probe must fail when any PREPARED artifact is missing,
altered, or unavailable after restart. Verifying artifacts only after
`PUBLISHED` is insufficient because it permits a provider to regenerate bytes
that were not durable at PREPARED.

The `notification_retry` probe must inject a failed delivery acknowledgement
after the provider attempts the completion notification. Without sending
another `FINALIZE` request, the harness must then observe the provider
independently retry the byte-identical notification with the same operation-keyed
idempotency identity. Replaying `FINALIZE` to cause the second notification does
not satisfy this probe.

Every entry in `conformance-vectors.json` is executable. A harness must validate
the vector document against its schema and execute each published
`case`/`outcome` pair against the provider through an injected durable fault.
Local receipt mutation, schema validation, parser validation, or checking case
labels does not count as provider execution. Inferring outcomes, skipping an
unsupported vector, accepting duplicate cases, or accepting extra cases is a
conformance failure.

The public matrix includes two absence/shape boundaries that must also execute
against the provider. `missing_receipt` proves that recovery fails when no
durable receipt exists. `receipt_missing_state` proves that a persisted receipt
without its required lifecycle `state` is rejected rather than inferred or
defaulted. Neither case may be satisfied by validating a locally fabricated
object without invoking the provider recovery path.

## Compatibility Boundary

- Every new `CLOCK_DRIVEN_HYBRID` launch requires `PLATFORM_OWNED_V2`,
  including both cadence-driven and `EVENT_ONLY` runs.
- `PLATFORM_OWNED_V1` is accepted only for an explicitly pinned legacy recovery.
- A V1 recovery request must not contain V2-only operation or receipt fields.

The schemas and samples under
`profiles/scenario-lab-finalization-v2/` are the executable, language-neutral
conformance source for these rules.
