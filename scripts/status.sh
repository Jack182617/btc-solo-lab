#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/configs/miner.env}"
source "$ROOT_DIR/scripts/lib/miner-env.sh"

if [[ -f "$ENV_FILE" ]]; then
  config_keys=(
    LOG_DIR
    MINER_BIN
  )
  load_miner_env "$ENV_FILE" "${config_keys[@]}"
fi

MINER_BIN="${MINER_BIN:-vendor/cpuminer-multi/cpuminer}"
LOG_DIR="${LOG_DIR:-logs}"
MINER_BIN="$(miner_abs_path "$MINER_BIN" "$ROOT_DIR")"
LOG_DIR="$(miner_abs_path "$LOG_DIR" "$ROOT_DIR")"

if ! miner_require_file_under_root "MINER_BIN" "$MINER_BIN" "$ROOT_DIR"; then
  echo "Configured MINER_BIN is outside project root; status is limited." >&2
  MINER_BIN="$ROOT_DIR/vendor/cpuminer-multi/cpuminer"
fi
if ! miner_require_path_under_root "LOG_DIR" "$LOG_DIR" "$ROOT_DIR"; then
  echo "Configured LOG_DIR is outside project root; status is limited." >&2
  LOG_DIR="$ROOT_DIR/logs"
fi

echo "Miner process status:"
if ps_output="$(ps -ax -o pid,stat,comm,%cpu,%mem,rss,args 2>/dev/null)"; then
  if printf '%s\n' "$ps_output" | grep -F "$MINER_BIN" | grep -v grep | miner_redact_sensitive_args; then
    :
  else
    echo "No cpuminer process found."
  fi
else
  echo "Process list unavailable."
fi

echo
echo "Recent logs:"
if [[ -d "$LOG_DIR" ]]; then
  find "$LOG_DIR" -maxdepth 1 -type f -name 'miner-*.log' -print | while IFS= read -r log; do
    if modified="$(stat -f %m "$log" 2>/dev/null)" && [[ "$modified" =~ ^[0-9]+$ ]]; then
      :
    elif modified="$(stat -c %Y "$log" 2>/dev/null)" && [[ "$modified" =~ ^[0-9]+$ ]]; then
      :
    else
      modified=0
    fi
    printf '%s\t%s\n' "$modified" "$log"
  done | sort -n | tail -5 | cut -f2-
else
  echo "No logs directory."
fi
