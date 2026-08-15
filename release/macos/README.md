# AkuBrowser macOS portable bundle

This self-contained offline bundle contains AkuBridge and the native Go
`AkuSidecar` runtime. Its unpacked AkuBridge uses a dedicated, stable
offline-production identity and does not require Chrome Web Store installation.
It does not include `AkuSupervisor`.

Do not run the offline and Chrome Web Store editions together. Their extension
identities and trusted runtime configurations are intentionally different.

## Prerequisites

- macOS on Intel or Apple silicon; the universal bundle contains native x64 and
  arm64 Sidecar slices;
- Codex App with App Server available and locally signed in, or a compatible Codex CLI;
- Google Chrome already signed in to every source you enable (X, LinkedIn, Facebook, or Instagram).

## Install and start

1. Extract the ZIP to a writable directory.
2. In Chrome, open `chrome://extensions`, enable **Developer mode**, select
   **Load unpacked**, and choose the included `AkuBridge` directory.
3. Verify the offline extension ID against `artifact-manifest.json`.
4. Start AkuBrowser from Terminal:

   ```sh
   ./Start-AkuBrowser.sh
   ```

   You can also double-click `Start-AkuBrowser.command` in Finder. Keep the
   terminal open while using AkuBrowser; Ctrl+C stops the Sidecar cleanly.

Load the bundled offline extension before starting the portable runtime. For
Chrome Web Store production, use the Store extension and installed companion
runtime. For workspace development, use the named `development` identity.

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
