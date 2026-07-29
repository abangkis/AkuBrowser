# Signed Windows runtime updater

Status: Stage 7 implementation, 29 July 2026.

## Outcome

The installed Native Messaging host now reconciles a newer exact extension
compatibility tuple through a signed runtime update. The extension still sends
only `ensure_runtime`; it cannot provide a URL, checksum, key, path, command, or
channel.

The host reads one compiled-in manifest URL:

`https://github.com/abangkis/AkuBrowser/releases/latest/download/AkuBrowserRuntimeUpdate.json`

The manifest is strict JSON and is authenticated with an Ed25519 public key
pinned into the Authenticode-signed host at production build time. It binds the
target version, runtime revision, Bridge contract, stable channel, publication
time, exact release artifact URL, byte size, and SHA-256.
Its dashboard-independent shape is recorded in
`contracts/runtime-update-manifest.schema.json`.

This does not change the existing portable-preview channel or its ZIP
deployment path. Only a signed production companion installer writes the
`stable` runtime channel and enables this updater trust chain.

## Update sequence

1. A Store extension update calls `ensure_runtime` with its exact tuple.
2. The host fetches and verifies the bounded signed manifest.
3. It downloads the bounded Windows x64 ZIP from the exact AkuBrowser GitHub
   release path and verifies its byte count and SHA-256.
4. It rejects traversal, duplicate, oversized, undeclared, or hash-mismatched
   archive entries and extracts into `runtime\candidates`.
5. The candidate `AkuSidecar.exe` runs `-runtime-candidate-probe`, validating
   its packaged configuration, version, runtime, and Bridge contract without
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

The release publishes:

- `AkuBrowserRuntimeSetup.exe`;
- `AkuBrowserRuntime-<version>-windows-x64.zip`;
- `AkuBrowserRuntimeUpdate.json`.

The selected release tag must exactly equal `v<version>` because the signed
artifact URL is version-bound.

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
