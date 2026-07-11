# ReasoningProvider Conformance Contract v0

> Status: **Harness implemented; deterministic provider verified**
> Date: **2026-07-12**

## Purpose

AkuBrowser must be able to replace Codex without changing candidate, provenance, acquisition, or telemetry semantics. A provider implementation is therefore accepted through behavior rather than its SDK type or vendor.

## Required phases

A conforming provider exposes:

- `analyze` for candidate evaluation;
- `planAcquisition` for the finite `finish` or `request_follow_up` decision;
- structured output accepted by the canonical schemas; and
- a stable provider name plus explicit capability manifest.

Candidate evaluation must assess every supplied evidence key exactly once. Promoted items may reference only supplied evidence. Telemetry may be absent, but when present it must identify phase, provider, outcome, and non-negative duration. Token usage remains provider-reported rather than estimated.

## Capability manifest

Each configured provider declares execution form, supported phases, structured-output support, model/effort configurability, usage-telemetry support, and whether it is eligible for pilot-quality decisions. Passing the structural contract does not imply quality equivalence.

The deterministic fallback passes transport and schema conformance but remains `pilotQualityEligible: false`. The Codex SDK is manifest-eligible, while live conformance is never invoked automatically because it would consume model quota.

## Verification

`npm run check:provider` runs the deterministic fixture without browser access, network access, model calls, or pilot database writes. Future local/open-source adapters must pass the same harness and then a separate quality benchmark against representative pilot evidence.
