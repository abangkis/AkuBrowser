# AkuBrowser

AkuBrowser turns a bounded sample of X and LinkedIn into one finite, source-backed Timeline. It is designed for people who want to keep up without surrendering their attention to another infinite feed.

Its cross-author semantic Event Engine treats the underlying event—not the number of posts about it—as the unit of attention. When different authors or sources report the same specific occurrence, AkuBrowser can collapse the repetition while preserving the reports for inspection and correction. The user reads the change once instead of paying the same attention cost again for every account that repeated it.

The personalization rule is equally direct: explicit user feedback has more authority than opaque engagement inferred by a social network. Once the local profile has enough repeated evidence, More and Not interested may promote, replace, demote, or suppress ordinary candidates. Evidence quality, material updates, contradictions, and one bounded discovery lane remain protected.

## Workspace boundary

AkuBrowser is a documentation and integration repository; it has no Node package or application runtime.

| Repository | Responsibility | Runtime |
| --- | --- | --- |
| `AkuBrowser` | Product contract, canonical schemas, integration check | PowerShell only |
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

Open `http://127.0.0.1:47821`. Load `..\AkuBridge` as an unpacked Chrome extension once; subsequent extension reloads are coordinated through AkuSupervisor.

## Canonical documentation

- [Product contract](docs/product-contract.md)
- [Runtime contract](docs/runtime-contract.md)
- [OpenAI Build Week submission draft](docs/openai-build-week-submission.md)
- [Bridge Contract v2](contracts/bridge-contract-v2.md)
- [Active machine-readable schemas](contracts/README.md)

Historical experiments and superseded contracts live in Git history, not in the active documentation set.
