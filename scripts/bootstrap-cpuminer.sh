#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/configs/miner.env}"
source "$ROOT_DIR/scripts/lib/miner-env.sh"

if [[ -f "$ENV_FILE" ]]; then
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
    MINER_BIN
    CPUMINER_REF
    MINER_DIR
    CPUMINER_REPO
    BUILD_JOBS
  )
  load_miner_env "$ENV_FILE" "${config_keys[@]}"
fi

MINER_DIR="${MINER_DIR:-$ROOT_DIR/vendor/cpuminer-multi}"
CPUMINER_REPO="${CPUMINER_REPO:-https://github.com/tpruvot/cpuminer-multi.git}"
CPUMINER_REF="${CPUMINER_REF:-d2927ed23b1d0eacd067c320fce64e6610737adb}"
BUILD_JOBS="${BUILD_JOBS:-2}"

if ! command -v git >/dev/null 2>&1; then
  echo "git is required. Install Xcode Command Line Tools or Homebrew git first." >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required. Install it first: https://brew.sh/" >&2
  exit 1
fi

missing=()
for pkg in automake autoconf libtool pkgconf curl openssl@3 jansson cpulimit; do
  if ! brew list "$pkg" >/dev/null 2>&1; then
    missing+=("$pkg")
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo "Installing Homebrew dependencies: ${missing[*]}"
  brew install "${missing[@]}"
fi

mkdir -p "$ROOT_DIR/vendor"

if [[ ! -d "$MINER_DIR/.git" ]]; then
  git clone "$CPUMINER_REPO" "$MINER_DIR"
fi

if [[ -n "${CPUMINER_REF:-}" ]]; then
  git -C "$MINER_DIR" fetch --tags --prune
  git -C "$MINER_DIR" checkout "$CPUMINER_REF"
fi

curl_prefix="$(brew --prefix curl)"
openssl_prefix="$(brew --prefix openssl@3)"

export PKG_CONFIG_PATH="$curl_prefix/lib/pkgconfig:$openssl_prefix/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export CPPFLAGS="-I$curl_prefix/include -I$openssl_prefix/include ${CPPFLAGS:-}"
export LDFLAGS="-L$curl_prefix/lib -L$openssl_prefix/lib ${LDFLAGS:-}"

configure_flags=(--with-crypto --with-curl)
case "$(uname -m)" in
  arm64|aarch64)
    configure_flags+=(--disable-assembly)
    ;;
esac

cd "$MINER_DIR"
./autogen.sh
./nomacro.pl
./configure CFLAGS="${CFLAGS:--O2 -march=native}" "${configure_flags[@]}"
make -j "$BUILD_JOBS"

"$MINER_DIR/cpuminer" --help >/dev/null
echo "cpuminer built: $MINER_DIR/cpuminer"
