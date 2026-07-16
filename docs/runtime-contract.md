# AkuBrowser runtime contract

Status: canonical implementation boundary, 16 July 2026.

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
  -> global cross-source composition + diversity guard
  -> finite Timeline, feedback, and Update Inbox
```

The default reasoning provider owns one managed `codex app-server` stdio process and constrains each evaluation with the active JSON schema. An explicit model-capacity failure may restart that process and retry the same model once inside the original invocation deadline. Cancellation, timeout, validation failure, and model fallback are never retried implicitly. `codex-exec` remains an explicit conformance transport, not the normal runtime.

## State and recovery

SQLite schema version 2 is a fresh Go boundary. There is no Node database importer or migration chain. A schema mismatch fails closed. Sessions and feedback are durable; the Bridge heartbeat is process-epoch scoped and must be refreshed after Sidecar replacement.

Exact source evidence cannot be delivered twice. `eventKey` and `knowledgeDelta` distinguish a new event from context, a material update, or a contradiction. Long-form LinkedIn snapshots that later reveal a stable native identity are reconciled before reasoning. On startup, completed Go-schema sessions are idempotently recomposed so the global-order invariant also holds for retained development rows created before this authority change.

Full reset is backup-first and idle-only. The health endpoint reports database health but never exposes the absolute database path. Operational diagnosis belongs in the compact Update Inbox and component-native tests.

## Trust boundary

All HTTP listeners remain loopback-only. Bridge routes require the durable Bridge token and exact `aku-browser.bridge.v2` header. Captured source content is untrusted input. Reasoning is read-only, approvals are disabled, structured output is mandatory, and the provider cannot directly navigate, expand the capture budget, or select Timeline items.

Capture degradation is explicit. Missing primary media may yield a usable-degraded item and an Open native post escape hatch; missing evidence is never fabricated. AkuBridge never performs social writes.

## Configuration

`AkuSidecar/config/sidecar.json` is strict. The fresh preference mode is `guarded_live`; the default reasoning provider is `codex-app-server`. Product Settings remain typed in SQLite and expose source selection, bounded load profile or Custom values, Timeline capacity, capture behavior, personalization mode, calibration, presentation, and stream width.

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
