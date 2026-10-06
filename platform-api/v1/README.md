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
- Bundle version: `0.1.1`; planned release tag: `platform-api-v0.1.1`.
- Release asset: `platform-api.zip`, containing top-level `platform-api/`.

This bundle contains API definitions, not platform implementation or deployment
credentials. Internal runtime endpoints and their authentication scheme are not
included. The runtime and public API use the same shared payload definitions;
OpenAPI generators consume the entry point and its relative schema references.

The platform repository and both language SDKs consume the same checksum-pinned
release. Edit these canonical files here and publish a new immutable contract
version before updating consumers. The initial bundle is currently unpublished;
explicit local ZIP builds are for development only.
