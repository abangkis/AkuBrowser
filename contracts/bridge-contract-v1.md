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

- Catch Up requires an already-open canonical feed: `https://x.com/home` or `https://www.linkedin.com/feed/`.
- Manual Live may use the active tab for the selected source.
- No source tab is silently opened when `openIfMissing` is false.
- A Gate 0A run performs zero bridge-directed scrolls.
- Browser observations are untrusted evidence and every promoted item must retain a URL present in that observation.
- `block.permalink` is an exact native post URL or `null`; it must not fall back to the feed URL.
- `block.feedPosition` preserves the source platform's observed presentation order as contextual evidence; it is not a truth or relevance score.
- `observation.pageUrl` is the canonical source page and descendant `block.links` are external or contextual references.
- Every result item declares `sourceUrlKind` as `native_post`, `source_page`, or `external_reference`; external references must never be labeled as native posts.

## Gate 0B.1 additive behavior

The `collect_visible` command may carry a bounded native-capture plan:

- `scrolls`: requested scroll count, currently `0..2`;
- `scrollFraction`: viewport fraction per movement, currently `0.75`;
- `scrollSettleMs`: maximum wait for the rendered feed to settle after movement;
- `captureTimeoutMs`: total acquisition deadline, currently `45000`;
- `maxBlocksPerSnapshot` and `maxBlockCharacters`: evidence-size budgets;
- `restoreScroll: true`; and
- `browserAdapter: "aku-bridge"`.

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
