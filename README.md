# AkuBrowser

AkuBrowser is the primary product and integration project for a bounded, source-backed way to consume internet information without creating another infinite feed.

The parent directory is a neutral workspace containing three independent sibling repositories:

```text
AkuWorkspace/
├── AkuBrowser/   architecture, canonical contracts, integration checks
├── AkuBridge/    read-only Chrome extension
└── AkuSidecar/   local UI, jobs, SQLite, and reasoning providers
```

## Repository boundary

- AkuBrowser owns product architecture and canonical inter-project contracts.
- AkuBridge and AkuSidecar own their runtime implementations and can be built independently.
- No runtime project imports source code from a sibling repository.
- Cross-project compatibility is verified here through contract-drift checks.

## Aggregate commands

Install dependencies in each runtime repository first, then run:

```powershell
npm run check
npm run smoke:http
$env:AKU_REASONING_PROVIDER='codex-sdk'
npm run dev
```

Load `..\AkuBridge` as an unpacked Chrome extension and open `http://127.0.0.1:47821`.
AkuSidecar development keeps this single URL: Vite provides frontend HMR while Node automatically restarts backend changes in the same visible terminal.

Gate 0B.3 lets a ReasoningProvider either finish after the initial bounded capture or request one deterministic, same-source, frontier-anchored follow-up. JobEngine—not the provider—owns the allowed action, position, scroll budget, and round limit.

See [the architecture reference](docs/aku-browser-architecture.md) and [bridge contract v1](contracts/bridge-contract-v1.md).
