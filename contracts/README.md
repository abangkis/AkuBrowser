# AkuBrowser Contracts

Current engine contracts:

- `preference-runtime-v2.md` — source-neutral features, reason-aware feedback, champion/challenger activation, and confidence-scaled reranking.
- `selection-engine-v1.md` — generic materiality admission and finite-budget ownership.
- `engine-replay-benchmark-v1.md` — read-only replay metrics and model/effort comparison hooks.

`preference-runtime-v1.md` is retained only as a superseded historical contract.

This directory is the canonical, implementation-neutral contract source for the AkuBrowser workspace.

Runtime projects may vendor a contract snapshot so they remain independently buildable. `npm run check:contracts` verifies that vendored snapshots and protocol identifiers have not drifted.

The reasoning-result contract also carries knowledge-continuity identity. Every promoted item binds to one observed `evidenceKey`, a stable semantic `eventKey`, and an append-only `knowledgeDelta`. These fields allow StateStore implementations to move from SQLite to IndexedDB or a browser-native store without changing their meaning.

Current contract artifacts:

- `onboarding-profile-v0.md` - source-only first-run setup, neutral platform-order transition, and development-reset boundary.
- `calibration-engine-v0.md` - separate first-run labeling lane and its handoff to automatic local fitting.
- `home-surface-v0.md` - finite Timeline, Settings-hosted source control, Source Registry, and update-result boundary.

- `trust-regression-v0.md` — executable prompt-isolation, bounded-evidence, diagnostic-disclosure, and least-authority regression boundaries.
- `operational-diagnostics-v0.md` — read-only AkuDoctor, component version sync, and extension package-fingerprint boundaries.
- `source-freshness-recovery-v1.md` — generic stale-tab wake/reveal state machine and adapter-specific freshness capability contract.
- `media-recovery-v1.md` — bounded media hydration and alternate DOM fallback with truthful degraded presentation.
- `local-data-operability-v0.md` — reversible SQLite health, backup, analysis-export, and retention-preview boundaries.
- `reasoning-provider-conformance-v0.md` — provider capability manifests and the vendor-neutral structural acceptance harness.

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
- `offline-preference-experiment-v0.md` — hard-gated shadow fitting, holdout evaluation, snapshot persistence, and live-influence boundary.
- `preference-replay-v0.md` — descriptive preference diagnostics and historical dataset-maturity gates.
- `preference-runtime-v1.md` — superseded historical automatic-fitting contract; retained for decision lineage only.
