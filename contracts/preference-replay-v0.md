# Preference Replay Contract v0

> Status: **Offline calibration implemented; live influence disabled**
> Date: **2026-07-11**

## Purpose

Preference Replay evaluates whether append-only user signals and structured candidate assessments are sufficient to fit an experimental preference model. It is read-only analysis: it cannot change candidate eligibility, ranking, attention budgets, comeback behavior, or Unified View presentation.

## Inputs

- persisted candidate evaluations;
- structured candidate assessments produced during the original evaluation invocation;
- append-only `more_like_this` and `less_like_this` events;
- run and source identity.

A signal without a matching candidate remains auditable but cannot contribute assessed feature tendencies. Retired development-only signal kinds are deleted rather than interpreted by replay.

## Readiness gates

Offline fitting requires every gate:

- 30 feedback events;
- 15 `more_like_this` signals;
- 5 `less_like_this` signals;
- 20 feedback events matched to structured assessments;
- feedback across 10 runs.

Passing these gates permits only the hard-gated Offline Preference Experiment v0 fit/evaluation. Live activation requires a later decision and comparative evidence against the current selector.

## Output

`GET /api/preferences/replay` returns:

- readiness status and gate progress;
- dataset coverage and polarity counts;
- source, selected/excluded, matched, and assessed coverage;
- descriptive content-type and topic-tag tendencies;
- average assessment dimensions by positive or negative polarity;
- explicit limitations; and
- `liveInfluence: false`.

The replay report performs no model call and records no inferred preference event.
