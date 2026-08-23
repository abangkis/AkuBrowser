# Windows preview acceptance

AkuBrowser owns distribution. AkuSidecar and AkuBridge remain source component
repositories; AkuSupervisor and AkuSupervisorConformance are not packaged.

> **Historical preview acceptance.** This runbook validates the current
> Store/portable and pre-Store lanes, not the approved single-installer
> installed-app target. See the [installed-app distribution contract](installed-app-distribution-contract.md).

## Automated artifact gate

Run the complete Windows gate from AkuBrowser. It builds and validates both the
production publish lane and the separate pre-Store acceptance lane:

```powershell
.\scripts\run-windows-stable-gate.ps1 `
  -ReleaseVersion <release-version> `
  -SidecarVersion <sidecar-version> `
  -BrowserSha <full-AkuBrowser-SHA> `
  -BridgeSha <full-AkuBridge-SHA> `
  -SidecarSha <full-AkuSidecar-SHA> `
  -UpdatePublicKey $env:AKU_UPDATE_PUBLIC_KEY `
  -UpdateSigningPrivateKeyPath <secure-key-path>
```

The build gate validates the release tuple, executes Sidecar and Bridge tests,
builds a stripped Windows x64 Sidecar, verifies the pinned c2patool version and
SHA-256 before copying it beside the Sidecar, copies only the verified extension
payload, projects exactly the release-selected Chrome Web Store Bridge origin
from `config/bridge-identities.json`, includes the exact upstream c2patool MIT
and Apache-2.0 license texts, records source commits, generates per-file SHA-256 checksums, and
creates the portable ZIP. The smoke gate revalidates every checksum, requires
every runtime schema, capability-checks the discovered Codex runtime, starts
the packaged Sidecar with the release App Server provider and a fresh database
on a temporary loopback port, and verifies health, bootstrap, and embedded UI
delivery.

## Manual pre-Store clean-machine gate

This gate validates the frozen AkuBridge and runtime integration before Store
publication. It does not claim Chrome Web Store installation or production-ID
acceptance. The GitHub portable ZIP/bundle is covered by the automated artifact
gate above.

Execute the single reusable
[Windows clean-machine Step 3B](windows-clean-machine-3b.md) runbook. It owns the
ordered manual procedure, pass/fail rule, Installed apps success identifier,
known non-blockers, and release acceptance log. The detailed product-behavior
checks below supplement that runbook and should be exercised where applicable.

Never mix the two lanes. Store installers and update metadata in `publish/` use
the `production-store` identity. Portable offline bundles in `publish/` use the
separate `production-offline` identity. `acceptance/` uses the unpacked
`acceptance` identity and exists only for Step 3B. The root `release-kit.json`
records both allowlists and their hashes.

The production Chrome Web Store ID, Store-managed installation/update, and
versioned public Setup download are verified only after publication in Step 5
of the stable release checklist.

During the first onboarding check, confirm that the separate learning carousel
is visible below the sticky progress panel, advances automatically, supports
manual Previous/Next and direct slide selection, and disappears outside the
active first-run check. Its width must follow the configured Timeline stream,
and two consecutive slides must explain Capture/Evaluate followed by
Compose/Publish, using readable body text without claiming that every optional
model stage blocks publication. Confirm that
the Inbox semantic summary reports the local onboarding path without a model
invocation, that neither an AI Fast assessment nor an AI Deep job exists for
the onboarding session, and that unchecked items expose no AI badge. If a source reasoning run is deliberately made to fail before any
candidate validates, the recovery action must say **Update now again**;
the Sidecar must remain ready and the captured trace must remain inspectable.
After calibration completes, its More and Less choices must remain selected on
the corresponding Timeline cards; Neutral must remain unselected. A later
Timeline choice must replace the calibration state without duplicating its
learning signal. Update Inbox must show the same effective More/Less choices,
identify choices originating in calibration, omit Neutral, and use canonical
reconciled capture counts identical to Inspect Flow.

For first-run performance, confirm that every source records exactly one capture
round, no Acquisition Planning invocation is retained, and normal later checks
can still request a second round. Confirm **Learning panel** starts enabled and
appears during the first check, then automatically turns off when first-run
calibration completes. Enable it again while the Timeline is idle and confirm the
carousel appears immediately above the Timeline and remains visible during a later
check; disable it and confirm the panel and its timer stop without cancelling the
run.

When a completed session is still releasing its managed capture surface, confirm
the active update action remains briefly disabled and the header explains **Finishing
capture cleanup…**. If AkuBridge is temporarily incompatible or reconnecting, the
same location must explain **Waiting for AkuBridge to reconnect…** rather than
leaving a disabled action unexplained.

During an active check, confirm the progress panel explains that processing keeps
running while the user reviews other areas and offers direct actions for **View
Update Inbox** and **View Settings**. Moving to either view must not stop polling,
capture, or later Timeline composition; returning to Timeline must show current
progress rather than restarting the check.

Login remediation, installer signing, and silent Chrome extension installation
are outside the `0.7.9` acceptance boundary; the user installs AkuBrowser from
the Chrome Web Store. Codex
discovery is owned by the cross-platform AkuSidecar runtime probe and
capability-checks App Server.
