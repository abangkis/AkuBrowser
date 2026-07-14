# Preference Runtime Contract v1

> Status: **Superseded by Preference Runtime v2; retained for historical audit**

See [`preference-runtime-v2.md`](preference-runtime-v2.md) for the current
source-neutral runtime.

## Product behavior

Preference Runtime is a normal local product capability. Users do not manually
fit a model during routine use. AkuSidecar starts from source/platform order,
fits a deterministic personal snapshot from explicit calibration and contextual
More/Less signals, and applies the latest compatible snapshot to subsequent
Unified Sessions.

Manual refitting, replay gates, holdout metrics, and eligibility-boundary
comparison are advanced diagnostics. They never block the baseline experience.

## Baseline and cold start

The cold-start baseline is `source_platform_order`:

- provider selection remains the eligibility boundary;
- platform order is the upstream prior within each source;
- active sources are interleaved deterministically; and
- the finite per-source and Unified Session ceilings remain unchanged.

No global topic, author, or source-taste weights are inferred from one pilot
user and shipped as universal preference.

## Automatic local fitting

AkuSidecar may fit locally once there are at least four assessed directional
signals containing at least one More and one Less label. A stale model is fitted
before the next Unified Session. Contextual feedback may also trigger a fit after
five new assessed signals. Fitting is deterministic, local, versioned, and does
not invoke a reasoning model.

Calibration More/Less labels enter the same append-only preference ledger as
routine feedback. Neutral and capture-issue decisions do not create directional
preference signals.

Evaluation keeps a stable run-level holdout for diagnostics, then the active
personal model is fitted from all current assessed signals. A new snapshot is
promoted atomically by persisted identifier. When no compatible snapshot is
available, AkuSidecar keeps the baseline order.

## Live influence boundary

Version 1 allows only `bounded_selected_rerank`:

- only candidates already selected by the provider participate;
- every selected item remains present;
- no excluded candidate is promoted;
- no selected candidate is removed;
- one item may move at most two positions from baseline order;
- a neighboring swap requires a preference-score difference of at least `0.03`;
- source acquisition and attention budgets never change; and
- every persisted result records snapshot id, baseline index, final index, and
  displacement.

Disabling Local personalization in Settings takes effect on the next run and
falls back to source/platform order. Existing historical results are not silently
rewritten.

Exploration and comeback do not need a separate quota while eligibility is
unchanged because the complete provider-selected set is still retained. They
must be explicitly designed before preference may alter eligibility.

## Diagnostics

Review Inbox exposes a collapsed Advanced preference diagnostics section with:

- replay coverage and historical readiness gates;
- holdout agreement, balanced accuracy, and polarity recall;
- model snapshot identity and feature contributions;
- eligibility-boundary comparison; and
- an explicit `Refit local snapshot` action.

The manual action is idempotent for an unchanged dataset. It is intended for
debugging, policy validation, and tinkering rather than onboarding or daily use.

## APIs

- `GET /api/preferences/runtime`
- `POST /api/preferences/runtime/refit`
- `POST /api/preferences/runtime/reset`
- `GET /api/preferences/replay`
- `GET /api/preferences/experiment`
- `GET /api/preferences/shadow-comparison`

The older experiment fit endpoint remains temporarily callable for development
compatibility, but it is not part of the routine UI or activation lifecycle.

## Deferred authority

Promoting excluded candidates, hiding selected candidates, changing source
shares, or changing attention budgets requires a later contract with explicit
exploration, comeback, rollback, and user-control behavior.
