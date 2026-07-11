# Learning Loop Experiment Contract v0

> Status: **Foundation implemented and locally verified; live candidate-label collection pending**
> Date: **2026-07-11**
> Owner: **AkuBrowser**

## Purpose

AkuBrowser must learn from corrections without turning review into another infinite feed. The Learning Loop makes the latest bounded run inspectable, records why each evaluated candidate was selected or excluded, and lets the user correct decisions from both Review Inbox and Unified View.

Pilot Analytics remains an aggregate diagnostic surface. Review Inbox becomes the default calibration workbench during the bootstrap phase; it is not a requirement to label every candidate.

## Fixed boundaries

1. Only evidence blocks supplied to reasoning may be called evaluated candidates.
2. Candidate review remains bounded to the captured run; it never fetches more content.
3. Feedback is append-only and reversible by a later event; history is never rewritten.
4. The source platform's feed order is an upstream prior, not ground truth.
5. Hard provenance, security, duplicate, acquisition, and attention constraints remain deterministic.
6. Codex may extract features and propose decisions, but provider-specific objects never become the preference contract.
7. A future local or open-source provider must be able to emit the same contracts.
8. `should_not_show` is a contextual negative preference signal, not a permanent ban. New evidence, material change, unusual popularity, or network-level relevance may make a topic eligible again under a future comeback policy.
9. Permanent blocking is a separate explicit capability and is outside experiment v0.
10. A future learned selector must preserve a bounded exploration lane for useful content outside established preferences; preference learning must not collapse into a closed filter bubble.

## Candidate decisions

Each unique evaluated evidence block has one current provider decision: `selected`, `deferred`, or `excluded`. Experiment v0 may initially record an unselected candidate as `excluded` with reason `not_promoted_by_provider` when the provider has not emitted richer decision features. This compatibility reason is explicit technical debt, not a semantic claim that the candidate is irrelevant.

## User signals

- `more_like_this`: this candidate is interesting and should strengthen future prioritization. It is not a command to present the item immediately; the engine still owns timing, ordering, deferral, and the finite attention boundary. It may target a selected or unselected candidate.
- `should_show`: legacy alias for `more_like_this`, retained for historical data and API compatibility.
- `should_not_show`: a selected candidate should not have appeared.
- Existing `useful`, `correct_lane`, `wrong_lane`, and `duplicate` signals remain valid for selected items.

Negative reason codes are `wrong_topic`, `already_known`, `duplicate`, `stale_or_superseded`, `low_signal`, `wrong_priority`, and `other`. A free-text note is optional except for `other`.

## Preference model boundary

The preference model is a versioned, rebuildable snapshot derived from append-only feedback. It may contain topic, author, source, novelty, priority, and reason-code tendencies. It must not silently mutate historical selection decisions. Experiment v0 collects trustworthy labels and exposes a neutral profile shell. Learned weights and exploration policy remain inactive until the sample is sufficient to compare them against the original decisions.

## Reasoning configuration and telemetry

Every provider invocation records its phase, provider, configured model and reasoning effort, prompt/contract version, duration, outcome, and observed input, cached-input, output, and reasoning-output tokens when reported. Token usage is reported separately for Candidate Evaluation and Acquisition Planning so quality and economics can be tuned independently. Token fields are observed usage, not a monetary-cost claim. Cost estimates require explicit versioned pricing configuration.

The initial accepted route is Luna High for the narrow acquisition-planning fallback and Terra High for candidate evaluation. Evaluation is a read-heavy relevance and classification workload with bounded output, matching the Scout route. XHigh is an escalation only after Terra High repeats the same capability failure following a precise correction.

Acquisition planning uses `deterministic_sparse_gap`: skip provider planning when there is no unseen evidence, when at least three unseen candidates already support bounded evaluation, or when browser movement cannot justify another viewport. Invoke Luna High only for one or two unseen candidates after the initial scroll budget was exhausted and one anchored follow-up remains technically possible.

## UI behavior

Review Inbox opens the newest run by default. It shows selected and unselected evaluated candidates, decision state, structured assessment, source link, and preference controls. Other runs remain collapsed. Unified View exposes both `More like this` and `Should not show` for every promoted item. The user can accept the recommended set by doing nothing.

## Initial acceptance tests

- Every unique evaluated evidence block is persisted once per run.
- Selected candidates bind to the exact promoted `itemId` and `evidenceKey`.
- `more_like_this` can target any evaluated candidate and legacy `should_show` is normalized to it.
- `should_not_show` can target only a selected candidate.
- Duplicate submissions are idempotent; opposing later signals remain auditable.
- Model and effort shown in the UI equal effective Sidecar configuration.
- Codex usage fields are persisted without estimation when returned by the SDK and aggregated separately by reasoning phase.
- Terra High returns a structured assessment for every supplied candidate in the same evaluation invocation.
- Review Inbox defaults to the newest run expanded and remains finite.

## Current implementation status

The additive SQLite ledger, append-only preference events, provider invocation telemetry, explicit Codex configuration, Review Inbox default, newest-run expansion, and Unified View signals are implemented. Historical `should_show` events remain readable as positive-interest signals. Historical runs remain readable but are not falsely backfilled as evaluated candidates because their exact provider prompt boundary cannot be reconstructed. Preference profile v0 intentionally remains in `collecting` state; learned ranking weights and exploration do not activate until natural candidate labels exist.

An inspectable engine dashboard is deferred until real labels establish which parameters need operator control. It should eventually expose active thresholds, preference tendencies, exploration budget, comeback triggers, policy version, and outcome/economic metrics without allowing UI settings to bypass hard safety constraints.
