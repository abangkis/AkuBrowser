# Facebook source adapter contract

Status: implemented for local preview development, updated 26 July 2026.

## Product boundary

Facebook is an available AkuBrowser source behind the same bounded, read-only
pipeline used by X and LinkedIn:

`bounded capture -> native resurface check -> Candidate Evaluation -> preference selection -> global composition -> semantic event resolution -> optional AI Fast Detection -> Timeline -> optional async AI Deep Detection`

AkuBrowser shows what the signed-in source feed presents, then gives the user
authority over what remains in their finite Timeline. Facebook does not receive
a separate ranking, preference, semantic-event, AI Detector, Inbox, retention,
or correction path. More/Less feedback and selection correction use the same
source-bound evidence contract.

Facebook is available and preselected with X and LinkedIn during fresh
onboarding. It requires an existing signed-in Chrome session; AkuBrowser does
not automate login.

## Generic source architecture

AkuSidecar owns one source registry. It supplies source identity, display
metadata, default activation, adapter versions, optional capabilities, and
source behavior metadata. `Source.Valid`, Settings validation, heartbeat
compatibility, onboarding controls, Timeline presentation, and database source
definitions consume this registry. SQLite schema 7 references the seeded
`source_definitions` table instead of repeating fixed source enums. Reasoning no
longer owns or returns source identity; Sidecar binds each result to its run.

AkuBridge owns one source catalog for source IDs, host/page policy, canonical
feed URLs, manifest match patterns, adapter scripts, readiness behavior, native
post URLs, and optional capabilities. The service worker, tab/window lifecycle,
trusted-sender checks, heartbeat, and package verification consume the catalog.
Chrome MV3 host permissions remain declarative in `manifest.json`, and tests
verify that the static manifest matches the catalog.

The generic content and media runtimes own budgets, deadlines, retries,
lifecycle, normalization, telemetry, scrolling, restoration, and safety. Each
adapter owns only source DOM knowledge: candidate boundaries, author and social
context, content expansion, permalink and timestamp evidence, nested-post
boundaries, visual hydration, and media extraction policy.

X response-backed media and avatar recovery remains an optional X capability.
It was not rewritten or generalized for Facebook. The existing DOM watcher,
MAIN-world resolver, response evidence, bounded caches, recapture policy, and
host sanitization remain protected by the original regression suite.

## Facebook feed-post scope

- signed-in desktop Facebook Home Feed only;
- main feed post, author or Page identity, exposed timestamp/permalink, social
  context, engagement summary, avatar, and best-effort image/video preview;
- suggested and sponsored feed entries remain capturable and are marked in
  normalized presentation data instead of being silently removed;
- comment threads, Stories, Reels player feeds, Marketplace, notifications,
  Messenger, profile crawling, Page crawling, and Group crawling are outside
  the adapter boundary;
- no GraphQL interception, cookies, access tokens, raw response persistence, or
  source-side mutation;
- text can remain usable when media is unavailable;
- quiet-first capture and explicit foreground permission remain global policy.

Candidate discovery prefers semantic `feed`/`article` roles and the explicit
`Actions for this post by ...` boundary. A Reels action boundary is not a feed
post boundary. It does not depend on Facebook's obfuscated class names.
Selector mismatch, login required, feed shell, and a valid zero-addition result
remain distinct telemetry outcomes.

Facebook virtualizes its Home Feed and may keep only one tall gallery post in
the rendered frontier. The generic capture runtime therefore accepts a bounded
per-adapter scroll-step multiplier. Facebook uses `2x`; X and LinkedIn remain
at `1x`. Scroll count, timeout, restoration, and all other movement authority
remain global and bounded.

Evidence admission is modality-based rather than text-length-based. Every
adapter declares its supported evidence family and extracts normalized text,
media, attachments, and native identity. Generic Bridge admission accepts a
stable, attributable text, media, or attachment-bearing feed post and rejects
identity-only shells. This allows short-caption and media-led Facebook posts
without weakening X or LinkedIn capture, and it does not admit Stories or
Reels as top-level candidates.

An initial zero-block observation is not accepted as a normal result. The
generic Bridge runtime records bounded selector/readiness diagnostics and
consults the source catalog for recovery policy. Facebook opts into one
`reload_managed_once` recovery of its Bridge-owned quiet-capture tab. X and
LinkedIn do not opt in, shared user tabs are never reloaded, and a second empty
capture fails explicitly as `capture_empty` with the diagnostic receipt kept in
the run ledger.

Facebook v14 also owns a separate managed-load recovery declaration. When a
newly created or canonically reset Bridge-owned Facebook surface does not reach
Chrome's completed navigation state within 20 seconds, AkuBridge requests and
verifies cleanup of that surface before recreating it once. Recreation is
forbidden after a lease mismatch, an unconfirmed release, or a second timeout.
The retry stays in the configured Quiet background path and never authorizes
foreground recovery. Final failure is typed as navigation or cleanup failure,
and the Inbox retains the release-requested, released/reconciled, and focus
telemetry needed to distinguish a slow Facebook page from a leaked window.

## Media and privacy limits

Facebook CDN URLs can expire before Timeline retention. Preview v1 therefore
uses best-effort currently rendered URLs and reports unavailable media honestly;
it does not introduce a local byte cache. The Sidecar CSP explicitly permits
the adapter's bounded `fbcdn.net` and `fbsbx.com` media hosts so a valid captured
URL can be replayed in the local Timeline. Durable media caching is a separate
storage, cleanup, and privacy decision.

Facebook Home Feed can include audience-restricted material. AkuBrowser keeps
capture local, bounded, user-initiated, and read-only, but public distribution
still needs an independent legal/compliance review of Meta's current terms.
This document is an engineering contract, not legal advice:

- [Meta Terms of Service](https://www.facebook.com/legal/terms)
- [Meta Automated Data Collection Terms](https://www.facebook.com/legal/automated_data_collection_terms)

## Acceptance evidence

The implementation is accepted at the code and synthetic-runtime layer when:

1. all existing X media, avatar, video, link-card, background hydration, and
   response-evidence tests remain green;
2. LinkedIn adapter and permalink/continuation regression tests remain green;
3. the Facebook adapter passes Home Feed conformance for readiness, normalized
   evidence, social context, sponsorship marking, and canonical links;
4. generic Bridge core contains no source-name control-flow branches;
5. Sidecar registry, schema 7, dynamic UI, heartbeat, and session creation accept
   three registered sources;
6. development package verification and integration contracts agree on runtime
   revision `source-adapters-v84`; immutable published release manifests retain
   the revision of their uploaded artifacts.

Facebook adapter v17 also treats the current Home Feed header as an explicit
adapter responsibility. It resolves the author from bounded profile links
or the explicit post-action label before the post body and rejects presence
labels such as `Online status indicator Active`. It reconstructs Facebook's visually rendered relative
timestamp while excluding its absolutely positioned decoy glyphs. The generic
Bridge core continues to receive ordinary `author`, `timestampText`, and
estimated `publishedAt` fields; it does not contain Facebook DOM rules.
Post identity is normalized from direct `posts/pfbid`, legacy `story.php`, video/watch, or
carousel `set=pcb.<post-id>` evidence. Comment and tracking parameters are
removed before the canonical URL and platform id enter generic deduplication.
The legacy `story.php` route names ordinary feed-post permalinks; the separate
Facebook Stories surface (`/stories/`) remains outside this adapter.

A structural Home Feed card can be present without containing a capture-eligible
post, for example Facebook's private Memories promotion with only Send and Share
actions. Adapter v11 reports those cards separately from eligible post
candidates. The generic readiness contract keeps the bounded hydration wait,
then admits `feed_empty` into capture so scrolling can still discover a later
post without misreporting a selector regression.

A Home Feed video can expose no stable wrapper permalink while still exposing
an embedded `/reel/<id>` anchor. Adapter v11 accepts that anchor as the native
evidence destination for the already-admitted feed post; it does not discover
or capture the Reels player feed. Poster images beneath `/videos/` or `/reel/`
are typed as video previews, so the generic Timeline can display an explicit
video cue even when quiet capture cannot obtain a playback URL or a useful
poster frame. The native evidence link remains available for direct review.

Live Facebook acceptance still requires a signed-in user session and repeated
captures of ordinary, shared, Page, suggested, sponsored, image, and video
entries. A live selector or media gap is an adapter defect; it must not be
worked around by adding source-specific branches to generic orchestration.

Adapter v17 exports bounded candidate-admission diagnostics with each
snapshot. It distinguishes structural cards from capture-eligible and visible
posts and names the adapter-owned admission or rejection reason. AkuBridge only
sanitizes and transports this generic telemetry; AkuSidecar stores it and the
Update Inbox renders it collapsed. Counts are observations per snapshot, not
unique-post totals, so the run rollup uses maxima rather than summing repeated
DOM candidates.

Live telemetry showed that a bounded viewport scroll moved the Facebook
document frontier but remained inside one tall post; a longer settle repeated
the same candidate and only added latency. Adapter v17 instead asks the generic
capture runtime to advance to the next already-admitted candidate when one is
below the viewport. If none is available, the existing bounded viewport scroll
remains the fallback. X and LinkedIn retain their existing scroll behavior.

The adapter also owns classification of Facebook's explicit account-level
service outage surface. A signed-in tab at `/sorry.php?msg=account` with the
rendered `Account Temporarily Unavailable` heading reports typed
`source_unavailable` / `site_outage` readiness instead of falling through to a
selector or visibility error. Generic Bridge orchestration carries that typed
outcome without foreground recovery, and Sidecar retains results from healthy
sources as a warning-tone partial session. This is failure isolation, not an
outage detector: AkuBrowser never infers a global incident from an empty feed.
