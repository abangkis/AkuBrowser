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
Understanding uses three separate concerns: a replaceable **Current
Projection**, append-only **Material History**, and an append-only **Evaluation
Audit**. An unchanged input is provider-free unless the user explicitly asks
for refresh. A valid semantic no-change replaces Current Projection without
adding Material History, while the job and model receipts still record the
evaluation. Insufficient evidence is shown truthfully as **Needs evidence**.

This stage has no external discovery, browser capture, automatic topic creation,
clustering, schedule, system notification, or Timeline promotion. Its bounded
notification is an in-app unread projection over newly auto-routed evidence. Bookmark Import is
not required for bounded activation over current local Memory; it remains the
provenance and lifecycle prerequisite before later Full stages can safely widen
the evidence pool.

## Storage contract (AkuSidecar schema 23)

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

The additive v20 to v21 migration adds nullable `move_id` ownership to topic
membership and a durable `living_topic_membership_moves` receipt. A
receipt preserves the exact source origin, match mode, confidence, reason,
added time, unread marker, and earlier move lineage. Moving evidence does not
copy, delete, upgrade, or recreate its Personal Memory recall stub. It appends
an exclude example for the source topic and an include example for the target;
Undo appends clear events and restores the exact source membership. Undo may
remove a target membership only while that membership is still owned by the
move. A later explicit Add clears move ownership, so Undo cannot remove an
independently claimed target.

Published understanding is divided into **current supported knowledge** and
**historical understanding**. A snapshot is current only when it is the newest
published version, its input digest equals the topic's last completed
understanding digest, and at least one cited evidence item remains active in
the topic. Every snapshot exposes active evidence count and `available`,
`partial`, or `unavailable` evidence availability. Moving, removing, or
forgetting evidence immediately demotes an older version to history while the
coalesced worker prepares a new current understanding. Historical derived
statements remain for audit, but are not eligible for Related Context or a
future default answer path.

The additive v22 to v23 migration introduces the Current Projection V2
contract. Existing snapshots remain immutable and are marked `legacy-v1`.
Every existing topic is queued for a lazy `migration_rebaseline`; legacy prose
is never supplied as synthesis input. Each valid V2 evaluation stores its
contract version, topic-relative evidence roles, coverage state, and whether
the result is a material semantic change. The newest valid V2 row is Current
Projection. Only rows marked as material changes join historical understanding;
understanding jobs and model invocations form Evaluation Audit.

The V2 input digest is order-independent and includes the topic criteria
revision, active evidence content and availability, and understanding contract
version. Evidence is classified as `core`, `supporting`, `peripheral`, or
`undetermined`, with an observed subtopic and source/event cluster. Routing
confidence, evidence role, claim centrality, epistemic status, and availability
are independent dimensions. The host builds the overview only from central,
supported claims; peripheral observations may remain visible but cannot lead
the topic conclusion.

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
- `POST /api/living-topics/{fromTopicId}/members/{memoryItemId}/move` accepts
  `{toTopicId}` and returns a reversible move receipt.
- `POST /api/living-topic-moves/{moveId}/undo` accepts an empty body and may
  undo only the latest active move for that Memory item.

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

Living Topic cost remains conditional. Clear deterministic routing consumes no
provider tokens, semantic routing records one asynchronous usage receipt for an
ambiguous item, and understanding records a receipt only for a changed evidence
digest that reaches synthesis. Unchanged digests remain provider-free and
evidence changes are coalesced. **Refresh now** bypasses the unchanged-input
fast path but still requires validation and creates Material History only when
the normalized claim set changes. The dated observed averages and their
limitations are maintained in the
[LLM Invocation and Token Cost Reference](llm-invocation-and-token-cost.md).

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

Each attached evidence row also offers a destination selector and **Move**.
After success the source view shows a bounded confirmation with **Undo** while
both source and destination understandings refresh. Moving does not create a
`New` badge in the destination because it is an explicit correction rather
than newly discovered evidence.

The Understanding tab renders a current card only when `isCurrent` is true.
It separates central understanding from supporting/peripheral observations and
shows bounded coverage plus independent evidence origins rather than implying
global topic completeness.
During refresh, insufficient evidence, or evidence loss it shows the truthful
current-state message and moves every older version under historical audit,
including its current evidence availability.

Top-level Library Search may surface at most three matching **Current Living
Topic knowledge** cards above individual Memory results. An explicit query is
matched locally against topic name, description, aliases, current overview,
and supported claims. These cards omit evidence ids and uncertain/mixed claims;
historical, partial, and unavailable understanding is ineligible. Source,
tier, and date filters apply only to the individual Memory results because a
topic understanding may span several sources. The lookup never invokes a
provider or changes topic state.

Timeline Related Context may render a **Current Living Topic understanding**
section before individual Memory matches. It uses the same bounded local
relevance engine and includes at most two current topic insights with overview,
up to three supported claims, active evidence count, version, and deterministic
match reason. A multi-token topic also requires at least two matching identity
tokens from its name, unless an explicit single-token alias matches; this
prevents a narrow sibling such as `Codex Reset` from matching an unrelated
general `Codex` post on one word alone. Mixed/uncertain claims and historical,
partial, or unavailable
snapshots are excluded. The lookup remains lazy, read-only, provider-free, and
does not mutate topic membership or feedback.

## Acceptance checks

- fresh and supported older databases reach schema 23 transactionally; a
  conflicting v18, v19, v20, or v21 migration preserves its prior version and rows;
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
- Move and Undo preserve source provenance and unread state, learn a
  contrastive topic correction, never mutate the recall stub, and cannot delete
  independently owned destination membership.
- a snapshot loses current authority as soon as its active evidence support or
  completed digest no longer matches; only current supported claims can enter
  Related Context.
- previous prose never enters fresh V2 synthesis; a valid no-material-change
  rebuild replaces Current Projection, leaves Material History untouched, and
  remains visible in Evaluation Audit.
- legacy or contract-stale projections, peripheral/mixed/uncertain/unavailable
  claims, and projections whose digest no longer matches active evidence are
  excluded from Library Search and Related Context.
- explicit Library queries can return bounded current supported topic knowledge
  separately from filtered Memory items without exposing evidence ids or
  mutating Library or Living Topic state.

## Implementation status

Implemented in AkuSidecar schema 23 and the AkuBrowser Living Topics, Library
Search, and Related Context surfaces.
Schema 22 introduced content-free provider receipts for semantic topic
routing and understanding. Retained published snapshot receipts are backfilled;
historical calls with no durable receipt remain unknown.
Schema 23 adds Current Projection V2, material-history classification,
topic-relative evidence roles, coverage state, and lazy legacy rebaselining.
External discovery, automatic topic clustering, Bookmark Import, scheduled
refresh, alerts, and operating-system notifications remain deferred to separately approved
stages.
