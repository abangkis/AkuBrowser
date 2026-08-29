# Personal Memory and Library Contract

This document is the canonical contract for the Personal Memory and Library foundation.
It defines durable local memory independently from the operational Timeline,
Inbox, preference learning, and semantic event resolver. The local read-only
Library surface includes deterministic FTS5 search and GET-only HTTP reads.
Mutation HTTP APIs, ingestion from `ComposeSession`, and Library UI remain
later milestones.

## Product boundary

| Layer | Contract | Lifetime |
| --- | --- | --- |
| Timeline | Selected results prepared for the current update | Operational; subject to retention |
| Preference ledger | Compact evidence for More/Less taste learning | Durable, but not content archive |
| Knowledge/events | Reasoning structures used by the update pipeline | Operational/semantic retention |
| Personal Memory | User-owned recall stubs and explicitly kept text | Independent of sessions/runs/Timeline |

`More` remains a preference signal. A routine `More` action may guarantee a
recall stub, but it does not imply a full copy. `Keep full copy` is the explicit
decision that retains text. `Release full copy` removes the text payload while
keeping the recall stub. Neutral Timeline results and calibration corrections
do not become durable memory automatically.

The guarantee is narrow: only an explicit routine `More` submitted for a
Timeline item that still exists after composition and belongs to a terminal
`completed` or `partial` session may project a recall stub. `Less`/
`Not interested`, neutral choices, calibration, selection corrections, AI
feedback, and non-surviving candidates are memory-neutral. A later `Less` or
undo changes preference authority only; it does not delete user-owned recall
history.

## State model

Each `memory_items` row has two independent dimensions:

```text
active + recall       -- metadata, source pointer, bounded labels
active + full_copy    -- recall data plus one or more text versions
tombstone             -- opaque deletion marker; no URL, text, author, or provenance
```

The delete transition removes raw aliases, provenance, and content versions,
then clears all identifying fields. It preserves only the opaque item id,
lifecycle state, timestamps, and keyed digests in `memory_tombstone_aliases`.
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

## Storage contract (AkuSidecar schema 13)

The additive v11 to v12 migration creates the memory tables and the additive
v12 to v13 migration creates/backfills the local search index. Both migrations
are transactional and update `meta.schema_version` only after all objects and
backfill rows succeed. The v13 index is provider-free and has no foreign key to
operational data.
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
by the delete privacy transition.

Index: `memory_provenance_item_created`.

### `memory_actions`

`id`, `memory_item_id`, `action`, `detail_json`, `created_at`. Supported
actions are `create_stub`, `update_stub`, `keep_full_copy`,
`release_full_copy`, `read_later`, `mark_read`, `import`, and `delete`.

Indexes: `memory_actions_item_created` and `memory_actions_action_created`.

No Personal Memory table has a foreign key to `sessions`, `runs`, or
`timeline_items`; operational deletion and `EnforceRetention` therefore cannot
delete a durable memory as a side effect.

### `memory_search_fts`

This FTS5 virtual table contains one logical row for every active memory item:
`memory_item_id` (unindexed), `title`, `summary`, `author`, `tags`, `facets`,
and `full_content`. It is rebuilt transactionally on recall create/update,
Keep, Release, and Delete. Tombstones are never indexed; Release clears the
full-copy field and Delete removes the row. Existing active v12 items are
backfilled during migration.

Search uses deterministic FTS5 BM25 with weights in column order
`title=10`, `summary=5`, `author=2`, `tags=3`, `facets=3`, and
`full_content=1` (lower scores rank first), then stable tie-breakers
`updated_at DESC, id DESC`. Empty queries use the same stable recent ordering
without touching FTS. The opaque keyset cursor is bound to the query and
filters; a cursor cannot be reused for another query.

The read-only HTTP contract is:

- `GET /api/library/items?query=&source=&tier=&publishedFrom=&publishedTo=&limit=&cursor=` lists or searches active items;
- `GET /api/library/items/{id}` returns one active item, including explicitly
  retained full text when present.

`limit` is 1--50 (default 24), query text is capped at 200 Unicode characters,
and cursors are capped at 512 characters. `publishedFrom` and `publishedTo`
accept RFC3339 timestamps or `YYYY-MM-DD`; a date-only `publishedTo` includes
the entire UTC day. The response exposes bounded recall
metadata and optional user-kept full text, but never tombstones, HMAC digests,
audit/provenance internals, credentials, or provider payloads. There are no
Library mutation routes.

The top-level Library view in the AkuBrowser web app is a read-only client of
these routes. It uses explicit local search, source/tier/date filters, stable
cursor-based Load more pagination, and a detail pane. The detail pane may show
only the returned full text and safe HTTPS source/media metadata references; it
does not infer a reason such as “remembered because More” when that reason is
not present in the public API.

## Media and privacy limits

The foundation stores UTF-8 text and at most 16 bounded HTTPS media metadata
references per item/version. A reference may contain kind, URL, title, and alt
text. Binary media, downloaded files, cookies, raw prompts, provider payloads,
and credentials are not stored. Full-copy text is capped at 4 MiB per action;
context and audit details are separately bounded.

Logical storage usage reports content, metadata, provenance, and action bytes;
it is not a claim about SQLite file or WAL size. An explicit full copy must not
be silently removed by pressure. Pressure/bucket UI and Spring Cleaning are
later milestones.

## Transaction and migration rules

Memory creation/update, aliases, optional provenance, and the corresponding
action are committed atomically. Keep, release, and delete are also atomic.
For an eligible routine `More`, the canonical `feedback_events` row and its
recall-stub projection, provenance, and action share one SQLite transaction;
if projection fails, the preference row is rolled back and retry is safe.
Schema migration is forward-only and additive: it runs in a transaction,
creates the v12 tables/indexes, creates and backfills the v13 search index,
updates `meta.schema_version` only after all objects succeed, and leaves v11
operational rows untouched. There is no `ComposeSession` ingestion in this
foundation; the projection is an explicit feedback boundary over the final
surviving Timeline item.

## Required acceptance checks

- fresh databases and v11 databases open at schema 13 with the exact objects above;
- v12 databases backfill active memory into FTS5 and leave failed migration/version state unchanged;
- local lexical ranking, source/tier/date filters, stable keyset cursors, empty-query recency, and restart persistence work without a provider;
- release and delete scrub their FTS rows as well as their stored payloads;
- Library HTTP reads validate bounds, hide internal fields, return 404 for tombstones, and expose no mutation route;
- migration failure leaves the source schema/version unchanged;
- equivalent identities deduplicate while ambiguous fingerprints do not merge;
- Keep then Release changes the tier and payload bytes without losing the stub;
- retention/session deletion leaves active memory intact;
- Delete clears URL/text/provenance and leaves only an opaque tombstone;
- Full Reset removes active memory, content, provenance, actions, aliases, and tombstones;
- SQLite integrity and foreign-key checks pass after fresh open and recovery.
