# LLM Invocation and Token Cost Reference

This document is the canonical reference for where the current AkuBrowser
pipeline may call a model and how locally retained token receipts should be
interpreted. It describes local invocation boundaries; dated measurements below
remain tied to their recorded versions. It is not a provider price guarantee or
a future Bookmark Import contract.

## End-to-end invocation map

```text
bounded browser capture                                           local
  -> native identity / resurface check                            local
  -> conditional Acquisition Planning                            model
  -> Candidate Evaluation for each source-run with new evidence  model
  -> preference scoring and finite composition                   local
  -> conditional Semantic Event Resolution                       model
  -> AI Fast Detection and Timeline publication                  local
  -> optional asynchronous AI Deep Detection                     model
  -> Personal Memory lifecycle and Library index                 local
  -> deterministic Living Topic routing                          local
  -> ambiguous Living Topic semantic routing                     model
  -> changed Living Topic understanding                          model
  -> Library Search and Related Context                           local
```

The browser capture lane never sends an unbounded feed to a provider.
Acquisition Planning receives bounded capture/frontier telemetry rather than
post content or prior knowledge. Candidate Evaluation receives bounded evidence
and locally selected prior-knowledge context. Preference scoring, selection,
global composition, exact native continuity, deterministic topic matching,
Library FTS search, Personal Memory lifecycle work, and Related Context are
provider-free.

## Invocation conditions

| Process | Execution | When a model is used | Provider-free alternative |
| --- | --- | --- | --- |
| Acquisition Planning | In-run | Capture evidence is incomplete, degraded, contradictory, or otherwise needs a bounded follow-up decision | A complete source-declared local frontier may finish acquisition |
| Candidate Evaluation | In-run | A source-run contains one or more new quality-admitted candidates | No new candidate means no evaluation call |
| Semantic Event Resolution | In-run | A bounded local shortlist has sufficiently strong cross-author event overlap | Unrelated reports use the local fast path; `show_all` bypasses resolution |
| AI Deep Detection | Async | The deterministic shortlist contains an eligible retained post, including an explicit `Unsure` review request | AI Fast Detection, platform evidence, C2PA checks, and ordinary neutral posts remain local |
| Living Topic routing | Async | Deterministic criteria do not resolve one or more remaining topic candidates | Clear criteria matches and non-matches remain local |
| Living Topic understanding | Async | Active topic evidence or criteria changes to a digest not already evaluated | An unchanged digest is a provider-free no-op; coalescing avoids one call per membership mutation |

Candidate Evaluation is recorded once per pipeline invocation. With Gemini, one
receipt may aggregate several physical provider requests because up to 20
candidates are split into chunks of at most six. The figures below are therefore
per durable AkuBrowser invocation receipt, not necessarily per provider HTTP
request.

## Observed token baseline — 2026-08-31

Lifecycle proof V5 keeps the existing Living Topic understanding invocation and
adds bounded proof fields to its structured response. Proof checking is local;
it adds no verification-model call and does not fetch or retain additional source
text. Existing invocation receipts remain the usage record. The response contract
can change output token volume, so the historical baseline below is not a V5
measurement; no new provider run or V5 operating-cost baseline was produced by
the implementation tests.

This snapshot was calculated from the development runtime's locally retained
30-day model-usage ledgers. The window contained 130 sessions and 480
receipt-bearing invocation rows. Most available receipts are from 28–31 August
2026 and include development activity plus mixed historical provider/profile
choices. These values are an engineering baseline, not a production forecast.

`Average total` is `input + ordinary output + reasoning output`. Input already
includes any cached input charged or reported by the provider; cached input is a
breakout and must not be added again. The retained receipts did not expose a
cached-input count, so cached input remains unavailable rather than being
reported as zero.

| Process | Receipts | Avg input | Avg ordinary output | Avg reasoning output | Average total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Acquisition Planning | 60 | 155 | 47 | 332 | **533** |
| Candidate Evaluation | 300 | 3,747 | 1,053 | 2,816 | **7,616** |
| Semantic Event Resolution | 110 | 3,167 | 967 | 2,696 | **6,829** |
| AI Deep Detection | 0 | unavailable | unavailable | unavailable | **unavailable** |
| Living Topic routing | 4 | 471 | 189 | 858 | **1,517** |
| Living Topic understanding | 6 | 603 | 282 | 1,452 | **2,336** |

The three in-run categories consumed 3,068,111 reported tokens across the 130
retained sessions, or an amortized **23,601 tokens per stored check**. This is
higher than adding one average call per category because one check may contain
several source-runs; the sample averaged 2.31 Candidate Evaluation receipts per
session.

A hypothetical path with exactly one Acquisition Planning, Candidate
Evaluation, and Semantic Event Resolution receipt is approximately **14,979
tokens**. If one surviving item also needs semantic Living Topic routing and
causes one topic understanding refresh, the observed add-on is approximately
**3,853 tokens**, for **18,832 tokens** across one invocation of each measured
stage. AI Deep Detection is excluded because the retained window has no
receipt-bearing invocation from which to calculate an average.

Living Topic routing and understanding are event-driven rather than mandatory
per check. A deterministic routing decision costs zero provider tokens, and one
coalesced understanding refresh may cover several evidence changes. Dividing
their new, short-lived telemetry by every historical session would therefore be
misleading.

## Cost and evidence semantics

- Token usage is not billed cost. Monetary cost depends on the provider, model,
  reasoning option, cache policy, and price effective when the call runs.
- Failed invocations remain in the ledger when the provider reported usage;
  failure does not imply zero cost.
- Missing usage is `unavailable`, never zero. Database reset, retention expiry,
  or storage trimming can narrow the available history.
- Aggregate Model Usage is local AkuBrowser history, not account-wide provider
  usage.
- Library Search, Personal Memory storage and lifecycle actions, deterministic
  Related Context, deterministic topic routing, AI Fast Detection, and local
  C2PA inspection add no model invocation.
- Bookmark Import and Management is outside the implemented pipeline and must
  receive its own cost contract before it can add any model-backed work.

## Optimization order

Candidate Evaluation accounted for about 74.5% of the measured in-run tokens,
Semantic Event Resolution about 24.5%, and Acquisition Planning about 1.0%.
Future cost work should therefore first reduce repeated or oversized Candidate
Evaluation evidence without weakening one-assessment-per-candidate coverage,
then improve high-precision local semantic bypasses. Acquisition Planning is
already a small share and should not be optimized by making ambiguous capture
decisions less truthful.

The live source of truth remains AkuSidecar's existing usage ledgers and the
`GET /api/model-usage?windowDays=7|30|90` projection. Update this dated baseline
only from a retained receipt readback; do not estimate missing counters from
prompt length or rewrite unknown values as zero.
