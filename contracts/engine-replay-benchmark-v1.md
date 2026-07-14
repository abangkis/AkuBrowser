# Engine Replay Benchmark Contract v1

> Status: **Implemented as a local, read-only diagnostic**

The benchmark replays persisted assessments, preference signals, selection
decisions, and reasoning telemetry. It never performs a model call and never
mutates the database.

It reports dataset/polarity balance; agreement, balanced accuracy, positive and
negative recall; source-sliced bias checks; selection rate and reason counts;
and latency/token aggregates by phase, provider, model, and effort.

Use `GET /api/preferences/benchmark` or `npm run benchmark:engine` while
AkuSidecar is running. Model/effort comparisons remain observational hooks
until a stable objective and comparable replay cohort exist.

