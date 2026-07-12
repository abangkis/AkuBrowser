# Onboarding Profile Contract v0

> Status: **Designed; not implemented**
> Date: **2026-07-12**

## Purpose

Onboarding creates the first explicit user-authored baseline for AkuBrowser. It replaces the pilot's hard-coded AI/technical-engineering context. It does not activate learned ranking, infer interests from historical feedback, or define interruption policy.

## Product rules

1. Onboarding does not import or summarize the existing pilot database.
2. The initial profile comes only from answers the user explicitly confirms.
3. `More like this` and `Less like this` remain contextual signals collected after onboarding.
4. Exploration appetite is not an onboarding question in v0.
5. P1-P4 are retired. They are not replaced by another hidden priority taxonomy.
6. Before a new ranking contract is activated, unseen candidates remain in source-platform order within the finite attention boundary.
7. Onboarding is short: three screens. Advanced operational controls remain in Settings.

## Three-screen flow

### Screen 1 - What do you want to keep up with?

The user writes one or more interest statements in their own words and may add or remove explicit topic chips. No topics are preselected from historical More/Less signals.

Examples are UI hints only and are never saved unless selected or entered by the user.

Required outcome:

- at least one non-empty interest statement or confirmed topic seed.

### Screen 2 - What kind of information is useful?

The user selects one or more desired content forms:

- changes and announcements;
- practical guides and tutorials;
- opinions and analysis;
- research;
- opportunities; and
- general discovery.

These are positive baseline preferences, not hard exclusions. The user can refine them later through `More like this` and `Less like this`.

### Screen 3 - Sources and confirmation

The user chooses from installed source adapters, with at least one active source, then reviews the complete profile summary and finishes onboarding. The screen links to Settings for advanced engine budgets but does not embed those controls in onboarding.

## Persisted profile

```json
{
  "version": 0,
  "status": "completed",
  "origin": "explicit_onboarding",
  "interestStatements": ["..."],
  "topicSeeds": ["..."],
  "preferredContentTypes": ["announcement", "tutorial"],
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

The provider cannot exclude a candidate merely because it falls outside the old AI/technical-engineering context. Onboarding data and More/Less feedback may be recorded, but neither changes live ordering until a separate ranking-composition contract is approved.

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

