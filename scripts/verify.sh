#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

npm run build
cargo fmt --manifest-path src-tauri/Cargo.toml -- --check
cargo test --manifest-path src-tauri/Cargo.toml
cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings

grep -qxF 'configs/miner.env' .gitignore || {
  echo "Expected configs/miner.env in .gitignore." >&2
  exit 1
}
grep -qxF 'vendor/cpuminer-multi/cpuminer' .gitignore || {
  echo "Expected vendor/cpuminer-multi/cpuminer in .gitignore." >&2
  exit 1
}
grep -q 'NOTARIZE=1 requires SIGNING_IDENTITY' scripts/package-macos.sh || {
  echo "Expected notarization guard in package script." >&2
  exit 1
}
grep -q 'Developer ID Application signing identity' scripts/package-macos.sh || {
  echo "Expected Developer ID identity guard in package script." >&2
  exit 1
}
grep -q 'real reverse-DNS bundle identifier' scripts/package-macos.sh || {
  echo "Expected public bundle identifier guard in package script." >&2
  exit 1
}
grep -q -- '--options runtime --timestamp' scripts/package-macos.sh || {
  echo "Expected hardened runtime signing in package script." >&2
  exit 1
}
grep -q 'scripts/audit-release.sh' scripts/package-macos.sh || {
  echo "Expected package script to run release audit." >&2
  exit 1
}
if grep -q '"../scripts/"' src-tauri/tauri.conf.json; then
  echo "Packaged app must not bundle the entire scripts directory." >&2
  exit 1
fi
if rg -q 'python3' scripts/lib/miner-env.sh scripts/preflight.sh scripts/run-solo-miner.sh scripts/status.sh scripts/check-ckpool-user.sh scripts/smoke-start.sh; then
  echo "Runtime scripts must not require python3." >&2
  exit 1
fi
grep -q 'runtime/scripts/run-solo-miner.sh' src-tauri/tauri.conf.json || {
  echo "Expected explicit packaged runtime script resources." >&2
  exit 1
}

if [[ ! -x vendor/cpuminer-multi/cpuminer ]]; then
  echo "Missing miner binary. Run ./scripts/bootstrap-cpuminer.sh first." >&2
  exit 1
fi

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
  scripts/lib/miner-env.sh

NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-${TMPDIR:-/tmp}/btc-demo-npm-cache}" \
  npm audit --audit-level=moderate

DRY_RUN=1 REQUIRE_PREFLIGHT=0 scripts/run-solo-miner.sh >/dev/null
scripts/smoke-start.sh >/dev/null

if POOL_PASSWORD=supersecret DRY_RUN=1 REQUIRE_PREFLIGHT=0 scripts/run-solo-miner.sh 2>/dev/null | grep -F 'supersecret' >/dev/null; then
  echo "Dry-run output leaked POOL_PASSWORD." >&2
  exit 1
fi
if ! POOL_PASSWORD=supersecret DRY_RUN=1 REQUIRE_PREFLIGHT=0 scripts/run-solo-miner.sh 2>/dev/null | grep -F -- '-p REDACTED' >/dev/null; then
  echo "Expected dry-run output to redact POOL_PASSWORD." >&2
  exit 1
fi
redaction_output="$(BTC_ADDRESS=1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa WORKER_NAME=verify-worker POOL_PASSWORD=supersecret DRY_RUN=1 REQUIRE_PREFLIGHT=0 scripts/run-solo-miner.sh 2>/dev/null)"
if grep -F '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa' <<<"$redaction_output" >/dev/null; then
  echo "Dry-run output leaked a full BTC address." >&2
  exit 1
fi
if ! grep -F '1A1zP1eP...DivfNa.verify-worker' <<<"$redaction_output" >/dev/null; then
  echo "Expected dry-run output to show only BTC address preview." >&2
  exit 1
fi

if DRY_RUN=1 REQUIRE_PREFLIGHT=0 LOG_FILE=/private/tmp/btc-solo-lab-escape.log scripts/run-solo-miner.sh >/dev/null 2>&1; then
  echo "Expected external LOG_FILE guard to fail." >&2
  exit 1
fi

if DRY_RUN=1 REQUIRE_PREFLIGHT=0 MINER_BIN=/bin/echo scripts/run-solo-miner.sh >/dev/null 2>&1; then
  echo "Expected external MINER_BIN guard to fail." >&2
  exit 1
fi

probe_dir="$ROOT_DIR/logs/.verify"
mkdir -p "$probe_dir"
escaped_miner="$probe_dir/escaped-miner"
ln -sf /bin/echo "$escaped_miner"
if DRY_RUN=1 REQUIRE_PREFLIGHT=0 MINER_BIN="$escaped_miner" scripts/run-solo-miner.sh >/dev/null 2>&1; then
  echo "Expected symlinked external MINER_BIN guard to fail." >&2
  rm -f "$escaped_miner"
  exit 1
fi
rm -f "$escaped_miner"

if DRY_RUN=1 REQUIRE_PREFLIGHT=0 LOG_RETENTION=0 scripts/run-solo-miner.sh >/dev/null 2>&1; then
  echo "Expected LOG_RETENTION guard to fail." >&2
  exit 1
fi

if DRY_RUN=1 REQUIRE_PREFLIGHT=0 REQUIRE_AC_POWER=2 scripts/run-solo-miner.sh >/dev/null 2>&1; then
  echo "Expected REQUIRE_AC_POWER guard to fail." >&2
  exit 1
fi

if DRY_RUN=1 REQUIRE_PREFLIGHT=0 POOL_PORT=70000 scripts/run-solo-miner.sh >/dev/null 2>&1; then
  echo "Expected POOL_PORT guard to fail." >&2
  exit 1
fi

BTC_ADDRESS=1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa DRY_RUN=1 REQUIRE_PREFLIGHT=0 scripts/run-solo-miner.sh >/dev/null
BTC_ADDRESS=3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy DRY_RUN=1 REQUIRE_PREFLIGHT=0 scripts/run-solo-miner.sh >/dev/null

if BTC_ADDRESS=1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb DRY_RUN=1 REQUIRE_PREFLIGHT=0 scripts/run-solo-miner.sh >/dev/null 2>&1; then
  echo "Expected invalid Base58Check BTC_ADDRESS guard to fail." >&2
  exit 1
fi

if BTC_ADDRESS=bc1q9clzaht7mrl2vaa0e2u53v59n5l2dgj0842uuq DRY_RUN=1 REQUIRE_PREFLIGHT=0 scripts/run-solo-miner.sh >/dev/null 2>&1; then
  echo "Expected invalid Bech32 BTC_ADDRESS guard to fail." >&2
  exit 1
fi
if BTC_ADDRESS=bc1q9clzaht7mrl2vaa0e2u53v59n5l2dgj0842uuq scripts/check-ckpool-user.sh >/dev/null 2>&1; then
  echo "Expected CKPool checker invalid BTC_ADDRESS guard to fail." >&2
  exit 1
fi

if ps -ax -o args >/dev/null 2>&1; then
  probe_miner="$probe_dir/cpuminer-probe"
  printf '#!/usr/bin/env bash\nsleep 3\n' > "$probe_miner"
  chmod +x "$probe_miner"
  "$probe_miner" -u 1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa.status-worker -p secret-status-password 3 >/dev/null 2>&1 &
  probe_pid=$!
  cleanup_probe() {
    kill "$probe_pid" >/dev/null 2>&1 || true
    wait "$probe_pid" 2>/dev/null || true
    rm -f "$probe_miner"
  }
  trap cleanup_probe EXIT
  probe_visible=0
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ps -ax -o args 2>/dev/null | grep -F "$probe_miner" | grep -v grep >/dev/null 2>&1; then
      probe_visible=1
      break
    fi
    sleep 0.1
  done
  if [[ "$probe_visible" != "1" ]]; then
    echo "Expected probe miner to be visible in process list." >&2
    exit 1
  fi
  if DRY_RUN=0 REQUIRE_PREFLIGHT=0 REQUIRE_AC_POWER=0 MINER_BIN="$probe_miner" scripts/run-solo-miner.sh >/dev/null 2>&1; then
    echo "Expected existing miner guard to fail." >&2
    exit 1
  fi
  if MINER_BIN="$probe_miner" scripts/status.sh | grep -F 'secret-status-password' >/dev/null; then
    echo "Status output leaked a process password argument." >&2
    exit 1
  fi
  if ! MINER_BIN="$probe_miner" scripts/status.sh | grep -F -- '-p REDACTED' >/dev/null; then
    echo "Expected status output to redact process password argument." >&2
    exit 1
  fi
  status_output="$(MINER_BIN="$probe_miner" scripts/status.sh)"
  if grep -F '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa' <<<"$status_output" >/dev/null; then
    echo "Status output leaked a full BTC address." >&2
    exit 1
  fi
  if ! grep -F '1A1zP1eP...DivfNa.status-worker' <<<"$status_output" >/dev/null; then
    echo "Expected status output to show only BTC address preview." >&2
    exit 1
  fi
  wait "$probe_pid" 2>/dev/null || true
  rm -f "$probe_miner"
  trap - EXIT
else
  if DRY_RUN=0 REQUIRE_PREFLIGHT=0 REQUIRE_AC_POWER=0 MINER_BIN=vendor/cpuminer-multi/cpuminer scripts/run-solo-miner.sh >/dev/null 2>&1; then
    echo "Expected unavailable process-list guard to fail." >&2
    exit 1
  fi
fi

scripts/status.sh >/dev/null
