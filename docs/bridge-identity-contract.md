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

The unpacked `development` identity is cryptographically pinned by the public
`key` in `AkuBridge/manifest.json`. Its Chrome extension ID is derived from that
key and must equal the registry entry. The key is public identity material, not
a signing secret; no private key is stored or required for Load unpacked.

## Development projection

`AkuSupervisor\scripts\dev.ps1 akusidecar` selects the `development` profile.
Because the manifest key pins the ID, Chrome assigns the same development ID
regardless of the directory used for Load unpacked or the machine running it.
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

The manifest key is also the runtime lifecycle marker. Automatic extension
reload/update and Chrome-startup events from the unpacked development build do
not contact the installed Native Messaging host and do not start the installed
AkuSidecar runtime. Development runtime ownership remains with `dev.ps1`; an
explicit extension action may still invoke `ensure_runtime` when the developer
intentionally tests the installed-runtime path.

The checked-in `AkuSidecar/config/sidecar.json` therefore contains no trusted
extension origin. Starting that base configuration without an explicit origin
fails closed.

## Production projection

`release/release-manifest.json` selects `bridgeIdentityProfile: production`.
It does not repeat the extension ID. Windows and macOS release packagers
resolve that profile through the registry and generate:

- exactly one packaged Sidecar `trustedExtensionOrigins` entry for portable and
  installed runtimes; and
- the Native Messaging host `allowed_origins` entry for companion installers.

Production builds reject any profile other than the release-selected Chrome
Web Store profile. An unsigned local installer may select another declared
profile such as `development`; arbitrary extension IDs are not accepted.
Production Chrome Web Store and portable packagers remove the development
`manifest.key` from their staged AkuBridge payload. Production identity remains
owned exclusively by the Chrome Web Store.

## Security invariant

AkuSidecar never trusts the first Bridge heartbeat, auto-discovers an extension
ID, or accepts a wildcard origin. Every running channel receives exactly one
origin derived from the registry before strict configuration validation.

