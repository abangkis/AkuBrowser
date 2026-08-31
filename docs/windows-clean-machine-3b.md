# Windows clean-machine Step 3B — v0.9.0

Use this runbook for independent Windows certification of the AkuBrowser v0.9.0
x64 release. It validates the one installed-app installer `.exe` and its
complete Bridge + Sidecar + pinned-Chromium tuple. This manual matrix is
post-release hardening and does not replace the automated release gates.

## Inputs for the active release lane

- one Windows x64 installer `.exe` and its adjacent SHA-256 checksum;
- the matching generated tuple/release manifest and source-freeze SHAs;
- a clean Windows x64 machine or account with no prior AkuBrowser data/process;
- Codex App with App Server installed and signed in locally;
- signed-in source accounts for the sources selected during acceptance.

The installed candidate owns its pinned Chromium profile. Do not use system
Chrome, Chrome Web Store installation, Developer Mode, a manually loaded
extension, a portable ZIP, or a separate runtime installer as v0.9.0 evidence.
Codex remains an external prerequisite. The optional Gemini provider uses a
user-supplied key stored through the Sidecar credential flow; it is not bundled
in the installer.

## Active RC checklist

- [ ] Verify the installer checksum and record the candidate version, source
      SHAs, signing state, and SmartScreen/antivirus behavior.
- [ ] Run the one installer `.exe` on the clean machine. Confirm it installs the
      launcher, Sidecar, internal production-app Bridge, pinned Chromium,
      c2patool, configuration, and manifests as one tuple.
- [ ] Launch from the installed application identity without system Chrome,
      Developer Mode, or a manually loaded extension. Confirm one app-shell
      instance and healthy Sidecar/Bridge heartbeat.
- [ ] Complete first-run setup for the four adapters: X, LinkedIn, Facebook,
      and opt-in Instagram. Verify source-scoped permission, sign-in readiness,
      denial/retry, and revocation behavior for each exercised source.
- [ ] Confirm Codex readiness, then exercise optional Gemini-key setup/use and
      one provider hot-swap at an idle boundary without restarting Sidecar.
- [ ] Verify schema 22 startup and the documented additive migration boundary
      without losing the existing user data fixture.
- [ ] Exercise install, restart, repair, update/rollback, ordinary uninstall
      with data preservation, and explicit full reset. Record any unimplemented
      behavior as a release blocker rather than marking it passed.
- [ ] Attach screenshots/logs, hashes, Installed Apps evidence, and a final
      pass/fail decision to the v0.9.0 release evidence.

The RC fails if any required item is unverified. An unsigned local candidate may
trigger SmartScreen or antivirus warnings; record that behavior and keep the
warning honest until the final signed artifact is verified.

## Historical pre-v0.9.0 Store/portable procedure

The procedure below is retained as historical evidence for the former acceptance
lane. It is not a v0.9.0 gate and must not be used to claim the installed-app
candidate passed.

## Manual checklist

- [ ] Confirm no AkuBrowser runtime/database from an earlier test remains and no
      old AkuSidecar process is running.
- [ ] Copy the complete `acceptance/` lane plus the root `release-kit.json`.
      Verify every file's byte count and SHA-256 against `acceptanceAssets`.
- [ ] Extract `AkuBridge-<version>-prestore-unpacked.zip`, use Chrome **Load
      unpacked**, and verify the acceptance extension ID printed in the lane's
      README and `release-kit.json`. It must be the dedicated `acceptance` ID,
      never the workspace development or either production ID.
- [ ] Open Setup and select **Check runtime**. Before installation it must report
      the runtime unavailable, offer the named local installer, and avoid a
      not-yet-published GitHub URL.
- [ ] Run `AkuBrowserRuntimeSetup-<version>-unsigned-local.exe` once and wait for
      it to finish. Record actual SmartScreen/antivirus behavior; allow only the
      verified file or narrow AkuBrowser installation path when required.
- [ ] Open Windows **Settings > Apps > Installed apps** and confirm **AkuBrowser
      Runtime** appears with the expected version. Treat this as the canonical
      successful-install identifier if antivirus makes the installer UI appear
      twice or sequentially.
- [ ] Return to Setup and select **Check runtime**. Confirm the runtime becomes
      ready/running, then verify stop and start/recovery behavior.
- [ ] Select **Check Codex**, confirm detection, and explicitly confirm Codex is
      signed in and ready.
- [ ] Grant only intended sources, complete onboarding/calibration, and run one
      full **Update now**. Inspect captured, evaluated, selected, and retained
      results for errors.
- [ ] After installation, Setup must show **Check runtime**, not **Show local
      installer**. Selecting it must re-check and start the compatible runtime;
      it must not incorrectly retain **Repair required**.
- [ ] Uninstall and choose **Preserve data**, reinstall, and confirm the existing
      database remains usable.
- [ ] Simulate a downgrade by placing a valid newer version in
      `%LOCALAPPDATA%\AkuBrowser\data\.runtime-version`, then run the older
      candidate installer. Confirm its archive-and-reset prompt. Choosing No must
      abort without changing data; choosing Yes must move the newer data under
      `data-backups\pre-downgrade-*`, write `downgrade-receipt.txt`, and create a
      fresh database.
- [ ] If the installer downgrade step is bypassed, Setup must report **Newer data
      detected** with **Reset with installer**. A generic **Try again** loop is a
      failure.
- [ ] Uninstall again and choose **Full reset**. Confirm `data`, `data-backups`,
      and `downgrade-receipt.txt` are removed; reinstall and confirm onboarding
      starts from a fresh database.
- [ ] Pass Chrome restart, Windows restart, runtime stop/start, installer repair,
      uninstall/reinstall, preserve-data, downgrade, and full-reset checks.
- [ ] Record extension ID, installer/runtime version, hashes, Installed apps
      evidence, antivirus behavior, screenshots/logs, non-blockers, and the final
      pass/fail decision.

## Decision rule

Step 3B passes only when install, runtime, Codex, one full update, and lifecycle
checks complete without a release blocker. A failed required item stops the
release. A non-blocking UX observation must be recorded for follow-up but does
not silently change the frozen candidate.

## Current known non-blockers

- Antivirus inspection can make installation appear to execute twice or
  sequentially. Use the verified installer result plus **AkuBrowser Runtime** in
  Installed apps as the successful-install evidence, rather than the number of
  installer windows shown.

## Acceptance log

| Release | Date | Environment | Result | Evidence and observations |
| --- | --- | --- | --- | --- |
| 0.8.0 | 2026-08-14 | Windows clean-machine flow | Passed before lifecycle UX fix | Development Bridge and local unsigned runtime completed the flow; AkuBrowser Runtime 0.8.0 appeared in Installed apps. The stale repair label was fixed afterward and requires Windows re-verification. |

Keep release-specific screenshots and logs with the release evidence. Refine
this runbook when a repeated observation becomes a required check or a fixed
behavior changes the expected result.
