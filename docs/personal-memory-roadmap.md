# Personal Memory Product Roadmap

This document is the sequencing authority for product work built on Personal
Memory. It deliberately separates the next bounded Living Topics experiment
from bookmark ingestion and from the eventual full Living Topics product. The
implemented behavior remains governed by the
[Personal Memory and Library contract](personal-memory-contract.md); a roadmap
phase does not become an active contract until its own design and acceptance
checks are approved.

## Accepted sequence

```text
Personal Memory foundation
        |
        v
Living Topics Thin Slice
        |
        v
Bookmark Import and Management
        |
        v
Living Topics Full
```

## Phase 1: Living Topics Thin Slice

The active design and acceptance boundary for this phase is the
[Living Topics Thin Slice contract](living-topics-thin-slice-contract.md).

The thin slice tests whether existing and newly confirmed Timeline evidence can become useful,
source-backed understanding instead of another collection of links. A user
creates and names a topic explicitly, supplies routing criteria, corrects
automatic membership by adding or removing evidence, and requests a bounded topic snapshot. The snapshot may organize
versioned claims, assessments, cited evidence, timestamps, and deltas from the
previous user-requested snapshot. Every statement must retain visible links to
the Memory evidence that supports it. Topic membership is independent from
Saved, Keep, More/Less, and Content Context feedback.

This phase is intentionally not the full Living Topics concept. It has no
automatic topic discovery or clustering, scheduled snapshot refresh, alerts,
source subscription, browser capture, or automatic Timeline insertion. Its one
background action is bounded routing of final non-duplicate Timeline posts into
existing user-defined topics. It cannot silently create Keep or
Saved ownership, treat topic membership as a taste signal, or become an
infinite feed. Refresh and synthesis are explicit, bounded user actions over
already available local evidence.

This phase is now implemented. A manually created topic can be revisited,
learns from auditable membership corrections, produces a bounded source-cited snapshot,
and shows truthful empty/no-change states without inventing a delta. The next
product phase remains Bookmark Import and Management; thin-slice completion
does not activate any deferred Full behavior.

## Phase 2: Bookmark Import and Management

Import begins as a read-only preview over bookmarks or history selected by the
user. It normalizes identity, reports supported, duplicate, skipped, and invalid
entries, and shows the recall stubs that would be created before any mutation.
Only an approved batch may write Personal Memory. Imported entries begin as
recall stubs with weak `imported` provenance; they are not Saved, Keep,
More/Less, Timeline items, or automatic topic members.

After preview and approved import are trusted, management may add bounded batch
history, source/folder filters, duplicate resolution, re-import, removal, and
explicit attachment to a Living Topic. One-time import and continuous sync are
separate decisions. Background bookmark synchronization is not implied by this
phase and requires its own permission, lifecycle, and conflict contract.

The phase is complete when preview and committed results reconcile exactly,
deduplication is deterministic, every imported item has auditable provenance,
and undo/removal cannot delete an item that later gained independent ownership
or provenance.

## Phase 3: Living Topics Full

Living Topics Full turns the proven topic model and the broader imported
evidence pool into a bounded Keep Up capability. It may add opt-in evidence
discovery, candidate topic suggestions, versioned claim evolution,
contradiction and freshness assessment, coverage gaps, scheduled refresh, and
user-controlled notifications. These capabilities must preserve source-level
provenance, make uncertainty visible, and keep the user authoritative over
topic membership and durable retention.

Full Living Topics must not become another infinite feed or silently convert
external activity into preference learning. Automatic discovery proposes
evidence; it does not automatically Keep content, promote Timeline items, or
rewrite user-approved claims without an auditable version. Work on this phase
starts only after the thin slice proves the topic interaction and Bookmark
Import proves identity, deduplication, provenance, and lifecycle behavior at a
larger scale.

## Shared boundaries

- Personal Memory remains independent from operational sessions, runs, and
  Timeline retention.
- More/Less remains the authority for taste learning; topic and import actions
  are not implicit preference signals.
- Saved and Keep remain explicit, independent retention decisions.
- Zero matches, no change, insufficient evidence, and unknown assessment are
  valid states and are never rewritten as success or certainty.
- Every mutating phase begins behind an explicit preview or user action and
  receives a separate contract before implementation.
