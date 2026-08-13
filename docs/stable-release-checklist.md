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
- [ ] Hand the same frozen tuple and Windows evidence to the macOS environment.
- [ ] On macOS, verify the tuple, complete Step 2 for macOS and Step 3A for macOS,
      then stop.
- [ ] Run and explicitly accept macOS Step 3B on Intel and Apple silicon.
- [ ] Return all artifacts and evidence to the primary Windows machine before
      continuing to Steps 4 and 5.

Do not advance a platform checkbox from another operating system. A syntax or
configuration check performed on the wrong host is only a preflight check; it is
not build, automated-acceptance, or clean-machine evidence.

## 1. Freeze the release

- [ ] Select one clean AkuBrowser, AkuBridge, and AkuSidecar source tuple.
- [ ] Confirm `release.version` equals `<release-version>` and
      `components.akuSidecar.version` equals `<sidecar-version>`; Bridge and
      Sidecar versions need not be equal when their compatibility contract overlaps.
- [ ] Record the three full commit SHAs in the release manifest.
- [ ] Dispatch the stable workflow with separate `browser_ref`, `bridge_ref`,
      and `sidecar_ref` values. Each must be the recorded lowercase 40-character
      commit SHA; the workflow reads back and asserts every checkout's `HEAD`.
- [ ] Keep existing preview tags immutable; do not merge preview binaries.

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

### macOS compact execution card

Run only after Windows 3B acceptance. One command verifies the clean frozen tuple,
uses a fresh output directory, builds both universal artifacts, runs every macOS
3A gate, verifies checksums/provenance, and prints machine-readable evidence:

```sh
./scripts/run-macos-stable-gate.sh \
  --release-version <release-version> \
  --sidecar-version <sidecar-version> \
  --browser-sha <full AkuBrowser SHA> \
  --bridge-sha <full AkuBridge SHA> \
  --sidecar-sha <full AkuSidecar SHA> \
  --update-public-key "$AKU_UPDATE_PUBLIC_KEY" \
  --update-signing-private-key /secure/path/runtime-update-signing-key.txt
```

Stop for explicit macOS 3B authorization after the runner returns `status: ok`.

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

After acceptance, upload only the stable runner output plus `release-manifest.json`
and the pinned C2PA SBOM. Never upload `*-unsigned-local.pkg` or a runtime-update
pair not created by this pass. Read the draft back and compare every GitHub digest.

The stable output allowlist is exactly the `assets` array printed by the runner.
It always includes the Sidecar-versioned PKG, stable PKG alias, schema-v2 macOS
feed, and Sidecar ZIP/checksum. It includes the frozen v1 pair only for an
aligned transitional release. For an independent release, the later promotion
gate carries the frozen signed v1 feed aliases from the previous Latest without
regenerating them or copying their archives; their URLs stay pinned to the old
immutable tag.

## 3A. Automated acceptance

- [ ] Pass the automated Windows build, portable smoke, installer, updater, and
      lifecycle gates.
- [ ] Pass the automated macOS universal build, portable smoke, and installer
      structure gates.
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
      Apple-silicon architectures.
- [ ] Verify the actual antivirus, SmartScreen, or Gatekeeper behavior and
      confirm the user guidance matches it.
- [ ] Do not use the portable AkuBrowser bundle or a terminal launcher as
      clean-machine acceptance evidence.
- [ ] Record that 3B validates clean-machine integration, not Chrome Web Store
      installation, production identity, or Store-managed updates.
- [ ] Preserve `release-kit.json` and the completed 3B evidence; upload only the
      files listed under its `publishAssets`, never `acceptanceAssets`.
- [ ] Obtain explicit Windows and macOS release acceptance.

## 4. Stage the stable release

- [ ] Create the annotated `v<sidecar-version>` release tag at the frozen
      AkuBrowser authority and AkuSidecar commits. Tag AkuBridge only when the
      Store component itself advances; never relabel an unchanged Bridge version.
- [ ] Push only the selected immutable tags without moving or replacing an existing tag.
- [ ] Create a draft GitHub release with `prerelease=false`.
- [ ] Upload all Windows and macOS artifacts, checksums, manifests, and SBOMs.
- [ ] Verify GitHub asset names, sizes, digests, source commits, and release notes.

## 5. Publish and verify

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
