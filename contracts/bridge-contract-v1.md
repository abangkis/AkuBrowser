# AkuBrowser Local Bridge Contract v1

Contract identifier: `aku-browser.bridge.v1`

## Participants

- AkuBrowser tab: local UI served by AkuSidecar.
- AkuBridge: read-only Chrome extension.
- AkuSidecar: localhost job, state, and reasoning runtime.

## Local origin

`http://127.0.0.1:47821`

## Authenticated extension headers

- `X-Aku-Bridge-Token`
- `X-Aku-Bridge-Id`
- `X-Aku-Bridge-Contract: aku-browser.bridge.v1`

The token is generated and persisted by AkuSidecar. All bridge command endpoints reject a missing token or contract mismatch.

## Window message types

- `AKU_BROWSER_BRIDGE_PING`
- `AKU_BROWSER_BRIDGE_READY`
- `AKU_BROWSER_DISPATCH`
- `AKU_BROWSER_BRIDGE_ERROR`

## Extension message type

- `AKU_BROWSER_COLLECT_VISIBLE`

## Gate 0A behavior

- Catch Up targets a canonical feed: `https://x.com/home` or `https://www.linkedin.com/feed/`.
- Manual Live may use the active tab for the selected source.
- `openIfMissing: true` may create one inactive canonical source tab for an initial acquisition; `openIfMissing: false` fails fast.
- A Gate 0A run performs zero bridge-directed scrolls.
- Browser observations are untrusted evidence and every promoted item must retain a URL present in that observation.
- `block.permalink` is an exact native post URL or `null`; it must not fall back to the feed URL.
- `block.feedPosition` preserves the source platform's observed presentation order as contextual evidence; it is not a truth or relevance score.
- `observation.pageUrl` is the canonical source page and descendant `block.links` are external or contextual references.
- Every result item declares `sourceUrlKind` as `native_post`, `source_page`, or `external_reference`; external references must never be labeled as native posts.
- A block may carry at most four presentation-only `media` records captured from rendered post images or video posters. Each record contains `kind`, HTTPS `url`, bounded `alt`, `width`, and `height`.
- Media URLs are accepted only from the source CDN allowlist: `pbs.twimg.com`/`video.twimg.com` for X and `*.licdn.com` for LinkedIn. Actor avatars and small icons are excluded by source adapters and minimum rendered dimensions.
- Media is not sent to text reasoning and does not alter evidence identity, candidate assessment, or selection. It exists only to reconstruct Source layout.

## Gate 0B.1 additive behavior

The `collect_visible` command may carry a bounded native-capture plan:

- `scrolls`: requested scroll count, currently `0..2`;
- `scrollFraction`: viewport fraction per movement, currently `0.75`;
- `scrollSettleMs`: maximum wait for the rendered feed to settle after movement;
- `captureTimeoutMs`: total acquisition deadline, currently `45000`;
- `maxBlocksPerSnapshot` and `maxBlockCharacters`: evidence-size budgets;
- `restoreScroll: true`; and
- `browserAdapter: "aku-bridge"`.
- `openIfMissing`, controlled by the Sidecar's `open_missing_tab` or `fail_fast` policy.

AkuBridge captures before moving, performs only native DOM scrolling, stops when the budget/deadline/no-movement condition is reached, and attempts to restore the original position in a `finally` path. Browser focus, clicking, engagement, and account mutation remain outside the contract.

Coverage adds these auditable fields:

- `browserAdapter` and `captureMethod`;
- `fallbackUsed`;
- `scrollContainer`;
- `pendingNewContent`, `pendingNewContentLabel`, and `pendingNewContentAction`;
- `requestedScrolls` and `performedScrolls`;
- `snapshotCount`;
- `originalScrollY` and `finalScrollY`;
- `restoreAttempted` and `restored`; and
- `scrollStopReason`: `budget_exhausted`, `no_movement`, `deadline`, `cancelled`, or `not_requested`.

These fields are additive to `aku-browser.bridge.v1`. An observation that omits them remains a valid Gate 0A fixture, while a Gate 0B run must surface them through the final coverage object. Computer Use is not an implicit execution path; any future fallback must be separately approved and reported with `fallbackUsed: true`.

Gate 0B.1 recognizes a visible platform signal such as `New posts` or `Show posts` and reports `pendingNewContentAction: not_activated`. It must not click that control. `not_detected` is reported when no signal is present. Future activation requires a separate BrowserAdapter command because it changes the rendered stream and has different restoration semantics from scrolling.

## Gate 0B.2 same-tab reveal behavior

The capture command may explicitly add:

- `pendingContentPolicy: "reveal_if_present"`;
- `sameTabMutationAllowed: true`;
- `pendingContentTimeoutMs`, currently capped at `5000`; and
- `pendingContentSettleMs`, currently capped at `2000`.

When and only when that policy is present, AkuBridge may invoke one visible allowlisted control whose normalized label matches LinkedIn `New post(s)`/`Show new post(s)` or X `New post(s)`/`Show [N] post(s)`. It performs at most one activation attempt. It does not click arbitrary page controls and it still cannot like, reply, follow, message, or post.

Hiding or removing the platform signal is not sufficient proof because LinkedIn can temporarily empty the feed while loading. If activation does not produce a non-empty visible-feed fingerprint different from the pre-action fingerprint within the deadline, browser capture fails rather than classifying stale or loading-state content. After a successful reveal, AkuBridge sets the latest feed to the top, records `pendingNewContentAction: activated`, `pendingContentActivationEvidence: feed_fingerprint_changed`, `feedMutation: true`, `sameTabMutation: true`, and `restorationScope: post_reveal_start`, then runs the normal bounded scroll plan. `preActionScrollY` retains the former position; `originalScrollY` and `finalScrollY` describe the post-reveal capture baseline. If no signal is detected, the action remains `not_detected` and restoration scope remains `pre_run_position`.

## Gate 0B.3 provider-directed follow-up behavior

After round one, the ReasoningProvider may return only `finish` or `request_follow_up` under `acquisition-plan.schema.json`. JobEngine remains the authority for every browser parameter. A permitted follow-up has these fixed properties:

- `acquisitionRound: 2` with `maxAcquisitionRounds: 2`;
- exactly one requested scroll;
- the same run source and already-open source tab;
- `openIfMissing: false`, because a replacement tab cannot satisfy the prior frontier;
- `pendingContentPolicy: "detect_only"` and `sameTabMutationAllowed: false`;
- a continuation containing the final round-one `startScrollY` and at most three permalink-or-text anchor keys; and
- no URL selection, navigation, arbitrary click, Computer Use fallback, or third acquisition round.

AkuBridge positions the same tab at the supplied frontier, captures before moving, and must observe at least one exact anchor key in that first follow-up snapshot. Failure to match the frontier fails browser capture. A successful observation reports `acquisitionRound`, `continuationRequested`, `continuationAnchorMatched`, and `captureStartScrollY`, then restores the tab to its pre-follow-up position. AkuSidecar validates those fields against the issued command, persists both observations, deduplicates their evidence, and exposes whether the provider requested and executed the follow-up in final coverage.

## LinkedIn source-readiness behavior

`tab.status=complete` proves only that the page shell loaded. Before LinkedIn capture, AkuBridge probes a bounded, content-script-owned readiness state:

- `feed_ready`;
- `loading`;
- `login_required`;
- `selector_mismatch`;
- `feed_not_visible`;
- `page_shell`; or
- `wrong_page`.

The probe reports total and visible selector counts plus loading/root state only; it does not expand evidence collection. `feed_ready` requires at least one visible feed candidate, not merely a stale or off-viewport matching node. If a background LinkedIn tab is not ready, AkuBridge may temporarily activate it, wait up to the fixed readiness deadline, and restore the previously active tab. During this reliability phase, every LinkedIn capture uses `detect_only` for pending content; X retains its separately validated reveal behavior.

If the first LinkedIn capture still produces zero evidence, AkuBridge may perform exactly one readiness-and-capture retry in the same tab. It cannot open a second tab, add scroll budget, or invoke reasoning. Coverage records readiness state, wait duration, selector count, loading/root state, whether the tab was opened or temporarily activated, its initial background state, and retry count. A zero-evidence result after this bounded recovery fails at `source_readiness`, not `reasoning`.
