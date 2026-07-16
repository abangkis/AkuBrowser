# Active contracts

This directory contains only contracts that are executed or validated by the current product boundary.

- `bridge-contract-v2.md` defines the read-only AkuBridge/AkuSidecar protocol.
- `acquisition-plan.schema.json` constrains the optional bounded follow-up decision.
- `reasoning-result.schema.json` constrains per-candidate reasoning, evidence identity, event identity, and knowledge delta.
- `calibration-session.schema.json`, `calibration-label.schema.json`, and `calibration-profile-snapshot.schema.json` constrain first-run calibration.

AkuSidecar vendors the five JSON schemas it executes. `scripts/check.ps1` verifies byte-equivalent SHA-256 hashes. Product behavior is defined in `../docs/product-contract.md`; runtime ownership is defined in `../docs/runtime-contract.md`.
