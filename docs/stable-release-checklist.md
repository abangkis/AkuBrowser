# Stable release checklist

This is the source of truth for publishing every stable AkuBrowser release.
Replace `<version>` and record the exact source commits before starting. Platform-specific
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
- [ ] Confirm versions and release contracts all equal `<version>`.
- [ ] Record the three full commit SHAs in the release manifest.
- [ ] Keep existing preview tags immutable; do not merge preview binaries.

## 2. Build the candidate for the current platform pass

- [ ] **Windows pass:** build the Windows portable ZIP and runtime installer
      from the frozen tuple on Windows.
- [ ] **macOS pass:** after Windows 3B acceptance, build the macOS universal ZIP
      and PKG from the same frozen tuple on macOS.
- [ ] Generate checksums, artifact manifests, release manifest, and required SBOMs.
- [ ] Confirm every artifact is clean, versioned, and declares its signing/notarization state.
- [ ] If a release is intentionally unsigned, confirm the manifest, Setup copy,
      listing, installer welcome page, and release notes all say so consistently.

## 3A. Automated acceptance

- [ ] Pass the automated Windows build, portable smoke, installer, updater, and
      lifecycle gates.
- [ ] Pass the automated macOS universal build, portable smoke, and installer
      structure gates.
- [ ] Verify checksums, artifact manifests, source commits, Store identity, and
      declared signing/notarization state.
- [ ] Confirm Setup download URLs, fallback instructions, and security guidance
      target `<version>` and match the declared trust state.
- [ ] Record the commands and machine-readable results used for acceptance.

Completing 3A proves that the candidate is reproducible and structurally valid.
It does not replace clean-machine acceptance.

**Mandatory stop gate:** after Windows 3A, do not start the macOS pass. Wait for
explicit Windows 3B acceptance. Apply the same stop between macOS 3A and macOS 3B.

## 3B. Clean-machine acceptance

- [ ] Pass Windows clean-machine install, update/repair, Chrome restart, PC
      restart, stop/start, uninstall, and reinstall tests.
- [ ] Pass the equivalent macOS clean-machine flow on the supported Intel and
      Apple-silicon architectures.
- [ ] Verify the Chrome Web Store identity, Native Messaging, Codex detection,
      and one full AkuBrowser update run on both platforms.
- [ ] Verify the actual antivirus, SmartScreen, or Gatekeeper behavior and
      confirm the user guidance matches it.
- [ ] Obtain explicit Windows and macOS release acceptance.

## 4. Stage the stable release

- [ ] Create annotated `v<version>` tags at the frozen commits in all three repositories.
- [ ] Push the three tags without moving or replacing any existing tag.
- [ ] Create a draft GitHub release with `prerelease=false`.
- [ ] Upload all Windows and macOS artifacts, checksums, manifests, and SBOMs.
- [ ] Verify GitHub asset names, sizes, digests, source commits, and release notes.

## 5. Publish and verify

- [ ] Publish the draft as the Latest stable release.
- [ ] Download the public assets and verify their SHA-256 values again.
- [ ] Test the public Setup/install path and portable fallback on both platforms.
- [ ] Confirm the Chrome Web Store package and runtime compatibility contract.
- [ ] Record known limitations, release URL, final digests, and acceptance evidence.
- [ ] Keep the previous stable release available for rollback.

If any required item fails, stop the release. Fix the source, select a new frozen tuple,
rebuild every affected platform artifact, and repeat acceptance before tagging stable.
