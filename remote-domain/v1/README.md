# remote-domain.v1 Partner Contract Bundle

This directory is the source of the partner-facing `remote-domain.v1` handoff.
It is intentionally about the wire contract, not the monorepo implementation.

## What Partners Receive

- `openapi/remote-domain.yaml`: HTTP/JSON API contract.
- `schemas/remote-domain.schema.json`: JSON Schema bundle for lifecycle payload validation.
- `schemas/*.v1.schema.json`: language-neutral schema source for reusable
  remote-domain documents such as scorecards, Wind Tunnel metadata, cohort
  bundles, population catalogs, and evidence exports.
- `docs/remote-domain-protocol-v1.md`: rendered protocol guide and ownership boundary.
- `docs/opportunity-worker-conformance-profile.md`: optional out-of-band worker
  classification and replay guarantees; it does not extend the v1 wire schema.
- `docs/scenario-lab-finalization-v2-profile.md`: optional out-of-band Scenario
  Lab finalization receipt, artifact-integrity, and retry guarantees. New
  event-driven launches require this profile; pinned legacy recovery remains v1.
- `samples/`: canonical request and response payloads for every lifecycle operation.
- `profiles/opportunity-worker/samples/`: worker-profile replay, report, and signed DSSE/in-toto examples.
- `profiles/opportunity-worker/schemas/`: out-of-band profile, report, and attestation schemas.
- `profiles/scenario-lab-finalization-v2/`: language-neutral profile, receipt,
  and adversarial conformance vectors for crash-safe finalization.
- `manifest.json`: bundle metadata, source provenance, and release artifact name.

## Code Generation Direction

Astraform should not let Java become the real contract by accident. The schema
source in this bundle is the cross-language source of truth.

- Java: use `openapi-generator-maven-plugin` for OpenAPI model generation.
- Python: use `datamodel-code-generator` to generate Pydantic v2 models from
  OpenAPI/JSON Schema.
- SDK author kits may add builders, adapters, and conformance helpers around
  generated models.
- Contract generation must not generate domain business behavior, CEL execution,
  scorecard execution, Spring/FastAPI adapters, or private platform internals.

## Policy Wind Tunnel Scorecard Roles

`capabilities.domainOutcomeScorecardRoles` is optional for compatibility with
existing `remote-domain.v1` providers. When it is absent, the pack declares no
scorecard with authority to originate a positive business verdict.

When present, it uses
`schemas/domain-outcome-scorecard-roles.v1.schema.json`. Its role declarations
must cover the complete `outcomeScorecards` catalog exactly once:

- `BUSINESS_OUTCOME` scorecards may originate a recognized positive business
  recommendation when all proof gates pass.
- `PROOF_GATE` scorecards are downgrade/block-only and cannot originate a
  positive business recommendation.
- A proof-only catalog is valid, but it has no positive business authority.
- Scorecard IDs are exact, untrimmed identifiers. Duplicate IDs, missing or
  extra role declarations, and conflicting role assignments are invalid.
- `outcomeScorecard`, when supplied as the primary scorecard pointer, must be
  exactly JSON-equivalent to one member of the plural catalog. A
  singular-only catalog is invalid.

## Build The Handoff Artifact

From the repository root:

```sh
scripts/package-remote-domain-contract.sh
```

The script writes `build/remote-domain-contract/remote-domain.v1/` and
`build/remote-domain-contract/remote-domain.v1.zip`.

## Versioning Rules

- `remote-domain.v1` is the protocol identifier and compatibility boundary.
- The repository-root `VERSION` owns the shared public-contract release version.
  This bundle's `VERSION`, `manifest.json` and OpenAPI `info.version` mirror it
  (`1.2.0` in this bundle). Both provider and platform API bundles ship together
  under tag `v1.2.0`; protocol and SDK package versions remain separate.
- Breaking protocol changes require `remote-domain.v2`.
- Additive optional fields may stay in `remote-domain.v1` when old clients can ignore them safely.

## Partner Handoff

Give partner engineering teams the generated `remote-domain.v1.zip`. They should
not need to browse this repository to understand the protocol, validate payloads,
or implement the lifecycle endpoints.

- [Native pure state transformation profile](profiles/native-state-transform/README.md):
  introduced in bundle 1.1.0 for opt-in preparation, bounded domain windows and
  authoritative timing over existing opaque-state operations. Domain rules remain
  in the provider; the host persists the complete business checkpoint supplied to
  each operation.

- [Native reference-state profile](profiles/native-reference-state/README.md):
  introduced in bundle 1.1.0 for opt-in provider-owned database evolution,
  reference-only checkpoints and transactional operation replay. Use this profile
  when authoritative business state lives in the partner's backend.
