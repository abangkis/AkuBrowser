# AkuBrowserLauncher Windows vertical slice

This module is the installed-app lifecycle entry point defined by
`../docs/installed-app-distribution-contract.md`. The first slice:

- strictly resolves `runtime/current.json` and the selected version manifest;
- rejects path escape, reparse/symlink payloads, undeclared files, and
  size/SHA-256 mismatches before starting a process;
- enforces the distinct `production-app` Bridge identity;
- keeps SQLite data and the pinned-Chromium profile under `%LOCALAPPDATA%`;
- owns one installed-app instance, starts AkuSidecar with exact app-shell paths,
  waits for matching health, and uses its scoped idle-shutdown API;
- owns the stable Windows application identity used for taskbar grouping,
  pinning, icon lookup, and relaunch instead of allowing the Chromium process
  identity to leak into the installed shortcut.

Development app-shell windows use the separate
`AI4U.AkuBrowser.Development` identity. Their relaunch command calls the same
launcher with `--development-workspace <root>`, and the launcher delegates the
actual lifecycle operation to the existing generic Supervisor command:

```powershell
.\AkuBrowserLauncher.exe --development-workspace C:\WorkspaceCodex\AkuWorkspace
```

The installed identity is `AI4U.AkuBrowser`; its relaunch command uses the
verified installed tuple instead of AkuSupervisor.

The manifest is not yet a standalone signed update envelope. The staged NSIS
lane validates the tuple before compilation and writes `current.json` last, but
its current artifact is explicitly unsigned and not shipped. Production
signing, clean-machine launch acceptance, atomic same-version repair, signed
update discovery, and rollback remain later phases.

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

After changing an existing taskbar identity, unpin the old Chrome-backed item
and pin the running AkuBrowser window once. Windows then persists the new
AkuBrowser relaunch tuple and icon resource.

Use `--verify-only --install-root <path>` to validate a staged fixture without
starting Sidecar or Chromium.
