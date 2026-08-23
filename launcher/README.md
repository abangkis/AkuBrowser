# AkuBrowserLauncher Windows vertical slice

This module is the installed-app lifecycle entry point defined by
`../docs/installed-app-distribution-contract.md`. The first slice:

- strictly resolves `runtime/current.json` and the selected version manifest;
- rejects path escape, reparse/symlink payloads, undeclared files, and
  size/SHA-256 mismatches before starting a process;
- enforces the distinct `production-app` Bridge identity;
- keeps SQLite data and the pinned-Chromium profile under `%LOCALAPPDATA%`;
- owns one installed-app instance, starts AkuSidecar with exact app-shell paths,
  waits for matching health, and uses its scoped idle-shutdown API.

The manifest is not yet a standalone signed update envelope. In this slice its
trust comes from a verified, signed installer boundary. Installer integration,
signed update discovery, atomic activation, repair, and rollback remain later
phases.

Run focused tests:

```powershell
Set-Location launcher
go test ./...
```

Build the Windows executable:

```powershell
Set-Location launcher
go build -trimpath -o AkuBrowserLauncher.exe ./cmd/AkuBrowserLauncher
```

Use `--verify-only --install-root <path>` to validate a staged fixture without
starting Sidecar or Chromium.
