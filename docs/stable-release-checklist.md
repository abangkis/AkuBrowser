# Stable release checklist

This is the source of truth for publishing every stable AkuBrowser release.
Replace `<version>` and record the exact source commits before starting. Platform-specific
test detail remains in the [Windows](windows-preview-acceptance.md) and
[macOS](macos-preview-acceptance.md) acceptance documents.

## 1. Freeze the release

- [ ] Select one clean AkuBrowser, AkuBridge, and AkuSidecar source tuple.
- [ ] Confirm versions and release contracts all equal `<version>`.
- [ ] Record the three full commit SHAs in the release manifest.
- [ ] Keep existing preview tags immutable; do not merge preview binaries.

## 2. Build one cross-platform candidate

- [ ] Build Windows portable ZIP and runtime installer from the frozen tuple.
- [ ] Build macOS universal ZIP and PKG from the same frozen tuple.
- [ ] Generate checksums, artifact manifests, release manifest, and required SBOMs.
- [ ] Confirm every artifact is clean, versioned, and declares its signing/notarization state.
- [ ] If a release is intentionally unsigned, confirm the manifest, Setup copy,
      listing, installer welcome page, and release notes all say so consistently.

## 3. Accept the candidate

- [ ] Pass all automated Windows and macOS build/smoke gates.
- [ ] Pass clean-machine install, update, restart, stop/start, and uninstall tests.
- [ ] Verify Chrome Web Store identity, Native Messaging, Codex detection, and one full update run.
- [ ] Verify antivirus, SmartScreen, or Gatekeeper guidance matches the actual trust state.
- [ ] Confirm Setup download URLs and fallback instructions target `<version>`.
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
