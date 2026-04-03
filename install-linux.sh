#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
ARCHIVE_PATH=""
ARCHIVE_URL=""
SKIP_ONBOARDING=0

usage() {
  cat <<'EOF'
Install Spider on Ubuntu/Debian-style Linux hosts.

This installer stages the Spider suite payload under /usr/local, then opens
the guided spider CLI so you can either host Spiderweb here or connect this
machine as a remote node.

Usage:
  ./install-linux.sh [--archive <path> | --url <url>] [--prefix <dir>] [--skip-onboarding]

Defaults:
  - downloads the latest matching spider-suite-linux-<arch>.tar.gz release asset
  - installs binaries into /usr/local/bin
  - installs shared assets into /usr/local/share
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)
      [[ $# -ge 2 ]] || fail "--archive requires a value"
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    --url)
      [[ $# -ge 2 ]] || fail "--url requires a value"
      ARCHIVE_URL="$2"
      shift 2
      ;;
    --prefix)
      [[ $# -ge 2 ]] || fail "--prefix requires a value"
      PREFIX="$2"
      shift 2
      ;;
    --skip-onboarding)
      SKIP_ONBOARDING=1
      shift
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

need_cmd tar
need_cmd mkdir
need_cmd cp

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH_LABEL="x86_64" ;;
  aarch64|arm64) ARCH_LABEL="aarch64" ;;
  *) fail "unsupported architecture: $ARCH" ;;
esac

if [[ -z "$ARCHIVE_PATH" && -z "$ARCHIVE_URL" ]]; then
  ARCHIVE_URL="https://github.com/DeanoC/Spider/releases/latest/download/spider-suite-linux-${ARCH_LABEL}.tar.gz"
fi

WORK_ROOT="$(mktemp -d)"
trap 'rm -rf "$WORK_ROOT"' EXIT

if [[ -n "$ARCHIVE_URL" ]]; then
  need_cmd curl
  ARCHIVE_PATH="$WORK_ROOT/spider-suite-linux-${ARCH_LABEL}.tar.gz"
  echo "==> Downloading Spider Linux suite for ${ARCH_LABEL}"
  curl -fL "$ARCHIVE_URL" -o "$ARCHIVE_PATH"
fi

[[ -f "$ARCHIVE_PATH" ]] || fail "archive not found: $ARCHIVE_PATH"

EXTRACT_ROOT="$WORK_ROOT/extract"
mkdir -p "$EXTRACT_ROOT"
echo "==> Extracting archive"
tar -xzf "$ARCHIVE_PATH" -C "$EXTRACT_ROOT"

SUITE_ROOT="$(find "$EXTRACT_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)"
[[ -n "$SUITE_ROOT" ]] || fail "could not locate extracted Spider suite root"

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
  need_cmd sudo
  SUDO="sudo"
fi

echo "==> Installing binaries into $PREFIX/bin"
$SUDO mkdir -p "$PREFIX/bin" "$PREFIX/share"
$SUDO cp -f "$SUITE_ROOT/bin/"* "$PREFIX/bin/"
if [[ -d "$SUITE_ROOT/share" ]]; then
  $SUDO mkdir -p "$PREFIX/share"
  $SUDO cp -R "$SUITE_ROOT/share/." "$PREFIX/share/"
fi

echo "==> Installed:"
echo "  spider"
echo "  spiderweb"
echo "  spiderweb-config"
echo "  spiderweb-fs-node"

if [[ "$SKIP_ONBOARDING" -eq 1 ]]; then
  echo "==> Skipping guided onboarding"
  exit 0
fi

if [[ ! -t 0 || ! -t 1 ]]; then
  echo "==> Non-interactive shell detected; skipping guided onboarding"
  echo "Run: $PREFIX/bin/spider"
  exit 0
fi

echo "==> Launching Spider guided setup"
exec "$PREFIX/bin/spider"
