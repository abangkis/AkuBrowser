# Runtime Configuration Contract v0

> Status: **Live and startup Settings implemented; environment setup deprecated**
> Date: **2026-07-15**

## Purpose

AkuBrowser exposes allowlisted operational settings through its local dashboard without turning arbitrary environment or process configuration into a web-editable surface.

## Normal configuration path

AkuBrowser Settings is the recommended configuration surface. A fresh checkout
uses the committed `codex-sdk`, Luna High, Terra High, and
`deterministic_sparse_gap` defaults without requiring environment setup.
Settings persist in AkuSidecar SQLite and survive supervised restarts.

## Resolution precedence

1. Valid environment override.
2. Persisted dashboard value in AkuSidecar SQLite settings.
3. Built-in default.

This order describes current compatibility behavior, not the recommended
installation workflow. Environment overrides are reserved for packaging or a
short-lived recovery diagnostic. The dashboard must show the effective value,
persisted value, source, and apply mode. When an environment override is active,
dashboard editing is disabled; remove the override after recovery so Settings
becomes authoritative again.

## Initial setting

`preferenceEligibilityMode` applies to the next run:

- `rank_only`: keep Selection Engine eligibility unchanged;
- `promote_unused_budget`: default; add at most one qualified preference
  candidate only when a per-source result slot is unused;
- `guarded_live`: additionally permit one protected, evidence-gated
  suppression. This is experimental and never bypasses the mandatory or
  reliable-floor protections.

Changing the mode does not refit the preference model, broaden acquisition, or
alter the source budget. The complete authority contract is
[`preference-eligibility-controller-v2.md`](preference-eligibility-controller-v2.md).

`missingSourceTabPolicy` accepts:

- `open_missing_tab`: initial acquisition may open one inactive canonical source feed tab;
- `fail_fast`: initial acquisition fails when no eligible tab exists.

The setting applies to the next run without restarting AkuSidecar. Follow-up acquisition always behaves as fail-fast because its observation must remain anchored to the existing tab frontier.

`defaultPresentation` accepts `source` or `brief`. It applies immediately to newly rendered Unified View and Review Inbox items. The built-in default is `source`; an individual item can still be switched without changing the saved default.

`homePresentation` is retained as a compatibility setting, but Timeline is now the only daily landing surface. The former Overview source controls live inside Settings.

`timelineCapacity` accepts an integer from 1 through 50. It controls the maximum number of evaluated updates retained in the rolling Timeline and defaults to 24 during the expanded-load experiment. New items displace the oldest retained items only after the capacity is full.

`activeSources` accepts an ordered non-empty subset of installed source adapters. It applies to the next run and defaults to `x,linkedin`. The pilot can include or exclude X and LinkedIn; registering an arbitrary website still requires a compatible adapter and source contract.

The Engine constraints group begins with one coordinated `boundedLoadProfile`:

- `standard_1x`: 2 scrolls, 5 items per source, 10 total, Timeline 12, 300 ms media settle;
- `expanded_2x`: 4 scrolls, 10 items per source, 20 total, Timeline 24, 1,000 ms media settle;
- `stress_3x`: 6 scrolls, 15 items per source, 30 total, Timeline 36, 1,000 ms media settle;
- `custom`: preserve the explicit advanced values.

Changing this one setting persists every derived budget. Editing an advanced
item, scroll, or Timeline value automatically changes the profile to `custom`.
The profile is the normal tuning path; advanced fields are retained for
diagnosis and controlled experiments.

The group also exposes four next-run budgets:

- `maxItemsPerSource`: 1 through 15, default 10 for the expanded-load experiment;
- `maxScrolls`: 0 through 6, default 4 for the expanded-load experiment;
- `maxAcquisitionRounds`: 1 or 2, default 2;
- `maxKnowledgeContextEvents`: 1 through 100, default 20.

It also displays the structural safety boundaries: at most 30 unified items under the largest built-in profile, one follow-up scroll, three continuation anchors, 20 evidence blocks per snapshot, 4,000 characters per block, four media entries per block, 45-second capture timeout, and 5-second fresh-content wait.

`streamWidth` accepts `compact`, `social`, `comfortable`, or `wide`. It applies live to Session and Review Inbox while leaving Settings at the full application width. The built-in `social` default is 640 px including panel padding, producing a reading column close to the primary feeds on X and LinkedIn.

`telemetryBehavior` accepts `flow` or `sticky`. The built-in default is `flow`, which lets Pilot Telemetry extend with the page. `sticky` constrains it to a separately scrolling rail on wide layouts.

## Startup reasoning settings

The dashboard also persists the existing reasoning startup configuration:

- `reasoningProvider`: `codex-sdk` or `deterministic`;
- `evaluationModel` and `planningModel`;
- `evaluationEffort` and `planningEffort`;
- `planningPolicy`: `deterministic_sparse_gap` or `always`;
- `timeoutMs`: `1000..600000`.

These values do not mutate the active provider. They become effective only
after the user restarts the visible AkuSidecar service through AkuSupervisor.
Until then the API and dashboard expose both the persisted and effective values
with `restartRequired: true`.

## Persistence and safety

- Dashboard values are persisted in SQLite and survive Sidecar restarts.
- Only named settings with explicit enums may be updated.
- Environment variables are not recommended as install or daily-run settings.
- Port, database path, executable path, arbitrary environment variables, and secrets are not dashboard-editable.
- Runtime configuration cannot broaden AkuBridge host permissions or browser-action authority.
- Invalid values fail closed with a contract error.

## API

- `GET /api/configuration/runtime`
- `PUT /api/configuration/runtime`

The update endpoint accepts only the allowlisted configuration object. Additional engine parameters require a new explicit contract decision.
