# Onboarding Profile Contract v0

> Status: **Implemented; source selection only**
> Date: **2026-07-12**

## Purpose

Onboarding connects the sources AkuBrowser may inspect. It does not ask the user to restate interests already encoded by a social source's long-lived behavioral model, activate learned ranking, infer interests from historical feedback, or define interruption policy.

## Product rules

1. Onboarding does not import or summarize the existing pilot database.
2. The initial profile contains only source choices the user explicitly confirms.
3. Entry-level `More like this` and `Less like this` are collected by a separate forced calibration lane after the first update.
4. Exploration appetite is not an onboarding question in v0.
5. P1-P4 are retired. They are not replaced by another hidden priority taxonomy.
6. Before a new ranking contract is activated, unseen candidates remain in source-platform order within the finite attention boundary.
7. Onboarding uses one focused source-selection screen. Advanced operational controls remain in Settings.
8. Completing first-time onboarding immediately starts the first bounded update.
9. A successful first update starts one bounded calibration session automatically.

## Source-selection flow

### Screen 1 - Sources and confirmation

The user chooses from installed source adapters, with at least one active source, then reviews the profile and finishes onboarding. The first bounded update starts automatically. The screen links to Settings for advanced engine budgets but does not embed those controls in onboarding.

## Persisted profile

```json
{
  "version": 0,
  "status": "completed",
  "origin": "explicit_onboarding",
  "activeSources": ["x", "linkedin"],
  "completedAt": "ISO-8601 timestamp"
}
```

The profile is provider-neutral and stored behind `StateStore`. It must not contain Codex prompt fragments, model identifiers, browser credentials, or inferred historical preferences.

## Neutral transition before learned ranking

Removing P1-P4 leaves presentation ordering under deterministic policy:

1. suppress already-known or exact duplicate evidence;
2. retain each source's visible platform order;
3. interleave active sources deterministically;
4. stop at the configured per-source and unified attention limits; and
5. use the ReasoningProvider only for structured description, topic/content metadata, knowledge delta, and source-backed summarization.

The provider cannot exclude a candidate merely because it falls outside the old AI/technical-engineering context. Source selection and calibration labels may be recorded, but neither changes live ordering until a separate ranking-composition contract is approved.

## Deferred

- exploration budget;
- comeback triggers;
- hard blocks or permanent bans;
- P0 notifications;
- implicit behavioral learning;
- onboarding-derived live ranking; and
- migration of old P1-P4 pilot rows.

## Development reset

The onboarding test may start from an empty development database. Reset is an explicit operator action, preceded by a backup when the current pilot data still has analytical value. Onboarding never deletes or resets data automatically.
