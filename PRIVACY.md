# AkuBrowser Privacy Policy

Last updated: 7 August 2026

AkuBrowser's single purpose is to let a user build and personalize a private AI
feed from the X, LinkedIn, and Facebook sources that the user explicitly
enables. The public Chrome extension is named **AkuBrowser**; its internal
extension component is called AkuBridge.

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
default. The setup page initially suggests the supported sources, prominently
explains the data handled, and requires the user to confirm the selection before
Chrome shows its own permission request for the selected domains. AkuBrowser
registers source content scripts only after Chrome grants that permission.

The user may return to the extension's options page and revoke one or all source
permissions. Revocation unregisters that source's persistent content scripts.
AkuBrowser rejects capture commands for a source whose Chrome host permission is
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

The AkuBrowser companion runtime stores the timeline, settings, feedback, and
operational history in a local SQLite database under the current Windows user's
AkuBrowser data directory. The user chooses a 30, 60, or 90 day retention
boundary and a bounded storage cap.

The Chrome extension stores only bounded local operational state. X post-media
URL evidence expires after 30 minutes by default; X avatar URL evidence expires
after seven days by default. Runtime status, source-permission state, and
short-lived capture coordination are also stored in `chrome.storage.local`.

Uninstalling the Chrome extension clears Chrome-managed extension storage.
Uninstalling or repairing the companion runtime intentionally preserves the
separate AkuBrowser data directory. The user can delete durable product data
through AkuBrowser's full-reset control, or after stopping AkuBrowser by removing
the local AkuBrowser data directory.

## Transfers and third parties

The Chrome extension sends captured source data only to the AkuBrowser runtime
on the same device through an authenticated loopback connection. The AkuBrowser
project does not operate a developer server that receives the captured social
content.

When the user runs AI-backed features, the local runtime may submit selected
content and a bounded task prompt to OpenAI through the user's signed-in Codex
App/App Server. OpenAI's handling of that data is governed by the terms and
privacy settings applicable to the user's OpenAI/Codex account. The extension
does not send captured source data to GitHub. GitHub hosts the project pages,
and the user-initiated companion installer. The current Early Preview installer
is unsigned and is disclosed as such before download. Preview runtime updates
use the same explicit user-run installer flow from the fixed official
AkuBrowser GitHub Releases location. Those requests contain no captured social
content, prompts, feedback, credentials, or AkuBrowser database data.

AkuBrowser does not sell user data. AkuBrowser does not transfer user data to
advertising platforms or data brokers. No project contributor reads captured
user data unless the user deliberately supplies specific diagnostic material
for support, or access is required by law or for a security investigation.

## Security

The extension contains all extension-side executable logic in its reviewed
Chrome Web Store package. It does not load remote JavaScript. Source access is
domain-specific and optional. Native runtime messages are accepted only through
the registered AkuBrowser host and contain bounded lifecycle data, not captured
social content or credentials. The local web API binds to loopback and requires
an instance-scoped Bridge token for privileged operations.

## Chrome Web Store Limited Use

The use of information received from Google APIs will adhere to the Chrome Web
Store User Data Policy, including the Limited Use requirements.

AkuBrowser limits use of user data to providing or improving its disclosed
single purpose, does not use or transfer it for personalized advertising, and
does not permit human access except where the user gives explicit consent for
support, where necessary for security, or where required by law.

## Contact and changes

Support and privacy questions may be filed at:
https://github.com/abangkis/AkuBrowser/issues

Material changes to data handling will be prominently disclosed in AkuBrowser
and will require renewed informed consent before the changed handling begins.
