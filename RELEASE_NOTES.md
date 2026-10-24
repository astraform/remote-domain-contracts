Public contracts 1.2.4 document bounded Experiment JSON and evidence admission
and typed admission errors. A platform release containing the controls is
required to enforce them. Contract publication does not deploy the platform or
update an installed SDK. The provider protocol remains `remote-domain.v1`.

## Experiment admission

- Adds `ExperimentIngressError` to the Experiment and evaluation API definitions.
  Its JSON body has required string fields `code` and `message`, with no
  additional properties. Other business-validation errors retain their existing
  response shapes.
- Documents `400` / `INVALID_EXPERIMENT_REQUEST` for malformed JSON,
  `413` / `EXPERIMENT_PAYLOAD_TOO_LARGE` for exceeded byte, JSON structure,
  batch or record limits, and `415` /
  `EXPERIMENT_CONTENT_ENCODING_UNSUPPORTED` for non-identity request content
  coding. Clients should branch on the status and code.
- Covers write requests under `/api/experiments`, `/api/experiment-runs`,
  `/api/simulation-runs`, `/api/evaluations` and `/api/calibration-observations`,
  including descendant routes. Actual request bytes are bounded even with
  unknown or chunked lengths. The default request limit is 16 MiB, with maximum
  JSON depth 64 and 100,000 tokens.
- Describes complete raw evidence-batch and serialized UTF-8 record admission
  before row or checkpoint-file effects. An admission rejection does not
  partially persist the rejected batch; unrelated database or filesystem failures
  retain their existing behavior.

## Limits and compatibility

Evidence batches default to 1,000 records and records to 1 MiB. Operators can
configure request bytes from 1 to 67,108,864, batch count from 1 to 10,000, and
record bytes from 1 to 16,777,216; the record limit cannot exceed the request
limit. Agent, event and checkpoint batch schemas declare `maxItems: 10000`,
while each deployment's configured admission limit still applies.

Split larger submissions into admitted batches, and send uncompressed JSON.
Setting the new limit variables does not upgrade an older platform image. See
the [platform admission guide](platform-api/v1/README.md#experiment-admission-errors-124)
for variable names and error handling.

Existing operation IDs, successful response schemas and provider lifecycle
payloads are unchanged. Provider and native profile identifiers remain stable.
The governed connection registry and frozen-revision behavior introduced in
1.2.3 remain available with supporting platform and SDK versions. Published
1.2.3 and earlier archives and checksums remain immutable; see the
[changelog](CHANGELOG.md) for their features and provenance.

## Downloads and upgrade

Both bundles share version 1.2.4 and ship with separate checksums:

- `remote-domain.v1.zip` and `remote-domain.v1.zip.sha256`, rooted at
  `remote-domain.v1/`.
- `platform-api.zip` and `platform-api.zip.sha256`, rooted at `platform-api/`.

After publication, pin `v1.2.4` and verify each asset's own checksum before
regenerating consumers. SDKs that need the new error models require generation
from the new published contract and their own package publication; changing a
contract pin does not update an installed client. Until publication, select
development ZIPs explicitly as `LOCAL_PRERELEASE` inputs. They do not replace
published dependencies. See the [release procedure](README.md#release).
