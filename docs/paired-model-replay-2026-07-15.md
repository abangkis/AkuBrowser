# Paired Model Replay - 2026-07-15

> Status: **Provisional evidence; no production routing mutation**

AkuSidecar 0.6.11 evaluated Terra High, Luna High, and Luna XHigh sequentially
over the same four persisted observations: two X runs and two LinkedIn runs,
18 canonical candidates total, with two routine More and two routine Less
signals. All 12 invocations completed and passed the production reasoning and
selection contracts.

| Profile | Feedback agreement | Selected | Average latency | Input | Output | Reasoning output |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Terra High | 4/4 (100%) | 10/18 (55.6%) | 43.20 s | 91,400 | 6,787 | 732 |
| Luna High | 3/4 (75%) | 13/18 (72.2%) | 43.27 s | 89,326 | 7,569 | 1,739 |
| Luna XHigh | 3/4 (75%) | 13/18 (72.2%) | 48.49 s | 83,650 | 9,124 | 3,362 |

Luna High and Luna XHigh had 100% pairwise selection agreement. Both were more
permissive than Terra and missed one of the two negative expectations. XHigh
added about 12% latency and substantially more output/reasoning tokens without
changing a decision, so this cohort provides no reason to prefer XHigh over
High. Terra is the only profile inside the strict five-percentage-point quality
band, but four feedback comparisons are only provisional evidence.

## Relative cost sensitivity

The diagnostic has no versioned monetary price contract. It therefore treats
Terra's observed blended token rate as 1.0 and reports hypotheses for Luna's
relative blended rate. Observed units are input plus output tokens; cached input
and reasoning-output subtotals remain separately visible.

| Assumed Luna blended rate | Luna High saving vs Terra | Luna XHigh saving vs Terra |
| ---: | ---: | ---: |
| 0.25x Terra | 75.3% | 76.4% |
| 0.50x Terra | 50.7% | 52.8% |
| 0.75x Terra | 26.0% | 29.1% |

The blended break-even ratio is 1.013x for Luna High and 1.058x for Luna
XHigh because both used slightly fewer total input-plus-output units in this
cohort. This is not an exact invoice estimate: input, cached input, and output
can have different prices. Supply an actual rate ratio to the runner when a
versioned rate card is available.

## Current interpretation

- Keep the result advisory; do not rewrite production Settings automatically.
- Luna High is the stronger cost-oriented Luna candidate because XHigh produced
  the same decisions with worse latency and more output reasoning.
- Terra currently has the stronger negative-control behavior. Expand the exact
  paired cohort before deciding whether Luna High's cost advantage outweighs
  its observed over-inclusion.
- Acquisition planning was not evaluated and remains a separate phase-level
  routing decision.
