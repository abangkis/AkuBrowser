# AkuBrowser runtime contract

Status: canonical implementation boundary, 19 July 2026.

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
  -> native-content continuity check + configurable resurface cooldown
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

The current inference transport is one managed `codex app-server` stdio process. Acquisition planning, candidate evaluation, semantic event resolution, and AI Deep Detection use separate bounded profiles: Luna `high` is the release default for acquisition, semantic resolution, and AI Deep Detection, while candidate evaluation alone defaults to Luna `xhigh`. Each process can be tuned for its next invocation through the backend-owned bounded catalog: Luna High, Luna XHigh, Terra High, Terra XHigh, or Sol Medium. Settings persists only opaque profile IDs; free-form model strings are rejected. A process reads its stored profile once when that process starts, the active provider resolves it to one concrete model-and-effort pair, and that pair remains fixed for the invocation. Settings is not polled during execution, and a change made during an active update applies only to the next applicable process. The domain adapters depend only on a generic structured-inference boundary and their own schemas, so another provider can replace Codex and publish a different catalog without changing event, AI, selection authority, or UI rendering. Each invocation uses an ephemeral read-only thread; no long-lived model thread owns the event index or an AI assessment history. An explicit model-capacity failure may restart the process and retry the same model once inside the original invocation deadline. Cancellation, timeout, validation failure, and model fallback are never retried implicitly. An unexpected process exit fails the active invocation, discards that transport, and lets the next invocation start a fresh process. App Server callbacks are rejected with a protocol error, and a completed turn without a final structured response is a hard failure rather than an empty result.

The Event Engine runs only after every source run is terminal and before global composition. Go performs bounded retrieval over normalized event summaries rather than raw source text. URL, platform, and generic-language tokens cannot trigger resolution. If no retained event reaches the historical overlap gate and no current pair shares a strong event/topic anchor, Go creates separate local event threads without an App Server call. Otherwise it sends at most the configured 5, 10, or 15 historical event aliases, opaque current-candidate aliases, bounded evaluated summaries, and at most a 600-character evidence excerpt per candidate. The model never receives stable event, evidence, Timeline, session, or run IDs. Trigger reason, strongest overlap, retained-event count, model usage, resolver status, and active user split/merge counts are durable Inbox diagnostics. A resolver failure degrades safely: current reports remain unique and session finalization continues. In `show_all` mode the Event Engine is not invoked.

Source scheduling has two typed modes. `progressive_wait` is the fresh default: capture remains a single session-wide browser lane, but the next source may enter that lane once the previous source has committed its observation and moved into reasoning. Codex App Server invocations remain serialized by the provider transport. `full_wait` starts the next source only after the current source run is terminal. Neither mode weakens the global terminal barrier: semantic-event resolution, Timeline composition, retention, calibration handoff, and publication wait for every active source run to complete, fail, or be cancelled. During the pending first-run calibration only, each source uses one bounded capture round and proceeds directly to Candidate Evaluation without an Acquisition Planning model turn. The same session uses a token-free local-index semantic path: every admitted item is established as a new local event while exact native replay constraints remain enforced. Both AI Fast Detection and AI Deep Detection are also skipped; AI assessment begins only with later update checks after calibration. These onboarding-only fast paths reduce funnel latency and token use without changing normal update depth. Model-backed planning, cross-author comparison, and AI assessment begin with later checks. The scheduling mode is snapshotted in session coverage when the check starts, so a later Settings edit affects only a future check. Multiple capture windows are not part of this contract.

AI Fast Detection runs only after the Event Engine and final global composition, so it cannot influence admission, ranking, event grouping, or capacity. The current deterministic detector is text-first and emits a content fingerprint plus explicit evidence codes. Session finalization then makes the Timeline available. AI Deep Detection is queued afterward through its own schema and Luna `high` default profile, with bounded text and opaque post aliases; captured content cannot invoke tools, browse, execute commands, or access local files. Every result binds `assessedObject=social_post` to a typed `signalScope`; evidence that AI created a quoted passage, attached medium, or external artifact cannot become a strong social-post assessment. It reviews only retained posts whose outcome can still change, skipping inadequate text, direct platform/provenance evidence, and active user corrections. The UI polls only while that job is queued or running. A new foreground update cancels older Deep jobs so candidate evaluation retains priority. Deep failure is non-fatal. Its job status, reviewed count, duration, token usage, and failure are retained in Update Inbox for acceptance and cost tuning. All assessment stages are append-only history, while one resolver applies direct-evidence rules and gives the latest active user correction highest authority.

The `AI Detection` Settings switch is authoritative for both detector stages outside onboarding. Disabling it cancels active Deep work, skips subsequent Fast and Deep execution (including selection-correction follow-up), and suppresses AI badges and the AI Signals pane without deleting historical assessments. Re-enabling applies to subsequent work. A Timeline item without an assessment exposes no AI badge; absence of a detector result is not presented as a Neutral result.

Reasoning profile IDs are opaque choices resolved by the active provider catalog. The release defaults are Luna High for acquisition planning, semantic event resolution, and AI Deep Detection, with Luna XHigh only for candidate evaluation. When a provider launches a local runtime, Settings exposes its validated full executable path beside those profiles. The current Codex adapter can rediscover or hot-switch the executable while reasoning is idle; alternate backends can omit this optional provider capability without changing the domain adapters.

## State and recovery

SQLite schema version 6 is the only accepted Go database boundary. Registered sources are seeded into `source_definitions`, and every source-bearing table references that registry instead of carrying fixed X/LinkedIn enums. There is no Node importer and no migration path from an earlier Go schema; a mismatch fails before AkuSidecar creates or alters application tables. Sessions, feedback, AI corrections, and selection corrections are durable; the Bridge heartbeat is process-epoch scoped and must be refreshed after Sidecar replacement. Feedback remains append-only, while fitting and Update Inbox resolve the latest More/Less or selection-correction event for each canonical source/evidence identity. `Should have selected` is initially the strongest positive taste evidence, but a later More or Less event supersedes it for learning. Reset learning keeps the historical Timeline choice visible while excluding corrections older than the reset boundary from the rebuilt profile.

An unchanged native replay inside cooldown cannot consume reasoning or unique Timeline capacity. A changed or cooldown-expired native item may be evaluated again, after which the Event Engine determines whether it is a material update, context, contradiction, or duplicate report. Source-scoped `eventKey` and `knowledgeDelta` remain the first evaluated continuity boundary; the global semantic event index then groups cross-author and cross-source reports. Only `duplicate_report` at or above the configured `0.85–0.95` automatic merge gate is capacity-free; the default gate is `0.92`. User corrections persist as `must_merge` or `must_not_merge` constraints and are undoable; active corrections retain both event sides until undo is no longer pending. Long-form LinkedIn snapshots that later reveal a stable native identity are reconciled before reasoning. Global composition is committed before a session becomes terminal; interrupted active sessions resume through the active-session recovery path, while completed history is never replayed at startup.

Native replay and semantic duplication are separate boundaries. After snapshot reconciliation and before any planning or candidate-evaluation call, Go compares each source-scoped evidence identity with a compact continuity ledger. In default `smart` mode an unchanged native item inside the configured 1, 2, 7, 14, or 30 day cooldown (default 7) is recorded as `resurfaced_unchanged` and fails fast without spending model tokens. Changed content, relationship context, or a material engagement delta bypasses the cooldown as `resurfaced_changed`; an unchanged item after the cooldown is `resurfaced_after_cooldown` and may be evaluated again. `evaluate_all` disables only the fail-fast action, not continuity diagnostics. Candidate Evaluation emits typed `knowledgeRelation`; `prior_knowledge_overlap` is reviewable evidence, while the Event Engine remains authoritative for cross-author and cross-source semantic duplicates. Intentionally re-evaluated native resurfaces are not forced through the old exact-replay merge constraint, allowing a material update or changed context to remain unique.

Retention is a dual boundary over the local SQLite database and its WAL/SHM working files. The selected age limit is 30, 60, or 90 days and the storage cap is 100, 200, 300, 400, 500 MB, or 1 GB. Cleanup runs at startup, after Settings changes, and after terminal sessions; crossing either boundary removes the oldest terminal history, continuity identities, and orphaned event threads. Retention controls how long a replay can be recognized; the independent cooldown controls how long an unchanged replay is automatically skipped.

Full reset is backup-first and idle-only. The health endpoint reports database health but never exposes the absolute database path. Operational diagnosis belongs in the compact Update Inbox and component-native tests. Inbox source cards report Captured, Evaluated, Selected, and Added stage durations, total source elapsed time, aggregate model time, and resurface/skip counts. Total includes browser and orchestration overhead that model time excludes. Inspect flow adds typed native-resurface and prior-knowledge-overlap badges. An unchanged fail-fast replay remains inspectable and retains its trusted native source link, but has no `Should have selected` action because it was deliberately not evaluated; an evaluated overlap uses `Select despite overlap`. `GET /api/inbox/runs/{runId}/trace` accepts one of `captured`, `evaluated`, `selected`, or `added` and returns at most 20 rows per request. `POST /api/inbox/runs/{runId}/re-evaluate` still reuses a failed run's durable observation without requesting a new capture.

## Trust boundary

All HTTP listeners remain loopback-only. AkuSidecar rejects non-loopback Host values before routing. A non-empty browser Origin must be the exact local UI origin; Chrome-extension origins are accepted only on Bridge routes, which still require the durable Bridge token and exact `aku-browser.bridge.v2` header. JSON mutations require `application/json`. Captured source content is untrusted input. Reasoning is read-only, approvals are disabled, structured output is mandatory, and the provider cannot directly navigate, expand the capture budget, select Timeline items, or choose link destinations. Native post links are rebound after inference from the matching captured evidence key and must satisfy the source-specific canonical HTTPS policy.

Capture degradation is explicit. Missing primary media may yield a
usable-degraded item while the Timeline remains usable. Live v57 validation
showed that Quiet X could detect media roots while hydrated media-container and
recoverable-URL counts remained at zero. The v60 passive path therefore combines
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

`AkuSidecar/config/sidecar.json` is strict. The fresh preference mode is `guarded_live`, the fresh bounded-load profile is Standard 1x, and the current reasoning provider is `codex-app-server` (with `deterministic` retained only for local tests). Product Settings remain typed in SQLite and expose source selection, source scheduling, bounded load profile or Custom values, Timeline capacity, capture behavior, personalization mode, calibration, a learning panel, presentation, stream width, semantic display mode, locked resolver shortlist, paired event-memory retention/storage, Smart/Evaluate-all resurface handling, the locked 1/2/7/14/30-day cooldown, the AI Detection master switch, the locked Inline/Drawer/Hide AI presentation, and one bounded reasoning profile per model-backed process. The learning panel starts enabled and is always visible during the active first-run check. Completing first-run calibration atomically turns the setting off. If the user enables it again, the carousel stays above the Timeline while idle as well as during later checks, and the toggle can be changed without restarting the runtime. Source hydration waits are source-registry-owned Settings: X defaults to 12 seconds, LinkedIn to an 18-second total two-phase budget, and Facebook to 25 seconds; each accepts whole-second changes only within five seconds below or above its default. For a fresh database or full reset, `0.7.0-preview.2` uses Standard 1x, Progressive wait, Smart resurface handling with a 7-day cooldown, the learning panel on until first-run calibration is complete, AI Detection enabled with Drawer presentation, Luna High for acquisition planning, semantic resolution, and AI Deep Detection, and Luna XHigh only for candidate evaluation.

The `0.7.0-preview.2` package assumes Codex App with App Server is installed and locally signed in, while Chrome is already signed in to every enabled source. It bundles AkuBridge as an unpacked payload for manual Developer-mode installation. A cross-platform AkuSidecar probe resolves an explicit override, `AKU_CODEX_PATH`, `PATH`, managed Codex App runtimes, and common CLI locations in that order; a candidate is accepted only when its App Server capability probe succeeds. Launchers and future installers consume this same JSON contract instead of maintaining their own path lists. Missing-login assistance and automated browser-extension distribution remain deferred beyond this preview.

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
