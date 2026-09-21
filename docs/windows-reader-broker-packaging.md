# Windows reader activation broker packaging

The Windows installed-app tuple includes a separately identified UI broker:
`aku-reader-broker.exe`, `ui-reader-broker/`, and
`com.akubrowser.reader_activation.json`. Its only allowed native-messaging
origin is `chrome-extension://dlibmmlopdahibfniinemhnghlifiple/`.
AkuBridge and the transitional `com.akubrowser.runtime` host are not granted
access to activation.

The helper manifest uses the sibling executable name, which Windows native
messaging resolves relative to the manifest directory. This keeps all tuple
files immutable and hashed across arbitrary install locations. The per-user
Chrome and Chromium registry values point to the absolute manifest path.

The installer checks for conflicting registrations before extracting files,
registers only this host, and verifies both registry values before activating
the tuple. A development or alternate installation registration outside the
selected installation's runtime tree causes a visible installation failure;
the installer does not silently replace it. Uninstall removes each registration
only when its value still equals this version's exact installed manifest path.

The builder verifies and copies the three UI extension files and builds the
helper from `AkuSidecar/cmd/aku-reader-broker`. All files enter the existing
payload size/hash manifest. The artifact verifier checks the host name,
relative helper path, exact sole extension origin, and required files.
Packaging or syntax verification does not register the host or launch it.

The feature remains gated to the Windows split UI at runtime. Source login
state stays in the existing capture profile; the broker neither receives nor
copies that profile. Live validation must verify direct native-host launch,
foreground readback, and background containment on the shipped Chromium.
