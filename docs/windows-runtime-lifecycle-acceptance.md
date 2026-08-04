# Windows runtime lifecycle acceptance

Status: Stage 5 implementation, 28 July 2026.

## Automated boundary

Run:

```powershell
.\scripts\test-windows-runtime-lifecycle.ps1
```

The automated suite covers the complete lifecycle contract without modifying
the current user's Chrome profile, registry, or AkuBrowser data:

- Store first-install missing-host projection;
- Chrome/PC startup and extension-update action planning;
- stopped or crashed Sidecar restart and retry;
- separation of release updates from Bridge-contract compatibility;
- no downgrade of a newer contract-compatible runtime;
- version-tolerant installed-runtime shutdown through the private control token;
- portable-runtime manual-stop guidance without installed-host authority;
- interrupted installer staging with the old `current.json` preserved;
- an unactivated failed-candidate directory having no process authority;
- idempotent repair;
- uninstall and reinstall with durable data preserved;
- Store package closure and absence of unpacked native executables.

The failed-candidate test remains an authority-isolation acceptance test.
Network download, signed-manifest verification, candidate health gating,
atomic activation, and executable rollback are implemented and tested by the
Stage 7 suite in `scripts/test-windows-runtime-updater.ps1`.

## Clean Windows machine

Use a disposable Windows 11 x64 VM with no existing AkuBrowser installation.
The VM test requires the real Chrome Web Store extension ID and the production
Authenticode-signed `AkuBrowserRuntimeSetup.exe`. An unsigned local candidate is
not accepted.

For every checkpoint, record the state shown on the bundled setup page and run
the read-only verifier with that state:

```powershell
.\scripts\test-windows-runtime-lifecycle.ps1 `
  -Scenario first_install `
  -ExtensionId "<store-extension-id>" `
  -InstallerPath ".\AkuBrowserRuntimeSetup.exe" `
  -ObservedState runtime_install_required
```

After running the installer and clicking **Periksa lagi**, use `reinstalled` as
the first ready checkpoint. Then execute these checkpoints after the named
user action:

1. `chrome_restart` after fully closing and reopening Chrome.
2. `pc_restart` after restarting Windows and opening Chrome.
3. `sidecar_recovery` after terminating only `AkuSidecar.exe`, then reopening
   AkuBrowser from the extension action.
4. `extension_update` after a Store update test.
5. `runtime_repair` after Windows Installed Apps **Modify/Repair**.
6. `uninstalled` after uninstalling the companion runtime.
7. `reinstalled` after installing it again.

Ready checkpoints require `-ObservedState runtime_ready`; the uninstall
checkpoint requires `runtime_install_required`. Add `-EvidencePath` to write a
bounded JSON receipt. The receipt contains no registry paths, usernames,
database contents, browser history, credentials, or social content.

Before uninstall, place a harmless marker file under
`%LOCALAPPDATA%\AkuBrowser\data` and pass its exact path as `-DataMarkerPath` to
both the `uninstalled` and `reinstalled` checkpoints. The verifier records only
its SHA-256, proving the same data survived without reading it into the receipt.

At the end, confirm:

- Chrome Developer Mode was never enabled;
- no unpacked extension was loaded;
- no terminal was used for the end-user install/restart/repair flow;
- `%LOCALAPPDATA%\AkuBrowser\data` retained its pre-uninstall marker or real
  database;
- every failure shown by setup was a typed recoverable state.

## Current execution boundary

Automated acceptance can run before Store submission. Clean-machine execution
cannot be claimed until the production Store ID and signed installer exist.
Stage 5 is therefore code-complete when the automated suite passes and this
runner is ready; its production clean-machine evidence remains a release gate.
