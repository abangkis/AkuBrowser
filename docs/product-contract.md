# AkuBrowser product contract

Status: canonical product boundary, 17 July 2026.

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

Preference cannot suppress an evidence-qualified contradiction, material update, highly urgent update, or highly novel update. Exact previously delivered evidence from the same source is always excluded before cross-source event grouping.

Direct labels generalize primarily through specific normalized topic tags. Broad topic facets remain a weaker fallback so a correction about one narrow subject does not automatically suppress an entire category such as developer tools or career information.

One neutral, evidence-qualified discovery candidate is retained per source when available and when doing so does not displace a protected update. This prevents the personalized Timeline from becoming a closed filter bubble.

The alternative Settings modes remain available without changing the Settings surface:

- `rank_only` changes ordering inside generic eligibility;
- `promote_unused_budget` may promote only into unused capacity;
- `guarded_live` provides the high-authority behavior above.

## Cross-source semantic events

A semantic event is one specific occurrence, not a broad topic: an actor performs an action or enters a state involving an object in a compatible time window. For example, several authors reporting the same product launch are separate reports of one event; a later capability release, contradiction, or consequence is unique information even when it belongs to that event thread.

After all source runs finish, a separate Event Engine compares the selected reports with a bounded local event index. High-precision deterministic retrieval removes URL, platform, and generic-language noise before producing one global shortlist. When there is neither a historical shortlist nor a strong intra-check match, Go takes a local fast path and creates independent event threads without spending another model call. Otherwise, the App Server resolver may classify reports as `new_event`, `duplicate_report`, `material_update`, `contradiction`, `new_consequence`, or `context_only`. Only a `duplicate_report` that reaches the automatic merge confidence threshold may merge. The default is `0.92`; Settings permits deliberate tuning from `0.85` to `0.95` in `0.01` steps. Every other relation consumes unique Timeline capacity.

Settings expose three explicit display contracts:

- `collapse` is the default: a duplicate remains visible as a quiet summary that the user can expand;
- `show_all` displays every report normally and bypasses semantic retrieval and resolution for new checks;
- `hide` omits duplicate reports while retaining the relationship locally.

The resolver shortlist maximum is a locked choice of 5, 10, or 15 retained event threads; the default is 10. The automatic merge confidence control is disabled with the shortlist when `Show all reports` turns the engine off. Event memory is trimmed when either paired boundary is reached: retention is 30, 60, or 90 days, and total local SQLite storage is 100, 200, 300, 400, 500 MB, or 1 GB. Defaults are 30 days and 100 MB.

Users may split a false merge with `Not the same event`, attach a report to one of at most three suggested event threads with `Same event`, and undo the latest correction. These direct corrections create deterministic local constraints for future checks; they do not require a permanent Codex conversation or expose stable database identities to the model.

## Unified Timeline

The Timeline header reports unique additions and duplicate-report count from the latest completed or partial check instead of repeating the configured retention capacity. When older retained items follow the newest additions, their first existing batch marker doubles as the single quiet history boundary. Its default 36 px spacing is user-adjustable from 16 to 80 px in Settings and can be reset without changing other Timeline preferences. By default, during downward scrolling the back-to-top control may align with each visible older-batch marker as a secondary cue; it returns smoothly to rest when the marker leaves view and does not chase markers during upward scrolling. Users may disable this boundary-follow cue without disabling the ordinary back-to-top control. The return animation defaults to 350 ms, is adjustable from 100 to 1000 ms on the same Settings row, and has an independent reset-to-default action.

X and LinkedIn are captured as child runs of one session. After all active sources reach a terminal state, AkuSidecar builds one global personalized order. A diversity guard prevents more than two consecutive items from one source while another source still has an item available. This is not strict round-robin: relevance remains primary and source diversity is a guardrail.

A partial session retains validated results from the source that completed and names the failed source. Update Inbox exposes captured, evaluated, selected, unique, and duplicate-report counts; whether semantic resolution used the local fast path or App Server; trigger reason, strongest overlap, and retained-event count; capture rounds; snapshots; scrolls; reasoning time; and follow-up failure. A completed session with no additions explicitly reports that outcome.

## Feedback semantics

- More is full-strength positive preference evidence.
- Less without a reason is negative preference evidence with reduced weight.
- Less like this is one direct, full-strength Not interested signal; it has no secondary reason menu.
- Freshness, prior knowledge, and cross-author duplication are handled by the evidence and semantic-event contracts instead of being mixed into preference feedback.
- When a captured post reports unavailable media, Recapture performs one item-scoped browser recovery and updates only that post's local evidence. It is not a new feed check and cannot add or rerank Timeline items.
- The latest signal for the same source/evidence identity replaces earlier labels during fitting.

All learning stays local and rebuildable from canonical feedback.

## Non-goals

AkuBrowser does not like, post, reply, follow, message, or mutate a source account. It does not optimize for session length, hide capture limitations, guarantee that a bounded sample contains every important post, or preserve compatibility with the retired Node Sidecar.
