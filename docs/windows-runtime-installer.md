# AkuBrowser Runtime Windows installer

Status: Stage 4 implementation, 28 July 2026.

## Outcome

`AkuBrowserRuntimeSetup.exe` is a self-contained, user-scoped Windows setup
wizard. It embeds the exact compatible AkuBrowser Runtime payload, requires no
administrator access, and presents the normal Windows flow: Welcome, selectable
installation folder, installation progress, Cancel, and Finish. Windows
Installed Apps receives a matching graphical uninstaller.

The installer owns:

- `%LOCALAPPDATA%\Programs\AkuBrowser\host\AkuBrowserRuntimeHost.exe`;
- the adjacent `com.akubrowser.runtime.json`;
- versioned Sidecar payloads under `runtime\versions\<version>`;
- `runtime\current.json`;
- the HKCU Chrome Native Messaging registration;
- the HKCU Windows uninstall registration.

Product data remains under `%LOCALAPPDATA%\AkuBrowser\data`. Install, repair,
and upgrade never place that directory under the replaceable program root. A
normal uninstall preserves it; the graphical uninstaller also offers an
explicit **Full reset** that permanently removes data and downgrade archives.

## Trust boundary

The build selects a named Bridge identity from
`config/bridge-identities.json`. Its exact ID is written as one
`chrome-extension://<id>/` origin. Wildcards, placeholder IDs, and arbitrary
extension-ID inputs are rejected.

Every embedded file has a size and SHA-256 entry in
`payload-manifest.json`. NSIS enforces its archive CRC before and during direct
extraction, while the manifest remains packaged as the installed provenance
record. `runtime\current.json` is extracted last so an interrupted extraction
cannot activate an incomplete runtime version.

The future signed production path signs the host executable, Sidecar
executable, c2patool executable, setup wizard, and generated uninstaller with
Authenticode using SHA-256 plus an RFC 3161 SHA-256 timestamp. The `v0.7.9`
stable release deliberately uses an unsigned installer; Windows Security,
SmartScreen, or antivirus may warn or quarantine it. The release manifest and
Setup page disclose this trust state.

NSIS 3.12 compiles the outer wizard. The build locates `makensis.exe` from
`PATH`, its standard installation folders, or the explicit `-NsisPath` value.
NSIS owns the Windows UI, direct payload extraction, HKCU Native Messaging Host
registration, and uninstall shell. It does not launch a nested installer or
maintenance executable. The host, Sidecar, and C2PA executables are extracted
as inert program files; `runtime\current.json` is written only after all other
payload files succeed. This avoids the unsigned-child-process pattern that
antivirus sandboxing can terminate while preserving last-step activation.

## Local candidate

An unsigned local candidate is deliberately named `*-unsigned-local.exe`:

```powershell
.\scripts\build-windows-runtime-installer.ps1 `
  -BridgeIdentityProfile development `
  -UnsignedLocalCandidate `
  -AllowDirty
```

This mode validates staging and installer behavior. It is not publishable and
must never be linked from the Store extension.

The stable unsigned candidate uses the production Store identity and the stable
runtime channel. Do not build it as a standalone release folder; use the unified
Windows stable gate documented in `docs/stable-release-checklist.md`:

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

The `publish/` lane contains the versioned installer and documented stable
alias. The `acceptance/` lane contains a differently named development-identity
installer plus the exact unpacked Bridge for Step 3B. This is a deliberate
unsigned release exception, not evidence of a signed publisher identity.

## Signed production build

```powershell
$env:AKU_WINDOWS_SIGNING_PASSWORD = "<PFX password>"
.\scripts\build-windows-runtime-installer.ps1 `
  -CertificatePath "C:\secure\akubrowser-code-signing.pfx" `
  -UpdatePublicKey "<base64 Ed25519 public key>" `
  -UpdateSigningPrivateKeyPath "C:\secure\akubrowser-runtime-update.key"
```

Production builds read the profile selected by
`release/release-manifest.json`, then resolve its exact Chrome Web Store ID
from `config/bridge-identities.json`. Production rejects a different profile.
An unsigned development candidate may select the declared `development`
profile, but cannot supply an arbitrary ID. The checked-in Sidecar base
configuration contains no trusted origin; the installer generates its packaged
allowlist from the selected registry profile. See
[Bridge identity contract](bridge-identity-contract.md).

The GitHub Actions workflow
`.github/workflows/windows-runtime-installer.yml` performs the same build using
encrypted repository secrets:

- `AKU_WORKSPACE_READ_TOKEN`;
- `WINDOWS_CODE_SIGNING_PFX_BASE64`;
- `WINDOWS_CODE_SIGNING_PFX_PASSWORD`;
- `RUNTIME_UPDATE_PUBLIC_KEY_BASE64`; and
- `RUNTIME_UPDATE_SIGNING_PRIVATE_KEY_BASE64`.

The workflow downloads the pinned c2patool release, verifies its existing
SHA-256, signs every native executable, verifies the final Authenticode
signature, pins the Ed25519 runtime-update public key into the native host, and
publishes the installer plus the signed update manifest and versioned runtime
ZIP on an explicitly selected existing GitHub release. The stable installer
asset is the target linked by the Store extension.

## Install, update, and uninstall

- Double-click Setup, choose the program folder, and select Install.
- Rerun a newer Setup to update or repair the installed runtime in place.
- Use Windows Installed Apps to launch the graphical uninstaller.
- Setup keeps the previous selected program folder, while the extension remains
  the normal place to check, update, run, and stop the runtime.

Uninstall removes the Chrome Native Messaging and Installed Apps registrations
first. Locked executable files are scheduled for deletion at reboot. The
default **Preserve data** choice keeps user data for reinstall; **Full reset**
removes the database, downgrade archives, and receipt.

Every successful install records the writing runtime in
`%LOCALAPPDATA%\AkuBrowser\data\.runtime-version`. If Setup finds a newer writer
version than the installer, it must not open that database with the older
runtime. Interactive Setup asks whether to archive the newer data and create a
fresh database; declining aborts without changing data. Acceptance moves the
directory under `data-backups\pre-downgrade-*` and records
`downgrade-receipt.txt`. Silent downgrade defaults to abort. If installation is
bypassed, the Native Messaging Host reports a typed `data_version_incompatible`
error so Setup shows **Newer data detected** rather than retrying indefinitely.
