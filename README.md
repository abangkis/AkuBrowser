# AkuBrowser

AkuBrowser is the primary product and integration project for a bounded, source-backed way to consume internet information without creating another infinite feed.

AkuBrowser evaluates only a bounded portion of each active source. Today it
filters that sample through generic materiality and evidence policy, then uses
local preference learning to reorder already-selected items. It does not claim
to inspect all source posts or surface only what the user wants. Preference
Eligibility Controller v2 now has explicit authority modes. The default may
fill one otherwise-unused per-source slot with a qualified candidate but cannot
replace or hide a selected item. Suppression is available only through a
separately gated experimental mode.

The parent directory is a neutral workspace containing four independent sibling repositories:

```text
AkuWorkspace/
├── AkuBrowser/     architecture, canonical contracts, integration checks
├── AkuBridge/      read-only Chrome extension
├── AkuSidecar/     local UI, jobs, SQLite, and reasoning providers
└── AkuSupervisor/  visible local-development lifecycle owner
```

## Repository boundary

- AkuBrowser owns product architecture and canonical inter-project contracts.
- AkuBridge and AkuSidecar own their runtime implementations and can be built independently.
- AkuSupervisor owns development process lifecycle but not AkuBrowser product settings.
- No runtime project imports source code from a sibling repository.
- Cross-project compatibility is verified through schema, bridge-runtime,
  adapter, and capability checks; repository package versions do not move in
  lockstep.

## Aggregate commands

Install AkuBrowser and AkuBridge dependencies once, ensure Go is available for
AkuSidecar, then run the read-only integration checks:

```powershell
npm run check
npm run doctor
npm run smoke:http
```

Load `..\AkuBridge` as an unpacked Chrome extension once. For normal
development, start the visible Supervisor and its registered Sidecar service:

```powershell
cd ..\AkuSupervisor
.\scripts\dev.ps1 akusidecar
```

Open `http://127.0.0.1:47821`. AkuSidecar now embeds its UI in the Go binary and
loads only the strict `config/sidecar.json` contract. Its Go watcher rebuilds
after source changes but defers replacement while a session is active.
`npm run dev` remains an integration convenience that launches the Go watcher,
but AkuSupervisor is the preferred full-workspace lifecycle owner.

The `codex-app-server` provider must run in a normal host context so it can own
the bundled `codex.exe` process and local Codex state. See the
[AkuSidecar development runbook](docs/sidecar-development-runbook.md).

`doctor` is read-only. It checks each component identity, AkuBridge
package/manifest alignment, the Sidecar health endpoint, SQLite integrity, the
latest sanitized AkuBridge heartbeat, declared Sidecar compatibility, and
source-adapter health aggregated from persisted observations. Component package
versions are reported but are intentionally independent. A runtime-revision or
adapter mismatch identifies an unpacked extension that has not been reloaded.
Chrome login and signed-in tab state remain explicit manual checks because the
local CLI does not inspect browser profile state.

After the one-time unpacked-extension bootstrap, reload source changes through
AkuSupervisor:

```powershell
..\AkuSupervisor\target\dev\aku-supervisor.exe bridge validate `
  --actor codex --request-id <unique-id>
```

Use the promoted stable binary path instead of `target\dev` outside active
Supervisor development.

The bridge diagnostics endpoint is `GET /api/operations/bridge/health`.
AkuBrowser posts a bounded capability heartbeat when the extension announces
readiness. The heartbeat is held in memory only and is associated with the
current Sidecar `instanceEpoch`. After a restart, the existing AkuBrowser tab
discards its prior Bridge-ready state and performs a fresh bounded handshake;
new runs never reuse readiness from the replaced process. The report exposes
adapter strategy, field coverage, frontier, source-event counts, lifecycle,
and restoration outcomes without raw post text, authors, URLs, cookies, or
tokens. `unavailable` means no current-process browser heartbeat and is a
Doctor warning rather than a process failure.

Gate 0B.3 lets a ReasoningProvider either finish after the initial bounded capture or request one deterministic, same-source, frontier-anchored follow-up. JobEngine—not the provider—owns the allowed action, position, scroll budget, and round limit.

Source-specific X and LinkedIn parsers feed a shared `social-post-v1`
capture-quality evaluator. AkuSidecar pre-authorizes at most one DOM-local
same-candidate retry, validates categorical reports and reason codes, removes
invalid candidates, and sends only complete or explicitly degraded evidence to
reasoning. See [the source-adapter quality architecture](docs/source-adapter-quality-design.md).

Gate 0 technical feasibility is passed. The active pilot now advances a checkpoint per source and mode, suppresses previously delivered exact evidence, and stores material updates as append-only knowledge-event versions.

See [the architecture reference](docs/aku-browser-architecture.md), [Selection Engine v1](contracts/selection-engine-v1.md), [Preference Runtime v2](contracts/preference-runtime-v2.md), and the active [Bridge Contract v2](contracts/bridge-contract-v2.md). Older contracts remain historical design evidence unless the Go rewrite explicitly adopts them.
