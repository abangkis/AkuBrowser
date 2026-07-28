# Chrome Web Store permission justification

## Required API permissions

| Permission | Current feature that requires it | Narrower boundary |
| --- | --- | --- |
| `alarms` | Wakes the bounded background dispatch/release pump after the MV3 worker sleeps. | One named AkuBrowser alarm; no browsing-history API. |
| `nativeMessaging` | Checks, starts, and reconciles the signed local AkuBrowser Runtime Host. | Fixed host `com.akubrowser.runtime`; no arbitrary native command. |
| `scripting` | Registers packaged source scripts after consent and injects the packaged capture bundle into an approved managed source tab when recovery is needed. | No remote code; source host permission must already be granted. |
| `storage` | Stores consent projection, runtime state, bounded X media/avatar evidence, and short-lived background coordination. | Local extension storage only; no `unlimitedStorage` or sync permission. |

The `tabs` permission is deliberately absent. AkuBrowser uses ordinary tab
creation/update methods and source-specific host authority; it does not request
blanket access to sensitive URL/title fields for unrelated tabs.

## Required host permissions

- `http://127.0.0.1:11122/*`
- `http://localhost:11122/*`

These two aliases reach only the local AkuBrowser companion runtime. They are
required for the product UI, health check, and authenticated Bridge API.

## Optional source host permissions

- `https://x.com/*`
- `https://www.linkedin.com/*`
- `https://www.facebook.com/*`
- `https://facebook.com/*`

All social hosts are optional, disabled by default, explained in-product, and
requested only from the setup-page consent button. Each source can be enabled or
revoked independently. Persistent source scripts are registered only after
Chrome confirms the matching host grant. Capture fails closed when the grant is
absent.

The optional patterns remain exact first-party hosts because Chrome host
permissions ignore URL paths. Registered content-script matches are narrower:
X home/status, LinkedIn feed/posts, and the Facebook home feed. Programmatic
recovery remains constrained by the selected source's exact host authority.

## Explicitly absent

AkuBrowser does not request `cookies`, `history`, `webRequest`, `debugger`,
`downloads`, `<all_urls>`, clipboard, geolocation, notifications, or remote-code
authority.
