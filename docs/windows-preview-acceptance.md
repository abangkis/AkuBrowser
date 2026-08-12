# Windows preview acceptance

AkuBrowser owns distribution. AkuSidecar and AkuBridge remain source component
repositories; AkuSupervisor and AkuSupervisorConformance are not packaged.

## Automated artifact gate

Run from AkuBrowser:

```powershell
.\scripts\build-windows-preview.ps1
.\scripts\test-windows-preview.ps1
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

1. start from a Windows machine or account with no AkuBrowser installation or database;
2. install Codex App, sign in locally, and confirm it is ready;
3. confirm Chrome is signed in to every source that will be enabled (X, LinkedIn, Facebook, or Instagram);
4. build the frozen package with `scripts/build-prestore-bridge-package.ps1`,
   extract it anywhere, load that directory through **Load unpacked**, and
   verify Chrome assigns the manifest-key-pinned `development` ID declared by
   `config/bridge-identities.json`;
5. open Setup and confirm it initially detects that the companion runtime is missing;
6. install the matching staging runtime built with
   `-BridgeIdentityProfile development -UnsignedLocalCandidate`, record the
   actual SmartScreen/antivirus behavior, then select **Check runtime**;
7. select **Check Codex**, confirm Codex is detected, and explicitly confirm that
   sign-in and prerequisites are complete;
8. grant only the intended source permissions, open AkuBrowser, complete
   onboarding and calibration, and run one full **Update now**;
9. inspect captured, evaluated, and selected evidence, then test Chrome restart,
   Windows restart, runtime stop/start, installer repair, uninstall, and reinstall;
10. confirm local data persists where required and that setup exposes recoverable
    actions for every deliberately interrupted state;
11. reset AkuBrowser and confirm onboarding starts from zero without classifying
    pre-reset native items as resurfaced; and
12. confirm no portable AkuBrowser ZIP, terminal launcher, or AkuSupervisor
    process is required.

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
