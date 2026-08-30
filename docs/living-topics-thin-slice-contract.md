# Living Topics Thin Slice Contract

> **Graduated foundation.** This contract remains the historical and technical
> foundation for automatic new-post routing and material-only understanding.
> The active local activation and candidate-review boundary is now defined by
> [Living Topics Full Stage 1](living-topics-full-stage-1-contract.md).

This document defines the implemented first bounded Living Topics vertical
slice. Its schema, API, UI, and acceptance checks ship as one contract. Product
sequencing and the deliberately deferred Full concept remain governed by the
[Personal Memory product roadmap](personal-memory-roadmap.md).

## Product boundary

A Living Topic is a user-named container for understanding one subject through
criteria-routed and explicitly selected Personal Memory evidence. It is not a bookmark folder, a
Timeline lane, or a preference signal. The user creates and renames topics,
defines a bounded description, and adds or removes existing active Library items. The Sidecar automatically
maintains a bounded current understanding after topic evidence changes. Topic actions do not create Saved or Keep ownership and do
not write More/Less or Content Context feedback.

After final Timeline composition, each surviving non-duplicate post is queued
for asynchronous topic routing. A deterministic criteria matcher handles clear
matches; a bounded semantic classifier evaluates the remainder when available.
A match creates only a recall stub and topic membership with routing provenance,
confidence, and reason. It does not create Saved or Keep ownership or act as a
More/Less signal.

Manual Add records a positive routing example. Manual Remove records a negative
example and suppresses the same item-topic pair on later routing while keeping
the recall stub available for re-adding. These examples influence the local
scorer and the bounded semantic prompt; they do not train the provider model.

The semantic sorter uses the distinct execution identity
`akusidecar.living_topic_routing` and the configured Candidate Evaluation
profile. A provider failure degrades to deterministic decisions and never
blocks Timeline publication.

The thin slice still has no automatic topic discovery or clustering, periodic
scheduled refresh, alerts, source subscription, or browser capture. Understanding refresh is event-driven by
local membership or criteria changes; an explicit `Refresh now` action is a secondary retry or re-evaluation path.
Refresh uses the Candidate Evaluation model/profile selection during this
thin slice while retaining the distinct execution identity
`akusidecar.living_topic_snapshot`.

## Storage contract (AkuSidecar schema 18)

The additive v15 to v16 migration creates the topic foundation; v16 to v17
adds active routing; v17 to v18 adds automatic understanding state and work:

- `living_topics`: `id`, bounded `name`, bounded `description`, current understanding status,
  last evaluated input digest/time, trigger/error receipts, `created_at`, and `updated_at`;
- `living_topic_memberships`: the unique topic/item pair plus `added_at`,
  `origin`, `match_mode`, `confidence`, and public `reason`;
- `living_topic_feedback_events`: append-only manual include/exclude examples;
- `living_topic_routing_jobs`: a durable per-Timeline-item async queue with
  terminal result or failure receipts;
- `living_topic_understanding_jobs`: a durable, coalescing secondary queue. A pending job is
  reused for repeated changes, while a new pending job may follow running work so evidence is not lost;
- `living_topic_snapshots`: append-only `id`, `topic_id`, `version`, `status`
  (`ready`, `insufficient_evidence`, or `no_change`), `overview`, bounded
  claims/deltas/evidence JSON, `input_digest`, provider/model/effort, bounded
  usage JSON, duration, nullable `previous_snapshot_id`, and `created_at`.

The core topic, membership, feedback, and snapshot records remain independent
from preference and knowledge-event storage. Routing jobs accept a post only
while its session is terminal and it is not a `duplicate_report`. Normal Remove and Forget permanently delete the
affected membership in the same transaction so deleted Memory cannot remain
cited by a topic. Existing append-only snapshots retain only the already
bounded public evidence ids, not copied Memory text, URLs, provenance payloads,
or provider prompts. Full Reset removes topics, memberships, routing/understanding jobs, and snapshots.

## HTTP contract

- `GET /api/living-topics` lists at most 100 topics with member count and the
  latest bounded snapshot projection.
- `POST /api/living-topics` accepts `{name, description?}` and creates one topic.
- `GET /api/living-topics/{id}` returns the topic, active public Memory
  members, and at most 20 newest snapshots.
- `PATCH /api/living-topics/{id}` accepts `{name, description}`.
- `POST /api/living-topics/{id}/members` accepts only `{memoryItemId}` and is
  idempotent for an existing active pair.
- `DELETE /api/living-topics/{id}/members/{memoryItemId}` removes only that
  membership and is idempotent.
- `POST /api/living-topics/{id}/snapshots` accepts no content and queues a
  background `Refresh now` evaluation from current active evidence. It returns the pending topic detail.

Names are trimmed, 1--120 Unicode characters, descriptions are trimmed and at
most 1,200 Unicode characters, and topics contain at most 20
active Memory members. Client text, claims, citations, timestamps, provider
selection, and prompts are never accepted at snapshot creation.

## Snapshot semantics

The Sidecar builds a bounded evidence projection from current topic members:
id, source, title, summary, author, publication time, tags/facets, and bounded
retained text when present. Source text is untrusted evidence and can never
instruct the model or host. The provider returns an overview plus at most eight
claims and eight deltas. Every claim and delta must cite one or more supplied
Memory ids; the host rejects unknown ids, empty citations, invalid assessment
or delta kinds, oversized text, and malformed output before storage.

Claims use `supported`, `mixed`, or `uncertain`. Deltas use `new`, `updated`,
`contradicted`, or `resolved`. The normalized input digest includes topic criteria and current evidence. An exact
already-evaluated digest is a provider-free no-op. Evidence changes are coalesced; if structured synthesis reports
no material delta, the Sidecar records the evaluated digest but does not publish another history version. The first
published understanding is a baseline with no artificial `new` deltas. Zero claims, insufficient evidence, and no
material change are truthful evaluation states rather than errors.

## UI contract

Living Topics is a distinct top-level local surface. It provides topic creation,
selection, criteria editing, Library evidence search/selection, current evidence removal,
and a secondary `Refresh now` action. The default Understanding tab shows one current
source-backed understanding, separates supported claims from uncertainty/conflicts, shows true material deltas only
after a baseline exists, collapses supporting evidence and generation metadata, and keeps earlier material versions
in a bounded history disclosure. Automatic evidence cards expose their
confidence, decision mode, and reason. Opening the view itself remains read-only.

## Acceptance checks

- fresh and older supported databases reach schema 18 transactionally; conflicting
  v15, v16, or v17 migrations preserve their previous version;
- topic names and the 20-member bound are enforced server-side;
- only active Memory can be attached and duplicate attachment is idempotent;
- Remove/Forget scrubs current membership without copying or exposing private
  Memory payloads in snapshot rows;
- exact already-evaluated inputs do not invoke a provider; insufficient evidence publishes no history version;
- pending changes coalesce, a change arriving during a running evaluation is preserved, and provider work never blocks Timeline publication;
- the first understanding is a delta-free baseline and a later zero-delta evaluation publishes no new version;
- structured output cannot cite an unknown Memory id or store a claim without
  evidence;
- list/detail projections expose only documented public fields and bounded
  history;
- opening Living Topics performs reads only; automatic refresh is driven only by evidence/criteria mutations or
  `Refresh now`, and one durable worker owns provider synthesis;
- no topic action changes Saved, Keep, More/Less, Timeline, Content Context, or
  Content Context feedback state.

## Implementation status

Implemented in AkuSidecar schema 18 with the top-level AkuBrowser `Living Topics`
surface. The shipped tests cover fresh/open migrations, atomic v16/v17 migrations,
criteria validation, manual feedback, explainable membership, coalesced automatic evaluation,
material-only history, provider-free exact no-change behavior, baseline delta suppression,
citation alias validation, HTTP privacy, and the bounded UI contract. Automatic topic discovery,
Bookmark Import, periodic scheduled refresh, alerts, and notifications remain deferred.
