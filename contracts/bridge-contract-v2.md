# AkuBrowser Local Bridge Contract v2

Contract identifier: `aku-browser.bridge.v2`

This contract begins the Go Sidecar boundary. It does not accept v1 headers,
payload aliases, build identities, or compatibility behavior.

## Participants and authority

- AkuBrowser is the local UI embedded in AkuSidecar.
- AkuBridge is the read-only bounded Chrome extension.
- AkuSidecar is the loopback coordinator, state owner, and policy authority.
- AkuSupervisor owns process lifecycle and the single cooperative
  `reload_self` mutation; it does not gain browser-content authority.

The supported local UI origins are `http://127.0.0.1:11122` and
`http://localhost:11122`. `127.0.0.1` remains the canonical launcher origin;
`localhost` is an equivalent loopback alias. Bridge-authenticated requests
carry all three headers:

```text
X-Aku-Bridge-Token: <durable random token>
X-Aku-Bridge-Id: <bounded caller identity>
X-Aku-Bridge-Contract: aku-browser.bridge.v2
```

## Required runtime identity

The active pair is exact:

- AkuBridge product version `0.7.0-preview.3` / Chrome manifest version `0.7.0.2`;
- runtime revision `source-adapters-v76`;
- build id `aku-bridge-0.7.0-preview.3-source-adapters-v76`; and
- contract `aku-browser.bridge.v2`.

Heartbeat publication is Bridge-authenticated. AkuSidecar process health is independent from Bridge readiness. A missing
current-process heartbeat is `reconnecting`; any observed mismatch is
`incompatible`. A session may start only when the current heartbeat is exact.
The exact v73 capability set includes
`mediaEvidenceAdapterVersions.x=x-response-evidence-v2` and the bounded
`observe_response_media_evidence` and `dispatch_background_commands` actions.
These declare evidence observation and bounded Sidecar-command dispatch, not
authority to issue provider requests or take unbounded browser control.

## Page relay messages

- `AKU_BROWSER_BRIDGE_PING`
- `AKU_BROWSER_BRIDGE_READY`
- `AKU_BROWSER_DISPATCH`
- `AKU_BROWSER_MEDIA_RECAPTURE`
- `AKU_BROWSER_MEDIA_RECAPTURE_COMPLETED`
- `AKU_BROWSER_MEDIA_RECAPTURE_FAILED`
- `AKU_BROWSER_X_MEDIA_EVIDENCE_LOOKUP`
- `AKU_BROWSER_X_MEDIA_EVIDENCE_RESULT`
- `AKU_BROWSER_X_MEDIA_EVIDENCE_FAILED`
- `AKU_BROWSER_BRIDGE_RELOAD_SELF`
- `AKU_BROWSER_CONFIGURE_BACKGROUND_DISPATCH`
- `AKU_BROWSER_BRIDGE_ERROR`

The relay transports only bounded commands, capability metadata, observations,
and failures. It grants no arbitrary script, navigation, click, debugger,
account, or filesystem authority.

## Capture command lifecycle

1. AkuSidecar persists a run and one `collect_visible` command.
2. AkuBridge claims it from `GET /api/bridge/commands/next`.
3. AkuBridge performs the bounded operation through the registered source adapter.
4. It returns one observation to
   `POST /api/bridge/commands/{id}/observation`, or one structured failure to
   `POST /api/bridge/commands/{id}/failure`.
5. AkuSidecar validates, persists, reasons, selects, and advances the session.

When Auto Update is enabled, the trusted AkuBrowser page may give the Bridge
service worker the loopback endpoint and durable Bridge token. The service
worker stores only that local dispatch configuration, polls the authenticated
pending-command endpoint at a bounded one-minute cadence, and executes the
same persisted command lifecycle. A `401` or `403` deletes the stored token and
stops the alarm until the trusted page configures it again. Claiming a command
remains atomic, so page dispatch and background dispatch cannot execute the
same command twice. A managed capture lease remains bound across acquisition
follow-ups and is released by the service worker only after the owning session
becomes terminal. Each background poll also republishes the authenticated
capability heartbeat so a restarted Sidecar can re-establish exact compatibility
without an open UI page.

Commands may authorize at most two acquisition rounds. Movement, timeout,
settle, snapshot, block, source-freshness, visibility, tab ownership, and
restoration ceilings are values issued by Sidecar policy, not by the model.
Each command also carries the registered source's `sourceHydrationTimeoutMs`.
The source registry owns its default and a fixed window of five seconds below
or above that default; Settings accepts only whole-second values inside that
window. LinkedIn's value is one total readiness budget spanning its initial
background observation and, when required, its activation retry.

An admitted observation must identify a source registered by both peers, contain at least one
snapshot and evidence block, and carry coverage. Every adapter declares the
`feed_post` family and its supported evidence modalities. Generic Bridge
admission requires author, one native or stable identity, and at least one of
text, image, video, typed attachment, or quoted-post evidence. Caption length
does not decide whether content exists. Stable text of at least 40 characters
is only the fallback identity when a native platform id and permalink are both
unavailable. AkuBridge supplies the admitted evidence; Go derives the canonical 24-hex
`evidenceKey` before validation and persistence.
Raw browser observations remain untrusted input. Reasoning output may reference
only evidence keys present in the admitted observation.

AkuSidecar recomputes the minimum evidence invariant and rejects identity-only
blocks, invalid native permalinks, malformed attachments, and bounded-resource
violations. The reasoning projection strips media URLs but preserves at most six
media metadata entries containing only kind, bounded alt text, dimensions, and
provenance. The evaluator must state limitations instead of claiming unseen
visual details.

Source-native presentation context remains separate from authored content.
LinkedIn may emit `presentation.socialContext` and an optional
`socialContextAvatarUrl` for feed-routing cues such as `Mohamad Ramzy commented`
or `Reza Lesmana likes this`. Sidecar displays that cue above the post identity;
it does not add it to the authored text, author, relationship type, or reasoning
evidence.

Attachments are typed separately from post media. A source adapter may emit at
most three `job`, `link_preview`, or `document` attachments with a canonical
HTTPS destination, bounded display metadata, and an optional rendered
thumbnail. The shared Sidecar renderer owns presentation; source adapters do
not emit HTML.

## Passive X media evidence

X media recovery has a passive path before item-scoped Recapture. Live v57
evidence showed that a Quiet X document could detect media roots while both
hydrated media-container and recoverable-URL counts stayed at zero. A DOM-only
cache therefore could not reliably recover the same evidence that appeared
after foreground visibility.

In v60, the existing `document_start` DOM watcher and fixed,
traversal-bounded MAIN-world React resolver are joined by
`x-response-evidence-v2`. This MAIN-world adapter also starts at
`document_start` and observes only successful JSON responses for X's exact
`HomeTimeline`, `HomeLatestTimeline`, and `TweetDetail` GraphQL operations. It
observes responses to requests X has already issued; it never creates, retries,
or modifies a provider request. Parsing is transient and bounded by response
bytes, traversal nodes, depth, properties, candidates, and media count.

This is not arbitrary script authority: only a normalized `x:status:<id>`,
media type, allowlisted `pbs.twimg.com` or `video.twimg.com` URL, dimensions,
`x_response_graphql` provenance, and the owning Tweet author's allowlisted
`pbs.twimg.com/profile_images/` URL may cross into the isolated runtime. Raw
React objects, raw GraphQL responses, operation URLs, post text, account state,
cookies, and provider authentication never cross worlds or persist. The
isolated runtime, extension store, and Sidecar each revalidate the bounded
envelope and allowlist.

The sanitized extension media cache is bounded to 30 minutes, 128 post
identities, and four media records per post. Avatar URLs use a separate
30-minute, 128-post in-memory cache. They are not published to the service
worker, written to extension storage, or relayed to Sidecar as post media. One
UI media lookup may request at most 64 identities.
Sidecar then revalidates the Timeline item's authoritative X identity and the
strict `pbs.twimg.com`/`video.twimg.com` host and path allowlist before accepting
`POST /api/bridge/timeline/{id}/media-evidence`. A successful update records a
completed `passive-x-media-enrichment-v2` provenance row with
`browserOperation=none` and replaces only local presentation evidence. It
creates no provider request, tab, window, focus change, navigation, scroll,
permission, Codex invocation, candidate, selection/ranking change, semantic
grouping change, or capacity cost. If the cache never obtains matching
evidence, the existing quiet Recapture and explicitly consented foreground job
remain the terminal fallback.

## Item-scoped media recapture

Recapture is a separate bounded Bridge task, not an update session. AkuSidecar
creates one job for a Timeline item whose captured media outcome is
`unavailable`. AkuBridge claims the job, opens only its canonical native-post
URL inside the managed capture surface, performs one zero-scroll capture, and
returns an observation or structured failure through the dedicated
`/api/bridge/media-recaptures/{id}` routes.

Quiet capture applies to recapture as strictly as it does to update capture.
The default `quiet` policy owns one shared non-focused managed window;
`quiet_multi_window` remains an experimental per-source-window option;
`adaptive_fidelity` uses an ordinary canonical source tab. Multiple managed
windows isolate source hydration but never authorize concurrent browser
capture.
The native-post tab is created inactive, activated only inside the unfocused
managed window, and guarded after activation and page load. If AkuBridge cannot
preserve or immediately restore the user's working window and tab, recapture
fails with `visible_recovery_required` instead of taking foreground focus.
Chrome's extension focus state is browser-scoped: it cannot identify which
non-Chrome desktop application currently owns foreground focus. Per-source
multi-window capture is therefore experimental and must not be treated as a
guarantee that Chrome can never surface while another application is active.

One generic Media Acquisition Engine serves every source adapter. In quiet
mode it attempts primary DOM evidence, source-exposed structured state, one
bounded hydration reread, and the adapter's alternate DOM extractor. Only
after those authorized background paths are exhausted may its audit set
`foregroundRequired`. A small or minimized window is not used as a substitute:
responsive layout and document visibility must remain representative while
the managed window stays unfocused.

Every returned observation includes a privacy-bounded capture-surface snapshot:
window state, type, focus, dimensions, plus tab active/discarded/load status.
Chrome window and tab identifiers are not transported. These fields must be
read together with `documentVisibleObserved`, readiness hydration counts, and
media-acquisition stages before classifying a quiet-capture failure.

Adaptive capture does not create the Quiet managed window first. It directly
uses the newest eligible canonical source tab in an ordinary Chrome window. An
existing tab remains user-owned and is preserved. If no eligible tab exists and
`openMissingSource` permits creation, Bridge records the new tab under the
session lease as `close_after_session`; terminal capture-surface cleanup closes
it only while it remains on the canonical feed. Navigation away from that feed
is treated as user adoption and the tab is preserved.

If that bounded background attempt completes with outcome `unavailable`, the
Timeline may offer a small inline question instead of opening a modal. A
foreground recapture is a separate job and requires an explicit per-item user
choice. Sidecar rejects it unless the latest completed attempt for that item was
an unavailable background attempt. The existing managed window is then focused
briefly on the canonical native post; its temporary tab and surface are closed
after capture, and AkuBridge restores the prior working surface unless the user
has intentionally moved elsewhere. This one-time authorization does not change
the persisted Quiet capture setting or permit foreground update capture.

Sidecar accepts only the requested source and evidence identity. A successful
result replaces that Timeline item's presentation evidence; it never creates a
candidate, invokes reasoning, changes semantic-event membership, or consumes
unique Timeline capacity. The temporary native-post tab and the managed
surface are released on success and failure.

## Cooperative reload

AkuSupervisor creates a single-flight request at
`POST /api/operations/bridge/actions/reload-self`. The local AkuBrowser relay
claims it through `/next`; AkuBridge accepts the action through `/{id}/accept`
before calling `chrome.runtime.reload()`.

The action completes only after a new heartbeat announces the exact v60 build.
Replay is idempotent only for the same request id, actor, and reason. Pending,
delivery, acceptance, heartbeat, build-mismatch, and expiry failures remain
explicit. No whole-browser restart or source-tab mutation is implied.

## Security and freshness

- The server binds only to loopback and rejects missing or mismatched Bridge
  authentication.
- Every Sidecar process creates a new non-secret `instanceEpoch`; old heartbeat
  readiness never crosses an epoch.
- Browser text is data, never executable instruction. The Codex provider is
  tool-free, read-only, web-disabled, and approval-free.
- The Bridge token is persisted in the fresh SQLite store and never placed in
  repository files or logs.
