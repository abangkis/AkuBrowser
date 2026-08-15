# AkuBrowser 0.7.9

`0.7.9` is the current cross-platform distribution candidate. It retains the explicit,
user-triggered Codex prerequisite check to Setup, with installation guidance
when Codex App Server is unavailable and manual sign-in confirmation only after
a compatible executable is detected. It keeps the bounded Luna
Max reasoning profile as an explicit tuning option, while Luna XHigh is the
fresh default for Candidate Evaluation, and raises the fresh Auto Update daily
model budget from 1M to 2M tokens while retaining the 25% user reserve. Existing persisted profile and
quota settings remain authoritative. This is the packaged
candidate described by the OpenAI Build Week
[final project story](openai-build-week-submission.md) and
[implementation evidence](../BUILD_WEEK.md). The first calibration
check builds its semantic index locally without a model-backed cross-author
comparison; later checks use the full Event Engine. The release contains
AkuSidecar and a verified AkuBridge payload for audit and troubleshooting, while
the published extension is installed from the Chrome Web Store. AkuSupervisor and
AkuSupervisorConformance remain development tooling and are not shipped.
AkuBrowser is the distribution authority: it owns portable bundle assembly,
release provenance, launchers, checksums, and acceptance documentation.
AkuSidecar and AkuBridge remain the authoritative source-component projects.

Windows has two coordinated delivery paths: the portable x64 ZIP remains the
manual fallback, while the Chrome Web Store flow uses a user-scoped companion
runtime installer. The stable `v0.7.9` release provides the equivalent
Chrome Web Store bootstrap through an explicitly named unsigned and not
notarized universal `.pkg`; the universal portable ZIP remains its manual
fallback. The package and release notes disclose the trust state, checksum
verification, and Apple's per-app **Open Anyway** recovery without instructing
users to disable Gatekeeper. Signed and notarized packages remain future
hardening work. Both platform bundles contain the Sidecar
executable, release configuration, the verified Bridge payload, and a
foreground launcher. Stable production bundles project the exact Chrome Web
Store Bridge identity into Sidecar configuration; the bundled Bridge directory
is not a second extension installation. The packages require no AkuSupervisor process or
development workspace path. The Windows bundle also carries a pinned
`c2patool.exe` so image-only C2PA inspection works without a separate tool
installation. Its required version and SHA-256 are release-manifest inputs and
are checked again by artifact acceptance. Windows stores user data under
`%LOCALAPPDATA%\AkuBrowser`; macOS stores it under
`~/Library/Application Support/AkuBrowser/data`.

## Preview prerequisites

This preview discovers and capability-checks a compatible Codex runtime. The
extension setup page links to Codex installation guidance, but the user remains
responsible for installing Codex App and completing local sign-in.
Before installation, the tester must have:

- Codex App installed with Codex App Server available, or a compatible Codex
  CLI; AkuSidecar discovers and capability-checks the runtime;
- a valid local Codex login;
- Google Chrome installed;
- an active Chrome login for every enabled source: X, LinkedIn, and/or Facebook.

AkuBrowser does not collect or manage Codex or social-source credentials.
Automated Codex installation and sign-in remain outside this preview boundary.
If the first check produces no validated calibration candidate, AkuBrowser keeps
the captured trace in Update Inbox and offers **Update now again** instead
of presenting a terminal calibration error.

## Portable fallback and Bridge installation

The stable portable bundle is a self-contained offline lane. Load its bundled
`AkuBridge` directory first, verify the stable `production-offline` ID, and then
start the portable runtime. The separate Chrome Web Store lane uses the
`production-store` identity and installed companion runtime; do not enable both
lanes together.

Local unpacked-extension work remains a separate AkuWorkspace development
channel, and Step 3B uses a fourth `acceptance` identity. On Windows, run the bundled
`.\Start-AkuBrowser.ps1` launcher from PowerShell and confirm the Bridge-ready
status. `Start-AkuBrowser.cmd` remains a convenience fallback and delegates to
the same PowerShell script.

The immutable preview tags retain their original installation contracts and are
not silently reclassified as stable production bundles.

On macOS, run `./Start-AkuBrowser.sh` from Terminal or double-click
`Start-AkuBrowser.command`; the macOS launcher performs the same Sidecar health
check before opening the local UI. See the bundled
[`release/macos/README.md`](../release/macos/README.md) for Codex discovery,
custom executable paths, and checksum verification.

## Build and acceptance

Windows x64 artifacts are built and smoke-tested with
`scripts/build-windows-preview.ps1` and `scripts/test-windows-preview.ps1`.
Those commands are component-level developer tools. A frozen stable release
must instead use `scripts/run-windows-stable-gate.ps1`, which produces one
release kit with separate `publish/` and local-only `acceptance/` allowlists.
In the shared Windows development workspace,
`scripts/prepare-local-release.ps1` is the canonical local release command. It
keeps artifact construction portable, then separately reconciles the generated
AkuSidecar development binary and the unpacked AkuBridge heartbeat after the
artifact passes acceptance. This prevents a release build from leaving a newly
reloaded extension paired with a stale Supervisor-owned development binary.
It does not create tags, push repositories, or publish assets.
macOS artifacts are built on a Mac with `scripts/build-macos-preview.sh` and
smoke-tested with `scripts/test-macos-preview.sh`. The build pipeline can
produce native `x64` or `arm64` bundles for focused testing; the published
`0.7.0-preview.3` asset is `macos-universal` and runs on Intel and Apple
silicon.
The earlier preview tags remain immutable and are not marked Latest. The stable
`v0.7.9` release is gated on aligned Windows and macOS assets from one source
tuple; its unsigned installer trust state is an explicit release decision.

The automated gates verify the bundle manifest, bundled-file checksums,
Sidecar health, both supported loopback hostnames, fresh-database defaults, and
the embedded UI. Final acceptance still requires a clean machine on the target
OS and architecture. See [Windows preview acceptance](windows-preview-acceptance.md)
and [macOS preview acceptance](macos-preview-acceptance.md). Promotion to a
cross-platform stable release follows the canonical
[stable release checklist](stable-release-checklist.md).

The Chrome Web Store package is built separately from the portable bundle. It
does not embed or silently execute native code: the user explicitly downloads
and runs the companion installer, then returns to Setup and checks the runtime.

## Fresh defaults

The release starts with Standard 1x, Quiet capture with one managed window per
source, Progressive wait, X,
LinkedIn, and Facebook enabled,
semantic duplicates collapsed, and AI Signals routed to the visible Drawer.
AI Detection is enabled by default and can be disabled as one unit, stopping
both local Fast Detection and asynchronous Deep Detection. Native resurfacing
uses Smart handling with a seven-day cooldown by default. Auto Update starts
with a 2M-token daily model budget and keeps 25% unavailable to background
preparation for user-visible updates.
The model-backed profiles are:

| Process | Default profile |
| --- | --- |
| Acquisition planning | Luna High |
| Candidate evaluation | Luna XHigh |
| Semantic event resolution | Luna High |
| AI Deep Detection | Luna High |

Only Candidate Evaluation uses Luna XHigh by default. Existing persisted user
settings remain authoritative; these values apply to a fresh database or full
reset.

## Version authority

[`release/release-manifest.json`](../release/release-manifest.json) is the
machine-readable release authority. The immutable `v0.7.0-preview.1` tags remain
the historical compatibility checkpoint and must never be moved. The
Preview tags identify historical source checkpoints; the stable `v0.7.9` tag
remains separate. Each generated bundle additionally
records its exact AkuBrowser, AkuSidecar, and AkuBridge commits and dirty state
in `artifact-manifest.json`.
