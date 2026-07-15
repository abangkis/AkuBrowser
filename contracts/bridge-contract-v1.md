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
- `AKU_BROWSER_BRIDGE_RELOAD_SELF`
- `AKU_BROWSER_RELEASE_CAPTURE_SURFACE`
- `AKU_BROWSER_CAPTURE_SURFACE_RELEASED`
- `AKU_BROWSER_CAPTURE_SURFACE_RELEASE_FAILED`
- `AKU_BROWSER_BRIDGE_ERROR`

## Extension message type

- `AKU_BROWSER_COLLECT_VISIBLE`
- `AKU_BROWSER_PROBE_SOURCE_READY`
- `AKU_BROWSER_CAPTURE_DIAGNOSTICS`
- `AKU_BROWSER_CAPTURE_DELAY`
- `AKU_BRIDGE_RELOAD_SELF`
- `AKU_BRIDGE_RELEASE_CAPTURE_SURFACE`

The readiness, diagnostics, and delay messages are extension-internal. Capture
diagnostics expose only bounded stage/revision/count metadata. Capture delay is
accepted only from an approved X or LinkedIn content-script sender and is
clamped to two seconds; it keeps settling reliable when Chrome throttles timers
in a long-backgrounded source tab.

## Additive capability handshake

`AKU_BROWSER_BRIDGE_READY` may include a `capabilities` object. Its current fields are:

- `bridgeId`, `extensionVersion`, `runtimeRevision`, derived `buildId`,
  `adapterVersions`, `contractVersion`, and `manifestVersion`;
- supported `sources` and `actions`;
- `authority: "read_only_bounded"`; and
- fixed `captureLimits` for scrolls, snapshots, and blocks per snapshot.

The handshake is diagnostic metadata. It does not grant new browser authority, contain DOM or account data, or replace server-side contract validation. Older AkuBrowser clients may ignore it. The extension also accepts the internal `AKU_BRIDGE_GET_CAPABILITIES` message from its local tab bridge.

## Sidecar instance epoch and readiness recovery

AkuSidecar creates one opaque, non-persisted `instanceEpoch` per process
lifetime and returns it from health, bootstrap, heartbeat acknowledgement,
Bridge diagnostics, and the `X-Aku-Sidecar-Instance-Epoch` response header on
every API response. This lets an existing tab detect process replacement on
its ordinary session polling path rather than waiting for a periodic Bridge
ping. The epoch is not an authentication secret and does not
replace the persisted Bridge token. Its only authority is freshness: a Bridge
heartbeat recorded by one Sidecar process cannot authorize capture after that
process has been replaced.

The AkuBrowser tab must request a new capability handshake before every new
run. When the Sidecar epoch changes, or after a bounded Sidecar reconnect, it
must first set Bridge readiness to false, disable new-run controls, and publish
the resulting heartbeat to the current Sidecar. The normal readiness window is
three seconds. Expiry leaves the run uncreated and does not reuse prior UI
state.

Admission failures distinguish these cases:

- `bridge_reconnecting`: no heartbeat exists in the current epoch; retryable
  only inside the bounded UI readiness flow; and
- `bridge_incompatible`: a heartbeat exists but its version, runtime revision,
  adapter versions, build identity, or actions fail the declared requirements.

Sidecar HTTP health deliberately does not require Bridge readiness. Lifecycle
health and capture-integration readiness are separate contracts.

## Cooperative self-reload

`reload_self` is the only operational extension mutation exposed to
AkuSupervisor. It is created through Sidecar's bridge-authenticated
`POST /api/operations/bridge/actions/reload-self`, delivered to the local page
through `GET /api/operations/bridge/actions/next`, and acknowledged by the
extension through the bridge-authenticated action `accept` endpoint. The
service worker accepts the internal reload message only from the configured
AkuBrowser origin and then calls `chrome.runtime.reload()`.

The local page starts the action long poll only after a compatible AkuBridge
capability handshake. A local AkuBrowser URL opened in a browser without the
extension, or with an incompatible extension, remains a passive UI and cannot
claim a cooperative action intended for the eligible Chrome relay tab.

The existing content-script context is expected to disconnect. AkuBrowser
refreshes only its own local tab, performs a new capability handshake, and
Sidecar completes the action only after the required build identity is
observed. An unavailable or disabled extension times out. The contract adds no
`chrome.management`, debugger/CDP, whole-browser restart, source-tab closure,
or account authority.

## Gate 0A behavior

- Catch Up targets a canonical feed: `https://x.com/home` or `https://www.linkedin.com/feed/`.
- Manual Live may use the active tab for the selected source.
- `openIfMissing: true` may create one inactive canonical source tab for an initial acquisition; `openIfMissing: false` fails fast.
- A Gate 0A run performs zero bridge-directed scrolls.
- Browser observations are untrusted evidence and every promoted item must retain a URL present in that observation.
- `block.permalink` is an exact native post URL or `null`; it must not fall back to the feed URL. LinkedIn may recover the exact post URN by transiently opening only that post's control menu, reading its visible Embed target, and closing the menu.
- `block.feedPosition` preserves the source platform's observed presentation order as contextual evidence; it is not a truth or relevance score.
- `observation.pageUrl` is the canonical source page and descendant `block.links` are external or contextual references captured only from the post-content root.
- LinkedIn preserves the source's relative `presentation.timestampText`. When
  no native `datetime` exists, a valid relative value such as `14h` produces a
  deterministic UTC-bucket estimate in `publishedAt` plus
  `timestampSource: relative_text_estimate`, `timestampEstimated: true`, and a
  bounded precision. A promoted post that exposes no time remains
  `publishedAt: null` with `not_exposed_promoted`; AkuBridge never fabricates a
  timestamp.
- Every result item declares `sourceUrlKind` as `native_post`, `source_page`, or `external_reference`; external references must never be labeled as native posts.
- A block may carry at most four presentation-only `media` records captured from rendered post images or video posters. Each record contains `kind`, HTTPS `url`, nullable `posterUrl`, nullable allowlisted `playbackUrl`, `playbackMode`, bounded `alt`, `width`, and `height`. Images may open the AkuBrowser viewer. Videos use inline playback only when the rendered source exposes a stable allowlisted media URL; otherwise their poster opens the exact native post and is never treated as a zoomable image.
- A source adapter may activate the post-local `Show more` control before extraction and records the bounded outcome in `presentation.contentExpansion`. LinkedIn restores a reversible `Show less` state afterward. X uses its stable `tweet-text-show-more-link` inline expansion; X currently exposes no matching collapse control, so the expanded read-only view remains in the source tab while scroll position is still restored. The control label itself is not evidence text.
- Media URLs are accepted only from the source CDN allowlist: `pbs.twimg.com`/`video.twimg.com` for X and `*.licdn.com` for LinkedIn. Actor avatars and small icons are excluded by source adapters and minimum rendered dimensions.
- Media is not sent to text reasoning and does not alter evidence identity, candidate assessment, or selection. It exists only to reconstruct Source layout.

## Gate 0B.1 additive behavior

The `collect_visible` command may carry a bounded native-capture plan:

- `scrolls`: requested scroll count, currently `0..6`; the active bounded-load
  profile normally requests 2, 4, or 6;
- `scrollFraction`: viewport fraction per movement, currently `0.75`;
- `scrollSettleMs`: maximum wait for the rendered feed to settle after movement;
- `captureTimeoutMs`: total acquisition deadline, currently `45000`;
- `maxBlocksPerSnapshot` and `maxBlockCharacters`: evidence-size budgets;
- `qualityReportRequired: true` for the current Sidecar runtime;
- `qualityRetryBudget`, currently clamped to `0..1`;
- `qualityRetrySettleMs`, derived from the active bounded-load profile (300 or
  1,000 ms in the built-in profiles) and capped at `1000`;
- `restoreScroll: true`; and
- `browserAdapter: "aku-bridge"`.
- `openIfMissing`, controlled by the Sidecar's `open_missing_tab` or `fail_fast` policy.
- `captureLeaseId`, set to the standalone run ID or shared unified-session ID.

AkuBridge captures before moving, performs only native DOM scrolling, stops when the budget/deadline/no-movement condition is reached, and attempts to restore the original position in a `finally` path. The global advertised block ceiling is 20; LinkedIn currently applies a stricter runtime ceiling of eight blocks per snapshot. The six-scroll/seven-snapshot Bridge ceiling is a structural safety boundary, while normal tuning is performed through one Sidecar bounded-load profile. Browser focus, clicking, engagement, and account mutation remain outside the contract.

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

Gate 0B.1 recognizes a visible platform signal such as `New posts` or `Show posts`. In an initial acquisition, the source-freshness policy may authorize Gate 0B.2 to resolve it before capture. A follow-up remains detect-only because its prior frontier must not be replaced.

## Source freshness recovery

Readiness and freshness are separate contracts. Readiness proves that a usable
rendered feed exists. Freshness recovery uses the generic
`source-freshness-recovery-v1` engine to wake a background tab, observe the
adapter-declared server-sync window, and resolve an automatically changed feed
or one pending-content control before capture.

Every Gate 0B observation reports `coverage.sourceFreshness`, including the
generic policy version, adapter freshness version, terminal outcome,
verification class, wake/activation state, bounded probe count and wait, and
pending-content mutation state. Raw feed fingerprints are never transported.
The complete normative state and adapter interface is in
`source-freshness-recovery-v1.md`.

## Gate 0B.2 same-tab reveal behavior

The capture command may explicitly add:

- `pendingContentPolicy: "reveal_if_present"`;
- `sameTabMutationAllowed: true`;
- `pendingContentTimeoutMs`, currently capped at `5000`; and
- `pendingContentSettleMs`, currently capped at `2000`.

When and only when that policy is present, the generic freshness runtime may invoke one visible allowlisted control whose normalized label matches the pattern supplied by the registered source adapter. Current adapters allow LinkedIn `New post(s)`/`Show new post(s)` and X `New post(s)`/`Show [N] post(s)`. It performs at most one activation attempt. It does not click arbitrary page controls and it still cannot like, reply, follow, message, or post.

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

The probe reports total and visible selector counts plus loading/root state only; it does not expand evidence collection. `feed_ready` requires at least one visible feed candidate, not merely a stale or off-viewport matching node. If a background LinkedIn tab is not ready, AkuBridge may temporarily activate it and wait up to the fixed readiness deadline. After readiness, the generic freshness stage applies the same wake/reveal/proof contract used for X. Both source adapters support reveal during initial acquisition.

Scroll settling and other bounded capture waits use a service-worker response
rather than relying only on a page timer, because Chrome may heavily throttle a
source tab that has remained in the background. The outer capture deadline can
request the content script's last safe progress stage so a timeout identifies
whether capture was probing, recovering permalinks, extracting a block,
scrolling, settling, or restoring. This diagnostic adds no post content.

There is no LinkedIn-specific detect-only retry. A freshness failure stops before
capture at `source_freshness`; a rendered feed that still yields zero usable
evidence fails later at `source_readiness` or quality admission. Neither case
is presented as a correctly empty catchup.

## Stale source-tab recovery

Chrome may close or replace a tab after AkuBridge discovers it but before capture begins. During acquisition round one only, an explicit stale-tab error permits exactly one new discovery attempt. The configured missing-tab policy remains authoritative: `open_missing_tab` may create the canonical feed if rediscovery finds none, while `fail_fast` may only use another already-open eligible tab. The observation reports `sourceTabRecoveryCount` as `0` or `1`.

Each observation also reports the selected `adapterVersion` and a bounded `adapterCapabilities` list. Every capability entry identifies its `source`, adapter `version`, trusted `qualityProfile`, `freshnessVersion`, `mediaRecoveryVersion`, and read-only `actions`; consumers must preserve this additive diagnostic metadata without treating it as new authority.

Acquisition round two never uses this recovery. A provider-directed follow-up is bound to the prior observation frontier, so losing its tab must fail explicitly rather than silently rebinding to a different page state.

## Source adapter and tab-lease behavior

X and LinkedIn DOM knowledge is registered through separate source adapters behind the same content-runtime contract. The shared runtime owns bounded movement, restoration, normalization, and extension messaging. An adapter owns source-page matching, feed candidate discovery, author discovery, source-specific media exclusions, a versioned freshness strategy, and a versioned alternate-media extraction strategy. The generic freshness runtime owns detection mechanics, activation orchestration, reveal proof, and outcomes. The generic media-recovery runtime owns bounded settling, primary re-read, allowlist normalization, outcomes, and aggregation. Runtime and adapter registries are revisioned: reinjecting the complete bundle replaces the stale generation and its message listener instead of preserving a permanent first-injection singleton.

Before capture, AkuBridge binds a short-lived lease containing the tab id, window id, source, and bound URL. It validates the lease immediately before and after collection. Navigation within the same approved source remains valid; a closed or replaced tab, changed window identity, or navigation outside the approved source fails closed. Structured failure payloads add stable `code`, `stage`, and safe `details` fields while retaining the human-readable `message` required by existing clients.

A runtime-generation command guard prevents duplicate terminal submissions for the same command id. Durable idempotency across Manifest V3 service-worker restarts remains owned by AkuSidecar's authenticated command-claim contract.

## Adapter observability, semantics, and frontier metadata

Every bounded observation may add three diagnostic structures without increasing browser authority:

- `adapterHealth` reports the selected discovery strategies, bounded selector counts, per-field presence counts, and a non-content DOM signature;
- evidence blocks report `contentKind`, `relationshipType`, optional `parentPermalink`, and bounded engagement labels in addition to existing author/time/provenance fields; and
- `frontier` reports the final scroll position, bounded anchor keys, final-viewport novelty, and a conservative `hasMoreCandidateSignal`.

These fields are observations, not commands. `hasMoreCandidateSignal` does not authorize another scroll; JobEngine still owns the acquisition round and budget. Engagement counts and platform ordering remain contextual evidence rather than ranking truth.

`adapterHealth.fieldCoverage` remains diagnostic, but capture admission is now
enforced by the generic `social-post-v1` quality profile. Text and author are
required; platform id, native permalink, or stable text identity is required
as a one-of identity; media and primary avatar are conditional when their
source roots are detected; timestamp is optional and can be explicitly
not-exposed.

Every evaluated candidate produces a report containing `profile`, categorical
`verdict`, diagnostic `score`, retry `attempt`, and bounded `issues`. An issue
contains `field`, stable `code`, `observedState`, `severity`, `recoverable`,
`impact`, and `attempt`. Impact is `identity`, `evidence`, or `presentation`.
Presentation-only avatar hydration warnings remain visible but neither consume
retry budget nor degrade an otherwise complete candidate. Verdicts are `complete`, `usable_degraded`, `retryable`, or
`invalid`. The numeric score is never the sole admission authority.

Each block carries its final `captureQuality`; each snapshot carries all
candidate `qualityReports`, including a report for an invalid or short-text
candidate that is not transported as a block; and coverage carries a summary
with profile, verdict totals, issue totals, retry budget, and retry attempts.
When a conditional value is detected but not hydrated, AkuBridge may consume
the one pre-authorized retry. For media, the generic recovery runtime first
settles and reruns primary extraction, then invokes one adapter-owned alternate
DOM extraction if necessary. Both paths remain inside the same candidate, tab,
viewport, and command deadline. The retry cannot add scrolling, navigation,
reveal actions, tab recovery, or command time. A final observation must not
contain `retryable`.

Every report has a bounded `candidateKey`: platform identity or native
permalink when available, otherwise a stable text fingerprint, and finally a
snapshot-local DOM key. Rejected candidates therefore remain diagnosable even
when they cannot produce an admitted evidence key.

Every transported block carries `mediaRecovery` with policy/strategy versions,
outcome, attempt count, recovery method, recovered count, a finite extraction
`trace`, and an optional limitation. Outcomes are `not_applicable`, `primary_complete`, `recovered`, and
`unavailable`. Coverage aggregates these outcomes in `mediaRecovery` and sets
`fallbackUsed` exactly when at least one candidate was recovered. AkuSidecar
rejects contradictory block/summary/fallback states. An unavailable media root
may remain as explicitly degraded textual evidence and Source layout must show
the limitation plus the native-post link rather than an empty media shell. The
normative lifecycle is [Media Recovery v1](media-recovery-v1.md).

Source adapters may declare semantic media evidence that exists before a CDN
asset hydrates. For X, an in-candidate status-photo permalink is such evidence.
Once detected, the candidate may not report `not_applicable`; it must report
`primary_complete`, `recovered`, or `unavailable` after the bounded lifecycle.

AkuSidecar validates structure and report consistency before persistence. It
admits `complete` and `usable_degraded` blocks, removes `invalid` blocks, and
fails closed if every candidate is invalid or any report contradicts the
observation. Coverage adds `qualityAdmission` with admitted, degraded,
rejected, retry, and issue totals. Acquisition planning and final reasoning
receive only admitted evidence.

Under deterministic sparse-gap planning, a sparse set of complete admitted
blocks terminates without provider planning. Presentation warnings and rejected
shells alone cannot justify a follow-up; an evidence-impact gap may.

`sourceEvents` is a bounded list of passive states such as `source_new_content_available`, `source_session_expired`, `source_feed_unavailable`, or `source_layout_changed`. Reporting an event never authorizes background monitoring, notification, engagement, or account mutation.

## Managed source-tab lifecycle

The command may carry a bounded `tabLifecycle` policy. Existing user tabs always have `shared` ownership and are preserved. A canonical source tab opened by AkuBridge is reported as `managed`; its default disposition is still `preserve`. The optional `close_after_capture` disposition may close only a tab opened by the same initial acquisition and only after a successful capture. It cannot close a pre-existing user tab or a tab needed for a frontier-anchored follow-up.

Quiet capture additionally binds its dedicated window and canonical feed tabs
to `captureLeaseId`. Both source children and any follow-up in one unified
session share that lease. AkuBrowser requests release only after the standalone
run or unified session becomes terminal and repeats the latest terminal release
after reload. AkuBridge closes the complete managed window only when every
remaining tab still has a recorded owned ID and canonical source URL. If any
unrecorded tab exists, or an owned tab was moved or navigated, the window is
preserved and only still-provable Bridge-owned tabs are closed. A mismatched
lease is rejected so delayed cleanup cannot close a newer session's surface.
Pre-existing working tabs/windows never enter the managed ownership record.

`workingTabPreserved` is an ownership assertion: the capture ran exclusively
against a Bridge-owned managed tab and did not navigate or close pre-existing
user work. It MUST NOT be inferred from equality with the focus snapshot taken
at capture start. `workingFocusRestored` is a separate diagnostic. Bridge may
restore focus only when its managed window became focused; a later user-selected
tab or non-managed window is authoritative and MUST NOT be rolled back.

## Source-adapter conformance

Each adapter version must pass synthetic DOM fixtures covering its primary discovery strategy and source semantics. The fixture suite is a drift detector, not evidence that the live platform DOM is stable; live `adapterHealth` remains authoritative for operational diagnosis.
