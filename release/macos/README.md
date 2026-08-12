# AkuBrowser macOS portable bundle

This portable bundle contains the native Go `AkuSidecar` runtime and works with
the published AkuBrowser extension from the Chrome Web Store. It does not
include `AkuSupervisor`.

The included `AkuBridge` directory is retained for source inspection and
advanced troubleshooting. Do not load it unpacked alongside the Chrome Web
Store extension: the production runtime accepts only the published extension's
exact identity.

## Prerequisites

- macOS on Intel or Apple silicon; the universal bundle contains native x64 and
  arm64 Sidecar slices;
- Codex App with App Server available and locally signed in, or a compatible Codex CLI;
- Google Chrome already signed in to every source you enable (X, LinkedIn, Facebook, or Instagram).

## Install and start

1. Install **AkuBrowser** from the Chrome Web Store:
   <https://chromewebstore.google.com/detail/akubrowser/phkaipecbhpgopggbfpcejgngbhddnkk>
2. Extract the ZIP to a writable directory.
3. Start AkuBrowser from Terminal:

   ```sh
   ./Start-AkuBrowser.sh
   ```

   You can also double-click `Start-AkuBrowser.command` in Finder. Keep the
   terminal open while using AkuBrowser; Ctrl+C stops the Sidecar cleanly.

Install the Chrome Web Store extension before starting the portable runtime so
the capture bridge is available when onboarding begins. For local
unpacked-extension development, use the AkuWorkspace development flow and its
named `development` Bridge identity rather than this production bundle.

User data is stored under `~/Library/Application Support/AkuBrowser/data` and
survives replacement of the extracted bundle.

The launcher opens the canonical `http://127.0.0.1:11122` origin. You may also
use `http://localhost:11122`; refresh the AkuBrowser tab after switching between
the two origins.

The launcher checks `AKU_CODEX_PATH`, the standard `Codex.app` and
`ChatGPT.app` locations, the Codex-managed runtime directory, and common CLI
locations. It accepts a candidate only after the App Server capability probe
succeeds. To inspect discovery without starting:

```sh
./Start-AkuBrowser.sh --diagnose-codex
```

For a custom installation:

```sh
./Start-AkuBrowser.sh --codex-path "/path/to/codex"
```

The `--provider deterministic` override is reserved for local smoke tests and
does not provide model-backed reasoning.

## Verify the download

`checksums.sha256` contains a SHA-256 digest for every bundled file. The ZIP is
published with a separate `.sha256` file for download-level verification.

Unsigned local preview binaries may trigger a Gatekeeper warning. Do not
disable Gatekeeper globally; use the macOS security prompt or remove the
quarantine attribute only after verifying the downloaded checksum.
