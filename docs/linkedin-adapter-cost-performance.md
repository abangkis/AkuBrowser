# LinkedIn adapter: time, identity, and token balance

## Executive summary

- **Capture is already bounded and reliable.** In the 12 latest development
  sessions reviewed on July 27, 2026, LinkedIn capture completed in about
  13 seconds at the median and 14 seconds at the 90th percentile. Every run
  produced a managed-surface release receipt and none required a focus
  intervention.
- **Repeated reasoning is the avoidable cost.** LinkedIn used about 83K
  input-plus-output tokens in the sample: about 40K for Acquisition Planning
  and 43K for Candidate Evaluation. Two retained entries were the same
  long-form post observed first with a fallback identity and later with a
  canonical LinkedIn identity.
- **Fix identity before adding browser work.** AkuSidecar promotes a strict
  fallback identity to a later stable platform ID or canonical permalink when
  source, author, and full normalized text match. Short or missing text is not
  eligible, and two different valid native identities never merge. Content
  kind and exact publication time guard against an author intentionally
  republishing the same wording. Relative timestamps marked as estimated are
  treated as unavailable; when exact publication time is unavailable, fallback
  promotion is limited to 30 minutes. A stable platform ID outranks harmless
  permalink spelling or tracking-query differences.
- **Use a guarded local frontier.** LinkedIn may skip a no-op Acquisition
  Planning turn only after complete, non-deadline-exhausted capture, at least
  one completed scroll, zero new candidates, and no `has more` signal.
  Ambiguous evidence still uses model planning, and requested follow-up keeps
  the existing continuation-overlap contract.
- **Do not change media or hydration in this slice.** LinkedIn media acquisition
  stays on the existing generic Bridge path, and the configured 18-second
  two-phase hydration budget remains unchanged.

## Observed baseline

The development baseline is a frozen window of 12 terminal sessions ending
with the check created at `2026-07-26T18:18:03.2938107Z` and completed at
`2026-07-26T18:19:37.656005Z`. Source work overlaps under Progressive wait, so
per-source durations are not additive and should not be treated as session
wall time.

| Measure | Observed value |
| --- | ---: |
| Sessions | 12 |
| Complete / partial sessions | 10 / 2 |
| LinkedIn capture median / p90 | 12.7s / 14.1s |
| LinkedIn total median / p90 | 13.1s / 93.4s |
| LinkedIn captured / evaluated / selected / added | 34 / 2 / 2 / 2 |
| Unchanged native resurfaces skipped locally | 32 |
| LinkedIn token use | 83,054 |
| Acquisition Planning | 40,131 tokens across 2 invocations |
| Candidate Evaluation | 42,923 tokens across 2 invocations |
| Follow-up capture rounds | 0 |
| Managed-surface release receipts | 12 of 12 |
| Focus interventions | 0 |

The two added entries had the same author and exact long-form text. The earlier
capture lacked a stable permalink or platform identity; the later capture
exposed a canonical LinkedIn identity. Treating them as unrelated evidence
spent about 41K tokens on the second observation and retained a duplicate card.
The identity-promotion slice prevents that pattern for future observations
without using semantic similarity or broad author-and-text deduplication.

## Safety and cost guardrails

1. Identity promotion is a generic continuity rule in AkuSidecar, not a
   LinkedIn selector heuristic.
2. Promotion requires a strict native-independent signature. Missing or
   ambiguous author or full-text evidence does not merge.
3. A stable native identity is authoritative. If both observations carry
   different valid native identities, the second remains distinct and Update
   Inbox records a conflict.
4. Matching exact publication timestamps and content kinds allow a fallback
   to inherit a later native identity. A mismatch remains separate.
   Relative/estimated timestamps are treated as unavailable. If either exact
   timestamp is unavailable, the promotion window is bounded to 30 minutes
   rather than treating identical wording as permanent identity.
5. `local_frontier` removes only a planning invocation that cannot point to a
   new frontier. It never bypasses Candidate Evaluation for a genuinely new
   candidate.
6. Incomplete, degraded, deadline-exhausted, or `has more` capture evidence
   retains the model planner. A requested second round still requires overlap
   with the prior LinkedIn frontier.
7. The slice adds no snapshot, scroll, hydration delay, media attempt, or
   foreground permission.

## Acceptance criteria

1. Capture one LinkedIn post without a stable native identity, then capture the
   same source, author, full text, content kind, and publication time with a
   canonical platform ID or permalink. The second observation must resolve
   through native continuity before planning or Candidate Evaluation.
2. Capture two observations with identical author and text but different valid
   native IDs. They must remain separate and emit an identity-conflict receipt.
3. Repeat identical author and text with a different exact publication time or
   content kind. It must remain separate. A timestamp-free or
   relative-timestamp fallback may be promoted only inside the 30-minute
   recovery window.
4. Complete a LinkedIn scroll with zero new candidates and no `has more`
   signal. Complete, non-deadline-exhausted capture should report
   `local_frontier`; incomplete or deadline-exhausted capture should report
   model planning.
5. Force a planned follow-up and verify that the next LinkedIn snapshot still
   contains the required continuation overlap.
6. Confirm Update Inbox reports stable or fallback identity, promotion or
   conflict, planning mode (`local_frontier`, model, or
   `continuity_bypass`), and follow-up yield without exposing raw post text or
   adding model usage.
7. Re-run LinkedIn image, attachment, and hydration acceptance unchanged.

## Expected effect and limits

In this small sample, avoiding the repeated canonical observation would have
saved about 41K LinkedIn tokens. A guarded local-frontier decision on the first
eligible run would have avoided roughly another 19K planning tokens. The
combined counterfactual is about 60K of 83K LinkedIn tokens, but it is not a
production savings forecast: the sample is one signed-in account, contains only
two reasoning-bearing LinkedIn runs, and had no genuine follow-up round.

The feature should therefore be judged by receipts rather than by the estimate:
no false identity merges, no lost continuation overlap, fewer no-op planning
invocations, and unchanged media or hydration success.
