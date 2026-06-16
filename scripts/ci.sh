#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

npm run build
cargo fmt --manifest-path src-tauri/Cargo.toml -- --check
cargo test --manifest-path src-tauri/Cargo.toml
cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings

bash -n \
  scripts/bootstrap-cpuminer.sh \
  scripts/run-solo-miner.sh \
  scripts/preflight.sh \
  scripts/status.sh \
  scripts/check-ckpool-user.sh \
  scripts/package-macos.sh \
  scripts/audit-release.sh \
  scripts/smoke-start.sh \
  scripts/verify.sh \
  scripts/ci.sh \
  scripts/lib/miner-env.sh

npm audit --audit-level=moderate

grep -qxF 'configs/miner.env' .gitignore
grep -qxF 'vendor/cpuminer-multi/' .gitignore
grep -qxF 'vendor/cpuminer-multi/cpuminer' .gitignore

stub_dir="$ROOT_DIR/logs/.ci"
cleanup() {
  rm -rf "$stub_dir"
}
trap cleanup EXIT
mkdir -p "$stub_dir"

cat > "$stub_dir/cpuminer" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--help" ]]; then
  echo "cpuminer stub"
  exit 0
fi
echo "cpuminer stub must not be started during CI." >&2
exit 99
STUB
chmod +x "$stub_dir/cpuminer"

DRY_RUN=1 \
REQUIRE_PREFLIGHT=0 \
MINER_BIN="$stub_dir/cpuminer" \
BTC_ADDRESS=1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa \
scripts/run-solo-miner.sh >/dev/null

if POOL_PASSWORD=supersecret \
  DRY_RUN=1 \
  REQUIRE_PREFLIGHT=0 \
  MINER_BIN="$stub_dir/cpuminer" \
  BTC_ADDRESS=1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa \
  scripts/run-solo-miner.sh 2>/dev/null | grep -F 'supersecret' >/dev/null; then
  echo "Dry-run output leaked POOL_PASSWORD." >&2
  exit 1
fi

if DRY_RUN=1 \
  REQUIRE_PREFLIGHT=0 \
  MINER_BIN=/bin/echo \
  BTC_ADDRESS=1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa \
  scripts/run-solo-miner.sh >/dev/null 2>&1; then
  echo "Expected external MINER_BIN guard to fail." >&2
  exit 1
fi

if DRY_RUN=1 \
  REQUIRE_PREFLIGHT=0 \
  MINER_BIN="$stub_dir/cpuminer" \
  BTC_ADDRESS=1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb \
  scripts/run-solo-miner.sh >/dev/null 2>&1; then
  echo "Expected invalid Base58Check BTC_ADDRESS guard to fail." >&2
  exit 1
fi

if rg -q 'python3' scripts/lib/miner-env.sh scripts/preflight.sh scripts/run-solo-miner.sh scripts/status.sh scripts/check-ckpool-user.sh scripts/smoke-start.sh; then
  echo "Runtime scripts must not require python3." >&2
  exit 1
fi
