# Chrome Web Store reviewer instructions

## Product boundary

The Store item is **AkuBrowser**. The repository/internal extension component is
named AkuBridge. The extension is Manifest V3 and contains all extension logic.
It requires a separately installed, user-scoped Windows or macOS companion
named **AkuBrowser Runtime** because Chrome Native Messaging hosts must be
registered by the operating system. Linux is intentionally unavailable in
0.7.9. The Windows Early Preview signature state and the macOS Preview 1
unsigned/not-notarized trust state are disclosed before installation. A future
stable macOS package remains subject to Developer ID and notarization gates.

## Environment

- Windows 11 x64 or macOS Intel/Apple-silicon current-user account
- Current stable Google Chrome
- Codex App installed and signed in
- Official unsigned Early Preview asset:
  `https://github.com/abangkis/AkuBrowser/releases/latest/download/AkuBrowserRuntimeSetup.exe`
- Official macOS Preview 1 asset (unsigned and not notarized):
  `https://github.com/abangkis/AkuBrowser/releases/download/v0.7.9-preview1/AkuBrowserRuntimeSetup-0.7.9-macos-universal-unsigned.pkg`
- Manual fallback asset pattern:
  `https://github.com/abangkis/AkuBrowser/releases/download/v<version>/AkuBrowser-<version>-windows-x64.zip`
- macOS fallback pattern:
  `https://github.com/abangkis/AkuBrowser/releases/download/v<version>/AkuBrowser-<version>-macos-universal.zip`
- Optional: reviewer-controlled accounts already signed in to any source being
  tested (X, LinkedIn, or Facebook)

No social credentials are supplied by or collected by AkuBrowser. The setup,
permission, runtime lifecycle, and local UI can be reviewed without enabling a
social source. Source capture requires a reviewer-controlled account for that
source.

## First-install review

1. Install AkuBrowser from the Chrome Web Store test channel.
2. Confirm the bundled setup page opens.
3. Confirm X, LinkedIn, and Facebook are initially suggested, but no
   social-domain permission has been granted.
4. Review the prominent disclosure, OpenAI/Codex transfer disclosure, privacy
   link, and per-source choices.
5. Confirm Setup shows **Not checked** and does not contact the native host until
   **Check runtime** is clicked. After the check reports **Not installed**, click
   **Install runtime**, run the disclosed platform installer,
   return to Setup, and click
   **Check runtime** again.
6. If the compatible runtime is stopped, click **Run AkuBrowser** and confirm the
   status changes to **Running** while the action becomes **Stop runtime**.
   Select **Stop runtime** while idle and confirm the control returns to
   **Run AkuBrowser**.
   If Setup detects a portable runtime instead, confirm it says
   **Portable runtime running**, instructs the reviewer to stop it manually,
   and offers **Check after stopping** rather than automatic Stop.
7. Confirm **Open AkuBrowser** appears only after the local runtime is running.
8. On Windows, confirm the security notice is shown for install, update, and
   failure states and never instructs the reviewer to disable antivirus
   protection. On macOS, confirm Setup discloses that the package is unsigned
   and not notarized, points to checksum verification, uses the standard
   Installer flow, and describes only the per-app **Privacy & Security > Open
   Anyway** recovery when Gatekeeper blocks the first open. It must never
   recommend disabling Gatekeeper globally.

## Consent and source review

1. Select only one source and click **I agree & enable**.
2. Confirm Chrome requests only that source's exact domain.
3. Confirm the setup status lists only that source.
4. Open the extension options page, uncheck the source, and save.
5. Confirm the permission is removed and a later capture for that source fails
   visibly as `source_permission_required`.

Repeat with another source if desired. The extension never asks for social
passwords, cookies, private messages, or all-sites access.

## Lifecycle review

1. Close all Chrome windows and reopen Chrome; the registered host should
   reconcile the runtime without a terminal.
2. End `AkuSidecar.exe` on Windows or `AkuSidecar` on macOS, click the AkuBrowser toolbar action, and confirm the
   registered native host recovers it.
3. Use Windows Installed Apps on Windows, or the packaged macOS uninstall
   command, to remove AkuBrowser Runtime.
4. Confirm uninstall makes setup show the install-required state while product
   data remains preserved.

## Network and executable behavior

- Extension-to-runtime traffic is loopback-only on port 11122.
- Native Messaging targets only `com.akubrowser.runtime`.
- The fixed GitHub installer URL and matching versioned portable-fallback URL
  are opened only by a user click; the extension does not use the Downloads API
  or silently execute either artifact.
- The current preview updates the native runtime through an explicit user-run
  installer from the fixed official AkuBrowser GitHub Releases origin. The
  extension never downloads or executes the installer silently.
- AI-backed features may communicate with OpenAI through the reviewer's signed-in
  Codex App. This is prominently disclosed before source consent.
- There is no remotely hosted JavaScript, `eval`, or downloaded command stream.

## Release blockers

Do not submit until:

- the Store item ID is embedded in the companion host manifest;
- both reviewed installer assets exist, their SHA-256 values are published, and
  the Windows and macOS preview disclosures match Setup and the listing;
- the clean-machine Stage 5 evidence is complete;
- the URLs in the listing resolve publicly.

Developer ID signing, notarization, and stapling are blockers for a future
stable macOS asset, not claims made for `v0.7.9-preview1`.
