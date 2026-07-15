# AkuSidecar Go Development Runbook

> Last verified: **2026-07-15**
> Active baseline: **AkuSidecar 1.0.0-dev.4, AkuBridge 0.6.0 / source-fidelity-v47, bridge v2**

## Runtime boundary

AkuSidecar is now an in-place Go rewrite. The Node/npm/Vite runtime and its
SQLite migrations ended at `pre-refactor-2026-07-15`; they are not fallback
paths. The current process embeds the UI, owns one fresh fifteen-table SQLite
schema, and uses a strict JSON configuration without legacy environment aliases.

The default reasoning transport is `codex-app-server`: Go owns one official
`codex.exe app-server` process, creates ephemeral read-only threads, sends each
output schema at turn start, and consumes structured notifications plus token
usage. `codex-exec` remains an explicit process-per-request conformance option.

## Required files

The native Codex distribution is local-only and must exist at:

```text
C:\WorkspaceCodex\AkuWorkspace\AkuSidecar\runtime\codex-cli\bin\codex.exe
C:\WorkspaceCodex\AkuWorkspace\AkuSidecar\runtime\codex-cli\codex-path\
C:\WorkspaceCodex\AkuWorkspace\AkuSidecar\runtime\codex-cli\codex-resources\
```

The binary and runtime directory are ignored by Git.

## Preferred startup

AkuSupervisor remains the visible lifecycle owner. Its checked-in profile
starts `runtime\dev\aku-sidecar.exe` directly with the strict configuration and
`--dev`. No component-level watcher or hidden replacement process remains.

```powershell
cd C:\WorkspaceCodex\AkuWorkspace\AkuSidecar
.\scripts\restart-dev.ps1
```

The explicit command builds `aku-sidecar.next.exe` first. It refuses to
interrupt an active session, asks AkuSupervisor to stop the registered service,
promotes the candidate to `aku-sidecar.exe`, and asks AkuSupervisor to start it
again. `npm run dev` from AkuBrowser invokes the same workflow.

The exact operational rule is:

- while the Supervisor watcher is active, its development binary is the owner;
- promoting AkuSupervisor stable is required only after a newer Supervisor
  development build exists;
- promotion happens while the watcher and required services remain live;
- stop the watcher only after promotion, then start
  `target\aku-supervisor.exe` for stable operation.

Direct component startup is reserved for isolated diagnostics:

```powershell
cd C:\WorkspaceCodex\AkuWorkspace\AkuSidecar
.\scripts\build-dev.ps1
.\runtime\dev\aku-sidecar.exe --config .\config\sidecar.json --dev
```

## Verification

1. Confirm Supervisor owns the service:

   ```powershell
   .\target\dev\aku-supervisor.exe status --json
   ```

2. Confirm the fresh Go boundary:

   ```powershell
   Invoke-RestMethod http://127.0.0.1:47821/api/health
   ```

   Required values are `status=ok`, `version=1.0.0-dev.4`, `runtime=go`,
   `provider=codex-app-server`, and
   `bridgeContractVersion=aku-browser.bridge.v2`.

3. Confirm `/api/bridge/health` reports `state=healthy`, `compatible=true`,
   extension `0.6.0`, and runtime revision `source-fidelity-v47` before starting
   a session.

4. Run one X + LinkedIn session. Success requires two persisted child runs,
   structured reasoning output, finite Timeline items, and token telemetry.

5. On a fresh database, completing source onboarding must start that session
   automatically. A completed or partial session must then open the forced
   calibration lane; the Timeline is available only after every sample has a
   More, Neutral, Less, or capture-issue decision.

6. After AkuBridge source changes, use cooperative reload and validate the
   exact expected build. Do not use the v1 protocol as a transition path.

## Failure boundaries

- HTTP health without a successful Codex invocation proves only process and
  database readiness.
- A missing Codex executable is a provider configuration failure, not a reason
  to reintroduce the SDK or Node runtime.
- A schema mismatch means the development database belongs to another fresh
  boundary; remove it and let the current schema initialize.
- A Bridge v1 or stale v46 heartbeat is incompatible by design.
