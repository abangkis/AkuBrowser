# Quiet capture focus policy monitoring

AkuBridge is 0.9.2; the installed app and Sidecar remain 0.9.1. The new tuple is Chrome 0.9.2.0,
runtime source-adapters-v111, policy quiet-containment-only-v2.
Source changes do not establish that a running worker has loaded this tuple.

Background capture never foregrounds a previous window or tab as focus repair.
It keeps a non-focused rendering window where possible, and minimizes only its
managed capture surface when containment is needed. An explicit foreground
recapture gets one focus write; completion returns to containment, never a
previous-window restoration. Native-reader user actions retain their own policy.

Minimizing can throttle Chromium rendering or change source hydration. Passing
unit tests establishes policy boundaries, not live capture quality or speed parity.
Do not silently compensate with foreground activation. Existing readiness,
bounded retries, capture_empty diagnostics, candidate counts, capture quality,
and run stage durations remain the evidence for these outcomes.

## Forward-only comparison

Use existing Inbox run receipts from GET /api/inbox. Join each run's
captureSurface events with its stageDurationsMs, candidateDiagnostics, status,
summary/error, and existing capture-quality/empty-capture evidence. Lifecycle
detail now carries:

- focusPolicyRevision and focusPolicyMode (background_containment_only or explicit_user_foreground);
- focusedWriteAttempted (an API request, not proof of actual OS activation);
- restorationSuppressed (background policy prohibits snapshot restoration);
- containmentApplied (a minimize request was needed), plus verified contained/preserved outcomes on interventions.

Segment by policy revision, source, capture mode, explicit foreground use,
containment, and comparable load/settings. Compare capture duration distributions,
candidate yield, empty/degraded/error rates, readiness failures, and intervention
frequency. Keep missing historical tags unknown; never backfill them as zero.
Do not mix explicit foreground runs into background quality comparisons.

The September 20 pre-v110 sample is too small to claim statistical parity.
Inspect the first completed runs per source and continue comparing forward
samples; flag meaningful repeated yield/readiness regressions or increased
latency before changing budgets or rendering behavior. No automatic monitoring
job, production restart, extension reload, or historical replay is installed by
this change. Inbox's existing collapsed Capture surface detail shows revision
and containment so this evidence is inspectable without adding per-run noise.

Development runtime/build drift remains distinct from compatibility. A drift
warning provides user-requested Reload; claimed captures block that control.
Success requires an expected-build heartbeat and a compatible, exact identity
readback. Rendering status never triggers reload automatically.
