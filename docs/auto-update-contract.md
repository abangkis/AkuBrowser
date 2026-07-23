# Auto Update contract

Auto Update reduces repeated manual **Check for updates** work without turning
the finite Timeline into an endless feed. AkuSidecar owns one persistent
scheduler. It may prepare bounded update sessions only while AkuSidecar is
running, AkuBridge is compatible, onboarding and calibration allow another
check, no manual or automatic session is active, and both queue and model-budget
boundaries allow it.

## Scheduling and authority

- **Adaptive activity** is the default. It catches up after AkuBrowser is
  opened and only continues while actual pointer, keyboard, touch, wheel, or
  visible-tab-return activity is recent. Status polling is not user activity.
- **Fixed background** does not require recent human activity while AkuSidecar
  is alive and the configured AkuBridge service worker can reach it.
- Open prepared-queue capacity is refilled on a configurable 3-, 5-, or
  10-minute cadence, with 5 minutes as the default. Revealing or expiring a
  prepared batch establishes a new vacancy boundary; a failed or empty
  automatic attempt establishes the next attempt boundary. Another automatic
  run cannot begin before the later applicable boundary.
- Manual **Check for updates** and user settings remain authoritative. Manual
  and automatic sessions never overlap.
- Settings exposes **Run automatic check now** for an explicit user-triggered
  background run. It keeps the same onboarding, Bridge, queue, active-session,
  and token-budget gates, but deliberately bypasses only the scheduler's
  configured refill delay and adaptive recent-use gates. Resetting the quota alone
  never bypasses those scheduler boundaries.
- Automatic work pauses when the prepared queue is full or its daily allowance
  is exhausted. The selectable daily boundaries are 1M, 2M, 3M, and 5M tokens,
  with 1M as the default. A protected share is unavailable to automatic work
  and remains available to an explicit manual check.

## Prepared batches

An automatic session is stored and remains inspectable in Update Inbox, but its
Timeline items are hidden in a prepared batch until the user reveals it. The
default behavior requires **Open next prepared batch** at the finish line. The
optional auto-load behavior reveals only a batch that was already prepared when
the current reading session began, and only when the user scrolls down to the
finish line. It never scrolls by itself and newly prepared batches wait for the
next reading session.

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

Expiration opens a queue slot but does not count as user activity. Adaptive
activity leaves that slot empty while the user is inactive and resumes on
return, preventing unattended freshness churn. Fixed background may refill the
slot while the user is away. The status contract exposes prepared count,
configured limit, and available slots so this state is visible rather than
inferred.

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
remaining automatic allowance, and the protected manual reserve. When the
daily budget or automatic allowance is exhausted, automatic admission changes
to `budget_paused`; no new automatic session is started until the local day
resets, the user changes the setting, or the user explicitly resets today's
local quota. A quota reset records the current counters as a new baseline. It
does not delete invocation history, change external Codex billing or quota, or
pretend the earlier usage did not happen. Manual **Check for updates** remains
available, subject to the ordinary runtime, Bridge, calibration, and source
checks.

The Timeline exposes `paused` and `budget_paused` without requiring a visit to
Settings. Settings remains the control surface for changing or resetting the
quota.

## Lifecycle

Auto Update does not install an OS service or wake a stopped Sidecar. Starting
AkuSidecar starts the scheduler; shutting it down cancels the scheduler and any
active background work. A later Sidecar start reconstructs queue and schedule
state from SQLite and catches up when policy allows.

The first trusted AkuBrowser page access configures AkuBridge with the local
Sidecar endpoint and durable Bridge token. AkuBridge then polls for persisted
pending capture commands at a bounded one-minute cadence, so Fixed background
work can continue after the page closes. Adaptive activity still requires
recent human interaction by policy. Invalid or rotated credentials are deleted by AkuBridge
after an authenticated rejection and are configured again on the next trusted
page access. Background and page dispatch both claim the same command, so only
one can win. AkuBridge persists the active capture lease across bounded
follow-up commands and releases the managed surface after the owning automatic
session becomes terminal. The same poll refreshes the authenticated Bridge
heartbeat, allowing a restarted Sidecar to recover exact Bridge compatibility
without waiting for the UI to open.
