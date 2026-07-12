# Home Surface Contract v0

> Status: **Implemented for the X + LinkedIn pilot**
> Date: **2026-07-12**

## Purpose

AkuBrowser separates the daily consumption surface from the operational source overview. Both read the same persisted sessions and source state; neither changes acquisition authority.

## Timeline

Timeline is the built-in default home presentation.

- It opens the latest completed or partial Unified Session after reload.
- It renders the existing finite, source-backed result and explicit finish line.
- The run form is a collapsible `Check for updates` runner rather than the home page itself.
- It never auto-loads another session or turns persisted history into an unbounded feed.
- Refresh reads persisted presentation data and does not start browser acquisition.
- Timeline session payloads exclude raw browser observations.

`GET /api/sessions?limit=1&offset=0` returns presentation-safe completed or partial Unified Sessions with pagination. Page size is bounded from 1 through 10. Child runs may include validated results, coverage, candidate presentation data, feedback, and reasoning telemetry, but not raw observations or bridge commands.

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

## Safety and scope

- Home presentation does not modify priority, checkpoints, attention budgets, or preference influence.
- Overview health is observational and cannot grant browser authority.
- Background polling, scheduled watch, P0 notification delivery, and arbitrary website support remain deferred.
