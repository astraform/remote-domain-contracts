# Opportunity Worker Conformance Profile

Status: optional host profile layered on top of `remote-domain.v1`.

This profile is not part of the `remote-domain.v1` wire schema. In particular,
tool effect classification must not be added to a v1 manifest tool descriptor:
published v1 validators close that object with `additionalProperties: false`.

The platform registration supplies an exact classification for every tool the
async opportunity worker may execute:

- `READ_ONLY`: execute on every delivery, return a complete fresh result, leave
  canonical state unchanged, and emit no mutation-replay marker or evidence
- `MUTATING`: identify the business effect with a stable core-owned `workId` and
  suppress reapplication of that effect across worker attempts

Profile classification values are exact and case-sensitive. Only `READ_ONLY`
and `MUTATING` are valid. A missing classification keeps the tool valid for
baseline v1 execution but makes the domain ineligible for the opportunity
worker.

The worker separates two identities:

- transport request identity: every changed request body receives a new
  `idempotencyKey`
- business effect identity: retries of one command retain the same `workId`

That changed-request behavior is a worker-profile rule, not baseline v1 retry
semantics. SDK conformance therefore runs it only when the caller explicitly
selects this profile and supplies safe probes for every classified tool.

For each probe, conformance executes the tool twice across distinct worker
attempts and verifies:

- `READ_ONLY` returns complete fresh results twice, keeps canonical state equal
  to each request state, and emits no `remote_domain_tool_effect_replayed`
  evidence
- `MUTATING` applies once, then returns a standard replay `NOOP` result and
  leaves canonical state equal to the second request state

Providers must not infer this profile from a v1 manifest. Eligibility belongs
to platform configuration and an explicit conformance report.

Opportunity-worker `toolEffects` keys and `toolProbes[].toolName` values use the
ASCII grammar `[A-Za-z][A-Za-z0-9_.:-]{0,127}`. Baseline v1 tool names remain
unchanged, but a tool outside this grammar is not eligible for the worker
profile. This restriction keeps the classification projection identical under
RFC 8785, Java, Python, and the isolated release signer; Unicode property-name
ordering must never be approximated by a language-native map sort.

## Signed Attestation Binding

A successful profile run emits
`remote_domain_opportunity_worker_conformance_report.v1`, then signs a DSSE
envelope containing an in-toto Statement v1. Its predicate binds:

- `domainId` and `protocolVersion`
- `profileDigest`: SHA-256 of the canonical classification projection containing
  only `schemaVersion` and the exact `toolEffects` map
- `manifestDigest`: SHA-256 of the exact manifest JSON returned by the provider
- `conformanceReportDigest` and the exact conformance harness name/version
- the in-toto subject digest of the exact OCI provider image tested

Protected OCI publication pipelines additionally bind
`conformanceHarnessImageDigest` and `buildProvenanceIndexDigest` in the signed
predicate. The former must come from an independently allowlisted,
digest-addressed conformance image; the latter identifies the BuildKit
provenance index containing the exact platform subject. Local SDK signing can
omit these deployment-specific fields, but the Astraform sample-image release
environment requires both.

The canonical report bound by `conformanceReportDigest` is not metadata-only.
It records a top-level `PASSED` result, the baseline protocol lifecycle checks,
the cross-attempt replay result, and exactly one result for every classified
tool. The protected signer must receive the canonical profile, recompute its
digest, and reject missing, duplicate, extra, or effect-mismatched probe results.
Optional baseline capabilities are recorded as either `PASSED` or
`NOT_APPLICABLE`; failed or skipped required checks cannot produce a passing
report.

All canonical JSON and digests use RFC 8785 JSON Canonicalization Scheme (JCS)
and SHA-256. Inputs must remain in the interoperable I-JSON number domain:
integers are limited to `-9007199254740991` through `9007199254740991`, and
non-finite numbers are forbidden. The DSSE signature uses Ed25519 in v1 of
this profile.

I-JSON validation applies after conversion to the RFC 8785 binary64 value. A
fractional spelling that rounds to an integral value outside the safe-integer
range is rejected consistently across SDK languages.

The cross-language acceptance and rejection cases are pinned in
`samples/rfc8785-ijson-number-vectors.json`. SDK conformance implementations
must execute those vectors rather than relying on parser defaults.

The runtime must verify the signature against an independently trusted key,
recompute the live manifest and configured profile digests, enforce an allowed
harness version, and obtain the running provider OCI digest from a trusted
deployment or workload-identity resolver. Neither a configured digest nor a
provider self-report is a workload identity. An arbitrary external URL cannot
be worker-authorized without deployment attestation.

A profile, report, or matching set of operator-supplied hashes without the
signed attestation and trusted workload identity is never sufficient. Baseline
`remote-domain.v1` operation remains available when worker authorization is
absent.

The profile, report, and DSSE envelope schemas live under
`profiles/opportunity-worker/schemas/`. They are out-of-band authorization
artifacts and do not change the closed `remote-domain.v1` manifest schema.
