# macOS preview acceptance

AkuBrowser owns the macOS distribution boundary across the component
repositories; AkuSupervisor and AkuSupervisorConformance are not packaged.
The `v0.7.9-preview1` target contains one `macos-universal` ZIP and one
explicitly unsigned universal user-scoped `.pkg`, each carrying x64 and arm64
Sidecar slices for Intel and Apple-silicon Macs.

## Automated artifact gate

Run on a Mac from the AkuBrowser repository:

```sh
./scripts/build-macos-preview.sh --architecture universal
./scripts/test-macos-preview.sh --zip artifacts/AkuBrowser-0.7.9-macos-universal.zip
```

Without an explicit target, the builder matches the host architecture. Use
`--architecture x64` or `--architecture arm64` for focused native testing;
`--architecture universal` reproduces the published combined artifact. A
publishable build requires clean AkuBrowser, AkuSidecar, and AkuBridge source trees;
`--allow-dirty` is only for local pipeline development.

The build gate verifies the release tuple, runs AkuSidecar Go tests and
AkuBridge JavaScript checks, builds a native Go Sidecar, copies only the
verified unpacked extension payload, records source commits, generates
per-file SHA-256 checksums, and creates the portable ZIP. The smoke gate
revalidates every bundled checksum, launcher and Sidecar executable bits,
starts the bundle with a temporary database, checks Sidecar health through
both `127.0.0.1` and `localhost`, verifies fresh defaults, and loads the
embedded UI.

To test an already extracted bundle or downloaded ZIP:

```sh
./scripts/test-macos-preview.sh --artifact-directory /path/to/extracted-bundle
./scripts/test-macos-preview.sh --zip /path/to/AkuBrowser-0.7.9-macos-universal.zip
```

## Clean-machine manual gate

Test Intel and Apple-silicon artifacts on matching hardware. Before publishing:

1. start from a macOS user account with no AkuBrowser database;
2. confirm Codex App/App Server or a compatible Codex CLI is installed and
   locally signed in;
3. confirm Chrome is signed in to each source that will be enabled;
4. verify the downloaded ZIP against its adjacent `.sha256` file;
5. extract the ZIP to a writable directory;
6. install the bundled `AkuBridge` first through `chrome://extensions` using
   **Developer mode** and **Load unpacked**;
7. run `./Start-AkuBrowser.sh --diagnose-codex` and confirm a compatible App
   Server runtime is found;
8. run `./Start-AkuBrowser.sh`, or double-click `Start-AkuBrowser.command`, and
   keep the terminal open;
9. complete onboarding and calibration, run **Update now** directly or load a prepared batch, provide
   More/Less feedback, and inspect Update Inbox and Settings;
10. stop AkuBrowser with Ctrl+C and confirm it exits cleanly;
11. restart the same extracted bundle and confirm state is retained under
    `~/Library/Application Support/AkuBrowser/data`; and
12. confirm no AkuSupervisor process or development workspace path is required.

Unsigned preview binaries may trigger Gatekeeper. Do not disable Gatekeeper
globally. Use the macOS security prompt, or remove quarantine only after the
ZIP checksum has been verified.

## Acceptance boundary

The preview provides a portable ZIP plus an explicitly unsigned and not
notarized user-scoped `.pkg`. Automatic AkuBridge installation, guided Codex
installation or login recovery, automatic updates, Linux packaging, and a
bundled cross-platform Supervisor remain outside the `v0.7.9-preview1`
acceptance boundary.

## 0.7.9 Chrome Web Store companion gate

The portable checks above remain the fallback boundary. Publishing the 0.7.9
macOS Store path additionally requires clean Intel and Apple-silicon evidence
for:

1. first Store install projecting `runtime_install_required`;
2. the fixed `.pkg` download opening only after a user click;
3. the Installer page and Setup both disclose that this preview package is
   unsigned and not notarized, identify the official GitHub source, require
   SHA-256 verification, and never recommend disabling Gatekeeper;
4. a Gatekeeper-blocked first open can be recovered through the per-app
   **Privacy & Security > Open Anyway** flow;
5. current-user Native Messaging registration with one exact Store origin;
6. `status`, `ensure_runtime`, `check_codex`, and `shutdown_if_idle` from Chrome;
7. Chrome restart and macOS restart recovery without a LaunchAgent;
8. universal host and Sidecar execution on both architectures;
9. versioned installer repair/update, idle handoff, activation, rollback, and
   checksum rejection; signed automatic runtime updates remain a future stable
   gate;
10. repair and uninstall preserving `~/Library/Application Support/AkuBrowser/data`;
11. portable-runtime conflict guidance; and
12. Linux showing an unavailable installer state rather than a broken link.

`scripts/test-macos-runtime-installer.sh` validates package structure and
architecture locally. It does not replace the two clean-machine install runs.

A future stable macOS package must additionally pass Developer ID Application
and Installer signature validation, notarization, stapling, and offline ticket
verification. Those stable-only gates do not describe the trust state of
`v0.7.9-preview1`.
