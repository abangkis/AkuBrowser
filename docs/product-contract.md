# AkuBrowser product contract

Status: canonical product boundary, 27 July 2026.

> **Distribution routing:** product behavior remains canonical here, while the
> approved installed-app first-run, isolated profile, permission broker, and
> launcher boundaries are defined in the [installed-app distribution contract](installed-app-distribution-contract.md).
> The distribution target is approved but not implemented yet.

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

1. The user chooses among the registered X, LinkedIn, Facebook, and Instagram sources. All registered sources are preselected for a new setup and remain independently configurable.
2. Once at least one selected source is ready, the user selects the reasoning provider before the first bounded capture: Codex App Server is the default and most compliant option, Gemini requires a free Google key and discloses that captured post text is processed by Google, and local Ollama models keep reasoning on the machine. A provider whose credential is missing shows setup guidance instead of a dead end. The selection applies immediately; the first update always runs on the chosen provider.
3. AkuBrowser performs one bounded capture to obtain real candidates.
4. Before the Timeline opens, the user calibrates a source-balanced sample with More, Neutral, Less, or a capture issue.
5. The local profile becomes active when repeated directional evidence is sufficient.
6. Later checks go directly to the finite Timeline and Update Inbox.

Later updates may also be prepared by Auto Update while AkuSidecar is running.
Prepared batches remain outside the Timeline until explicitly opened, or until
the bounded finish-line auto-load policy reveals a batch that existed when the
reading session began. Queue, freshness, and local model-budget limits prevent
this from becoming an endless background feed. See the reader-facing lifecycle
in [`auto-update-guide.md`](auto-update-guide.md) and its normative boundaries in
[`auto-update-contract.md`](auto-update-contract.md).

All entry points use one update pipeline. Each session records who triggered
it, whether selected items are immediately visible or remain prepared, and
whether it spends user-reserved or automatic budget. **Update now** remains
available in the Timeline whether Auto Update is enabled or disabled and
publishes directly. When prepared material is available, the header separately
offers **Load latest batch** and the finish line offers **Continue with next
batch**.

Reset learning removes calibration, More/Less feedback, and the fitted profile. Historical selection corrections and their restored Timeline items remain auditable, but corrections older than the reset boundary no longer train the rebuilt profile. Full reset first creates a verified SQLite backup, then clears Timeline, runs, learning, onboarding, settings, and native content-continuity history. It asks the Bridge to revoke every optional source host permission and unregister the source capture scripts, and reports honestly when that acknowledgement is unavailable. Full reset preserves the browser profile and its source login sessions; deleting that profile is a separate destructive operation, not part of product reset. The reasoning runtime and persisted settings return together to the configured default provider. The result is a clean AkuBrowser database and capture-permission surface without forcing the user to sign in to every source again. The Bridge identity remains valid throughout.

## Selection and personalization

Every reconciled candidate that passes Bridge and Sidecar quality admission is evaluated. Admission is evidence-based rather than caption-length-based: an identified source post may carry text, image, video, typed attachment, or quoted-post evidence. This keeps text-heavy X/LinkedIn entries and media-heavy Facebook or future Instagram/TikTok entries behind the same core invariant. Adapters declare what they can extract; they never decide relevance or selection. Captured blocks that remain invalid after the bounded recovery path are diagnosed but do not enter reasoning. The generic base score is:

`0.40 materiality + 0.20 novelty + 0.15 actionability + 0.10 urgency + 0.15 evidence strength`

Ordinary admission requires evidence strength of at least `0.35` and a base score of at least `0.40`. There is no “reliable fallback”: when nothing is genuinely new, material, and sufficiently supported, `0 additions` is the correct result.

The fresh default is `guarded_live`. Once direct-signal authority is ready, preference alignment contributes up to `±0.45`, enough to change admission and not merely decorate an existing order. It may:

- promote a trusted candidate that generic admission missed;
- replace a lower-value ordinary candidate inside the finite budget;
- demote or suppress an ordinary candidate with repeated negative evidence;
- reorder selected candidates globally across sources.

Preference cannot suppress an evidence-qualified contradiction, material update, highly urgent update, or highly novel update. Exact previously delivered evidence from the same source is always excluded before cross-source event grouping.

When the same source post first appears without a stable native identity and later reveals one, AkuBrowser may promote the fallback identity only when source, normalized author, and full normalized text match; short or missing text is not eligible. Exact publication time and content kind guard against a later repost. Relative timestamps marked as estimated are treated as unavailable and therefore use the bounded recovery window. A stable platform ID is authoritative over harmless permalink spelling or tracking-query differences; a canonical permalink remains authoritative when no platform ID is available. Two different valid native identities never merge merely because their author and text match.

Direct labels generalize primarily through specific normalized topic tags. Broad topic facets remain a weaker fallback so a correction about one narrow subject does not automatically suppress an entire category such as developer tools or career information.

One neutral, evidence-qualified discovery candidate is retained per source when available and when doing so does not displace a protected update. This prevents the personalized Timeline from becoming a closed filter bubble.

The alternative Settings modes remain available without changing the Settings surface:

- `rank_only` changes ordering inside generic eligibility;
- `promote_unused_budget` may promote only into unused capacity;
- `guarded_live` provides the high-authority behavior above.

## Cross-author semantic attention engine

The semantic layer treats an event—not a post—as the unit of unique Timeline capacity. A semantic event is one specific occurrence, not a broad topic: an actor performs an action or enters a state involving an object in a compatible time window. For example, several authors reporting the same product launch are separate reports of one event; a later capability release, contradiction, or consequence is unique information even when it belongs to that event thread.

This is an attention contract, not only a deduplication optimization. Repeated reporting may remain available as provenance, but it should not force the user to reread the same change or consume capacity intended for new information.

After all source runs finish, a separate Event Engine compares the selected reports with a bounded local event index. Re-observing the exact same opaque native evidence identity is resolved locally as `Already captured`; it is not presented as cross-author semantic similarity and does not spend another resolver call. High-precision deterministic retrieval removes URL, platform, and generic-language noise before producing one global shortlist for the remaining reports. When there is neither a historical shortlist nor a strong intra-check match, Go takes a local fast path and creates independent event threads without spending another model call. Otherwise, the App Server resolver may classify reports as `new_event`, `duplicate_report`, `material_update`, `contradiction`, `new_consequence`, or `context_only`. Only a `duplicate_report` that reaches the automatic merge confidence threshold may merge. The default is `0.92`; Settings permits deliberate tuning from `0.85` to `0.95` in `0.01` steps. Every other relation consumes unique Timeline capacity.

A safely promoted fallback-to-native identity belongs to this same native replay boundary. It is not a cross-author semantic merge, does not consume unique Timeline capacity again while unchanged inside cooldown, and does not require Event Engine inference.

Settings expose three explicit display contracts:

- `collapse` is the default: a duplicate remains visible as a quiet summary that the user can expand;
- `show_all` displays every report normally and bypasses semantic retrieval and resolution for new checks;
- `hide` omits duplicate reports while retaining the relationship locally.

The resolver shortlist maximum is a locked choice of 5, 10, or 15 retained event threads; the default is 10. The automatic merge confidence control is disabled with the shortlist when `Show all reports` turns the engine off. Event memory is trimmed when either paired boundary is reached: retention is 30, 60, or 90 days, and total local SQLite storage is 100, 200, 300, 400, 500 MB, or 1 GB. Defaults are 30 days and 100 MB.

Users may split a false merge with `Not the same event`, attach a report to one of at most three suggested event threads with `Same event`, and undo the latest correction. These direct corrections create deterministic local constraints for future checks; they do not require a permanent Codex conversation or expose stable database identities to the model.

## AI origin signals

AI Detector is a presentation and user-control layer, not an authorship oracle. It records evidence-bounded `AI origin signals`; it never changes candidate selection, personalized ranking, semantic-event membership, or unique Timeline capacity. Source adapters may emit a generic, bounded `presentation.originSignals` record with an explicit kind, object scope, platform authority, label, and source. A platform label attached to media remains `attached_media`; it cannot become a claim about the authored social post. `Content Credentials` alone records available provenance but is neutral about AI origin. Image provenance is a separate asynchronous contract: AkuSidecar may inspect an already captured image for an embedded C2PA manifest after the Timeline is usable. A C2PA result describes the attached image only and must never be promoted into a claim that the post caption or author is AI-generated. Video provenance is not implemented.

The first image-provenance adapter invokes local `c2patool` with remote manifest and OCSP fetching disabled. It downloads only HTTPS images from the source registry's media-host allowlist into a bounded temporary file, sniffs the image bytes before choosing the temporary file type, stores the verification result and SHA-256 identity, and deletes the bytes after inspection. A missing manifest is neutral. An invalid manifest is visible as failed provenance, not AI evidence. A valid manifest whose action declares `trainedAlgorithmicMedia` or `compositeWithTrainedAlgorithmicMedia` is a direct attached-media signal. Signing trust is retained separately so AkuBrowser can distinguish verified trusted provenance from a valid but not locally trusted declaration. Settings exposes whether the optional local verifier is ready.

Detection has two independent stages:

- **Fast Detection** runs locally and deterministically after final global composition. It recognizes only explicit, auditable evidence such as a platform AI label, an author declaration about the post text itself, or prompt/instruction residue. A disclosure that AI created an image, video, website, code, design, paper, or other artifact is not text-post authorship evidence. Style alone—polished prose, lists, regular grammar, or generic wording—is never sufficient. A strong Fast result is marked Preliminary and is not Hide-eligible unless the evidence is a direct platform label or verified provenance.
- **Deep Detection** starts asynchronously only after the finite Timeline is available. It is a bounded evidence reviewer, not a broad classifier: its separate schema-bound App Server adapter receives at most five retained posts per check. An explicit personal `Unsure` review request has first priority, followed by preliminary deterministic findings and explicit but phrasing-ambiguous authorship or agent-identity disclosures that Fast Detection deliberately did not label strong. Shortlisting is not evidence and writing style alone can never create a candidate. Inadequate text, direct platform/provenance evidence, ordinary neutral posts, and active personal AI/not-AI verdicts never spend a Deep model call. Each invocation carries only bounded authored and quoted evidence plus minimal Fast context; semantic-event state, durable IDs, and redundant detector fields stay local. Every result explicitly assesses the social post and names whether the detected signal belongs to that post, quoted content, attached media, an external artifact, no object, or mixed evidence. `strong_signals` is invalid unless the signal belongs to the social post itself. A deterministic postcondition independently verifies any proposed strong evidence against captured source fields before it can receive presentation, Drawer, or Hide authority; model-assigned scope is not trusted by itself. Strong results from an older detector contract lose that authority and remain visible as a corrected assessment until a current result or direct user feedback supersedes them. If Deep Detection overturns an earlier strong assessment, the badge remains visible as a correction instead of silently disappearing. Failure degrades to the local Fast result and never blocks Timeline delivery.

Each Update Inbox check includes a collapsed `AI Detector yield` receipt. It separates local Fast review, targeted Deep eligibility/review/skips, high-authority platform labels, and C2PA outcomes. This is local detector telemetry, not a claim that unflagged posts are human-authored.

The repository keeps a local, source-controlled AI review corpus with positive and negative controls. Its acceptance test reports shortlist true positives, false positives, true negatives, and false negatives without invoking a model. The corpus is a regression and contract harness, not a claim of real-world detector accuracy; production quality must still be measured from observed local receipts and voluntary user corrections.

Labels name the evidence rather than using the ambiguous blanket term “AI disclosed”: for example `Platform AI label`, `Author-declared AI · Preliminary`, `AI signals confirmed`, or `AI assessment corrected`. The user's object-scoped `Mark as AI-generated` or `Mark as not AI-generated` feedback has the highest personal presentation authority for that same object and can be cleared to reveal the resolved detector history again. `Unsure` requests one immediate bounded Deep review without asserting either verdict. Its pending badge remains until a newer Deep assessment is durable, after which presentation follows that assessment while the request remains inspectable in feedback history.

Settings expose three locked presentation modes:

- `drawer` is the preview default and routes strong-signal posts into the generic side-pane host. Inference-only results preserve an already-seen inline item, but direct C2PA AI-media provenance moves the item into the drawer even after publication because the attached image has crossed the configured secondary-content boundary;
- `inline` leaves every retained post in the Timeline with one compact expandable AI-signal control. Posts without a strong assessment use a quiet `AI signal · Neutral` state rather than claiming they are definitely human-authored;
- `hide` is a high-risk mode protected by warnings and the exact typed phrase `HIDE STRONG AI SIGNALS`. It hides only direct-origin evidence, Deep-confirmed strong signals, or posts explicitly marked AI by the user. Preliminary inferred signals are never hidden. Items remain stored locally and reappear when Hide is disabled.

When a direct C2PA image signal routes an item into the drawer, media-scoped `Mark as not AI-generated` is the user's highest personal presentation authority and restores the item to the Timeline. The provenance receipt remains inspectable rather than being deleted. A post-text correction cannot erase attached-media provenance. Clearing the media feedback restores system routing.

The side pane is a generic Timeline alternate-view host. AI Detector supplies the first `AI Signals` pane, but does not own the underlying UI primitive. On wide layouts the unbounded edge of its closed tab and the open edge of its pane attach directly to the left edge of the active Timeline stream rather than floating at the viewport edge. Both the closed tab and open pane derive their vertical anchor from the first Timeline card below the latest `Checked` divider, then inset that anchor by the card's actual top-left radius so the attachment begins where the card edge is straight. This alignment remains live while the progress panel changes the Timeline layout. The pane grows upward as that card scrolls toward the viewport inset, then remains bounded and floating at its maximum viewport height. Opening it fully hides the closed tab so no control leaks around the pane edge. Narrower layouts retain the bounded overlay treatment.

Source attachments are also generic presentation evidence. LinkedIn currently
maps native job cards and external link previews into bounded `job` or
`link_preview` records; the Timeline renderer owns their common card UI.
Attachments are not gallery media, so an external logo or AI-created artifact
cannot silently inherit the provenance scope of the authored post. Attachment
destinations and thumbnails must use HTTPS. A source card that exposes only an
insecure target is omitted as presentation evidence without discarding the
otherwise valid captured post.

Inline playback URLs are treated as ephemeral evidence rather than permanent
assets. A source may opt into `native_post_recapture`; LinkedIn and Facebook
currently do so. After an explicit play attempt fails, AkuBrowser falls back to
the native-post control and may queue one background recapture bound to that
Timeline item and its canonical post URL. The replacement is accepted only
when it contains a different allowlisted progressive playback URL. A failed
background attempt may offer the existing explicit foreground recapture, and
native-post access remains the terminal fallback.

AI status, detector detail, and personal AI feedback are one UI family and therefore share the same badge slot at the start of the card toolbar. The badge has a restrained interactive cue rather than competing with the card's primary actions. Clicking it reveals the assessment and presents `Mark as AI-generated`, `Mark as not AI-generated`, and `Unsure · Review more deeply` immediately; object scope and bounded reason remain available in a secondary optional disclosure and default to the social-post text. Both disclosure levels survive routine Timeline polling and rendering. Personal outcomes use distinct semantic tones: AI is amber, not-AI is green, and an unsure review request is blue pending. An explicit AI verdict bypasses the async-detector stability guard and moves an already-seen post into the configured Drawer or Hide presentation immediately; the guard only prevents late detector work from unexpectedly moving content the user is already reading. A clear action replaces the decision hierarchy after personal feedback. The canonical append-only AI Feedback Engine and its deterministic Personal AI Policy are defined in [ai-feedback-contract.md](ai-feedback-contract.md). Detector transitions—neutral, preliminary, confirmed, disputed, corrected, review-requested, or user-overridden—change the badge state without moving the actions elsewhere. The card footer remains reserved for source access, More/Less preference feedback, and semantic-event correction.

## Unified Timeline

The Timeline header reports unique additions and duplicate-report count from the latest completed or partial check instead of repeating the configured retention capacity. When older retained items follow the newest additions, their first existing batch marker doubles as the single quiet history boundary. Its default 36 px spacing is user-adjustable from 16 to 80 px in Settings and can be reset without changing other Timeline preferences. By default, during downward scrolling the back-to-top control may align with each visible older-batch marker as a secondary cue; it returns smoothly to rest when the marker leaves view and does not chase markers during upward scrolling. Users may disable this boundary-follow cue without disabling the ordinary back-to-top control. The return animation defaults to 350 ms, is adjustable from 100 to 1000 ms on the same Settings row, and has an independent reset-to-default action. In every primary view, including Library and Living Topics, the control anchors beside the active content panel when horizontal room exists and falls back to the viewport edge only on constrained layouts.

Follow-up planning is a source-declared capability behind one generic engine boundary. Facebook and LinkedIn may finish locally only after a completed scroll reports zero new candidates and no explicit `has more` signal. LinkedIn additionally requires complete, non-deadline-exhausted capture evidence. Ambiguous capture falls back to model planning, and a requested LinkedIn follow-up keeps the existing continuation-overlap rule. Native identity recovery is likewise source-generic: exact source, author, and full text must agree, while content kind and exact publication time prevent a later exact-text repost from being merged. Relative/estimated timestamps are treated as unavailable, and an unavailable exact timestamp permits only a 30-minute fallback-recovery window. This optimization changes neither source hydration nor the generic Bridge media-acquisition path. The frozen development baseline, cost boundaries, and acceptance matrix are recorded in [linkedin-adapter-cost-performance.md](linkedin-adapter-cost-performance.md).

Every active registered source is captured as a child run of one session. Progressive wait, the default, overlaps the next source's single-lane browser capture with earlier source reasoning; Full wait preserves fully serial source execution. The browser lane itself never captures two sources concurrently. The default single-window Quiet visibility policy shares one non-focused managed window across sources; experimental multi-window Quiet remains selectable for per-source isolation. Window isolation does not make browser capture concurrent. Every Bridge-created managed window or Adaptive tab remains in the managed-surface ledger until cleanup has a receipt. The ledger is reconciled on extension start/reload and before another lease takes ownership. A source may declare one bounded recovery for a newly created Bridge-owned surface, but recreation is allowed only after confirmed cleanup; it never extends foreground authority. Auto Update requests per-source cleanup immediately after that source closes Acquisition; its one-minute alarm remains a fallback. After all active sources reach a terminal state, AkuSidecar builds one global personalized order. A diversity guard prevents more than two consecutive items from one source while another source still has an item available. This is not strict round-robin: relevance remains primary and source diversity is a guardrail.

One collapsed `Acquisition & identity` receipt in Update Inbox identifies guarded local-frontier completion, model planning, or a continuity bypass that removed every unchanged native resurface before planning; it reports follow-up yield and counts native identity, fallback identity, alias reuse, promotion, conflict, and ambiguous fallback. It is derived from durable local evidence, exposes no raw post text, and consumes no additional model tokens.

A partial session retains validated results from the source that completed and names the failed source. A source that explicitly reports a temporary service outage is shown as unavailable with warning tone rather than as an adapter or reasoning failure. Update Inbox exposes captured, evaluated, selected, unique, and duplicate-report counts; a small execution duration in each source-stage box; source Total versus aggregate model time; resurface/skip counts; whether semantic resolution used the local fast path or App Server; trigger reason, strongest overlap, retained-event count, and post-hoc user split/merge counts; Deep Detection status, reviewed-post count, duration, and safe degradation; capture rounds; snapshots; scrolls; follow-up failure; and a collapsed capture-surface receipt listing created/reused, release requested, released, preserved as user-owned, reconciled, and focus-intervention events. Model-token accounting is consolidated into one lazy, collapsed section per check using the same four process categories as Settings. Each category names the profile actually recorded by its invocations; pending categories show the profile currently configured in Settings, a bypassed category states that no model was used, and historical aggregates explicitly identify mixed profiles. Its help control explains cached and reasoning breakouts, failed invocations, missing telemetry, and asynchronous Deep updates. A linked secondary view aggregates 7, 30, or 90 days of local AkuBrowser usage without claiming account-wide Codex usage. While a non-terminal run has durable captured evidence but evaluation has not returned, Inbox says `Evaluating...`; later run stages remain `Pending`, and the session summary says `composition pending`, instead of presenting transient zeros as final outcomes. It also provides a boxed, default-collapsed Personalization decisions section listing the More/Less decisions made on retained Timeline items, so a mistaken choice can be replaced after the item has left the visible Timeline without dominating the ordinary diagnostic view. During a full page reload, the Timeline stays in an explicit restoring state with its finish line hidden until bootstrap has restored both retained items and any active check; it never temporarily claims that setup is incomplete or that retained evidence is empty. A lazy Inspect flow action on each source run derives one row per canonical evidence identity from already-durable data and lets an interested user inspect Captured, Evaluated, Selected, and Added paths in bounded pages. Each row contains only a compact excerpt, provenance link, outcome, one-line rationale, and typed content-continuity badge when applicable. Cross-author semantic duplicates remain separate from native resurfaces. The ordinary Inbox response does not carry raw observations, prompts, media, or heavy telemetry. A completed session with no additions explicitly reports that outcome.

The aggregate Model Usage view extends the four per-check categories with
asynchronous Living Topic routing and understanding receipts. Library search,
Personal Memory storage, and deterministic Related Context remain local and add
no provider invocation. Schema-22 migration backfills retained published
understanding receipts; earlier semantic no-change and routing calls without a
durable receipt remain unknown rather than being reported as zero.
The complete model-call sequence, invocation conditions, dated token baseline,
and interpretation rules are maintained in the
[LLM Invocation and Token Cost Reference](llm-invocation-and-token-cost.md).

An ordinarily evaluated candidate that was not automatically selected exposes `Should have selected`. A typed `prior_knowledge_overlap` instead exposes `Select despite overlap`, so the user sees that the candidate repeated retained information before creating a high-authority correction. An unchanged native replay skipped before reasoning is labeled `Resurfaced · unchanged`, remains reviewable in Captured flow, and exposes no selection correction because it has no current evaluation to bypass. Its trusted native evidence link remains available whenever the adapter captured one, because fail-fast processing must not prevent a user from reviewing the original source. Choosing an available correction immediately restores that candidate to the current Timeline and records an append-only, undoable selection correction. Explicit restoration may exceed the automatic per-source allocation for that check, but the visible Timeline remains subject to its retained-capacity boundary. The restored item then passes through item-scoped semantic-event resolution and knowledge continuity; AI Fast and Deep Detection run only when the AI Detection master setting is enabled. If reasoning failed after capture, `Re-evaluate run` reuses the durable observation without opening the browser or capturing again. If the evidence itself is incomplete, the existing Recapture contract remains the recovery path.

## Feedback semantics

- More is full-strength positive preference evidence.
- Less like this is one direct, full-strength Not interested signal; it has no secondary reason menu.
- `Should have selected` is a stronger positive correction because it fixes both a missed outcome and the user's taste model. It is undoable, and its restored Timeline item is removed on undo.
- Freshness, prior knowledge, and cross-author duplication are handled by the evidence and semantic-event contracts instead of being mixed into preference feedback.
- When an X post reports unavailable media, it may remain usable-degraded and gain media later from AkuBridge's short-lived, allowlisted evidence cache. Quiet v57 runs established that X can expose media roots without hydrating either a media container or URL in the hidden DOM, so the current v60 runtime may also observe only X's already-requested `HomeTimeline`, `HomeLatestTimeline`, and `TweetDetail` responses. The response is inspected transiently; raw payloads and text never cross worlds or persist. Only the same native post identity and allowlisted media metadata with `x_response_graphql` provenance can enter passive enrichment. This path makes no provider request, opens or focuses no tab, and cannot add, select, rerank, regroup, or spend Timeline capacity. If no passive evidence appears, Recapture performs one quiet, item-scoped browser acquisition and updates only that post's local evidence. The shared engine exhausts primary DOM, source-exposed structured state, one bounded background hydration reread, and adapter alternate DOM before foreground is eligible. If the background attempt still cannot hydrate the media, the UI quietly offers one explicit foreground attempt; declining it has no side effect, accepting it does not change the persisted Quiet setting, and AkuBrowser restores the prior working surface unless the user intentionally moved elsewhere.
- A captured video may use its poster image as a bounded Timeline preview. An allowlisted progressive URL permits explicit, poster-first inline playback; otherwise the play cue opens the trusted native post. Only one inline video plays at a time, playback pauses when scrolled out of view, and active playback renews Presence-aware Auto Update activity. Video posters are excluded from the image zoom gallery. For ordinary captured images, Fit and Zoom are snap presets rather than locked modes: minus/plus, keyboard, and wheel/trackpad controls can still zoom in or out manually after either preset.
- The latest event across More, Less, calibration, and selection correction for the same source/evidence identity is authoritative during fitting. A later More or Less choice can therefore correct the taste signal created by `Should have selected` without rewriting the historical selection audit. Update Inbox projects calibration More/Less alongside later routine decisions and identifies their origin without creating duplicate feedback events; a later routine choice replaces that projection. Neutral calibration labels remain absent. Update Inbox exposes exactly More and Less for preference replacement; it does not provide a separate neutral state.

All learning stays local and rebuildable from canonical feedback.

The detailed data flow, feature lifecycle, authority resolution, fitting weights, and persisted-model boundary are specified in `preference-learning-contract.md`.

## Non-goals

AkuBrowser does not like, post, reply, follow, message, or mutate a source account. It does not optimize for session length, hide capture limitations, guarantee that a bounded sample contains every important post, or preserve compatibility with the retired Node Sidecar.
