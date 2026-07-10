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
