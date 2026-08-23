# Active and staged contracts

This directory contains contracts that are executed by the current product
boundary or staged as the normative input to an explicitly gated implementation.

- `bridge-contract-v2.md` defines the read-only AkuBridge/AkuSidecar protocol.
- `acquisition-plan.schema.json` constrains the optional bounded follow-up decision.
- `reasoning-result.schema.json` constrains per-candidate reasoning, evidence identity, event identity, and knowledge delta.
- `semantic-event-resolution.schema.json` constrains the separate cross-source event resolver and its high-precision relationship labels.
- `ai-deep-detection.schema.json` constrains asynchronous Deep Detection without turning an origin signal into a claim of authorship certainty.
- `calibration-session.schema.json`, `calibration-label.schema.json`, and `calibration-profile-snapshot.schema.json` constrain first-run calibration.
- `native-runtime-messaging.schema.json` defines the current strict v2
  capability-negotiated AkuBridge to native-host protocol.
- `native-runtime-messaging-v1.schema.json` freezes the exact v1 migration
  shape. It must never gain v2 actions, capability negotiation, urgency, or
  deadline fields because deployed hosts reject unknown properties.
- `runtime-update-manifest.schema.json` defines the current independently
  versioned AkuSidecar update feed (schema v2), including host, Bridge, database,
  and platform compatibility gates.
- `runtime-update-manifest-v1.schema.json` freezes the legacy AkuBrowser runtime
  feed. It remains separately signed during migration because installed v1
  hosts reject every unknown field; v2 fields must never be added to that feed.
- `installed-app-active-pointer.schema.json` and
  `installed-app-bundle-manifest.schema.json` define the strict Windows launcher
  selection and complete-tuple payload boundary for the new installed-app lane.
- `examples/native-runtime-ensure-request.json` and
  `examples/native-runtime-ready-response.json` are accepted v2 examples.
  Their `native-runtime-v1-*` counterparts are accepted frozen migration
  examples. `examples/native-runtime-invalid-arbitrary-action.json` must remain
  rejected by both the action allowlist and strict-property boundary.

AkuSidecar vendors the seven JSON schemas it executes. `scripts/check.ps1`
verifies byte-equivalent SHA-256 hashes. The staged native protocol remains
owned by AkuBrowser until its host exists. Product behavior is defined in
`../docs/product-contract.md`; runtime ownership is defined in
`../docs/runtime-contract.md`; Store distribution is defined in
`../docs/chrome-store-distribution-contract.md`.
