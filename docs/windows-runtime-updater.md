# Signed AkuSidecar updater for Windows

Status: Stage 7 implementation, 29 July 2026.

> **Historical Sidecar-only updater contract — superseded for target
> production.** This document records the current Native Messaging and
> companion-runtime updater. The approved target updates a complete signed
> AkuBrowser tuple and rolls back the whole tuple atomically; see the
> [installed-app distribution contract](installed-app-distribution-contract.md).
> Binary/delta patching is not part of that target yet.

## Outcome

AkuBridge and AkuSidecar update independently. Chrome Web Store owns Bridge
updates; AkuSidecar discovers its signed platform feed and applies a verified
candidate only through the internal Native Messaging host shipped by the
Sidecar installer. The host is a short-lived launch/update helper, not a third
product, and AkuSupervisor has no production role.

Current hosts prefer the schema-v2 Windows feed:

`https://github.com/abangkis/AkuBrowser/releases/latest/download/AkuSidecarUpdate.json`

During migration, old hosts continue to read the separately signed schema-v1
feed:

`https://github.com/abangkis/AkuBrowser/releases/latest/download/AkuBrowserRuntimeUpdate.json`

The v2 manifest is strict JSON authenticated with the same pinned Ed25519 key.
It binds `sidecarVersion` independently from the Store extension version,
runtime revision, minimum host version, Bridge protocol range and required
capabilities, database schema range and rollback safety, optional urgency and
deadline, and one exact platform artifact. Its shape is
`contracts/runtime-update-manifest.schema.json`. The frozen v1 shape is
`contracts/runtime-update-manifest-v1.schema.json`; never add v2 fields to it,
because deployed v1 hosts reject unknown fields.

The Bridge tries native protocol v2 first and falls back once to the exact v1
message shape. A valid v1 response keeps a compatible running Sidecar usable,
but is persisted as `hostUpgradeRequired`; the popup and Setup offer one
installer refresh so the internal host can join the independent v2 update
lane. The host executable is never replaced by a Sidecar ZIP. The installer is
therefore the explicit, signed bootstrap boundary for this one-time migration.
If a verified v2 feed requires a newer host, `host_upgrade_required` preserves
the signed manifest's `sidecarVersion` as `update.targetVersion`; Setup may then
offer only the matching versioned installer asset. Ordinary bootstrap and
repair continue to use the static Bridge-packaged companion version.
Sidecar candidate probing follows the same overlap rule: an old host receives
the frozen five-field probe, while a v2 host explicitly requests probe schema
2 with `databaseSchemaVersion`.

This does not change the existing portable-preview channel or its ZIP
deployment path. Only a signed production companion installer writes the
`stable` runtime channel and enables this updater trust chain.

## Update sequence

1. Bridge calls `ensure_runtime` with its version, protocol, and capabilities.
2. The host fetches and verifies v2, falling back to the legacy v1 feed only
   during the transition window.
3. It checks host, Bridge, and database compatibility before downloading the
   bounded Windows x64 ZIP from the exact AkuBrowser GitHub
   release path and verifies its byte count and SHA-256.
4. It rejects traversal, duplicate, oversized, undeclared, or hash-mismatched
   archive entries and extracts into `runtime\candidates`.
5. The candidate `AkuSidecar.exe` runs `-runtime-candidate-probe
   -runtime-candidate-probe-schema 2`, validating its packaged configuration,
   version, runtime, Bridge contract, and database compatibility without
   opening the user's database.
6. The active Sidecar must report `idle` through
   `/api/runtime/update-readiness`. Any session or background worker blocks the
   replacement.
7. A separate 256-bit instance control token authorizes
   `/api/runtime/shutdown-if-idle`. The token is generated and stored locally
   by the host, passed only to Sidecar, and never enters Native Messaging.
8. After the old endpoint stops, the candidate directory moves into the
   version store, the prior metadata is persisted separately, and
   `current.json` is replaced atomically.
9. The activated runtime must return the exact health tuple. Failure restores
   the previous `current.json`, restarts the known-good runtime, and removes the
   failed candidate.
10. A same-version confirmation marker is written only after that health gate.
    If the short-lived host exits between pointer replacement and confirmation,
    the next `ensure_runtime` either confirms the exact healthy tuple or
    automatically executes the persisted rollback.
11. Successful cleanup keeps only the active and one rollback version. A
    bounded JSONL audit records time, versions, phase, and typed error code
    without paths, content, credentials, prompts, or database data.

`status` may report a running contract-compatible runtime together with
`currentVersion` and `targetVersion`; the runtime remains usable while Setup
offers **Update runtime**. `shutdown_if_idle` does not require an exact release
tuple because the installed runtime's private control token proves ownership.
This exception grants no authority over portable runtimes: a loopback-only
portable process has no installed-host control token and must be stopped
manually.

## Release signing

Production builds require two independent trust inputs:

- an Authenticode certificate for the installer, host, Sidecar, and native
  binaries;
- an Ed25519 private key for the update manifest, with the matching public key
  pinned into the host through the build.

The private Ed25519 key is never embedded or uploaded as an artifact. GitHub
Actions restores it temporarily from
`RUNTIME_UPDATE_SIGNING_PRIVATE_KEY_BASE64`, derives its public key while
signing, and fails if that key differs from
`RUNTIME_UPDATE_PUBLIC_KEY_BASE64`.

The release publishes the current feed:

- `AkuBrowserRuntimeSetup.exe`;
- `AkuBrowserRuntimeSetup-<sidecarVersion>.exe` and its checksum for every
  Bridge-pinned bootstrap or host-refresh request;
- `AkuSidecar-<sidecarVersion>-windows-x64.zip`;
- `AkuSidecarUpdate.json`.

For an aligned transitional release, the same payload is also published under
`AkuBrowserRuntime-<releaseVersion>-windows-x64.zip` with the separately signed
`AkuBrowserRuntimeUpdate.json`. That v1 pair is valid only for releases where
the legacy Bridge/runtime tuple remains aligned; it is a compatibility lane,
not the model for future Sidecar-only releases. When an independent release is
promoted, the workflow instead copies both frozen signed v1 feed aliases
byte-for-byte from the previous Latest release and verifies their Ed25519
signatures. Their artifact URLs remain pinned to the old immutable release tag,
so the old archives are not copied; promotion verifies that each referenced
archive still exists.

The selected release tag must exactly equal `v<sidecarVersion>` because the v2
artifact URL is Sidecar-version-bound. An aligned transitional v1 feed uses the
same tag because all component versions are equal in that lane.
The Windows workflow uploads its platform assets but leaves `promote_latest`
false by default. Promotion is an explicit finalization action and fails unless
the matching Windows and macOS installer aliases, Sidecar archives, and v2 feeds
are already attached to the tag and both current-or-carried v1 feed aliases pass
verification. Only then does it mark the tag as GitHub's
latest release; installed clients and stable installer aliases resolve through
`/releases/latest/download/...` without exposing a partial platform rollout.

## Key generation and rotation

Generate an Ed25519 seed in an offline administrative environment. Store the
base64 seed and derived base64 public key in separate protected secret stores.
Never commit either the seed or the 64-byte private key.

The current manifest uses key ID `aku-runtime-stable-v1`. Rotation requires a
host/installer release that pins the next public key before manifests begin
using the next key ID. Losing the private key requires an installer repair or
upgrade; the updater must never accept an unsigned emergency manifest.

## Validation

Run:

```powershell
.\scripts\test-windows-runtime-updater.ps1
```

The suite covers signature tampering, downgrade and origin rejection, archive
traversal and undeclared files, busy-runtime deferral, healthy activation,
failed-candidate rollback, Sidecar readiness, and release-signing tooling.

Production evidence additionally requires an upgrade from the previously
supported signed release on a clean Windows VM. Record the old and new
`current.json` versions, signed asset hashes, setup-page state, and bounded
update audit. Do not include the control token, local paths, user data, or
captured source content.
