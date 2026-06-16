#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="BTC Solo Lab"
VERSION="${VERSION:-0.1.0}"
if [[ -z "${ARCH:-}" ]]; then
  case "$(uname -m)" in
    arm64) ARCH="aarch64" ;;
    x86_64) ARCH="x64" ;;
    *) ARCH="$(uname -m)" ;;
  esac
fi
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
NOTARIZE="${NOTARIZE:-0}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"

APP_PATH="$ROOT_DIR/src-tauri/target/release/bundle/macos/$APP_NAME.app"
BUNDLE_DIR="$ROOT_DIR/src-tauri/target/release/bundle"
DMG_DIR="$BUNDLE_DIR/dmg"
DMG_PATH="$DMG_DIR/${APP_NAME}_${VERSION}_${ARCH}.dmg"
STAGE_DIR="$ROOT_DIR/src-tauri/target/release/package-dmg"
MOUNT_POINT=""

cleanup() {
  if [[ -n "$MOUNT_POINT" ]] && mount | grep -F "$MOUNT_POINT" >/dev/null 2>&1; then
    hdiutil detach "$MOUNT_POINT" >/dev/null || true
  fi
}
trap cleanup EXIT

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

need npm
need plutil
need codesign
need hdiutil
need ditto
need shasum
if [[ "$NOTARIZE" == "1" ]]; then
  need xcrun
fi

detach_image_path() {
  local image_path="$1"
  hdiutil info | awk -v image_path="$image_path" '
    /^image-path[[:space:]]*:/ {
      in_target = index($0, image_path) > 0
      next
    }
    in_target && /^\/dev\/disk[0-9]+/ {
      print $1
    }
    /^=+/ {
      in_target = 0
    }
  ' | sort -u | while read -r device; do
    [[ -n "$device" ]] && hdiutil detach "$device" >/dev/null 2>&1 || true
  done
}

verify_dmg() {
  local image_path="$1"
  local attempt
  for attempt in 1 2 3 4 5; do
    detach_image_path "$image_path"
    if hdiutil verify "$image_path"; then
      return 0
    fi
    sleep "$attempt"
  done
  hdiutil verify "$image_path"
}

create_dmg() {
  local image_path="$1"
  local source_dir="$2"
  local attempt
  for attempt in 1 2 3 4 5; do
    detach_image_path "$image_path"
    rm -f "$image_path"
    if hdiutil create -volname "$APP_NAME" -srcfolder "$source_dir" -ov -format UDZO "$image_path"; then
      return 0
    fi
    sleep "$attempt"
  done
  detach_image_path "$image_path"
  rm -f "$image_path"
  hdiutil create -volname "$APP_NAME" -srcfolder "$source_dir" -ov -format UDZO "$image_path"
}

cd "$ROOT_DIR"
if [[ ! -x "$ROOT_DIR/vendor/cpuminer-multi/cpuminer" ]]; then
  echo "Missing miner binary. Run ./scripts/bootstrap-cpuminer.sh first." >&2
  exit 1
fi
if [[ "$NOTARIZE" != "0" && "$NOTARIZE" != "1" ]]; then
  echo "NOTARIZE must be 0 or 1." >&2
  exit 1
fi
if [[ "$NOTARIZE" == "1" && "$SIGNING_IDENTITY" == "-" ]]; then
  echo "NOTARIZE=1 requires SIGNING_IDENTITY='Developer ID Application: ...'." >&2
  exit 1
fi
if [[ "$NOTARIZE" == "1" && "$SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "NOTARIZE=1 requires a Developer ID Application signing identity." >&2
  exit 1
fi
if [[ "$NOTARIZE" == "1" ]]; then
  if [[ -z "$NOTARY_KEYCHAIN_PROFILE" && ( -z "$APPLE_ID" || -z "$APPLE_TEAM_ID" || -z "$APPLE_APP_SPECIFIC_PASSWORD" ) ]]; then
    echo "NOTARIZE=1 requires NOTARY_KEYCHAIN_PROFILE or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_SPECIFIC_PASSWORD." >&2
    exit 1
  fi
  bundle_identifier="$(plutil -extract identifier raw -o - "$ROOT_DIR/src-tauri/tauri.conf.json")"
  if [[ "$bundle_identifier" == com.local.* ]]; then
    echo "NOTARIZE=1 requires a real reverse-DNS bundle identifier, not $bundle_identifier." >&2
    exit 1
  fi
fi
npm run build:vite
npm run tauri -- build --bundles app

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app bundle: $APP_PATH" >&2
  exit 1
fi

codesign_args=(--force --deep --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  codesign_args+=(--options runtime --timestamp)
fi
codesign "${codesign_args[@]}" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$DMG_DIR"
ditto "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

detach_image_path "$DMG_PATH"
create_dmg "$DMG_PATH" "$STAGE_DIR"
verify_dmg "$DMG_PATH"

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

if [[ "$NOTARIZE" == "1" ]]; then
  notary_args=(notarytool submit "$DMG_PATH" --wait)
  if [[ -n "$NOTARY_KEYCHAIN_PROFILE" ]]; then
    notary_args+=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
  else
    notary_args+=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD")
  fi
  xcrun "${notary_args[@]}"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

attach_output="$(hdiutil attach -readonly -nobrowse "$DMG_PATH")"
printf '%s\n' "$attach_output"
MOUNT_POINT="$(printf '%s\n' "$attach_output" | awk -F '\t' '$NF ~ /^\/Volumes\// {print $NF; exit}')"
if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
  echo "Failed to resolve mounted DMG path." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$MOUNT_POINT/$APP_NAME.app"
hdiutil detach "$MOUNT_POINT"
MOUNT_POINT=""

shasum -a 256 "$DMG_PATH"
if [[ "${RUN_RELEASE_AUDIT:-1}" == "1" ]]; then
  REQUIRE_DISTRIBUTION="$NOTARIZE" "$ROOT_DIR/scripts/audit-release.sh"
fi
echo "macOS package ready: $DMG_PATH"
