# Preference Runtime Contract v2

> Status: **Implemented; supersedes v1**

Preference Runtime is automatic and local. Manual fitting is an optional
diagnostic action. Selection Engine decides eligibility before preference
scoring.

Version 2 uses stable features only: canonical topic facets, content type,
novelty, urgency, actionability, materiality, and evidence strength. Source
identity is prohibited as a preference feature. Source balance is a hard
composition constraint, not an inferred taste. Raw tags remain explanatory but
are canonicalized before fitting.

## Feedback semantics

Every event records `origin` (`calibration` or `routine`) and a context id.
Neutral is a real tie/regularization signal. Wrong-topic and wrong-priority Less
events train preference. Ambiguous legacy Less events receive reduced weight.
Reasons owned by continuity, deduplication, recency, or materiality do not train
topic preference.

## Champion and challenger

The active champion remains live while newer feedback is fitted. A candidate is
promoted only when it upgrades the model version or improves holdout balanced
accuracy by the configured margin without materially regressing negative
recall. Otherwise it remains an inspectable challenger.

Reset suspends automatic fitting without deleting feedback. A forced
before-session fit respects suspension; only explicit manual refit resumes the
runtime.

## Live authority

Preference reorders only selected items. Authority is confidence-scaled: zero
positions for weak evaluation, one position from balanced accuracy `0.50`, and
two positions from `0.65`. A swap requires a score delta of `0.03`. Composition
avoids three consecutive items from one source when a bounded alternative is
available. Preference never hides, promotes, acquires, or changes budgets.

## APIs

- `GET /api/preferences/runtime`
- `POST /api/preferences/runtime/refit`
- `POST /api/preferences/runtime/reset`
- `GET /api/preferences/benchmark`
- replay, experiment, and shadow-comparison diagnostics remain under
  `/api/preferences/*`.

