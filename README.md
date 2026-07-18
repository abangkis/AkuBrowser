# AkuBrowser

Current preview release: **`0.7.0-preview.1`**. The canonical component tuple,
bundle boundary, and preview prerequisites are recorded in
[`release/release-manifest.json`](release/release-manifest.json).

AkuBrowser turns a bounded sample of X and LinkedIn into one finite, source-backed Timeline. It is designed for people who want to keep up without surrendering their attention to another infinite feed.

Its cross-author semantic Event Engine treats the underlying event—not the number of posts about it—as the unit of attention. When different authors or sources report the same specific occurrence, AkuBrowser can collapse the repetition while preserving the reports for inspection and correction. The user reads the change once instead of paying the same attention cost again for every account that repeated it.

Its AI Detector adds a separate, explicitly uncertain layer for AI origin signals. A local deterministic pass can annotate retained text immediately, while an asynchronous Codex pass may confirm, dispute, or correct that preliminary assessment. Every assessment binds the social post to the actual evidence scope, so an AI-created external artifact is not mislabeled as an AI-authored post. These signals never affect selection or ranking. Drawer is the preview default; users may instead keep strong signals inline or, after an exact typed warning, hide only direct or Deep-confirmed results. Direct user correction has the highest presentation authority.

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

| Repository | Responsibility | Runtime |
| --- | --- | --- |
| `AkuBrowser` | Product contract, canonical schemas, distribution assembly, integration and artifact checks | PowerShell only |
| `AkuBridge` | Read-only bounded Chrome capture | Browser JavaScript / Node test tooling |
| `AkuSidecar` | UI, sessions, SQLite, reasoning, selection, personalization | Go |
| `AkuSupervisor` | Visible development process ownership | Rust |

Only AkuBridge uses npm, because it is the Chrome extension. AkuSidecar is fully Go. AkuSupervisor starts the Sidecar executable directly.

## Development

Run the workspace check from this repository:

```powershell
.\scripts\check.ps1
```

That command verifies the cross-repository identities and schemas, runs Go tests in AkuSidecar, runs npm checks inside AkuBridge, and runs the AkuSupervisor schema contract. AkuBrowser itself does not install npm dependencies.

For normal local operation, build AkuSidecar and let AkuSupervisor own its lifecycle:

```powershell
cd ..\AkuSidecar
.\scripts\restart-dev.ps1
```

Open `http://127.0.0.1:11122`. Load `..\AkuBridge` as an unpacked Chrome extension once; subsequent extension reloads are coordinated through AkuSupervisor.

The preview package assumes Codex App with App Server is installed and signed
in locally, and that Chrome is already signed in to X and LinkedIn. AkuBridge
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

## Canonical documentation

- [Product contract](docs/product-contract.md)
- [Runtime contract](docs/runtime-contract.md)
- [Preview release](docs/preview-release.md)
- [Windows preview acceptance](docs/windows-preview-acceptance.md)
- [OpenAI Build Week submission draft](docs/openai-build-week-submission.md)
- [Bridge Contract v2](contracts/bridge-contract-v2.md)
- [Active machine-readable schemas](contracts/README.md)

Historical experiments and superseded contracts live in Git history, not in the active documentation set.
