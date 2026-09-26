# Windows headful capture split

New installed Windows tuples declare `windowsCaptureSplit: true`; their launcher
passes `--windows-capture-split` by default. Older tuples remain on the original
launch path. Start the installed launcher with `--legacy-single-process` after
normal shutdown to use the original path with the same data and capture profile.
The development-only experimental flag and environment alias have been retired;
use `--windows-capture-split` for a development split launch. The loopback port
must be 11122. macOS/Linux retain the existing launch/extension path. A source
change alone does not switch an already installed runtime; a verified new tuple must
be installed and activated.

The original `--browser-profile` (or runtime `app-profile`) stays exclusively
owned by capture Chromium. Source cookies, sign-ins and extension permissions
are neither moved nor copied. The UI uses pinned Chrome for Testing, a sibling
profile suffixed `-ui-split-cft`, and only the narrow `ui-reader-broker`
extension for explicit native-post activation. It does not load AkuBridge or
grant source-host permissions in that profile. The older `-ui-split` profile is
left intact. Profile aliases are rejected. Both roots are separate owned
processes with independent Windows Job Objects. Closing
the UI, exiting the capture root, or normal Sidecar shutdown terminates both.

Capture is headful and keeps a small dedicated host window, plus the existing
on-demand managed source windows. Startup observes its exact root HWND/PID,
verifies Job Object membership, requests `SW_SHOWMINNOACTIVE` once, and verifies
`IsIconic`. Unverified minimization aborts capture launch and cleans up its
owned tree. There is no `SetForegroundWindow`, normal-show request, or change
to unrelated windows. Chromium may display/promote its window before this
observation; the implementation does **not** promise zero startup focus changes.
`--start-minimized` is not assumed to exist. `--no-startup-window` was not used:
an MV3 worker alone is not a verified browser-lifetime guarantee here.

The host window must remain open while the app runs. Closing its last browser
window exits capture and consequently shuts down the paired UI. User-requested
source sign-in/permission and native-post reader windows still open visibly in
the capture process. No persistent host-window hiding or user-close suppression
is installed. Background capture windows have a Windows-only, non-activating
Z-order containment monitor; it does not guarantee zero transient paint. See
[the Sidecar containment contract](../../AkuSidecar/docs/windows-capture-containment.md)
for the exact ownership, foreground, and reader-exemption checks.

The capture host reports its handshake state. An unsupported/stale worker,
rejected bootstrap, or disconnected extension now becomes a visible failure
after six attempts (each bounded to eight seconds), rather than silent retries
forever. Chrome manifest version 0.9.2.0 uses a new thin worker entrypoint to
replace the pre-split registration on extension upgrade; AkuBridge product
version is 0.9.2, while the then-current installed app and Sidecar were 0.9.1.
Browser restart alone had retained the old 0.9.1.1 worker cache during
the first Windows acceptance attempt. No cache/profile deletion was required;
the later development runtime reported exact v111 identity and healthy Bridge
readiness after restart. This does not establish a packaged fresh-install or
upgrade result.

The explicit-reader generation is `source-adapters-v111` with entrypoint
`service-worker-entry-v3.js`; the Sidecar expects its distinct build ID before
reporting reload completion. A successful `open_native_post` result additionally
requires successful native foreground readback for that same action. A stale
worker returning success without that handshake receives a terminal failure
in the UI instructing an AkuBridge reload, rather than false success or a queue
timeout. Native prepare, foreground and final-result outcomes are logged.

## Transport and supported actions

The ordinary UI Bridge path uses a server-injected same-origin adapter. The
separate `ui-reader-broker` content script is limited to trusted-click
correlation, readiness, and the one-time startup reload. The adapter preserves
the existing UI message contract and sends typed, authenticated
requests to an in-memory Sidecar queue. Capture's extension bootstraps from an
ephemeral launch capability, then polls that queue and uses the existing Bridge
command/heartbeat/lease APIs. The capability is not printed in startup logs.

Supported: Bridge readiness, timeline/batch dispatch and background pumping,
source-session probes, source open and source-specific permission broker,
lease-scoped release, media recapture/evidence lookup, native-post reading,
extension self-reload, and source-access revocation. UI-ready messages cannot
refresh capture heartbeat authority; only the active capture instance can.
The permission broker retains Chrome's user gesture on its own Allow button.

The queue allows 32 outstanding actions and waits at most 115 seconds per UI
request. Claims are at most once; timeout does not replay an action that may
already be executing. Capture operations retain existing bounded acquisition
budgets and lease guards. An instance key and Sidecar epoch reject stale worker
claims/results and old UI requests. Credentials come from Sidecar bootstrap,
never from arbitrary action endpoint/token payloads. On restart, pending UI
control actions disappear; existing durable command recovery remains in force.

The split isolates app-shell promotion from capture-process Z-order behavior.
The bounded containment monitor corrects observed capture-window promotion,
but does not prove that a transient overlay can never occur. Native trace
attribution uses the capture root PID.

## Validation and activation boundary

Automated coverage exercises profile separation, default/platform gate,
authenticated queue round trips, stale-instance rejection, UI-heartbeat fencing,
bounded queue, typed worker dispatch, reader-broker authorization, containment,
and epoch mismatch. It does not establish real Chromium lifetime or focus
behavior. Development acceptance has observed healthy split Bridge readiness,
background batches without focus writes, and explicit native-post foreground
readback. The owner approved the Windows source default after development
canaries, while packaged fresh install and upgrade, live automatic white-screen
recovery, and capture-host UX remain unverified. Record capture and app-shell
outcomes separately; retain the legacy launch path as a rollback switch.

Fallback reference: `pre-headful-capture-split-2026-09-21`. For an installed
split tuple, use `AkuBrowserLauncher.exe --legacy-single-process` after normal
shutdown. For a development launch, omit `--windows-capture-split` or set it to
`false`. The original authenticated profile resumes the ordinary
single-process role; the separate UI profile is left intact. No profile
deletion, copy-back, or automatic Git reset is part of fallback.
