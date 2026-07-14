# Offline Preference Experiment Contract v0

> Status: **Retained as optional diagnostics; superseded for product activation by Preference Runtime v1**
> Date: **2026-07-11**

## Purpose

Offline Preference Experiment v0 remains an inspectable diagnostic replay over assessed `more_like_this`, `neutral`, and reason-aware `less_like_this` signals. It is no longer the product activation path. Automatic fitting and bounded live composition are governed by `preference-runtime-v2.md`.

## Diagnostic gate

Fitting is permitted only when every Preference Replay v0 readiness gate passes. Before that point:

- `GET /api/preferences/experiment` returns `status: blocked`;
- `POST /api/preferences/experiment/fit` also returns `status: blocked`;
- no preference-model snapshot is persisted; and
- `liveInfluence` remains `false`.

Passing readiness changes the diagnostic status to `ready_to_fit`. Preference Runtime does not wait for these historical thresholds; it has a smaller mixed-polarity minimum and fits automatically.

## Dataset and split

Only the latest contextual signal for each source/evidence identity is fitted, so repeat appearances cannot multiply one preference event. The snapshot fingerprint is a deterministic SHA-256 digest of that deduplicated assessed dataset. Signals are split by stable run identity so candidates from one run cannot appear in both training and holdout. Twenty percent of feedback-bearing runs form the holdout.

## Model v1.1

The current model is a deterministic, class-balanced, regularized additive model. It records tendencies for:

- source and content type;
- topic tags; and
- novelty, urgency, and actionability.

Original provider decision and recommended priority are deliberately excluded from learned preference features so the preference layer does not learn the engine's own historical output. Categorical features with fewer than three supporting signals receive zero weight; one-sided categories are strongly shrunk; and every categorical contribution is capped at magnitude `0.5`.

The model emits a preference probability. That probability is not a relevance fact and is never written back into historical candidate decisions. The diagnostic comparison still uses `0.6` and `0.25` to inspect hypothetical eligibility-boundary movements. Preference Runtime v1 instead applies bounded neighboring swaps only among already-selected items.

## Shadow comparison

After a snapshot is current for the active dataset, AkuBrowser may compare its probability against the provider's persisted `selected` or `excluded` decision. Candidate comparison first collapses repeat appearances by source/evidence identity, then reports `would_move_up`, `would_move_down`, or `unchanged`, plus bounded feature contributions. It does not invent a numeric provider baseline score and does not alter historical decisions.

`GET /api/preferences/shadow-comparison?limit=50&offset=0` returns an explicit unavailable state while no current snapshot exists. Summary metrics always cover the complete bounded comparison window, while candidate details are paged with `total`, `offset`, `limit`, `returned`, and `hasNext`. The endpoint accepts page sizes from 1 through 100 so complete evaluation does not require one unbounded payload. Every response declares `liveInfluence: false`. A reusable synthetic dataset may exercise fitting, explanation, comparison, and pagination contracts in tests, but synthetic signals are never written to the pilot database or counted toward readiness.

## Evaluation

Each snapshot records:

- training and holdout signal/run counts;
- holdout agreement and balanced accuracy;
- positive and negative recall plus the confusion matrix;
- mean shadow score for originally selected and excluded candidates;
- selected/excluded candidates that the shadow model would prefer; and
- source coverage.

`sufficientForActivationDecision` remains `false` because this legacy field describes eligibility-changing activation. Bounded selected-item reranking no longer depends on it.

## Exploration and comeback

Eligibility exploration and comeback remain deferred. Preference Runtime v1 retains the complete provider-selected set, so bounded presentation reranking does not require a separate exploration quota.

## Persistence and idempotency

Fitted snapshots are stored in AkuSidecar SQLite by unique dataset fingerprint. Re-fitting unchanged data returns the existing snapshot rather than creating another version. New assessed feedback creates a new fingerprint and makes the previous snapshot stale.

## API

- `GET /api/preferences/experiment`
- `POST /api/preferences/experiment/fit`
- `GET /api/preferences/shadow-comparison`

Review Inbox keeps this material under collapsed Advanced preference diagnostics. Manual refitting is explicit and optional; routine fitting is automatic.
