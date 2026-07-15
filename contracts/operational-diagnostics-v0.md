# Operational Diagnostics Contract v0

> Status: **AkuDoctor, compatibility diagnostics, and extension verification implemented**
> Date: **2026-07-14**

## AkuDoctor

AkuDoctor is a read-only workspace diagnostic. It reports independent component
identities, verifies AkuBridge package/manifest alignment, queries the visible
Sidecar health endpoint, checks SQLite integrity, and compares the live bridge
heartbeat against Sidecar's declared runtime, adapter, action, and minimum
extension compatibility requirements. It reports `mutationsPerformed: false`
and never prints the bridge token.

Browser profile state remains outside the CLI diagnostic boundary. Confirming
signed-in source tabs is an explicit manual check. After the one-time unpacked
extension bootstrap, AkuBridge source changes are loaded through AkuSupervisor
`bridge validate` or `bridge reload`; ordinary Chrome control is not the
recommended reload path.

## Extension package verification

AkuBridge package verification resolves every Manifest V3 script and local service-worker import, requires package/manifest version equality, and emits per-file SHA-256 hashes plus an aggregate fingerprint. Verification does not create an archive or alter the installed extension.

Cross-repository contract checks require synchronized canonical schemas,
AkuBridge package/manifest identity, a Bridge version at or above Sidecar's
minimum, the exact declared runtime revision and adapter versions, and every
required capability action. AkuBrowser, AkuSidecar, and AkuBridge package
versions are intentionally independent.

AkuSidecar diagnostics also expose the current non-secret `instanceEpoch` and
the epoch associated with the accepted heartbeat. `unavailable` after a
Sidecar restart is a readiness state, not evidence that the extension needs an
update. A present heartbeat that fails the compatibility tuple is reported
separately as incompatible. Persisted or last-known heartbeat data may be shown
for historical diagnosis but must never authorize a new run.
