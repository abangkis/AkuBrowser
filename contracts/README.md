# Active and staged contracts

This directory contains contracts that are executed by the current product
boundary or staged as the normative input to an explicitly gated implementation.

- `bridge-contract-v2.md` defines the read-only AkuBridge/AkuSidecar protocol.
- `acquisition-plan.schema.json` constrains the optional bounded follow-up decision.
- `reasoning-result.schema.json` constrains per-candidate reasoning, evidence identity, event identity, and knowledge delta.
- `semantic-event-resolution.schema.json` constrains the separate cross-source event resolver and its high-precision relationship labels.
- `ai-deep-detection.schema.json` constrains asynchronous Deep Detection without turning an origin signal into a claim of authorship certainty.
- `calibration-session.schema.json`, `calibration-label.schema.json`, and `calibration-profile-snapshot.schema.json` constrain first-run calibration.
- `native-runtime-messaging.schema.json` defines the staged Chrome extension to
  native runtime host protocol. It becomes executable in rollout Stage 2/3 and
  must not be treated as a currently installed host.
- `examples/native-runtime-ensure-request.json` and
  `examples/native-runtime-ready-response.json` are accepted protocol examples.
  `examples/native-runtime-invalid-arbitrary-action.json` must remain rejected.

AkuSidecar vendors the seven JSON schemas it executes. `scripts/check.ps1`
verifies byte-equivalent SHA-256 hashes. The staged native protocol remains
owned by AkuBrowser until its host exists. Product behavior is defined in
`../docs/product-contract.md`; runtime ownership is defined in
`../docs/runtime-contract.md`; Store distribution is defined in
`../docs/chrome-store-distribution-contract.md`.
