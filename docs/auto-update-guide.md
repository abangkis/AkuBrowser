# How Auto Update works

AkuBrowser keeps the Timeline finite, but a finite Timeline should not require
the user to stop and wait for a multi-minute update every time.
Auto Update moves that waiting time into bounded background work. It prepares a
small number of local batches while AkuSidecar is available, then lets the user
decide when the next batch enters the reading flow.

Auto Update does not create a second update engine or an endless feed. Every
update uses one inspectable capture, evaluation, selection, and composition
pipeline. A policy attached to the session declares its trigger
(`onboarding`, `scheduler`, or `user`), delivery (`visible` or `prepared`), and
budget authority (`user` or `automatic`). The result always appears in Update
Inbox and uses the same source, evidence, and local model-usage contracts.

## When an automatic check may start

AkuSidecar owns the scheduler, so Auto Update can run only while AkuSidecar is
alive. It also requires compatible AkuBridge state, completed onboarding and
first-run calibration, no active update, queue capacity, and
enough local model budget for the estimated next run.

The scheduler treats the prepared queue as bounded capacity, not as an endless
feed. Continuous background exposes an interval of 5, 10, 15, 30, or 60
minutes; 15 minutes is the default. At each tick it evaluates all stoppers once.
If the queue is full, the daily or automatic token allowance is insufficient,
AkuBridge is unavailable, calibration blocks work, or another session is
active, that tick is skipped and the scheduler waits for the next full
interval. A newly opened queue slot does not create an immediate retry.

**Presence-aware** is the clearer user-facing name for the stored `adaptive`
policy. It adapts cadence to demand, not token price. Explicit activity no more
than 5 minutes old selects the 5-minute `active` cadence; activity between 5
and 30 minutes old selects the 15-minute `warm` cadence; older or missing
activity selects the 60-minute `idle` cadence. A successful visible bootstrap,
pointer, keyboard, touch, wheel, visible-tab-return, or active-video playback
renews activity at a bounded rate. A read-only bootstrap/status fetch and a
merely visible but unattended page do not count. Idle scheduling continues
slowly rather than stopping, while new activity wakes the scheduler and can
make the next tick due sooner.

**Continuous background** is the clearer user-facing name for the stored
`fixed` policy. While AkuSidecar is alive, its independent periodic cadence
continues regardless of user presence. The interval appears in Settings only
when this mode is selected. A tick is an evaluation opportunity rather than a
guaranteed run: queue capacity, freshness, budget, Bridge readiness,
calibration, and single-session serialization can skip it, after which the
next evaluation occurs one configured interval later.
AkuBridge's service worker can claim pending capture commands even when the
AkuBrowser page is closed. Neither mode starts a stopped AkuSidecar or bypasses
queue, budget, or active-session limits.

Settings also reports the latest durable scheduler decision. Each due tick is
first stored as `checking`, then completed as `started` with its prepared
session identity or `skipped` with the stopper reason. The local history is
bounded to 32 receipts and the API exposes at most the newest 10, preventing
diagnostics from growing without limit. If Sidecar exits between those writes,
the unresolved `checking` state remains useful crash evidence. These receipts
contain scheduler metadata only, not captured post text or model prompts.

Settings also provides **Prepare batch now** when the user wants to
start prepared work immediately. This explicit action still checks
onboarding, Bridge readiness, prepared-batch capacity, active sessions, and
the automatic token allowance. It bypasses only the scheduler's minimum
cadence delay; resetting the quota does not
itself force a run.
Because this is an explicit user action rather than a due scheduler tick, it
does not add a scheduler receipt.

## Prepared batches and reading continuity

An automatic session with selected items becomes a prepared batch in SQLite.
Prepared items remain absent from the Timeline query, but the session and its
diagnostics are already visible in Update Inbox. The default finish-line action
is **Continue with next batch**. Revealing changes that batch from `prepared`
to `visible` without rerunning reasoning.

Settings reports queue capacity explicitly as prepared batches, configured
limit, and open slots. A prepared count of zero therefore does not mean Auto
Update is disabled; it means all configured slots are currently available for
refill when scheduling, activity, and budget admission permit it.

AkuBrowser provides two intentional reveal paths. **Load latest batch** in the
Timeline header reveals one batch, reconstructs the newest-first Timeline,
places that newly revealed batch above the material already on screen, scrolls
to the top, and reports how many items were loaded. Repeating this action places
Batch 2 above Batch 1. **Continue with next batch** at the finish line preserves
the current reading order and scroll position, appends the revealed material
after what the user just consumed, and marks its first item with a **New
prepared batch** boundary. Repeating this action places Batch 2 below Batch 1.
Both paths use an explicit placement rule instead of relying on session
completion timestamps. **Update now**
remains a separate direct action beside these controls, so a reader never has
to visit Settings or wait for the scheduler to request fresh material.
If another update is already preparing the next batch, **Update now** remains
disabled but both reveal paths remain usable for any previously prepared
batch. Reading available material is independent from producing future
material.

Completing background preparation updates only queue status and available
actions. It does not rerender the visible Timeline or move the reader.

The optional auto-load mode uses the same continuity reveal operation when the
user reaches the finish line. AkuBrowser does not scroll on the user's behalf,
does not merge batches before they are revealed, and still exposes a visible
batch boundary.

## Budget allocation, exhaustion, and reset

AkuBrowser records local model usage for acquisition planning, candidate
evaluation, semantic event resolution, and AI Deep Detection. Local AI Fast
Detection does not spend model tokens. Before an automatic check starts,
AkuSidecar estimates the next run from recent sessions and verifies that both
the daily quota and the automatic allowance can contain it.

The selectable daily quotas are 1M, 2M, 3M, and 5M tokens. The default is 2M.
The user-reserve percentage is removed from the automatic allowance, so
prepared work cannot consume the entire configured quota. **Update now** uses
that higher-authority user reserve and publishes its result directly into the
Timeline whether Auto Update is enabled or disabled.

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
is present. Presence-aware reconsiders the slot on its current active, warm, or
idle cadence, while Continuous background uses the next configured periodic
tick. Neither mode retries immediately merely because capacity opened.

## Capture lease and update policy

AkuBridge assigns the automatic session a capture lease: an ownership record
for every Bridge-created source tab or quiet-capture window. The lease is
retained across initial and follow-up acquisition so the adapter keeps the same
source frontier instead of reopening or losing its place. A durable
managed-surface ledger keeps each surface until Bridge records a cleanup
receipt, including across extension reload. When Acquisition Planning can no
longer request another capture and Candidate Evaluation begins, Auto Update
sends an explicit cleanup action for that source immediately. A short
background pump handles the normal path; the one-minute extension alarm plus
terminal source/session release remain recovery fallbacks. Reconciliation also
runs before a new lease takes ownership. Cleanup closes only still-provable
Bridge surfaces and preserves user-created or user-adopted tabs. Update Inbox
shows the resulting created/reused, release-requested, released,
user-preserved, reconciliation, and focus-intervention receipts.

Updates never overlap. A scheduler-triggered prepared update waits while a
user-visible update is active, and another update cannot start while
preparation is running. Revealing a previously prepared, terminal batch is not
an update run and remains available. The UI shows the active policy, keeps
Timeline reading, Inbox, and Settings available, and converges every path on
the same finite Timeline, provenance, personalization authority, and
inspectable run ledger.

| Entry point | Trigger | Delivery | Budget authority |
| --- | --- | --- | --- |
| First-run onboarding | `onboarding` | `visible` | `user` |
| Sidecar scheduler | `scheduler` | `prepared` | `automatic` |
| Settings **Prepare batch now** | `user` | `prepared` | `automatic` |
| Timeline **Update now** | `user` | `visible` | `user` |
