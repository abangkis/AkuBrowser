# AkuBrowser

AkuBrowser is the primary product and integration project for a bounded, source-backed way to consume internet information without creating another infinite feed.

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

Install dependencies in each Node repository once, then run the read-only
integration checks:

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

Open `http://127.0.0.1:47821`. Configure provider, models, efforts, timeout,
sources, and capture budgets in AkuBrowser Settings; do not set
`AKU_REASONING_PROVIDER` for normal startup. Vite provides frontend HMR while
Node automatically restarts backend changes inside the supervised process tree.
`npm run dev` remains an integration convenience that delegates directly to
AkuSidecar, but it is not the preferred full-workspace lifecycle path.

When the Codex SDK provider is active, the Sidecar process must be started from a normal host process context so it can spawn Codex CLI. See the [AkuSidecar development runbook](docs/sidecar-development-runbook.md); an ordinary sandboxed command can appear healthy yet fail every reasoning phase with `spawn EPERM`.

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

The bridge diagnostics endpoint is `GET /api/operations/bridge/health`. AkuBrowser posts a bounded capability heartbeat when the extension announces readiness. The heartbeat is held in memory only; the report exposes adapter strategy, field coverage, frontier, source-event counts, lifecycle, and restoration outcomes without raw post text, authors, URLs, cookies, or tokens. `unavailable` means no current browser heartbeat and is reported as a Doctor warning rather than a process failure.

Gate 0B.3 lets a ReasoningProvider either finish after the initial bounded capture or request one deterministic, same-source, frontier-anchored follow-up. JobEngine—not the provider—owns the allowed action, position, scroll budget, and round limit.

Source-specific X and LinkedIn parsers feed a shared `social-post-v1`
capture-quality evaluator. AkuSidecar pre-authorizes at most one DOM-local
same-candidate retry, validates categorical reports and reason codes, removes
invalid candidates, and sends only complete or explicitly degraded evidence to
reasoning. See [the source-adapter quality architecture](docs/source-adapter-quality-design.md).

Gate 0 technical feasibility is passed. The active pilot now advances a checkpoint per source and mode, suppresses previously delivered exact evidence, and stores material updates as append-only knowledge-event versions.

See [the architecture reference](docs/aku-browser-architecture.md), [Unified Session Experiment Contract v0](contracts/unified-session-experiment-v0.md), [bridge contract v1](contracts/bridge-contract-v1.md), and the [2026-07-14 release checkpoint](docs/release-checkpoint-2026-07-14.md).
