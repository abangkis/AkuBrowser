# AkuBrowser product contract

Status: canonical product boundary, 17 July 2026.

## Promise

AkuBrowser gives the user a finite answer to “what changed?” across selected social sources. It inspects a bounded capture, explains source-backed updates, counts unique information rather than repeated posts, learns from direct corrections, and stops. It does not reproduce an infinite feed and it does not claim comprehensive coverage.

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

Reset learning removes calibration, More/Less feedback, and the fitted profile. Historical selection corrections and their restored Timeline items remain auditable, but corrections older than the reset boundary no longer train the rebuilt profile. Full reset first creates a verified SQLite backup, then clears Timeline, runs, learning, onboarding, and settings while preserving the Bridge identity.

## Selection and personalization

Every reconciled candidate that passes Bridge and Sidecar quality admission is evaluated. Captured blocks that remain invalid after the bounded recovery path are diagnosed but do not enter reasoning. The generic base score is:

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

## Cross-author semantic attention engine

The semantic layer treats an event—not a post—as the unit of unique Timeline capacity. A semantic event is one specific occurrence, not a broad topic: an actor performs an action or enters a state involving an object in a compatible time window. For example, several authors reporting the same product launch are separate reports of one event; a later capability release, contradiction, or consequence is unique information even when it belongs to that event thread.

This is an attention contract, not only a deduplication optimization. Repeated reporting may remain available as provenance, but it should not force the user to reread the same change or consume capacity intended for new information.

After all source runs finish, a separate Event Engine compares the selected reports with a bounded local event index. High-precision deterministic retrieval removes URL, platform, and generic-language noise before producing one global shortlist. When there is neither a historical shortlist nor a strong intra-check match, Go takes a local fast path and creates independent event threads without spending another model call. Otherwise, the App Server resolver may classify reports as `new_event`, `duplicate_report`, `material_update`, `contradiction`, `new_consequence`, or `context_only`. Only a `duplicate_report` that reaches the automatic merge confidence threshold may merge. The default is `0.92`; Settings permits deliberate tuning from `0.85` to `0.95` in `0.01` steps. Every other relation consumes unique Timeline capacity.

Settings expose three explicit display contracts:

- `collapse` is the default: a duplicate remains visible as a quiet summary that the user can expand;
- `show_all` displays every report normally and bypasses semantic retrieval and resolution for new checks;
- `hide` omits duplicate reports while retaining the relationship locally.

The resolver shortlist maximum is a locked choice of 5, 10, or 15 retained event threads; the default is 10. The automatic merge confidence control is disabled with the shortlist when `Show all reports` turns the engine off. Event memory is trimmed when either paired boundary is reached: retention is 30, 60, or 90 days, and total local SQLite storage is 100, 200, 300, 400, 500 MB, or 1 GB. Defaults are 30 days and 100 MB.

Users may split a false merge with `Not the same event`, attach a report to one of at most three suggested event threads with `Same event`, and undo the latest correction. These direct corrections create deterministic local constraints for future checks; they do not require a permanent Codex conversation or expose stable database identities to the model.

## AI origin signals

AI Detector is a presentation and user-control layer, not an authorship oracle. It records evidence-bounded `AI origin signals`; it never changes candidate selection, personalized ranking, semantic-event membership, or unique Timeline capacity. The first implemented surface is authored text. Image and video assessment remain future extensions and must not be implied by a text result.

Detection has two independent stages:

- **Fast Detection** runs locally and deterministically after final global composition. It recognizes only explicit, auditable evidence such as a platform AI label, an author declaration about the post text itself, or prompt/instruction residue. A disclosure that AI created an image, video, website, code, design, paper, or other artifact is not text-post authorship evidence. Style alone—polished prose, lists, regular grammar, or generic wording—is never sufficient. A strong Fast result is marked Preliminary and is not Hide-eligible unless the evidence is a direct platform label or verified provenance.
- **Deep Detection** starts asynchronously only after the finite Timeline is available. Its separate schema-bound App Server adapter reviews only eligible retained posts as untrusted evidence and may confirm, dispute, or correct the Fast result. Every result explicitly assesses the social post and names whether the detected signal belongs to that post, quoted content, attached media, an external artifact, no object, or mixed evidence. `strong_signals` is invalid unless the signal belongs to the social post itself. A deterministic postcondition independently verifies any proposed strong evidence against captured source fields before it can receive presentation, Drawer, or Hide authority; model-assigned scope is not trusted by itself. Strong results from an older detector contract lose that authority and remain visible as a corrected assessment until a current result or direct user correction supersedes them. Inadequate text, direct platform/provenance evidence, and active user corrections do not spend another model call because the same captured evidence cannot responsibly improve those outcomes. If Deep Detection overturns an earlier strong assessment, the badge remains visible as a correction instead of silently disappearing. Failure degrades to the local Fast result and never blocks Timeline delivery.

Labels name the evidence rather than using the ambiguous blanket term “AI disclosed”: for example `Platform AI label`, `Author-declared AI · Preliminary`, `AI signals confirmed`, or `AI assessment corrected`. The user's `Mark as AI-generated` or `Mark as not AI-generated` correction has the highest personal presentation authority and can be cleared to reveal the resolved detector history again.

Settings expose three locked presentation modes:

- `drawer` is the preview default and routes unseen strong-signal posts into the generic side-pane host, while a post already seen inline does not disappear abruptly when an asynchronous result arrives;
- `inline` leaves every retained post in the Timeline with one compact expandable AI-signal control. Posts without a strong assessment use a quiet `AI signal · Neutral` state rather than claiming they are definitely human-authored;
- `hide` is a high-risk mode protected by warnings and the exact typed phrase `HIDE STRONG AI SIGNALS`. It hides only direct-origin evidence, Deep-confirmed strong signals, or posts explicitly marked AI by the user. Preliminary inferred signals are never hidden. Items remain stored locally and reappear when Hide is disabled.

The side pane is a generic Timeline alternate-view host. AI Detector supplies the first `AI Signals` pane, but does not own the underlying UI primitive. On wide layouts the unbounded edge of its closed tab and the open edge of its pane attach directly to the left edge of the active Timeline stream rather than floating at the viewport edge. Both the closed tab and open pane derive their vertical anchor from the first Timeline card below the latest `Checked` divider, then inset that anchor by the card's actual top-left radius so the attachment begins where the card edge is straight. This alignment remains live while the progress panel changes the Timeline layout. The pane grows upward as that card scrolls toward the viewport inset, then remains bounded and floating at its maximum viewport height. Opening it fully hides the closed tab so no control leaks around the pane edge. Narrower layouts retain the bounded overlay treatment.

Source attachments are also generic presentation evidence. LinkedIn currently
maps native job cards and external link previews into bounded `job` or
`link_preview` records; the Timeline renderer owns their common card UI.
Attachments are not gallery media, so an external logo or AI-created artifact
cannot silently inherit the provenance scope of the authored post. Attachment
destinations and thumbnails must use HTTPS. A source card that exposes only an
insecure target is omitted as presentation evidence without discarding the
otherwise valid captured post.

AI status, detector detail, and user correction are one UI family and therefore share the same badge slot at the start of the card toolbar. Clicking that control reveals `Mark as AI-generated` and `Mark as not AI-generated`, or `Clear my correction` after a personal override. Detector transitions—neutral, preliminary, confirmed, disputed, corrected, or user-overridden—change the badge state without moving the actions elsewhere. The card footer remains reserved for source access, More/Less preference feedback, and semantic-event correction.

## Unified Timeline

The Timeline header reports unique additions and duplicate-report count from the latest completed or partial check instead of repeating the configured retention capacity. When older retained items follow the newest additions, their first existing batch marker doubles as the single quiet history boundary. Its default 36 px spacing is user-adjustable from 16 to 80 px in Settings and can be reset without changing other Timeline preferences. By default, during downward scrolling the back-to-top control may align with each visible older-batch marker as a secondary cue; it returns smoothly to rest when the marker leaves view and does not chase markers during upward scrolling. Users may disable this boundary-follow cue without disabling the ordinary back-to-top control. The return animation defaults to 350 ms, is adjustable from 100 to 1000 ms on the same Settings row, and has an independent reset-to-default action.

Every active registered source is captured as a child run of one session. After all active sources reach a terminal state, AkuSidecar builds one global personalized order. A diversity guard prevents more than two consecutive items from one source while another source still has an item available. This is not strict round-robin: relevance remains primary and source diversity is a guardrail.

A partial session retains validated results from the source that completed and names the failed source. Update Inbox exposes captured, evaluated, selected, unique, and duplicate-report counts; whether semantic resolution used the local fast path or App Server; trigger reason, strongest overlap, retained-event count, and post-hoc user split/merge counts; Deep Detection status, reviewed-post count, duration, token usage, and safe degradation; capture rounds; snapshots; scrolls; reasoning time; and follow-up failure. It also lists the More/Less decisions made on retained Timeline items, so a mistaken choice can be replaced after the item has left the visible Timeline. A lazy Inspect flow action on each source run derives one row per canonical evidence identity from already-durable data and lets an interested user inspect Captured, Evaluated, Selected, and Added paths in bounded pages. Each row contains only a compact excerpt, provenance link, outcome, and one-line rationale; repeated or late-identified snapshots are reconciled exactly as they are before reasoning, while a selected semantic duplicate is explicitly identified and does not consume unique-addition capacity. The ordinary Inbox response does not carry these rows, raw observations, prompts, media, or heavy telemetry. A completed session with no additions explicitly reports that outcome.

An evaluated candidate that was not automatically selected exposes `Should have selected`. Choosing it immediately restores that candidate to the current Timeline and records an append-only, undoable selection correction. Explicit restoration may exceed the automatic per-source allocation for that check, but the visible Timeline remains subject to its retained-capacity boundary. The restored item then passes through item-scoped semantic-event resolution, knowledge continuity, AI Fast Detection, and asynchronous AI Deep Detection; a true semantic duplicate stays capacity-free as unique information. Captured-only evidence cannot be promoted around reasoning. If reasoning failed after capture, `Re-evaluate run` reuses the durable observation without opening the browser or capturing again. If the evidence itself is incomplete, the existing Recapture contract remains the recovery path.

## Feedback semantics

- More is full-strength positive preference evidence.
- Less like this is one direct, full-strength Not interested signal; it has no secondary reason menu.
- `Should have selected` is a stronger positive correction because it fixes both a missed outcome and the user's taste model. It is undoable, and its restored Timeline item is removed on undo.
- Freshness, prior knowledge, and cross-author duplication are handled by the evidence and semantic-event contracts instead of being mixed into preference feedback.
- When an X post reports unavailable media, it may remain usable-degraded and gain media later from AkuBridge's short-lived, allowlisted evidence cache. Quiet v57 runs established that X can expose media roots without hydrating either a media container or URL in the hidden DOM, so the current v60 runtime may also observe only X's already-requested `HomeTimeline`, `HomeLatestTimeline`, and `TweetDetail` responses. The response is inspected transiently; raw payloads and text never cross worlds or persist. Only the same native post identity and allowlisted media metadata with `x_response_graphql` provenance can enter passive enrichment. This path makes no provider request, opens or focuses no tab, and cannot add, select, rerank, regroup, or spend Timeline capacity. If no passive evidence appears, Recapture performs one quiet, item-scoped browser acquisition and updates only that post's local evidence. The shared engine exhausts primary DOM, source-exposed structured state, one bounded background hydration reread, and adapter alternate DOM before foreground is eligible. If the background attempt still cannot hydrate the media, the UI quietly offers one explicit foreground attempt; declining it has no side effect, accepting it does not change the persisted Quiet setting, and AkuBrowser restores the prior working surface unless the user intentionally moved elsewhere.
- The latest event across More, Less, calibration, and selection correction for the same source/evidence identity is authoritative during fitting. A later More or Less choice can therefore correct the taste signal created by `Should have selected` without rewriting the historical selection audit. Update Inbox exposes exactly More and Less for ordinary preference replacement; it does not provide a separate neutral state.

All learning stays local and rebuildable from canonical feedback.

The detailed data flow, feature lifecycle, authority resolution, fitting weights, and persisted-model boundary are specified in `preference-learning-contract.md`.

## Non-goals

AkuBrowser does not like, post, reply, follow, message, or mutate a source account. It does not optimize for session length, hide capture limitations, guarantee that a bounded sample contains every important post, or preserve compatibility with the retired Node Sidecar.
