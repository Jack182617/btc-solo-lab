#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/configs/miner.env}"
source "$ROOT_DIR/scripts/lib/miner-env.sh"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "FAIL missing config: $ENV_FILE" >&2
  echo "Create it from configs/miner.env.example first." >&2
  exit 1
fi

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
  MINER_BIN
)

load_miner_env "$ENV_FILE" "${config_keys[@]}"

BTC_ADDRESS="${BTC_ADDRESS:-}"
WORKER_NAME="${WORKER_NAME:-mac-cpu}"
POOL_HOST="${POOL_HOST:-solo.ckpool.org}"
POOL_PORT="${POOL_PORT:-3333}"
ALGO="${ALGO:-sha256d}"
THREADS="${THREADS:-1}"
CPULIMIT_PERCENT="${CPULIMIT_PERCENT:-10}"
CPULIMIT_INCLUDE_CHILDREN="${CPULIMIT_INCLUDE_CHILDREN:-1}"
NICE_LEVEL="${NICE_LEVEL:-20}"
REQUIRE_AC_POWER="${REQUIRE_AC_POWER:-1}"
ALLOW_UNLIMITED_RUN="${ALLOW_UNLIMITED_RUN:-0}"
ALLOW_MULTI_THREAD="${ALLOW_MULTI_THREAD:-0}"
THROTTLE_MODE="${THROTTLE_MODE:-duty-cycle}"
DUTY_ACTIVE_SECONDS="${DUTY_ACTIVE_SECONDS:-1}"
DUTY_IDLE_SECONDS="${DUTY_IDLE_SECONDS:-9}"
TIME_LIMIT_SECONDS="${TIME_LIMIT_SECONDS:-300}"
LOG_DIR="${LOG_DIR:-logs}"
LOG_RETENTION="${LOG_RETENTION:-100}"
MINER_BIN="${MINER_BIN:-vendor/cpuminer-multi/cpuminer}"

MINER_BIN="$(miner_abs_path "$MINER_BIN" "$ROOT_DIR")"
LOG_DIR="$(miner_abs_path "$LOG_DIR" "$ROOT_DIR")"

fail() {
  echo "FAIL $*" >&2
  exit 1
}

warn() {
  echo "WARN $*" >&2
}

pass() {
  echo "OK   $*"
}

[[ -n "$BTC_ADDRESS" ]] || fail "BTC_ADDRESS is empty"
[[ -n "$WORKER_NAME" ]] || fail "WORKER_NAME is empty"
[[ "$ALGO" == "sha256d" ]] || fail "ALGO must be sha256d for Bitcoin mainnet"
if ! [[ "$POOL_HOST" =~ ^[A-Za-z0-9.-]+$ ]]; then
  fail "POOL_HOST must be a hostname or IP literal without spaces"
fi
if ! [[ "$POOL_PORT" =~ ^[0-9]+$ ]] || (( POOL_PORT < 1 || POOL_PORT > 65535 )); then
  fail "POOL_PORT must be 1..65535"
fi
miner_require_file_under_root "MINER_BIN" "$MINER_BIN" "$ROOT_DIR" || fail "unsafe miner binary path"
miner_require_path_under_root "LOG_DIR" "$LOG_DIR" "$ROOT_DIR" || fail "unsafe log directory"
[[ -x "$MINER_BIN" ]] || fail "miner binary missing or not executable: $MINER_BIN"
command -v nc >/dev/null 2>&1 || fail "nc is missing"
command -v pmset >/dev/null 2>&1 || warn "pmset is missing; AC power cannot be verified"

if ! [[ "$WORKER_NAME" =~ ^[A-Za-z0-9._-]{1,32}$ ]]; then
  fail "WORKER_NAME must be 1-32 chars: letters, numbers, dot, underscore, hyphen"
fi

miner_validate_btc_address "$BTC_ADDRESS" || fail "BTC_ADDRESS checksum/network validation failed"
pass "BTC_ADDRESS checksum and network"

if ! [[ "$THREADS" =~ ^[0-9]+$ ]] || (( THREADS < 1 )); then
  fail "THREADS must be a positive integer"
fi
if (( THREADS != 1 )) && [[ "$ALLOW_MULTI_THREAD" != "1" ]]; then
  fail "THREADS must stay 1 for this Mac learning profile; set ALLOW_MULTI_THREAD=1 to override"
fi
if ! [[ "$CPULIMIT_PERCENT" =~ ^[0-9]+$ ]] || (( CPULIMIT_PERCENT < 1 || CPULIMIT_PERCENT > 100 )); then
  fail "CPULIMIT_PERCENT must be an integer from 1 to 100"
fi
if [[ "$CPULIMIT_INCLUDE_CHILDREN" != "0" && "$CPULIMIT_INCLUDE_CHILDREN" != "1" ]]; then
  fail "CPULIMIT_INCLUDE_CHILDREN must be 0 or 1"
fi
if ! [[ "$NICE_LEVEL" =~ ^-?[0-9]+$ ]] || (( NICE_LEVEL < -20 || NICE_LEVEL > 20 )); then
  fail "NICE_LEVEL must be -20..20"
fi
if [[ "$REQUIRE_AC_POWER" != "0" && "$REQUIRE_AC_POWER" != "1" ]]; then
  fail "REQUIRE_AC_POWER must be 0 or 1"
fi
if [[ "$ALLOW_UNLIMITED_RUN" != "0" && "$ALLOW_UNLIMITED_RUN" != "1" ]]; then
  fail "ALLOW_UNLIMITED_RUN must be 0 or 1"
fi
if [[ "$ALLOW_MULTI_THREAD" != "0" && "$ALLOW_MULTI_THREAD" != "1" ]]; then
  fail "ALLOW_MULTI_THREAD must be 0 or 1"
fi
if [[ "$THROTTLE_MODE" != "duty-cycle" && "$THROTTLE_MODE" != "cpulimit" && "$THROTTLE_MODE" != "none" ]]; then
  fail "THROTTLE_MODE must be duty-cycle, cpulimit, or none"
fi
if [[ "$THROTTLE_MODE" == "cpulimit" ]]; then
  command -v cpulimit >/dev/null 2>&1 || fail "cpulimit is missing"
  warn "cpulimit was unreliable in this Codex/macOS session; duty-cycle is recommended"
fi
if [[ "$THROTTLE_MODE" == "none" && "$ALLOW_MULTI_THREAD" != "1" ]]; then
  fail "THROTTLE_MODE=none requires ALLOW_MULTI_THREAD=1 as an explicit override"
fi
if ! [[ "$DUTY_ACTIVE_SECONDS" =~ ^[0-9]+$ ]] || (( DUTY_ACTIVE_SECONDS < 1 )); then
  fail "DUTY_ACTIVE_SECONDS must be a positive integer"
fi
if ! [[ "$DUTY_IDLE_SECONDS" =~ ^[0-9]+$ ]]; then
  fail "DUTY_IDLE_SECONDS must be a non-negative integer"
fi
if [[ -z "$TIME_LIMIT_SECONDS" && "$ALLOW_UNLIMITED_RUN" != "1" ]]; then
  fail "TIME_LIMIT_SECONDS is empty; set a time limit or ALLOW_UNLIMITED_RUN=1"
fi
if [[ -n "$TIME_LIMIT_SECONDS" ]] && { ! [[ "$TIME_LIMIT_SECONDS" =~ ^[0-9]+$ ]] || (( TIME_LIMIT_SECONDS < 1 || TIME_LIMIT_SECONDS > 3600 )); }; then
  fail "TIME_LIMIT_SECONDS must be 1..3600 for this lab profile"
fi
if ! [[ "$LOG_RETENTION" =~ ^[0-9]+$ ]] || (( LOG_RETENTION < 1 || LOG_RETENTION > 10000 )); then
  fail "LOG_RETENTION must be 1..10000"
fi

if command -v pmset >/dev/null 2>&1; then
  power_state="$(pmset -g batt 2>/dev/null || true)"
  if [[ "$REQUIRE_AC_POWER" == "1" && "$power_state" != *"AC Power"* ]]; then
    fail "Mac is not on AC Power"
  fi
  pass "power source: ${power_state%%$'\n'*}"
fi

cpu_model="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
logical_cpu="$(sysctl -n hw.logicalcpu 2>/dev/null || true)"
mem_bytes="$(sysctl -n hw.memsize 2>/dev/null || true)"
perf_cores="$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || true)"
eff_cores="$(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null || true)"
if [[ -n "$cpu_model" || -n "$logical_cpu" ]]; then
  pass "hardware: ${cpu_model:-unknown CPU}, logical_cpu=${logical_cpu:-unknown}, perf=${perf_cores:-unknown}, efficiency=${eff_cores:-unknown}"
else
  warn "hardware profile unavailable"
fi
if [[ -n "$mem_bytes" ]]; then
  pass "memory: $(( mem_bytes / 1024 / 1024 / 1024 ))GB"
fi

if ps_output="$(ps -ax -o args 2>/dev/null)"; then
  if printf '%s\n' "$ps_output" | grep -F "$MINER_BIN" | grep -v grep >/dev/null 2>&1; then
    fail "an existing cpuminer process is already running"
  fi
else
  warn "process list unavailable; cannot verify no existing miner"
fi

if ! "$MINER_BIN" --help 2>&1 | grep -q "sha256d"; then
  fail "miner binary does not advertise sha256d support"
fi
pass "miner binary runs and supports sha256d"

mkdir -p "$LOG_DIR"
pass "log directory: $LOG_DIR"
pass "log retention: $LOG_RETENTION"

if nc -vz -G 5 "$POOL_HOST" "$POOL_PORT" >/dev/null 2>&1; then
  pass "TCP connectivity to $POOL_HOST:$POOL_PORT"
elif nc -vz -w 5 "$POOL_HOST" "$POOL_PORT" >/dev/null 2>&1; then
  pass "TCP connectivity to $POOL_HOST:$POOL_PORT"
else
  fail "cannot connect to $POOL_HOST:$POOL_PORT"
fi

pass "config ready: ${BTC_ADDRESS:0:8}...${BTC_ADDRESS: -6}.${WORKER_NAME}"
case "$THROTTLE_MODE" in
  duty-cycle)
    pass "resource profile: threads=$THREADS duty=${DUTY_ACTIVE_SECONDS}s active/${DUTY_IDLE_SECONDS}s paused"
    ;;
  cpulimit)
    pass "resource profile: threads=$THREADS cpu_limit=${CPULIMIT_PERCENT}% include_children=$CPULIMIT_INCLUDE_CHILDREN"
    ;;
  none)
    pass "resource profile: threads=$THREADS no throttle"
    ;;
esac
if [[ -n "$TIME_LIMIT_SECONDS" ]]; then
  pass "time limit: ${TIME_LIMIT_SECONDS}s"
fi
pass "preflight complete; miner was not started"
