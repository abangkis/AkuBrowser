# Build output and acceptance state

`build/` contains reconstructable compiler/package/test output and verified dependency caches. `artifacts/` contains generated release packages. Neither directory is a place for source checkouts, user databases, browser profiles, unique release notes, or durable acceptance evidence.

Release notes belong in `docs/release-notes/`. Sanitized acceptance receipts belong in the tracked `acceptance/` directory. Private profiles, databases, raw evidence, migration manifests, and ownership metadata belong in ignored `acceptance-state/`. Actual installed/development runtime directories are outside cleanup scope.

## Retention

The central policy is `config/build-retention.json`:

| Class | Completed outputs per producer family | Age | Total logical size ceiling |
| --- | --- | --- | --- |
| build | 3 | 7 days | 4 GiB |
| artifacts | 2 | 30 days | 4 GiB |

Count/age rules remove eligible older outputs. The latest successful output per family, pinned release kits, builds in progress, active process references, and trees containing source/state are protected. Protected and unregistered content still counts toward the size ceiling. If that content prevents admission, the next build stops before copying another runtime; retention never overrides these protections to make space.

Windows installed-app, preview, runtime installer, installed-app installer, Store/pre-Store packagers, stable gate, Node cache, and Node cache tests use the shared producer adapter. A stable gate owns its final/staging trees and gives its nested builders the same reservation. The stable gate and signed update packages pin their completed outputs. Register additional producers with `scripts/output-lifecycle.ps1` or the platform-neutral Node CLI before writing new runtime copies. macOS packaging remains a deferred product lane; its shell producers have not been exercised or automatically integrated on this Windows host.

Only registered generated output can be deleted. The registry lives outside disposable output at `acceptance-state/.output-lifecycle/`. Unknown old output is preserved and explicitly listed. Locks and failures are skipped; cleanup never terminates processes.

From AkuBrowser, using PowerShell 7 and Node.js:

```powershell
./scripts/cleanup-build-output.ps1          # dry-run: exact targets, protections, sizes
./scripts/cleanup-build-output.ps1 -Apply   # revalidate and remove eligible owned output
```

The report separates removed logical bytes from the observed change in volume free space. Concurrent activity, compression, and allocation affect volume space; the report does not attribute that entire delta to cleanup.

An interrupted producer remains `building` and an abandoned operation lock fails closed. Inspect the owner PID, process references and exact outputs before recovering it. Once its owner has exited, mark the record failed with `node scripts/build-output-lifecycle.mjs finish --id <id> --state failed`. Remove an abandoned `operation.lock` only after confirming its recorded PID no longer owns an operation. Never edit metadata to adopt unknown source/state as disposable output.

## One-time preservation

```powershell
./scripts/migrate-build-state.ps1                         # dry-run
./scripts/migrate-build-state.ps1 -Apply
./scripts/migrate-build-state.ps1 -OutputClass artifacts  # dry-run
./scripts/migrate-build-state.ps1 -OutputClass artifacts -Apply
```

The helper moves each eligible direct child into `acceptance-state/legacy-build/` or `legacy-artifacts/`, never overwrites a destination, and verifies a complete SHA-256 manifest before and after the move. It skips active or locked content and fails closed if process inspection is unavailable. Migration is preservation, not disk reclamation. The legacy archives are outside automatic retention and require separate inspection before any future deletion.

RC6/RC7 source snapshots are retained in this archive, including ignored files and embedded Git repositories. Their clean tracked source commits were found in the primary repositories; the archive also protects content not established to be reconstructable. RC6 through RC9 release notes are copied into tracked documentation.

New acceptance roots must be direct children of `acceptance-state/`. Migrated roots remain usable under `legacy-build/`. Migration receipts preserve the original credential namespace, so changing the directory does not silently select a different isolated Windows credential identity. Use `start-installed-app-acceptance.ps1 -PlanOnly` to inspect the launch plan; actual foreground acceptance still requires `-AllowForeground`.

## Manual clean rebuild

Prerequisites: PowerShell 7, Node.js, the Go version declared by each module, Git, the pinned Chrome for Testing distribution under `AkuSidecar/runtime/chromium` with `pin.json`, and the manifest-pinned Windows c2patool binary. Installer creation additionally needs NSIS. A cold build may fetch Go modules (including private modules) and the pinned Node.js archive from its official distribution URL. Browser runtime provisioning is a separate explicit dependency step; deleting output does not install it automatically.

`provision-shared-c2patool.ps1` anchors the manifest's SharedTemp suffix at the nearest existing ancestor SharedTemp. It reuses a matching target or stages and verifies the matching local `AkuSidecar/runtime/dev/c2patool.exe`. It never downloads an unpinned substitute. An explicit `-C2paToolPath` remains available. Supply a verified `-SourcePath` to the provisioner if the local development copy is absent.

```powershell
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE = '0'
./scripts/provision-shared-c2patool.ps1
./scripts/build-windows-installed-app.ps1 -OutputRoot ./build/manual-clean
./scripts/test-windows-installed-app-builder.ps1 -ArtifactDirectory ./build/manual-clean/AkuBrowser-0.9.0-windows-x64-installed-app
```

Use `-AllowDirty` only for a local candidate when validating approved uncommitted edits. The builder retains identity/hash/version checks. Rebuild and packaging do not restart the user's runtime, reload their extension, commit, push, or publish.

The Windows development scripts remove the worker backup created by a successful staging/promotion transaction after rollback is no longer needed. They preserve older unowned backups and refuse further accumulation when a new managed backup cannot be safely retired. They do not force-close a locked runtime.

## Validation on 7 October 2026

The real migration preserved 97 build items (5,794,152,697 logical bytes) and 20 artifact items (3,875,333,753 bytes), with matching pre/post SHA manifests. A migrated acceptance profile's `-PlanOnly` output retained its original credential namespace and started no application.

A clean Windows installed-app rebuild produced 422 payload files / 589,348,961 bytes and passed the installed-app verifier. Four distinct output names completed; the fourth removed the oldest package through retention. The final build tree contained three `chrome.dll` copies and 2,288,661,481 logical bytes, within the 4 GiB ceiling, with no nonempty unregistered output. Launcher and Sidecar hashes matched across the builds. One concurrent packaging attempt exposed metadata-lock contention; bounded lock waiting was added and the build/packaging checks then passed.

Validation includes 16 lifecycle/identity tests, migration and credential fixtures, cache cold/warm/corruption checks, worker packaging, c2patool resolver/junction checks, and worker-backup locked-file/process/state protections. Full source tests, a live development restart, foreground UI acceptance, and macOS packaging were outside this validation. Raw local reports remain ignored under `acceptance-state/`; none are release publication evidence.
