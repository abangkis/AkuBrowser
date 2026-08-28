# AkuBrowser Privacy Policy

Last updated: 28 August 2026

AkuBrowser's single purpose is to let a user build and personalize a private AI
feed from the X, LinkedIn, Facebook, and Instagram sources that the user
explicitly enables. The v0.9.0 Windows release is an isolated
installed app distributed as one installer `.exe`; its internal Manifest V3
extension component is called AkuBridge. Chrome Web Store publication is frozen
and remains only as historical compatibility for existing users. macOS and Linux
are deferred.

## Data AkuBrowser handles

For an enabled source, AkuBrowser may handle:

- rendered feed and post text;
- displayed account names, handles, profile images, and post authors;
- post URLs, source URLs, rendered timestamps, and source identity;
- displayed images, video metadata, and media URLs;
- the user's explicit AkuBrowser feedback, source selections, and settings;
- bounded operational state needed to complete a capture or recover the local
  runtime.

These categories include website content, browsing activity limited to the
enabled source pages, and user interaction with AkuBrowser. AkuBrowser does not
request social-account passwords, authentication cookies, payment information,
health information, or private-message access.

## Consent and source access

Social-source access is optional and no social-domain permission is granted by
default. The Sidecar-owned app shell initially suggests the supported sources,
prominently explains the data handled, and requires the user to confirm the
selection before the bundled Chromium profile shows its permission request for
the selected domains. AkuBrowser registers source content scripts only after
the user grants that permission.

The user may return to the app shell and revoke one or all source permissions.
Revocation unregisters that source's persistent content scripts. AkuBrowser
rejects capture commands for a source whose bundled-Chromium host permission is
not currently granted.

## How data is used

AkuBrowser uses source data only to:

- capture the user-requested source feed;
- evaluate, organize, deduplicate, and present items in the local AkuBrowser
  timeline;
- personalize selection using the user's explicit feedback;
- provide AI assessment and event grouping selected by the user;
- maintain security, compatibility, reliability, and bounded recovery of those
  features.

AkuBrowser does not use source data for advertising, credit decisions, data
brokerage, or an unrelated purpose.

## Storage and retention

The installed AkuBrowser app stores the timeline, settings, feedback, and
operational history in a local SQLite database under the current Windows user's
AkuBrowser data directory. The active release uses schema 10 and the user
chooses a 30, 60, or 90 day retention boundary and a bounded storage cap.

The bundled AkuBridge extension stores only bounded local operational state in
the app-shell profile. X post-media URL evidence expires after 30 minutes by
default; X avatar URL evidence expires after seven days by default. Runtime
status, source-permission state, and short-lived capture coordination are also
stored in its local extension storage.

Uninstalling or repairing the installed app intentionally preserves the separate
AkuBrowser data directory. The user can delete durable product data through
AkuBrowser's full-reset control, or after stopping AkuBrowser by removing the
local AkuBrowser data directory. The app-shell profile and bundled extension
state are owned by the installed application and are not a system Chrome
profile.

## Transfers and third parties

AkuBridge sends captured source data only to the AkuBrowser Sidecar on the same
device through an authenticated loopback connection. The AkuBrowser project
does not operate a developer server that receives the captured social content.

When the user runs AI-backed features, the local runtime may submit selected
content and a bounded task prompt to OpenAI through the user's signed-in Codex
App/App Server. Codex App/App Server is an external prerequisite. If the user
selects the optional Gemini provider, selected content is sent to that provider
using the user-supplied key stored by the Sidecar credential flow; provider
handling is governed by the provider's terms and privacy settings. Provider
hot-swaps apply at an idle boundary. AkuBrowser does not send captured source
data to GitHub. GitHub hosts project pages and, after release approval, the one
Windows installer and its checksum. The v0.9.0 unsigned/SmartScreen
state is disclosed before download. Installer/update requests contain no
captured social content, prompts, feedback, credentials, or AkuBrowser database
data.

AkuBrowser does not sell user data. AkuBrowser does not transfer user data to
advertising platforms or data brokers. No project contributor reads captured
user data unless the user deliberately supplies specific diagnostic material
for support, or access is required by law or for a security investigation.

## Security

The installed app contains the reviewed AkuBridge payload and does not load
remote JavaScript. Source access is domain-specific and optional. Native runtime
messages, if retained for transitional compatibility, are accepted only through
the registered AkuBrowser host and contain bounded lifecycle data, not captured
social content or credentials. The local web API binds to loopback and requires
an instance-scoped Bridge token for privileged operations.

## Historical Chrome Web Store Limited Use

For the frozen Chrome Web Store listing and existing users, the use of
information received from Google APIs adheres to the Chrome Web Store User Data
Policy, including the Limited Use requirements. This section is retained for
historical compatibility; the v0.9.0 Windows installer is not published through
the Store.

AkuBrowser limits use of user data to providing or improving its disclosed
single purpose, does not use or transfer it for personalized advertising, and
does not permit human access except where the user gives explicit consent for
support, where necessary for security, or where required by law.

## Contact and changes

Support and privacy questions may be filed at:
https://github.com/abangkis/AkuBrowser/issues

Material changes to data handling will be prominently disclosed in AkuBrowser
and will require renewed informed consent before the changed handling begins.
