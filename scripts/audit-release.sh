#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-BTC Solo Lab}"
VERSION="${VERSION:-0.1.0}"
if [[ -z "${ARCH:-}" ]]; then
  case "$(uname -m)" in
    arm64) ARCH="aarch64" ;;
    x86_64) ARCH="x64" ;;
    *) ARCH="$(uname -m)" ;;
  esac
fi
REQUIRE_DISTRIBUTION="${REQUIRE_DISTRIBUTION:-0}"

APP_PATH="${APP_PATH:-$ROOT_DIR/src-tauri/target/release/bundle/macos/$APP_NAME.app}"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/src-tauri/target/release/bundle/dmg/${APP_NAME}_${VERSION}_${ARCH}.dmg}"

fail() {
  echo "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}

if [[ "$REQUIRE_DISTRIBUTION" != "0" && "$REQUIRE_DISTRIBUTION" != "1" ]]; then
  fail "REQUIRE_DISTRIBUTION must be 0 or 1."
fi

need codesign
need hdiutil
need shasum
if [[ "$REQUIRE_DISTRIBUTION" == "1" ]]; then
  need xcrun
fi

[[ -d "$APP_PATH" ]] || fail "Missing app bundle: $APP_PATH"
[[ -f "$DMG_PATH" ]] || fail "Missing DMG: $DMG_PATH"

INFO_PLIST="$APP_PATH/Contents/Info.plist"
[[ -f "$INFO_PLIST" ]] || fail "Missing Info.plist: $INFO_PLIST"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
if [[ "$REQUIRE_DISTRIBUTION" == "1" && "$bundle_id" == com.local.* ]]; then
  fail "Public distribution must use a real reverse-DNS bundle identifier, not $bundle_id."
fi

RUNTIME_DIR="$APP_PATH/Contents/Resources/runtime"
[[ -d "$RUNTIME_DIR" ]] || fail "Missing packaged runtime directory: $RUNTIME_DIR"

required_runtime_files=(
  "scripts/check-ckpool-user.sh"
  "scripts/lib/miner-env.sh"
  "scripts/preflight.sh"
  "scripts/run-solo-miner.sh"
  "scripts/smoke-start.sh"
  "scripts/status.sh"
  "configs/miner.env.example"
  "vendor/cpuminer-multi/cpuminer"
)

for file in "${required_runtime_files[@]}"; do
  [[ -e "$RUNTIME_DIR/$file" ]] || fail "Missing runtime resource: $file"
done

for script in \
  "scripts/check-ckpool-user.sh" \
  "scripts/preflight.sh" \
  "scripts/run-solo-miner.sh" \
  "scripts/smoke-start.sh" \
  "scripts/status.sh"; do
  [[ -x "$RUNTIME_DIR/$script" ]] || fail "Runtime script is not executable: $script"
done
[[ -x "$RUNTIME_DIR/vendor/cpuminer-multi/cpuminer" ]] || fail "Packaged miner is not executable."

[[ ! -e "$RUNTIME_DIR/configs/miner.env" ]] || fail "Real miner config must not be bundled."
for forbidden in \
  "scripts/bootstrap-cpuminer.sh" \
  "scripts/package-macos.sh" \
  "scripts/verify.sh"; do
  [[ ! -e "$RUNTIME_DIR/$forbidden" ]] || fail "Development script must not be bundled: $forbidden"
done

codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null
hdiutil verify "$DMG_PATH" >/dev/null

signature_info="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 || true)"
if [[ "$REQUIRE_DISTRIBUTION" == "1" ]]; then
  grep -q 'Authority=Developer ID Application' <<<"$signature_info" || fail "Distribution app is not signed with Developer ID Application."
  grep -q 'flags=.*runtime' <<<"$signature_info" || fail "Distribution app is missing hardened runtime."
  codesign --verify --verbose=2 "$DMG_PATH" >/dev/null
  xcrun stapler validate "$DMG_PATH" >/dev/null
fi

MOUNT_POINT=""
cleanup() {
  if [[ -n "$MOUNT_POINT" ]] && mount | grep -F "$MOUNT_POINT" >/dev/null 2>&1; then
    hdiutil detach "$MOUNT_POINT" >/dev/null || true
  fi
}
trap cleanup EXIT

attach_output="$(hdiutil attach -readonly -nobrowse "$DMG_PATH")"
MOUNT_POINT="$(printf '%s\n' "$attach_output" | awk -F '\t' '$NF ~ /^\/Volumes\// {print $NF; exit}')"
[[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]] || fail "Failed to resolve mounted DMG path."
[[ -d "$MOUNT_POINT/$APP_NAME.app" ]] || fail "Mounted DMG is missing $APP_NAME.app."
codesign --verify --deep --strict --verbose=2 "$MOUNT_POINT/$APP_NAME.app" >/dev/null
[[ ! -e "$MOUNT_POINT/$APP_NAME.app/Contents/Resources/runtime/configs/miner.env" ]] || fail "Mounted app bundles real miner config."
hdiutil detach "$MOUNT_POINT" >/dev/null
MOUNT_POINT=""

checksum="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"

echo "Release audit passed."
echo "App: $APP_PATH"
echo "DMG: $DMG_PATH"
echo "Bundle identifier: $bundle_id"
echo "DMG SHA-256: $checksum"
if [[ "$REQUIRE_DISTRIBUTION" == "1" ]]; then
  echo "Distribution checks: Developer ID, hardened runtime, notarization staple, mounted app verification."
else
  echo "Distribution checks: local/ad-hoc package only; set REQUIRE_DISTRIBUTION=1 for public release gates."
fi
