# Windows clean-machine Step 3B

Use this runbook for the manual Windows acceptance of every stable AkuBrowser
candidate. Replace `<version>` with the frozen release version. This validates
the unpacked development Bridge and its matching local runtime before Store
publication; it does not validate the production Chrome Web Store package.

## Inputs

- the complete, separate `acceptance/` lane from one unified Windows release kit;
- the root `release-kit.json` from that same kit;
- a clean Windows x64 machine or account;
- Chrome, Codex App signed in locally, and signed-in source accounts.

Never use files from `publish/`, a future GitHub URL, the portable bundle, or a
terminal launcher as Step 3B evidence.

The Windows stable gate is the only producer of this lane. Do not rebuild or
copy individual files into it after the gate: the unpacked Bridge ZIP, receipt,
local installer, checksums, and README must remain together and must match the
root `release-kit.json`. The entire lane is non-publishable.

## Manual checklist

- [ ] Confirm no AkuBrowser runtime/database from an earlier test remains and no
      old AkuSidecar process is running.
- [ ] Copy the complete `acceptance/` lane plus the root `release-kit.json`.
      Verify every file's byte count and SHA-256 against `acceptanceAssets`.
- [ ] Extract `AkuBridge-<version>-prestore-unpacked.zip`, use Chrome **Load
      unpacked**, and verify the development extension ID printed in the lane's
      README and `release-kit.json`.
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
- [ ] Pass Chrome restart, Windows restart, runtime stop/start, installer repair,
      uninstall, reinstall, required data preservation, and full-reset checks.
- [ ] Record extension ID, installer/runtime version, hashes, Installed apps
      evidence, antivirus behavior, screenshots/logs, non-blockers, and the final
      pass/fail decision.

## Decision rule

Step 3B passes only when install, runtime, Codex, one full update, and lifecycle
checks complete without a release blocker. A failed required item stops the
release. A non-blocking UX observation must be recorded for follow-up but does
not silently change the frozen candidate.

## Current known non-blockers

- Setup may alternate between **Check runtime** and **Show local installer**
  during installation. After installation, it may still show **Check runtime**
  instead of **Start runtime**; selecting it starts the runtime successfully.
  Improve this state transition in a later release.
- Antivirus inspection can make installation appear to execute twice or
  sequentially. Use the verified installer result plus **AkuBrowser Runtime** in
  Installed apps as the successful-install evidence, rather than the number of
  installer windows shown.

## Acceptance log

| Release | Date | Environment | Result | Evidence and observations |
| --- | --- | --- | --- | --- |
| 0.8.0 | 2026-08-14 | Windows clean-machine flow | Passed | Development Bridge and local unsigned runtime completed the flow; AkuBrowser Runtime 0.8.0 appeared in Installed apps. The two UX observations above were non-blocking. |

Keep release-specific screenshots and logs with the release evidence. Refine
this runbook when a repeated observation becomes a required check or a fixed
behavior changes the expected result.
