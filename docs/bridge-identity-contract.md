# Bridge identity contract

Status: implemented, 7 August 2026.

## One authority, two named identities

`config/bridge-identities.json` is the only checked-in authority for AkuBridge
extension identities. It declares two different identities rather than one
value that development overrides:

| Profile | Distribution | Purpose |
| --- | --- | --- |
| `development` | `unpacked` | Local AkuWorkspace development |
| `production` | `chrome-web-store` | Published AkuBrowser extension and runtime packages |

An extension ID must be changed in this registry, never in Sidecar source
configuration, Supervisor service configuration, release scripts, or native
host manifests.

## Development projection

`AkuSupervisor\scripts\dev.ps1 akusidecar` selects the `development` profile.
Before Supervisor starts AkuSidecar, the AkuWorkspace adapter projects the
registry origin into the active, local Supervisor service arguments as:

```text
--bridge-extension-origin chrome-extension://<development-id>/
```

The script prints the selected channel, distribution, extension ID, registry
path, and generated projection path at startup. The local `services.json` value
is generated runtime state, not another authority; manual edits are replaced
the next time `dev.ps1` runs. `-Rebuild` affects the Sidecar binary only and
does not change identity selection.

The checked-in `AkuSidecar/config/sidecar.json` therefore contains no trusted
extension origin. Starting that base configuration without an explicit origin
fails closed.

## Production projection

`release/release-manifest.json` selects `bridgeIdentityProfile: production`.
It does not repeat the extension ID. The Windows runtime installer resolves
that profile through the registry and generates both:

- the packaged Sidecar `trustedExtensionOrigins` entry; and
- the Native Messaging host `allowed_origins` entry.

Production builds reject any profile other than the release-selected Chrome
Web Store profile. An unsigned local installer may select another declared
profile with `-BridgeIdentityProfile development`; arbitrary extension IDs are
not accepted.

## Security invariant

AkuSidecar never trusts the first Bridge heartbeat, auto-discovers an extension
ID, or accepts a wildcard origin. Every running channel receives exactly one
origin derived from the registry before strict configuration validation.

