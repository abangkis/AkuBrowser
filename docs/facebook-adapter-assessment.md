# Facebook source adapter assessment

Status: assessment only; no Facebook implementation is authorized yet, 19 July 2026.

## Outcome

Facebook can fit AkuBrowser's bounded, read-only, finite-Timeline product model, but it must not be added as one more collection of `if source === "facebook"` branches. The current system has a real adapter boundary in AkuBridge, while source identity, source surfaces, storage constraints, heartbeat compatibility, UI metadata, and several capture behaviors remain hard-coded for exactly X and LinkedIn.

The recommended sequence is:

1. make source registration generic without changing capture, reasoning, Event Engine, preference, AI Detector, or Timeline architecture;
2. prove X and LinkedIn conformance is unchanged;
3. add Facebook Home Feed as a narrow adapter behind the same contract;
4. expand Facebook fidelity only from live, signed-in DOM evidence and acceptance telemetry.

There is also a separate policy gate. Meta's current Terms state that automated access or collection requires prior permission, including when logged in. Its Automated Data Collection Terms additionally require express written permission and restrict collection of non-public personal data. This assessment is technical, not legal advice, but implementation and public distribution should not proceed without an explicit product/compliance decision:

- [Meta Terms of Service](https://www.facebook.com/legal/terms)
- [Meta Automated Data Collection Terms](https://www.facebook.com/legal/automated_data_collection_terms)

## What remains unchanged

Facebook should enter the same pipeline as every other source:

`bounded capture -> Candidate Evaluation -> preference selection -> global composition -> semantic event resolution -> AI Fast Detection -> Timeline -> async AI Deep Detection`

The following components should remain source-agnostic and require no Facebook-specific behavior:

- Candidate Evaluation and its replaceable reasoning provider;
- preference fitting and More/Less authority;
- selection thresholds and protected updates;
- global finite-capacity composition and discovery lane;
- cross-author semantic event resolution across all active sources;
- AI Detector;
- Update Inbox and correction semantics;
- Timeline retention and finish-line behavior.

Facebook must produce the same normalized `Observation`, `Block`, `CandidateAssessment`, `TimelineItem`, media, attachment, presentation, and telemetry contracts. Downstream engines must not know which DOM produced them.

## Current source coupling that must be removed first

### AkuBridge

The adapter runtime is a good base: each adapter registers discovery, author, semantics, quality, freshness, and media-acquisition behavior. Core code still assumes exactly two sources in several places:

- `manifest.json` declares only X and LinkedIn hosts and scripts;
- `bridge-capabilities.js` hard-codes source and adapter maps;
- `source-tab-policy.js`, capture-window tracking, and trusted-sender validation hard-code source hosts and feed URLs;
- `service-worker.js` branches on source for tab queries, readiness timeouts, visual hydration, native recapture URL validation, and X response evidence;
- `content-script.js` owns LinkedIn permalink/timestamp recovery, source-specific expansion, scroll context, quoted-root handling, visual hydration, and parts of media extraction;
- `bounded-capture-policy.js` hard-codes platform IDs and media host allowlists;
- `media-acquisition-engine.js` still knows `video.twimg.com`.

Platform selectors and extraction rules belong in an adapter. Platform identities, canonical URLs, readiness strategy, and optional capabilities belong in one source catalog. Generic capture and media engines should only call those contracts.

Chrome MV3 still requires static `host_permissions` and content-script matches. That declarative manifest is a platform requirement, not avoidable runtime hard-coding. It should be generated from or verified against the same source catalog so the manifest cannot drift from runtime capabilities. Adding Facebook host access will produce a new extension permission warning for users.

### AkuSidecar

The Go pipeline is generic after a run owns a valid `domain.Source`, but source admission is fixed in:

- `Source.Valid()` and default Settings;
- the `activeSources` maximum of two;
- nine SQLite source constraints that accept only `x` and `linkedin`;
- bridge heartbeat versions and exact map lengths;
- native-source URL validation;
- reasoning-result source enums and evidence-key patterns;
- onboarding and Settings controls;
- Timeline labels, icons, fallback avatars, engagement rendering, and source URL checks;
- X-only passive media enrichment and parts of recapture identity handling.

Adding Facebook cleanly therefore requires a fresh schema boundary. The current schema is version 5 and intentionally has no migration path. A source-catalog schema would be version 6 and require a development database reset under the existing fresh-boundary policy.

## Recommended source contracts

### 1. Sidecar source registry

One Go registry should own stable product metadata and policy:

- source ID, display name, and UI icon key;
- enabled/default state and ordering;
- native permalink validator;
- evidence-key namespace;
- expected Bridge adapter version and optional capability versions;
- source-level bounded limits only when they differ from global defaults.

`Source.Valid`, Settings validation, heartbeat compatibility, URL validation, onboarding metadata, and UI bootstrap should all read this registry. Candidate Evaluation should not be trusted to choose a source: AkuSidecar already knows the run source and should bind it deterministically. The structured output schema should stop enumerating source IDs or source-prefixed evidence keys supplied by the model.

For SQLite, prefer a seeded `source_definitions` table referenced by source-bearing tables, or remove fixed SQL enums and validate every write through the compiled registry. The first option preserves database-level integrity and makes later source additions data changes rather than table-definition changes.

### 2. Bridge source catalog

One JavaScript catalog should expose:

- source ID and adapter script;
- allowed page hosts and canonical feed URL policy;
- content-script match patterns;
- native post URL and recapture target validation;
- readiness timeout and background-visual-hydration policy;
- managed-window and tab-lifecycle behavior;
- media URL allowlist and optional response-evidence capability;
- adapter and capability versions.

The service worker, tab/window runtime, trusted-sender checks, capability heartbeat, and package verifier should consume this catalog. X response-media capture remains an optional X capability, not part of the contract every source must implement.

### 3. Source Adapter v2 hooks

The existing required methods remain. Source-specific branches currently in `content-script.js` should move behind adapter hooks:

- `getScrollContext()`;
- `expandContent()` and `restoreContent()`;
- `recoverPermalinks()`;
- `canonicalPermalink()` and `platformIdentity()`;
- `findQuotedRoot()` or a generic nested-post extractor;
- `resolveTimestamp()`;
- `summarizeVisualHydration()`;
- `safeMediaUrl()` and media-root extraction;
- `readinessPolicy` and `captureLimits` metadata.

Hooks may be optional with conservative generic defaults. The core owns budgets, deadlines, retries, lifecycle, normalization, telemetry, and safety. The adapter owns only source semantics and DOM knowledge.

### 4. Generic UI source descriptors

Onboarding and Settings should render active sources from bootstrap descriptors instead of static HTML checkboxes. Timeline cards should use normalized presentation data plus descriptor-provided label, icon, color token, and canonical-link policy. X, LinkedIn, and Facebook must not require three rendering branches.

Source-specific visual differences remain allowed only where the normalized evidence differs, for example nested quoted posts or social-context text. They should be represented by data capabilities, not source-name checks.

## Facebook v1 scope

If the policy gate is cleared, start deliberately narrow:

- signed-in desktop Facebook Home Feed only;
- read-only bounded observation; no reactions, comments, sharing, following, messaging, or login automation;
- main post body, author/Page identity, timestamp/permalink when exposed, social context, engagement summary, avatar, and image preview;
- exclude comment threads, Stories, Reels player feeds, Marketplace, notifications, Messenger, profile crawling, Page crawling, and Group crawling;
- no GraphQL interception, cookie access, token access, or response-body collection;
- no foreground fallback without the existing quiet-first exhaustion and explicit user consent contract;
- text remains usable when media cannot be acquired.

The adapter must be built from live DOM evidence. Facebook uses heavily dynamic and virtualized markup, and public documentation does not provide a stable Home Feed DOM contract. Candidate discovery should prefer semantic feed/article boundaries and multiple independent anchors rather than obfuscated class names. Synthetic fixtures alone are insufficient; acceptance needs repeated signed-in captures across ordinary posts, shared posts, Page posts, suggested posts, sponsored content, images, and video placeholders.

## Facebook-specific risks and decisions

### Policy and privacy: blocking decision

The Home Feed may contain content visible only because of a friendship, Group membership, or another audience restriction. Meta's published automated-collection terms distinguish publicly available personal data and require express permission for automated collection. Local-only storage and user initiation reduce product risk but do not obviously override those terms. Public release needs an explicit decision before code is enabled.

### Sponsored content: product decision

Facebook interleaves sponsored and suggested content with ordinary posts. Decide whether v1:

- evaluates sponsored posts normally;
- captures them but marks and excludes them deterministically; or
- omits them at the adapter quality boundary.

This must be a product contract, not a selector accident.

### Durable media: architecture decision

Facebook image, avatar, and video URLs commonly use signed CDN URLs whose usefulness may be shorter than Timeline retention. Reusing remote URLs may render correctly immediately and fail later. A durable local media cache would solve that but adds storage, cleanup, content-security, and packaging responsibilities. For v1, the lowest-risk boundary is text-first plus best-effort current image/avatar URLs, with honest unavailable-media state; video acquisition and local byte caching should remain separate follow-up decisions.

### DOM durability: expected high maintenance

Facebook's feed virtualization, nested shared posts, comments inside post containers, localized labels, and limited stable test IDs make false boundaries more likely than on LinkedIn. The adapter needs a frontier contract that proves movement and new candidates, plus source-specific health telemetry. Selector mismatch must fail visibly instead of silently returning zero additions.

## Acceptance gates

Architecture is ready for Facebook only when:

1. X and LinkedIn pass unchanged adapter conformance after registry extraction;
2. adding a synthetic third source requires no new source-name branch in Bridge or Sidecar core;
3. schema v6 accepts registered sources without editing every source-bearing table again;
4. heartbeat compatibility derives from registries rather than exact two-entry maps;
5. onboarding, Settings, Timeline icon/label, Inbox, calibration, and global composition render a third source dynamically;
6. reasoning binds source identity deterministically outside model output;
7. generic media acquisition has no X or LinkedIn host knowledge;
8. Facebook live acceptance distinguishes login required, feed ready, selector mismatch, zero material additions, and capture failure;
9. no capture path accesses comments, messages, cookies, tokens, or unrequested surfaces;
10. policy/compliance direction has been explicitly approved.

## Proposed implementation checkpoints after approval

1. **Generic source foundation:** Sidecar and Bridge registries, dynamic UI descriptors, schema v6, and conformance tests using a synthetic third source.
2. **Facebook text adapter:** Home Feed readiness, candidate boundary, text/author/social context, canonical identity, quiet lifecycle, and telemetry.
3. **Facebook presentation evidence:** avatar and image acquisition, shared-post nesting, engagement, and explicit sponsored-content policy.
4. **Durability review:** repeated live runs, selector failure tests, expiring-media behavior, Update Inbox traces, cross-source semantic events, and reset/packaging acceptance.

No checkpoint should change the downstream selection, preference, semantic, AI Detector, or finite-Timeline architecture.
