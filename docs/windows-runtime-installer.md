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
upgrade, and uninstall never place that directory under the replaceable program
root.

## Trust boundary

The Chrome Web Store extension ID is a mandatory build input. It is written as
one exact `chrome-extension://<id>/` origin. Wildcards and placeholder IDs are
rejected for production inputs.

Every embedded file has a size and SHA-256 entry in
`payload-manifest.json`. The installer verifies the entire embedded payload
before writing anything. Runtime files are written through same-directory
temporary files; `runtime\current.json` is activated last.

The host executable, Sidecar executable, c2patool executable, internal
maintenance engine, setup wizard, and generated uninstaller are
Authenticode-signed before release. The signing command uses SHA-256 plus an RFC
3161 SHA-256 timestamp. Production builds fail when neither a PFX nor a
certificate-store thumbprint is supplied.

NSIS 3.12 compiles the outer wizard. The build locates `makensis.exe` from
`PATH`, its standard installation folders, or the explicit `-NsisPath` value.
NSIS is used only for the Windows UI and uninstall shell; the Go maintenance
engine remains authoritative for payload verification, atomic activation, and
Native Messaging Host registration.

## Local candidate

An unsigned candidate is deliberately named `*-unsigned-local.exe`:

```powershell
.\scripts\build-windows-runtime-installer.ps1 `
  -ExtensionId aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa `
  -UnsignedLocalCandidate `
  -AllowDirty
```

This mode validates staging and installer behavior. It is not publishable and
must never be linked from the Store extension.

## Signed production build

```powershell
$env:AKU_WINDOWS_SIGNING_PASSWORD = "<PFX password>"
.\scripts\build-windows-runtime-installer.ps1 `
  -CertificatePath "C:\secure\akubrowser-code-signing.pfx"
```

Production builds read the exact Chrome Web Store extension ID from
`release/release-manifest.json`; supplying a different ID is rejected. An
unsigned development candidate may still pass `-ExtensionId` explicitly for
one exact unpacked-extension origin.

The GitHub Actions workflow
`.github/workflows/windows-runtime-installer.yml` performs the same build using
encrypted repository secrets:

- `AKU_WORKSPACE_READ_TOKEN`;
- `WINDOWS_CODE_SIGNING_PFX_BASE64`;
- `WINDOWS_CODE_SIGNING_PFX_PASSWORD`.

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
first. Locked executable files are scheduled for deletion at reboot. User data
is preserved.
