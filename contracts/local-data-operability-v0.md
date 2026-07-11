# Local Data Operability Contract v0

> Status: **Health, backup, export, and retention preview implemented**
> Date: **2026-07-12**

## Boundary

AkuSidecar local-data tooling must remain explicit, filesystem-local, and reversible. No maintenance command may upload data, expose the bridge token, or delete pilot state.

## Operations

- `health` runs SQLite integrity and foreign-key checks, reports journal mode, size, and bounded table counts.
- `backup` uses SQLite `VACUUM INTO`, refuses existing targets, and validates the created database before reporting success.
- `export` writes a new analysis JSON document containing runs, results, candidate assessments, preference feedback, and reasoning telemetry. It declares that source content is present and raw browser observations are absent.
- `retention-preview` reports age-based counts only. It has no deletion path and labels feedback-bearing or promoted runs as protected.

Backup and export require an explicit new output path. Neither operation runs automatically from the dashboard or during startup. Test coverage uses temporary databases rather than the active pilot database.
