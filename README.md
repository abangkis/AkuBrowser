# AkuBrowser

Current release: **`v0.9.0` for Windows x64**. It is distributed as one
unsigned installer `.exe` containing AkuBrowserLauncher,
AkuSidecar, the internal AkuBridge payload, pinned Chromium, c2patool, and the
release configuration/checksums needed by the isolated app shell. The release
publishes a SHA-256 checksum and explicitly discloses the unsigned SmartScreen
trust state. Independent clean-machine coverage remains tracked as post-release
hardening. The canonical
bundle boundary and gates are in the [installed-app distribution
contract](docs/installed-app-distribution-contract.md).

> **v0.9.0 distribution boundary.** The active release path is
> one Windows x64 installed-app installer. It does not require the Chrome Web
> Store, system Chrome, Developer Mode, a manually loaded extension, or a
> separate runtime installer. The current candidate still carries an honest
> unsigned/SmartScreen warning; users should verify the published checksum.
> macOS and Linux are deferred and are not part of this release.

> ### Chrome Web Store publication is frozen
>
> The existing Chrome Web Store listing remains available to current users, but
> no new Store builds are published. New production work targets the single
> installed-app tuple, with AkuSidecar owning first-run onboarding in the
> isolated app shell. The listing and portable ZIP are historical/recovery
> lanes, not v0.9.0 release outputs. See the [installed-app distribution
> target](docs/installed-app-distribution-contract.md).

## Release downloads

The [AkuBrowser v0.9.0 release](https://github.com/abangkis/AkuBrowser/releases/tag/v0.9.0)
exposes one Windows x64 installer `.exe` and its SHA-256 checksum as the
supported download. It is intentionally unsigned, so Windows may show a
SmartScreen warning. Verify the checksum and do not run it alongside the frozen
Store edition.

The old Windows/macOS runtime installers and portable bundles remain versioned
historical/recovery assets. macOS and Linux downloads are explicitly deferred
from v0.9.0.

AkuBrowser turns bounded samples from the user's chosen social feeds into one finite, source-backed Timeline. The current source registry supports four adapters: X, LinkedIn, Facebook, and opt-in Instagram. It is designed for people who want to keep up without surrendering their attention to another infinite feed.

Its cross-author semantic Event Engine treats the underlying event—not the number of posts about it—as the unit of attention. When different authors or sources report the same specific occurrence, AkuBrowser can collapse the repetition while preserving the reports for inspection and correction. The user reads the change once instead of paying the same attention cost again for every account that repeated it.

Its AI Signals layer adds a separate, explicitly uncertain view of AI origin.
A local deterministic pass can annotate retained text immediately, while an
asynchronous Codex pass may confirm, dispute, or correct that preliminary
assessment. These signals never affect relevance selection or ranking. Drawer
is the preview default; users may instead keep strong signals inline or, after
an exact typed warning, hide only direct or Deep-confirmed results. Direct user
correction has the highest presentation authority.

X media can also finish passively after the usable Timeline is already on
screen. AkuBridge v60 keeps only short-lived, allowlisted post-media evidence
from the rendered page or X's already-requested timeline/detail responses and
may attach it to the matching retained item without making a provider request
or opening or focusing a tab. Raw responses and post text never leave the page
world or persist. Explicit quiet/foreground Recapture remains the fallback when
that evidence never appears.

The personalization rule is equally direct: explicit user feedback has more authority than opaque engagement inferred by a social network. Once the local profile has enough repeated evidence, More and Not interested may promote, replace, demote, or suppress ordinary candidates. Evidence quality, material updates, contradictions, and one bounded discovery lane remain protected.

## Distribution and workspace boundary

AkuBrowser is the distribution authority as well as the product-contract and
integration repository. It owns release manifests, installed-app installer
assembly, checksums, launchers, and acceptance guidance, while keeping
application runtime code in its component repositories. AkuBrowser has no Node
package or application runtime of its own.

### Historical shipped distribution (pre-v0.9.0)

The staged consumer distribution path publishes the extension under the public
name **AkuBrowser** while retaining `AkuBridge` as the internal component name.
Its Native Messaging, companion installer, Store, and signed runtime-update
gates are preserved as current implementation history in
[`docs/chrome-store-distribution-contract.md`](docs/chrome-store-distribution-contract.md).
Development and production extension IDs are named profiles in one registry;
their generated runtime projections are defined in
[`docs/bridge-identity-contract.md`](docs/bridge-identity-contract.md).

The pre-v0.9.0 end-user deployment had exactly two independently updated products:
AkuBridge from the Chrome Web Store and AkuSidecar from the signed platform
feed. The Native Messaging host is an internal helper shipped inside the
AkuSidecar installer, not a third deployable. AkuSupervisor remains optional
development tooling and is never required or shipped to Store users.

| Repository | Responsibility | Runtime |
| --- | --- | --- |
| `AkuBrowser` | Product contract, canonical schemas, distribution assembly, integration and artifact checks | PowerShell + POSIX shell release tooling |
| `AkuBridge` | Read-only bounded Chrome capture | Browser JavaScript / Node test tooling |
| `AkuSidecar` | UI, sessions, SQLite, reasoning, selection, personalization | Go |
| `AkuSupervisor` | Optional development-only process ownership; excluded from end-user deployment | Rust |

Only AkuBridge uses npm, because it is the Chrome extension. AkuSidecar is fully Go. In development AkuSupervisor may start Sidecar; production installation and update do not depend on Supervisor.

## Development and v0.9.0 release build

Run the workspace check from this repository:

```powershell
.\scripts\check.ps1
```

That command first runs a fail-fast integration identity check across the release manifest and the public Bridge/Sidecar declarations, then verifies schemas, runs Go tests in AkuSidecar, and runs npm checks inside AkuBridge. The identity check is development/release tooling only: AkuBridge and AkuSidecar do not import one another or read sibling repositories at runtime. It does not read AkuSupervisor configuration or require AkuSupervisor to be present. AkuBrowser itself does not install npm dependencies.

For normal local operation, build AkuSidecar and let AkuSupervisor own its lifecycle:

```powershell
cd ..\AkuSidecar
.\scripts\restart-dev.ps1
```

Open `http://127.0.0.1:11122` (or `http://localhost:11122`). Load
`..\AkuBridge` as an unpacked Chrome extension once; subsequent extension
reloads use the Sidecar's cooperative `reload_self` contract. AkuSupervisor
remains only the generic process owner.

The v0.9.0 installed app uses the bundled pinned Chromium profile and
does not require system Chrome or manual extension loading. Codex App with App
Server remains an external prerequisite and must be installed and signed in
locally. An optional Gemini provider accepts a user-supplied key through the
Sidecar credential flow; provider hot-swaps apply at an idle boundary. The four
source adapters are X, LinkedIn, Facebook, and opt-in Instagram. AkuSidecar
uses schema 10 and owns first-run onboarding, source readiness, and Timeline
state. See [Preview/release candidate notes](docs/preview-release.md).

The portable ZIP and Chrome Web Store package are historical/recovery lanes and
are not v0.9.0 distribution paths.

Build and validate the Windows installed-app release from this repository:

```powershell
.\scripts\build-windows-installed-app.ps1 -OutputRoot .\artifacts
.\scripts\test-windows-installed-app-builder.ps1 `
  -ArtifactDirectory .\artifacts\AkuBrowser-<version>-windows-x64-installed-app
.\scripts\build-windows-installed-app-installer.ps1 `
  -TupleDirectory .\artifacts\AkuBrowser-<version>-windows-x64-installed-app `
  -NsisPath "C:\Program Files (x86)\NSIS\makensis.exe"
.\scripts\test-windows-installed-app-installer.ps1 `
  -TupleDirectory .\artifacts\AkuBrowser-<version>-windows-x64-installed-app `
  -InstallerPath .\artifacts\installed-app-installer\AkuBrowserSetup-0.9.0-windows-x64.exe
```

These commands produce the intentionally unsigned release artifact and matching
checksum. Automated checks validate the tuple, hashes, launcher, and PE
structure; the broader clean-machine matrix remains documented in the [stable
release checklist](docs/stable-release-checklist.md).

### Historical portable preview build

The following commands reproduce the pre-v0.9.0 portable recovery lane; they
are not the active single-installer release gate:

```powershell
.\scripts\build-windows-preview.ps1
.\scripts\test-windows-preview.ps1
```

The generated directory, ZIP, and ZIP checksum are written beneath
`artifacts\`. Use `-AllowDirty` only while developing the pipeline; a publishable
artifact requires clean AkuBrowser, AkuSidecar, and AkuBridge source trees.

The old `scripts/run-windows-stable-gate.ps1` flow produces the historical
Store/portable release kit. It is not the active v0.9.0 one-installer gate; keep
its outputs only for recovery and historical reproduction.

For a local release checkpoint, use the reconciled workflow instead:

```powershell
.\scripts\prepare-local-release.ps1
```

It builds and smoke-tests the bundle, waits for Sidecar update readiness,
atomically rebuilds the Supervisor-owned development executable, verifies the
new health version, and reloads AkuBridge only when its capability heartbeat is
not already compatible. `runtime\dev\aku-sidecar.exe.runtime-state.json` records
the exact development source commit and binary hash. The workflow never tags,
pushes, or uploads a release. Use `-SkipDevelopmentSync` only when intentionally
building an isolated artifact without changing the active development runtime.

## OpenAI Build Week

AkuBrowser began as an early bounded X/LinkedIn prototype and was materially
extended during OpenAI Build Week. Working with Codex, the project rewrote
AkuSidecar from Node.js to Go, moved runtime reasoning to Codex App Server,
activated preference filtering, added cross-source semantic event resolution
and AI Signals, expanded capture to Facebook, strengthened recovery, and built
verifiable portable previews for Windows x64 and macOS on Intel and Apple
silicon.

Codex accelerated architecture, implementation, live debugging, tests,
documentation, and release preparation. In the running product, GPT-5.6 powers
schema-bound Acquisition Planning, Candidate Evaluation, Semantic Event
Resolution, and AI Deep Detection. AkuSidecar—not the model—remains responsible
for permissions, budgets, validation, preference authority, SQLite state, and
final composition.

The submission evidence, the distinction between earlier work and dated
submission-period extensions, and the release/judge workflow are in
[`BUILD_WEEK.md`](BUILD_WEEK.md). The copy-ready project story is in
[`docs/openai-build-week-submission.md`](docs/openai-build-week-submission.md).

macOS and Linux packaging are deferred from v0.9.0. Their historical preview
instructions remain below for reproducibility, but they are not release gates
for this Windows-only candidate.

On macOS, the historical preview boundary was packaged with the native Go
Sidecar and the unpacked AkuBridge extension. Go, Node.js, npm, and the macOS
`zip` tools were needed on the build machine; end users needed Codex App/App
Server and Chrome. Build and smoke-test the historical host architecture with:

```sh
./scripts/build-macos-preview.sh
./scripts/test-macos-preview.sh
```

The default target matches the build Mac. Use `--architecture x64` or
`--architecture arm64` for a native single-architecture artifact, or
`--architecture universal` for a dual-architecture form. Use
`--allow-dirty` only for local pipeline development; a publishable artifact
requires clean AkuBrowser, AkuSidecar, and AkuBridge source trees. The artifact
directory, ZIP, and ZIP checksum are written beneath `artifacts/`. Installation
and launcher details are in
[`release/macos/README.md`](release/macos/README.md).
Build the historical Chrome Web Store macOS companion separately with
`scripts/build-macos-runtime-installer.sh`; validate its payload with
`scripts/test-macos-runtime-installer.sh`. The stable `v0.7.9` release uses an
explicitly disclosed unsigned package, a pinned universal C2PA tool, and an
Installer warning page. Users must verify the adjacent SHA-256
and use macOS **Privacy & Security > Open Anyway** if Gatekeeper blocks the
package; they must never disable Gatekeeper globally. Developer ID Application
and Installer identities and notarization remain future hardening work. Stable
runtime-update manifests use the Mac signing-request producer and Windows
finalizer documented in `docs/github-macos-signing-handoff.md`; the private key
never leaves Windows.

## Canonical documentation

- [Installed-app distribution target](docs/installed-app-distribution-contract.md)
- [v0.9.0 Windows release notes](docs/releases/v0.9.0.md)
- [AkuBrowserLauncher Windows vertical slice](launcher/README.md)
- [Product contract](docs/product-contract.md)
- [Runtime contract](docs/runtime-contract.md)
- [AI Feedback Engine contract](docs/ai-feedback-contract.md)
- [Personal Memory and Library contract](docs/personal-memory-contract.md)
- [Personal Memory product roadmap](docs/personal-memory-roadmap.md)
- [Preview release](docs/preview-release.md)
- [Stable release checklist](docs/stable-release-checklist.md)
- [Windows clean-machine Step 3B](docs/windows-clean-machine-3b.md)
- [Windows preview acceptance](docs/windows-preview-acceptance.md)
- [macOS preview acceptance](docs/macos-preview-acceptance.md)
- [Build Week evidence and judge checklist](BUILD_WEEK.md)
- [OpenAI Build Week final project story](docs/openai-build-week-submission.md)
- [Bridge Contract v2](contracts/bridge-contract-v2.md)
- [Active machine-readable schemas](contracts/README.md)

Historical experiments and superseded contracts live in Git history, not in the active documentation set.
