# AkuBrowser Contracts

This directory is the canonical, implementation-neutral contract source for the AkuBrowser workspace.

Runtime projects may vendor a contract snapshot so they remain independently buildable. `npm run check:contracts` verifies that vendored snapshots and protocol identifiers have not drifted.

The reasoning-result contract also carries knowledge-continuity identity. Every promoted item binds to one observed `evidenceKey`, a stable semantic `eventKey`, and an append-only `knowledgeDelta`. These fields allow StateStore implementations to move from SQLite to IndexedDB or a browser-native store without changing their meaning.
