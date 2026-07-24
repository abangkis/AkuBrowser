# AkuBrowser 0.7.1

`0.7.1` is the current source-aligned Windows preview. It
retains the unified packaging boundary established by preview.1 and adds the
current three-source, progressive scheduling, native-resurface, execution
timing, onboarding recovery, and AI Signals controls. This is the packaged
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

The Windows delivery format is a portable x64 ZIP, not an installer. The
published macOS delivery is one universal portable ZIP containing both x64 and
arm64 Sidecar slices. Both platform bundles contain the Sidecar
executable, release configuration, the verified unpacked Bridge payload, and a
foreground launcher. The packages require no AkuSupervisor process or
development workspace path. Windows stores user data under
`%LOCALAPPDATA%\AkuBrowser`; macOS stores it under
`~/Library/Application Support/AkuBrowser/data`.

## Preview prerequisites

This preview discovers and capability-checks a compatible Codex runtime but
deliberately defers guided installation and login assistance.
Before installation, the tester must have:

- Codex App installed with Codex App Server available, or a compatible Codex
  CLI; AkuSidecar discovers and capability-checks the runtime;
- a valid local Codex login;
- Google Chrome installed;
- an active Chrome login for every enabled source: X, LinkedIn, and/or Facebook.

AkuBrowser does not collect or manage Codex or social-source credentials.
Guided missing-app and signed-out recovery remain outside this preview boundary.
If the first check produces no validated calibration candidate, AkuBrowser keeps
the captured trace in Update Inbox and offers **Update now again** instead
of presenting a terminal calibration error.

## Manual AkuBridge installation

The preview bundle carries AkuBridge as a stable unpacked directory. Chrome on
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
macOS artifacts are built on a Mac with `scripts/build-macos-preview.sh` and
smoke-tested with `scripts/test-macos-preview.sh`. The build pipeline can
produce native `x64` or `arm64` bundles for focused testing; the published
`0.7.0-preview.3` asset is `macos-universal` and runs on Intel and Apple
silicon.
The Windows 0.7.1 bundle and its adjacent checksum are available from the
[`v0.7.1` GitHub Release](https://github.com/abangkis/AkuBrowser/releases/tag/v0.7.1).
The previously published macOS universal bundle remains available from the
[`v0.7.0-preview.3` GitHub Release](https://github.com/abangkis/AkuBrowser/releases/tag/v0.7.0-preview.3)
until a matching macOS 0.7.1 build is produced.

The automated gates verify the bundle manifest, bundled-file checksums,
Sidecar health, both supported loopback hostnames, fresh-database defaults, and
the embedded UI. Final acceptance still requires a clean machine on the target
OS and architecture. See [Windows preview acceptance](windows-preview-acceptance.md)
and [macOS preview acceptance](macos-preview-acceptance.md).

Future Store, private-test, or enterprise distribution is a separate release
decision. The preview does not claim automatic extension installation.

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
| Candidate evaluation | Luna XHigh |
| Semantic event resolution | Luna High |
| AI Deep Detection | Luna High |

Only Candidate Evaluation uses Luna XHigh by default. Existing persisted user
settings remain authoritative; these values apply to a fresh database or full
reset.

## Version authority

[`release/release-manifest.json`](../release/release-manifest.json) is the
machine-readable release authority. The immutable `v0.7.0-preview.1` tags remain
the historical compatibility checkpoint and must never be moved. The published
`v0.7.1` tags identify the current release source checkpoints; each generated
bundle additionally records its exact AkuBrowser, AkuSidecar, and AkuBridge
commits and dirty state in `artifact-manifest.json`.
