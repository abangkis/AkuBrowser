# AkuBrowserLauncher Windows app shell — v0.9.0

Status: stable-release documentation. The v0.9.0 Windows x64 installer is
intentionally unsigned; independent clean-machine certification remains future
hardening. The old Store/portable launch paths are historical only.

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

The release tuple is one installed Windows application: the launcher starts the
bundled AkuSidecar and pinned Chromium with the internal `production-app`
AkuBridge payload. It does not use system Chrome, Chrome Web Store installation,
Developer Mode, or a separately installed companion runtime. AkuSupervisor is
development-only. macOS and Linux are deferred from v0.9.0.

Development app-shell windows use the separate
`AI4U.AkuBrowser.Development` identity. Their relaunch command calls the same
launcher with `--development-workspace <root>`, and the launcher delegates the
actual lifecycle operation to the existing generic Supervisor command:

```powershell
.\AkuBrowserLauncher.exe --development-workspace C:\WorkspaceCodex\AkuWorkspace
```

The installed identity is `AI4U.AkuBrowser`; its relaunch command uses the
verified installed tuple instead of AkuSupervisor.

The manifest is not yet a standalone signed update envelope. The NSIS
lane validates the tuple before compilation and writes `current.json` last, but
the v0.9.0 release remains explicitly unsigned. Do not silence
SmartScreen/antivirus warnings; verify the published SHA-256. Atomic
same-version repair, signed update discovery, and rollback remain future work.

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

Historical installations may retain a Chrome-backed taskbar item; unpin that
old item once and pin the running AkuBrowser window if needed. v0.9.0 uses the
stable `AI4U.AkuBrowser` application identity and its launcher relaunch tuple.

Use `--verify-only --install-root <path>` to validate a staged fixture without
starting Sidecar or Chromium.
