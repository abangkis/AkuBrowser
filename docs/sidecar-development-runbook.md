# AkuSidecar Development Runbook

> Last verified: **2026-07-15**

## Required startup boundary

AkuSidecar uses the Codex SDK provider, which launches Codex CLI during candidate evaluation and acquisition planning. The Sidecar must therefore run in a normal host process context with permission to create child processes.

Do not start the long-lived development server through an ordinary sandboxed command runner. That process may still:

- bind `127.0.0.1:47821`;
- serve `/api/health` successfully;
- receive AkuBridge captures; and
- write runs to SQLite;

but fail as soon as reasoning begins with:

```text
spawn EPERM
```

HTTP health alone is not proof that the reasoning provider can execute.

## Preferred startup

AkuSupervisor is the preferred lifecycle owner. It starts AkuSidecar in the
normal user host context, records the complete npm/server process tree,
monitors `/api/health`, and provides bounded restart and logs without taking
over the user's browser.

For active AkuSupervisor development, start the visible watcher and request the
registered Sidecar service:

```powershell
cd C:\WorkspaceCodex\AkuWorkspace\AkuSupervisor
.\scripts\dev.ps1 akusidecar
```

For the stable Supervisor, start `target\aku-supervisor.exe` visibly and use a
second terminal for lifecycle requests:

```powershell
.\target\aku-supervisor.exe start akusidecar `
  --reason "start AkuBrowser development runtime"
```

The checked-in Supervisor profile runs `npm run dev` from AkuSidecar with an
empty environment map. Configure provider, models, efforts, policy, timeout,
and source behavior through AkuBrowser Settings. Do not set
`AKU_REASONING_PROVIDER` for normal startup.

`npm run dev` mounts Vite middleware and HMR but deliberately does not run
Node's file watcher. Codex SDK evaluation occurs inside a persisted active run;
filesystem activity from that child process must not restart AkuSidecar during
reasoning. Frontend changes hot-reload. Backend changes require an explicit
AkuSupervisor restart, which preserves the database and lets the engine resume
the persisted run.

Direct `npm run dev` remains a component-isolation fallback when AkuSupervisor
is intentionally unavailable. It must still run in a visible, normal host
terminal:

```powershell
cd C:\WorkspaceCodex\AkuWorkspace\AkuSidecar
npm run dev
```

Do not replace AkuSupervisor with a hidden detached `Start-Process` launch. It
loses the visible ownership, health, audit, restart, and full-tree cleanup
guarantees that now exist.

## Verification checklist

1. Verify Supervisor ownership and health from a second terminal:

   ```powershell
   cd C:\WorkspaceCodex\AkuWorkspace\AkuSupervisor
   .\target\dev\aku-supervisor.exe status --json
   ```

   Use `target\aku-supervisor.exe` instead when running the promoted stable
   binary. MCP may inspect the same service read-only through
   `supervisor_get_service`.

2. Verify HTTP health and the intended provider:

   ```powershell
   (Invoke-WebRequest -UseBasicParsing http://127.0.0.1:47821/api/health).Content
   ```

   Expected provider: `codex-sdk`.

3. Verify SQLite integrity:

   ```powershell
   npm run db:health
   ```

4. Run or observe one bounded update. Do not declare startup successful until the newest `reasoning_invocations` row advances beyond immediate `spawn EPERM` failure. A healthy provider invocation takes materially longer than a 3-10 ms spawn failure and ultimately records token usage or a provider-level error.

5. If the server was restarted while a Chrome tab was open, confirm `/api/health`
   returns a new `instanceEpoch` and the existing tab automatically returns to
   both `AkuSidecar ready` and `AkuBridge ready`. Ordinary API polling carries
   the epoch header, so a completed onboarding tab should re-handshake without
   a manual reload. Check for updates performs one additional bounded handshake
   before creating work. When AkuBridge source changed, use
   `aku-supervisor bridge validate` rather than Chrome control after the
   one-time extension bootstrap.

## Recovery from `spawn EPERM`

1. Restart the registered `akusidecar` service through AkuSupervisor so the
   complete npm/server process tree is replaced and audited.
2. Keep the database unless a clean onboarding experiment was explicitly requested. Failed runs are useful diagnostics.
3. Confirm Supervisor reports the complete owned PID tree and healthy transport.
4. Verify port, health, provider, and one real reasoning invocation.
5. Retry `Check for updates`. Do not reload or reinstall AkuBridge for this error: capture already succeeded, and the failure is in the Sidecar-to-Codex process boundary.

## Proven incident

During the first source-only onboarding and forced-calibration pilot, two
Unified Sessions captured X and LinkedIn successfully but both sources failed
in candidate evaluation with `spawn EPERM`. The server had been launched
through a sandboxed long-running command. A normal-host launch fixed the
incident. AkuSupervisor now provides that host-context lifecycle boundary and
is the preferred durable solution.
