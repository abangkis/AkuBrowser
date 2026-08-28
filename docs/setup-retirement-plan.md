# AkuBrowser legacy Bridge setup retirement plan

Status: active plan, updated 28 August 2026. Chrome Web Store publication is
frozen; all future production releases ship through the single signed
installed-app tuple defined in the
[installed-app distribution contract](installed-app-distribution-contract.md).
The Sidecar-owned provider onboarding and local readiness lane are complete.
Legacy setup deletion and Stage 3 documentation retirement are complete; the
automated portion of Stage 4 is recorded below, with only clean-machine
portable acceptance remaining.

This plan executes Phase 5 of the installed-app migration: removing the
legacy Bridge-owned `setup.html` surface after the Sidecar-owned setup path
has proven itself. It names every file, entry point, test, and document that
retirement touches so the removal is mechanical and reviewable.

## Decision record — 2026-08-27

- Chrome Web Store publication of AkuBrowser is **frozen**. No further Store
  builds are planned or submitted.
- The existing Web Store listing remains downloadable for current users but
  receives no updates. Its guided setup keeps working against already-shipped
  Sidecar releases; frozen publication means no new runtime has to keep it
  compatible.
- All future production installation and update authority is the single
  signed installed-app tuple (Phase 4 of the installed-app contract).
- The portable GitHub ZIP remains a recovery lane until whole-tuple updating
  ships; its bundled Bridge must not regress when the legacy surface is
  removed.
- No final "last Store build" is cut before Stage 2. `production-store`
  becomes a retired identity profile at Stage 2 completion.

## Background: what the legacy surface is

Sidecar owns the complete setup and onboarding experience
([installed-app contract](installed-app-distribution-contract.md), Phase 2/3).
The Bridge-owned monolithic page survives only as:

| Legacy artifact | Role |
| --- | --- |
| `setup.html`, `setup.css`, `setup.js` | Monolithic setup page: source consent checkboxes, runtime install steps, Codex readiness |
| `setup-platform.js` | Platform detection for installer copy |
| `setup-runtime-view.js`, `setup-runtime-installer.js`, `setup-runtime-simulation.js` | Companion-runtime installer guidance, pinned assets, simulation query parameter |
| `setup-codex-view.js` | Codex setup guidance |
| `icons/setup-favicon.svg` | Page icon |
| `test/setup-*.test.mjs` (5 files) | Dedicated tests for the modules above |

Entry points that reach the legacy page today:

1. `manifest.json` — `"options_page": "setup.html"`.
2. `popup.js` — "Setup & source access" button opens the options page.
3. `service-worker.js` (`chrome.runtime.onInstalled`) — auto-opens the page
   for `LEGACY_SETUP_MODES` (`production-store`, `acceptance`) via
   `planNativeRuntimeLifecycle` in `native-runtime-lifecycle.js`.
4. `service-worker.js` — `AKU_BRIDGE_OPEN_SETUP` message handler, relayed by
   `aku-browser-tab-bridge.js` from loopback pages (`AKU_BROWSER_OPEN_BRIDGE_SETUP`).
5. `native-runtime-status-view.js` — user-facing copy instructs "Open Setup…"
   in every missing/incompatible/stopped runtime state.

The replacement path already exists and is not part of this cleanup:
Sidecar `/api/onboarding`, the loopback first-run UI, per-source readiness,
and the narrow extension-owned permission broker
(`source-permission.html` + `source-permission.js`). Sidecar's own test suite
rejects any use of `AKU_BROWSER_OPEN_BRIDGE_SETUP` from its UI.

## Blocking gate before deletions

Stage 2 deletes files. It starts only after the acceptance record named below
passes with current code:

- [x] Reset multi-source acceptance on the development lane (Chrome Stable
      with the dedicated persistent AkuBrowser development profile and an
      isolated database): keep the profile/login sessions, revoke source
      permissions, then repeat the completed X acceptance for LinkedIn and
      Facebook — deny then grant the optional host permission, observe typed
      `login_required` → ready transitions when applicable, restart Sidecar and
      Bridge, and complete calibration to Timeline. Pinned-Chromium login
      compatibility remains a later installed-app release gate.
- [x] Failure-path states render from Sidecar without the legacy page:
      permission denied, registration missing, login required, Codex
      unavailable/pre-flight blocked, runtime stopped, and portable offline
      lane startup.

Record the run beneath this checklist in this document before staging
deletions. This mirrors the existing gap note in the installed-app contract:
one isolated X acceptance proved the flow for one source; multi-source and
failure paths close the remaining precondition.

Acceptance progress recorded on 28 August 2026:

- Interactive development acceptance passed X and LinkedIn permission/session
  readiness, including recognition of an authenticated source after its tab is
  closed.
- Provider onboarding passed Codex/local readiness presentation, secure Gemini
  key storage, immediate Gemini selection, and a first Gemini-backed update.
- The prescribed reset LinkedIn/Facebook lane passed: reset revoked optional
  browser permissions while preserving the profile and login sessions;
  LinkedIn Back left permission ungranted and its subsequent grant became
  ready; Facebook Deny remained `permission_not_granted`, then retry with Allow
  became ready. Both sources remained access-ready with source tabs closed.
- AkuSidecar restarted gracefully and AkuBridge completed a cooperative reload
  without losing either source permission. A Codex-backed two-source first
  update then completed with four Timeline items and zero duplicates, followed
  by a completed 4/4 calibration snapshot with no capture issues.
- The `login_required` state remains contract-tested rather than live-tested in
  this lane because preserving the authenticated profile is an explicit reset
  requirement.

Failure-state matrix evidence recorded on 28 August 2026:

- Permission denial and missing content-script registration are derived from
  the Bridge heartbeat as separate typed outcomes. Sidecar now preserves that
  distinction in both onboarding and Settings (`Access: permission required`
  versus `Access: capture registration missing`).
- `login_required` remains a bounded source-session observation with a Sidecar
  `Sign in` action; it is contract-tested and was not forced live because the
  accepted profile must retain its authenticated sessions.
- Codex unavailable and failed App Server pre-flight are covered by the
  cost-free provider-readiness contract. Sidecar keeps onboarding usable,
  renders `Unavailable`, and blocks activation until readiness succeeds.
- Runtime stopped/reconnecting and the portable offline recovery lane are
  covered by the bounded Bridge/native-host lifecycle contracts: stopped
  runtime state is explicit, offline update discovery remains recoverable, and
  portable startup probes only the fixed Sidecar loopback health contract.
  Forcing a live stop or launching a second portable runtime would change the
  active development lane, so those two states remain contract-tested here;
  the manual acceptance action is to stop the active runtime, start the
  matching portable bundle with `Start-AkuBrowser.ps1`, and confirm the
  Bridge-ready Sidecar shell before restoring the normal lane.
- Sidecar's embedded failure-state contract asserts all six states and rejects
  `setup.html`, `AKU_BROWSER_OPEN_BRIDGE_SETUP`, and `AKU_BRIDGE_OPEN_SETUP` in
  its served UI. Targeted Sidecar HTTP/Node tests, Bridge source/session and
  native-runtime tests, and native-host lifecycle tests passed without a
  profile reset, credential change, live restart, or model call.

Stage 1 manual acceptance recorded on 28 August 2026:

- The owner reloaded the unpacked AkuBridge in the existing development lane;
  no `setup.html` tab opened. The popup presented only **Open AkuBrowser**, and
  that action opened the Sidecar loopback app shell. No profile, credential,
  source permission, or runtime reset was performed.

Stage 2 deletion evidence recorded on 28 August 2026:

- Deleted the nine actual legacy setup artifacts: `setup.html`, `setup.css`,
  `setup.js`, `setup-platform.js`, `setup-runtime-view.js`,
  `setup-runtime-installer.js`, `setup-runtime-simulation.js`,
  `setup-codex-view.js`, and `icons/setup-favicon.svg`.
- Deleted the five dedicated setup tests under `test/setup-*.test.mjs`.
  The source-permission broker remains present and its favicon now uses the
  packaged `icons/icon-48.png`, which was the only active reference to the
  retired setup favicon.
- Removed the unreachable `AKU_BROWSER_OPEN_BRIDGE_SETUP` relay, removed the
  package verifier's manifest-options reference, and removed setup-only
  syntax checks. The Bridge revision advanced to `source-adapters-v107` and
  Sidecar's expected revision/build tracking was updated to accept it.
- Targeted Bridge absence/lifecycle/status tests, the canonical Bridge check,
  package verification, and relevant Sidecar HTTP/engine tests passed. No
  profile reset, credential change, source permission change, live runtime
  restart, or model call was performed.

Next action: complete the automated Stage 4 checks, then perform the documented
clean-machine portable stop/start gesture as a later release gate. No further
reset, credential, or live development-runtime change is required for the
retired setup surface.

## Stages

### Stage 0 — Decision and gates (this stage)

- Record the Store-freeze decision (Decision record above).
- Update the canonical contracts so no active document still claims Store
  publication is forward-looking.
- Define and run the blocking gate above. Delete nothing yet.

### Stage 1 — Rewire entries (reversible, additive)

Every change below leaves the setup files present but unreferenced from
active code paths, so a revert is trivial.

- `manifest.json`: remove `"options_page": "setup.html"`.
- `popup.{html,js}`: replace the two-button layout ("Open AkuBrowser",
  "Setup & source access") with one action that opens the loopback origin.
  Keep the runtime-status view rendering in the popup; popup status must stay
  honest while identity/installer copy changes later.
- `native-runtime-lifecycle.js`: retire `LEGACY_SETUP_MODES`;
  `planNativeRuntimeLifecycle` returns `openSetup: false` unconditionally for
  every event, mode, and distribution. Drop the field from the returned plan
  objects instead of preserving a dead flag.
- `service-worker.js`: delete both `chrome.tabs.create(...setup.html...)`
  call sites (the `onInstalled` branch and the `AKU_BRIDGE_OPEN_SETUP`
  handler). Update the tab-recovery behavior if an install-time tab was part
  of its assumptions; the installed-app lane lands users in the app shell,
  not an extension page.
- `native-runtime-status-view.js`: rewrite all action copy to direct the user
  to the loopback application (repair/reinstall/update states included) and
  out of extension-page flows.
- Tests updated in the same commit: `native-runtime-lifecycle.test.mjs`,
  `extension-contract.test.mjs` assertions about `options_page`, the popup,
  and status-view copy expectations.
- Verification: `npm run check` in AkuBridge plus one manual pass of fresh
 -profile load-unpacked + Sidecar dev runtime confirming no active code path
  opens `setup.html`. [x] Manual acceptance recorded above.

### Stage 2 — Deletions

- Delete the nine legacy artifacts listed in the background table.
- Remove the `AKU_BRIDGE_OPEN_SETUP` relay from `aku-browser-tab-bridge.js`
  (already unreachable after Stage 1).
- Remove the sidecar-host fallback acceptor of that message type if Bridge
  contract v2 schema still declares it; the contract documents the message
  inventory, so it must be reconciled in the same commit rather than left
  stale.
- Collapse `native-runtime-status-view.js` simulation-only remnants that only
  served the setup page (`?simulateRuntime=` handling belongs to
  `setup-runtime-simulation.js` and dies with it).
- Test cleanup: delete `test/setup-*.test.mjs`; shrink
  `extension-contract.test.mjs` to assert the *absence* contract
  (no `options_page`, no `setup.html` reference anywhere packaged); keep and
  do not weaken the session-readiness assertions covering
  `source-permission.html`.
- Packaging: `scripts/verify-extension-package.mjs` drops `addReference` for
  the manifest `options_page`.
- Blocking gate evidence must exist in this document before this stage's
  first commit.
- After deletion: bump the Bridge runtime revision constant in
  `bridge-capabilities.js` per existing practice, and confirm Sidecar's
  expected runtime revision tracking accepts the reload.

### Stage 3 — Documentation retirement (complete — 28 August 2026)

- [x] AkuBridge README: remove the setup-page walkthrough (runtime simulation
  query parameters, installer retry escalation, manual bundle instructions)
  and document the Sidecar-owned first-run path as the only onboarding.
- [x] Historical contracts receive superseded banners, not rewrites:
  `chrome-store-distribution-contract.md` gains the frozen-publication note,
  and `windows-runtime-installer.md` / `windows-runtime-updater.md` are
  already marked historical — extend their banners only where wording still
  implies future Store work.
- [x] `BUILD_WEEK.md` and release notes describing shipped `0.7.x` behavior are
  historical evidence and are not edited.
- [x] AkuBrowser top-level README: replace the "Install from the Chrome Web
  Store"   routing block with the frozen-publication statement and installed-app
  target link once Stage 2 is complete. Keep launcher identity docs current.

Stage 3 evidence recorded on 28 August 2026:

- AkuBridge README now documents the Sidecar loopback app as the only current
  first-run/onboarding and repair path; the retired walkthrough, simulation
  query parameters, installer retry escalation, and manual bundle instructions
  are absent.
- The named historical contracts retain their shipped-flow bodies with explicit
  frozen/superseded banners. `BUILD_WEEK.md` and release notes were not edited.
- AkuBrowser's top-level README routes the frozen Store listing to the signed
  installed-app target and keeps the portable ZIP as a technical-user/recovery
  lane.

### Stage 4 — Final verification (automated portion complete — 28 August 2026)

- `npm run check` in AkuBridge; `.\scripts\check.ps1` from AkuBrowser for the
  workspace aggregate.
- Grep sweep proving zero live references:
  `setup\.html|options_page|OPEN_SETUP|openSetup|setup-favicon|simulateRuntime`
  must match only this plan, superseded banners, and Git history outside
  them.
- Re-run clean-machine Step 3B-style acceptance for the offline portable
  lane with the post-deletion Bridge payload.
- Confirm `store/` submission materials now require no reconciliation, or add
  explicit notes there stating the listing is frozen.

Automated evidence recorded on 28 August 2026:

- The zero-live-reference sweep found no forbidden token in active Bridge,
  Sidecar, or AkuBrowser implementation/release paths. The remaining matches
  are confined to this plan, the explicitly historical contract bodies, and
  intentional absence assertions in Bridge/Sidecar tests.
- The first aggregate run exposed stale v106 release tracking after the
  intentional Bridge/Sidecar v107 revision bump. The release manifest, Bridge
  contract, and five runtime examples were reconciled to v107; the focused
  identity verifier then passed with build ID
  `aku-bridge-0.8.0-source-adapters-v107`.
- `AkuBridge\npm run package:verify` passed and listed no deleted setup
  artifact. The aggregate `AkuBrowser\scripts\check.ps1` reached and passed
  its identity, Sidecar, Bridge (292 JS tests plus native tests), and installer
  stages. Its launcher stage was blocked by the sandbox default temp-path ACL
  (`resolve install root: Access is denied`) before any launcher assertion ran;
  the same canonical launcher package passed with `TEMP`/`TMP` redirected to
  the task-owned `.tmp-stage3` directory and repo-local Go cache.
- No Sidecar tests were rerun after the documentation-only changes; the
  relevant HTTP/engine suite had already passed on the unchanged Sidecar
  payload.

The remaining Stage 4 gate is manual and intentionally not run here: on a
clean machine, stop the active runtime, start the matching portable bundle with
`Start-AkuBrowser.ps1`, and confirm the Bridge-ready Sidecar shell before
restoring the normal lane. Signing, shipping, deployment, profile/session
changes, source-permission changes, and credential changes remain out of scope.

## Explicit non-goals

- Companion Native Messaging update machinery, `SIDECAR_BOOTSTRAP_VERSION`
  bookkeeping, and Native Messaging manifest narrowing belong to Phase 4
  tuple work and are untouched here except where they literally reference
  the deleted page.
- Database schema reconciliation for the staged installed-app manifest is
  tracked separately in the installed-app contract and is not repeated here.
- No functional change to capture, media evidence, reader windows, background
  dispatch, or semantic/behavioral behavior accompanies the retirement.
- No cleanup of Chromium pinned-build, signing, NSIS, or updater code beyond
  what deleting the setup surface requires.

## Related documents

- [Installed-app distribution contract](installed-app-distribution-contract.md)
- [Chrome Store distribution contract](chrome-store-distribution-contract.md)
- [Product contract](product-contract.md)
- [Bridge identity contract](bridge-identity-contract.md)
