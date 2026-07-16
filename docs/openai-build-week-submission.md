# AkuBrowser — a finite, user-steered layer over infinite feeds

## Inspiration

Social feeds are excellent discovery engines, but their success metric is usually more consumption. I wanted the opposite experience: ask “what changed?”, inspect a bounded amount of source evidence, keep what is genuinely useful, and reach a visible end.

The second insight was about personalization. A platform infers preference from pauses, clicks, and engagement collected behind the scenes. AkuBrowser can ask directly. When a user says More or Not interested, that intentional correction should carry more authority than an opaque behavioral proxy—without letting preference override evidence quality or trap the user inside a filter bubble.

## What it does

AkuBrowser captures a bounded slice of the user's signed-in X and LinkedIn feeds through a read-only Chrome extension. A local Go application evaluates every candidate with structured Codex output, removes repeated evidence, distinguishes new events from material updates, and builds one finite Timeline.

The first run leads into calibration before the Timeline opens. Later, direct feedback can promote, replace, demote, and suppress ordinary candidates. Material updates and contradictions remain protected, while one discovery lane preserves useful surprise. X and LinkedIn are ranked together rather than displayed as two separate or rigidly alternating feeds. If nothing clears the newness, materiality, and evidence boundary, AkuBrowser says `0 additions` and stops.

## How it was built

The system has three runtime pieces:

- AkuBridge, a Manifest V3 extension, performs bounded read-only capture and reports source-specific quality honestly.
- AkuSidecar, rewritten from Node.js to Go, owns the embedded UI, SQLite state, session engine, personalization policy, and one managed Codex App Server process.
- AkuSupervisor, written in Rust, owns the visible local development lifecycle so the Sidecar never needs a hidden watcher or self-replacement process.

Codex is used as a constrained reasoning component, not as an autonomous browser. It receives only the admitted bounded evidence and returns schema-validated candidate assessments, event identity, and knowledge delta. Deterministic Go code owns budgets, deduplication, trust gates, user-preference authority, and final composition.

## Challenges

The hardest part was preserving the product experience while replacing the runtime. A first port looked healthy but skipped calibration, changed UI behavior, leaked duplicate LinkedIn entries when a permalink appeared late, and made repeated update checks look like no-ops. Each failure revealed a contract that had been implicit in the old implementation.

Another challenge was separating “the user dislikes this topic” from “this item is old, duplicated, or already known.” Treating every Less reason as preference would teach the wrong model. AkuBrowser now routes those diagnostic corrections separately and uses canonical source/evidence identity so repeated captures do not multiply feedback.

Cross-source ordering was also subtler than round-robin. Strict alternation looks balanced but can lower relevance; pure scoring can let one platform dominate. The final rule keeps global personalized ranking and adds a small diversity guard only when another source has a candidate available.

## What I learned

The most important lesson was that AI product quality depends on explicit authority boundaries. The model is good at describing evidence; it should not silently own capture depth, trust, display budget, or the meaning of user feedback. Those decisions became smaller deterministic policies around a structured model call.

I also learned that an empty result can be a feature. A finite attention product loses its purpose if uncertainty always triggers a fallback item. “Nothing material changed” is often the most useful answer.

Finally, documentation became part of the refactor. Historical experiments and backward-compatibility contracts were creating more confusion than safety. The active project now keeps one product contract, one runtime contract, the current Bridge protocol, and only the schemas the runtime executes.

## What's next

The next step is to validate the experience across more real update cycles and tune readiness thresholds from direct user outcomes, not engagement. After that, the focus is packaging the local system cleanly, extending the source-adapter interface without weakening the bounded contract, and hardening Codex App Server as the durable reasoning boundary.
