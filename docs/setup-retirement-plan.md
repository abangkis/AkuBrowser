# AkuBrowser legacy Bridge setup retirement plan

Status: active plan, 27 August 2026. Chrome Web Store publication is frozen;
all future production releases ship through the single signed installed-app
tuple defined in the [installed-app distribution contract](installed-app-distribution-contract.md).

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

- [ ] Fresh-profile multi-source acceptance on the development lane
      (pinned Chromium, SharedTemp-isolated database): repeat the completed
      X acceptance for LinkedIn and Facebook — deny then grant the optional
      host permission, sign in inside the isolated profile, observe typed
      `login_required` → ready transitions, restart Sidecar and Bridge,
      complete calibration to Timeline.
- [ ] Failure-path states render from Sidecar without the legacy page:
      permission denied, registration missing, login required, Codex
      unavailable/pre-flight blocked, runtime stopped, and portable offline
      lane startup.

Record the run beneath this checklist in this document before staging
deletions. This mirrors the existing gap note in the installed-app contract:
one isolated X acceptance proved the flow for one source; multi-source and
failure paths close the remaining precondition.

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
  opens `setup.html`.

### Stage 2 — Deletions

- Delete the ten legacy artifacts listed in the background table.
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

### Stage 3 — Documentation retirement

- AkuBridge README: remove the setup-page walkthrough (runtime simulation
  query parameters, installer retry escalation, manual bundle instructions)
  and document the Sidecar-owned first-run path as the only onboarding.
- Historical contracts receive superseded banners, not rewrites:
  `chrome-store-distribution-contract.md` gains the frozen-publication note,
  and `windows-runtime-installer.md` / `windows-runtime-updater.md` are
  already marked historical — extend their banners only where wording still
  implies future Store work.
- `BUILD_WEEK.md` and release notes describing shipped `0.7.x` behavior are
  historical evidence and are not edited.
- AkuBrowser top-level README: replace the "Install from the Chrome Web
  Store"   routing block with the frozen-publication statement and installed-app
  target link once Stage 2 is complete. Keep launcher identity docs current.

### Stage 4 — Final verification

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
