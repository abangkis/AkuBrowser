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
- `Check for updates` directly starts a Unified Catch Up from engine defaults and the active Source Registry; no run form is required.
- It never auto-loads another session or turns persisted history into an unbounded feed.
- Refresh reads persisted presentation data and does not start browser acquisition.
- Timeline session payloads exclude raw browser observations.

`GET /api/timeline?limit=12&offset=0` returns the bounded rolling buffer with pagination. Entries carry presentation-safe session and child-run context, validated results, candidate presentation data, feedback, and reasoning telemetry, but not raw observations or bridge commands. `GET /api/sessions` remains the presentation-safe session-history seam.

## Overview

Overview is the source control plane, not an alternate infinite result feed.

- It reports registered sources and current operational health.
- It distinguishes source activation from whether a browser tab is currently reported open.
- It shows the latest bounded activity and collection policy.
- `Check for updates` returns to Timeline and opens the same bounded runner.
- The user can choose Overview as the default landing surface without removing Timeline.

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

Their presence in Overview does not claim that adapters, schedules, or background watchers exist.

## Configuration

`homePresentation` accepts `timeline` or `overview`, applies live, persists in the StateStore, and defaults to `timeline`.

`timelineCapacity` accepts an integer from 1 through 50, applies live, persists in the StateStore, and defaults to 12.

Mode, source scope, and free-form session intent are not routine homepage controls. Catch Up and the active Source Registry provide temporary defaults. A future onboarding questionnaire may establish explicit baseline interests; routine `More like this` and `Less like this` feedback then tunes contextual preference without becoming an immediate display command.

## Safety and scope

- Home presentation does not modify priority, checkpoints, attention budgets, or preference influence.
- Overview health is observational and cannot grant browser authority.
- Background polling, scheduled watch, P0 notification delivery, and arbitrary website support remain deferred.
