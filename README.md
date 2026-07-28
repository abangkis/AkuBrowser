# AkuBrowser

Current preview release: **`0.7.4`**. The canonical component tuple,
bundle boundary, and preview prerequisites are recorded in
[`release/release-manifest.json`](release/release-manifest.json).

AkuBrowser turns bounded samples from the user's chosen social feeds into one finite, source-backed Timeline. The current source registry supports X, LinkedIn, and Facebook. It is designed for people who want to keep up without surrendering their attention to another infinite feed.

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

The staged consumer distribution path publishes the extension under the public
name **AkuBrowser** while retaining `AkuBridge` as the internal component name.
Its Native Messaging, companion installer, Store, and signed runtime-update
gates are defined in
[`docs/chrome-store-distribution-contract.md`](docs/chrome-store-distribution-contract.md)
and [`docs/chrome-store-rollout-plan.md`](docs/chrome-store-rollout-plan.md).

| Repository | Responsibility | Runtime |
| --- | --- | --- |
| `AkuBrowser` | Product contract, canonical schemas, distribution assembly, integration and artifact checks | PowerShell + POSIX shell release tooling |
| `AkuBridge` | Read-only bounded Chrome capture | Browser JavaScript / Node test tooling |
| `AkuSidecar` | UI, sessions, SQLite, reasoning, selection, personalization | Go |
| `AkuSupervisor` | Visible development process ownership, health, logs, cooperative Bridge reload, and read-only MCP inspection | Rust |

Only AkuBridge uses npm, because it is the Chrome extension. AkuSidecar is fully Go. AkuSupervisor starts the Sidecar executable directly.

## Development

Run the workspace check from this repository:

```powershell
.\scripts\check.ps1
```

That command verifies the AkuBrowser, AkuSidecar, and AkuBridge identities and schemas, runs Go tests in AkuSidecar, and runs npm checks inside AkuBridge. It does not read AkuSupervisor configuration or require AkuSupervisor to be present. AkuBrowser itself does not install npm dependencies.

For normal local operation, build AkuSidecar and let AkuSupervisor own its lifecycle:

```powershell
cd ..\AkuSidecar
.\scripts\restart-dev.ps1
```

Open `http://127.0.0.1:11122` (or `http://localhost:11122`). Load
`..\AkuBridge` as an unpacked Chrome extension once; subsequent extension
reloads are coordinated through AkuSupervisor.

The preview package assumes Codex App with App Server is installed and signed
in locally, and that Chrome is already signed in to every enabled source. AkuBridge
is bundled as an unpacked payload and installed manually through Chrome
Developer mode. See [Preview release](docs/preview-release.md).

Build and smoke-test the Windows x64 portable preview from this repository:

```powershell
.\scripts\build-windows-preview.ps1
.\scripts\test-windows-preview.ps1
```

The generated directory, ZIP, and ZIP checksum are written beneath
`artifacts\`. Use `-AllowDirty` only while developing the pipeline; a publishable
artifact requires clean AkuBrowser, AkuSidecar, and AkuBridge source trees.

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
The `v0.7.4` tag is the source checkpoint for the current bundle. The Windows
ZIP and adjacent checksum are published from the
[`v0.7.4` GitHub Release](https://github.com/abangkis/AkuBrowser/releases/tag/v0.7.4).

## Canonical documentation

- [Product contract](docs/product-contract.md)
- [Runtime contract](docs/runtime-contract.md)
- [AI Feedback Engine contract](docs/ai-feedback-contract.md)
- [Preview release](docs/preview-release.md)
- [Windows preview acceptance](docs/windows-preview-acceptance.md)
- [macOS preview acceptance](docs/macos-preview-acceptance.md)
- [Build Week evidence and judge checklist](BUILD_WEEK.md)
- [OpenAI Build Week final project story](docs/openai-build-week-submission.md)
- [Bridge Contract v2](contracts/bridge-contract-v2.md)
- [Active machine-readable schemas](contracts/README.md)

Historical experiments and superseded contracts live in Git history, not in the active documentation set.
