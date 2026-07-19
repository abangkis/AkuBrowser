# AkuBrowser preference learning contract

Status: technical authority for the current Go implementation, 19 July 2026.

This document explains how direct user feedback becomes personalization, which data is authoritative, and where topic tags and facets enter or leave the system. It complements the product-level rules in `product-contract.md`.

## Terms

- A **candidate assessment** is the structured evaluation of one captured post. It contains evidence quality and value scores plus `topicTags` and `topicFacets`.
- A **preference signal** is the latest effective user decision for one canonical source/evidence identity. It may come from calibration, Timeline More/Less feedback, or `Should have selected`.
- The **preference profile** is the in-memory Go `preference.Profile` fitted from all current effective signals. It contains normalized feature weights and activation flags.
- The **preference model** is the JSON snapshot of that fitted profile stored in SQLite's singleton `preference_model` row. It is a materialized projection, not the canonical learning evidence.

## End-to-end flow

```mermaid
flowchart LR
    A["Captured source evidence"] --> B["Candidate Evaluator"]
    B --> C["Candidate assessment: tags, facets, quality and value scores"]
    C --> D["Durable candidate_assessments"]
    U["Calibration, More/Less, or selection correction"] --> E["Append-only user evidence"]
    D --> F["Canonical latest-signal resolver"]
    E --> F
    F --> G["Deterministic Go preference fitter"]
    G --> H["In-memory preference profile"]
    H --> I["Admission, promotion, suppression, and ranking"]
    G --> J["Persisted preference_model snapshot"]
```

The candidate model describes the post. The user supplies the preference direction. Deterministic Go code resolves authority, fits weights, and applies them to selection. The model provider never directly chooses the final Timeline.

## 1. Where tags and facets originate

Candidate Evaluation emits one assessment for every accepted candidate after capture. The current release uses the configured Codex App Server provider, but the contract is provider-replaceable.

- `topicTags` are specific free-text descriptors: at most five values, each at most 80 characters. Examples are `Codex`, `Spring Data JPA`, or `remote work`.
- `topicFacets` are broad categories: at most three values chosen from the schema-controlled vocabulary such as `ai_models`, `developer_tools`, `career_hiring`, or `sports`.

The reasoning schema requires both fields. AkuSidecar binds the returned assessment back to the captured evidence identity by position, validates the complete result, and stores the assessment with its run. If the deterministic conformance provider is used instead, it emits the fallback tag `unclassified` and facet `other`.

Therefore responsibility is split deliberately:

1. the Candidate Evaluator proposes the semantic description;
2. JSON Schema limits its shape and the facet vocabulary;
3. AkuSidecar binds it to validated evidence and stores it;
4. the user decides whether those features are positive or negative preference evidence;
5. the Go preference fitter calculates the actual authority and weight.

There is currently no direct tag/facet correction UI. More and Less correct the preference direction, not the Candidate Evaluator's semantic description. A wrongly tagged assessment can therefore generalize a correct user decision through the wrong feature until later evidence counterbalances it. Direct semantic-feature correction or evaluator-consistency diagnostics are future hardening options, not current behavior.

## 2. How More and Less become canonical signals

Clicking a Timeline control appends a row to `feedback_events`:

- **More like this** records `direction=more` with no reason;
- **Less like this** records `direction=less` and `reason=not_interested`.

The event is tied to the Timeline item, run, session, and canonical evidence key. Earlier feedback is not overwritten. The Timeline and Update Inbox resolve the newest event for display, while profile fitting resolves one effective signal per canonical `(source, evidenceKey)` identity across three origins:

- routine Timeline feedback;
- calibration labels;
- an active `Should have selected` correction.

Newest evidence wins. If timestamps tie, routine feedback outranks a selection correction, which outranks calibration. This is why a later More or Less choice can correct the taste effect of `Should have selected` without deleting its separate selection audit.

Completed calibration labels remain visible on their original Timeline items: More and Less render as the active button state, while Neutral remains visually neutral. This is a read projection of `calibration_samples`, not a duplicate routine feedback event, so calibration keeps its higher fitting authority. A later Timeline More or Less event replaces that visible state and becomes the newest canonical preference signal.

The current contribution before normalization is:

| Signal | Contribution to every attached tag and facet |
| --- | ---: |
| Routine More | `+1.00` |
| Routine Less / Not interested | `-1.00` |
| Calibration More | `+1.10` |
| Calibration Less | `-1.10` |
| `Should have selected` | `+1.25` |
| Calibration Neutral | `0` |

Legacy code can interpret a reasonless routine Less as `-0.75`, but the active API requires `not_interested`, so the current UI produces the full `-1.00` signal.

## 3. When tags and facets enter, change, or leave the profile

Tags and facets exist first on the durable candidate assessment. They enter the learned profile only when that candidate has an effective non-neutral preference signal.

For each fit, AkuSidecar:

1. collects the latest effective signal for every canonical source/evidence identity;
2. reads that candidate's stored tags and facets;
3. normalizes feature keys by trimming whitespace, collapsing internal whitespace, and lowercasing;
4. adds the signal contribution once per distinct feature;
5. divides the accumulated contribution by `max(3, number of observations for that feature)`;
6. clamps every weight to `[-1, +1]`.

More and Less do not literally insert or delete a tag from a global taxonomy. They add positive or negative evidence to the next fitted weight. Replacing Less with More changes the contribution's sign because only the latest signal for that evidence identity participates.

A feature disappears from a rebuilt profile when no current effective non-neutral signal contributes it. That can happen after:

- Reset learning removes calibration and routine feedback;
- a selection correction is undone and no other effective signal supplies the feature;
- full reset removes all learning data;
- current retention enforcement deletes the old terminal session that owns its assessment and feedback through foreign-key cascade.

The last item is an implementation coupling, not an ideal personalization guarantee. Today knowledge/session retention and learning-evidence lifetime are not fully separated. If long-lived personal taste must survive short evidence retention, AkuBrowser should later retain a compact canonical learning ledger independently of expired run payloads.

## 4. How the profile affects a future Timeline

AkuSidecar rebuilds the profile from canonical signals immediately before deterministic selection for each source run that completes Candidate Evaluation. It also persists a snapshot after completed calibration and during evaluated update runs. Clicking More or Less updates canonical evidence immediately, but does not retroactively rerank the already-visible Timeline; it affects the next profile fit.

The base candidate score remains independent:

`0.40 materiality + 0.20 novelty + 0.15 actionability + 0.10 urgency + 0.15 evidence strength`

Preference alignment is calculated separately:

- when at least one specific tag matches, alignment is `75% tag alignment + 25% facet alignment`;
- when no tag matches, broad facets contribute only `30%` of facet alignment;
- the preference score added to ranking is `0.45 * alignment`.

This makes precise tags authoritative and broad facets a weak fallback. A Less decision about `Spring Data JPA` should not automatically suppress every `developer_tools` post.

Directional authority activates only after a small repeated pattern:

- promotion is ready after at least three effective signals including at least two positive signals;
- suppression is ready after at least three effective signals including at least two negative signals;
- either condition makes the profile authority-ready.

In the default `guarded_live` mode, the profile can promote, replace, demote, suppress, and reorder ordinary candidates. Promotion requires trusted evidence, a minimum generic base score, and alignment of at least `+0.25`. Suppression requires alignment of at most `-0.25` and cannot remove a protected contradiction, material update, highly urgent update, or highly novel update. A bounded neutral discovery lane remains available to reduce filter-bubble lock-in.

## 5. Why canonical evidence remains the source of truth

The stored `preference_model` is currently written but not read as selection authority. Every active selection fit is rebuilt from canonical feedback, calibration, selection corrections, and their candidate assessments.

Benefits of this evidence-first design:

- **User corrections remain explainable.** A weight can be traced back to specific direct decisions.
- **Authority conflicts are deterministic.** The newest canonical decision can supersede an older one without destructive rewriting.
- **Fitting logic can evolve.** New weights or thresholds can be applied to existing evidence without pretending an old snapshot used the new algorithm.
- **Stale or partially written snapshots cannot silently become truth.** Selection derives from the underlying decisions.
- **Audit and reset semantics stay precise.** Selection correction history can remain visible even when its learning influence is undone or reset.
- **Provider output does not own preference direction.** The model describes features, while direct user actions determine positive or negative authority.

Costs of this design:

- fitting reads and recomputes more data than loading one ready-made model;
- provenance tables and conflict resolution are more complex;
- retention of source evidence must be designed carefully so learning does not disappear accidentally;
- the persisted snapshot may be temporarily stale after a More/Less click because it is refreshed at the next fit, even though canonical feedback is already correct;
- without a model version and source watermark, the stored snapshot is useful mainly for diagnostics rather than safe cache reuse.

Making the persisted model the sole source of truth would make startup and scoring cheaper and bound storage more aggressively. It would also require every feedback, undo, reset, retention operation, and fitting-algorithm migration to update that model transactionally. A stale or corrupted aggregate could no longer be explained or corrected from user evidence, and changing the fitting rules would either preserve obsolete behavior or discard accumulated taste.

The recommended long-term boundary is therefore:

- canonical user evidence and candidate features remain authoritative;
- `preference_model` may become a validated cache or serving projection;
- a reusable snapshot must carry a fitting-algorithm version and a source-event watermark or digest;
- any mismatch must fall back to rebuilding from canonical evidence.

## Proposed validated projection contract

Status: accepted direction, not implemented yet.

The persisted model should remain an optimization boundary, never independent authority. A future stored projection should include at least:

- `algorithmVersion`: identifies the exact normalization, weighting, and activation rules;
- `sourceWatermark`: identifies the newest canonical learning event included in the fit;
- `sourceDigest`: binds the projection to the resolved effective-signal set, including active undo/reset boundaries;
- `effectiveSignalCount`: supports a cheap consistency check without replacing the digest;
- `fittedAt`: distinguishes canonical event time from projection time;
- the fitted weights and authority flags already present in `preference.Profile`.

The serving rule should be deterministic:

1. resolve the current canonical learning watermark and digest;
2. load the stored projection only when its algorithm version, watermark, digest, and signal count all match;
3. otherwise rebuild from canonical evidence and atomically replace the projection;
4. never repair canonical feedback from the projection.

More, Less, calibration completion, selection-correction create/undo, Reset learning, and any retention operation that changes effective evidence must invalidate or refresh the projection. This removes the current interval in which `preference_model` can be stale after direct feedback while preserving fast reads when nothing changed.

Two lifecycle boundaries need explicit follow-up design:

- **Learning retention must be independent from bulky run retention.** Expiring screenshots, observations, reasoning telemetry, or old Timeline payloads should not silently erase compact user-taste evidence. A future canonical learning ledger should retain only the evidence identity, normalized semantic features, user direction, origin, authority timestamps, and reset/undo state needed to refit.
- **Semantic feature correction is separate from preference-direction correction.** More/Less must continue to mean user taste. If tag/facet correction is added, it should be an inspectable correction to the candidate description or evaluator-consistency layer, not another hidden meaning attached to Less.

Until that contract exists, the active safe behavior remains rebuild-on-fit from canonical evidence. The singleton `preference_model` row is diagnostic materialization and must not be treated as a trustworthy cache by new code.

## Current code authority

- `AkuSidecar/internal/reasoning/prompts.go`: Candidate Evaluator boundary.
- `AkuSidecar/schemas/reasoning-result.schema.json`: tag and facet shape.
- `AkuSidecar/internal/store/store.go`: append-only feedback and canonical signal resolution.
- `AkuSidecar/internal/preference/preference.go`: deterministic fitting and alignment.
- `AkuSidecar/internal/selection/selection.go`: Timeline admission and ranking effects.
- `AkuSidecar/internal/engine/calibration.go`: profile rebuild and snapshot persistence.
- `AkuSidecar/internal/store/calibration.go`: persisted `preference_model` projection.
