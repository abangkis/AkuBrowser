# How Auto Update works

AkuBrowser keeps the Timeline finite, but a finite Timeline should not require
the user to stop and wait for a multi-minute **Check for updates** every time.
Auto Update moves that waiting time into bounded background work. It prepares a
small number of local batches while AkuSidecar is available, then lets the user
decide when the next batch enters the reading flow.

Auto Update does not create an endless feed. Every automatic check is the same
inspectable capture, evaluation, selection, and composition pipeline used by a
manual check. The resulting session appears in Update Inbox, consumes the same
local model-usage ledger, and must pass the same source and evidence contracts.
The difference is delivery: its selected items remain hidden in a `prepared`
batch until the user reveals them.

## When an automatic check may start

AkuSidecar owns the scheduler, so Auto Update can run only while AkuSidecar is
alive. It also requires compatible AkuBridge state, completed onboarding and
first-run calibration, no active manual or automatic check, queue capacity, and
enough local model budget for the estimated next run.

The scheduler treats the prepared queue as bounded capacity, not as a
four-hour appointment. When a slot opens because a batch is revealed, expires,
or a prior automatic check produced no prepared batch, the scheduler waits for
the configured refill delay before it may try to refill that slot. The setting
offers 3, 5, and 10 minutes; 5 minutes is the default. If more capacity
remains after the next check, another refill may start no sooner than that
delay later. Queue and model-budget boundaries can delay it further.

**Adaptive activity** is the default and associates refilling with actual user
activity. Opening AkuBrowser records one access; later pointer, keyboard,
touch, wheel, or visible-tab-return activity renews it at a bounded rate.
Background status polling does not count. After activity is no longer recent,
the scheduler pauses even when freshness expiration opens a queue slot. When
the user returns, AkuSidecar catches up under the same refill-delay, capacity,
and budget rules. This prevents an unattended open page from continually
replacing batches while its user sleeps.

**Fixed background** scheduling does not require recent human activity. While
AkuSidecar is alive, its bounded scheduler may refill an open slot after each
configured refill boundary. This is an explicit opt-in for users who prefer prepared
work while away; queue capacity, freshness, and budget still bound it.
AkuBridge's service worker can claim pending capture commands even when the
AkuBrowser page is closed. Neither mode starts a stopped AkuSidecar or bypasses
queue, budget, or active-session limits.

Settings also provides **Run automatic check now** when the user wants to
start a background-style batch immediately. This explicit action still checks
onboarding, Bridge readiness, prepared-batch capacity, active sessions, and
the automatic token allowance. It bypasses only the scheduler's minimum
configured refill delay and Adaptive recent-use waits; resetting the quota does not
itself force a run.

## Prepared batches and reading continuity

An automatic session with selected items becomes a prepared batch in SQLite.
Prepared items remain absent from the Timeline query, but the session and its
diagnostics are already visible in Update Inbox. The default finish-line action
is **Open next prepared batch**. Revealing changes that batch from `prepared` to
`visible` without rerunning reasoning.

Settings reports queue capacity explicitly as prepared batches, configured
limit, and open slots. A prepared count of zero therefore does not mean Auto
Update is disabled; it means all configured slots are currently available for
refill when scheduling, activity, and budget admission permit it.

The existing Timeline remains in its current reading order when a prepared
batch is opened. The newly revealed batch is placed after the material the user
has just consumed, a **New prepared batch** boundary identifies its first item,
the scroll position is restored, and the user can continue downward into the
new batch. A later fresh page load may reconstruct the normal
newest-first Timeline; the continuity ordering is for the active reading
session.

The optional auto-load mode uses the same reveal operation. It takes a snapshot
of batches that were already prepared when the reading session began. When the
user scrolls downward to the finish line, one of those batches may be revealed.
AkuBrowser does not scroll on the user's behalf, and a batch prepared after the
snapshot waits for the next reading session. This prevents an endless feed from
forming underneath the user.

## Budget allocation, exhaustion, and reset

AkuBrowser records local model usage for acquisition planning, candidate
evaluation, semantic event resolution, and AI Deep Detection. Local AI Fast
Detection does not spend model tokens. Before an automatic check starts,
AkuSidecar estimates the next run from recent sessions and verifies that both
the daily quota and the automatic allowance can contain it.

The selectable daily quotas are 1M, 2M, 3M, and 5M tokens. The default is 1M.
The manual-reserve percentage is removed from the automatic allowance, so
background work cannot consume the entire configured quota. An explicit manual
**Check for updates** remains a higher-authority user action and is not blocked
by the Auto Update gate.

When the daily quota or automatic allowance cannot contain the estimated next
run, the scheduler enters `budget_paused`. The Timeline shows the paused state,
while Settings shows actual usage since local midnight, usage against the
current quota window, remaining capacity, automatic allowance, and manual
reserve. Prepared batches remain available.

The quota normally resets at local midnight. The user may instead increase the
configured quota or choose **Reset today's quota**. A manual reset establishes
a new local allowance baseline at the current counters. It preserves every
invocation record and continues to show actual usage for the day. It does not
reset an external Codex limit or reduce billing; it only authorizes AkuBrowser
to spend more tokens automatically during that local day.

## Freshness and urgency

A prepared batch has a bounded freshness window. The default is 24 hours, but
the highest candidate urgency can shorten it. Urgency is already part of the
candidate assessment and describes time sensitivity rather than importance or
popularity. Same-day information may shorten freshness to 12 hours, information
useful within a few hours to 4 hours, and immediate or action-critical material
to 2 hours. An expired unread batch is not published into the Timeline; its
diagnostic session remains inspectable.

Expiration opens queue capacity, but it does not by itself prove that the user
is present. Adaptive activity therefore leaves the slot empty while the user
is inactive and resumes when the user returns. Fixed background may refill it
while the user is away, within its configured refill and budget boundaries.

## Capture lease and manual checks

AkuBridge assigns the automatic session a capture lease: an ownership record
for the Bridge-managed source tab or quiet-capture window. The lease is retained
across initial and follow-up acquisition so the adapter keeps the same source
frontier instead of reopening or losing its place. It is released only after
the owning session becomes terminal. Cleanup closes only Bridge-owned surfaces
and preserves user-created tabs.

A manual **Check for updates** never overlaps an automatic one. If manual work
starts first, Auto Update waits. If automatic work is already active, the UI
shows its progress and keeps Inbox and Settings available. Both paths converge
on the same finite Timeline, provenance, personalization authority, and
inspectable run ledger.
