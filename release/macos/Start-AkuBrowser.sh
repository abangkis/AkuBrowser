#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./Start-AkuBrowser.sh [options]

Options:
  --codex-path <path>       Explicit Codex executable
  --data-directory <path>   User data directory (default: ~/Library/Application Support/AkuBrowser/data)
  --port <port>             Loopback port (default: 11122; AkuBridge expects this port)
  --provider <provider>     Reasoning provider override (for local deterministic smoke tests only)
  --diagnose-codex          Probe Codex and exit without starting AkuBrowser
  --no-open                 Do not open the browser automatically
  -h, --help                Show this help
EOF
}

bundle_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sidecar_path="$bundle_root/AkuSidecar"
config_path="$bundle_root/config/sidecar.json"
release_path="$bundle_root/release-manifest.json"
codex_path="${AKU_CODEX_PATH:-}"
data_directory="${HOME}/Library/Application Support/AkuBrowser/data"
port=11122
provider=""
no_open=0
diagnose_codex=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --codex-path)
      [[ $# -ge 2 ]] || die "--codex-path requires a value"
      codex_path="$2"
      shift 2
      ;;
    --data-directory)
      [[ $# -ge 2 ]] || die "--data-directory requires a value"
      data_directory="$2"
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || die "--port requires a value"
      port="$2"
      shift 2
      ;;
    --provider)
      [[ $# -ge 2 ]] || die "--provider requires a value"
      provider="$2"
      shift 2
      ;;
    --diagnose-codex)
      diagnose_codex=1
      shift
      ;;
    --no-open)
      no_open=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

for required in "$sidecar_path" "$config_path" "$release_path"; do
  [[ -f "$required" ]] || die "AkuBrowser bundle is incomplete: $required"
done

if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
  die "port must be between 1 and 65535"
fi

version="$(/usr/bin/plutil -extract version raw -o - "$release_path")"
browser_url="http://127.0.0.1:${port}"
health_url="${browser_url}/api/health"

probe_codex() {
  local probe_file
  probe_file="$(mktemp "${TMPDIR:-/tmp}/akubrowser-codex-probe.XXXXXX.json")"
  trap 'rm -f -- "$probe_file"' RETURN
  if [[ -n "$codex_path" ]]; then
    "$sidecar_path" --discover-codex --codex-path "$codex_path" > "$probe_file" || true
  else
    "$sidecar_path" --discover-codex > "$probe_file" || true
  fi
  local status
  status="$(/usr/bin/plutil -extract status raw -o - "$probe_file" 2>/dev/null || true)"
  if [[ "$status" != "ok" ]]; then
    echo "AkuBrowser could not find a compatible Codex App Server runtime." >&2
    cat "$probe_file" >&2
    echo "Install and sign in to Codex App, or set AKU_CODEX_PATH / --codex-path." >&2
    return 1
  fi
  /usr/bin/plutil -p "$probe_file"
  codex_path="$(/usr/bin/plutil -extract executable raw -o - "$probe_file")"
}

if [[ "$diagnose_codex" -eq 1 ]]; then
  [[ "$provider" != "deterministic" ]] || die "--diagnose-codex cannot be combined with --provider deterministic"
  probe_codex
  echo "Codex runtime: $codex_path"
  exit 0
fi

if [[ "$provider" == "" || "$provider" == "codex-app-server" ]]; then
  probe_codex || exit 2
  echo "Codex runtime: $codex_path"
elif [[ "$provider" == "deterministic" ]]; then
  echo "Reasoning provider: deterministic (local smoke/test mode)"
else
  die "unsupported provider override: $provider"
fi

if existing_health="$(/usr/bin/curl -fsS --max-time 2 "$health_url" 2>/dev/null)"; then
  existing_version="$(printf '%s' "$existing_health" | /usr/bin/plutil -extract version raw -o - - 2>/dev/null || true)"
  existing_status="$(printf '%s' "$existing_health" | /usr/bin/plutil -extract status raw -o - - 2>/dev/null || true)"
  if [[ "$existing_status" == "ok" && "$existing_version" == "$version" ]]; then
    echo "AkuBrowser $version is already running at $browser_url"
    if [[ "$no_open" -eq 0 ]]; then /usr/bin/open "$browser_url"; fi
    exit 0
  fi
  die "port $port is already owned by a different Sidecar or service"
fi

mkdir -p "$data_directory"
database_path="$data_directory/aku-sidecar.db"
sidecar_args=(--config "$config_path" --database "$database_path" --port "$port")
if [[ -n "$codex_path" ]]; then sidecar_args+=(--codex-path "$codex_path"); fi
if [[ -n "$provider" ]]; then sidecar_args+=(--provider "$provider"); fi

echo "Starting AkuBrowser $version"
echo "UI: $browser_url"
echo "Data: $database_path"
echo "Press Ctrl+C to stop AkuBrowser."

"$sidecar_path" "${sidecar_args[@]}" &
sidecar_pid=$!
cleanup() {
  local child_pid="${sidecar_pid:-}"
  sidecar_pid=""
  if [[ -n "$child_pid" ]] && kill -0 "$child_pid" 2>/dev/null; then
    kill -TERM "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
  fi
}
handle_signal() {
  cleanup
  exit 0
}
trap cleanup EXIT
trap handle_signal INT TERM

healthy=0
for _ in $(seq 1 80); do
  if ! kill -0 "$sidecar_pid" 2>/dev/null; then
    wait "$sidecar_pid" || true
    die "AkuSidecar exited before becoming healthy"
  fi
  health="$(/usr/bin/curl -fsS --max-time 1 "$health_url" 2>/dev/null || true)"
  status="$(printf '%s' "$health" | /usr/bin/plutil -extract status raw -o - - 2>/dev/null || true)"
  if [[ "$status" == "ok" ]]; then
    healthy=1
    break
  fi
  sleep 0.25
done
(( healthy == 1 )) || die "AkuSidecar did not become healthy within 20 seconds"

if [[ "$no_open" -eq 0 ]]; then
  /usr/bin/open "$browser_url"
fi

set +e
wait "$sidecar_pid"
status=$?
set -e
trap - INT TERM EXIT
exit "$status"
