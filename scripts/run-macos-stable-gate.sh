#!/usr/bin/env bash
set -euo pipefail

# Compatibility entry point. The stable Mac pass now stops at the
# Windows-signing handoff and never accepts a private update key.
browser_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$browser_root/scripts/run-macos-signing-request.sh" "$@"
