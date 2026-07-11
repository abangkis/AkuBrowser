# Operational Diagnostics Contract v0

> Status: **AkuDoctor and extension package verification implemented**
> Date: **2026-07-12**

## AkuDoctor

AkuDoctor is a read-only workspace diagnostic. It verifies package/manifest version alignment, queries the visible Sidecar health endpoint, reads the declared provider capability manifest, and checks SQLite integrity through a local health endpoint. It reports `mutationsPerformed: false` and never prints the bridge token.

Browser profile state remains outside the CLI diagnostic boundary. Reloading an unpacked extension and confirming signed-in source tabs are explicit manual checks rather than hidden automation.

## Extension package verification

AkuBridge package verification resolves every Manifest V3 script and local service-worker import, requires package/manifest version equality, and emits per-file SHA-256 hashes plus an aggregate fingerprint. Verification does not create an archive or alter the installed extension.

Cross-repository contract checks also require AkuBrowser, AkuSidecar, AkuBridge, and the AkuBridge manifest to share one version.
