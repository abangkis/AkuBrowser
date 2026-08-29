# Personal Memory and Library Contract

This document is the canonical contract for the Personal Memory foundation.
It defines durable local memory independently from the operational Timeline,
Inbox, preference learning, and semantic event resolver. The first shipped
foundation is storage and store APIs only; HTTP, FTS/search, ingestion from
`ComposeSession`, and Library UI remain later milestones.

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

## Storage contract (AkuSidecar schema 12)

The additive v11 to v12 migration creates these independent tables and indexes.
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
Schema migration is forward-only and additive: it runs in a transaction,
creates the v12 tables/indexes, updates `meta.schema_version` only after all
objects succeed, and leaves v11 operational rows untouched. There is no
ComposeSession ingestion in this foundation; the eventual ingestion boundary
is the final surviving item after composition, not `CompleteRun`.

## Required acceptance checks

- fresh databases and v11 databases open at schema 12 with the exact objects above;
- migration failure leaves the source schema/version unchanged;
- equivalent identities deduplicate while ambiguous fingerprints do not merge;
- Keep then Release changes the tier and payload bytes without losing the stub;
- retention/session deletion leaves active memory intact;
- Delete clears URL/text/provenance and leaves only an opaque tombstone;
- Full Reset removes active memory, content, provenance, actions, aliases, and tombstones;
- SQLite integrity and foreign-key checks pass after fresh open and recovery.
