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
  -> finite Timeline, feedback, and Update Inbox
```

The only Codex transport is one managed `codex app-server` stdio process. Candidate evaluation and semantic event resolution are separate adapters with separate schemas, but share that transport. Each invocation uses an ephemeral read-only thread; no long-lived model thread owns the event index. An explicit model-capacity failure may restart the process and retry the same model once inside the original invocation deadline. Cancellation, timeout, validation failure, and model fallback are never retried implicitly. An unexpected process exit fails the active invocation, discards that transport, and lets the next invocation start a fresh process. App Server callbacks are rejected with a protocol error, and a completed turn without a final structured response is a hard failure rather than an empty result.

The Event Engine runs only after every source run is terminal and before global composition. Go performs bounded retrieval over normalized event summaries rather than raw source text. URL, platform, and generic-language tokens cannot trigger resolution. If no retained event reaches the historical overlap gate and no current pair shares a strong event/topic anchor, Go creates separate local event threads without an App Server call. Otherwise it sends at most the configured 5, 10, or 15 historical event aliases, opaque current-candidate aliases, bounded evaluated summaries, and at most a 600-character evidence excerpt per candidate. The model never receives stable event, evidence, Timeline, session, or run IDs. Trigger reason, strongest overlap, retained-event count, model usage, and resolver status are durable Inbox diagnostics. A resolver failure degrades safely: current reports remain unique and session finalization continues. In `show_all` mode the Event Engine is not invoked.

## State and recovery

SQLite schema version 2 is a fresh Go boundary. There is no Node database importer or migration chain. A schema mismatch fails closed. Sessions and feedback are durable; the Bridge heartbeat is process-epoch scoped and must be refreshed after Sidecar replacement.

Exact source evidence cannot be delivered twice. Source-scoped `eventKey` and `knowledgeDelta` remain the first continuity boundary; the global semantic event index then groups cross-author and cross-source reports. Only `duplicate_report` at or above the configured `0.85–0.95` automatic merge gate is capacity-free; the default gate is `0.92`. `material_update`, `contradiction`, `new_consequence`, and `context_only` remain unique Timeline information. User corrections persist as `must_merge` or `must_not_merge` constraints and are undoable; active corrections retain both event sides until undo is no longer pending. Long-form LinkedIn snapshots that later reveal a stable native identity are reconciled before reasoning. On startup, completed Go-schema sessions are idempotently recomposed so the global-order invariant also holds for retained development rows created before this authority change.

Retention is a dual boundary over the local SQLite database and its WAL/SHM working files. The selected age limit is 30, 60, or 90 days and the storage cap is 100, 200, 300, 400, 500 MB, or 1 GB. Cleanup runs at startup, after Settings changes, and after terminal sessions; crossing either boundary removes the oldest terminal history and orphaned event threads.

Full reset is backup-first and idle-only. The health endpoint reports database health but never exposes the absolute database path. Operational diagnosis belongs in the compact Update Inbox and component-native tests.

## Trust boundary

All HTTP listeners remain loopback-only. Bridge routes require the durable Bridge token and exact `aku-browser.bridge.v2` header. Captured source content is untrusted input. Reasoning is read-only, approvals are disabled, structured output is mandatory, and the provider cannot directly navigate, expand the capture budget, or select Timeline items.

Capture degradation is explicit. Missing primary media may yield a usable-degraded item with a bounded Recapture action. Recapture revisits only that native post, replaces its local presentation evidence when possible, consumes no Timeline capacity or reasoning call, and always cleans up its managed capture surface. The normal Open native post action remains available below the card; missing evidence is never fabricated. AkuBridge never performs social writes.

## Configuration

`AkuSidecar/config/sidecar.json` is strict. The fresh preference mode is `guarded_live`, the fresh bounded-load profile is Standard 1x, and the reasoning provider is `codex-app-server` (with `deterministic` retained only for local tests). Product Settings remain typed in SQLite and expose source selection, bounded load profile or Custom values, Timeline capacity, capture behavior, personalization mode, calibration, presentation, stream width, semantic display mode, locked resolver shortlist, and paired event-memory retention/storage. A persisted user choice such as Expanded 2x remains authoritative across restart; Standard 1x applies to a fresh database or full reset.

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
