# Living Topics Thin Slice Contract

This document defines the implemented first bounded Living Topics vertical
slice. Its schema, API, UI, and acceptance checks ship as one contract. Product
sequencing and the deliberately deferred Full concept remain governed by the
[Personal Memory product roadmap](personal-memory-roadmap.md).

## Product boundary

A Living Topic is a user-named container for understanding one subject through
explicitly selected Personal Memory evidence. It is not a bookmark folder, a
Timeline lane, or a preference signal. The user creates and renames topics,
adds or removes existing active Library items, and explicitly requests a
bounded snapshot. Topic actions do not create Saved or Keep ownership and do
not write More/Less or Content Context feedback.

The thin slice has no automatic discovery or clustering, background work,
scheduled refresh, alerts, source subscription, browser capture, automatic
Timeline insertion, or autonomous membership changes. A snapshot invocation
may call the currently selected reasoning provider only after an explicit user
action. It uses the Candidate Evaluation model/profile selection during this
thin slice while retaining the distinct execution identity
`akusidecar.living_topic_snapshot`.

## Storage contract (AkuSidecar schema 16)

The additive v15 to v16 migration creates:

- `living_topics`: `id`, bounded `name`, `created_at`, and `updated_at`;
- `living_topic_memberships`: `topic_id`, `memory_item_id`, and `added_at`,
  unique per pair;
- `living_topic_snapshots`: append-only `id`, `topic_id`, `version`, `status`
  (`ready`, `insufficient_evidence`, or `no_change`), `overview`, bounded
  claims/deltas/evidence JSON, `input_digest`, provider/model/effort, bounded
  usage JSON, duration, nullable `previous_snapshot_id`, and `created_at`.

The tables have no foreign key to sessions, runs, Timeline, preference, or
knowledge-event storage. Normal Remove and Forget permanently delete the
affected membership in the same transaction so deleted Memory cannot remain
cited by a topic. Existing append-only snapshots retain only the already
bounded public evidence ids, not copied Memory text, URLs, provenance payloads,
or provider prompts. Full Reset removes topics, memberships, and snapshots.

## HTTP contract

- `GET /api/living-topics` lists at most 100 topics with member count and the
  latest bounded snapshot projection.
- `POST /api/living-topics` accepts only `{name}` and creates one topic.
- `GET /api/living-topics/{id}` returns the topic, active public Memory
  members, and at most 20 newest snapshots.
- `PATCH /api/living-topics/{id}` accepts only `{name}`.
- `POST /api/living-topics/{id}/members` accepts only `{memoryItemId}` and is
  idempotent for an existing active pair.
- `DELETE /api/living-topics/{id}/members/{memoryItemId}` removes only that
  membership and is idempotent.
- `POST /api/living-topics/{id}/snapshots` accepts no content and creates an
  on-demand snapshot from the topic's current active evidence.

Names are trimmed, 1--120 Unicode characters, and topics contain at most 20
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
`contradicted`, or `resolved`. With no active members, the host writes a
provider-free `insufficient_evidence` snapshot. When the normalized evidence
input digest equals the previous snapshot, the host writes a provider-free
`no_change` snapshot that reuses the previous claims and cites no invented
delta. Zero claims, insufficient evidence, and no change are truthful success
states rather than errors.

## UI contract

Topics is a distinct top-level local surface. It provides topic creation,
selection, rename, Library evidence search/selection, current evidence removal,
and an explicit `Create snapshot` action. The topic view shows bounded loading,
empty, insufficient-evidence, no-change, error, claims, deltas, citations,
provider identity, and timestamp states. It never refreshes or changes
membership merely because the view opens.

## Acceptance checks

- fresh and v15 databases reach schema 16 transactionally; a conflicting
  object leaves schema version 15 unchanged;
- topic names and the 20-member bound are enforced server-side;
- only active Memory can be attached and duplicate attachment is idempotent;
- Remove/Forget scrubs current membership without copying or exposing private
  Memory payloads in snapshot rows;
- empty and unchanged snapshots do not invoke a provider;
- structured output cannot cite an unknown Memory id or store a claim without
  evidence;
- list/detail projections expose only documented public fields and bounded
  history;
- opening Topics performs reads only; snapshot generation is explicit and
  only one active Sidecar operation owns it;
- no topic action changes Saved, Keep, More/Less, Timeline, Content Context, or
  Content Context feedback state.

## Implementation status

Implemented in AkuSidecar schema 16 with the top-level AkuBrowser `Topics`
surface. The shipped tests cover fresh/open migrations, atomic v15 migration
failure, manual membership, lifecycle scrubbing, append-only snapshots,
provider-free empty/no-change behavior, citation alias validation, HTTP
privacy, and the bounded UI contract. Automatic discovery, Bookmark Import,
monitoring, scheduled refresh, alerts, and notifications remain deferred.
