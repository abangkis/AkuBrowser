# RC9 installed-app acceptance on an existing Windows account

Status: **local installed-app retest passed for startup and four sources; clean-machine and capture-split gates remain open**. This was performed on the existing `Force` Windows account after the RC8 installation had been removed, with its database and capture profile preserved. It is not an independent clean Windows account or VM.

## Frozen candidate

| Item | Value |
| --- | --- |
| Tag | `v0.9.0-rc.9` |
| Installer | `AkuBrowserSetup-0.9.0-windows-x64.exe` |
| Installer SHA-256 | `eb251704166d0e8261549794090adfbc507a6ea7ecf66fe9e0ff28c83ef94cd2` |
| AkuBrowser source | `fb445b230762d90f9caeaa25270ac3e935427e7b` |
| AkuSidecar source | `05e80232a04f62fd289588639741008f0a16ebf2` |
| AkuBridge source | `62fd01b03c2dc2dc41327f37ddcdcdb14bcf1346` |
| Product / Sidecar / Bridge | `0.9.0` / `0.9.0` / `0.9.2` |
| Trust state | unsigned |

The source reconciliation check passed outside the sandbox, followed by the installed-app tuple test, installer structure test, and checksum comparison. The first sandbox check failed only because the launcher tests could not access the Windows temporary directory; the same gate passed when rerun on the normal host. The pinned Chromium was `152.0.7977.54`; the selected project-local c2patool was `0.26.60` and matched the release manifest's SHA-256.

## Existing-account installation and source update

- Before installation, the preserved installed-app database SHA-256 was `3e4620385cd635e68356590afbe7d0c33eb519c195c5ef998436af9e684e6ca4`. A byte-verified copy was kept under the local ignored RC9 test directory. The dev Sidecar was gracefully stopped and its exact two reader-host registry values were backed up and temporarily removed.
- Silent installation completed. The installed manifest named the three source commits above. The installed launcher `--verify-only` exited 0; normal startup created the installed launcher, Sidecar, and pinned Chromium processes. Sidecar `/api/health` reported `ok`, version `0.9.0`, database `healthy`; Bridge reported `healthy` and compatible.
- The prior Timeline still had seven items and its earlier partial update receipt when RC9 opened, establishing preservation of the RC8 database through this same-version installation. One RC9 update, `session_776bff771497583f221a97ffe015c884`, completed **X, LinkedIn, Facebook, and Instagram** without a source error. The Facebook RC8 failure preceded completion of the profile's two-factor login flow; this retest supports an authentication-timing explanation, not an adapter fix.
- Runtime update readiness returned `ready: true`, reason `idle`. Cooperative shutdown returned HTTP 202, and both installed launcher and Sidecar exited. Ordinary silent uninstall exited 0 and removed the program directory and installed reader-host registrations while preserving the database and capture profile. The database SHA-256 after the new update and uninstall was `969e88864c03bf25d370fb1abc5670016e6e062b1c694df8df19bf72848641a8`.
- The dev reader-host registration was restored to `AkuSidecar/runtime/dev/com.akubrowser.reader_activation.json` for Chrome and Chromium. AkuSupervisor started `akusidecar` again and reported `running/healthy`; the dev API reported version `0.9.0`, database healthy, and Bridge healthy/compatible.

## Limits

The user reported removing the temporary Avast exception before this test, but the Avast configuration was not independently readable. The local startup success is therefore not independent proof of unsigned launch on another Windows machine. The installed Chromium shell was launched but its rendered UI was not visually inspected. This test did not remeasure repeated split-capture focus containment, exercise explicit full reset, or prove rollback to an older database schema. The packaged Launcher and Sidecar SHA-256 match RC8, so RC9 has no installed-app code fix for the RC8 Avast behavior. An independent clean-machine fresh install remains open.
