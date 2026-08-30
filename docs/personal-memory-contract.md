# Personal Memory and Library Contract

This document is the canonical contract for the Personal Memory and Library foundation.
It defines durable local memory independently from the operational Timeline,
Inbox, preference learning, and semantic event resolver. The local Library
surface includes deterministic FTS5 search, GET-only reads, and explicit
local lifecycle actions: Read later, Keep in Library, Done, Release full copy,
Remove, and Forget permanently. Ingestion from `ComposeSession` remains a
later milestone. Read later is a bounded local retention action over persisted
Timeline evidence; it creates current Saved membership, while Keep in Library
is the separate permanent full-copy decision made after reading.

## Product boundary

| Layer | Contract | Lifetime |
| --- | --- | --- |
| Timeline | Selected results prepared for the current update | Operational; subject to retention |
| Preference ledger | Compact evidence for More/Less taste learning | Durable, but not content archive |
| Knowledge/events | Reasoning structures used by the update pipeline | Operational/semantic retention |
| Personal Memory | User-owned recall stubs and explicitly retained text | Independent of sessions/runs/Timeline |

`More` and `Less` remain preference signals. A routine `More` action may
guarantee a recall stub, but it does not imply Saved membership or a full copy.
`Read later` copies the best bounded text available in authoritative persisted
Timeline evidence (or stores a truthful source-dependent recall item when text
is unavailable) and creates current Saved membership. After reading, `Keep in
Library` creates permanent full-copy ownership without duplicating content and
resolves Saved membership. `Done` resolves Saved membership; without an
independent Keep claim it releases the temporary full copy and leaves a recall
stub. Neutral Timeline results and calibration corrections do not become
durable memory automatically.

The guarantee is narrow: only an explicit routine `More` submitted for a
Timeline item that still exists after composition and belongs to a terminal
`completed` or `partial` session may project a recall stub. `Less`/
`Not interested` for the same final survivor retracts a recall stub that is
proven to exist only because of that routine `More`; it does not create a
tombstone, so a later `More` can recreate the stub. Full copies, independent
captured/imported/manual provenance, current Saved membership, and permanent
Keep ownership remain untouched. Less consults these current ownership claims
rather than historical `read_later`/`mark_read` rows; after Done without Keep,
the item may again behave as a normal recall stub. Neutral choices, calibration,
selection corrections, AI feedback, and non-surviving candidates are
memory-neutral.

## State model

Each `memory_items` row has a recall/full-copy tier plus independent current
Saved and Keep claims:

```text
active + recall       -- metadata, source pointer, bounded labels
active + full_copy    -- recall data plus one or more text versions
active + saved        -- current Saved membership claim (may also have text)
active + keep         -- independent permanent Keep ownership claim
tombstone             -- opaque deletion marker; no URL, text, author, or provenance
absent                -- local removal; no memory or suppression marker remains
```

Saved and Keep are materialized current claims, not inferred from action
history. A full-copy item present during migration is treated as permanently
Kept; historical `read_later` or `mark_read` actions never create Saved
membership.

Normal Remove physically deletes the active item, search row, content versions,
provenance, actions, and aliases without writing a tombstone. A later routine
`More` may therefore recreate the same source identity. Forget permanently
uses the opaque Forget permanently transition: it removes raw aliases, provenance, and
content versions, then clears all identifying fields. It preserves only the
opaque item id, lifecycle state, timestamps, and keyed digests in
`memory_tombstone_aliases`.
The per-install HMAC key is held in local metadata and is never exposed as an
alias value; a plain SHA-256 of a known URL is not treated as non-reversible.
Every matching future create is rejected as tombstoned, even when it carries
only one prior evidence key, permalink, platform id, or fingerprint, so an
accidental recapture cannot resurrect the deleted memory. Full Reset removes
tombstones and the local HMAC key as well as active memory and is preceded by
the existing verified backup.

## Identity and deduplication

The store normalizes one source-owned identity and writes aliases in this
order of authority:

1. `(source, canonical_evidence_key)`;
2. `(source, canonical_permalink)`;
3. `(source, canonical_platform_id)`;
4. `(source, content_fingerprint)` only when no stronger identity is present.

The final fingerprint is a hint, not a primary key: ambiguous fingerprint
matches never merge two active memories. Equivalent aliases update one item and
append provenance/action evidence instead of creating a duplicate.

## Storage contract (AkuSidecar schema 15)

The additive v11 to v12 migration creates the memory tables and the additive
v12 to v13 migration creates/backfills the local search index. The additive v13
to v14 migration creates current retention claims and materializes a permanent
`keep` claim for every active legacy `full_copy` item. It does not infer Saved
membership from historical actions. The additive v14 to v15 migration creates
the append-only Content Context feedback ledger. All migrations
are transactional and update `meta.schema_version` only after all objects and
backfill rows succeed. The v13 FTS index and v14 claim indexes are
provider-free and have no foreign key to operational data.
The local `memory_tombstone_key_v1` metadata value is generated randomly and
used only for keyed deletion suppression digests:

### `memory_items`

`id`, `source`, `identity_digest`, `canonical_evidence_key`,
`canonical_permalink`, `canonical_platform_id`, `content_fingerprint`,
`title`, `summary`, `author`, `published_at`, `tags_json`, `facets_json`,
`media_metadata_json`, `retention_tier`, `lifecycle_state`,
`full_content_version_id`, `content_bytes`, `reason`, `created_at`, `updated_at`.

Indexes: `memory_items_identity_digest`,
`memory_items_lifecycle_updated`, and `memory_items_source_updated`.

### `memory_identity_aliases`

`source`, `alias_kind`, `alias_value`, `memory_item_id`, `created_at`,
`last_seen_at`. Strong aliases (`canonical_evidence_key`,
`canonical_permalink`, and `canonical_platform_id`) are unique per source;
content-fingerprint aliases may be shared by separate items.

Indexes: `memory_identity_aliases_lookup`,
`memory_identity_aliases_strong_unique`, and `memory_identity_aliases_item`.

### `memory_tombstone_aliases`

`memory_item_id`, `alias_kind`, `alias_digest`, and `created_at`. This table
contains keyed HMAC digests only; it deliberately has no source, URL, evidence
key, platform id, or content value. A digest is stored for every normalized
identity alias at deletion time.

Indexes: `memory_tombstone_aliases_lookup` and
`memory_tombstone_aliases_item`.

### `memory_content_versions`

`id`, `memory_item_id`, `version`, `content`, `content_fingerprint`,
`media_metadata_json`, `content_bytes`, `captured_at`, `created_at`,
`released_at`. There is no foreign key to an operational table or to a
session/run/Timeline row.

Indexes: `memory_content_versions_item_created` and
`memory_content_versions_active`.

### `memory_provenance`

`id`, `memory_item_id`, `provenance_kind`, `source`,
`canonical_evidence_key`, `source_url`, `capture_context_json`, `reason`,
`created_at`. Provenance is append-only while an item is active and is removed
by the Forget permanently privacy transition.

Index: `memory_provenance_item_created`.

### `memory_actions`

`id`, `memory_item_id`, `action`, `detail_json`, `created_at`. Supported
actions are `create_stub`, `update_stub`, `keep_full_copy`,
`release_full_copy`, `read_later`, `mark_read`, `import`, and `delete`.

Indexes: `memory_actions_item_created` and `memory_actions_action_created`.

### `memory_retention_claims`

`memory_item_id`, `claim_kind` (`saved` or `keep`), `claimed_at`, and nullable
`resolved_at`. The primary key is `(memory_item_id, claim_kind)`, so each item
has at most one current claim of each kind. Active membership/ownership is
represented by a null `resolved_at`; resolving a claim is idempotent and keeps
the audit-safe timestamps without relying on action rows.

Indexes: `memory_retention_claims_active` and `memory_retention_claims_item`.

### `content_context_feedback_events`

`id`, `timeline_id`, internal stable `context_key`, `memory_item_id`, `verdict`
(`relevant`, `not_relevant`, or `clear`), `engine_version`, server-derived
`result_rank`, server-derived `match_reason`, nullable `supersedes_id`, and
`created_at`. Events are append-only pairwise evidence about the relationship
between one Timeline context and one Memory item; they never classify the
Memory item globally. The table deliberately has no foreign key to operational
Timeline or Personal Memory rows, and its internal context key never crosses
the public API.

Indexes: `content_context_feedback_pair_created` and
`content_context_feedback_timeline_created`.

No Personal Memory table has a foreign key to `sessions`, `runs`, or
`timeline_items`; operational deletion and `EnforceRetention` therefore cannot
delete a durable memory as a side effect.

### `memory_search_fts`

This FTS5 virtual table contains one logical row for every active memory item:
`memory_item_id` (unindexed), `title`, `summary`, `author`, `tags`, `facets`,
and `full_content`. It is rebuilt transactionally on recall create/update,
Read later, Keep in Library, Done, Release, Remove, and Forget permanently.
Tombstones are never indexed;
Release clears the full-copy field and both removal actions remove the row.
Existing active v12 items are backfilled during migration.

Search uses deterministic FTS5 BM25 with weights in column order
`title=10`, `summary=5`, `author=2`, `tags=3`, `facets=3`, and
`full_content=1` (lower scores rank first), then stable tie-breakers
`updated_at DESC, id DESC`. Empty queries use the same stable recent ordering
without touching FTS. The opaque keyset cursor is bound to the query and
filters; a cursor cannot be reused for another query.

The HTTP contract is:

- `GET /api/library/items?query=&source=&tier=&publishedFrom=&publishedTo=&limit=&cursor=` lists or searches active items;
- `GET /api/library/saved?query=&source=&tier=&publishedFrom=&publishedTo=&limit=&cursor=` lists only items with a current Saved claim. The equivalent `saved=true` filter on the general Library endpoint is also supported.
- `GET /api/library/items/{id}` returns one active item, including explicitly
  retained full text when present.
- `GET /api/library/storage?limit=` returns a logical local-storage estimate
  plus bounded review-only recommendations. The default recommendation limit
  is 6 and the accepted range is 1--12. Usage includes active items,
  tombstones, recall/full-copy counts, and content, metadata, provenance, and
  action byte estimates; it is not the physical SQLite or WAL file size.
  Recommendations include only `id`, `source`, public `title`/`author` when
  present, `contentBytes`, `reclaimableBytes`, `updatedAt`, `reasonCode`, and
  `reviewAction`. They select active `full_copy` items with positive content
  bytes and rank them by reclaimable content bytes descending, then
  `updatedAt` descending and `id` descending. The current reason code is
  `largest_full_copy` and the existing review action is `review_full_copy`.
  Tombstones count in usage but are never recommended. An empty set returns a
  successful response with `recommendations: []`.
- Current Saved items are excluded from the general full-copy recommendations,
  so temporary Saved text is not presented as ordinary releasable Keep storage.
  The same storage response adds the read-only `savedPressure` fact snapshot
  and bounded `savedRecommendations` array. `savedPressure` contains only
  `activeItems`, `localCopyItems`, `sourceDependentItems`, `contentBytes`, and
  `oldestClaimedAt`; `localCopyItems` counts Saved items with a positive local
  full-text byte count, while `sourceDependentItems` contains every other
  active Saved item, including recall stubs and zero-byte media-metadata-only
  `full_copy` rows. The two counts sum to `activeItems`. The oldest timestamp
  is an empty string when no active Saved claim exists. It is a current-schema
  count/byte snapshot, not a pressure score, warning threshold, hard limit, or
  capacity decision.
  `savedRecommendations` reuses the storage recommendation limit (default 6,
  accepted range 1--12), selects only active unresolved Saved claims, and
  orders them strictly FIFO by current `savedAt`/claim time ascending, then
  `id` ascending. Each entry contains only `id`, `source`, public `title` and
  `author` when present, `savedAt`, `retentionTier`, `contentBytes`,
  `sourceDependent`, `reasonCode`, and navigation-only `reviewAction`.
  `sourceDependent` is false only for a `full_copy` item with positive local
  text bytes; it is true for recall and zero-byte full-copy items. It never
  includes content, provenance, audit details, claim internals, or
  provider data. Empty responses always return non-null arrays.
- The storage surface is strictly non-mutating: `GET /api/library/storage`
  never deletes, releases, downgrades, tombstones, rewrites, or changes
  retention state; it accepts no memory content, calls no provider, and never
  auto-cleans. Its recommendations only open the existing Library detail for
  user review. Any lifecycle mutation remains an explicit detail action with
  its own endpoint and confirmation.
- `POST /api/timeline/{timelineId}/read-later` stores the best bounded local
  text available from final persisted Timeline evidence and creates current
  Saved membership. It accepts no body or client content and returns
  `{saved:true,alreadySaved,retentionTier,permanentKeep}`; the internal
  Personal Memory id is not exposed at the Timeline boundary. Missing or
  unavailable text remains a truthful source-dependent Saved recall item. The
  Sidecar rejects missing/non-final items and tombstoned identities without a
  provider call, browser recapture, or media download. Repeating the request
  while Saved is active is idempotent. The legacy
  `POST /api/timeline/{timelineId}/keep-full-copy` compatibility endpoint may
  remain for existing clients, but it is not a visible Timeline action.
- `POST /api/library/items/{id}/keep-in-library` converts the current Saved
  item to permanent Keep ownership, reuses the existing active full-copy
  version, resolves Saved membership, and returns
  `{kept:true,id,saved:false,permanentKeep:true,retentionTier}`. It returns a
  bounded unavailable-text error when a full copy cannot be established.
- `POST /api/library/items/{id}/done` resolves Saved membership and returns
  `{done:true,id,saved:false,permanentKeep,retentionTier}`. Without a Keep
  claim, temporary Read Later text is released and the item becomes a recall
  stub; an existing Keep claim leaves its full copy intact. Both mutations are
  idempotent and accept no body or client content.
- `POST /api/library/items/{id}/release-full-copy` releases the retained text
  and preserves the searchable recall metadata and identity. It accepts no
  body or client content and returns only
  `{released:true,id,retentionTier:"recall"}`. The operation is safe to repeat
  for an already-recall item; tombstoned or missing items return 404.
- `DELETE /api/library/items/{id}` performs the normal local Remove. It
  accepts no memory content and returns only `{removed:true,id}`. The
  Sidecar physically removes the active item and its local rows without a
  tombstone, so matching future automatic `More` projections may recreate it.
- `POST /api/library/items/{id}/forget-permanently` performs the explicit
  permanent Forget action. It accepts no memory content and returns only
  `{forgotten:true,id}`. The Sidecar writes opaque keyed tombstone
  aliases, removes the item from search, and makes matching future automatic
  `More` projections fail closed.

`limit` is 1--50 (default 24), query text is capped at 200 Unicode characters,
and cursors are capped at 512 characters. `publishedFrom` and `publishedTo`
accept RFC3339 timestamps or `YYYY-MM-DD`; a date-only `publishedTo` includes
the entire UTC day. The response exposes bounded recall
metadata and optional user-kept full text, but never tombstones, HMAC digests,
audit/provenance internals, credentials, or provider payloads. The delete
responses do not return the removed item.

## Content Context v2

Content Context is an explicit, read-only lookup from one currently visible
Timeline item into local Personal Memory. The contract is
`GET /api/timeline/{timelineId}/content-context?limit=` with a default limit of
3 and an accepted range of 1--5. The Sidecar accepts only a final item from a
completed or partial session whose Timeline batch is visible; missing,
running, expired, or prepared items cannot request context.

The Sidecar derives bounded query features locally from the persisted Timeline
`WhatChanged` (title-like text), source evidence text, `WhyItMatters` (summary),
and topic tags/facets. FTS5 is only the bounded candidate generator and may
over-fetch a small local pool. A deterministic relevance engine then extracts
structured topic anchors, admits substantively related candidates, ranks them,
and produces the public match reason. Generic one-token overlap, common prose,
and generic phrases cannot admit a candidate by themselves; BM25 candidate
order may break ties but is not the relevance decision. Returning zero matches
is valid and preferable to filling the drawer with weak context.

The complete path remains local and makes no provider, browser, media, or
Bridge call. Exact source/evidence-key, permalink, and platform-id matches are
excluded when deterministically available, so the current item does not
recommend itself. Candidate generation, admission, ranking, and reasons are
bounded and deterministic for the same stored state.

The response contains at most five existing public Library projections and a
deterministic `matchReason` naming only matching public fields such as title,
summary, author, tags, facets, or retained text. It never returns full content,
provenance, audit rows, identity digests, or provider payloads. An empty result
is successful. The operation opens no Saved/Keep state and performs no memory,
Timeline, preference, action, or provenance write.

Each returned match may expose its current pairwise feedback state. Explicit
feedback uses
`POST /api/timeline/{timelineId}/content-context-feedback` with only
`memoryItemId` and a `relevant` or `not_relevant` verdict. The Sidecar accepts
feedback only when the current engine can reproduce that surfaced match; it
derives the stable context identity, result rank, match reason, and engine
version server-side. Undo is
`POST /api/content-context-feedback/{feedbackId}/undo` and appends a `clear`
event only when the referenced event remains the latest decision for the pair.

On later retrieval, `not_relevant` suppresses only that exact pair. `relevant`
adds a strong deterministic boost to an otherwise admitted pair but never
admits a candidate rejected by the current relevance policy. Feedback is
independent of More/Less, Saved, Keep, Timeline selection, and global Memory
quality. Reset
Learning removes this learning ledger; ordinary retrieval remains read-only.

The Timeline UI exposes one compact, accessible `Related context` right-edge
tab on every eligible rendered post and performs a lookup only after that
post's action. A collapsed duplicate report has no tab until `Show report`
reveals its post, and `Hide report` removes the tab again. The tab is shown only
when the actual horizontal gap between the post and the Back to top control (or
viewport edge) can fit it safely; the Back to top control yields or repositions
instead of hiding the tab for the next readable post.

Only one item-scoped drawer can be open globally. Activating another post
atomically closes the previous drawer and anchors the same right-side surface
to the newly selected post. The rail is positioned relative to its post and
does not float or follow the viewport like AI Signals. Downward scrolling
closes and clears the drawer when its active post's bottom crosses the 20%
viewport line. Upward behavior is controlled by
`contentContextUpScrollMode`: the default `close_offscreen` closes and clears
the drawer when the active post exits below the viewport, while `preserve`
retains its item state so the drawer can return with that anchored post; it
still never becomes a floating drawer.

On narrow viewports the tab may hide when there is no safe room, while the
drawer remains an accessible overlay/bottom sheet with Close, Escape, focus
return, internal scrolling, and reduced-motion handling. It renders bounded
loading, empty, error, and result states with the returned reasons; it does not
prefetch context for every post.
Selecting either feedback action does not remove or reorder the current drawer.
A `not_relevant` row becomes visually subdued and both verdicts show an inline
Undo action. The current result set remains stable until the drawer closes or
switches to another post; its cached result is then discarded so the next
lookup applies the latest pairwise verdict.
Content Context does not add More/Less, Read later, Keep, or import behavior,
and its presentation does not reuse the AI Signals side-pane follow-scroll
behavior.

The top-level Library view in the AkuBrowser web app is a local search client
with distinct `Saved`, `Library`, and lazy-loaded read-only `Spring Cleaning`
tabs. Saved lists only current Read Later membership; Library lists all active
recall/full-copy items. Both use explicit local search, source/tier/date filters,
stable cursor-based Load more pagination, and a detail pane. The detail pane may
show only the returned full text and safe HTTPS source/media metadata
references; it does not infer a reason such as “remembered because More” when
that reason is not present in the public API.

Saved detail offers exactly `Keep in Library` and `Done` for the Saved lifecycle.
Keep uses a clear confirmation and preserves one existing full-copy version;
Done uses a clear confirmation and releases only temporary Read Later text.
Existing Release full copy, Remove, and Forget permanently actions remain
available where applicable as independent Library actions. Timeline exposes one
retention action, `Read later`, which changes to `Saved` after success; it never
shows a separate full-copy Keep control. All actions are keyboard/mobile/
accessibility compatible and do not accept client-supplied memory content.

## Media and privacy limits

The foundation stores UTF-8 text and at most 16 bounded HTTPS media metadata
references per item/version. A reference may contain kind, URL, title, and alt
text. Binary media, downloaded files, cookies, raw prompts, provider payloads,
and credentials are not stored. Full-copy text is capped at 4 MiB per action;
context and audit details are separately bounded.

Logical storage usage reports content, metadata, provenance, and action bytes;
it is not a claim about SQLite file or WAL size. An explicit full copy must not
be silently removed by pressure. The Library Spring Cleaning section is a
read-only view of the bounded full-copy recommendations from
`GET /api/library/storage`; it states that nothing is removed automatically
and offers only `Review` navigation to existing Library detail. Its lazy-loaded
`Saved backlog` subsection reports the current Saved fact snapshot and FIFO
review cards; `Review` switches to the Saved tab and opens that item. Search,
filters, and item content remain in the Saved/Library surfaces, and Library's
storage snapshot and full-copy section remain intact. No automatic cleanup,
retention mutation, provider call, schema migration, or physical database-size
claim is part of this surface.

## Transaction and migration rules

Memory creation/update, aliases, optional provenance, and the corresponding
action are committed atomically. Read later, Keep in Library, Done, Release,
Remove, and Forget permanently are also atomic. Retention claims are updated in
the same transaction as their lifecycle mutation and are never reconstructed
from historical action rows.
For an eligible routine `More`, the canonical `feedback_events` row and its
recall-stub projection, provenance, and action share one SQLite transaction;
if projection fails, the preference row is rolled back and retry is safe.
Schema migration is forward-only and additive: it runs in a transaction,
creates the v12 tables/indexes, creates and backfills the v13 search index,
creates the v14 retention claims and legacy full-copy Keep claims, creates the
v15 Content Context feedback ledger, updates `meta.schema_version` only after
all objects succeed, and leaves v11
operational rows untouched. There is no `ComposeSession` ingestion in this
foundation; the projection is an explicit feedback boundary over the final
surviving Timeline item.

## Required acceptance checks

- fresh databases and v11 databases open at schema 15 with the exact objects above;
- v12 databases backfill active memory into FTS5 and leave failed migration/version state unchanged;
- v13 databases migrate to v14 with active legacy full copies materialized as permanent Keep claims, without inferring Saved from historical actions;
- v14 databases create the Content Context feedback ledger transactionally and
  preserve schema 14 when a conflicting object makes migration fail;
- local lexical ranking, source/tier/date filters, stable keyset cursors, empty-query recency, and restart persistence work without a provider;
- release, routine-Less retraction, Remove, and Forget permanently scrub their
  FTS rows as well as
  their stored payloads;
- Library HTTP reads validate bounds, hide internal fields, return 404 for
  tombstones, and expose distinct narrow Remove and Forget permanently
  mutations;
- Content Context uses FTS5 only for bounded candidate generation, rejects
  generic single-term or generic-phrase matches, permits a successful empty
  result, and returns deterministic ordering and substantive public reasons
  for the same stored state without provider or write activity;
- every eligible rendered post owns a Related context tab, collapsed duplicate
  reports own none, only one drawer can be active globally, downward crossing
  of the 20% viewport line closes it, and `contentContextUpScrollMode` validates
  and persists the default `close_offscreen` and optional `preserve` behaviors;
- Content Context feedback accepts only currently surfaced pairs, records
  append-only server-derived rank/reason/version evidence, suppresses a
  negative pair only on later retrieval, projects positive state, and permits
  only the latest decision to be undone with a `clear` event;
- the open drawer never removes or reorders a just-rated row, visually subdues
  `not_relevant`, exposes inline Undo, and invalidates its cached result only
  after close or a switch to another post;
- the Library storage GET validates its 1--12 recommendation bound, returns
  usage plus `recommendations: []` when no positive full copies exist, ranks
  recommendations deterministically, excludes tombstones, exposes only its
  documented safe fields, and has no mutation method or provider path;
- the storage GET returns an empty, non-null Saved snapshot and recommendation
  array when no current Saved claim exists, computes populated Saved counts and
  bytes from active unresolved claims, classifies positive-byte full copies as
  local-copy and all other Saved items (including zero-byte full-copy media
  metadata) as source-dependent, orders Saved recommendations FIFO with
  deterministic id tie-breaking, excludes resolved/tombstoned/non-Saved items,
  excludes current Saved items from general full-copy recommendations, and
  exposes no content, provenance, audit, claim-internal, or provider fields;
- migration failure leaves the source schema/version unchanged;
- equivalent identities deduplicate while ambiguous fingerprints do not merge;
- Read later from a final Timeline item derives only persisted text server-side,
  creates current Saved membership, and is idempotent while that membership is
  active without accepting client content or calling a provider;
- Read later remains truthful for unavailable text, and non-final or tombstoned
  Timeline evidence fails closed;
- Keep in Library reuses the Read Later full-copy version, resolves Saved, and
  creates permanent Keep ownership without duplicating content;
- Done resolves Saved, releases temporary Read Later content without Keep, and
  preserves full copy when permanent Keep ownership exists;
- Keep then Release changes the tier and payload bytes without losing the stub;
- retention/session deletion leaves active memory intact;
- Less after routine More removes only a recall stub with no independent
  provenance/retention intent, creates no tombstone, and permits a later More
  to recreate it;
- Remove clears local rows without a tombstone and allows a later More to
  recreate the identity;
- Forget permanently clears URL/text/provenance and leaves only an opaque
  tombstone that suppresses later automatic recapture;
- Full Reset removes active memory, content, provenance, actions, aliases, and tombstones;
- SQLite integrity and foreign-key checks pass after fresh open and recovery.
