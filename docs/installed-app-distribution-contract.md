# AkuBrowser installed-app distribution contract

Status: approved target architecture; Phase 0 identity and Windows launcher
vertical slice implemented, and a local Windows tuple builder is staged. A
signed unified installer and shipped migration remain pending.

The staged builder records the current Sidecar database schema separately from
the historical Sidecar-only update feed. It accepts the current additive
7-to-9 migration path, but database rollback remains explicitly unimplemented
until whole-tuple activation and rollback are built.

This document is the canonical distribution target for the next AkuBrowser
product direction. It supersedes the assumption that production is delivered
through the Chrome Web Store or through a separately installed companion
runtime. The current implementation remains documented honestly in the
historical contracts linked below until the migration is complete.

## Decision

AkuBrowser production will be distributed as one signed, downloadable
installer. The installer bundles the complete user-facing tuple:

- `AkuBrowserLauncher`, owned and released by the AkuBrowser repository;
- AkuSidecar, the Go application and loopback API;
- AkuBridge, loaded as an internal Manifest V3 extension/sensor;
- one pinned Chromium build used only by the AkuBrowser app shell;
- c2patool and other pinned local support assets;
- projected configuration, exact extension identity, compatibility metadata,
  checksums, and signed update metadata.

Chrome Web Store installation and the user's system Chrome are not part of the
target production path. A normal installation does not ask the user to enable
Developer Mode, load an extension manually, or install a separate runtime
companion. The app shell owns the browser profile and the product entry point.

This is a target contract, not a claim about the current artifacts. The current
Store/companion implementation remains useful historical evidence in the
[Chrome Store distribution contract](chrome-store-distribution-contract.md),
[Windows runtime installer](windows-runtime-installer.md), and
[Windows runtime updater](windows-runtime-updater.md).

## Authority and ownership

| Boundary | Target authority | Explicit non-authority |
| --- | --- | --- |
| Product entry, install, repair, update, rollback, uninstall | AkuBrowserLauncher and its signed installer/update helper | AkuBridge UI, generic loopback pages |
| Setup and onboarding UI | AkuSidecar | AkuBridge full setup page |
| Durable onboarding, source intent, settings, calibration, Timeline state | AkuSidecar SQLite and API | Chrome extension storage as the product record |
| Optional source host permissions and content-script registration | AkuBridge permission broker and service worker | AkuSidecar HTTP/JavaScript |
| Source tabs, login readiness, bounded capture, heartbeat | AkuBridge | AkuSidecar direct browser automation |
| Browser engine and isolated profile | Installer/launcher-managed pinned Chromium | System Chrome or an arbitrary executable selected by the user |
| OS process lifecycle | Launcher/update helper | A loopback web page or a hidden Sidecar watcher |
| Native Messaging / companion host | Transitional compatibility boundary only | Target setup or update authority |

AkuBridge remains an internal implementation component. It is not a separately
marketed or independently installed product in the target lane.

## Bundle and filesystem boundary

The installer must stage the complete tuple under a replaceable program root,
with user data and the app-shell profile outside that root. A release-specific
layout is expected to be equivalent to:

```text
AkuBrowser/
  AkuBrowserLauncher.exe
  runtime/
    current.json
    versions/<version>/
      AkuSidecar.exe
      AkuBridge/
      chromium/<pinned-build>/
      c2patool.exe
      config/sidecar.json
      manifests/
  install-manifest.json
  Uninstall.exe

User data (preserved by ordinary uninstall):
  %LOCALAPPDATA%/AkuBrowser/data/

Isolated browser profile (preserved or reset by explicit product policy):
  %LOCALAPPDATA%/AkuBrowser/browser-profile/
```

The exact platform paths may differ, but these invariants must hold:

- the launcher never selects an arbitrary executable, extension directory, or
  Chromium build from user-editable configuration;
- the installed manifest records every payload file, size, hash, version, and
  source tuple;
- the active version pointer is written only after the complete tuple is
  staged and verified;
- user data and the browser profile are not inside the replaceable version
  directory;
- repair and uninstall resolve paths from an ownership manifest and refuse
  paths that escape the installed root.

The legacy runtime installer does not satisfy this layout: it stages the Native
Host and Sidecar payload but not AkuBridge or pinned Chromium. A separate staged
NSIS lane now consumes the verified installed-app tuple, writes the active
pointer last, and preserves data and the isolated profile on ordinary uninstall.
It remains unsigned and not shipped; see the
[current implementation gap](#current-implementation-gap).

## Installed-app identity and trust

The loaded Bridge must have one exact, stable extension identity for the
installed-app lane. The identity is projected into the packaged Bridge
manifest and into Sidecar's trusted extension-origin configuration. Sidecar
must independently verify the exact origin on every heartbeat; it must never
discover or accept a wildcard origin from Bridge.

The target identity is named explicitly as `production-app` in the identity
registry and has a distinct public key and extension ID. It does not alias the
existing `production-offline` identity. The target profile binds:

- exact extension ID and public manifest key;
- installed-app distribution and lifecycle metadata;
- release version and source-freeze tuple;
- exact Bridge contract and required capabilities;
- exact pinned Chromium and app-shell policy.

The current identity rules and five-profile registry are described in the
[Bridge identity contract](bridge-identity-contract.md). Store and portable
profiles remain historical implementation lanes during migration.

If Native Messaging is retained during migration, its manifest may allow only
this exact installed-app origin and one installer-owned executable path. It
must not become a general command runner. Native Messaging is transitional;
the target lifecycle authority is the signed launcher/update boundary.

## Process graph

The target process graph is:

```text
AkuBrowserLauncher
  -> versioned AkuSidecar (loopback API + embedded UI)
      -> pinned Chromium --app=<loopback setup/timeline URL>
          -> internal AkuBridge loaded from the verified bundle
              -> source tabs in the isolated AkuBrowser profile
```

Sidecar and Bridge continue to communicate through the existing loopback
contract, Bridge token, exact contract version, and capability heartbeat.
The launcher owns process startup and shutdown. Closing the app shell must
cooperatively stop Sidecar and its Chromium descendants, with no orphaned
capture windows.

The existing app-shell implementation already supports a pinned executable,
separate `--user-data-dir`, and `--load-extension`; the current launcher and
installer do not yet make those options the production default.

## First-run flow

The first-run flow is entirely inside the installed app shell:

1. The installer verifies and installs the complete signed tuple.
2. The launcher creates or opens the isolated app profile and starts the
   versioned Sidecar with the exact Chromium and Bridge paths.
3. Sidecar serves the loopback UI and opens its `/setup` state when onboarding
   is not complete.
4. The Sidecar setup UI explains the product, runtime, local storage, Codex,
   source permissions, and the isolated browser profile.
5. The user chooses source intent in Sidecar. Sidecar persists this intent only
   in its canonical onboarding state.
6. Sidecar asks the Bridge permission broker to request the selected optional
   host permissions. A genuine user gesture in an extension-owned page must
   authorize the request; a generic loopback page must not be trusted to do so.
7. Bridge registers the selected content scripts and reports per-source
   permission, registration, and effective readiness through the heartbeat.
8. For a fresh isolated profile, the user signs in manually inside the pinned
   Chromium source tabs. AkuBrowser does not import cookies, passwords, or
   profile state from system Chrome.
9. Sidecar displays source login/readiness separately from source intent and
   asks for the Codex readiness/sign-in confirmation required by the product.
10. Sidecar persists onboarding, starts bounded calibration, and opens the
    Timeline only when the required readiness gates pass.

The Codex application remains an external prerequisite unless a later product
decision explicitly bundles it. “Signed in” remains a user confirmation unless
the runtime can prove a stronger, machine-verifiable state.

## Setup UI and permission broker

`setup.html` is not part of the target product UI. Sidecar owns the complete
setup/onboarding experience. The extension must retain only a minimal,
extension-owned permission broker (for example, a small `permissions.html`)
until Chrome permission user-gesture behavior is proven through the pinned
Chromium integration.

The broker may perform only fixed, allowlisted operations:

- request or remove the exact source origins declared by Bridge;
- reconcile the corresponding dynamic content scripts;
- return bounded success, denial, and readiness outcomes to Sidecar.

It must not accept arbitrary origins, executable paths, URLs, commands, or
Native Messaging actions. Sidecar may render Bridge state and request a broker
operation, but it cannot call Chrome Extensions APIs directly.

The current `setup.html`, `setup.js`, popup route, service-worker setup route,
and setup-specific tests are therefore migration inputs, not target ownership.

## Login and isolated profile policy

The pinned Chromium profile is intentionally separate from every system Chrome
profile. This provides isolation and makes the installed app reproducible, but
it means a new user must sign in within the AkuBrowser profile. The setup flow
must provide a clear per-source “open sign-in” action and report:

- permission not granted;
- permission granted but content script not registered;
- registered but source login required;
- source ready;
- source unavailable or incompatible.

No source is considered usable merely because it is selected in Sidecar.
Bridge permission/readiness and source login readiness remain separate facts.

Profile reset is a destructive action and requires explicit confirmation. An
ordinary application update preserves the profile. An ordinary uninstall
preserves user data according to the product retention policy; a full reset
explicitly removes both data and the isolated profile.

## Launcher responsibilities

`AkuBrowserLauncher` is owned by the AkuBrowser repository and is the stable
entry point for installed users. It must:

- enforce one active installed-app instance;
- resolve only the signed, active version from `current.json`;
- verify the installed payload before launch;
- pass the exact Sidecar, Chromium, Bridge, profile, database, and control
  paths;
- wait for the Sidecar health contract before presenting the app shell;
- surface bounded diagnostics when a component is missing, corrupt, or
  incompatible;
- request cooperative idle shutdown before updates or uninstall;
- close or reap owned Chromium descendants on failure;
- restart the known-good tuple after a failed candidate activation.

The launcher must not become a second product runtime. Product state remains in
Sidecar; browser capture remains in Bridge; the launcher owns only packaging,
lifecycle, and recovery.

## Failure and recovery contract

| Failure | Required behavior |
| --- | --- |
| Sidecar missing or incompatible | Launcher shows repair/reinstall guidance and does not open system Chrome |
| Bridge missing, tampered, or wrong identity | Launcher refuses capture startup and offers repair |
| Chromium missing, tampered, or wrong pin | Launcher refuses app-shell startup and offers repair |
| Sidecar stopped/crashed | Launcher restarts the active known-good tuple; no hidden Sidecar watcher is added |
| Bridge heartbeat reconnecting | Sidecar shows blocked/reconnecting state; no source is treated as ready |
| Source permission denied | Sidecar preserves intent but marks that source disabled until explicit retry |
| Source login required | Sidecar opens the bounded source sign-in path in the isolated profile |
| Codex unavailable | Setup remains usable, but reasoning/calibration readiness is blocked |
| Update candidate unhealthy | Restore the previous complete tuple and reopen the known-good app shell |
| Profile corrupt | Offer explicit profile recreation; disclose that source sessions are lost |
| Interrupted install/update | Keep the prior active pointer; never run a partial tuple |

There is no regular-Chrome fallback in the target production contract. A
diagnostic command may emit logs or a repair bundle, but it must not silently
escape the isolated app-shell boundary.

## Update and rollback contract

For the first installed-app releases, updates are full signed tuple downloads.
The tuple includes AkuBrowserLauncher/update helper metadata, AkuSidecar,
AkuBridge, pinned Chromium, c2patool, configuration, and required manifests.

The update sequence is:

1. Discover a signed release manifest from the fixed product update authority.
2. Verify the manifest signature, artifact hash, version, platform, identity,
   Bridge contract, database compatibility, and Chromium pin.
3. Download one complete tuple; reject traversal, duplicate, undeclared, or
   hash-mismatched entries.
4. Stage it in a versioned candidate directory without touching the active
   tuple or user data.
5. Wait for Sidecar idle and request a cooperative app-shell shutdown.
6. Atomically activate the candidate pointer.
7. Start the candidate, verify Sidecar health, Bridge heartbeat, exact origin,
   extension fingerprint, and pinned Chromium capability.
8. Confirm activation only after all gates pass.
9. On any failure, restore the previous complete tuple and restart it.

Binary patching, delta downloads, and independently updating Chromium or Bridge
are explicitly deferred optimizations. The current architecture must not
depend on them. A future delta updater must preserve the same signed complete-
tuple postcondition and whole-tuple rollback semantics.

The existing [Windows runtime updater](windows-runtime-updater.md) is a
historical Sidecar-only/Native Messaging implementation record. It must not be
read as the target update authority.

## Uninstall and data preservation

An ordinary uninstall must:

- stop the app shell and all owned descendants;
- remove the installed program root, Bridge payload, Chromium, and launcher;
- remove any transitional Native Messaging registration;
- remove the installed-app identity/configuration;
- preserve user data and any explicitly retained profile state.

A full reset must require an explicit confirmation and remove user data,
SQLite databases, downgrade backups, and the isolated browser profile. The
uninstaller must report exactly what was preserved or removed.

The installed program root is replaceable. Data and profile paths must be
validated to remain outside that root before any recursive removal.

## Security invariants

- Only the signed installer/update authority may introduce executables,
  extensions, or Chromium builds.
- The app shell uses a pinned Chromium and a dedicated profile with component
  updates disabled unless a signed AkuBrowser tuple activates them.
- Only the verified Bridge directory is loaded; user-editable paths cannot
  inject an extension.
- Sidecar remains loopback-only with the existing CSP, host, origin, Bridge
  token, and contract checks.
- Sidecar never receives cookies, passwords, raw browser storage, or arbitrary
  Native Messaging authority.
- Bridge optional host permissions remain source-scoped, revocable, and
  user-consented.
- Native Messaging, if retained, accepts exactly one extension origin and one
  installer-owned executable path and exposes only fixed bounded actions.
- No setup or update flow accepts arbitrary download URLs, executable paths,
  shell commands, registry targets, or scripts.
- Telemetry contains lifecycle/readiness/error metadata only; it excludes
  source content, credentials, cookies, and profile data.
- The app refuses concurrent installed tuples with different identities or
  unverified origins.

## Phased migration and acceptance gates

### Phase 0 — Contract and identity

- Define the installed-app identity/profile and bundle manifest.
- Define launcher arguments, profile/data paths, tuple compatibility, and
  rollback records.
- Decide whether Native Messaging remains a transitional update bridge.
- Preserve the current Store/companion documentation as historical evidence.

Gate: contract review confirms no target production step requires Web Store or
system Chrome.

### Phase 1 — Bundle and app-shell launcher

- Package Bridge, Sidecar, pinned Chromium, c2patool, config, and launcher in
  one installer.
- Make the launcher pass exact app-shell and extension paths.
- Verify clean-profile startup and single-instance behavior.

Gate: a clean machine can install and launch the isolated app shell without
Developer Mode, system Chrome, or a separate runtime installer.

### Phase 2 — Sidecar-owned setup

- Add Sidecar setup/onboarding state and target first-run UI.
- Move runtime/Codex presentation and durable source intent to Sidecar.
- Add source sign-in actions for the isolated profile.

Gate: Sidecar can render all readiness states without relying on `setup.html`.

### Phase 3 — Bridge broker and heartbeat

- Add the minimal extension-owned permission broker.
- Validate genuine user-gesture permission requests in pinned Chromium.
- Add exact broker message validation and idempotent source reconciliation.
- Fix and verify the Bridge heartbeat in pinned Chromium before any
  end-to-end setup acceptance.

Gate: Bridge heartbeat is stable and reports exact identity, contract,
permission, script, and source-login readiness in a fresh app profile.

### Phase 4 — Tuple update, repair, uninstall

- Implement full signed tuple downloads and atomic activation.
- Add whole-tuple rollback, repair, interrupted-update recovery, and process
  cleanup.
- Validate ordinary uninstall versus full reset.

Gate: failed candidates never leave a mixed Bridge/Sidecar/Chromium tuple.

### Phase 5 — Remove the old setup surface

- Route popup and all lifecycle actions to Sidecar setup or the broker.
- Remove `setup.html` and setup-specific full UI only after the broker and
  fallback acceptance gates pass.
- Retire Store/companion production wording from active release guidance while
  preserving historical documents with superseded banners.

Gate: clean install, upgrade, repair, Bridge reload, Sidecar restart, denied
permission, missing login, missing Codex, rollback, and uninstall all have a
recoverable app-shell path.

## Acceptance matrix

The target is not ready until all of these pass on each supported platform:

- install from one signed artifact on a clean machine;
- verify complete payload, exact identity, and pinned Chromium hash;
- launch without system Chrome or Developer Mode;
- complete first-run Sidecar setup in a fresh isolated profile;
- grant, deny, revoke, and retry each optional source permission;
- manually sign in to a source inside the pinned profile and observe typed
  `login_required`/ready transitions;
- observe a stable Bridge heartbeat before calibration;
- detect missing/incompatible/stopped Sidecar, Bridge, Chromium, and Codex;
- update with a complete signed tuple while idle;
- fail candidate health and prove whole-tuple rollback;
- interrupt installation/update and retain the known-good pointer;
- restart after app-shell close/crash without orphaned descendants;
- ordinary uninstall preserves declared data;
- full reset removes declared data/profile only after confirmation;
- verify no credentials, cookies, source content, or arbitrary commands cross
  the launcher, Sidecar, Bridge, or Native Messaging boundaries.

## Current implementation gap

The approved target is partially implemented in the current repositories. The
highest-impact remaining gaps are:

- the Windows launcher verifies a staged tuple and starts the app shell;
  `scripts/build-windows-installed-app.ps1` builds the tuple and
  `scripts/build-windows-installed-app-installer.ps1` emits a separate unsigned
  NSIS candidate, but no signed installer has passed clean-machine install and
  launch acceptance or shipped;
- current Windows/macOS installer builders package a companion runtime rather
  than one Bridge + Sidecar + Chromium installer;
- the current preview still requires manual unpacked Bridge installation and
  system Chrome;
- `AkuBridge/manifest.json`, `popup.js`, `service-worker.js`, and extension
  contract tests still treat `setup.html` as the setup surface;
- source permission requests still originate in the old extension setup page;
- the current runtime updater and Native Messaging lifecycle are Sidecar/
  companion-oriented rather than whole-tuple app-managed;
- `production-app`, `production-installed-app`, launcher, tuple, and unsigned
  NSIS builder contracts exist, but signing, atomic same-version repair,
  whole-tuple rollback, and release publication remain unimplemented;
- pinned-Chromium Bridge heartbeat behavior must be fixed and accepted before
  end-to-end setup migration.

Until these gaps are closed, the current Store/companion and portable-preview
documents describe shipped behavior and must not be silently interpreted as
the approved target.

## Related documents

- [Product contract](product-contract.md)
- [Runtime contract](runtime-contract.md)
- [Bridge identity contract](bridge-identity-contract.md)
- [Historical Chrome Store distribution contract](chrome-store-distribution-contract.md)
- [Historical Windows runtime installer](windows-runtime-installer.md)
- [Historical Windows runtime updater](windows-runtime-updater.md)
- [Stable release checklist](stable-release-checklist.md)
- [Preview release](preview-release.md)
