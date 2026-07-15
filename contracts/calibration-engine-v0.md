# Calibration Engine v0

> Status: **Implemented as the first-run label source for Preference Runtime v2**

## Purpose

Calibration verifies a source's existing recommendations against explicit user decisions. It is not a recommendation session and does not replace the timeline. Directional labels feed the local preference ledger used by subsequent automatic fits.

## Lifecycle

```mermaid
flowchart LR
  O["Source-only onboarding"] --> U["First bounded unified update"]
  U --> S["Raw candidate sampler"]
  S --> C["Explicit More/Neutral/Less calibration"]
  C --> P["Append-only local labels"]
  P --> F["Automatic local fit"]
  F --> R["Bounded selected-item reranking"]
```

1. The first completed or partial Unified Session supplies validated raw candidates.
2. The sampler preserves source platform order, caps each source at five entries, and interleaves sources round-robin up to ten entries.
3. Every sampled entry must receive `more_like_this`, `neutral`, `less_like_this`, or a separate capture-issue report. `neutral` means the entry should neither raise nor lower preference weight; it is not an unresolved sample.
4. Decisions may be revised with Previous before completion.
5. Completing all entries writes an immutable calibration summary. More/Less decisions also enter the preference ledger; Neutral and capture issues do not.

## Separation rules

- Calibration labels and ordinary timeline More/Less events share one directional preference ledger. Neutral lets a user advance without manufacturing directional preference.
- Presentation media and avatars remain remote HTTPS references. AkuBrowser does not persist image or video binaries.
- Capture problems (`capture_incomplete`, `wrong_source`, `duplicate`, `formatting`) are quality reports, never preference labels.
- Calibration samples come from candidate evaluation before promotion, so the experiment inspects the borrowed source prior rather than only the current engine's selected output.
- No interest taxonomy, free-form intent, provider relevance lane, exploration, comeback, or permanent block is introduced by this contract.

## Trigger policy

v0 enables only `first_run`. Manual, periodic, and random triggers remain contract-compatible future options but are disabled until the first-run experiment is evaluated.

## Influence boundary

Calibration itself never changes the current session. Its labels may affect
later sessions through Preference Runtime v2's maximum two-position rerank and
Preference Eligibility Controller v2's configured authority. Default
eligibility may add one qualified item only into unused capacity.
