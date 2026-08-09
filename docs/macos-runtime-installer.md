# AkuBrowser Runtime macOS installer

Status: 0.7.9 implementation contract.

## Outcome

`AkuBrowserRuntimeSetup.pkg` is the macOS companion for the Chrome Web Store
extension. It installs a universal Intel and Apple-silicon Native Messaging
Host and AkuSidecar runtime for the current user. Chrome continues to own the
extension installation and update lifecycle.

The setup flow is deliberately user initiated:

1. AkuBrowser Setup checks `com.akubrowser.runtime`.
2. A missing host exposes **Install runtime**.
3. The action opens the versioned official
   `AkuBrowserRuntimeSetup-<version>-macos-universal.pkg` release asset.
4. The user opens the package and completes macOS Installer.
5. The user returns to Setup and selects **Check runtime**.
6. Chrome starts the registered host, which reconciles AkuSidecar and returns
   the bounded Native Messaging response.

The extension cannot silently download or execute native code.

## User-scoped layout

The package targets the current-user home installation domain:

- host: `~/Library/Application Support/AkuBrowser/host/AkuBrowserRuntimeHost`;
- adjacent authority manifest:
  `~/Library/Application Support/AkuBrowser/host/com.akubrowser.runtime.json`;
- Chrome registration:
  `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.akubrowser.runtime.json`;
- versioned runtime:
  `~/Library/Application Support/AkuBrowser/runtime/versions/<version>/`;
- active metadata: `~/Library/Application Support/AkuBrowser/runtime/current.json`;
- durable product data: `~/Library/Application Support/AkuBrowser/data`.

Both native-host manifests contain an absolute executable path and the one
exact production Chrome Web Store origin. Wildcards are forbidden. Ordinary
install, repair, update, and uninstall preserve `data`.

The release manifest selects a named Bridge identity profile. The installer
resolves that profile through `config/bridge-identities.json`, which is the
only checked-in authority for the exact extension ID. Published preview and
production packages reject any profile other than the release-selected Chrome
Web Store profile. An unsigned local candidate may instead select another
declared profile, but cannot accept an arbitrary extension ID.

No LaunchAgent is installed. Chrome starts the Native Messaging Host on demand;
the host starts AkuSidecar only for a bounded `ensure_runtime` request.

## Build trust

The production pipeline must:

- build universal `x86_64` and `arm64` host and Sidecar binaries;
- include the approved universal C2PA verifier;
- sign native executables with Developer ID Application;
- sign the package with Developer ID Installer;
- submit the package with `notarytool` and wait for acceptance;
- staple the notarization ticket;
- verify signatures, architectures, package contents, and SHA-256 output.

The future signed production mode fails closed when any signing identity, notarization profile,
or C2PA input is missing. The universal C2PA binary, upstream archive, and SBOM
digests are pinned in `release-manifest.json`. The build verifies its SHA-256,
version, and both architectures before packaging. `--unsigned-local-candidate`
produces an explicitly named development artifact that must never be published.
`--unsigned-preview-candidate` requires clean source trees, the production Store
extension ID, and the pinned universal C2PA binary. The `v0.7.9` stable
exception uses `--unsigned-stable-candidate`; its Installer welcome page
discloses that the stable package is unsigned and not notarized. It remains a
deliberate trust exception, not a substitute for the future Developer ID path.

## Build

Local structural candidate:

```sh
./scripts/build-macos-runtime-installer.sh \
  --c2pa-tool ../AkuSidecar/runtime/dev/macos-universal/c2patool \
  --bridge-identity-profile development \
  --unsigned-local-candidate \
  --allow-dirty
```

Public unsigned preview:

```sh
./scripts/build-macos-runtime-installer.sh \
  --c2pa-tool ../AkuSidecar/runtime/dev/macos-universal/c2patool \
  --unsigned-preview-candidate
```

Stable unsigned `v0.7.9` candidate:

```sh
./scripts/build-macos-runtime-installer.sh \
  --c2pa-tool ../AkuSidecar/runtime/dev/macos-universal/c2patool \
  --unsigned-stable-candidate
```

Production:

```sh
./scripts/build-macos-runtime-installer.sh \
  --c2pa-tool /secure/path/c2patool \
  --application-identity "Developer ID Application: Example (TEAMID)" \
  --installer-identity "Developer ID Installer: Example (TEAMID)" \
  --notary-profile AkuBrowserNotary \
  --update-public-key "$AKU_UPDATE_PUBLIC_KEY" \
  --update-signing-private-key /secure/path/update-signing-key.txt
```

## Linux boundary

The 0.7.9 Native Host owns platform-neutral runtime paths, executable names,
artifact identities, and update-manifest endpoints. Linux adapters resolve XDG
storage and `linux-x64` or `linux-arm64`, but Setup intentionally exposes no
Linux installer action in 0.7.9. Debian packages and their portable fallback
belong to the 0.7.10 release gate.
