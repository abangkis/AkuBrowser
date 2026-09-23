# RC8 installed-app acceptance on an existing Windows account

Decision: **partial, not a clean-machine pass**. This record covers the
published `v0.9.0-rc.8` installer on an existing Windows account that had no
prior installed-app registration, program directory, installed data, or
installed browser profile. Development-runtime data and signing material were
left intact. It does not represent an independent Windows account or VM.

## Frozen artifact

| Item | Value |
| --- | --- |
| Installer | `AkuBrowserSetup-0.9.0-windows-x64.exe` |
| SHA-256 | `b3270aae847ac08a8bcbdd788312802316f42ee7b21eb3c0866a30f2db02c3b0` |
| AkuBrowser source | `42ac9958044870f96ce9bbaa102003c24b80b0c7` |
| AkuSidecar source | `46b4a6142659a25d5b0a1d62e63b614e6630dfc5` |
| AkuBridge source | `62fd01b03c2dc2dc41327f37ddcdcdb14bcf1346` |
| Installed runtime | `0.9.0`, schema 29, pinned Chromium `152.0.7977.54` |
| Trust state | unsigned |

## Observed result

- The installer exited 0 and registered the installed app, launcher, Sidecar,
  bundled Bridge, native reader host, and active tuple. The first launch did
  **not** work without intervention: Avast One AutoSandbox recorded termination
  of the unsigned launcher and Sidecar; Sidecar execution returned `Access is
  denied`. With a user-added temporary exception limited to the installed-app
  program folder, `AkuBrowserLauncher.exe --verify-only` exited 0 and normal
  startup proceeded. The exception remains a test condition, not a product fix.
- Sidecar reported `/api/health` `ok`, version `0.9.0`, database `healthy`.
  Bridge reported `healthy` and compatible with build
  `aku-bridge-0.9.2-source-adapters-v111`. Startup produced separate UI and
  capture Chromium roots. Capture used the isolated source profile with
  bundled AkuBridge; UI used the separate `browser-profile-ui-split-cft`
  profile with `ui-reader-broker`. Both native-host registrations pointed to
  the installed version's manifest. The local web UI rendered Source Setup;
  visual confirmation of the installed Chromium app shell is pending.
- Cooperative Sidecar shutdown returned HTTP 202 and removed the installed
  launcher and Sidecar. Ordinary silent uninstall exited 0, removed the
  program directory and its registry entries, and preserved both database and
  browser profile. The database SHA-256 immediately before and after uninstall
  was identical. Reinstall exited 0, preserved that hash, verified the active
  tuple, and started with healthy database and Bridge.
- Same-version repair exited 0 and restored the installed reader-host entries.
  The application started afterward with healthy database and Bridge. Byte
  preservation across repair was not measured immediately before the repair.
- Packaged `--legacy-single-process` launch used the same database and source
  profile with one Chromium root. It reported healthy database and compatible
  Bridge. After normal shutdown, default launch restored separate UI and
  capture roots and the healthy Bridge. This proves the packaged mode switch,
  not source quality parity or complete rollback behavior.

## Unverified gates

At 07:49 UTC, the new profile remained at `onboarding: not_started`. Bridge
reported permission, script registration, and access readiness for X,
LinkedIn, Facebook, and Instagram after the user granted access. This alone
was not evidence of authenticated source sessions. A later first update
completed X, LinkedIn, and Instagram, and produced seven Timeline items.
Facebook returned `login_required` despite the user's report of signing in;
that discrepancy still needs diagnosis. The first update was partial, not a
four-source pass. Provider use, explicit native
post activation, visual startup recovery, capture-host minimized and focus
behavior, full reset, prior-RC upgrade with login continuity, and independent
clean-machine behavior are unverified. No newer RC may claim these gates passed
based on this receipt. The temporary Avast exception was reported removed by
the user after local testing; its removal was not independently verified.
