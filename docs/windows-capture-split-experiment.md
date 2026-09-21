# Windows headful capture split (experimental, default off)

Enable only in an explicitly selected test run with Sidecar's
`--app-shell --experimental-windows-capture-split`, or inherit
`AKUBROWSER_EXPERIMENTAL_WINDOWS_CAPTURE_SPLIT=1` into the normal launcher.
The loopback port must be 11122. No installed runtime is switched by building
the code. On macOS/Linux the flag is ignored and the existing single-process
launch/extension path is retained. Normal Windows launches remain unchanged.

The original `--browser-profile` (or runtime `app-profile`) stays exclusively
owned by capture Chromium. Source cookies, sign-ins and extension permissions
are neither moved nor copied. UI Chromium gets a sibling directory suffixed
`-ui-split`, with extensions disabled. Profile aliases are rejected. Both roots
are separate owned processes with independent Windows Job Objects. Closing
the UI, exiting the capture root, or normal Sidecar shutdown terminates both.

Capture is headful and keeps a small dedicated host window, plus the existing
on-demand managed source windows. Startup observes its exact root HWND/PID,
verifies Job Object membership, requests `SW_SHOWMINNOACTIVE` once, and verifies
`IsIconic`. Unverified minimization aborts capture launch and cleans up its
owned tree. There is no `SetForegroundWindow`, normal-show request, or change
to unrelated windows. Chromium may display/promote its window before this
observation; the experiment does **not** promise zero startup focus changes.
`--start-minimized` is not assumed to exist. `--no-startup-window` was not used:
an MV3 worker alone is not a verified browser-lifetime guarantee here.

The host window must remain open while the app runs. Closing its last browser
window exits capture and consequently shuts down the paired UI. User-requested
source sign-in/permission and native-post reader windows still open visibly in
the capture process. No persistent host-window hiding or user-close suppression
is installed.

The capture host reports its handshake state. An unsupported/stale worker,
rejected bootstrap, or disconnected extension now becomes a visible failure
after six attempts (each bounded to eight seconds), rather than silent retries
forever. Chrome manifest version 0.9.1.2 uses a new thin worker entrypoint to
replace the pre-split registration on extension upgrade; product version stays
0.9.1. Browser restart alone had retained the old 0.9.1.1 worker cache during
the first Windows acceptance attempt. No cache/profile deletion is required.
Actual upgrade/readiness still needs confirmation after the next authorized
restart; these source changes do not reload the currently running extension.

## Transport and supported actions

The UI has no content-script dependency. A server-injected same-origin adapter
preserves the existing UI message contract and sends typed, authenticated
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
It does not fix Chromium's capture-window behavior or prove capture windows
never foreground. Native trace attribution now uses the capture root PID.

## Validation and activation boundary

Automated coverage exercises profile separation, default/platform gate,
authenticated queue round trips, stale-instance rejection, UI-heartbeat fencing,
bounded queue, typed worker dispatch, and epoch mismatch. It does not establish
real Chrome lifetime/focus behavior. No Chrome runtime was launched by these
implementation checks. Windows live acceptance remains required: inspect two
root PIDs/user-data directories, confirm UI extensions are disabled, verify
capture host minimized state, then test source sign-in, permission grant,
timeline batch dispatch/release, media recapture, native post, reload/revoke,
and close/shutdown with no orphan processes. Compare focus/Z-order telemetry
while typing in an external application; report capture/app-shell outcomes
separately. Do not call this a proven focus fix before those observations.

Fallback reference: `pre-headful-capture-split-2026-09-21`. To stop experimenting,
launch without the flag/environment variable after normal shutdown. The original
authenticated profile resumes the ordinary single-process role; the separate UI
profile is left intact. No profile deletion, copy-back, or automatic Git reset
is part of fallback.
