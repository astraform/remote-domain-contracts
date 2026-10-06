# Platform API Contract 0.1.1

Initial public platform API contract bundle. This release is prepared but not
published; consumers must not treat the planned tag as available yet.

The bundle contains the existing Experiment Registry, Agent Catalog, Agent
Journey, Simulation Run, Scenario Lab, evaluation, and MCP management API
contracts. Shared customer simulation payloads are defined in the schema-only
`core/common.yaml` document. Internal runtime command paths and their internal
authentication declaration remain outside this public bundle.

This is a canonical-source and packaging change. Existing API operation IDs,
routes, request/response validation and generated SDK namespaces are preserved.
The partner SDK continues to generate from the Experiment entry point; the
additional documents do not imply new SDK or deployment gateway capabilities.

The artifact is `platform-api.zip`, containing top-level `platform-api/`, with a
SHA-256 checksum file. Its release tag is `platform-api-v0.1.1`. Platform and SDK
builds should pin the exact release and checksum after publication. The provider
`remote-domain.v1` bundle retains its independent version and artifact.
