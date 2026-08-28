# AkuBrowser Windows distribution — v0.9.0

> **Active release path:** v0.9.0 is a Windows x64 stable release delivered
> through one intentionally unsigned installed-app installer `.exe` plus its
> SHA-256 checksum. Chrome Web Store publication is frozen;
> macOS and Linux are deferred.

## Active v0.9.0 release

The installer bundles AkuBrowserLauncher, AkuSidecar, the internal
`production-app` AkuBridge payload, pinned Chromium, c2patool, configuration,
and checksums in one tuple. It does not require system Chrome, Developer Mode,
manual extension loading, or a separate runtime installer. Codex App/App Server
is an external prerequisite. The optional Gemini provider uses a user-supplied
key through the Sidecar credential flow. The candidate covers X, LinkedIn,
Facebook, and opt-in Instagram adapters, provider hot-swap at an idle boundary,
and schema 10.

Use only the installer and checksum supplied by the v0.9.0 release evidence.
The installer is intentionally unsigned and may trigger SmartScreen or
antivirus warnings; verify the checksum before running it. Code signing and
independent clean-machine certification remain future hardening.

Follow [Windows clean-machine Step 3B](../../docs/windows-clean-machine-3b.md)
for the pending install, launch, source, provider, migration, repair,
update/rollback, uninstall, and full-reset acceptance.

## Historical portable recovery bundle

The content below describes the pre-v0.9.0 self-contained offline ZIP. It is
retained for recovery and reproducibility, not as an active v0.9.0 distribution
path.

This self-contained offline bundle contains AkuBridge, the Go AkuSidecar
runtime, and the pinned `c2patool.exe` runtime used for local, image-only
Content Credentials verification. Its unpacked AkuBridge has a dedicated,
stable offline-production identity. It does not depend on Chrome Web Store
installation, install a Windows service, or include AkuSupervisor.

Do not run the historical offline and Chrome Web Store editions together. Their
extension identities and trusted runtime configurations are intentionally
different.

## What it demonstrates

AkuBrowser provides bounded capture from authenticated X, Facebook, and
LinkedIn feeds; Codex-backed Acquisition Planning, Candidate Evaluation,
Semantic Event Resolution, and AI Deep Detection; deterministic preference
filtering; and a finite, source-backed Timeline. AkuSupervisor remains optional
development tooling and is intentionally excluded from this bundle.

## Prerequisites

- Windows 10 or newer on x64 hardware;
- Codex App installed and locally signed in, or a Codex CLI build that includes
  App Server;
- Google Chrome already signed in to every source you enable (X, LinkedIn, Facebook, or Instagram);
- if antivirus protection causes a problem during installation or onboarding,
  follow the narrow-exception guidance below before trying again.

## Install and start

1. Extract the complete ZIP to a writable directory.
2. In Chrome, open `chrome://extensions`, enable **Developer mode**, select
   **Load unpacked**, and choose the included `AkuBridge` directory.
3. Verify that Chrome shows the offline extension ID documented in
   `artifact-manifest.json`.
4. Open PowerShell in the extracted directory and run:

   ```powershell
   .\Start-AkuBrowser.ps1
   ```

5. If running PowerShell scripts is unavailable, use `Start-AkuBrowser.cmd` as
   the fallback launcher.
6. Keep its terminal open while using AkuBrowser.
7. Press Ctrl+C in that terminal to stop AkuBrowser.

Load the bundled offline extension before starting the portable runtime. For
Chrome Web Store production, use the Store extension and installed companion
runtime instead. For workspace development, use the named `development`
identity rather than this production bundle.

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

Avast CyberCapture can open an isolated second copy of the unsigned installer,
including a second Setup window that appears after the first installation has
finished. Complete only the first Setup window. If another Setup window appears,
select **No** or **Cancel** and close it; do not run **Repair** twice. Before
adding an exception, verify the installer against the SHA-256 published beside
the official release asset. If the duplicate behavior continues, add an Avast
exception only for that exact verified installer file, not the Downloads folder.

For the installed runtime, add a narrow exception for
`%LOCALAPPDATA%\Programs\AkuBrowser\`. For this portable ZIP, restore
`AkuSidecar.exe` first if it was quarantined, then add an exception for that exact file
in the extracted AkuBrowser directory. Moving or extracting the
portable bundle to another directory may require a new exception for the new
path.

If installation or **Update now** fails with `Access is denied`, the security
software may have sandboxed AkuSidecar even though the runtime health check
passed. After adding the exception, stop the running `AkuSidecar.exe`. Installed
runtime users should return to the extension Setup page and select the available
**Update runtime**, **Run AkuBrowser**, or **Try again** action. Portable users
should run `Start-AkuBrowser.ps1` again. Do not delete `%USERPROFILE%\.codex` or
its SQLite files to resolve this error.

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
