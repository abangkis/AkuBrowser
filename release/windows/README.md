# AkuBrowser Windows Preview

This portable preview contains the Go AkuSidecar runtime and AkuBridge as an
unpacked Chrome extension. It does not install a Windows service and does not
include AkuSupervisor.

## Prerequisites

- Windows 10 or newer on x64 hardware;
- Codex App installed and locally signed in, or a Codex CLI build that includes
  App Server;
- Google Chrome already signed in to every source you enable (X, LinkedIn, or Facebook).

## Start AkuBrowser

1. Extract the complete ZIP to a writable directory.
2. Run `Start-AkuBrowser.cmd`.
3. Keep its terminal open while using AkuBrowser.
4. Press Ctrl+C in that terminal to stop AkuBrowser.

The launcher opens `http://127.0.0.1:11122` after Sidecar becomes healthy.
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

## Install AkuBridge manually

1. Open `chrome://extensions`.
2. Enable **Developer mode**.
3. Choose **Load unpacked**.
4. Select the `AkuBridge` directory inside this bundle.
5. Return to AkuBrowser and confirm that AkuBridge is ready.

The extension must stay at that extracted path. Moving or deleting the folder
will make Chrome unable to reload it.

## Verify the download

`checksums.sha256` contains a SHA-256 digest for every bundled file. The ZIP is
published with a separate `.sha256` file for download-level verification.
