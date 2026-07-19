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
builds a stripped Windows x64 Sidecar, copies only the verified extension
payload, records source commits, generates per-file SHA-256 checksums, and
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
7. run Check for updates and inspect captured, evaluated, and selected evidence;
8. stop with Ctrl+C, restart, and confirm local state persists;
9. reset AkuBrowser and confirm onboarding starts from zero without classifying pre-reset native items as resurfaced;
10. confirm no AkuSupervisor process or development workspace path is required.

During the first onboarding check, confirm that the separate learning carousel
is visible below the sticky progress panel, advances automatically, supports
manual Previous/Next and direct slide selection, and disappears outside the
active first-run check. Its width must follow the configured Timeline stream,
and one slide must explain Capture, Evaluate, Compose, and Publish without
claiming that every optional model stage blocks publication. Confirm that
the Inbox semantic summary reports the local onboarding path without a model
invocation. If a source reasoning run is deliberately made to fail before any
candidate validates, the recovery action must say **Check for updates again**;
the Sidecar must remain ready and the captured trace must remain inspectable.
After calibration completes, its More and Less choices must remain selected on
the corresponding Timeline cards; Neutral must remain unselected. A later
Timeline choice must replace the calibration state without duplicating its
learning signal.

Login remediation, installer signing, and automatic Chrome extension
installation are outside the `0.7.0-preview.2` acceptance boundary. Codex
discovery is owned by the cross-platform AkuSidecar runtime probe and
capability-checks App Server.
