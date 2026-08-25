# AkuBrowser

Current shipped release: **`0.7.9`**. The repository also contains an
unshipped **`0.8.0`** development tuple in
[`release/release-manifest.json`](release/release-manifest.json); its installed-
app schema metadata must be reconciled with the current Sidecar before another
candidate is built. The canonical bundle boundary and migration gates are in
the [installed-app distribution contract](docs/installed-app-distribution-contract.md).

> **Approved target distribution — partially staged, not shipped.** The next production
> direction is one signed installer containing AkuBrowserLauncher, AkuSidecar,
> AkuBridge, pinned Chromium, and the local support assets, with setup owned by
> AkuSidecar inside an isolated app shell. Chrome Web Store and system Chrome
> are not part of that target. See the canonical
> [installed-app distribution contract](docs/installed-app-distribution-contract.md).
> The Store/portable instructions below describe the current shipped state and
> remain historical evidence until the migration is complete.

> ### Install AkuBrowser from the Chrome Web Store
>
> [**Add AkuBrowser to Chrome →**](https://chromewebstore.google.com/detail/akubrowser/phkaipecbhpgopggbfpcejgngbhddnkk)
>
> The Chrome Web Store extension is the supported production installation for
> AkuBrowser. After installing it, use the guided **Setup** flow to install or
> update the local AkuSidecar companion runtime. The Windows/macOS portable
> bundles are a separate, self-contained offline production lane with their
> own stable unpacked-extension identity.

## Latest release downloads

The stable GitHub release is [AkuBrowser 0.7.9](https://github.com/abangkis/AkuBrowser/releases/latest).
Use the platform installer aliases below so future stable releases can update
these links without another README change:

- [Windows runtime installer](https://github.com/abangkis/AkuBrowser/releases/latest/download/AkuBrowserRuntimeSetup.exe)
- [macOS runtime installer](https://github.com/abangkis/AkuBrowser/releases/latest/download/AkuBrowserRuntimeSetup.pkg)
- [All release assets and checksums](https://github.com/abangkis/AkuBrowser/releases/latest)

The portable Windows and macOS bundles remain versioned assets on the release
page. Each contains its matching AkuBridge and AkuSidecar runtime for offline
installation. Verify the adjacent SHA-256 file before using one, and do not run
the offline and Chrome Web Store editions together.

AkuBrowser turns bounded samples from the user's chosen social feeds into one finite, source-backed Timeline. The current source registry supports X, LinkedIn, Facebook, and opt-in Instagram. It is designed for people who want to keep up without surrendering their attention to another infinite feed.

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
integration repository. It owns release manifests, portable bundle assembly,
checksums, launchers, and acceptance guidance, while keeping application
runtime code in its component repositories. AkuBrowser has no Node package or
application runtime of its own.

### Current shipped distribution (historical)

The staged consumer distribution path publishes the extension under the public
name **AkuBrowser** while retaining `AkuBridge` as the internal component name.
Its Native Messaging, companion installer, Store, and signed runtime-update
gates are preserved as current implementation history in
[`docs/chrome-store-distribution-contract.md`](docs/chrome-store-distribution-contract.md).
Development and production extension IDs are named profiles in one registry;
their generated runtime projections are defined in
[`docs/bridge-identity-contract.md`](docs/bridge-identity-contract.md).

The end-user deployment has exactly two independently updated products:
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

## Development

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

The preview assumes Codex App with App Server is installed and signed in
locally, and that Chrome is already signed in to every enabled source. Store
users follow the guided extension Setup and install the user-scoped companion
runtime; the portable ZIP remains available as a self-contained offline lane.
Its bundled `production-offline` Bridge is distinct from both the Store package
and the Load unpacked `acceptance` package used for clean-machine Step 3B.
See [Preview release](docs/preview-release.md).

Build and smoke-test the Windows x64 portable preview from this repository:

```powershell
.\scripts\build-windows-preview.ps1
.\scripts\test-windows-preview.ps1
```

The generated directory, ZIP, and ZIP checksum are written beneath
`artifacts\`. Use `-AllowDirty` only while developing the pipeline; a publishable
artifact requires clean AkuBrowser, AkuSidecar, and AkuBridge source trees.

For a frozen stable candidate, do not run the portable and installer builders
into separate folders. Use `scripts/run-windows-stable-gate.ps1`; it creates one
release kit with a GitHub-uploadable `publish/` lane and a local-only
`acceptance/` lane containing the matching unpacked Bridge and runtime installer.
The exact command and handoff gates are in the
[stable release checklist](docs/stable-release-checklist.md).

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

On macOS, the same preview boundary is packaged with the native Go Sidecar and
the unpacked AkuBridge extension. Go, Node.js, npm, and the macOS `zip` tools are
needed on the build machine; end users only need Codex App/App Server and
Chrome. Build and smoke-test the host architecture with:

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
Build the Chrome Web Store macOS companion separately with
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
- [AkuBrowserLauncher Windows vertical slice](launcher/README.md)
- [Product contract](docs/product-contract.md)
- [Runtime contract](docs/runtime-contract.md)
- [AI Feedback Engine contract](docs/ai-feedback-contract.md)
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
