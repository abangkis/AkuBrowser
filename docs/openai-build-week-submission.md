# AkuBrowser — a finite, user-steered layer over infinite feeds

## Inspiration

Social feeds are excellent discovery engines, but their success metric is usually more consumption. I wanted the opposite experience: ask “what changed?”, inspect a bounded amount of source evidence, keep what is genuinely useful, and reach a visible end.

There is also a quieter attention tax inside every feed: the same occurrence is repeated by many accounts, often with different wording and on different platforms. A product launch reported by five authors is useful evidence, but it should not cost five full reads. That led to one of AkuBrowser's defining ideas: the event, not the post, should be the unit of attention.

The second insight was about personalization. A platform infers preference from pauses, clicks, and engagement collected behind the scenes. AkuBrowser can ask directly. When a user says More or Not interested, that intentional correction should carry more authority than an opaque behavioral proxy—without letting preference override evidence quality or trap the user inside a filter bubble.

A third question emerged while reading: how much of the conversation was created or amplified by AI? Hiding uncertain content by default would simply replace one opaque algorithm with another. The more useful product direction was to expose bounded AI origin signals, let the user decide where those posts belong, and make every detector correction visible.

The same attention principle applies to browser acquisition. A missing image
should not force the product to interrupt the user or hold back an otherwise
useful Timeline. Evidence can arrive in layers: deliver the bounded text first,
then complete the matching media quietly if the source exposes it later.

## What it does

AkuBrowser captures a bounded slice of the user's chosen signed-in feeds through a read-only Chrome extension. The current source registry supports X, LinkedIn, and Facebook. A local Go application quality-admits and reconciles the capture, evaluates each admitted candidate with structured Codex output, removes repeated evidence, groups cross-author and cross-source reports of the same specific event, and builds one finite Timeline.

The cross-author semantic Event Engine is the feature that changed the value of the product for me. It distinguishes a repeated report from a material update, contradiction, consequence, or additional context. True duplicates collapse quietly by default, so the user reads the event once, while every source report remains inspectable and a false merge can be corrected. In a 17 July local validation check, six selected reports became five unique Timeline additions plus one duplicate report. That small example captures the intended experience: preserve provenance, remove repeated attention cost.

AI Detector extends the same attention principle without pretending to solve authorship. A local deterministic text pass annotates only explicit evidence such as a platform label, an author declaration about the social post itself, or prompt residue. A separate asynchronous Codex pass can confirm, dispute, or correct that preliminary result after the Timeline is already usable. Its schema explicitly binds the object being assessed to the scope of the evidence: an AI-created website discussed in a human-authored post is not evidence that AI wrote the post. Because a model can still assign the wrong scope, a deterministic postcondition verifies every proposed strong result against the captured evidence before it receives UI, Drawer, or Hide authority; stale strong results from older contracts are shown as corrected rather than silently trusted. Inline badges are the default, and one stable badge slot holds neutral state, detector transitions, assessment detail, and direct user correction instead of scattering those controls across the card. The user may route unseen strong signals into a generic side pane, or deliberately activate a warned Hide mode that excludes only direct or Deep-confirmed results. If the deeper assessment says the first badge was wrong, AkuBrowser shows that correction instead of making the badge silently disappear. A direct user correction outranks both detector layers.

The first run leads into calibration before the Timeline opens. Later, direct feedback can promote, replace, demote, and suppress ordinary candidates. Material updates and contradictions remain protected, while one discovery lane preserves useful surprise. Active sources are ranked together rather than displayed as separate or rigidly alternating feeds. If nothing clears the newness, materiality, and evidence boundary, AkuBrowser says `0 additions` and stops.

X media follows the same finite-delivery rule. AkuBrowser can show a
usable-degraded post first, retain only short-lived allowlisted media evidence,
and complete the matching card without opening or focusing another tab. Live
validation made the boundary concrete: a Quiet X document detected media
roots, but both hydrated media-container and recoverable-URL counts stayed at
zero. The response-evidence path is the bounded answer to that measured gap,
not permission to take the foreground. Quiet and explicitly consented
foreground Recapture remain fallbacks, not the default price of uncertainty.

## How it was built

The system has three runtime pieces:

- AkuBridge, a Manifest V3 extension, performs bounded read-only capture and reports source-specific quality honestly.
- AkuSidecar, rewritten from Node.js to Go, owns the embedded UI, SQLite state, session engine, personalization policy, and one managed Codex App Server process.
- AkuSupervisor, written in Rust, owns the visible local development lifecycle so the Sidecar never needs a hidden watcher or self-replacement process.

Codex is used as a constrained reasoning component, not as an autonomous browser. One managed Codex App Server process currently serves schema-bound acquisition planning, candidate evaluation, semantic event resolution, and asynchronous AI Deep Detection. Candidate evaluation alone defaults to Luna `xhigh`; acquisition planning, semantic event resolution, and AI Deep Detection default to Luna `high`. A bounded per-process picker lets the user compare Luna High/XHigh, Terra High/XHigh, and Sol Medium without accepting arbitrary model strings. Go owns the bounded local event index, deterministic AI Fast Detection, retrieval shortlist, retention, confidence gates, correction authority, budgets, trust, personalization, and final composition. The AI Detection master switch can disable both Fast and Deep Detection without changing selection or Timeline composition, avoiding all Deep Detection token use. When deterministic event retrieval finds no plausible relationship, the Event Engine creates local event threads without paying for another model call. Deep Detection likewise skips evidence that is inadequate, already decided by direct platform provenance, or overridden by the user. Each adapter depends on a generic structured-inference contract rather than Codex-specific code, so the reasoning backend and its option catalog remain replaceable without weakening product authority. Stable local identities never enter model prompts, social content is treated as untrusted evidence, and every current App Server thread is ephemeral, read-only, tool-disabled, and schema-bound.

AkuBridge handles X media with three bounded evidence inputs: a
`document_start` DOM watcher, a fixed traversal-bounded MAIN-world React
resolver, and the v59 `x-response-evidence-v2` adapter. The last one observes
only successful responses to X's already-issued `HomeTimeline`,
`HomeLatestTimeline`, and `TweetDetail` GraphQL requests. It never issues or
retries a provider request. Raw responses and post text are parsed only inside
the page world and are never relayed or stored. The only output is a normalized
post ID plus at most four allowlisted X media records and, separately, the
owning author's allowlisted avatar URL. A 30-minute Bridge hot cache repairs
Quiet presentation; a bounded seven-day extension-local fallback retains only
the sanitized avatar URL and at most 512 normalized status-or-handle keys so a
later run can reuse previously observed presentation evidence. Neither cache
stores post text or raw responses, and the avatar never becomes post media or
Sidecar state. The extension keeps sanitized post-media evidence for 30
minutes across at most 128 post identities; Sidecar
revalidates the identity and CDN path before applying a presentation-only
override with `x_response_graphql` provenance. No new permission, tab, window,
focus change, Codex call, selection/ranking change, or provider authentication
is involved.

## Challenges

The hardest part was preserving the product experience while replacing the runtime. A first port looked healthy but skipped calibration, changed UI behavior, leaked duplicate LinkedIn entries when a permalink appeared late, and made repeated update checks look like no-ops. Each failure revealed a contract that had been implicit in the old implementation.

Another challenge was keeping preference feedback semantically clean. An earlier reason menu mixed “not interested” with freshness, prior knowledge, and duplication. The current contract makes Less like this one direct Not interested signal, while freshness and cross-author repetition remain evidence and Event Engine responsibilities. Canonical source identity prevents repeated captures from multiplying feedback, and Update Inbox lets the user replace a mistaken More/Less decision later without erasing the local audit trail.

The same control now reaches below the automatic selection line. From the lazy Inspect flow, a user can mark an evaluated candidate as `Should have selected`. AkuBrowser restores it immediately, runs the downstream semantic and AI Detector stages for that item, and turns the correction into its strongest positive taste signal. The action is undoable, and a later More or Less decision can supersede its learning effect. A reasoning failure is recoverable too: `Re-evaluate run` reuses durable captured evidence without reopening the browser.

Cross-source ordering was also subtler than round-robin. Strict alternation looks balanced but can lower relevance; pure scoring can let one platform dominate. The final rule keeps global personalized ranking and adds a small diversity guard only when another source has a candidate available.

The read-only browser boundary added another class of uncertainty. Social DOM
changes, external LinkedIn cards are not the same thing as post images, and X
media may hydrate differently in background and foreground windows. An active
tab is not necessarily a focused or document-visible tab. In the v57 live
trace, Quiet detected the X media roots but hydrated zero containers and
recovered zero URLs; Adaptive could succeed after visibility changed. Keeping
the DOM-only implementation would have made the product either unreliable or
interruptive. The response-evidence adapter instead observes only the three
already-requested X operations, reduces each response inside the page world to
a post identity and strict CDN media allowlist, and discards everything else.
One generic Media Acquisition Engine still shares budget, visibility policy,
and telemetry across adapters, while each source contributes bounded strategies
and foreground remains explicit consent. This preserves the user's attention
without disguising a missing image as complete evidence.

Cross-author duplication introduced a different problem: two posts can discuss the same topic without reporting the same occurrence. The Event Engine therefore uses high-precision actor/action/object/time matching, defaults to a `0.92` automatic-merge confidence gate with tightly bounded user tuning, and treats updates, contradictions, consequences, and context as unique information. A false merge can be split or reassigned by the user and undone immediately.

AI-origin assessment has an even sharper uncertainty problem. Stylistic “AI detectors” can punish polished human writing and present probabilities as facts. AkuBrowser therefore starts with deterministic evidence rather than style, keeps the model pass asynchronous, uses the language of signals rather than truth, preserves a visible correction when Deep Detection overturns Fast Detection, and never allows a preliminary inferred signal to trigger Hide. The UI primitive is also intentionally generic: AI Signals is one pane hosted by a reusable alternate-view drawer, not a new feed architecture coupled to the detector.

## What I learned

The most important lesson was that AI product quality depends on explicit authority boundaries. The model is good at describing evidence; it should not silently own capture depth, trust, display budget, or the meaning of user feedback. Those decisions became smaller deterministic policies around a structured model call.

The same boundary applies when the product evaluates AI-origin evidence. A detector may be useful while still being wrong. Reliability comes from naming the evidence, separating preliminary and deeper stages, preserving assessment history, and making the user's correction the highest authority for their own experience—not from displaying a more confident percentage.

I also learned that an empty result can be a feature—and that a post is the wrong unit for an attention product. A finite Timeline loses its purpose if uncertainty always triggers a fallback item or if five accounts repeating one occurrence consume five slots. “Nothing material changed” and “this is the same event” can both be valuable answers.

Browser evidence taught the same lesson in another form: primary delivery does
not need to block until every presentation detail is complete. A bounded item
can remain truthful and useful, then receive stronger media evidence
asynchronously, without turning uncertainty into permission to take the
foreground.

Finally, documentation became part of the refactor. Historical experiments and backward-compatibility contracts were creating more confusion than safety. The active project now keeps one product contract, one runtime contract, the current Bridge protocol, and only the schemas the runtime executes.

## What's next

AkuBrowser will keep strengthening the parts that protect a user's attention:
reliable quiet capture, high-authority personalization, event-level repetition
control, honest AI-origin signals, and clear source provenance. New sources and
media modalities will enter through the same bounded adapter and assessed-object
contracts rather than weakening the core with source-specific shortcuts.

The product will also keep reducing setup and operating friction while
preserving local ownership, inspectability, and explicit consent whenever a
browser action could interrupt the user. The direction is durable even as
individual adapters, models, packaging formats, and release milestones evolve.
