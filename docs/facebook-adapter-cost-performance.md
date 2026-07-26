# Facebook adapter: time and token balance

## Executive Summary

- **Keep media improvement local.** Across the 12 most recent development
  sessions, Facebook capture itself took about 14-16 seconds when it completed.
  Longer Facebook cards mostly reflected waiting behind shared reasoning work,
  not browser hydration.
- **Reasoning, not capture, is the material cost.** The 12 sessions used about
  1.15M input-plus-output tokens. Facebook accounted for about 144K (12.5%),
  all from four runs that contained a new candidate. A new Facebook candidate
  cost about 36K tokens on average: roughly 17K for acquisition planning and
  19K for candidate evaluation.
- **Use deterministic frontier evidence before another model turn.** When one
  bounded Facebook scroll produces no new candidate and no `has more` signal,
  AkuSidecar now finishes acquisition locally. This removes an observed
  no-op planning turn while preserving candidate evaluation.
- **Do not buy recall with more background work yet.** Media diagnostics reuse
  the already captured observation. They add no snapshot, hydration wait, or
  reasoning invocation. New capture attempts require live evidence that the
  current bounded path missed a distinct post or media object.

## Where the time and tokens currently go

The development sample covers the 12 latest sessions visible in Update Inbox
on July 27, 2026. Sources run progressively and overlap, so source durations
must not be summed to estimate user waiting time. Session wall time is the
elapsed time from session start to terminal state; token use is additive across
all model invocations.

| Measure | Observed value |
| --- | ---: |
| Sessions | 12 |
| Median session wall time | 161 seconds |
| 90th-percentile session wall time | 208 seconds |
| Median input + output tokens per session | 73K |
| Mean input + output tokens per session | 96K |
| Facebook capture, completed runs | about 14-16 seconds |
| Sessions where Facebook was the longest source | 2 of 12 |
| Facebook candidates captured / evaluated | 11 / 4 |
| Facebook token use | 144K of 1.15M |
| Mean tokens when Facebook required reasoning | about 36K |

Across all sources, acquisition planning used about 505K tokens and candidate
evaluation about 548K. Semantic event resolution used about 86K and AI Deep
Detection about 13K in this sample. These categories are additive costs even
when their source work overlaps in wall-clock time.

The latest Facebook capture reported two admitted DOM structures but only one
unique native post. The second structure was a repeated wrapper, not proof of
another feed item. After one bounded scroll, the frontier moved but produced
zero new candidates. A longer settling delay had already repeated the same
item and only increased latency.

## Cost-aware implementation guardrails

1. The adapter may declare source DOM and frontier policy, but it does not
   select content or decide relevance.
2. The generic media engine keeps the existing one-attempt bound. Facebook
   does not receive an extra snapshot or a second hydration phase merely to
   improve diagnostics.
3. The local frontier fast path applies only after at least one completed
   scroll, zero new candidates, and no explicit `has more` candidate signal.
   LinkedIn now declares the same generic capability behind stricter complete,
   non-deadline-exhausted capture guards; X retains model planning. This does
   not change Facebook's adapter, hydration, or media behavior.
4. Candidate evaluation remains model-backed whenever a new Facebook item
   survives continuity filtering. The optimization removes only follow-up
   planning that cannot point to a new frontier.
5. Update Inbox exposes media outcomes—primary, recovered, unavailable,
   attempts, expected kinds, and foreground requirements—from evidence already
   present in the observation. Reading these diagnostics consumes no tokens.

## Recommended next steps

1. Run acceptance against a Facebook feed containing a new image post and a
   new video post, then inspect the new Media evidence panel.
2. Compare the next candidate-bearing Facebook run with the observed baseline:
   it should retain candidate-evaluation cost but report no acquisition-planning
   invocation when the local frontier is exhausted.
3. Improve selectors or media extraction only when telemetry shows a rendered
   media root ending as unavailable. Do not add model reasoning to repair a
   missing URL.
4. Revisit the fast path if a live run proves that `zero new after one scroll`
   hides a distinct eligible post that a bounded follow-up round can recover.

## Further questions

- Does Facebook expose different wrappers for ordinary, shared, Page,
  suggested, sponsored, image, and video posts that change the reliability of
  the local frontier signal?
- How often does a rendered Facebook media root end as unavailable, and which
  extraction stage fails?
- Do later Facebook layouts require a stricter source-specific guard on the
  already generic local-frontier capability?

## Caveats and assumptions

This is a small development sample from one signed-in account and one local
runtime. One session had partial model-usage coverage. Percentiles describe
these 12 sessions, not production performance. Source durations overlap under
progressive wait, and some per-source total durations include time waiting for
the shared reasoning lane; they cannot be interpreted as pure adapter CPU or
browser time.
