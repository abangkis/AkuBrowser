# Chrome Store distribution contract

Status: implemented distribution authority, 31 July 2026. Publication frozen
27 August 2026.

> **Historical shipped-state contract — publication frozen.**
> Chrome Web Store publication of AkuBrowser is frozen: no further Store
> builds are submitted, and all future production releases ship through the
> single installed-app tuple in the
> [installed-app distribution contract](installed-app-distribution-contract.md).
> This document preserves the Chrome Web Store plus companion-runtime design
> that shipped artifacts implement and remains useful historical evidence for
> the migration; it is not the forward-looking distribution authority.
> Legacy setup-surface removal is tracked in the
> [setup retirement plan](setup-retirement-plan.md).

## Decision

The public Chrome Web Store product is **AkuBrowser**. `AkuBridge` remains the
internal extension component and repository name. Existing Bridge IDs,
`aku-browser.bridge.v2`, source-adapter contracts, and capture behavior do not
change merely because the public display name changes.

Chrome Web Store distribution owns installation and updates of the Manifest V3
extension. The user installs AkuSidecar once through its platform companion
installer because Chrome cannot create Native Messaging registration. The
installer includes a small **AkuBrowser Runtime Host** for bootstrap and update
handoff; that host is internal machinery, not a third deployed product.

The portable GitHub ZIP remains a supported technical-user and recovery path.
It is not removed by the Store distribution path.

## External platform constraints

The design depends on these official Chrome boundaries:

- [Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)
  requires an OS-registered native host and an exact extension origin.
- [Manifest V3 requirements](https://developer.chrome.com/docs/webstore/program-policies/mv3-requirements)
  require extension logic to remain discernible in the submitted package and
  prohibit remote hosted executable logic.
- [Extension update lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/extensions-update-lifecycle)
  gives Chrome Web Store authority over extension updates and requires the
  extension to become idle before an update is installed.
- [Extension service-worker lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle)
  provides `onInstalled` and `onStartup` but does not guarantee a permanently
  running worker.
- [Downloads API](https://developer.chrome.com/docs/extensions/reference/api/downloads)
  permits opening a downloaded installer only in response to a user gesture.

## Components and authority

| Component | Public identity | Authority |
| --- | --- | --- |
| Chrome extension | AkuBrowser | Chrome Web Store |
| Extension implementation | AkuBridge | `AkuBridge` repository |
| Native bootstrap/update helper | AkuBrowser Runtime Host | Internal to the AkuSidecar installer |
| Native application | AkuSidecar | Signed AkuSidecar release manifest |
| Image provenance tool | c2patool | Pinned runtime release manifest |
| Product UI and local data | AkuBrowser via AkuSidecar | Loopback runtime and SQLite |

`AkuBrowser` remains the distribution authority. AkuBridge and AkuSidecar have
independent versions. Their handshake and the signed Sidecar feed define the
compatible Bridge protocol/capabilities instead of requiring equal product
versions. AkuSupervisor is outside this end-user distribution boundary.

## Fixed identities

- Public extension name: `AkuBrowser`
- Internal extension component: `AkuBridge`
- Native Messaging host: `com.akubrowser.runtime`
- Native protocol schema: `native-runtime-messaging.schema.json`
- Native protocol version: `2` (with one exact v1 migration fallback)
- Bridge contract: `aku-browser.bridge.v2`
- Loopback endpoints: `http://127.0.0.1:11122` and
  `http://localhost:11122`

The production Chrome extension ID lives only in
[`../config/bridge-identities.json`](../config/bridge-identities.json).
`release/release-manifest.json` selects the `production` profile without
repeating its value. Installer builds resolve that profile and generate the
native-host `allowed_origins` entry plus the packaged Sidecar allowlist.
Wildcards and arbitrary build-time IDs are forbidden. The checked-in Sidecar
base configuration contains no Bridge identity. Development selects the
separate `development` profile and projects its exact origin into the active
Supervisor service arguments. The complete authority and projection rules are
defined in [Bridge identity contract](bridge-identity-contract.md).

The checked-in AkuBridge manifest carries the public `development` identity.
The Store packager removes that key and projects `production-store`; the
portable packager replaces it with the dedicated public
`production-offline` key before hashing.

AkuSidecar records the browser-supplied extension origin on every heartbeat.
If two explicitly allowlisted origins remain live at the same time, Bridge
dispatch stops with guidance to disable the legacy unpacked installation. Each
source reports permission, dynamic content-script registration, and effective
readiness independently; partial access is visible and only ready sources may
enter an update.

## Installation lifecycle

### Release URL authority

Ordinary first install, missing-host recovery, and repair stay pinned to an
explicit Sidecar bootstrap version packaged into the Store Bridge. The release
gate requires that value to equal `release.components.akuSidecar.version`; it is
not inferred from the independently versioned Bridge. Legacy-host refresh uses
the same compatible pinned installer; Setup never resolves native code through
GitHub Latest.

The native runtime updater has a different responsibility: discovering a newer
published stable runtime. Its signed update-manifest endpoint intentionally
remains under `releases/latest`. Bootstrap selection and update discovery must
not share one URL policy. Latest promotion is allowed only after both platform
aliases, signed v2 feeds, Sidecar archives, and the two frozen signed v1 feed
aliases are attached. An independent release carries those v1 aliases
byte-for-byte from previous Latest; their URLs remain pinned to its immutable
legacy archives rather than being regenerated against the independent tuple.

### Store extension installed

1. Chrome installs the signed Manifest V3 extension.
2. `chrome.runtime.onInstalled` records first-install state and opens the bundled
   setup page.
3. The extension sends one `status` request to `com.akubrowser.runtime`.
4. If Chrome reports that the native host is missing, the client projects
   `runtime_install_required`; this state is not a fabricated native response.
5. The setup page presents one explicit **Install AkuBrowser Runtime** action.
6. The user downloads and runs the disclosed user-scoped installer. The
   `v0.7.9` Windows and macOS assets are explicitly unsigned and may trigger
   platform security warnings; the setup copy and release notes disclose this
   trust state. A future signed release may move to the production signing
   path.
7. The installer places the stable host executable and manifest, then registers
   the host under the current Windows user.
8. The setup page retries `status`, then sends `ensure_runtime`.
9. When the response is `ready`, the extension opens the loopback AkuBrowser UI.

The Windows security notice is shown before installation, for installer repair
or failure, and when only the compatible loopback endpoint can be confirmed. It
explains that an unsigned testing build may be warned, quarantined, blocked, or
sandboxed and never recommends disabling antivirus protection. It also explains
that Avast CyberCapture may open an isolated second Setup window. The user
completes only one Setup flow and selects **No** or **Cancel** if another window
appears. AkuBrowser never attempts to disable or reconfigure antivirus software.

If the registered native host does not answer but the version-compatible local
loopback health endpoint does, Setup reports a neutral **Runtime running** state.
It must not mislabel that process as portable or let a stale installer failure
override the healthy endpoint. A subsequent **Check native host again** remains
available for control-path verification.

If automatic setup returns `runtime_failed`, the page may expose one explicit
**Download manual Windows bundle** fallback. Its URL is derived only from the
Bridge-packaged Sidecar bootstrap version and the compiled-in official
AkuBrowser GitHub Releases origin. The fallback ZIP is never downloaded or executed
silently. It must not run concurrently with an installed or older portable
Sidecar, does not replace the registered Native Messaging Host, and must be
started manually after Windows restarts.

The extension never claims that Store installation alone installed native code.
The installer action remains visible, attributable, and user initiated.

### Chrome or PC restart

This automatic recovery applies to the Chrome Web Store distribution. The
unpacked development and offline identities suppress automatic Native Messaging
lifecycle work so reloading them cannot start the installed Store runtime.

1. Chrome starts the user's profile and fires `chrome.runtime.onStartup`.
2. The extension sends one `ensure_runtime` request.
3. Chrome starts the registered native host.
4. The host starts or reconciles the compatible AkuSidecar runtime.
5. The extension opens the UI only after a `ready` response or a successful
   loopback health check.

The runtime is not required to start before Chrome. A Windows service, Scheduled
Task, or machine-wide installation is outside the v2 lifecycle protocol.

### Extension update

This flow applies only to the Chrome Web Store distribution. Reloading or
updating the unpacked development extension performs no automatic
`ensure_runtime`; `dev.ps1` remains the development runtime authority.

1. Chrome Web Store installs the new extension while it is idle.
2. `onInstalled` with reason `update` sends the v2 `reconcile_runtime` request
   with Bridge protocol/capabilities; this starts or verifies the installed
   compatible Sidecar without forcing an update-feed check.
3. Capture dispatch remains paused until the host reports a compatible runtime.
4. If a compatible runtime is already active, ordinary Bridge operation resumes.
5. If native runtime work is needed, setup state reports `updating`, `busy`,
   `restart_required`, or a typed failure without weakening capture authority.

If a reasoning run later proves that Windows security sandboxed AkuSidecar even
though loopback health passed, the loopback UI replaces the raw state-database
error with bounded recovery guidance and the same matching manual-bundle
fallback. It does not delete, move, or recommend deleting the user's Codex
state.

### Runtime update

Runtime update execution is introduced only in Stage 7. Its contract is already
bounded:

1. The host fetches a manifest from one compiled-in HTTPS release origin.
2. The extension cannot supply or override a download URL, executable path,
   command line, signature key, or checksum.
3. The host verifies the manifest signature with a pinned public key.
4. The host downloads to a versioned staging directory.
5. It verifies platform, architecture, signature, and SHA-256.
6. It waits for AkuSidecar update readiness and never replaces an active
   reasoning or capture session.
7. It starts and health-checks the candidate before changing the active pointer.
8. It performs an atomic activation and retains one known-good rollback version.
9. A failed candidate is rolled back and reported with a typed error.

## Native Messaging transport

The extension uses one-shot `chrome.runtime.sendNativeMessage()` calls. A
permanent `connectNative()` port is not the default because it would couple
extension service-worker lifetime to the native process and may delay Store
updates.

Each call contains exactly one request and receives at most one response. The
current v2 normative JSON shape is
[`../contracts/native-runtime-messaging.schema.json`](../contracts/native-runtime-messaging.schema.json).
The exact migration fallback remains separately frozen in
[`../contracts/native-runtime-messaging-v1.schema.json`](../contracts/native-runtime-messaging-v1.schema.json).
Accepted request/response examples and one required rejection case live under
[`../contracts/examples/`](../contracts/examples/).

Supported actions are deliberately small:

- `status`: inspect installed runtime and update state;
- `ensure_runtime`: start or reconcile a compatible runtime;
- `reconcile_runtime`: start/reconcile the installed Sidecar without consulting
  the update feed (v2 only, used for quiet startup recovery);
- `shutdown_if_idle`: request shutdown only when the runtime proves it is idle.
- `check_codex`: inspect bounded local Codex availability without exposing credentials.

There is no arbitrary shell, process, filesystem, registry, URL, installer, or
script action. The extension opens the fixed loopback UI itself after
`ensure_runtime` returns `ready`; native UI-launch authority is unnecessary.

## Client-projected states

The following states exist only inside the extension client and setup UI:

- `checking_host`
- `runtime_install_required`
- `runtime_ready`
- `runtime_updating`
- `runtime_busy`
- `runtime_restart_required`
- `runtime_incompatible`
- `runtime_failed`

`runtime_install_required` is derived from Chrome's missing-host error because no
native process exists to return a response. All actual host responses must pass
the schema and bind to the original `requestId` and `action`.

## Compatibility rules

The request always carries:

- AkuBrowser extension product version;
- Bridge runtime revision;
- Bridge protocol major/minor;
- a bounded capability list.

The v2 host refuses unsupported protocol ranges or missing required capabilities
rather than guessing. Product release numbers and build revisions are diagnostic
metadata, not an exact-tuple usability boundary. A compatible older runtime may
remain usable while the host advertises a target update; a compatible newer
runtime is not downgraded. During migration the Bridge retries once with the
frozen v1 request shape; a valid v1 response keeps the runtime usable and offers
one explicit installer refresh for the internal host.
If a signed v2 feed requires a newer host, the bounded
`host_upgrade_required` response preserves the authenticated Sidecar version in
`update.targetVersion`. Setup accepts only the exact versioned companion
installer for that target; ordinary bootstrap and repair remain pinned to the
static compatible Sidecar version packaged into Bridge.
`ensure_runtime` succeeds only when all of these hold:

1. the Store extension origin is allowlisted;
2. the installer-owned stable or preview channel is valid;
3. the native protocol version is supported;
4. the target runtime supports the requested Bridge protocol and capabilities;
5. an update candidate satisfies the signed protocol, capability, host, and
   database compatibility ranges;
6. the Sidecar health response reports the expected candidate identity and runtime;
7. the fixed loopback endpoint is owned by the expected AkuSidecar instance.

The release channel is never accepted from the extension request. It is fixed
by the signed companion installation and returned only as observed runtime
state.

No compatibility check may silently downgrade the extension's capture,
authentication, provenance, or read-only boundaries.

The installed host may use `shutdown_if_idle` across product-version or build
revision differences because the private instance control token proves that it
owns the installed Sidecar. Loopback reachability alone is never process-control
authority. A portable runtime detected only through loopback is reported by
Setup as unmanaged and must be stopped from its own terminal or extracted
bundle before the installed runtime is reconciled.

## Filesystem and registration boundary

The companion installer is user scoped by default. Windows uses:

- stable native host:
  `%LOCALAPPDATA%\Programs\AkuBrowser\host\AkuBrowserRuntimeHost.exe`
- native host manifest:
  `%LOCALAPPDATA%\Programs\AkuBrowser\host\com.akubrowser.runtime.json`
- versioned payloads:
  `%LOCALAPPDATA%\Programs\AkuBrowser\runtime\versions\<version>\`
- active-version metadata:
  `%LOCALAPPDATA%\Programs\AkuBrowser\runtime\current.json`
- existing product data:
  `%LOCALAPPDATA%\AkuBrowser\data`

The native host manifest is registered under
`HKCU\Software\Google\Chrome\NativeMessagingHosts\com.akubrowser.runtime`.
The stable host path is not a versioned payload path. Runtime activation changes
only `current.json` after candidate acceptance, allowing rollback without moving
the registered host.

User data is never stored inside a version directory and is never deleted by an
ordinary install, update, rollback, extension removal, or runtime repair.

macOS uses the equivalent current-user layout:

- stable native host:
  `~/Library/Application Support/AkuBrowser/host/AkuBrowserRuntimeHost`
- Native Messaging manifest:
  `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.akubrowser.runtime.json`
- versioned payloads:
  `~/Library/Application Support/AkuBrowser/runtime/versions/<version>/`
- active-version metadata:
  `~/Library/Application Support/AkuBrowser/runtime/current.json`
- product data:
  `~/Library/Application Support/AkuBrowser/data`

The macOS manifest contains the absolute host path required by Chrome. Both the
explicitly unsigned `v0.7.9-preview1` package and a future signed/notarized
package register only the exact production extension origin. The preview's
Installer page and Setup disclose its trust state and direct a blocked user to
the per-app **Privacy & Security > Open Anyway** flow after checksum
verification; neither recommends disabling Gatekeeper. The package installs no
LaunchAgent because Chrome launches the Native Messaging Host on demand.

## Security invariants

1. Native messages are accepted only from exact allowlisted extension origins.
2. Extension inputs are data, never commands or executable logic.
3. The extension cannot choose update URLs, filesystem paths, or processes.
4. The extension package contains all extension-side logic; no remote JavaScript
   or interpreted command stream is allowed.
5. Native payloads require a valid signed manifest and exact SHA-256.
6. Installer, host, Sidecar, and any update helper must be code signed for
   production.
7. Native protocol stdout contains framed JSON only; diagnostics use stderr.
8. Absolute local executable and data paths are not returned to the extension.
9. Tokens, credentials, social content, prompts, and database contents never
   enter the Native Messaging protocol.
10. Runtime update is refused while AkuSidecar cannot prove update readiness.
11. Candidate failure preserves the active version and local database.
12. Store permissions and user-data disclosures must describe the complete
    extension plus companion-runtime experience.

## Stage 1 acceptance

Stage 1 is complete when:

- this document is the reviewed distribution authority;
- the native request/response schema parses as JSON;
- example request and response objects validate against the intended schema;
- public and internal naming are unambiguous;
- host registration, fixed trust inputs, compatibility, data preservation,
  startup, update, and rollback boundaries are explicit;
- no Store, Bridge runtime, Sidecar runtime, registry, or installer mutation has
  been introduced.

Stage 2 may then add only the extension-side client and tests. It must not
silently simulate a present native host or alter existing capture behavior.
