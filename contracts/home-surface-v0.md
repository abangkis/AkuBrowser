# Home Surface Contract v0

> Status: **Implemented for the X + LinkedIn pilot**
> Date: **2026-07-12**

## Purpose

AkuBrowser separates the daily consumption surface from the operational source overview. Both read the same persisted sessions and source state; neither changes acquisition authority.

## Timeline

Timeline is the built-in default home presentation.

- It opens a rolling buffer of the newest evaluated items across completed or partial Unified Sessions.
- Its capacity defaults to 12 and is configurable from 1 through 50.
- New session items enter first; older retained items fill only the remaining capacity and the oldest overflow leaves the view.
- After each completed check, the heading reports how many genuinely new items the latest session added. A completed empty check explicitly reports `0 additions`; retained count and capacity are not repeated as the primary status.
- During an active check, the compact progress strip stays visible while the user scrolls the retained Timeline. Newly added items from the latest check use a subtle distinct background until a later check becomes the newest session.
- `Check for updates` directly starts a Unified Catch Up from engine defaults and the active Source Registry; no run form is required.
- While acquisition is active, the retained Timeline remains readable. A compact progress strip above it reports the current source/stage, its deterministic step position, progress, and Cancel. The default two-source update has 12 steps; the total contracts when fewer sources are active. Elapsed-time estimates and detailed run-contract metrics are not part of the daily surface.
- Routine Timeline cards omit coverage diagnostics and duplicate result chrome. Those details remain available in pilot/review surfaces when needed.
- It never auto-loads another session or turns persisted history into an unbounded feed.
- Refresh reads persisted presentation data and does not start browser acquisition.
- Timeline session payloads exclude raw browser observations.

`GET /api/timeline?limit=12&offset=0` returns the bounded rolling buffer with pagination. Entries carry presentation-safe session and child-run context, validated results, candidate presentation data, feedback, and reasoning telemetry, but not raw observations or bridge commands. `GET /api/sessions` remains the presentation-safe session-history seam.

## Settings and source control

The former Overview is merged into Settings so configuration and source state share one control plane.

- Settings reports installed source adapters and current operational health.
- It distinguishes source activation from whether a browser tab is currently reported open.
- It shows the latest bounded activity and collection policy.
- The user may include or exclude installed adapters from the next update; at least one remains active.
- Adding an arbitrary website still requires a compatible AkuBridge adapter and source contract.

## Source Registry v0

Each source declares:

- stable `id` and user-facing `label`;
- `behavior`: `stream`, `periodic`, `static`, or `push`;
- `accessMode`;
- `activationState`;
- `collectionPolicy`; and
- canonical location when applicable.

The initial registry contains X and LinkedIn as `stream`, `authenticated_browser`, `active`, and `user_triggered`. `connected` or `open` is runtime health/lifecycle state reported by BrowserAdapter, not membership in the registry.

The other behavior classes are architectural seams only in v0:

- periodic sources should detect change before invoking reasoning;
- static sources should use manual or infrequent revalidation;
- push sources should ingest events without browser polling.

Their presence in the architecture does not claim that adapters, schedules, or background watchers exist.

## Configuration

Timeline is the only daily home surface. Source operations live in Settings.

`timelineCapacity` accepts an integer from 1 through 50, applies live, persists in the StateStore, and defaults to 12.

Mode, source scope, and free-form session intent are not routine homepage controls. Catch Up and the active Source Registry provide temporary defaults. A future onboarding questionnaire may establish explicit baseline interests; routine `More like this` and `Less like this` feedback then tunes contextual preference without becoming an immediate display command.

## Safety and scope

- Home presentation does not modify priority, checkpoints, attention budgets, or preference influence.
- Source health is observational and cannot grant browser authority.
- Background polling, scheduled watch, P0 notification delivery, and arbitrary website support remain deferred.
