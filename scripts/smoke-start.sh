#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/configs/miner.env}"
SMOKE_SECONDS="${SMOKE_SECONDS:-15}"
REAL_START_SMOKE="${REAL_START_SMOKE:-0}"
REAL_START_CONFIRM="${REAL_START_CONFIRM:-}"

if [[ ! "$SMOKE_SECONDS" =~ ^[0-9]+$ ]] || (( SMOKE_SECONDS < 5 || SMOKE_SECONDS > 60 )); then
  echo "SMOKE_SECONDS must be 5..60." >&2
  exit 1
fi

if [[ "$REAL_START_SMOKE" != "0" && "$REAL_START_SMOKE" != "1" ]]; then
  echo "REAL_START_SMOKE must be 0 or 1." >&2
  exit 1
fi

if [[ "$REAL_START_SMOKE" != "1" ]]; then
  echo "Dry smoke only; miner will not start."
  DRY_RUN=1 REQUIRE_PREFLIGHT=0 "$ROOT_DIR/scripts/run-solo-miner.sh"
  "$ROOT_DIR/scripts/status.sh"
  exit 0
fi

if [[ "$REAL_START_CONFIRM" != "REAL_MAINNET_CPU_MINING" ]]; then
  echo "REAL_START_SMOKE=1 requires REAL_START_CONFIRM=REAL_MAINNET_CPU_MINING." >&2
  exit 1
fi

LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
mkdir -p "$LOG_DIR"
log_file="$LOG_DIR/miner-smoke-$(date -u +"%Y%m%dT%H%M%SZ")-$$.log"

echo "Running real Bitcoin mainnet CPU mining smoke for ${SMOKE_SECONDS}s."
TIME_LIMIT_SECONDS="$SMOKE_SECONDS" LOG_FILE="$log_file" "$ROOT_DIR/scripts/run-solo-miner.sh"

if ! grep -Eq "Starting real Bitcoin mainnet solo mining|stratum|Stratum|job|hashrate|thread" "$log_file"; then
  echo "Smoke log did not contain expected miner startup markers: $log_file" >&2
  exit 1
fi

if "$ROOT_DIR/scripts/status.sh" | grep -F "No cpuminer process found." >/dev/null 2>&1; then
  echo "Real smoke complete; no cpuminer process remains."
else
  echo "Smoke ended, but cpuminer process state is not clean." >&2
  "$ROOT_DIR/scripts/status.sh" >&2 || true
  exit 1
fi

echo "Smoke log: $log_file"
