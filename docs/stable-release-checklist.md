# Stable release checklist

This is the source of truth for publishing every stable AkuBrowser release.
Replace `<release-version>` and `<sidecar-version>` independently and record the
exact source commits before starting. Platform-specific
test detail remains in the [Windows](windows-preview-acceptance.md) and
[macOS](macos-preview-acceptance.md) acceptance documents.

## Execution order and machine handoff

The release is coordinated from the primary Windows machine, but each platform
pass must run serially on its target environment:

- [ ] Freeze the source tuple once in Step 1.
- [ ] On Windows, complete Step 2 for Windows and Step 3A for Windows, then stop.
- [ ] Run and explicitly accept Windows Step 3B before starting any macOS pass.
- [ ] On the primary Windows machine, complete Step 3C: create the initial draft
      release and accurate release notes from the full development history.
- [ ] Hand the same frozen tuple, draft URL, Windows evidence, and public update
      key to the macOS environment.
- [ ] On macOS, verify the tuple, complete Step 2 for macOS and Step 3A for macOS,
      then stop.
- [ ] Use the [GitHub macOS signing handoff](github-macos-signing-handoff.md):
      Mac uploads a signing request to the existing draft, Windows signs it, and
      Mac verifies and finalizes the candidate. The private key stays on Windows.
- [ ] Run and explicitly accept macOS Step 3B on Intel and Apple silicon.
- [ ] Mac confirms the assets already staged by the handoff match its finalized
      kit, returns its finalizer and 3B evidence to Windows, then stops. Mac does
      not perform any post-3B GitHub mutation.
- [ ] On the primary Windows machine, reconcile that evidence and perform all of
      Steps 4 and 5 as the sole final publisher.

**Final publisher invariant:** only the primary Windows machine may remove
handoff assets, edit final release notes, create or push stable tags, publish the
draft, or promote it to Latest. macOS may upload only its pre-signing allowlist
and signing request during the handoff; successful macOS 3B is an evidence return,
not publication authority.

Do not advance a platform checkbox from another operating system. A syntax or
configuration check performed on the wrong host is only a preflight check; it is
not build, automated-acceptance, or clean-machine evidence.

## 1. Freeze the release

- [ ] Finish and commit every manifest, version, URL, identity, packaged payload,
      and user-facing installer/setup change before selecting the source tuple.
- [ ] A newer release-tooling commit may operate on the older frozen tuple only
      when `scripts/verify-release-tooling-drift.mjs` passes on both Mac and
      Windows. The artifact records both `sourceCommits` and `toolingCommits`.
      Any drift outside its narrow documentation/tooling allowlist invalidates
      the candidate; freeze is not advanced merely because tooling is newer.
- [ ] Select one clean AkuBrowser, AkuBridge, and AkuSidecar source tuple.
- [ ] Confirm `release.version` equals `<release-version>` and
      `components.akuSidecar.version` equals `<sidecar-version>`; Bridge and
      Sidecar versions need not be equal when their compatibility contract overlaps.
- [ ] Record the three full commit SHAs in the release manifest.
- [ ] Dispatch the stable workflow with separate `browser_ref`, `bridge_ref`,
      and `sidecar_ref` values. Each must be the recorded lowercase 40-character
      commit SHA; the workflow reads back and asserts every checkout's `HEAD`.
- [ ] Keep existing preview tags immutable; do not merge preview binaries.

After freeze, documentation and explicitly allowlisted release-tooling changes
do not retarget the frozen source tuple when the verifier passes. Pin the newer
tooling SHA separately and keep the release tag on the recorded frozen source
SHA. Any manifest, version, URL, identity, contract, runtime source, packaged
payload, or user-facing product/installer change invalidates the candidate and
requires a new tuple plus the affected-platform rebuild and acceptance.

## 2. Build the candidate for the current platform pass

- [ ] **Windows pass:** run the Windows stable gate once. It must create one
      release-kit root containing `publish/` and `acceptance/`, never separate
      top-level build folders that must be combined manually.
- [ ] **macOS pass:** after Windows 3B acceptance, build the macOS universal ZIP
      and PKG from the same frozen tuple on macOS.
- [ ] Generate checksums, artifact manifests, release manifest, and required SBOMs.
- [ ] Confirm every artifact is clean, versioned, and declares its signing/notarization state.
- [ ] If a release is intentionally unsigned, confirm the manifest, Setup copy,
      listing, installer welcome page, and release notes all say so consistently.

### Windows compact execution card

On the primary Windows release machine, the canonical protected runtime-update
key custody directory is `D:\data\keys\AkuBrowser`:

- `runtime-update-stable-v1.json` contains the key ID and public key metadata;
- `runtime-update-stable-v1.seed.dpapi` contains the Ed25519 seed protected with
  Windows DPAPI for the current user.

The DPAPI payload uses the fixed non-secret entropy string
`AkuBrowser runtime update stable v1`. Before the gate, confirm both files
exist, the metadata says `aku-runtime-stable-v1` / `Ed25519`, DPAPI unprotection
with that entropy succeeds as the release user, the seed and public key are each
32 bytes, and their derived public keys match. Never pass the `.dpapi` file
directly to the gate. Unprotect it only into an explicitly named temporary
plaintext file, pass that file to `-UpdateSigningPrivateKeyPath`, then overwrite
and delete it in a `finally` block. Never print, commit, upload, or retain either
key as plaintext.

Run once from AkuBrowser on the primary Windows machine:

```powershell
.\scripts\run-windows-stable-gate.ps1 `
  -ReleaseVersion <release-version> `
  -SidecarVersion <sidecar-version> `
  -BrowserSha <full-AkuBrowser-SHA> `
  -BridgeSha <full-AkuBridge-SHA> `
  -SidecarSha <full-AkuSidecar-SHA> `
  -UpdatePublicKey $env:AKU_UPDATE_PUBLIC_KEY `
  -UpdateSigningPrivateKeyPath <secure-key-path>
```

The runner must return `status: ok` and create exactly two lanes:

- `publish/` uses the production Chrome Web Store identity and is the only
  GitHub-uploadable asset directory;
- `acceptance/` contains the matching manifest-key-pinned unpacked Bridge and
  unsigned local runtime installer for Step 3B only. Never upload this lane.

The root `release-kit.json` is the authoritative asset allowlist and records
the frozen tuple, identities, hashes, and signing state. Do not assemble a
release by copying files between old artifact directories.

After the runner returns, perform release-kit QA before 3B:

- [ ] Confirm there is one final `stable-<sidecar-version>-windows/` directory
      and no `.building` directory or separate installer/portable rebuild roots.
- [ ] Confirm every `publishAssets` and `acceptanceAssets` entry exists and its
      recorded byte count and SHA-256 match the file.
- [ ] Read the generated root and acceptance READMEs. They must contain literal
      filenames, literal extension IDs, and the literal `publish/` and
      `acceptance/` lane names; reject `$(` fragments, control characters, or
      unresolved template expressions.
- [ ] Confirm the plaintext temporary signing-key file no longer exists.
- [ ] Do not hand-edit a generated kit. Fix and commit the generator, choose a
      new frozen AkuBrowser SHA, delete or archive the invalid candidate, and
      rerun the complete Windows gate.

### macOS compact execution card

Run only after Windows 3B acceptance. The Mac lane verifies the clean frozen
tuple, builds both universal artifacts in a fresh output directory, runs macOS
3A, and stops at the signing-request boundary before Windows signing. The Mac
lane never receives the update private key.

On the primary Windows machine, obtain the pinned public key from the stable key
metadata and copy only that public value to the Mac:

```powershell
$env:AKU_UPDATE_PUBLIC_KEY = (
  Get-Content -LiteralPath 'D:\data\keys\AkuBrowser\runtime-update-stable-v1.json' -Raw |
    ConvertFrom-Json
).publicKeyBase64
```

On macOS, set `AKU_UPDATE_PUBLIC_KEY` to that Base64 value. Never copy
`runtime-update-stable-v1.seed.dpapi` or a plaintext private key to macOS.

Run `scripts/run-macos-signing-request.sh` (or the compatibility entry point
`scripts/run-macos-stable-gate.sh`) with the frozen tuple and
the separately pinned `--browser-tooling-sha` plus `$AKU_UPDATE_PUBLIC_KEY`.
It creates `publish/` and `handoff/` lanes and returns
`status: awaiting_windows_signing`. Follow the [GitHub macOS signing handoff](github-macos-signing-handoff.md).
Windows runs `scripts/finalize-macos-signing-request.ps1` with the temporary
decrypted key, then Mac runs `scripts/finalize-macos-signing.sh` to verify the
receipt and produce the final kit. Stop before macOS 3B until this verification
and finalization pass succeeds.

For pre-Store 3B, keep development staging separate from publishable output:

```sh
node scripts/bridge-extension-identity.mjs \
  config/bridge-identities.json ../AkuBridge/manifest.json development
./scripts/build-macos-runtime-installer.sh \
  --output-root "artifacts/development-<sidecar-version>-macos" \
  --bridge-identity-profile development \
  --c2pa-tool ../AkuSidecar/runtime/dev/macos-universal/c2patool \
  --unsigned-local-candidate
```

Load `../AkuBridge`, install only the matching `*-unsigned-local.pkg`, then check
runtime, Codex, source login, one full update, restart, repair, and data-preserving
reinstall. Never upload the development output directory.

Upload only the Mac publishable binaries and the signing-request ZIP described
by the handoff document. After Windows signing and Mac verification, the final
allowlist includes the Sidecar-versioned PKG, stable PKG alias, schema-v2 macOS
feed, Sidecar ZIP/checksum, and signing receipt. Never upload
`*-unsigned-local.pkg`. Remove the signing request and every unsigned manifest
before publication. For an independent release, the later promotion gate
carries the frozen signed v1 feed aliases from the previous Latest without
regenerating them or copying their archives; their URLs stay pinned to the old
immutable tag.

## 3A. Automated acceptance

- [ ] Pass the automated Windows build, portable smoke, installer, updater, and
      lifecycle gates.
- [ ] Pass the automated macOS universal build, portable smoke, and installer
      structure gates, then stop at the signing-request boundary.
- [ ] Pass the Mac-to-Windows GitHub handoff: verify the signing request on
      Windows, sign with the DPAPI-protected authority, and verify the signed
      result again on Mac before macOS 3B.
- [ ] Treat GitHub portable ZIP/bundle validation as an automated 3A
      responsibility; do not repeat it as a manual clean-machine flow.
- [ ] Verify checksums, artifact manifests, source commits, Store identity, and
      declared signing/notarization state.
- [ ] Confirm Setup download URLs, fallback instructions, and security guidance
      keep ordinary bootstrap pinned to the Bridge-packaged Sidecar bootstrap
      version, which must equal `<sidecar-version>`; no Setup lane may resolve
      native code through GitHub Latest.
- [ ] Record the commands and machine-readable results used for acceptance.

Completing 3A proves that the candidate is reproducible and structurally valid.
It does not replace clean-machine acceptance.

**Mandatory stop gate:** after Windows 3A, do not start the macOS pass. Wait for
explicit Windows 3B acceptance. Apply the same stop between macOS 3A and macOS 3B.

## 3B. Clean-machine acceptance

- [ ] On Windows, execute the complete
      [Windows clean-machine Step 3B](windows-clean-machine-3b.md) runbook and
      record its pass/fail decision and non-blocking observations.
- [ ] Copy the complete `acceptance/` lane from the single Windows or macOS
      release kit to the clean machine; do not fetch a not-yet-published GitHub URL.
- [ ] Extract and Load unpacked the frozen pre-Store AkuBridge package; verify
      its manifest-key-pinned `development` identity from
      `config/bridge-identities.json` is unchanged across folders and machines.
- [ ] Confirm Setup names the local acceptance installer and does not open the
      future `v<sidecar-version>` GitHub release URL.
- [ ] Use only the matching development-identity local runtime from the same
      `acceptance/` lane; never relabel or publish it as the production installer.
- [ ] Complete runtime installation, Codex detection and sign-in confirmation,
      source consent, and one full AkuBrowser update.
- [ ] Pass Windows update/repair, Chrome restart, PC restart, stop/start,
      uninstall, and reinstall tests.
- [ ] Pass the equivalent pre-Store macOS flow on the supported Intel and
      Apple-silicon architectures using the Windows-finalized signed manifests.
- [ ] Verify the actual antivirus, SmartScreen, or Gatekeeper behavior and
      confirm the user guidance matches it.
- [ ] Do not use the portable AkuBrowser bundle or a terminal launcher as
      clean-machine acceptance evidence.
- [ ] Record that 3B validates clean-machine integration, not Chrome Web Store
      installation, production identity, or Store-managed updates.
- [ ] Preserve `release-kit.json` and the completed 3B evidence; upload only the
      files listed under its `publishAssets`, never `acceptanceAssets`.
- [ ] Obtain explicit Windows and macOS release acceptance.

## 3C. Create the Windows-owned draft

- [ ] On the primary Windows machine, confirm `v<sidecar-version>` does not
      already exist as a tag or release.
- [ ] Create one GitHub release with target set to the frozen AkuBrowser SHA,
      `draft=true`, and `prerelease=false`. Do not create or push the final tag yet.
- [ ] Write the initial title and concise release notes on Windows, where the full
      cross-repository development history is available.
- [ ] Upload only the Windows files listed by the accepted kit's `publishAssets`.
- [ ] Read the draft back and verify its target, state, notes, and Windows asset
      digests before handing its URL to macOS.
- [ ] Treat the Windows-authored title and notes as authoritative during the Mac
      pass. macOS may upload only its runner allowlist to this existing draft.

## 4. Windows-only: reconcile and stage the stable release

- [ ] Confirm this step is running from the primary Windows release checkout;
      do not continue Step 4 from macOS.
- [ ] Create the annotated `v<sidecar-version>` release tag at the frozen
      AkuBrowser authority and AkuSidecar commits. Tag AkuBridge only when the
      Store component itself advances; never relabel an unchanged Bridge version.
- [ ] Push only the selected immutable tags without moving or replacing an existing tag.
- [ ] On Windows, reconcile all Windows and macOS artifacts, checksums,
      manifests, SBOMs, and acceptance evidence against their allowlists.
- [ ] Remove the macOS signing-request ZIP and every unsigned manifest from the
      draft; confirm the final signing receipt remains and no private material
      was ever uploaded.
- [ ] Refine the Windows-authored release notes with the final cross-platform
      acceptance state; do not reconstruct them only from the Mac checkout.
- [ ] Verify GitHub asset names, sizes, digests, source commits, release target,
      release notes, `draft=true`, and `prerelease=false`.

## 5. Windows-only: publish and verify

- [ ] Confirm the primary Windows machine still owns the authenticated publisher
      session and that no Mac-side release mutation occurred after 3B.
- [ ] Confirm the Windows and macOS stable installer aliases, Sidecar archives,
      and schema-v2 feeds are all attached to `v<sidecar-version>`.
- [ ] Confirm both schema-v1 feed aliases are attached. For an independent
      release, verify they are byte-identical to previous Latest, their Ed25519
      signatures are valid, and their pinned legacy archives still exist.
- [ ] Publish the draft as the Latest stable release. The Windows workflow leaves
      `promote_latest` false by default and refuses promotion while any required
      cross-platform asset is absent.
- [ ] Download the public assets and verify their SHA-256 values again.
- [ ] Install the actual Chrome Web Store package on clean Windows and macOS
      environments with Developer Mode off and no unpacked copy enabled.
- [ ] Verify the production Store identity, versioned Setup installer URL,
      Native Messaging, Codex confirmation, source consent, and one full update.
- [ ] Confirm Store-managed extension updates and the production runtime
      compatibility contract; reverify the portable fallback through its
      automated checksums and manifests.
- [ ] Record known limitations, release URL, final digests, and acceptance evidence.
- [ ] Keep the previous stable release available for rollback.

If any required item fails, stop the release. Fix the source, select a new frozen tuple,
rebuild every affected platform artifact, and repeat acceptance before tagging stable.
