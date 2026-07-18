# Facebook source adapter contract

Status: implemented for local preview development, 19 July 2026.

## Product boundary

Facebook is an available AkuBrowser source behind the same bounded, read-only
pipeline used by X and LinkedIn:

`bounded capture -> Candidate Evaluation -> preference selection -> global composition -> semantic event resolution -> AI Fast Detection -> Timeline -> async AI Deep Detection`

AkuBrowser shows what the signed-in source feed presents, then gives the user
authority over what remains in their finite Timeline. Facebook does not receive
a separate ranking, preference, semantic-event, AI Detector, Inbox, retention,
or correction path. More/Less feedback and selection correction use the same
source-bound evidence contract.

Facebook is available in onboarding and Settings but is not preselected. The
fresh release default remains X plus LinkedIn. Enabling Facebook requires an
existing signed-in Chrome session; AkuBrowser does not automate login.

## Generic source architecture

AkuSidecar owns one source registry. It supplies source identity, display
metadata, default activation, adapter versions, optional capabilities, and
source behavior metadata. `Source.Valid`, Settings validation, heartbeat
compatibility, onboarding controls, Timeline presentation, and database source
definitions consume this registry. SQLite schema 6 references the seeded
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

## Facebook v1 scope

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

Candidate discovery prefers semantic `feed`/`article` roles and independent
post-action evidence. It does not depend on Facebook's obfuscated class names.
Selector mismatch, login required, feed shell, and a valid zero-addition result
remain distinct telemetry outcomes.

## Media and privacy limits

Facebook CDN URLs can expire before Timeline retention. Preview v1 therefore
uses best-effort currently rendered URLs and reports unavailable media honestly;
it does not introduce a local byte cache. Durable media caching is a separate
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
5. Sidecar registry, schema 6, dynamic UI, heartbeat, and session creation accept
   three registered sources;
6. package verification and distribution contracts agree on runtime revision
   `source-adapters-v62`.

Live Facebook acceptance still requires a signed-in user session and repeated
captures of ordinary, shared, Page, suggested, sponsored, image, and video
entries. A live selector or media gap is an adapter defect; it must not be
worked around by adding source-specific branches to generic orchestration.
