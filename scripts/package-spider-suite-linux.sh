#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPIDERAPP_REPO="${SPIDERAPP_REPO:-$REPO_ROOT/SpiderApp}"
SPIDERWEB_REPO="${SPIDERWEB_REPO:-$REPO_ROOT/Spiderweb}"
SPIDERNODE_REPO="${SPIDERNODE_REPO:-$REPO_ROOT/SpiderNode}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/dist}"
SKIP_GIT_SUBMODULE_UPDATE="${SKIP_GIT_SUBMODULE_UPDATE:-0}"

usage() {
  cat <<'EOF'
Build a Linux Spider suite archive containing:
  - spider CLI
  - spiderweb host/runtime binaries
  - spiderweb-fs-node
  - shared runtime assets

Usage:
  package-spider-suite-linux.sh [--out-dir <dir>]

Outputs:
  <out-dir>/SpiderSuite-linux-<arch>-spiderweb-<spiderweb-version>-spiderapp-<spiderapp-version>.tar.gz
  <out-dir>/SpiderSuite-linux-<arch>-spiderweb-<spiderweb-version>-spiderapp-<spiderapp-version>.tar.gz.sha256
  <out-dir>/spider-suite-linux-<arch>.tar.gz
  <out-dir>/spider-suite-linux-<arch>.tar.gz.sha256
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

version_from_zon() {
  local zon_path="$1"
  sed -n 's/.*\.version = "\(.*\)",/\1/p' "$zon_path" | head -n1
}

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH_LABEL="x86_64" ;;
  aarch64|arm64) ARCH_LABEL="aarch64" ;;
  *) ARCH_LABEL="$ARCH" ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      [[ $# -ge 2 ]] || fail "--out-dir requires a value"
      OUT_DIR="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

require_command zig
require_command tar
require_command cp
require_command mkdir
if [[ "$SKIP_GIT_SUBMODULE_UPDATE" != "1" ]]; then
  require_command git
fi
require_command mktemp
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  fail "missing required command: sha256sum or shasum"
fi

SPIDERAPP_VERSION="$(version_from_zon "$SPIDERAPP_REPO/build.zig.zon")"
SPIDERWEB_VERSION="$(version_from_zon "$SPIDERWEB_REPO/build.zig.zon")"
[[ -n "$SPIDERAPP_VERSION" ]] || fail "could not determine SpiderApp version"
[[ -n "$SPIDERWEB_VERSION" ]] || fail "could not determine Spiderweb version"

WORK_ROOT="$(mktemp -d)"
trap 'rm -rf "$WORK_ROOT"' EXIT

SPIDERAPP_PREFIX="$WORK_ROOT/spiderapp-prefix"
SPIDERNODE_PREFIX="$WORK_ROOT/spidernode-prefix"
SPIDERWEB_OUT="$WORK_ROOT/spiderweb-out"
SPIDERWEB_EXTRACT="$WORK_ROOT/spiderweb-extract"
SUITE_NAME="SpiderSuite-linux-${ARCH_LABEL}-spiderweb-${SPIDERWEB_VERSION}-spiderapp-${SPIDERAPP_VERSION}"
SUITE_ROOT="$WORK_ROOT/$SUITE_NAME"
ARCHIVE_PATH="$OUT_DIR/${SUITE_NAME}.tar.gz"
ARCHIVE_SHA_PATH="${ARCHIVE_PATH}.sha256"
LATEST_ALIAS_PATH="$OUT_DIR/spider-suite-linux-${ARCH_LABEL}.tar.gz"
LATEST_ALIAS_SHA_PATH="${LATEST_ALIAS_PATH}.sha256"

mkdir -p "$SPIDERAPP_PREFIX" "$SPIDERNODE_PREFIX" "$SPIDERWEB_OUT" "$SPIDERWEB_EXTRACT" "$SUITE_ROOT" "$OUT_DIR"

if [[ "$SKIP_GIT_SUBMODULE_UPDATE" != "1" ]]; then
  echo "==> Ensuring SpiderApp, SpiderNode, and Spiderweb submodules are ready"
  git -C "$SPIDERAPP_REPO" submodule update --init --recursive
  git -C "$SPIDERNODE_REPO" submodule update --init --recursive
  git -C "$SPIDERWEB_REPO" submodule update --init --recursive
fi

echo "==> Building SpiderApp CLI install prefix"
(
  cd "$SPIDERAPP_REPO"
  zig build --release=safe -Dcli-only=true cli
)
mkdir -p "$SPIDERAPP_PREFIX/bin"
cp "$SPIDERAPP_REPO/zig-out/bin/spider" "$SPIDERAPP_PREFIX/bin/spider"
[[ -x "$SPIDERAPP_PREFIX/bin/spider" ]] || fail "missing spider CLI in staged prefix"

echo "==> Building SpiderNode daemon install prefix"
(
  cd "$SPIDERNODE_REPO"
  zig build install --release=safe --prefix "$SPIDERNODE_PREFIX"
)
[[ -x "$SPIDERNODE_PREFIX/bin/spiderweb-fs-node" ]] || fail "missing spiderweb-fs-node in SpiderNode prefix"

echo "==> Building Spiderweb Linux release archive"
"$SPIDERWEB_REPO/scripts/package-spiderweb-linux-release.sh" --out-dir "$SPIDERWEB_OUT"

SPIDERWEB_ARCHIVE="$SPIDERWEB_OUT/spiderweb-linux-${ARCH_LABEL}.tar.gz"
[[ -f "$SPIDERWEB_ARCHIVE" ]] || fail "missing Spiderweb Linux archive: $SPIDERWEB_ARCHIVE"

echo "==> Extracting Spiderweb Linux release archive"
tar -xzf "$SPIDERWEB_ARCHIVE" -C "$SPIDERWEB_EXTRACT"
SPIDERWEB_ROOT="$SPIDERWEB_EXTRACT/spiderweb-linux-${ARCH_LABEL}"
[[ -d "$SPIDERWEB_ROOT" ]] || fail "unexpected Spiderweb archive layout"

echo "==> Staging Spider suite payload"
mkdir -p "$SUITE_ROOT/bin" "$SUITE_ROOT/share/spider/systemd" "$SUITE_ROOT/docs"
cp "$SPIDERAPP_PREFIX/bin/spider" "$SUITE_ROOT/bin/spider"
cp -R "$SPIDERWEB_ROOT/bin/." "$SUITE_ROOT/bin/"
cp -R "$SPIDERWEB_ROOT/share/." "$SUITE_ROOT/share/"
cp "$SPIDERNODE_PREFIX/bin/spiderweb-fs-node" "$SUITE_ROOT/bin/spiderweb-fs-node"

cat >"$SUITE_ROOT/share/spider/systemd/spiderweb.service.example" <<'EOF'
[Unit]
Description=Spiderweb Workspace Host
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/spiderweb
WorkingDirectory=%h/Spiderweb
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat >"$SUITE_ROOT/share/spider/systemd/spider-node.service.example" <<'EOF'
[Unit]
Description=Spider Linux Node
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/spiderweb-fs-node --config %h/.config/spider/linux-node.json
WorkingDirectory=%h/.config/spider
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cp "$REPO_ROOT/docs/linux-host-spiderweb.md" "$SUITE_ROOT/docs/host-spiderweb-on-linux.md" 2>/dev/null || true
cp "$REPO_ROOT/docs/linux-connect-node.md" "$SUITE_ROOT/docs/connect-linux-node.md" 2>/dev/null || true

cat >"$SUITE_ROOT/manifest.json" <<EOF
{
  "suite": "SpiderSuite",
  "platform": "linux",
  "arch": "${ARCH_LABEL}",
  "spiderapp_version": "${SPIDERAPP_VERSION}",
  "spiderweb_version": "${SPIDERWEB_VERSION}",
  "binaries": [
    "spider",
    "spiderweb",
    "spiderweb-config",
    "spiderweb-control",
    "spiderweb-fs-mount",
    "spiderweb-fs-node",
    "spiderweb-local-node"
  ]
}
EOF

echo "==> Writing suite archive"
rm -f "$ARCHIVE_PATH" "$ARCHIVE_SHA_PATH" "$LATEST_ALIAS_PATH" "$LATEST_ALIAS_SHA_PATH"
tar -C "$WORK_ROOT" -czf "$ARCHIVE_PATH" "$SUITE_NAME"
ARCHIVE_SHA="$(sha256_file "$ARCHIVE_PATH")"
printf '%s  %s\n' "$ARCHIVE_SHA" "$(basename "$ARCHIVE_PATH")" >"$ARCHIVE_SHA_PATH"
cp "$ARCHIVE_PATH" "$LATEST_ALIAS_PATH"
printf '%s  %s\n' "$ARCHIVE_SHA" "$(basename "$LATEST_ALIAS_PATH")" >"$LATEST_ALIAS_SHA_PATH"

echo "Archive: $ARCHIVE_PATH"
echo "SHA256:  $ARCHIVE_SHA_PATH"
echo "Alias:   $LATEST_ALIAS_PATH"
