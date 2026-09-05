# Personal Memory Product Roadmap

This document is the sequencing authority for product work built on Personal
Memory. It separates the graduated local Living Topics stages from bookmark
ingestion and from later external discovery. The
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
Living Topics Full Stage 1 — local activation and review
        |
        v
Living Topics local knowledge use — move, lifecycle, Related Context
        |
        v
Bookmark Import and Management
        |
        v
Living Topics Full — broader discovery and Keep Up
```

## Phase 1: Living Topics Thin Slice

The completed design and acceptance boundary for this phase is the
[Living Topics Thin Slice contract](living-topics-thin-slice-contract.md).

The thin slice tests whether existing and newly confirmed Timeline evidence can become useful,
source-backed understanding instead of another collection of links. A user
creates and names a topic explicitly, supplies routing criteria, and corrects
automatic membership by adding or removing evidence. Evidence changes trigger a coalesced background refresh of the
topic's current understanding. Material versions organize claims, assessments, cited evidence, timestamps, and deltas
from the previous materially different understanding. Every statement must retain visible links to
the Memory evidence that supports it. Topic membership is independent from
Saved, Keep, More/Less, and Content Context feedback.

This phase is intentionally not the full Living Topics concept. It has no
automatic topic discovery or clustering, periodic scheduled refresh, alerts,
source subscription, browser capture, or automatic Timeline insertion. Its one
background actions are bounded routing of final non-duplicate Timeline posts into
existing user-defined topics and secondary synthesis over already-local evidence. It cannot silently create Keep or
Saved ownership, treat topic membership as a taste signal, or become an
infinite feed. Synthesis is event-driven by evidence or criteria changes; `Refresh now` remains an explicit
secondary control. It does not poll or discover external sources.

This phase is implemented and graduated. A manually created topic can be revisited,
learns from auditable membership corrections, automatically maintains a bounded source-cited current understanding,
and publishes history only for material semantic changes. Exact no-change and insufficient-evidence evaluations do
not create noisy versions. The next
graduated local stage is Full Stage 1; thin-slice completion does not activate
external discovery.

## Phase 1B: Living Topics Full Stage 1

The active design and acceptance boundary is the
[Living Topics Full Stage 1 contract](living-topics-full-stage-1-contract.md).
This stage adds revisioned purpose, aliases, include/exclude criteria, a durable
bounded scan over already-local Memory, suggested evidence, and explicit
Accept/Reject/Undo feedback. New final non-duplicate Timeline posts retain the
thin-slice automatic routing path; retroactive activation remains proposal-only
until Accept.

This stage is implemented without waiting for Bookmark Import because it reads
only the existing local Memory pool and does not invent broader acquisition or
retention authority. It deliberately excludes browser discovery, continuous
capture, clustering, schedules, and system notifications. A bounded in-app
badge reports newly auto-routed evidence in the menu and affected topic; explicit
topic selection acknowledges only the visible evidence generation.

The graduated local continuation adds reversible Move/Undo between topics,
explicit current-vs-historical knowledge authority, and current supported topic
insights in both Library Search and Timeline Related Context. Library Search
keeps topic knowledge separate from individual Memory results and remains
provider-free and read-only. Current insights exclude historical and temporally
unknown claims, and distinguish evidence publication time from projection
refresh time. Lifecycle proof V5 additionally requires retained-source support
for completed or cancelled claims; older projections require refresh before
regaining current authority. This still uses only existing local Memory, does
not broaden acquisition, and does not authorize Bookmark work. A future Ask
this topic path remains unimplemented and requires its own cited, read-only
answer contract.

## Phase 2: Bookmark Import and Management

This phase is frozen until the user explicitly authorizes Bookmark Import or
Management work. Completion of any Living Topics stage does not implicitly
start it.

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

Later Living Topics Full stages turn the proven topic model and the broader imported
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
starts only after local activation proves candidate review and Bookmark Import
proves identity, deduplication, provenance, and lifecycle behavior at a larger
scale.

## Shared boundaries

- Personal Memory remains independent from operational sessions, runs, and
  Timeline retention.
- More/Less remains the authority for taste learning; topic and import actions
  are not implicit preference signals.
- Saved and Keep remain explicit, independent retention decisions.
- Zero matches, no change, insufficient evidence, and unknown assessment are
  valid states and are never rewritten as success or certainty.
- Every model-backed roadmap addition must extend the
  [LLM Invocation and Token Cost Reference](llm-invocation-and-token-cost.md)
  with its trigger, provider-free alternative, durable usage receipt, and a
  dated observed baseline before it is treated as part of normal operating
  cost.
- Every mutating phase begins behind an explicit preview or user action and
  receives a separate contract before implementation.
