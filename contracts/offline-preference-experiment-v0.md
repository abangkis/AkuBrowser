# Offline Preference Experiment Contract v0

> Status: **Implemented; currently blocked by calibration readiness**
> Date: **2026-07-11**

## Purpose

Offline Preference Experiment v0 fits and evaluates an inspectable preference snapshot from assessed `more_like_this` and `less_like_this` signals. It is a shadow experiment only. It cannot change live eligibility, ranking, attention budgets, exploration, comeback behavior, or Unified View presentation.

## Hard gate

Fitting is permitted only when every Preference Replay v0 readiness gate passes. Before that point:

- `GET /api/preferences/experiment` returns `status: blocked`;
- `POST /api/preferences/experiment/fit` also returns `status: blocked`;
- no preference-model snapshot is persisted; and
- `liveInfluence` remains `false`.

Passing readiness changes the status to `ready_to_fit`; it does not fit or activate anything automatically.

## Dataset and split

Only the latest contextual signal for each assessed run/evidence pair is fitted. The snapshot fingerprint is a deterministic SHA-256 digest of the assessed fitting dataset. Signals are split by stable run identity so candidates from one run cannot appear in both training and holdout. Twenty percent of feedback-bearing runs form the holdout.

## Model v1

The first model is a deterministic, class-balanced, smoothed additive model. It records tendencies for:

- source and original provider decision;
- content type and recommended priority;
- topic tags; and
- intent relevance, novelty, urgency, and actionability.

The model emits a shadow preference probability. That probability is not a relevance fact and is never written back into historical candidate decisions.

## Evaluation

Each snapshot records:

- training and holdout signal/run counts;
- holdout agreement and balanced accuracy;
- positive and negative recall plus the confusion matrix;
- mean shadow score for originally selected and excluded candidates;
- selected/excluded candidates that the shadow model would prefer; and
- source coverage.

`sufficientForActivationDecision` is always `false` in v0. A later explicit decision must define quality thresholds and comparative evidence before live influence is possible.

## Exploration and comeback

The snapshot carries non-active proposals for a bounded exploration lane and future comeback behavior. Both remain `active: false`. Their presence makes the future policy seam inspectable; it does not authorize either mechanism.

## Persistence and idempotency

Fitted snapshots are stored in AkuSidecar SQLite by unique dataset fingerprint. Re-fitting unchanged data returns the existing snapshot rather than creating another version. New assessed feedback creates a new fingerprint and makes the previous snapshot stale.

## API

- `GET /api/preferences/experiment`
- `POST /api/preferences/experiment/fit`

The Review Inbox exposes status, gate progress, snapshot evaluation, and a Fit button that is enabled only for `ready_to_fit`.
