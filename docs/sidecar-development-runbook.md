# AkuSidecar Development Runbook

> Last verified: **2026-07-12**

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

For an operator-visible terminal:

```powershell
cd C:\WorkspaceCodex\AkuWorkspace\AkuSidecar
npm run dev
```

When Codex is explicitly responsible for maintaining the server, start `npm run dev` outside its filesystem/process sandbox as a detached host process. Report the launcher PID, listener PID, port, and every stop or restart to the user.

Example detached launch:

```powershell
$process = Start-Process `
  -FilePath 'C:\nvm4w\nodejs\npm.cmd' `
  -ArgumentList 'run', 'dev' `
  -WorkingDirectory 'C:\WorkspaceCodex\AkuWorkspace\AkuSidecar' `
  -WindowStyle Hidden `
  -PassThru
$process.Id
```

This hidden form is allowed only when the user has delegated server lifecycle management and has been told that it is running in the background. Otherwise use the visible terminal form.

## Verification checklist

1. Verify the listener:

   ```powershell
   netstat -ano | Select-String ':47821.*LISTENING'
   ```

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

5. If the server was restarted while a Chrome tab was open, confirm the tab reports both `AkuSidecar ready` and `AkuBridge ready` before starting a run.

## Recovery from `spawn EPERM`

1. Stop the entire AkuSidecar process tree, not only `src/server.mjs`; otherwise the Node watcher may immediately recreate the restricted child.
2. Keep the database unless a clean onboarding experiment was explicitly requested. Failed runs are useful diagnostics.
3. Start the server again from a normal host process context using one of the preferred startup forms.
4. Verify port, health, provider, and one real reasoning invocation.
5. Retry `Check for updates`. Do not reload or reinstall AkuBridge for this error: capture already succeeded, and the failure is in the Sidecar-to-Codex process boundary.

## Proven incident

During the first source-only onboarding and forced-calibration pilot, two Unified Sessions captured X and LinkedIn successfully but both sources failed in candidate evaluation with `spawn EPERM`. The server had been launched through a sandboxed long-running command. Replacing it with a detached normal host process fixed the issue: X and LinkedIn completed, and Calibration Engine created a nine-entry batch.
