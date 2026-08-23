# Bridge identity and deployment-mode contract

Status: implemented, 15 August 2026.

> **Target routing:** this document records the currently shipped development,
> acceptance, Store, and offline identities. The approved installed-app target
> is defined in the [installed-app distribution contract](installed-app-distribution-contract.md)
> and is not implemented by this registry yet. Do not treat
> `production-store` as target production authority.

## One authority, four stable identities

`config/bridge-identities.json` is the only checked-in authority for AkuBridge
extension identities. Every extension ID is unique and identifies one delivery
lane:

| Profile | Distribution | Runtime lifecycle | User-facing mode |
| --- | --- | --- | --- |
| `development` | Load unpacked workspace | Manual, Supervisor-owned | Development |
| `acceptance` | Frozen Load unpacked package | Local acceptance installer | Stable candidate · 3B |
| `production-store` | Chrome Web Store | Managed companion runtime | Production · Web Store |
| `production-offline` | Self-contained offline ZIP | Bundled portable runtime | Production · Offline bundle |

Never copy an ID into Sidecar source configuration, Supervisor service
configuration, a native-host manifest, or release documentation. Packagers
resolve the selected profile and project its exact origin.

## Public identity keys

The three unpacked identities contain a checked-in RSA public key. The package
projector writes that public material to `manifest.key`, giving Load unpacked a
stable ID on every machine and from every directory. These public keys are not
code-signing secrets. No private key is required or distributed for Load
unpacked.

The checked-in AkuBridge manifest and `bridge-deployment.js` represent only the
`development` workspace. Acceptance and offline packagers stage a copy and run
`scripts/project-bridge-package-identity.mjs`; they never mutate the workspace
manifest in place. The Chrome Web Store projector removes `manifest.key`
because the Store owns the `production-store` identity.

## Trusted deployment metadata

AkuSidecar configuration carries locally projected deployment provenance:

- `mode`: `development`, `acceptance`, `production-store`, or
  `production-offline`;
- `runtimeInstallKind`: `workspace`, `installed`, or `portable`;
- `bridgeIdentityProfile`;
- release version, source-freeze tuple, and artifact ID when packaged.

Sidecar exposes this trusted local metadata through health/bootstrap APIs and
renders the mode pill. AkuBridge does not get to self-declare Sidecar ownership.
Sidecar still independently verifies the heartbeat's exact extension origin
against its single configured trusted origin.

Missing metadata remains runnable for backward compatibility but appears as
`Mode unknown`; release packagers and acceptance gates must reject it.

## Channel rules

- Development uses `AkuSupervisor\scripts\dev.ps1` and the `development`
  origin. Automatic Native Messaging lifecycle remains disabled.
- Step 3B uses the `acceptance` Bridge and an installer bound only to that
  origin. It is never uploaded.
- Web Store production uses `production-store`, removes the workspace key, and
  enables managed Native Messaging lifecycle.
- The offline ZIP uses `production-offline`, retains its dedicated public key,
  contains the load-unpacked AkuBridge payload plus portable AkuSidecar, and
  performs no Store or installer download.
- Store and offline editions must not run concurrently.

## Security invariants

- All four IDs are unique and validated from the registry.
- An unpacked package ID derives from the selected profile public key.
- AkuSidecar never trusts the first heartbeat, discovers an ID dynamically, or
  accepts a wildcard origin.
- A packaged runtime trusts exactly one projected Bridge origin.
- Environment and install kind come from local runtime packaging, not an
  extension message.
