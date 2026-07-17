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

The only origin is `http://127.0.0.1:47821`. Bridge-authenticated requests
carry all three headers:

```text
X-Aku-Bridge-Token: <durable random token>
X-Aku-Bridge-Id: <bounded caller identity>
X-Aku-Bridge-Contract: aku-browser.bridge.v2
```

## Required runtime identity

The active pair is exact:

- AkuBridge extension/manifest `0.6.6`;
- runtime revision `source-fidelity-v56`;
- build id `aku-bridge-0.6.6-source-fidelity-v56`; and
- contract `aku-browser.bridge.v2`.

Heartbeat publication is Bridge-authenticated. AkuSidecar process health is independent from Bridge readiness. A missing
current-process heartbeat is `reconnecting`; any observed mismatch is
`incompatible`. A session may start only when the current heartbeat is exact.

## Page relay messages

- `AKU_BROWSER_BRIDGE_PING`
- `AKU_BROWSER_BRIDGE_READY`
- `AKU_BROWSER_DISPATCH`
- `AKU_BROWSER_MEDIA_RECAPTURE`
- `AKU_BROWSER_MEDIA_RECAPTURE_COMPLETED`
- `AKU_BROWSER_MEDIA_RECAPTURE_FAILED`
- `AKU_BROWSER_BRIDGE_RELOAD_SELF`
- `AKU_BROWSER_BRIDGE_ERROR`

The relay transports only bounded commands, capability metadata, observations,
and failures. It grants no arbitrary script, navigation, click, debugger,
account, or filesystem authority.

## Capture command lifecycle

1. AkuSidecar persists a run and one `collect_visible` command.
2. AkuBridge claims it from `GET /api/bridge/commands/next`.
3. AkuBridge performs the bounded X or LinkedIn adapter operation.
4. It returns one observation to
   `POST /api/bridge/commands/{id}/observation`, or one structured failure to
   `POST /api/bridge/commands/{id}/failure`.
5. AkuSidecar validates, persists, reasons, selects, and advances the session.

Commands may authorize at most two acquisition rounds. Movement, timeout,
settle, snapshot, block, source-freshness, visibility, tab ownership, and
restoration ceilings are values issued by Sidecar policy, not by the model.

An admitted observation must identify X or LinkedIn, contain at least one
snapshot and evidence block, and carry coverage. AkuBridge supplies native
identity/permalink/text evidence; Go derives the canonical 24-hex
`evidenceKey` before validation and persistence.
Raw browser observations remain untrusted input. Reasoning output may reference
only evidence keys present in the admitted observation.

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

## Item-scoped media recapture

Recapture is a separate bounded Bridge task, not an update session. AkuSidecar
creates one job for a Timeline item whose captured media outcome is
`unavailable`. AkuBridge claims the job, opens only its canonical native-post
URL inside the managed capture surface, performs one zero-scroll capture, and
returns an observation or structured failure through the dedicated
`/api/bridge/media-recaptures/{id}` routes.

Quiet capture applies to recapture as strictly as it does to update capture.
The native-post tab is created inactive, activated only inside the unfocused
managed window, and guarded after activation and page load. If AkuBridge cannot
preserve or immediately restore the user's working window and tab, recapture
fails with `visible_recovery_required` instead of taking foreground focus.

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

The action completes only after a new heartbeat announces the exact v52 build.
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
