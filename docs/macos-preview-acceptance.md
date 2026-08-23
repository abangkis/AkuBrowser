# macOS preview acceptance

AkuBrowser owns the macOS distribution boundary across the component
repositories; AkuSupervisor and AkuSupervisorConformance are not packaged.
The `v0.7.9-preview1` target contains one `macos-universal` ZIP and one
explicitly unsigned universal user-scoped `.pkg`, each carrying x64 and arm64
Sidecar slices for Intel and Apple-silicon Macs.

> **Historical preview acceptance.** This runbook validates the current
> Store/portable preview and is not the acceptance contract for the approved
> installed-app target. See the [installed-app distribution contract](installed-app-distribution-contract.md).

## Automated artifact gate

Run on a Mac from the AkuBrowser repository:

```sh
./scripts/build-macos-preview.sh --architecture universal
./scripts/test-macos-preview.sh --zip artifacts/AkuBrowser-0.7.9-macos-universal.zip
```

Without an explicit target, the builder matches the host architecture. Use
`--architecture x64` or `--architecture arm64` for focused native testing;
`--architecture universal` reproduces the published combined artifact. A
publishable build requires clean AkuBrowser, AkuSidecar, and AkuBridge source trees;
`--allow-dirty` is only for local pipeline development.

The build gate verifies the release tuple, runs AkuSidecar Go tests and
AkuBridge JavaScript checks, builds a native Go Sidecar, copies only the
verified unpacked extension payload, records source commits, generates
per-file SHA-256 checksums, and creates the portable ZIP. The smoke gate
revalidates every bundled checksum, launcher and Sidecar executable bits,
starts the bundle with a temporary database, checks Sidecar health through
both `127.0.0.1` and `localhost`, verifies fresh defaults, and loads the
embedded UI.

To test an already extracted bundle or downloaded ZIP:

```sh
./scripts/test-macos-preview.sh --artifact-directory /path/to/extracted-bundle
./scripts/test-macos-preview.sh --zip /path/to/AkuBrowser-0.7.9-macos-universal.zip
```

## Clean-machine manual gate

Test the frozen AkuBridge and runtime integration on matching Intel and
Apple-silicon hardware before Store publication. The portable ZIP is covered by
automated 3A acceptance, and this gate does not claim production Store identity.

1. start from a macOS user account with no AkuBrowser installation or database;
2. install Codex App/App Server or a compatible Codex CLI and sign in locally;
3. confirm Chrome is signed in to each source that will be enabled;
4. generate the separate kit with `scripts/build-macos-3b-acceptance-kit.sh`,
   load its generated unpacked Bridge folder, and verify its manifest-key-pinned
   `development` identity from `config/bridge-identities.json`;
5. install the matching versioned `*-unsigned-local.pkg` from the same
   `acceptance/` lane, then check the runtime and Codex prerequisites;
6. grant only the intended source permissions and complete one full AkuBrowser
   update; and
7. complete the companion lifecycle checks below without a portable ZIP,
   terminal launcher, AkuSupervisor, or development workspace. Follow the
   canonical [macOS clean-machine Step 3B](macos-clean-machine-3b.md) runbook.

Unsigned preview binaries may trigger Gatekeeper. Do not disable Gatekeeper
globally. Use the macOS security prompt, or remove quarantine only after the
ZIP checksum has been verified.

## Acceptance boundary

The preview provides a portable ZIP plus an explicitly unsigned and not
notarized user-scoped `.pkg`. Automatic AkuBridge installation, guided Codex
installation or login recovery, automatic updates, Linux packaging, and a
bundled cross-platform Supervisor remain outside the `v0.7.9-preview1`
acceptance boundary.

## 0.7.9 Chrome Web Store companion gate

The portable ZIP remains an automated fallback boundary. After publication,
the 0.7.9 macOS Store path requires clean Intel and Apple-silicon evidence for:

1. first Store install projecting `runtime_install_required`;
2. the fixed `.pkg` download opening only after a user click;
3. the Installer page and Setup both disclose that this preview package is
   unsigned and not notarized, identify the official GitHub source, require
   SHA-256 verification, and never recommend disabling Gatekeeper;
4. a Gatekeeper-blocked first open can be recovered through the per-app
   **Privacy & Security > Open Anyway** flow;
5. current-user Native Messaging registration with one exact Store origin;
6. `status`, `ensure_runtime`, `check_codex`, and `shutdown_if_idle` from Chrome;
7. Chrome restart and macOS restart recovery without a LaunchAgent;
8. universal host and Sidecar execution on both architectures;
9. versioned installer repair/update, idle handoff, activation, rollback, and
   checksum rejection; signed automatic runtime updates remain future
   hardening work;
10. repair and ordinary uninstall preserving
    `~/Library/Application Support/AkuBrowser/data`, plus explicit Full reset;
11. archive-first downgrade handling using `data/.runtime-version`, with a
    fresh database and typed **Newer data detected** fallback when bypassed;
12. portable-runtime conflict guidance; and
13. Linux showing an unavailable installer state rather than a broken link.

`scripts/test-macos-runtime-installer.sh` validates package structure and
architecture locally. It does not replace the two clean-machine install runs.

Future signed macOS packages should additionally pass Developer ID Application
and Installer signature validation, notarization, stapling, and offline ticket
verification. The current stable `v0.7.9` package intentionally remains
unsigned and uses the same checksum/Open Anyway disclosure described above.
Those future hardening gates do not describe the trust state of the immutable
`v0.7.9-preview1` asset.

## Stable release handoff

For stable releases, the primary Windows machine creates the one authoritative
GitHub draft and authors its initial release notes after Windows 3B. The Mac
operator receives that draft URL and the frozen three-repository tuple. Mac
uploads its publishable binaries plus a signing-request ZIP; Windows verifies
and signs the canonical manifests, and Mac verifies the returned signed result
before 3B. Follow the complete
[GitHub macOS signing handoff](github-macos-signing-handoff.md).
The Mac pass must not create another release or change the draft's tag, target,
title, notes, prerelease flag, or publication state.
After the Mac finalizer and clean-machine 3B pass, return the finalized release-kit
and acceptance evidence to the primary Windows machine and stop. Windows is the
sole final publisher: it reconciles the cross-platform allowlist, removes the
signing request, updates final notes, creates and pushes stable tags, publishes
the draft, and verifies Latest.

`AKU_UPDATE_PUBLIC_KEY` is the Base64 Ed25519 public key copied from the Windows
stable-key metadata property `publicKeyBase64`. It is safe to transfer to macOS.
The Windows file `runtime-update-stable-v1.seed.dpapi` is a DPAPI-protected
private seed; never copy it or any plaintext derivative to macOS, and never
upload it as a release artifact. `scripts/run-macos-signing-request.sh` now
produces the unsigned Mac handoff kit; Windows signs with
`scripts/finalize-macos-signing-request.ps1`, and Mac verifies with
`scripts/finalize-macos-signing.sh` before 3B.
