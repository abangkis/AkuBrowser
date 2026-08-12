# Instagram adapter assessment

Status: initial bounded vertical slice, 12 August 2026.

## Confirmed live feed contract

The signed-in Instagram web Home Feed exposes ordinary posts as `main article`
elements. A native post has a stable time anchor whose path is one of
`/p/<shortcode>/`, `/reel/<shortcode>/`, or legacy `/tv/<shortcode>/`; the
`time` element exposes an ISO `datetime`. Header profile links and profile
images provide the author and avatar. Caption text is rendered in bounded
`span[dir="auto"]` roots, while like and comment controls expose accessible SVG
labels and adjacent rendered counts.

The initial adapter admits only articles with a same-origin native permalink.
This intentionally rejects observed sponsored cards that had no native post
identity. Instagram is registered as a preselected source, consistent with X,
LinkedIn, and Facebook in both extension setup and new Sidecar profiles. Chrome
host authority remains revocable and is granted only after the user confirms
the selected sources.

## Media boundary

Rendered images use HTTPS hosts below `fbcdn.net` or `cdninstagram.com` and can
flow through the generic bounded media acquisition and post-processing path.
Profile pictures and small UI images are excluded before media normalization.

Observed video elements use MediaSource `blob:` URLs, have no poster attribute,
and therefore cannot safely become durable inline playback evidence from the
DOM alone. The adapter detects the expected video kind, but the initial slice
records media unavailability and preserves the native-post fallback. Inline
Instagram playback requires a later, source-specific response-evidence resolver
that extracts a progressive HTTPS media URL, binds it to the exact native
shortcode, and passes it through the existing generic media post processor and
Sidecar allowlist. Blob URLs, arbitrary page-provided URLs, and unbound CDN
responses must remain inadmissible.

## Performance and batching

Candidate discovery and semantic extraction are synchronous DOM reads bounded
to visible `main article` elements. Media acquisition retains the existing
single bounded retry and does not add a serial network request. Instagram uses
a 15-second hydration default (10-20 second configurable contract), but normal
progressive source scheduling can still overlap earlier-source reasoning. The
source remains on the generic local-frontier policy, so no Instagram-specific
batch scheduler dependency is introduced.

## Remaining validation

- run the extension and Sidecar contract suites with runtime revision
  `source-adapters-v91`;
- reload the local Bridge and verify a compatible four-source heartbeat;
- enable Instagram explicitly and execute one bounded capture against the live
  signed-in feed;
- use that captured evidence to design response-backed video resolution without
  weakening the generic media or source-identity contracts.
