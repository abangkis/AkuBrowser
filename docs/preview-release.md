# AkuBrowser 0.7.6

`0.7.6` is the current source-aligned Windows preview. It adds a guided,
platform-aware Chrome extension setup flow, clearer Windows antivirus guidance,
an explicit manual portable-bundle fallback, and actionable recovery when
Windows security software blocks AkuSidecar or Codex state access. This is the packaged
candidate described by the OpenAI Build Week
[final project story](openai-build-week-submission.md) and
[implementation evidence](../BUILD_WEEK.md). The first calibration
check builds its semantic index locally without a model-backed cross-author
comparison; later checks use the full Event Engine. The release contains AkuSidecar and an
unpacked AkuBridge payload. AkuSupervisor and
AkuSupervisorConformance remain development tooling and are not shipped.
AkuBrowser is the distribution authority: it owns portable bundle assembly,
release provenance, launchers, checksums, and acceptance documentation.
AkuSidecar and AkuBridge remain the authoritative source-component projects.

Windows has two coordinated delivery paths: the portable x64 ZIP remains the
manual fallback, while the Chrome Web Store flow uses a user-scoped companion
runtime installer. The published macOS delivery is one universal portable ZIP containing both x64 and
arm64 Sidecar slices. Both platform bundles contain the Sidecar
executable, release configuration, the verified unpacked Bridge payload, and a
foreground launcher. The packages require no AkuSupervisor process or
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

## Portable fallback and manual AkuBridge installation

The portable preview bundle carries AkuBridge as a stable unpacked directory. Chrome on
Windows and macOS does not permit an ordinary third-party installer to silently
install a local extension. The tester must:

1. open `chrome://extensions`;
2. enable Developer mode;
3. choose **Load unpacked**;
4. select the bundled `AkuBridge` directory; and
5. confirm that the extension is enabled before starting AkuBrowser.

AkuBridge is deliberately installed first so onboarding never begins with only
half of the local system available. After the extension is ready, run the
bundled `.\Start-AkuBrowser.ps1` launcher from PowerShell and confirm the
Bridge-ready status. `Start-AkuBrowser.cmd` remains a convenience fallback and
delegates to the same PowerShell script.

On macOS, run `./Start-AkuBrowser.sh` from Terminal or double-click
`Start-AkuBrowser.command`; the macOS launcher performs the same Sidecar health
check before opening the local UI. See the bundled
[`release/macos/README.md`](../release/macos/README.md) for Codex discovery,
custom executable paths, and checksum verification.

## Build and acceptance

Windows x64 artifacts are built and smoke-tested with
`scripts/build-windows-preview.ps1` and `scripts/test-windows-preview.ps1`.
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
The `v0.7.6` tag is the source checkpoint for the Windows bundle and future
matching macOS bundle. The accepted Windows bundle and its adjacent checksum
are published from the
[`v0.7.6` GitHub Release](https://github.com/abangkis/AkuBrowser/releases/tag/v0.7.6).
The previously published macOS universal bundle remains available from the
[`v0.7.0-preview.3` GitHub Release](https://github.com/abangkis/AkuBrowser/releases/tag/v0.7.0-preview.3)
until a matching macOS 0.7.6 build completes acceptance.

The automated gates verify the bundle manifest, bundled-file checksums,
Sidecar health, both supported loopback hostnames, fresh-database defaults, and
the embedded UI. Final acceptance still requires a clean machine on the target
OS and architecture. See [Windows preview acceptance](windows-preview-acceptance.md)
and [macOS preview acceptance](macos-preview-acceptance.md).

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
uses Smart handling with a seven-day cooldown by default.
The model-backed profiles are:

| Process | Default profile |
| --- | --- |
| Acquisition planning | Luna High |
| Candidate evaluation | Luna Max |
| Semantic event resolution | Luna High |
| AI Deep Detection | Luna High |

Only Candidate Evaluation uses Luna Max by default. Existing persisted user
settings remain authoritative; these values apply to a fresh database or full
reset.

## Version authority

[`release/release-manifest.json`](../release/release-manifest.json) is the
machine-readable release authority. The immutable `v0.7.0-preview.1` tags remain
the historical compatibility checkpoint and must never be moved. The published
`v0.7.6` tags identify the current release source checkpoints; each generated
bundle additionally records its exact AkuBrowser, AkuSidecar, and AkuBridge
commits and dirty state in `artifact-manifest.json`.
