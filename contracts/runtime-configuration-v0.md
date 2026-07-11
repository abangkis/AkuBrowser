# Runtime Configuration Contract v0

> Status: **Initial live and startup settings implemented**
> Date: **2026-07-11**

## Purpose

AkuBrowser exposes allowlisted operational settings through its local dashboard without turning arbitrary environment or process configuration into a web-editable surface.

## Precedence

1. Valid environment override.
2. Persisted dashboard value in AkuSidecar SQLite settings.
3. Built-in default.

The dashboard must show the effective value, persisted value, source, and apply mode. When an environment override is active, dashboard editing is disabled.

## Initial setting

`missingSourceTabPolicy` accepts:

- `open_missing_tab`: initial acquisition may open one inactive canonical source feed tab;
- `fail_fast`: initial acquisition fails when no eligible tab exists.

The setting applies to the next run without restarting AkuSidecar. Follow-up acquisition always behaves as fail-fast because its observation must remain anchored to the existing tab frontier.

`defaultPresentation` accepts `source` or `brief`. It applies immediately to newly rendered Unified View and Review Inbox items. The built-in default is `source`; an individual item can still be switched without changing the saved default.

## Startup reasoning settings

The dashboard also persists the existing reasoning startup configuration:

- `reasoningProvider`: `codex-sdk` or `deterministic`;
- `evaluationModel` and `planningModel`;
- `evaluationEffort` and `planningEffort`;
- `planningPolicy`: `deterministic_sparse_gap` or `always`;
- `timeoutMs`: `1000..600000`.

These values do not mutate the active provider. They become effective only after the user restarts the visible AkuSidecar process. Until then the API and dashboard expose both the persisted and effective values with `restartRequired: true`.

## Persistence and safety

- Dashboard values are persisted in SQLite and survive Sidecar restarts.
- Only named settings with explicit enums may be updated.
- Port, database path, executable path, arbitrary environment variables, and secrets are not dashboard-editable.
- Runtime configuration cannot broaden AkuBridge host permissions or browser-action authority.
- Invalid values fail closed with a contract error.

## API

- `GET /api/configuration/runtime`
- `PUT /api/configuration/runtime`

The update endpoint accepts only the allowlisted configuration object. Expansion to attention budgets or other engine parameters requires a new explicit contract decision.
