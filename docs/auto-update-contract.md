# Auto Update contract

Auto Update removes repeated foreground waiting without turning
the finite Timeline into an endless feed. AkuSidecar owns one persistent
scheduler. It may prepare bounded update sessions only while AkuSidecar is
running, AkuBridge is compatible, onboarding and calibration allow another
check, no update session is active, and both queue and model-budget
boundaries allow it.

## Scheduling and authority

- **Presence-aware** is the user-facing name for the persisted `adaptive`
  policy and remains the default. It selects one of three cadences from the
  last explicit activity: `active` at 5 minutes while activity is at most 5
  minutes old, `warm` at 15 minutes while activity is at most 30 minutes old,
  and `idle` at 60 minutes after that or when activity has never been recorded.
  A successful visible bootstrap, visible pointer, keyboard, touch, wheel,
  tab-return, or active-video playback renews activity at a bounded rate. A
  read-only bootstrap/status fetch, status polling, and a merely open but
  unattended tab are not user activity. Idle slows scheduling; it does not
  stop it.
- **Continuous background** is the user-facing name for the persisted `fixed`
  policy. While AkuSidecar is alive, it evaluates one periodic tick on a
  configurable 5-, 10-, 15-, 30-, or 60-minute interval, with 15 minutes as the
  default. Each tick checks compatibility, calibration, active-session, queue,
  and budget stoppers once. Whether the tick starts work or is skipped, the
  next evaluation waits for the next configured interval. Revealing or
  expiring a batch does not trigger an immediate Continuous-background retry.
- Both modes use the same tick-consumption and stopper path. They differ only
  in whether the cadence comes from the activity tier or the configured fixed
  interval. Queue-vacancy events do not bypass either cadence.
- Every due scheduler tick writes a durable local receipt before admission.
  The receipt records its mode, cadence tier/minutes, tick and next-tick time,
  then resolves from `checking` to `started` with the prepared session ID or
  `skipped` with the exact stopper reason. A crash can therefore leave an
  inspectable `checking` receipt instead of erasing the attempted boundary.
  Storage keeps only the newest 32 receipts; status exposes the newest 10 and
  Settings summarizes the latest one. Manual **Prepare batch now** is not a
  scheduler tick and creates no scheduler receipt.
- User actions and user settings remain authoritative. Update sessions never
  overlap.
- Settings exposes **Prepare batch now** for an explicit user-triggered
  prepared run. It keeps the same onboarding, Bridge, queue, active-session,
  and token-budget gates, but deliberately bypasses only the scheduler's
  cadence gate. Resetting the quota alone
  never bypasses those scheduler boundaries.
- Automatic work pauses when the prepared queue is full or its daily allowance
  is exhausted. The selectable daily boundaries are 1M, 2M, 3M, and 5M tokens,
  with 2M as the default. A protected share is unavailable to automatic work
  and remains available to an explicit user-visible update.

## Prepared batches

Any session with `delivery=prepared` remains inspectable in Update Inbox, but its
Timeline items are hidden in a prepared batch until the user reveals it. The
finish line offers **Continue with next batch**, preserving reading order and
scroll position. The Timeline header offers **Load latest batch**, rebuilding
newest-first order by explicitly placing the newly revealed batch before the
currently visible Timeline, then moving the reader to the top. Repeated header
reveals therefore show Batch 2 above Batch 1. The finish-line path explicitly
places each newly revealed batch after the currently visible Timeline, so
Batch 2 continues below Batch 1. Neither path infers presentation order from
session completion timestamps. Optional auto-load uses the
finish-line continuity path and never scrolls on the user's behalf. The header
also keeps **Update now** available as an independent `user/visible/user`
request, regardless of whether Auto Update is enabled or a prepared batch is
waiting. Starting another update remains blocked while any update is active,
but revealing an already-terminal prepared batch remains available during that
work: it changes only queue visibility and the local Timeline projection.

The queue defaults to two batches. Unread batches expire at the configured
freshness boundary. Candidate Evaluation supplies urgency on a stable rubric:

- `0.00-0.24`: evergreen;
- `0.25-0.49`: contextual;
- `0.50-0.74`: useful within the same day;
- `0.75-0.84`: useful within a few hours;
- `0.85-1.00`: immediate or action-critical.

Urgency is time sensitivity, not importance or popularity. The most urgent item
in a prepared batch can shorten its effective freshness window to 12, 4, or 2
hours. Expired batches remain represented by their underlying run diagnostics;
they are not published into the Timeline.

Expiration opens a queue slot but does not count as user activity.
Presence-aware reconsiders that slot on its next active, warm, or idle tick;
new activity can shorten the next due boundary. Continuous background
reconsiders it on its next configured tick. The status contract exposes the
last activity time, 30-minute warm boundary, current cadence tier and minutes,
last scheduler tick, next scheduled tick, prepared count, configured limit,
and available slots so presence, cadence, capacity, and budget remain separate
observable gates. Full reset clears scheduler receipts and the last-tick
boundary; learning reset does not.

## Model budget

Budget enforcement uses locally retained invocation telemetry from acquisition
planning, candidate evaluation, semantic event resolution, and AI Deep
Detection. Automatic admission uses a conservative estimate before starting.
Actual usage is then counted from midnight in the Sidecar host's local time.
AI Deep Detection is optional for an automatic session and is skipped when its
additional estimate would cross the automatic allowance. Local AI Fast
Detection does not spend model tokens.

The token value is a safety boundary over AkuBrowser's local telemetry, not an
external Codex billing or quota guarantee. Reset and retention can narrow the
available history.

The UI exposes actual tokens consumed since the local host's midnight, usage
counted against the current local quota window, remaining daily capacity,
remaining automatic allowance, and the protected user reserve. When the
daily budget or automatic allowance is exhausted, automatic admission changes
to `budget_paused`; no new automatic session is started until the local day
resets, the user changes the setting, or the user explicitly resets today's
local quota. A quota reset records the current counters as a new baseline. It
does not delete invocation history, change external Codex billing or quota, or
pretend the earlier usage did not happen. With Auto Update disabled, **Update
now** remains available subject to the ordinary runtime, Bridge, calibration,
and source checks.

## Unified update policy

Every update session carries three independent authority fields:

- `trigger`: `onboarding`, `scheduler`, or `user`;
- `delivery`: `visible` or `prepared`;
- `budgetAuthority`: `user` or `automatic`.

The scheduler uses `scheduler/prepared/automatic`. **Prepare batch now** uses
`user/prepared/automatic`. Onboarding uses
`onboarding/visible/user`. **Update now** always uses `user/visible/user`.
There is no separate manual pipeline.

The Timeline exposes `paused` and `budget_paused` without requiring a visit to
Settings. Settings remains the control surface for changing or resetting the
quota.

## Lifecycle

Auto Update does not install an OS service or wake a stopped Sidecar. Starting
AkuSidecar starts the scheduler; shutting it down cancels the scheduler and any
active background work. A later Sidecar start reconstructs queue and schedule
state from SQLite and catches up when policy allows.

The first trusted AkuBrowser page access configures AkuBridge with the local
Sidecar endpoint and durable Bridge token. AkuBridge polls for persisted
pending capture commands at a bounded one-minute cadence, so Fixed background
work can continue after the page closes. After a background observation it
also performs a short bounded session pump: as soon as one source closes
Acquisition, Bridge receives an explicit per-source cleanup request and releases
that source without waiting for the next alarm. The one-minute alarm remains a
crash/reload fallback rather than the primary cleanup timer. Visible interaction
or active playback accelerates Presence-aware cadence but is not required for its idle tick. Invalid or rotated credentials are deleted by AkuBridge
after an authenticated rejection and are configured again on the next trusted
page access. Background and page dispatch both claim the same command, so only
one can win. AkuBridge persists the active capture lease across bounded
follow-up commands in a version-two managed-surface ledger. Every Bridge-created
managed window or Adaptive tab remains in that ledger until a cleanup receipt
exists. Ledger reconciliation runs when the extension starts or reloads and
before another lease takes ownership; it closes only still-provable Bridge
surfaces and preserves anything adopted by the user. Terminal source/session
cleanup remains the fallback. The same poll refreshes the authenticated Bridge
heartbeat, allowing a restarted Sidecar to recover exact Bridge compatibility
without waiting for the UI to open.
