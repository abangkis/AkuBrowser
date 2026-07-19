# AkuBrowser Windows Preview

This portable preview contains the Go AkuSidecar runtime and AkuBridge as an
unpacked Chrome extension. It does not install a Windows service and does not
include AkuSupervisor.

## Prerequisites

- Windows 10 or newer on x64 hardware;
- Codex App installed and locally signed in, or a Codex CLI build that includes
  App Server;
- Google Chrome already signed in to every source you enable (X, LinkedIn, or Facebook).

## Install and start

1. Extract the complete ZIP to a writable directory.
2. Open `chrome://extensions` in Google Chrome.
3. Enable **Developer mode**.
4. Choose **Load unpacked**.
5. Select the `AkuBridge` directory inside this bundle.
6. Confirm that AkuBridge is enabled.
7. Open PowerShell in the extracted directory and run:

   ```powershell
   .\Start-AkuBrowser.ps1
   ```

8. If running PowerShell scripts is unavailable, use `Start-AkuBrowser.cmd` as
   the fallback launcher.
9. Keep its terminal open while using AkuBrowser.
10. Press Ctrl+C in that terminal to stop AkuBrowser.

Install AkuBridge before starting AkuBrowser. This ensures the capture bridge is
available when onboarding begins instead of launching a partially working
system. The extension must stay at the extracted path; moving or deleting that
directory will make Chrome unable to reload it.

`Start-AkuBrowser.ps1` is the primary launcher and exposes the diagnostic and
configuration options documented below. `Start-AkuBrowser.cmd` delegates to the
same script and is retained only as a convenience fallback. The launcher opens
`http://127.0.0.1:11122` after Sidecar becomes healthy.
User data is stored under `%LOCALAPPDATA%\AkuBrowser\data` and is not removed
when the extracted bundle is replaced.

The launcher automatically checks `AKU_CODEX_PATH`, `PATH`, managed Codex App
runtime folders, Windows App aliases, and common npm CLI locations. It accepts a
candidate only after `codex app-server --help` confirms the required capability.
Inspect the result without starting AkuBrowser:

```powershell
.\Start-AkuBrowser.ps1 -DiagnoseCodex
```

If automatic discovery still cannot find a custom installation, launch
explicitly:

```powershell
.\Start-AkuBrowser.ps1 -CodexPath "C:\path\to\codex.exe"
```

Login assistance remains outside this preview. Discovery reports the locations
it checked and links to the Codex setup guide without collecting credentials.

## Verify the download

`checksums.sha256` contains a SHA-256 digest for every bundled file. The ZIP is
published with a separate `.sha256` file for download-level verification.
