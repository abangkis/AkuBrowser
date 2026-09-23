# Release version policy

`release/release-manifest.json` is the source authority for the installed-app
product line. A GitHub prerelease tag adds the candidate suffix; the installer
and its versioned runtime currently use the three-part product version. For
example, `v0.9.0-rc.8` may contain `AkuBrowserSetup-0.9.0-windows-x64.exe`.
The manifest's `channel: stable` describes the installed-app/update channel;
GitHub's prerelease flag describes the publication state. Record both in notes.

## Before building a candidate

1. Name the intended final product line and next RC tag in the checklist.
   Keep the product line fixed across its RCs. Advancing `0.9.0` to `0.9.1`
   requires an explicit release decision after the `0.9.0` line is closed;
   a component upgrade or a new source revision alone is not that decision.
2. Check existing local and remote tags/releases. Never move or replace a
   published tag. The repository already has a `v0.9.0` release/tag, so an RC8
   cannot later be promoted by retargeting that tag. Resolve the final-release
   identity explicitly before any final publication.
3. Reconcile product, Sidecar, native host, Windows installer/asset names,
   generated runtime paths, and current docs to the product version. AkuBridge
   has its own package/Chrome versions; keep its Chrome manifest version
   monotonic for extension upgrades. Record the component version, runtime
   revision, build ID, and compatibility contract in the release manifest.
4. Run `scripts/check.ps1` and the installed-app builder/verifiers against
   clean source commits. The check pins the open product line and verifies the
   cross-repository tuple. Altering its line guard is a release decision that
   must be explained in the checklist and reviewed with the version change.
5. Keep old acceptance receipts immutable. A successful build from a new tuple
   needs new artifact hashes and a new receipt. A prerelease with open
   clean-machine or split-capture gates must say so plainly in its notes.

## Same-version RC upgrades

Multiple RCs can share the installer filename and `runtime/versions/0.9.0`
path. The installer overwrites that path and updates `runtime/current.json`
only after staging. Before claiming upgrade readiness, test install over the
prior RC with preserved data and profile, verify that the active manifest and
Bridge identity changed to the new source tuple, and verify repair/rollback.
An automated tuple check or local build does not prove this installed upgrade.

## RC8 identity

| Layer | RC8 value |
| --- | --- |
| GitHub prerelease tag | `v0.9.0-rc.8` |
| AkuBrowser installed app and AkuSidecar | `0.9.0` |
| AkuBridge package / Chrome manifest | `0.9.2` / `0.9.2.0` |
| Bridge runtime revision | `source-adapters-v111` |
| Windows installer | `AkuBrowserSetup-0.9.0-windows-x64.exe` |

Do not edit this table to imply that a historical `0.9.1` development canary
was tested as RC8. Freeze and record the actual three source SHAs and artifact
SHA-256 after the candidate build succeeds.

## RC9 identity

RC9 keeps the same product and component versions as RC8. Its installed
Launcher and Sidecar binaries have the same SHA-256 as RC8; the new commit
records development recovery guidance and acceptance evidence. The published
prerelease tag is `v0.9.0-rc.9`, with installer
`AkuBrowserSetup-0.9.0-windows-x64.exe` at SHA-256
`eb251704166d0e8261549794090adfbc507a6ea7ecf66fe9e0ff28c83ef94cd2`.
The frozen source commits and remaining acceptance gates are recorded in the
[RC9 receipt](../acceptance/windows-installed-app-rc9-2026-09-23.md).
