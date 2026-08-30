# Living Topics Full Stage 1 Contract

This document defines the first graduated Living Topics stage after the
[Thin Slice](living-topics-thin-slice-contract.md). It activates a user-created
topic against already-local Personal Memory while keeping topic membership,
retention, and preference authority explicit.

## Product boundary

A topic has a name, purpose, aliases, explicit include criteria, and explicit
exclude criteria. These fields form one revisioned routing contract. New final,
non-duplicate Timeline posts continue to route asynchronously: a sufficiently
confident match may create a topic-owned recall stub and automatic membership,
with mode, confidence, and reason retained for inspection.

Creating a topic or changing its criteria also queues a bounded retroactive scan
over at most 100 recent active local Memory items. Only the 12 strongest local
candidates may reach semantic classification. A scan never changes membership:
matches appear as **Suggested evidence** until the user chooses **Accept**.
**Reject** records a negative routing example, and **Undo** returns the row to
its suggested state. These decisions are local signals for this topic, not
provider training and not More/Less feedback.

Accepted evidence triggers the existing coalesced understanding worker.
Understanding remains an evidence-backed, material-only history: an unchanged
input is provider-free, a semantic no-change publishes no noisy version, and
insufficient evidence is shown truthfully as **Needs evidence**.

This stage has no external discovery, browser capture, automatic topic creation,
clustering, schedule, system notification, or Timeline promotion. Its bounded
notification is an in-app unread projection over newly auto-routed evidence. Bookmark Import is
not required for bounded activation over current local Memory; it remains the
provenance and lifecycle prerequisite before later Full stages can safely widen
the evidence pool.

## Storage contract (AkuSidecar schema 20)

The additive v18 to v19 migration:

- adds `criteria_revision`, `aliases_json`, `include_criteria`,
  `exclude_criteria`, and routing status/check/error receipts to `living_topics`;
- creates `living_topic_activation_jobs`, unique per topic and criteria
  revision, with durable pending/running/completed/failed state and bounded
  result/error receipts;
- creates `living_topic_candidate_evaluations`, unique per topic, Memory item,
  and criteria revision, with `suggested`, `accepted`, `rejected`, or
  `not_matched` status plus engine version, mode, confidence, reason, and review
  timestamps;
- extends append-only topic feedback with `clear` so Undo is auditable without
  rewriting an earlier include/exclude event;
- queues one activation job for every migrated topic without changing existing
  membership, Saved, Keep, or preference state.

Only active Memory not already attached to the topic is scanned. Candidate rows
hold references and bounded routing receipts, not copied full content or provider
prompts. Remove, Forget permanently, and Full Reset preserve the existing Memory
scrubbing rules; Full Reset also removes activation jobs and candidate rows.

The additive v19 to v20 migration adds `evidence_seen_at` to each topic and
`new_evidence` plus `new_evidence_at` to each membership. Existing memberships
migrate as already seen. Only a newly inserted **automatic** membership receives
an unread marker; manual Add, candidate Accept, duplicate routing, and criteria
changes do not. Unread totals are derived from active memberships rather than a
denormalized topic counter, so concurrent evidence cannot be lost and removing
or forgetting evidence also removes its unread contribution.

## HTTP contract

- `POST /api/living-topics` and `PATCH /api/living-topics/{id}` accept
  `{name, description?, aliases?, includeCriteria?, excludeCriteria?}`.
- `GET /api/living-topics` includes criteria revision, routing status, suggested
  count, and the existing understanding projection.
- `GET /api/living-topics/{id}` includes public current-revision candidate rows;
  retained full text and internal provenance remain hidden.
- `POST /api/living-topics/{id}/activation` accepts an empty body and queues a
  bounded local rescan.
- `POST /api/living-topics/{id}/candidates/{memoryItemId}/accept`, `/reject`,
  and `/undo` accept empty bodies and return updated public topic detail.
- `GET /api/living-topics/notifications` returns the total unread evidence,
  number of affected topics, and latest unread evidence timestamp.
- `POST /api/living-topics/{id}/seen` accepts `{seenThrough}` and acknowledges
  only unread memberships at or before that RFC3339 timestamp. Evidence routed
  after the visible projection remains unread.

Names remain 1--120 Unicode characters. Purpose/include/exclude values are each
at most 1,200 Unicode characters. A topic accepts at most 12 case-insensitive
unique aliases of 1--80 Unicode characters and at most 20 active members.

## Routing and review semantics

The deterministic shortlist scores topic name, aliases, purpose, and include
criteria against title, summary, tags, and facets, while exclude criteria and
negative examples reduce confidence. Clear high-confidence matches remain local;
the configured Living Topics semantic router may classify ambiguous shortlisted
items. Provider failure degrades safely to the local result and cannot block the
Timeline or add membership.

Accept creates or updates a manual membership with `candidate_accept`
provenance and appends an include example. Reject removes only membership owned
by a prior candidate Accept and appends an exclude example. Undo removes only
that candidate-owned membership, returns the current-revision candidate to
`suggested`, and appends `clear`. It never removes independently manual or
automatically routed ownership.

Changing any routing criterion increments the revision. New candidates and
counts are scoped to that revision; previous review receipts remain auditable
but do not appear as current suggestions.

## UI contract

The top-level menu is **Living Topics**. The default Understanding tab remains
the primary surface. Manage evidence exposes the revisioned purpose, aliases,
include, and exclude fields, then a **Suggested evidence** section with routing
status, **Accept**, **Reject**, inline **Undo**, and a secondary **Scan again**
control. Suggestions never masquerade as evidence before acceptance, and an item
already attached manually is not duplicated in the suggestion list.

The Living Topics menu shows the total unread auto-routed evidence count. Each
affected topic shows **New** or **New N**. Entering the Living Topics surface and
its default topic is read-only and does not clear either badge. Explicitly
selecting a topic acknowledges the currently visible unread generation; this
keeps the signal discoverable while preventing a newer concurrent route from
being acknowledged accidentally.

## Acceptance checks

- fresh and supported older databases reach schema 20 transactionally; a
  conflicting v18 or v19 migration preserves its prior version and rows;
- migrated topics queue activation without changing membership;
- a bounded scan examines at most 100 active local items and semantically
  classifies at most 12 shortlisted items;
- scan results alone never create topic membership, Saved, Keep, More/Less,
  Timeline, or Content Context state;
- Accept, Reject, and Undo are revision-scoped, auditable, and preserve
  independently owned membership;
- criteria changes increment the revision and queue both activation and
  understanding work;
- candidate/detail projections expose only bounded public Memory fields;
- activation and understanding resume safely after restart and never block
  Timeline publication;
- zero suggestions, insufficient evidence, no change, and provider failure are
  represented truthfully.
- automatic new membership increments the in-app unread projection exactly
  once; duplicate/manual/candidate membership does not; acknowledgment is
  bounded by the visible evidence timestamp.

## Implementation status

Implemented in AkuSidecar schema 20 and the AkuBrowser Living Topics surface.
External discovery, automatic topic clustering, Bookmark Import, scheduled
refresh, alerts, and operating-system notifications remain deferred to separately approved
stages.
