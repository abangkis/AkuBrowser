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
payload, includes the exact upstream c2patool MIT and Apache-2.0 license texts,
records source commits, generates per-file SHA-256 checksums, and
creates the portable ZIP. The smoke gate revalidates every checksum, requires
every runtime schema, capability-checks the discovered Codex runtime, starts
the packaged Sidecar with the release App Server provider and a fresh database
on a temporary loopback port, and verifies health, bootstrap, and embedded UI
delivery.

## Manual clean-machine gate

Before publishing a preview artifact, test the extracted ZIP without
AkuSupervisor:

1. start from a machine or Windows account with no AkuBrowser database;
2. confirm Codex App is installed and locally signed in, then run
   `Start-AkuBrowser.ps1 -DiagnoseCodex`;
3. confirm Chrome is signed in to every source that will be enabled (X, LinkedIn, or Facebook);
4. load the bundled AkuBridge directory through Chrome Developer mode;
5. run `.\Start-AkuBrowser.ps1` from PowerShell (`Start-AkuBrowser.cmd` is the fallback);
6. complete onboarding and calibration;
7. run **Update now** with Auto Update either enabled or disabled; also use **Prepare batch now** and **Load latest batch**; inspect captured, evaluated, and selected evidence;
8. stop with Ctrl+C, restart, and confirm local state persists;
9. reset AkuBrowser and confirm onboarding starts from zero without classifying pre-reset native items as resurfaced;
10. after onboarding is complete, restart or temporarily delay AkuSidecar and refresh the page; the Timeline must remain in a restoring state until bootstrap succeeds and source onboarding must not reappear. Only Full reset may intentionally expose onboarding again;
11. confirm no AkuSupervisor process or development workspace path is required.

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

Login remediation, installer signing, and automatic Chrome extension
installation are outside the `0.7.9` acceptance boundary. Codex
discovery is owned by the cross-platform AkuSidecar runtime probe and
capability-checks App Server.
