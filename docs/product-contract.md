# AkuBrowser product contract

Status: canonical product boundary, 16 July 2026.

## Promise

AkuBrowser gives the user a finite answer to “what changed?” across selected social sources. It inspects a bounded capture, explains source-backed updates, learns from direct corrections, and stops. It does not reproduce an infinite feed and it does not claim comprehensive coverage.

## Authority order

The product resolves competing signals in this order:

1. hard trust and evidence protections;
2. the user's explicit More, Not interested, and calibration labels;
3. generic materiality, novelty, actionability, urgency, and evidence strength;
4. the source platform's order as a cold-start prior.

Social engagement is useful for discovery, but it is indirect behavioral inference. Direct feedback is intentional and therefore receives higher personalization authority.

## First-run experience

1. The user chooses X, LinkedIn, or both.
2. AkuBrowser performs one bounded capture to obtain real candidates.
3. Before the Timeline opens, the user calibrates a source-balanced sample with More, Neutral, Less, or a capture issue.
4. The local profile becomes active when repeated directional evidence is sufficient.
5. Later checks go directly to the finite Timeline and Update Inbox.

Reset learning removes calibration, feedback, and the fitted profile. Full reset first creates a verified SQLite backup, then clears Timeline, runs, learning, onboarding, and settings while preserving the Bridge identity.

## Selection and personalization

Every captured candidate is evaluated. The generic base score is:

`0.40 materiality + 0.20 novelty + 0.15 actionability + 0.10 urgency + 0.15 evidence strength`

Ordinary admission requires evidence strength of at least `0.35` and a base score of at least `0.40`. There is no “reliable fallback”: when nothing is genuinely new, material, and sufficiently supported, `0 additions` is the correct result.

The fresh default is `guarded_live`. Once direct-signal authority is ready, preference alignment contributes up to `±0.45`, enough to change admission and not merely decorate an existing order. It may:

- promote a trusted candidate that generic admission missed;
- replace a lower-value ordinary candidate inside the finite budget;
- demote or suppress an ordinary candidate with repeated negative evidence;
- reorder selected candidates globally across sources.

Preference cannot suppress an evidence-qualified contradiction, material update, highly urgent update, or highly novel update. Exact previously delivered evidence is always excluded. An existing semantic event is admitted again only as a material update or contradiction.

Direct labels generalize primarily through specific normalized topic tags. Broad topic facets remain a weaker fallback so a correction about one narrow subject does not automatically suppress an entire category such as developer tools or career information.

One neutral, evidence-qualified discovery candidate is retained per source when available and when doing so does not displace a protected update. This prevents the personalized Timeline from becoming a closed filter bubble.

The alternative Settings modes remain available without changing the Settings surface:

- `rank_only` changes ordering inside generic eligibility;
- `promote_unused_budget` may promote only into unused capacity;
- `guarded_live` provides the high-authority behavior above.

## Unified Timeline

The newest successful check remains first in the unified personalized order. When older retained items follow it, one quiet unlabeled rule marks the end of the newest additions without turning the Timeline into an attention-seeking unread-count surface.

X and LinkedIn are captured as child runs of one session. After all active sources reach a terminal state, AkuSidecar builds one global personalized order. A diversity guard prevents more than two consecutive items from one source while another source still has an item available. This is not strict round-robin: relevance remains primary and source diversity is a guardrail.

A partial session retains validated results from the source that completed and names the failed source. Update Inbox exposes captured, evaluated, selected, and added counts plus capture rounds, snapshots, scrolls, reasoning time, and follow-up failure. A completed session with no additions explicitly reports that outcome.

## Feedback semantics

- More is full-strength positive preference evidence.
- Less without a reason is negative preference evidence with reduced weight.
- Not interested is full-strength negative preference evidence.
- Already knew, Old info, and Duplicate are diagnostic corrections; they do not train topic dislike.
- The latest signal for the same source/evidence identity replaces earlier labels during fitting.

All learning stays local and rebuildable from canonical feedback.

## Non-goals

AkuBrowser does not like, post, reply, follow, message, or mutate a source account. It does not optimize for session length, hide capture limitations, guarantee that a bounded sample contains every important post, or preserve compatibility with the retired Node Sidecar.
