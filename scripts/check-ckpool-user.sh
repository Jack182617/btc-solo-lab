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

config_keys=(
  BTC_ADDRESS
)
load_miner_env "$ENV_FILE" "${config_keys[@]}"

if [[ -z "${BTC_ADDRESS:-}" ]]; then
  echo "BTC_ADDRESS is empty in $ENV_FILE" >&2
  exit 1
fi
miner_validate_btc_address "$BTC_ADDRESS" || {
  echo "BTC_ADDRESS checksum/network validation failed." >&2
  exit 1
}

url="https://solo.ckpool.org/users/$BTC_ADDRESS"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

echo "Fetching $url"
http_code="$(curl -sS --connect-timeout 5 --max-time 15 -o "$tmp" -w "%{http_code}" "$url" || true)"

case "$http_code" in
  200)
    cat "$tmp"
    echo
    ;;
  404)
    echo "No CKPool user stats yet."
    echo "For this CPU lab profile that is expected until a sufficiently difficult share is submitted."
    ;;
  *)
    echo "Unexpected HTTP status from CKPool: $http_code" >&2
    cat "$tmp" >&2 || true
    exit 1
    ;;
esac
