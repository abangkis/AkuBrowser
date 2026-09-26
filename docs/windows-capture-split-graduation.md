# Windows capture split graduation

Status: **owner-accepted as passed for Windows capture split on 2026-09-26**.
The owner accepted the split after reviewing the live two-process runtime and
the development canary, including its known evidence limits. This product
decision supersedes the earlier 2026-09-23 default-only approval. Individual
unobserved checks remain unverified and belong to Windows installed-app
acceptance; they are not retroactively marked as measured passes. This is the
acceptance record for the Windows split UI/capture path. Use one frozen
AkuBrowser/AkuBridge/AkuSidecar source tuple and record its full commit SHAs,
generated installer hash, pinned UI Chromium hash, and database schema before
starting. Keep the ordinary single-process launch available for rollback.

The UI uses pinned Chrome for Testing with `ui-reader-broker` in its isolated
`-ui-split-cft` profile. Capture owns the original signed-in profile and
AkuBridge. Do not copy profiles, cookies, or credentials between them. See the
[split contract](windows-capture-split-experiment.md),
[containment contract](../../AkuSidecar/docs/windows-capture-containment.md), and
[reader-broker packaging contract](windows-reader-broker-packaging.md).

## Acceptance evidence and remaining verification

| Gate | Evidence to record | Pass condition |
| --- | --- | --- |
| Fresh install and upgrade | Installer/checksum, source tuple, profile paths, Bridge build ID, Sidecar schema, before/after data and login continuity | A clean install works without manual extension loading; an upgrade preserves source login and activates the exact worker/broker tuple. |
| Startup and profile isolation | Two root PIDs, Job Object ownership, executable identity, `--user-data-dir` roots, capture-host state, UI broker readiness | Capture and UI have different owned profiles; UI loads only its broker; the host starts minimized without an unresolved focus or Z-order interruption. |
| Background capture | At least five ordinary four-source batches while another application is in active use; source outcomes, duration, yield, focus-write attempts, covering classifications, containment readbacks, split action audit | No unrequested capture foreground or user-observed overlay; Bridge remains healthy and source quality/duration do not materially regress. Check every covering or foreground sample against the action audit and verified containment readback. |
| Explicit native post | Cold and reused/minimized reader attempts, foreground-switch cancellation, action/reader readback, then another background batch | The user-requested reader alone reaches foreground; rejected or stale actions fail visibly; the later batch does not reactivate it. |
| Startup recovery | Fresh profile first launch, UI `ready` acknowledgement, one-time automatic reload when needed, visible result | The UI becomes usable without a manual Ctrl+R or a second window. A failed one-time recovery gives a clear next action. |
| Shutdown | Close UI, close capture root, and normal Sidecar stop in separate runs; process-tree and port readback | Both owned Chromium trees and Sidecar exit; no orphaned reader broker or listener remains. |
| Rollback | Launch the same data/profile through the ordinary path after normal split shutdown | Legacy launch works without copying, resetting, or deleting either profile. |

The owner accepts Windows capture split as passed at the product-decision level.
Treat missing observations as **unverified**, not measured passes. The clean-machine
installer/upgrade checks belong to the current [Step 3B](windows-clean-machine-3b.md)
lane. A development-runtime canary may establish a narrower fact, but cannot
substitute for packaged install/upgrade evidence. Record those limits in any
future RC notes; release publication remains a separate decision. Record screenshots and
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
new explicit-action audit row. Three further clean batches at 00:49–00:51,
00:52–00:54, and 00:58–01:00 UTC each completed all four sources with the UI
open, no capture or UI foreground probe sample, no focused write, and no
split-action audit row. Thus five ordinary development-runtime background
batches meet the repeated nonactivation sample count. Their session durations
were 119.81, 87.13, 94.75, 89.73, and 90.26 seconds. Facebook and Instagram
were `usable_degraded` in all five, matching the first two clean batches;
LinkedIn was `complete` throughout; X was `usable_degraded` in one later batch
and `complete` in the other four. This series does not prove quality parity
against a contemporary ordinary-path baseline. Other attempted batches were
excluded after UI interaction or an external app switch; see the development
receipt for the exact windows and attribution limits. The bounded
[foreground probe samples](../acceptance/windows-capture-split-foreground-probes-2026-09-23.json)
retain seven later attempts with session/run status, native classifications,
focused-write counts, and foreground transitions, without captured content.

One idle development restart used Supervisor's normal Sidecar stop: it sent a
graceful signal, reported no forced termination, and found no owned PIDs
afterward. Separate development-runtime UI-close and capture-host-close runs
also ended Sidecar, both Chromium trees, reader broker, and the port without
orphan processes. An ordinary-path rollback used the same Sidecar binary,
original browser profile, and schema-29 data after normal split shutdown. It
started one Chrome root, retained 277 Timeline items, passed SQLite
`quick_check`, and returned a compatible Bridge with access to all four sources.
Its four-source comparison batch completed in 71.48 seconds with Facebook and
Instagram `usable_degraded` and LinkedIn and X `complete`. One ordinary-path
sample does not establish duration parity. X first-round source readiness
waited about 12 seconds in each split batch versus 1.83 seconds in this one
ordinary-path sample. The five split windows were minimized with incomplete
visual hydration; the ordinary-path window was normal and visually ready.
The current X readiness policy waits up to 12 seconds for hydrated media, then
allows a `feed_ready` capture. Shortening that wait may admit incomplete media;
restoring the capture window may violate quiet focus. This tradeoff needs a
validated policy and repeated comparison. The original Supervisor
configuration was restored byte-for-byte and split mode returned healthy.
One split restart exposed the capture host visible but not minimized; a later
restart showed it minimized. The cause is unresolved, so startup-host behavior
remains a follow-up verification item. Packaged rollback is still unverified. No clean Windows x64 VM/account is
currently available for fresh install and upgrade acceptance. A local
v0.9.1 installed-app tuple and unsigned installer were built from clean
AkuBrowser `7b1d693`, AkuSidecar `4b74396`, and AkuBridge `d36fda4` commits;
the tuple and installer verifiers passed, and the installer SHA-256 is recorded
in the development receipt. This proves package structure and hashes, not
installation or upgrade behavior. Repeated
visible-workflow checks, live automatic startup recovery, capture host UX,
and packaged shutdown/rollback checks also remain unverified. The split is the
source default for new Windows tuples and owner-accepted as passed, while these
verification limits remain explicit. The
[development canary receipt](../acceptance/windows-capture-split-dev-2026-09-23.json)
records the current failed and unverified gates without post content or URLs.
