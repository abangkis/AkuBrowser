# AkuBrowser 0.7.0-preview.2

`0.7.0-preview.2` is the current source-aligned Windows preview candidate. It
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

The first Windows delivery format is a portable x64 ZIP, not an installer. It
contains the Sidecar executable, release configuration, the verified unpacked
Bridge payload, and a foreground launcher. The package stores user data under
`%LOCALAPPDATA%\AkuBrowser` and requires no AkuSupervisor process or development
workspace path.

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
the captured trace in Update Inbox and offers **Check for updates again** instead
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

Future Store, private-test, or enterprise distribution is a separate release
decision. The preview does not claim automatic extension installation.

## Fresh defaults

The release starts with Standard 1x, Quiet capture, Progressive wait, X,
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
the historical compatibility checkpoint and must never be moved. Once this
candidate is accepted, `v0.7.0-preview.2` tags must identify the exact source
commits used by the published bundle in each AkuWorkspace repository. Local
candidate builds before that acceptance record their source commits and dirty
state directly in `artifact-manifest.json`.
