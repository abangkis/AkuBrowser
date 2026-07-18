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
3. confirm Chrome is signed in to X and LinkedIn;
4. load the bundled AkuBridge directory through Chrome Developer mode;
5. run `Start-AkuBrowser.cmd`;
6. complete onboarding and calibration;
7. run Check for updates and inspect captured, evaluated, and selected evidence;
8. stop with Ctrl+C, restart, and confirm local state persists;
9. reset AkuBrowser and confirm onboarding starts from zero; and
10. confirm no AkuSupervisor process or development workspace path is required.

Login remediation, installer signing, and automatic Chrome extension
installation are outside the `0.7.0-preview.1` acceptance boundary. Codex
discovery is owned by the cross-platform AkuSidecar runtime probe and
capability-checks App Server.
