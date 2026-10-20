Adds an opt-in domain connection registry and governed Agent Journey selection
to the public platform API. Supporting platform and generated SDK versions are
required; publishing these definitions does not deploy features or update an
installed client. The provider protocol remains `remote-domain.v1`.

## Connection registry

- Register immutable revisions of A2A, native-domain and customer MCP connections.
  List owner-scoped connections and retained revisions with bounded pagination.
- Probe capabilities separately from approval and activation. Discovery performs
  no business work, tool execution or model inference. Activation requires the
  current approved probe and selects the revision for subsequent governed launches.
- Reconcile uncertain mutations with the same request ID and identical body.
  Expected versions fence concurrent changes; retained lifecycle records cannot
  be hard-deleted through this API.
- Use configured deployment-operator bearer permissions and permitted origins
  and credential references. Ownership comes from server configuration, not a
  caller-supplied owner field. Credential values are not part of registration.

## Governed launches and discovery

- Adds optional non-null `AgentJourneyLaunchRequest.connectionSelection` with
  value `REGISTERED` and no wire default. Existing partner, native-domain and
  MCP binding keys select active approved revisions allowed to the authenticated
  operator. Omitting the field preserves startup binding selection and existing
  launch identity.
- Registered selection requires `EXECUTE` permission and explicit connection-key
  and Catalog-agent grants. Existing published Catalog tool grants must match the
  selected binding, provider and descriptor identities; discovery grants no tools.
- Adds `getDomainConnectionCapabilities` to inspect an approved active connection
  through native Java/Python clients. The response contains the connection head,
  exact revision and sanitized capabilities. Legacy discovery signatures remain
  available. Registered launch authentication failures use typed `401`/`403`
  responses.
- A supporting implementation freezes exact revision identities before admission
  and uses them without restarting Runtime. Later activation affects new launches;
  accepted replay retains its original run identity and selection, while its
  operational status may advance.

## Lifecycle and compatibility

Retirement prevents new selection while permitting accepted exact work. Revocation
blocks subsequent governed dispatch without undoing already dispatched work or
discarding uncertain effects. Committed A2A receipt recovery retains the original
operation identity and does not resend the operation when authority is denied or
unavailable. Startup-selected bindings remain a separate path governed by deployment
configuration.

This is trusted deployment-operator functionality, not department self-service
identity or enterprise isolation. New connections must use already permitted
origins and configured credential references. Model and embedding bindings remain
deployment configuration.

Published contract 1.2.2 and its archives remain immutable. Supporting SDKs must
regenerate the new operations and selection model; changing a contract pin alone
does not add them to an installed package. Existing provider routes, profile
identifiers, completion rules and assessment payloads remain available.

## Downloads and upgrade

Both bundles share version 1.2.3 and ship with separate checksums:

- `remote-domain.v1.zip` and `remote-domain.v1.zip.sha256`, rooted at
  `remote-domain.v1/`.
- `platform-api.zip` and `platform-api.zip.sha256`, rooted at `platform-api/`.

After publication, pin `v1.2.3` and verify each asset's own checksum before
regenerating consumers. Until then, select development ZIPs explicitly as
`LOCAL_PRERELEASE` inputs; they do not replace published dependencies. See the
[release procedure](README.md#release) and [changelog](CHANGELOG.md).
