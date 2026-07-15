# Paired Model Replay Contract v1

> Status: **Implemented as an explicit local diagnostic**

Paired Model Replay compares candidate-evaluation profiles over identical,
already persisted browser observations. Version 1 evaluates Terra High, Luna
High, and Luna XHigh sequentially. It uses the production reasoning-result,
observed-source, complete-candidate-assessment, platform-order, and Selection
Engine contracts for every invocation.

## Authority boundary

- Only an explicit local CLI command may invoke models.
- Opening Review and `GET /api/reasoning/model-pairing` are read-only.
- Replay must not capture a source, mutate a run, Timeline eligibility,
  preference feedback, preference snapshots, acquisition planning, or runtime
  model Settings.
- The persisted report is summary-only: run identity, source, contract result,
  selections, assessments, feedback agreement, latency, and token telemetry.
  Raw observation text is not copied into the report.
- A partial or failed profile remains visible and cannot be recommended as if
  it completed the paired cohort.

## Comparable cohort

Cases come from completed runs with stored observations. Routine directional
feedback is prioritized and sources are alternated when both are available.
Every profile receives the same in-memory observation object and an empty
knowledge checkpoint so that model and effort are the intended variables.
Acquisition planning is outside this experiment.

## Quality and recommendation

The report includes feedback agreement, selection rate, selected assessment
means, pairwise selection agreement, failures, latency, and token totals. A
routing recommendation is `insufficient`, `provisional`, or `supported` from
the size of the exact paired cohort and its routine feedback. Within a cost
scenario, the recommended profile must have no failures and remain within five
percentage points of the best paired feedback agreement. The recommendation is
advisory and cannot update production routing.

## Cost contract

Token telemetry is not currency. Version 1 uses observed input plus output
tokens as a transparent blended unit and retains cached-input and
reasoning-output subtotals for inspection. Terra's relative blended rate is
1.0. Each configured Luna rate is a sensitivity hypothesis. For a candidate
profile:

`break-even relative rate = Terra observed units / candidate observed units`

The candidate is cheaper than Terra only when its actual blended rate ratio is
below that break-even value. Exact monetary cost requires an external,
versioned price contract and is deliberately not inferred by this diagnostic.

Run with:

```powershell
node scripts/benchmark-model-pairing.mjs --cases 4 --luna-rate 0.25 --luna-rate 0.50
```
