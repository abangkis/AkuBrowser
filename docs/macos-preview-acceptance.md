# macOS preview acceptance

AkuBrowser owns the macOS distribution boundary across the component
repositories; AkuSupervisor and AkuSupervisorConformance are not packaged.
The published `0.7.0-preview.3` target is one `macos-universal` ZIP containing
both x64 and arm64 Sidecar slices for Intel and Apple-silicon Macs.

## Automated artifact gate

Run on a Mac from the AkuBrowser repository:

```sh
./scripts/build-macos-preview.sh --architecture universal
./scripts/test-macos-preview.sh --zip artifacts/AkuBrowser-0.7.0-preview.3-macos-universal.zip
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
./scripts/test-macos-preview.sh --zip /path/to/AkuBrowser-0.7.0-preview.3-macos-universal.zip
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
9. complete onboarding and calibration, run **Check for updates**, provide
   More/Less feedback, and inspect Update Inbox and Settings;
10. stop AkuBrowser with Ctrl+C and confirm it exits cleanly;
11. restart the same extracted bundle and confirm state is retained under
    `~/Library/Application Support/AkuBrowser/data`; and
12. confirm no AkuSupervisor process or development workspace path is required.

Unsigned preview binaries may trigger Gatekeeper. Do not disable Gatekeeper
globally. Use the macOS security prompt, or remove quarantine only after the
ZIP checksum has been verified.

## Acceptance boundary

The preview is a portable ZIP, not a signed or notarized installer. Automatic
AkuBridge installation, guided Codex installation or login recovery, automatic
updates, Linux packaging, and a bundled cross-platform Supervisor remain
outside the `0.7.0-preview.3` acceptance boundary.
