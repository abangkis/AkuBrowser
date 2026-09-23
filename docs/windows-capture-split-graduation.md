# Windows capture split graduation

Status: **experimental; default off**. This is the acceptance record for
promoting the Windows split UI/capture path. The source implementation and unit
checks do not by themselves authorize changing the default. Use one frozen
AkuBrowser/AkuBridge/AkuSidecar source tuple and record its full commit SHAs,
generated installer hash, pinned UI Chromium hash, and database schema before
starting. Keep the ordinary single-process launch available for rollback.

The UI uses pinned Chrome for Testing with `ui-reader-broker` in its isolated
`-ui-split-cft` profile. Capture owns the original signed-in profile and
AkuBridge. Do not copy profiles, cookies, or credentials between them. See the
[split contract](windows-capture-split-experiment.md),
[containment contract](../../AkuSidecar/docs/windows-capture-containment.md), and
[reader-broker packaging contract](windows-reader-broker-packaging.md).

## Evidence required before changing the default

| Gate | Evidence to record | Pass condition |
| --- | --- | --- |
| Fresh install and upgrade | Installer/checksum, source tuple, profile paths, Bridge build ID, Sidecar schema, before/after data and login continuity | A clean install works without manual extension loading; an upgrade preserves source login and activates the exact worker/broker tuple. |
| Startup and profile isolation | Two root PIDs, Job Object ownership, executable identity, `--user-data-dir` roots, capture-host state, UI broker readiness | Capture and UI have different owned profiles; UI loads only its broker; the host starts minimized without an unresolved focus or Z-order interruption. |
| Background capture | At least five ordinary four-source batches while another application is in active use; source outcomes, duration, yield, focus-write attempts, covering classifications, containment readbacks, split action audit | No unrequested capture foreground or user-observed overlay; Bridge remains healthy and source quality/duration do not materially regress. Check every covering or foreground sample against the action audit and verified containment readback. |
| Explicit native post | Cold and reused/minimized reader attempts, foreground-switch cancellation, action/reader readback, then another background batch | The user-requested reader alone reaches foreground; rejected or stale actions fail visibly; the later batch does not reactivate it. |
| Startup recovery | Fresh profile first launch, UI `ready` acknowledgement, one-time automatic reload when needed, visible result | The UI becomes usable without a manual Ctrl+R or a second window. A failed one-time recovery gives a clear next action. |
| Shutdown | Close UI, close capture root, and normal Sidecar stop in separate runs; process-tree and port readback | Both owned Chromium trees and Sidecar exit; no orphaned reader broker or listener remains. |
| Rollback | Launch the same data/profile through the ordinary path after normal split shutdown | Legacy launch works without copying, resetting, or deleting either profile. |

Treat missing observations as **unverified**, not passed. The clean-machine
installer/upgrade checks belong to the current [Step 3B](windows-clean-machine-3b.md)
lane. A development-runtime canary may establish a narrower fact, but cannot
substitute for packaged install/upgrade evidence. Do not switch the default or
publish an RC with a failed or unverified required gate. Record screenshots and
bounded telemetry with the acceptance artifact; do not include post bodies,
URLs, cookies, or credentials.

## Current checkpoint

The development runtime has shown exact Bridge readiness, no background
`focused:true` writes in sampled batches, and explicit native-post foreground
readback. Two schema-28 batches at 23:12 and 23:28–23:30 UTC recorded capture
foreground or covering samples with no Bridge focused-write attempt. Their
causes remain unresolved because that version lacked a durable action audit.
Two later schema-29 batches overlapped accepted `open_native_post` actions;
the user confirmed clicking the native-post link during those tests. Their
foreground samples cannot establish background nonactivation.

Current development-process readback found two distinct root PIDs under the
same Sidecar parent: pinned Chrome for Testing with `ui-reader-broker` in the
isolated UI profile, and branded Chrome with AkuBridge in the original capture
profile. The capture-host window was visible and minimized at readback. This
does not independently prove separate Job Objects or packaged first-launch
behavior.

One controlled schema-29 four-source batch at 00:03–00:05 UTC completed with
the UI minimized and an external window verified in foreground before capture.
A 150-second probe sampled capture=0 and UI=0; all 1472 samples belonged to
external windows. Fifteen native traces contained no capture-foreground
classification, Bridge attempted zero focused writes, and the split-action
audit contained no new action. A second batch at 00:11–00:13 UTC kept the UI
open while another application held foreground; it also completed all four
sources, with capture=0 and UI=0 across 150 seconds, no focused write, and no
new explicit-action audit row. These are two of the five required ordinary
background batches, not a complete gate. One idle development restart used
Supervisor's normal Sidecar stop: it sent a graceful signal, reported no forced
termination, and found no owned PIDs afterward. The rebuilt runtime returned
healthy on schema 29. Separate UI-close and capture-root-close shutdown runs,
and packaged rollback, remain unverified. No clean Windows x64 VM/account is
currently available for fresh install and upgrade acceptance. Repeated
visible-workflow acceptance, live automatic startup recovery, capture host UX,
shutdown/orphan checks, and packaged rollback also remain open. The split
stays experimental until an acceptance record closes each gate above. The
[development canary receipt](../acceptance/windows-capture-split-dev-2026-09-23.json)
records the current failed and unverified gates without post content or URLs.
