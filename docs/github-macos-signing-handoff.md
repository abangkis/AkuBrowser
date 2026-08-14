# GitHub macOS signing handoff

This is the source of truth for transferring a stable macOS candidate between
the Mac builder and the primary Windows signing authority. GitHub Releases is
the transport; the existing Windows-owned draft is the only staging location.

## Security invariants

- The Ed25519 private key remains on the primary Windows machine, protected by
  DPAPI, with at most one separately encrypted offline backup.
- Neither the DPAPI seed, a plaintext seed, nor a 64-byte private key is copied
  to macOS or uploaded to GitHub.
- GitHub transport is not a trust decision. Every transfer is accepted only
  after its frozen source tuple, asset allowlist, byte counts, and SHA-256
  digests are verified.
- The public key may be transferred to macOS and pinned into the Native Host.
- Only Windows produces the final signed update manifests and signing receipt.

## Handoff checklist

### A. Mac build and signing request

- [ ] Verify the frozen AkuBrowser, AkuBridge, and AkuSidecar SHAs and clean trees.
- [ ] Build and test the universal ZIP, PKG, Sidecar update archive, checksums,
      unsigned canonical update manifests, and machine-readable provenance.
- [ ] Package only the unsigned manifests, artifact metadata, source tuple, and
      signing-request receipt as
      `AkuBrowser-<release-version>-macos-signing-request.zip`.
- [ ] Upload the Mac publishable binaries and signing-request ZIP to the existing
      Windows-owned draft. Do not upload any private key or edit release metadata.
- [ ] Read the draft back and record the GitHub asset IDs, byte counts, and digests.

### B. Windows verification and signing

- [ ] Download the signing request and referenced Mac assets from the draft with
      authenticated `gh`; do not accept files from an unrelated URL or branch.
- [ ] Match every source SHA, asset name, size, and SHA-256 digest to the frozen
      request before decrypting the key.
- [ ] Unprotect the DPAPI seed into an explicitly named temporary plaintext file.
- [ ] Sign the exact canonical manifests and verify that the derived public key
      equals `publicKeyBase64` in `runtime-update-stable-v1.json`.
- [ ] Produce the final signed manifests and a receipt that binds their SHA-256
      digests to the request asset IDs and frozen source tuple.
- [ ] Overwrite and delete the temporary plaintext key immediately after signing.
- [ ] Upload the signed manifests and receipt to the same draft, then read them
      back and compare their GitHub digests.

### C. Mac finalization and 3B

- [ ] Download the Windows signing receipt and signed manifests from the draft.
- [ ] Verify the receipt, pinned public key, manifest signatures, source tuple,
      artifact URLs, sizes, and SHA-256 digests.
- [ ] Assemble the final Mac release-kit allowlist without regenerating or
      modifying the signed manifests.
- [ ] Run macOS clean-machine 3B on the finalized candidate and return its evidence
      to Windows.

### D. Pre-publication cleanup

- [ ] Windows verifies the complete cross-platform release allowlist.
- [ ] Remove the signing-request ZIP and every unsigned manifest from the draft.
- [ ] Confirm no staging asset or private material remains before publication.

## Current tooling boundary

`run-macos-stable-gate.sh` and `build-macos-runtime-installer.sh` currently sign
inside the Mac build and therefore still require
`--update-signing-private-key`. Do not satisfy that option by copying the stable
private key to macOS. The stable Mac lane is blocked at the signing handoff until
the tooling is split into a Mac signing-request producer and a Windows finalizer.

