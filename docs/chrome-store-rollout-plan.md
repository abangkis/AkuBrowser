# Chrome Store rollout plan

Status: sequential implementation plan, 28 July 2026.

The stages are intentionally gated. A later stage may not weaken an earlier
contract to make a demo pass.

## Stage 1 — Native Messaging and lifecycle contract

Deliver:

- public versus internal naming decision;
- Native Messaging request/response schema;
- install, startup, extension-update, runtime-update, and rollback lifecycle;
- trust, compatibility, filesystem, registration, and data boundaries.

Exit:

- contract and schema review complete;
- JSON and examples validate;
- no runtime behavior changed.

## Stage 2 — AkuBridge native runtime client

Deliver:

- `native-runtime-client.js`;
- deterministic client state machine;
- `status`, `ensure_runtime`, and `shutdown_if_idle` requests;
- `onInstalled`, `onStartup`, and action-click integration;
- simulated missing-host, ready, busy, incompatible, and failure tests.

Exit:

- existing capture suite remains green;
- no arbitrary native action or URL enters the client;
- missing host shows setup instead of a false runtime failure.

## Stage 3 — Minimal native host

Deliver:

- user-mode Go native host;
- framed JSON stdin/stdout protocol;
- exact Store-origin validation;
- `status` and `ensure_runtime`;
- start and health reconciliation for an already-installed AkuSidecar;
- structured stderr diagnostics.

Exit:

- schema conformance tests pass;
- unknown origins, actions, and protocol versions fail closed;
- Chrome can start the host and recover a stopped Sidecar.

## Stage 4 — Signed Windows companion installer

Deliver:

- user-scoped installer;
- stable native host and manifest paths;
- HKCU Native Messaging registration;
- uninstall and repair;
- production code-signing pipeline;
- bundled setup page guidance.

Exit:

- clean Windows user can install without Developer Mode;
- Store extension detects the host after installer completion;
- uninstall preserves user data unless separately requested.

## Stage 5 — Lifecycle acceptance

Implementation: automated acceptance and the production clean-machine evidence
runner live in `scripts/test-windows-runtime-lifecycle.ps1`; the execution
boundary and release-gate checklist live in
`docs/windows-runtime-lifecycle-acceptance.md`.

Deliver automated and clean-machine tests for:

- first install;
- Chrome restart;
- PC restart;
- stopped or crashed Sidecar;
- extension update;
- incompatible tuple;
- interrupted staging;
- failed candidate and rollback;
- runtime repair;
- uninstall and reinstall.

Exit:

- no terminal or manual unpacked-extension step is required;
- current data survives every non-reset path;
- failures remain recoverable and visibly typed.

## Stage 6 — Chrome Web Store readiness

Implementation: Store listing, privacy declarations, permission justification,
reviewer guidance, and submission gates live under `store/`; the public privacy
policy lives in `PRIVACY.md`. The checked-in readiness test and deterministic
ZIP builder live in `scripts/test-chrome-store-readiness.ps1` and
`scripts/build-chrome-store-package.ps1`.

Deliver:

- Store listing under `AkuBrowser`;
- icons, screenshots, description, support URL, and privacy policy;
- prominent disclosure and consent;
- permission justification;
- source-by-source host-permission minimization plan;
- reviewer instructions and test account/environment guidance.

Exit:

- submitted package contains all extension logic;
- companion requirement is disclosed;
- permissions match implemented features;
- privacy and data-use statements match runtime behavior.

## Stage 7 — Signed automatic runtime updater

Deliver:

- signed release manifest;
- fixed update origin and pinned verification key;
- staged download and verification;
- update-readiness handshake;
- candidate health gate;
- atomic activation;
- one-version rollback;
- bounded cleanup and update audit.

Exit:

- update succeeds from the prior supported release;
- tampered manifest, signature, checksum, or payload fails closed;
- active capture/reasoning blocks replacement;
- failed candidate returns to the known-good runtime;
- remote artifact and local active revision are independently verifiable.
