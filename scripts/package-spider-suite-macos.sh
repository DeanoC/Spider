#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SPIDERWEB_DIR="$ROOT_DIR/Spiderweb"
SPIDERAPP_DIR="$ROOT_DIR/SpiderApp"
SPIDERWEB_PACKAGE_SCRIPT="$SPIDERWEB_DIR/platform/macos/scripts/package-spiderweb-macos-release.sh"
SPIDERAPP_PACKAGE_SCRIPT="$SPIDERAPP_DIR/scripts/package-macos-app.sh"
SUITE_RELEASE_NOTES_TEMPLATE="$ROOT_DIR/docs/releases/spidersuite-macos-template.md"

usage() {
  cat <<'EOF'
Build a parent-level macOS Spider suite installer by orchestrating the product-local packagers.

Usage:
  package-spider-suite-macos.sh [--out-dir <dir>] [--skip-notarize]

What it does:
  - builds/packages Spiderweb with its existing signed macOS release script
  - builds/packages SpiderApp with its existing macOS app bundle script
  - stages both outputs into one suite folder with a manifest
  - builds a top-level signed SpiderSuite installer package
  - zips that suite folder for handoff or release staging

Notes:
  - Spiderweb signing/notarization env vars are still required because this script delegates
    to Spiderweb's own release packager.
  - The suite packager re-signs the staged SpiderApp bundle with the Developer ID Application
    identity that Spiderweb already requires, then installs it via a signed component package.

Outputs:
  <out-dir>/SpiderSuite-macos-spiderweb-<spiderweb-version>-spiderapp-<spiderapp-version>.pkg
  <out-dir>/SpiderSuite-macos-spiderweb-<spiderweb-version>-spiderapp-<spiderapp-version>/
  <out-dir>/SpiderSuite-macos-spiderweb-<spiderweb-version>-spiderapp-<spiderapp-version>.zip
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

read_version() {
  local zon_path="$1"
  python3 - <<'PY' "$zon_path"
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
match = re.search(r'\.version\s*=\s*"([^"]+)"', text)
if not match:
    raise SystemExit("unknown")
print(match.group(1))
PY
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "missing required file: $path"
}

require_dir() {
  local path="$1"
  [[ -d "$path" ]] || fail "missing required directory: $path"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

write_suite_release_notes() {
  local template_path="$1"
  local output_path="$2"
  local suite_name="$3"
  local spiderweb_version="$4"
  local spiderapp_version="$5"
  local suite_pkg_name="$6"

  python3 - <<'PY' "$template_path" "$output_path" "$suite_name" "$spiderweb_version" "$spiderapp_version" "$suite_pkg_name"
from pathlib import Path
from datetime import date
import sys

template_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
suite_name = sys.argv[3]
spiderweb_version = sys.argv[4]
spiderapp_version = sys.argv[5]
suite_pkg_name = sys.argv[6]

text = template_path.read_text()
replacements = {
    "{{RELEASE_DATE}}": date.today().isoformat(),
    "{{SUITE_NAME}}": suite_name,
    "{{SPIDERWEB_VERSION}}": spiderweb_version,
    "{{SPIDERAPP_VERSION}}": spiderapp_version,
    "{{SUITE_PKG_NAME}}": suite_pkg_name,
}
for needle, replacement in replacements.items():
    text = text.replace(needle, replacement)

output_path.write_text(text)
PY
}

OUT_DIR="$ROOT_DIR/dist"
SKIP_NOTARIZE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      OUT_DIR="${2:?missing value for --out-dir}"
      shift 2
      ;;
    --skip-notarize)
      SKIP_NOTARIZE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

require_dir "$SPIDERWEB_DIR"
require_dir "$SPIDERAPP_DIR"
require_file "$SPIDERWEB_PACKAGE_SCRIPT"
require_file "$SPIDERAPP_PACKAGE_SCRIPT"
require_file "$SUITE_RELEASE_NOTES_TEMPLATE"

SPIDERWEB_VERSION="$(read_version "$SPIDERWEB_DIR/build.zig.zon")"
SPIDERAPP_VERSION="$(read_version "$SPIDERAPP_DIR/build.zig.zon")"
HOST_ARCH="$(uname -m)"
SUITE_NAME="SpiderSuite-macos-spiderweb-${SPIDERWEB_VERSION}-spiderapp-${SPIDERAPP_VERSION}"
SUITE_DIR="$OUT_DIR/$SUITE_NAME"
SUITE_PKG_PATH="$OUT_DIR/$SUITE_NAME.pkg"
ZIP_PATH="$OUT_DIR/$SUITE_NAME.zip"
SPIDERWEB_PKG_ID="com.deanoc.spiderweb.filesystems.fs.spiderweb.pkg"
SPIDERAPP_PKG_ID="com.deanocalver.spiderapp.pkg"

require_command codesign
require_command ditto
require_command pkgbuild
require_command productbuild
require_command python3

mkdir -p "$OUT_DIR"
rm -rf "$SUITE_DIR" "$ZIP_PATH" "$SUITE_PKG_PATH"

WORK_ROOT="$(mktemp -d /tmp/spider-suite-macos.XXXXXX)"
trap 'rm -rf "$WORK_ROOT"' EXIT
SUITE_PKG_WORK_DIR="$WORK_ROOT/suite-pkg"
mkdir -p "$SUITE_PKG_WORK_DIR"

echo "==> Packaging Spiderweb"
SPIDERWEB_DIST_DIR="$OUT_DIR/.spiderweb-dist"
rm -rf "$SPIDERWEB_DIST_DIR"
mkdir -p "$SPIDERWEB_DIST_DIR"
SPIDERWEB_ARGS=(--out-dir "$SPIDERWEB_DIST_DIR")
if [[ "$SKIP_NOTARIZE" == "1" ]]; then
  SPIDERWEB_ARGS+=(--skip-notarize)
fi
"$SPIDERWEB_PACKAGE_SCRIPT" "${SPIDERWEB_ARGS[@]}"

SPIDERWEB_PKG_PATH="$SPIDERWEB_DIST_DIR/Spiderweb-macos-${SPIDERWEB_VERSION}.pkg"
require_file "$SPIDERWEB_PKG_PATH"

echo "==> Packaging SpiderApp"
"$SPIDERAPP_PACKAGE_SCRIPT"

SPIDERAPP_APP_PATH="$SPIDERAPP_DIR/zig-out/SpiderApp.app"
SPIDERAPP_ZIP_PATH="$SPIDERAPP_DIR/zig-out/SpiderApp-macos-${HOST_ARCH}.zip"
require_dir "$SPIDERAPP_APP_PATH"
require_file "$SPIDERAPP_ZIP_PATH"

echo "==> Staging suite bundle"
mkdir -p "$SUITE_DIR/Spiderweb" "$SUITE_DIR/SpiderApp"
cp "$SPIDERWEB_PKG_PATH" "$SUITE_DIR/Spiderweb/"
ditto "$SPIDERAPP_APP_PATH" "$SUITE_DIR/SpiderApp/SpiderApp.app"

echo "==> Re-signing staged SpiderApp bundle"
codesign --force --sign "$SPIDERWEB_MACOS_DEVELOPER_ID_APPLICATION" --timestamp --options runtime \
  "$SUITE_DIR/SpiderApp/SpiderApp.app/Contents/Resources/spider"
codesign --force --deep --sign "$SPIDERWEB_MACOS_DEVELOPER_ID_APPLICATION" --timestamp --options runtime \
  "$SUITE_DIR/SpiderApp/SpiderApp.app"
codesign --verify --deep --strict "$SUITE_DIR/SpiderApp/SpiderApp.app"

STAGED_SPIDERAPP_ZIP_PATH="$SUITE_DIR/SpiderApp/$(basename "$SPIDERAPP_ZIP_PATH")"
rm -f "$STAGED_SPIDERAPP_ZIP_PATH"
ditto -c -k --keepParent "$SUITE_DIR/SpiderApp/SpiderApp.app" "$STAGED_SPIDERAPP_ZIP_PATH"

echo "==> Building SpiderSuite installer package"
SPIDERAPP_COMPONENT_PKG="$SUITE_PKG_WORK_DIR/SpiderApp-macos-${HOST_ARCH}.pkg"
pkgbuild \
  --component "$SUITE_DIR/SpiderApp/SpiderApp.app" \
  --install-location "/Applications" \
  --identifier "$SPIDERAPP_PKG_ID" \
  --version "$SPIDERAPP_VERSION" \
  --sign "$SPIDERWEB_MACOS_DEVELOPER_ID_INSTALLER" \
  "$SPIDERAPP_COMPONENT_PKG"

cp "$SPIDERWEB_PKG_PATH" "$SUITE_PKG_WORK_DIR/$(basename "$SPIDERWEB_PKG_PATH")"

python3 - <<'PY' \
  "$SUITE_PKG_WORK_DIR/Distribution.xml" \
  "$SUITE_NAME" \
  "$SPIDERWEB_VERSION" \
  "$SPIDERAPP_VERSION" \
  "$SPIDERWEB_PKG_ID" \
  "$(basename "$SPIDERWEB_PKG_PATH")" \
  "$SPIDERAPP_PKG_ID" \
  "$(basename "$SPIDERAPP_COMPONENT_PKG")"
from pathlib import Path
import sys

distribution_path = Path(sys.argv[1])
suite_name = sys.argv[2]
spiderweb_version = sys.argv[3]
spiderapp_version = sys.argv[4]
spiderweb_pkg_id = sys.argv[5]
spiderweb_pkg_file = sys.argv[6]
spiderapp_pkg_id = sys.argv[7]
spiderapp_pkg_file = sys.argv[8]

distribution_path.write_text(f"""<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>{suite_name}</title>
  <options customize="never" require-scripts="false"/>
  <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
  <choices-outline>
    <line choice="choice.spiderweb"/>
    <line choice="choice.spiderapp"/>
  </choices-outline>
  <choice id="choice.spiderweb" title="Spiderweb">
    <pkg-ref id="{spiderweb_pkg_id}"/>
  </choice>
  <choice id="choice.spiderapp" title="SpiderApp">
    <pkg-ref id="{spiderapp_pkg_id}"/>
  </choice>
  <pkg-ref id="{spiderweb_pkg_id}" version="{spiderweb_version}">{spiderweb_pkg_file}</pkg-ref>
  <pkg-ref id="{spiderapp_pkg_id}" version="{spiderapp_version}">{spiderapp_pkg_file}</pkg-ref>
</installer-gui-script>
""")
PY

productbuild \
  --distribution "$SUITE_PKG_WORK_DIR/Distribution.xml" \
  --package-path "$SUITE_PKG_WORK_DIR" \
  --sign "$SPIDERWEB_MACOS_DEVELOPER_ID_INSTALLER" \
  "$SUITE_PKG_PATH"

if [[ "$SKIP_NOTARIZE" != "1" && -n "${SPIDERWEB_MACOS_NOTARY_PROFILE:-}" ]]; then
  echo "==> Notarizing SpiderSuite installer package"
  xcrun notarytool submit "$SUITE_PKG_PATH" --keychain-profile "$SPIDERWEB_MACOS_NOTARY_PROFILE" --wait
  echo "==> Stapling SpiderSuite installer package"
  xcrun stapler staple "$SUITE_PKG_PATH"
fi

cp "$SUITE_PKG_PATH" "$SUITE_DIR/"
write_suite_release_notes \
  "$SUITE_RELEASE_NOTES_TEMPLATE" \
  "$SUITE_DIR/RELEASE_NOTES.md" \
  "$SUITE_NAME" \
  "$SPIDERWEB_VERSION" \
  "$SPIDERAPP_VERSION" \
  "$(basename "$SUITE_PKG_PATH")"

python3 - <<'PY' \
  "$SUITE_DIR/manifest.json" \
  "$SUITE_NAME" \
  "$SPIDERWEB_VERSION" \
  "$SPIDERAPP_VERSION" \
  "$HOST_ARCH" \
  "$SPIDERWEB_PKG_PATH" \
  "$SUITE_DIR/SpiderApp/SpiderApp.app" \
  "$STAGED_SPIDERAPP_ZIP_PATH" \
  "$SUITE_PKG_PATH"
from pathlib import Path
import json
import sys
from datetime import datetime, timezone

manifest_path = Path(sys.argv[1])
manifest = {
  "schema": 1,
  "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "suite": {
    "name": sys.argv[2],
    "platform": "macos",
    "host_arch": sys.argv[5],
    "installer_pkg": Path(sys.argv[9]).name,
    "source_installer_path": sys.argv[9],
  },
  "products": {
    "Spiderweb": {
      "version": sys.argv[3],
      "artifact": "Spiderweb/" + Path(sys.argv[6]).name,
      "source_path": sys.argv[6],
    },
    "SpiderApp": {
      "version": sys.argv[4],
      "app_bundle": "SpiderApp/SpiderApp.app",
      "zip_artifact": "SpiderApp/" + Path(sys.argv[8]).name,
      "source_app_path": sys.argv[7],
      "source_zip_path": sys.argv[8],
    },
  },
}
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
PY

echo "==> Creating suite zip"
ditto -c -k --keepParent "$SUITE_DIR" "$ZIP_PATH"

echo "Created suite installer: $SUITE_PKG_PATH"
echo "Created suite directory: $SUITE_DIR"
echo "Created suite archive: $ZIP_PATH"
