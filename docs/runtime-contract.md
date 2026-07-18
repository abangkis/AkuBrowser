# AkuBrowser runtime contract

Status: canonical implementation boundary, 17 July 2026.

## Components

- AkuBridge is a Manifest V3 Chrome extension. It owns source-specific DOM adapters, bounded read-only capture, freshness recovery, truthful quality reports, and capture-surface cleanup.
- AkuSidecar is one Go process. It owns the embedded UI, loopback API, SQLite, sessions, reasoning transport, deterministic selection, personalization, and Timeline composition.
- AkuSupervisor is the visible Rust lifecycle owner. It starts and stops the Sidecar executable; AkuSidecar has no watcher or hidden replacement process.
- AkuBrowser owns this product contract, the active schemas, and the cross-repository PowerShell check. It has no package runtime.

## Runtime flow

```text
UI session
  -> AkuBridge bounded capture
  -> snapshot reconciliation and quality admission
  -> Codex structured candidate evaluation
  -> exact-evidence and event-continuity exclusion
  -> generic trust/materiality admission
  -> local high-authority personalization + discovery lane
  -> bounded cross-source Event Engine + optional App Server resolution
  -> global cross-source composition + diversity guard
  -> local deterministic AI Fast Detection
  -> finite Timeline, feedback, and Update Inbox
  -> passive X DOM/response media-evidence completion when matching evidence appears
  -> asynchronous AI Deep Detection + presentation-only refresh
```

The current inference transport is one managed `codex app-server` stdio process. Acquisition planning uses Luna `high`; candidate evaluation, semantic event resolution, and AI Deep Detection use separate Luna `xhigh` profiles. The domain adapters depend only on a generic structured-inference boundary and their own schemas, so another provider can replace Codex without changing event, AI, or selection authority. Each invocation uses an ephemeral read-only thread; no long-lived model thread owns the event index or an AI assessment history. An explicit model-capacity failure may restart the process and retry the same model once inside the original invocation deadline. Cancellation, timeout, validation failure, and model fallback are never retried implicitly. An unexpected process exit fails the active invocation, discards that transport, and lets the next invocation start a fresh process. App Server callbacks are rejected with a protocol error, and a completed turn without a final structured response is a hard failure rather than an empty result.

The Event Engine runs only after every source run is terminal and before global composition. Go performs bounded retrieval over normalized event summaries rather than raw source text. URL, platform, and generic-language tokens cannot trigger resolution. If no retained event reaches the historical overlap gate and no current pair shares a strong event/topic anchor, Go creates separate local event threads without an App Server call. Otherwise it sends at most the configured 5, 10, or 15 historical event aliases, opaque current-candidate aliases, bounded evaluated summaries, and at most a 600-character evidence excerpt per candidate. The model never receives stable event, evidence, Timeline, session, or run IDs. Trigger reason, strongest overlap, retained-event count, model usage, resolver status, and active user split/merge counts are durable Inbox diagnostics. A resolver failure degrades safely: current reports remain unique and session finalization continues. In `show_all` mode the Event Engine is not invoked.

AI Fast Detection runs only after the Event Engine and final global composition, so it cannot influence admission, ranking, event grouping, or capacity. The current deterministic detector is text-first and emits a content fingerprint plus explicit evidence codes. Session finalization then makes the Timeline available. AI Deep Detection is queued afterward through its own schema and Luna `xhigh` profile, with bounded text and opaque post aliases; captured content cannot invoke tools, browse, execute commands, or access local files. Every result binds `assessedObject=social_post` to a typed `signalScope`; evidence that AI created a quoted passage, attached medium, or external artifact cannot become a strong social-post assessment. It reviews only retained posts whose outcome can still change, skipping inadequate text, direct platform/provenance evidence, and active user corrections. The UI polls only while that job is queued or running. A new foreground update cancels older Deep jobs so candidate evaluation retains priority. Deep failure is non-fatal. Its job status, reviewed count, duration, token usage, and failure are retained in Update Inbox for acceptance and cost tuning. All assessment stages are append-only history, while one resolver applies direct-evidence rules and gives the latest active user correction highest authority.

## State and recovery

SQLite schema version 5 is the active Go boundary. There is no Node database importer or historical Node migration chain. Narrow current-Go v2/v3/v4 migrations add AI history/job tables, typed assessed-object/signal-scope columns, durable evaluated-candidate payloads, and append-only selection corrections; every other schema mismatch fails closed. The v4 migration is transactional and interruption-safe. It preserves More plus canonical Not interested evidence (including retired `wrong_topic`) but drops retired `already_know`, `old_info`, and `duplicate` preference reasons rather than converting non-preference semantics into taste. Sessions, feedback, AI corrections, and selection corrections are durable; the Bridge heartbeat is process-epoch scoped and must be refreshed after Sidecar replacement. Feedback remains append-only, while fitting and Update Inbox resolve the latest More/Less or selection-correction event for each canonical source/evidence identity. `Should have selected` is initially the strongest positive taste evidence, but a later More or Less event supersedes it for learning. Reset learning keeps the historical Timeline choice visible while excluding corrections older than the reset boundary from the rebuilt profile.

Exact source evidence cannot be delivered twice. Source-scoped `eventKey` and `knowledgeDelta` remain the first continuity boundary; the global semantic event index then groups cross-author and cross-source reports. Only `duplicate_report` at or above the configured `0.85–0.95` automatic merge gate is capacity-free; the default gate is `0.92`. `material_update`, `contradiction`, `new_consequence`, and `context_only` remain unique Timeline information. User corrections persist as `must_merge` or `must_not_merge` constraints and are undoable; active corrections retain both event sides until undo is no longer pending. Long-form LinkedIn snapshots that later reveal a stable native identity are reconciled before reasoning. On startup, completed Go-schema sessions are idempotently recomposed so the global-order invariant also holds for retained development rows created before this authority change.

Retention is a dual boundary over the local SQLite database and its WAL/SHM working files. The selected age limit is 30, 60, or 90 days and the storage cap is 100, 200, 300, 400, 500 MB, or 1 GB. Cleanup runs at startup, after Settings changes, and after terminal sessions; crossing either boundary removes the oldest terminal history and orphaned event threads.

Full reset is backup-first and idle-only. The health endpoint reports database health but never exposes the absolute database path. Operational diagnosis belongs in the compact Update Inbox and component-native tests. Inbox run inspection is a lazy projection over existing observations, candidate assessments, Timeline rows, corrections, and semantic reports. `GET /api/inbox/runs/{runId}/trace` accepts one of `captured`, `evaluated`, `selected`, or `added`, returns at most 20 rows per request, and never adds a second diagnostic persistence model. Evidence identities repeated across capture snapshots pass through the same canonical reconciliation as reasoning, so a late stable permalink does not create a second actionable row; `duplicate_report` remains inspectable but is excluded from the Added stage and count. Evaluated candidates outside the automatic bounded selection expose an opaque correction reference. `POST /api/inbox/runs/{runId}/selection-corrections` immediately restores one such item, then runs item-scoped semantic resolution, knowledge continuity, AI Fast Detection, and asynchronous AI Deep Detection. Undo removes only that restored item and correction-derived continuity. Captured-only rows never bypass reasoning; `POST /api/inbox/runs/{runId}/re-evaluate` reuses a failed run's durable observation without requesting a new capture.

## Trust boundary

All HTTP listeners remain loopback-only. Bridge routes require the durable Bridge token and exact `aku-browser.bridge.v2` header. Captured source content is untrusted input. Reasoning is read-only, approvals are disabled, structured output is mandatory, and the provider cannot directly navigate, expand the capture budget, or select Timeline items.

Capture degradation is explicit. Missing primary media may yield a
usable-degraded item while the Timeline remains usable. Live v57 validation
showed that Quiet X could detect media roots while hydrated media-container and
recoverable-URL counts remained at zero. The v59 passive path therefore combines
the existing `document_start` DOM watcher and fixed bounded MAIN-world resolver
with `x-response-evidence-v2`, a MAIN-world adapter installed at
`document_start`. It observes only successful responses to X's already-issued
`HomeTimeline`, `HomeLatestTimeline`, and `TweetDetail` GraphQL requests. It
does not create or retry network traffic.

Response parsing is transient and bounded. Raw responses, operation URLs, post
text, account state, and provider authentication never cross worlds or persist;
only the matching `x:status:<id>` and allowlisted `pbs.twimg.com` or
`video.twimg.com` media metadata with `x_response_graphql` provenance can enter
the sanitized media cache. The owning author's allowlisted X avatar URL may
enter a separate 30-minute, 256-key in-memory cache so Quiet capture can fill
presentation without foregrounding the tab. A service-worker-owned cross-run
fallback persists only that sanitized URL and normalized status/handle keys
for seven days, capped at 512 keys. Capture consults it only after current DOM
and response evidence fail to expose the avatar. No raw response, post text,
account state, or authentication enters this store, and avatar evidence never
crosses into Sidecar state or post media. The media cache keeps 30 minutes, 128
posts, and four media records per post. When media evidence appears, the UI relay and Bridge-authenticated
Sidecar endpoint revalidate identity and host/path before applying
`passive-x-media-enrichment-v2` to that item's local evidence. This async path
adds no permission and performs no provider request, browser operation, focus
change, reasoning call, selection/ranking change, semantic grouping change, or
capacity spend.

If passive completion has no evidence, the item keeps a bounded Recapture
action. One generic Media Acquisition Engine serves every adapter; source
adapters contribute only media-kind detection and bounded source-specific
extractors. Recapture first revisits only that native post inside the unfocused
managed capture surface, then exhausts primary DOM, source-exposed structured
state, one background hydration reread, and alternate DOM before it may request
foreground visibility. It replaces only local presentation evidence, consumes
no Timeline capacity or reasoning call, and always cleans up its temporary tab
and surface. A small or minimized window is not used because it can change
responsive DOM and hydration; the sufficiently sized managed window remains
unfocused behind the working surface. If this quiet attempt completes without
media, the UI may show one small inline offer for a separate foreground job.
Sidecar accepts that job only after an unavailable background result and
explicit per-item consent. The foreground authorization is one-time, does not
modify the persisted Quiet setting, and restores the prior working surface
unless the user intentionally moved elsewhere. Typed external attachments
remain separate from post media and use one generic renderer. The normal Open
native post action remains available below the card; missing evidence is never
fabricated. AkuBridge never performs social writes.

## Configuration

`AkuSidecar/config/sidecar.json` is strict. The fresh preference mode is `guarded_live`, the fresh bounded-load profile is Standard 1x, and the current reasoning provider is `codex-app-server` (with `deterministic` retained only for local tests). Product Settings remain typed in SQLite and expose source selection, bounded load profile or Custom values, Timeline capacity, capture behavior, personalization mode, calibration, presentation, stream width, semantic display mode, locked resolver shortlist, paired event-memory retention/storage, and the locked Inline/Drawer/Hide AI Detector presentation. A read-only Reasoning processes section reports the active provider, model, effort, and in-run/async phase from runtime configuration; it does not pretend a model change can be hot-applied. Quiet capture uses the dedicated non-focused managed window. Adaptive fidelity directly uses the newest eligible canonical source tab in an ordinary Chrome window; it does not first create or try the Quiet managed window. A persisted user choice such as Expanded 2x remains authoritative across restart; Standard 1x and Inline AI signals apply to a fresh database or full reset.

## Lifecycle and validation

Normal rebuild/restart:

```powershell
cd ..\AkuSidecar
.\scripts\restart-dev.ps1
```

Restarting the registered service through AkuSupervisor does not rebuild the
embedded UI or Go source. Use the command above after source changes; it builds
the candidate binary and refuses replacement while an update session is active.
A manual Supervisor stop or restart is an operator lifecycle action and must not
be issued during capture or reasoning.

Workspace verification:

```powershell
cd ..\AkuBrowser
.\scripts\check.ps1
```

The check verifies schema and version boundaries, runs `go test -p 1 ./...` in AkuSidecar, `npm run check` only inside AkuBridge, and the AkuSupervisor schema-contract test. No command may push changes; repository push remains an explicit user-approved step.
