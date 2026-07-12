# Onboarding Profile Contract v0

> Status: **Implemented; calibration-only**
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
7. Onboarding uses four focused screens. Advanced operational controls remain in Settings.

## Four-screen flow

### Screen 1 - Choose broad interests

The user selects one or more broad, curated interest categories in a visual chip grid inspired by social onboarding patterns. No interests are preselected from historical More/Less signals.

These categories define the starting breadth and future exploration space. They are positive signals, not permanent filters.

Required outcome:

- at least one selected interest.

### Screen 2 - Refine the selected interests

The user may describe what they hope to find inside the selected categories. Guidance and an example explain the input's meaning. The refinement cannot introduce a hidden category or exclude a selected category; future ranking treats it as a more specific positive signal inside the selected breadth.

During calibration, this value is persisted and inspectable but has no live ranking influence.

### Screen 3 - What kind of information is useful?

The user selects one or more desired content forms:

- changes and announcements;
- practical guides and tutorials;
- opinions and analysis;
- research;
- opportunities; and
- general discovery.

These are positive baseline preferences, not hard exclusions. The user can refine them later through `More like this` and `Less like this`.

### Screen 4 - Sources and confirmation

The user chooses from installed source adapters, with at least one active source, then reviews the complete profile summary and finishes onboarding. The screen links to Settings for advanced engine budgets but does not embed those controls in onboarding.

## Persisted profile

```json
{
  "version": 0,
  "status": "completed",
  "origin": "explicit_onboarding",
  "selectedInterests": ["ai", "software_development"],
  "interestRefinement": "Practical Codex workflows and creative AI uses.",
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
