# AkuBrowser Windows Preview

This portable preview contains the Go AkuSidecar runtime and AkuBridge as an
unpacked Chrome extension. It also includes the pinned `c2patool.exe` runtime
used for local, image-only Content Credentials verification. It does not
install a Windows service and does not include AkuSupervisor.

## OpenAI Build Week preview

This is the judge-ready package for the AkuBrowser Build Week story. It
demonstrates bounded capture from authenticated X, Facebook, and LinkedIn
feeds; Codex-backed Acquisition Planning, Candidate Evaluation, Semantic Event
Resolution, and AI Deep Detection; deterministic preference filtering; and a
finite, source-backed Timeline. AkuSupervisor remains optional development
tooling and is intentionally excluded from this preview.

## Prerequisites

- Windows 10 or newer on x64 hardware;
- Codex App installed and locally signed in, or a Codex CLI build that includes
  App Server;
- Google Chrome already signed in to every source you enable (X, LinkedIn, or Facebook);
- if antivirus protection causes a problem during installation or onboarding,
  follow the narrow-exception guidance below before trying again.

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
`http://127.0.0.1:11122` after Sidecar becomes healthy; `http://localhost:11122`
is also supported. Reload AkuBridge and refresh the page after switching
between the two origins.
User data is stored under `%LOCALAPPDATA%\AkuBrowser\data` and is not removed
when the extracted bundle is replaced.

## Antivirus warning

The current testing installer and native runtime are not code-signed yet.
Windows Security, Avast, or another antivirus may warn, quarantine, block, or
sandbox them. Verify that the download came from the official AkuBrowser GitHub
release before allowing it. Do not disable antivirus protection or exclude your
Downloads folder.

For the installed runtime, add a narrow exception for
`%LOCALAPPDATA%\Programs\AkuBrowser\`. For this portable ZIP, restore
`AkuSidecar.exe` first if it was quarantined, then add an exception for that exact file
in the extracted AkuBrowser directory. Moving or extracting the
portable bundle to another directory may require a new exception for the new
path.

If installation or **Update now** fails with `Access is denied`, the security
software may have sandboxed AkuSidecar even though the runtime health check
passed. After adding the exception, stop the running `AkuSidecar.exe`. Installed
runtime users should return to the extension Setup page and select
**Check installation** before trying again. Portable users should run
`Start-AkuBrowser.ps1` again. Do not delete `%USERPROFILE%\.codex` or its SQLite
files to resolve this error.

When automatic setup or a Windows-security-blocked update fails, AkuBrowser
offers **Download manual Windows bundle**. The button opens the matching
versioned `AkuBrowser-<version>-windows-x64.zip` asset on the official GitHub
release. Verify the adjacent `.sha256` asset, extract the ZIP to a writable
folder, add an antivirus exception only for the extracted `AkuSidecar.exe` if
needed, and run `Start-AkuBrowser.ps1`.

The portable bundle is a fallback, not a second concurrent installation. Stop
the installed or older portable `AkuSidecar.exe` before starting it. It does not
replace the registered Native Messaging Host and must be started manually again
after Windows restarts.

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
The release manifest additionally pins the bundled c2patool version and
SHA-256, while `artifact-manifest.json` records the exact tool included in this
build. Exact upstream MIT and Apache-2.0 license texts and the third-party
notice are included under `third-party/c2patool`.
