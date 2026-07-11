# Unified Session Experiment Contract v0

> Status: **Implemented; live orchestration and recovery verified, positive-result product gate pending**
> Date: **2026-07-11**
> Owner: **AkuBrowser**

## 1. Purpose

The Unified Session is the default daily-use Catch Up and Manual Live experience. One user action evaluates X and LinkedIn and produces one finite, source-backed brief. Existing source-specific runs remain the execution, persistence, checkpoint, feedback, and troubleshooting units.

This contract defines the experiment boundary before implementation. It does not change the browser-acquisition budget, introduce background monitoring, or claim semantic cross-source deduplication.

## 2. Product invariants

1. The default daily-use surface is unified across X and LinkedIn.
2. A Unified Session is a parent over source-specific child runs; a child run never changes its `source` contract.
3. Child runs execute sequentially in the declared source order for the initial experiment.
4. Each child may promote at most five items. Five is a ceiling, not a quota.
5. The unified brief contains at most ten items and may contain zero.
6. Browser-acquisition limits remain unchanged until evidence shows that acquisition, rather than classification or source quality, is the bottleneck.
7. The unified list is finite, scrollable, and ends with an explicit finish line. It must not auto-load another session.
8. Single-source execution remains available as an Advanced/Pilot capability.
9. Source provenance, child-run identity, per-source coverage, and partial failures remain inspectable.
10. Page content remains untrusted evidence and cannot alter the session policy.

## 3. Logical model

```text
UnifiedSession
├── X child run
├── LinkedIn child run
├── derived session status
├── deterministic unified result
└── aggregate coverage
```

The parent adds orchestration and presentation. It does not replace `RunContract`, `ResultContract`, `BrowserAdapter`, `ReasoningProvider`, source checkpoints, or source-specific knowledge state.

## 4. Session request

The conceptual request is:

```json
{
  "mode": "catch_up",
  "intent": "Show material AI and technical-engineering changes that affect my work.",
  "sources": ["x", "linkedin"],
  "maxItemsPerSource": 5
}
```

### Validation

- `mode` is `catch_up` or `manual_live`.
- `intent` follows the existing bounded run-intent rules.
- Experiment v0 requires exactly `x` and `linkedin`, once each.
- Source order is execution order; v0 uses `x`, then `linkedin`.
- `maxItemsPerSource` is an integer from one through five; daily-use v0 defaults to five.
- `maxItemsTotal` is derived as `sources.length * maxItemsPerSource` and is capped at ten.
- Browser scrolls, capture timeout, acquisition rounds, and continuation budgets come from existing deterministic policy and are not supplied by the page.

## 5. Persisted session shape

The implementation may evolve its physical SQLite schema, but it must preserve this logical shape:

```json
{
  "id": "session-id",
  "mode": "catch_up",
  "intent": "...",
  "sources": ["x", "linkedin"],
  "maxItemsPerSource": 5,
  "maxItemsTotal": 10,
  "status": "running",
  "activeSource": "x",
  "createdAt": "...",
  "startedAt": "...",
  "completedAt": null,
  "children": [
    { "source": "x", "runId": "run-id", "status": "reasoning", "ordinal": 0 },
    { "source": "linkedin", "runId": null, "status": "queued", "ordinal": 1 }
  ]
}
```

Every child attempt is retained. Replacing or retrying a child must not rewrite prior evidence. Retry behavior is outside experiment v0; the user starts a new Unified Session.

## 6. Lifecycle

### Session statuses

| Status | Meaning |
|---|---|
| `queued` | Session exists but no child has started. |
| `running` | At least one child is active or a later child remains queued. |
| `completed` | Both child runs completed, including valid empty results. |
| `partial` | At least one child completed and at least one child failed or was cancelled. |
| `failed` | No child completed and execution cannot continue. |
| `cancelled` | User cancellation stopped the active child and prevented queued children from starting; no child completed. |

### Sequential execution

1. Create the session and both child slots transactionally.
2. Create and dispatch the X child run.
3. When X becomes terminal, persist its outcome.
4. Unless the session was cancelled, create and dispatch the LinkedIn child run.
5. When both slots are terminal, derive the session status and unified result.

A failed X run does not prevent LinkedIn from running. A cancelled session prevents any not-yet-started child from starting.

### Checkpoints

- Only a completed child run advances its source-and-mode checkpoint.
- Failed or cancelled children do not advance checkpoints.
- Parent completion never creates or advances a global checkpoint.
- A partial session exposes the unaffected completed source truthfully.

## 7. Unified result

The unified result is a deterministic projection of validated child results. It does not invoke a second reasoning provider in experiment v0.

Each unified item carries the unchanged validated result item, the producing `runId`, the parent `sessionId`, and its source-specific feedback target.

### Merge order

1. Partition child items into `P1`, `P2`, `P3`, and `P4` lanes.
2. Emit lanes in that priority order.
3. Within a lane, round-robin the declared source order while preserving each child's provider-selected order.
4. Do not promote, rewrite, or synthesize an item during merge.
5. Stop at `maxItemsTotal`, although valid child ceilings should already enforce it.

Example:

```text
P1 X
P1 LinkedIn
P1 X
P2 X
P2 LinkedIn
```

### Duplicate policy

Child-level evidence deduplication remains active. Experiment v0 does not semantically merge X and LinkedIn items. Exact source-backed identities remain distinct across platforms. Cross-source event grouping or supersession requires representative pilot examples and a separate calibration contract.

### Summary and coverage

Session summary text is deterministic and factual, for example: `6 material items from 2 completed sources.` It must not add claims beyond child results.

Aggregate coverage includes:

- requested, completed, failed, and cancelled sources;
- result count by source and total;
- child run IDs and statuses;
- per-source bounded coverage without flattening away differences;
- whether the session is complete, partial, failed, or cancelled; and
- an explicit statement that the session covers bounded samples, not complete feeds.

## 8. Feedback semantics

- Item feedback from the unified list is posted to the producing child run and item ID.
- An empty-source verdict remains attached to that source's completed empty child run.
- The session is globally empty only when both completed child results contain zero items.
- `Correctly empty` for one source says nothing about the other source.
- Experiment v0 does not introduce a session-level usefulness verdict.
- Pilot Review continues to inspect child runs; a later session filter may group them without changing feedback ownership.

## 9. Daily-use UI contract

### Default surface

- One mode selector and one intent field.
- No default source selector; the Unified Session requests X and LinkedIn.
- One action starts the bounded session.
- Progress lists each source separately while acquisition remains sequential.
- The unified list appears after both child slots are terminal.
- A partial result is displayed with a visible source failure rather than discarded.

### Finite scrolling

- The result count is known before the unified list is shown.
- The page may show progress such as `3 of 7` as the user scrolls.
- Every card exposes source and priority.
- Details may expand, but expansion does not fetch another batch.
- The end marker says `End of catch-up` or the equivalent mode-specific finish line.
- Starting another session requires an explicit user action.
- Infinite scroll, automatic pagination, and silent next-session loading are forbidden.

### Advanced/Pilot surface

Single-source execution remains available for debugging, adapter calibration, and controlled experiments. It is not the default daily-use flow.

## 10. Experiment metrics

Measure the Unified Session separately from child-run health:

- unified sessions started and terminal;
- completed, partial, failed, and cancelled session rates;
- result count per source and per session;
- sessions with zero results;
- promoted items reviewed and positive item rate;
- wrong-lane and duplicate feedback;
- time to first terminal source and total session duration;
- sessions in which one source dominates the result count;
- source links opened;
- whether the user reaches the explicit end marker; and
- explicit request to run another bounded session.

Passive scroll depth must not automatically become a ranking signal during this experiment. It is evaluation evidence only.

## 11. Experiment gates

### Functional gate

- One request creates exactly two source-specific child slots.
- Child execution is sequential and resumable from persisted state.
- Completed, empty, failed, cancelled, and partial combinations derive the correct session status.
- Unified ordering is deterministic and never loses provenance.
- Item feedback still validates against the producing result.
- Restart recovery does not duplicate completed child work.

### Product gate

Collect at least five natural daily-use Unified Sessions, with at least three sessions containing one or more promoted items. Review every promoted item before judging usefulness. Do not force low-value results to satisfy this sample requirement.

The experiment should answer:

1. Is a maximum of five items per source useful without becoming noisy?
2. Does the finite scroll feel sufficient while still producing a finish line?
3. Does one source dominate the brief?
4. Are cross-source duplicates material enough to justify semantic merging?
5. Is the existing browser-acquisition budget the limiting factor?

### Acquisition escalation gate

Do not increase scrolling merely because a session returns fewer than ten items. Consider changing acquisition only when reviewed sessions show valuable information was repeatedly outside the bounded sample and classification or suppression is not the cause.

## 12. Explicit non-goals for v0

- parallel child execution;
- arbitrary source selection in the default flow;
- more than X and LinkedIn;
- semantic cross-source event merging;
- cross-source temporal supersession;
- a second model pass for unified summarization;
- background scheduling or P0 notification;
- infinite scrolling or automatic continuation;
- implicit behavioral ranking; and
- changing existing browser movement budgets.

## 13. Implementation sequence after acceptance

1. Add a canonical machine-readable session schema and contract-sync checks.
2. Add additive SQLite session and child-attempt persistence behind `StateStore`.
3. Add deterministic session orchestration and merge logic to `JobEngine`.
4. Add session create, read, and cancel HTTP endpoints.
5. Make Unified Session the default UI while retaining Advanced/Pilot single-source execution.
6. Add lifecycle, restart, partial-failure, merge-order, feedback-routing, and HTTP tests.
7. Run deterministic smoke tests, then live Chrome pilot on X and LinkedIn.

### Current implementation status

Steps 1 through 6 are implemented in AkuSidecar. The existing source-specific bridge protocol remains unchanged. Automated coverage includes sequential completion, persistence across restart, partial success after a source failure, cancellation, deterministic merge order, request validation, and HTTP lifecycle.

A live unified run in the development Chrome profile verified sequential X-to-LinkedIn orchestration, finite completion, same-session UI recovery after a reload, and one bounded LinkedIn fallback from pending-content reveal to native detect-only acquisition. That run also exposed an important truthfulness boundary: a source with zero visible evidence blocks is acquisition-unavailable, not a trustworthy empty result. The runtime now fails that source explicitly, preserves a partial result from the other source, and excludes the non-evidence run from empty-result review metrics. The remaining product gate is to collect natural sessions with promoted items and complete item-level usefulness review as defined above.
