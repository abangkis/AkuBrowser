# AkuBrowser Contracts

This directory is the canonical, implementation-neutral contract source for the AkuBrowser workspace.

Runtime projects may vendor a contract snapshot so they remain independently buildable. `npm run check:contracts` verifies that vendored snapshots and protocol identifiers have not drifted.

The reasoning-result contract also carries knowledge-continuity identity. Every promoted item binds to one observed `evidenceKey`, a stable semantic `eventKey`, and an append-only `knowledgeDelta`. These fields allow StateStore implementations to move from SQLite to IndexedDB or a browser-native store without changing their meaning.

Current contract artifacts:

- `reasoning-result.schema.json` — validated provider-neutral result items.
- `acquisition-plan.schema.json` — the finite provider acquisition decision.
- `bridge-contract-v1.md` — the constrained localhost and page-message bridge protocol.
- `unified-session-experiment-v0.md` — the accepted product, lifecycle, merge, feedback, and finite-scroll boundary for the unified X + LinkedIn experiment.
- `unified-session.schema.json` — the persisted parent-session, child-run, aggregate-result, and coverage resource contract.
- `learning-loop-experiment-v0.md` — the review-first preference-learning and telemetry boundary.
- `candidate-evaluation.schema.json` — one auditable decision for every evaluated evidence block.
- `preference-feedback.schema.json` — append-only corrections from Review Inbox and Unified View.
- `preference-profile.schema.json` — a rebuildable, provider-neutral learning snapshot.
- `selection-decision.schema.json` — the deterministic selection audit record.
- `reasoning-invocation.schema.json` — provider configuration, outcome, latency, and observed token usage.
- `reasoning-routing-v0.json` — explicit phase-level model, effort, and planning-policy defaults.
- `runtime-configuration-v0.md` — allowlisted dashboard settings, persistence, precedence, and apply-mode boundary.
