# Chrome Web Store reviewer instructions

## Product boundary

The Store item is **AkuBrowser**. The repository/internal extension component is
named AkuBridge. The extension is Manifest V3 and contains all extension logic.
It requires a separately installed, signed, user-scoped Windows companion named
**AkuBrowser Runtime** because Chrome Native Messaging hosts must be registered
by the operating system.

## Environment

- Windows 11 x64 current-user account
- Current stable Google Chrome
- Codex App installed and signed in
- Signed release asset:
  `https://github.com/abangkis/AkuBrowser/releases/latest/download/AkuBrowserRuntimeSetup.exe`
- Optional: reviewer-controlled accounts already signed in to any source being
  tested (X, LinkedIn, or Facebook)

No social credentials are supplied by or collected by AkuBrowser. The setup,
permission, runtime lifecycle, and local UI can be reviewed without enabling a
social source. Source capture requires a reviewer-controlled account for that
source.

## First-install review

1. Install AkuBrowser from the Chrome Web Store test channel.
2. Confirm the bundled setup page opens.
3. Confirm X, LinkedIn, and Facebook are unchecked and no social-domain
   permission has been granted.
4. Review the prominent disclosure, OpenAI/Codex transfer disclosure, privacy
   link, and per-source choices.
5. Click **Install AkuBrowser Runtime**, run the signed installer, return to the
   setup page, and click **Periksa lagi**.
6. Confirm **Buka AkuBrowser** appears only after the local runtime is ready.

## Consent and source review

1. Select only one source and click **Saya setuju & aktifkan**.
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
2. End `AkuSidecar.exe`, click the AkuBrowser toolbar action, and confirm the
   signed native host recovers it.
3. Use Windows Installed Apps to repair or uninstall AkuBrowser Runtime.
4. Confirm uninstall makes setup show the install-required state while product
   data remains preserved.

## Network and executable behavior

- Extension-to-runtime traffic is loopback-only on port 11122.
- Native Messaging targets only `com.akubrowser.runtime`.
- The fixed GitHub release URL is opened only by a user click; the extension
  does not use the Downloads API or silently execute the installer.
- AI-backed features may communicate with OpenAI through the reviewer's signed-in
  Codex App. This is prominently disclosed before source consent.
- There is no remotely hosted JavaScript, `eval`, or downloaded command stream.

## Release blockers

Do not submit until:

- the Store item ID is embedded in the signed companion host manifest;
- the stable installer asset exists and has a valid Authenticode signature;
- the clean-machine Stage 5 evidence is complete;
- the URLs in the listing resolve publicly.
