#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/configs/miner.env}"
source "$ROOT_DIR/scripts/lib/miner-env.sh"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing config: $ENV_FILE" >&2
  echo "Create it from configs/miner.env.example first." >&2
  exit 1
fi
miner_harden_env_permissions "$ENV_FILE"

config_keys=(
  BTC_ADDRESS
  WORKER_NAME
  POOL_HOST
  POOL_PORT
  POOL_PASSWORD
  ALGO
  THREADS
  CPULIMIT_PERCENT
  CPULIMIT_INCLUDE_CHILDREN
  NICE_LEVEL
  REQUIRE_AC_POWER
  REQUIRE_PREFLIGHT
  ALLOW_UNLIMITED_RUN
  ALLOW_MULTI_THREAD
  THROTTLE_MODE
  DUTY_ACTIVE_SECONDS
  DUTY_IDLE_SECONDS
  TIME_LIMIT_SECONDS
  LOG_DIR
  LOG_RETENTION
  LOG_FILE
  DRY_RUN
  MINER_BIN
)

load_miner_env "$ENV_FILE" "${config_keys[@]}"

BTC_ADDRESS="${BTC_ADDRESS:-}"
WORKER_NAME="${WORKER_NAME:-mac-cpu}"
POOL_HOST="${POOL_HOST:-solo.ckpool.org}"
POOL_PORT="${POOL_PORT:-3333}"
POOL_PASSWORD="${POOL_PASSWORD:-x}"
ALGO="${ALGO:-sha256d}"
THREADS="${THREADS:-1}"
CPULIMIT_PERCENT="${CPULIMIT_PERCENT:-10}"
CPULIMIT_INCLUDE_CHILDREN="${CPULIMIT_INCLUDE_CHILDREN:-1}"
NICE_LEVEL="${NICE_LEVEL:-20}"
REQUIRE_AC_POWER="${REQUIRE_AC_POWER:-1}"
REQUIRE_PREFLIGHT="${REQUIRE_PREFLIGHT:-1}"
ALLOW_UNLIMITED_RUN="${ALLOW_UNLIMITED_RUN:-0}"
ALLOW_MULTI_THREAD="${ALLOW_MULTI_THREAD:-0}"
THROTTLE_MODE="${THROTTLE_MODE:-duty-cycle}"
DUTY_ACTIVE_SECONDS="${DUTY_ACTIVE_SECONDS:-1}"
DUTY_IDLE_SECONDS="${DUTY_IDLE_SECONDS:-9}"
TIME_LIMIT_SECONDS="${TIME_LIMIT_SECONDS:-300}"
LOG_DIR="${LOG_DIR:-logs}"
LOG_RETENTION="${LOG_RETENTION:-100}"
DRY_RUN="${DRY_RUN:-0}"
MINER_BIN="${MINER_BIN:-vendor/cpuminer-multi/cpuminer}"

MINER_BIN="$(miner_abs_path "$MINER_BIN" "$ROOT_DIR")"
LOG_DIR="$(miner_abs_path "$LOG_DIR" "$ROOT_DIR")"

fail() {
  echo "$*" >&2
  exit 1
}

[[ -n "$BTC_ADDRESS" ]] || fail "BTC_ADDRESS is empty."
[[ -n "$WORKER_NAME" ]] || fail "WORKER_NAME is empty."
[[ "$ALGO" == "sha256d" ]] || fail "ALGO must be sha256d for Bitcoin mainnet."
if ! [[ "$POOL_HOST" =~ ^[A-Za-z0-9.-]+$ ]]; then
  fail "POOL_HOST must be a hostname or IP literal without spaces."
fi
if ! [[ "$POOL_PORT" =~ ^[0-9]+$ ]] || (( POOL_PORT < 1 || POOL_PORT > 65535 )); then
  fail "POOL_PORT must be 1..65535."
fi
miner_require_file_under_root "MINER_BIN" "$MINER_BIN" "$ROOT_DIR" || fail "Unsafe MINER_BIN path."
miner_require_path_under_root "LOG_DIR" "$LOG_DIR" "$ROOT_DIR" || fail "Unsafe LOG_DIR path."
[[ -x "$MINER_BIN" ]] || fail "Miner binary missing or not executable: $MINER_BIN"

if [[ -z "$TIME_LIMIT_SECONDS" && "$ALLOW_UNLIMITED_RUN" != "1" ]]; then
  fail "TIME_LIMIT_SECONDS is empty; refusing unbounded run."
fi

if [[ "$THROTTLE_MODE" != "duty-cycle" && "$THROTTLE_MODE" != "cpulimit" && "$THROTTLE_MODE" != "none" ]]; then
  fail "THROTTLE_MODE must be duty-cycle, cpulimit, or none."
fi
if [[ "$DRY_RUN" != "0" && "$DRY_RUN" != "1" ]]; then
  fail "DRY_RUN must be 0 or 1."
fi

mkdir -p "$LOG_DIR"
run_id="$(date -u +"%Y%m%dT%H%M%SZ")-$$"
LOG_FILE="${LOG_FILE:-$LOG_DIR/miner-$run_id.log}"
LOG_FILE="$(miner_abs_path "$LOG_FILE" "$ROOT_DIR")"
mkdir -p "$(dirname "$LOG_FILE")"
miner_require_log_file_under_dir "$LOG_FILE" "$LOG_DIR" || fail "Unsafe LOG_FILE path."

miner_validate_btc_address "$BTC_ADDRESS" || fail "BTC_ADDRESS checksum/network validation failed."
if ! [[ "$WORKER_NAME" =~ ^[A-Za-z0-9._-]{1,32}$ ]]; then
  fail "WORKER_NAME must be 1-32 chars: letters, numbers, dot, underscore, hyphen."
fi
if ! [[ "$THREADS" =~ ^[0-9]+$ ]] || (( THREADS < 1 )); then
  fail "THREADS must be a positive integer."
fi
if ! [[ "$CPULIMIT_PERCENT" =~ ^[0-9]+$ ]] || (( CPULIMIT_PERCENT < 1 || CPULIMIT_PERCENT > 100 )); then
  fail "CPULIMIT_PERCENT must be an integer from 1 to 100."
fi
if [[ "$CPULIMIT_INCLUDE_CHILDREN" != "0" && "$CPULIMIT_INCLUDE_CHILDREN" != "1" ]]; then
  fail "CPULIMIT_INCLUDE_CHILDREN must be 0 or 1."
fi
if ! [[ "$NICE_LEVEL" =~ ^-?[0-9]+$ ]] || (( NICE_LEVEL < -20 || NICE_LEVEL > 20 )); then
  fail "NICE_LEVEL must be -20..20."
fi
if [[ "$REQUIRE_AC_POWER" != "0" && "$REQUIRE_AC_POWER" != "1" ]]; then
  fail "REQUIRE_AC_POWER must be 0 or 1."
fi
if (( THREADS != 1 )) && [[ "$ALLOW_MULTI_THREAD" != "1" ]]; then
  fail "THREADS must stay 1 for this Mac learning profile; set ALLOW_MULTI_THREAD=1 to override."
fi
if [[ "$ALLOW_UNLIMITED_RUN" != "0" && "$ALLOW_UNLIMITED_RUN" != "1" ]]; then
  fail "ALLOW_UNLIMITED_RUN must be 0 or 1."
fi
if [[ "$ALLOW_MULTI_THREAD" != "0" && "$ALLOW_MULTI_THREAD" != "1" ]]; then
  fail "ALLOW_MULTI_THREAD must be 0 or 1."
fi
if [[ "$THROTTLE_MODE" == "none" && "$ALLOW_MULTI_THREAD" != "1" ]]; then
  fail "THROTTLE_MODE=none requires ALLOW_MULTI_THREAD=1 as an explicit override."
fi
if ! [[ "$DUTY_ACTIVE_SECONDS" =~ ^[0-9]+$ ]] || (( DUTY_ACTIVE_SECONDS < 1 )); then
  fail "DUTY_ACTIVE_SECONDS must be a positive integer."
fi
if ! [[ "$DUTY_IDLE_SECONDS" =~ ^[0-9]+$ ]]; then
  fail "DUTY_IDLE_SECONDS must be a non-negative integer."
fi
if [[ -n "$TIME_LIMIT_SECONDS" ]] && { ! [[ "$TIME_LIMIT_SECONDS" =~ ^[0-9]+$ ]] || (( TIME_LIMIT_SECONDS < 1 || TIME_LIMIT_SECONDS > 3600 )); }; then
  fail "TIME_LIMIT_SECONDS must be 1..3600 for this lab profile."
fi
if ! [[ "$LOG_RETENTION" =~ ^[0-9]+$ ]] || (( LOG_RETENTION < 1 || LOG_RETENTION > 10000 )); then
  fail "LOG_RETENTION must be 1..10000."
fi

: > "$LOG_FILE"

say() {
  printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

if [[ "$REQUIRE_AC_POWER" == "1" ]]; then
  if command -v pmset >/dev/null 2>&1; then
    power_state="$(pmset -g batt 2>/dev/null || true)"
    if [[ "$power_state" != *"AC Power"* ]]; then
      say "Mac is not on AC Power."
      exit 1
    fi
  else
    say "WARN pmset is missing; AC power cannot be verified."
  fi
fi

if [[ "$DRY_RUN" != "1" ]]; then
  if ps_output="$(ps -ax -o args 2>/dev/null)"; then
    if printf '%s\n' "$ps_output" | grep -F "$MINER_BIN" | grep -v grep >/dev/null 2>&1; then
      say "An existing cpuminer process is already running."
      exit 1
    fi
  else
    say "Process list unavailable; refusing real start because existing miners cannot be ruled out."
    exit 1
  fi
fi

prune_old_logs() {
  local count remove_count log log_real current_real modified
  current_real="$(cd "$(dirname "$LOG_FILE")" && pwd -P)/$(basename "$LOG_FILE")" || return 1
  count="$(find "$LOG_DIR" -maxdepth 1 -type f -name 'miner-*.log' -print | wc -l | tr -d ' ')"
  remove_count=$(( count - LOG_RETENTION ))
  (( remove_count > 0 )) || return 0

  while IFS= read -r log; do
    log_real="$(cd "$(dirname "$log")" && pwd -P)/$(basename "$log")" || continue
    [[ "$log_real" == "$current_real" ]] && continue
    if ! rm -f -- "$log"; then
      echo "WARN failed to remove old log: $log" >&2
    fi
    remove_count=$(( remove_count - 1 ))
    (( remove_count <= 0 )) && break
  done < <(
    find "$LOG_DIR" -maxdepth 1 -type f -name 'miner-*.log' -print | while IFS= read -r log; do
      if modified="$(stat -f %m "$log" 2>/dev/null)" && [[ "$modified" =~ ^[0-9]+$ ]]; then
        :
      elif modified="$(stat -c %Y "$log" 2>/dev/null)" && [[ "$modified" =~ ^[0-9]+$ ]]; then
        :
      else
        modified=0
      fi
      printf '%s\t%s\n' "$modified" "$log"
    done | sort -n | cut -f2-
  )
}

if ! prune_old_logs; then
  say "WARN Log retention cleanup failed."
fi

if [[ "$REQUIRE_PREFLIGHT" == "1" && "${PREFLIGHT_RUNNING:-0}" != "1" ]]; then
  say "Running preflight."
  if ! PREFLIGHT_RUNNING=1 "$ROOT_DIR/scripts/preflight.sh" 2>&1 | tee -a "$LOG_FILE"; then
    say "Preflight failed."
    exit 1
  fi
  say "Preflight passed."
fi

stratum_url="stratum+tcp://$POOL_HOST:$POOL_PORT"
username="$BTC_ADDRESS.$WORKER_NAME"

if [[ "$DRY_RUN" == "1" ]]; then
  say "Preparing real Bitcoin mainnet solo mining command."
else
  say "Starting real Bitcoin mainnet solo mining."
fi
say "Run id: $run_id"
say "Log: $LOG_FILE"
say "Log retention: $LOG_RETENTION"
say "Pool: $stratum_url"
say "User: $(miner_redact_pool_username "$username")"
say "Algo: $ALGO"
say "Threads: $THREADS"
say "Throttle mode: $THROTTLE_MODE"
case "$THROTTLE_MODE" in
  duty-cycle)
    say "Duty cycle: ${DUTY_ACTIVE_SECONDS}s active / ${DUTY_IDLE_SECONDS}s paused"
    ;;
  cpulimit)
    say "CPU limit: $CPULIMIT_PERCENT%"
    if [[ "$CPULIMIT_INCLUDE_CHILDREN" == "1" ]]; then
      say "CPU limit includes child processes."
    fi
    ;;
  none)
    say "CPU throttle: none"
    ;;
esac
if [[ -n "$TIME_LIMIT_SECONDS" ]]; then
  say "Time limit: ${TIME_LIMIT_SECONDS}s"
fi
if [[ "$DRY_RUN" != "1" ]]; then
  say "Stop with Ctrl-C."
fi

miner_args=(
  -a "$ALGO"
  -o "$stratum_url"
  -u "$username"
  -p "$POOL_PASSWORD"
  -t "$THREADS"
)

if [[ "$DRY_RUN" == "1" ]]; then
  say "Dry run only; miner was not started."
  miner_print_redacted_command "$MINER_BIN" "${miner_args[@]}" | tee -a "$LOG_FILE"
  exit 0
fi

tail -n 0 -f "$LOG_FILE" &
tail_pid=$!

cleanup_pid() {
  local pid="$1"
  if kill -0 "$pid" >/dev/null 2>&1; then
    kill -CONT "$pid" >/dev/null 2>&1 || true
    kill -TERM "$pid" >/dev/null 2>&1 || true
    sleep 1
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill -KILL "$pid" >/dev/null 2>&1 || true
    fi
    wait "$pid" 2>/dev/null || true
  fi
  if [[ -n "${tail_pid:-}" ]] && kill -0 "$tail_pid" >/dev/null 2>&1; then
    kill "$tail_pid" >/dev/null 2>&1 || true
    wait "$tail_pid" 2>/dev/null || true
  fi
}

sleep_checked() {
  local seconds="$1"
  local end
  end=$(( $(date +%s) + seconds ))
  while (( $(date +%s) < end )); do
    if [[ -n "$TIME_LIMIT_SECONDS" ]] && (( $(date +%s) - started_at >= TIME_LIMIT_SECONDS )); then
      cleanup_pid "$miner_pid"
      exit 0
    fi
    sleep 1
  done
}

if [[ "$THROTTLE_MODE" == "cpulimit" ]]; then
  if [[ -n "$TIME_LIMIT_SECONDS" ]]; then
    miner_args+=(--time-limit="$TIME_LIMIT_SECONDS")
  fi
  command -v cpulimit >/dev/null 2>&1 || {
    echo "cpulimit is missing." | tee -a "$LOG_FILE" >&2
    exit 1
  }
  cpulimit_args=(-l "$CPULIMIT_PERCENT")
  if [[ "$CPULIMIT_INCLUDE_CHILDREN" == "1" ]]; then
    cpulimit_args+=(-i)
  fi
  cpulimit_args+=(-- "$MINER_BIN" "${miner_args[@]}")

  nice_probe="$(nice -n "$NICE_LEVEL" true 2>&1 >/dev/null || true)"
  if [[ -z "$nice_probe" ]]; then
    nice -n "$NICE_LEVEL" cpulimit "${cpulimit_args[@]}" >> "$LOG_FILE" 2>&1 &
    miner_pid=$!
    trap 'cleanup_pid "$miner_pid"' INT TERM EXIT
    wait "$miner_pid"
    exit $?
  fi

  echo "nice priority change is unavailable in this environment; continuing with cpulimit only." | tee -a "$LOG_FILE" >&2
  cpulimit "${cpulimit_args[@]}" >> "$LOG_FILE" 2>&1 &
  miner_pid=$!
  trap 'cleanup_pid "$miner_pid"' INT TERM EXIT
  wait "$miner_pid"
  exit $?
fi

"$MINER_BIN" "${miner_args[@]}" >> "$LOG_FILE" 2>&1 &
miner_pid=$!
started_at=$(date +%s)
trap 'cleanup_pid "$miner_pid"' INT TERM EXIT

if [[ "$THROTTLE_MODE" == "none" ]]; then
  while kill -0 "$miner_pid" >/dev/null 2>&1; do
    if [[ -n "$TIME_LIMIT_SECONDS" ]] && (( $(date +%s) - started_at >= TIME_LIMIT_SECONDS )); then
      cleanup_pid "$miner_pid"
      exit 0
    fi
    sleep 1
  done
  wait "$miner_pid"
  exit $?
fi

while kill -0 "$miner_pid" >/dev/null 2>&1; do
  kill -CONT "$miner_pid" >/dev/null 2>&1 || true
  sleep_checked "$DUTY_ACTIVE_SECONDS"

  if ! kill -0 "$miner_pid" >/dev/null 2>&1; then
    break
  fi

  kill -STOP "$miner_pid" >/dev/null 2>&1 || true
  sleep_checked "$DUTY_IDLE_SECONDS"
done

wait "$miner_pid"
