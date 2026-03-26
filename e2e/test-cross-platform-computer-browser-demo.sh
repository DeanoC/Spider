#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINUX_HELPER="$ROOT_DIR/e2e/run_linux_cross_platform_computer_browser_host.sh"
FIXTURE_DIR="$ROOT_DIR/e2e/fixtures/macos-computer-browser"
FIXTURE_SWIFT="$FIXTURE_DIR/ComputerFixtureApp.swift"
BROWSER_FIXTURE_DIR="$FIXTURE_DIR/browser_fixture"
WRITE_CAPABILITY_MANIFESTS="$ROOT_DIR/e2e/write_capability_manifests.py"

OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/e2e/out/cross-platform-computer-browser-demo-$(date +%Y%m%d-%H%M%S)-$$}"
case "$OUTPUT_DIR" in
    "$ROOT_DIR"/*) RUN_DIR_REL="${OUTPUT_DIR#"$ROOT_DIR/"}" ;;
    *)
        echo "OUTPUT_DIR must live under $ROOT_DIR for Orb path sharing" >&2
        exit 1
        ;;
esac

LOG_DIR="$OUTPUT_DIR/logs"
STATE_DIR="$OUTPUT_DIR/state"
ARTIFACT_DIR="$OUTPUT_DIR/artifacts"
BUILD_DIR="$OUTPUT_DIR/build/macos"
TEMP_HOME="$OUTPUT_DIR/home"
REMOTE_EXPORT_COPY="$STATE_DIR/macos-remote-export"

SPIDERNODE_PREFIX="$BUILD_DIR/spidernode-prefix"
SPIDERNODE_LOCAL_CACHE="$BUILD_DIR/spidernode-local-cache"
SPIDERNODE_GLOBAL_CACHE="$BUILD_DIR/spidernode-global-cache"
LOCAL_NODE_BIN="$SPIDERNODE_PREFIX/bin/spiderweb-fs-node"

ORB_MACHINE="${ORB_MACHINE:-}"
ORB_IP="${ORB_IP:-}"
SPIDERWEB_PORT="${SPIDERWEB_PORT:-}"
LOCAL_WORKSPACE_NODE_PORT="${LOCAL_WORKSPACE_NODE_PORT:-}"
REMOTE_NODE_PORT="${REMOTE_NODE_PORT:-}"
REMOTE_NODE_NAME="${REMOTE_NODE_NAME:-cross-macos-computer-browser-node}"
REMOTE_EXPORT_NAME="${REMOTE_EXPORT_NAME:-macos-demo-export}"

MACOS_BROWSER_FIXTURE_PORT="${MACOS_BROWSER_FIXTURE_PORT:-}"
MACOS_BROWSER_URL=""
MACOS_FIXTURE_APP_BIN="$BUILD_DIR/SpiderCrossPlatformComputerFixture"
MACOS_FIXTURE_APP_LOG="$LOG_DIR/macos-computer-fixture.log"
MACOS_FIXTURE_APP_STATE="$STATE_DIR/macos-computer-fixture-state.json"
MACOS_BROWSER_HTTP_LOG="$LOG_DIR/macos-browser-fixture-http.log"
MACOS_CAPABILITY_MANIFEST_DIR="$STATE_DIR/macos-node-services.d"
MACOS_BROWSER_DRIVER_STATE="$STATE_DIR/macos-browser-driver/state.json"
MACOS_BROWSER_DRIVER_PROFILE="$STATE_DIR/macos-browser-driver/profile"

MACOS_FIXTURE_APP_NAME="${MACOS_FIXTURE_APP_NAME:-SpiderCrossPlatformComputerFixture}"
MACOS_WINDOW_TITLE="${MACOS_WINDOW_TITLE:-Spider Cross Platform Computer Fixture}"
BUTTON_TITLE="${BUTTON_TITLE:-Press Fixture Button}"

LINUX_COMPUTER_TEXT="${LINUX_COMPUTER_TEXT:-Hello from Linux target}"
MACOS_COMPUTER_TEXT="${MACOS_COMPUTER_TEXT:-Hello from macOS target}"
LINUX_BROWSER_TEXT="${LINUX_BROWSER_TEXT:-linux browser demo}"
MACOS_BROWSER_TEXT="${MACOS_BROWSER_TEXT:-mac browser demo}"

LOCAL_REMOTE_NODE_LOG="$LOG_DIR/macos-remote-node.log"
LOCAL_REMOTE_NODE_PID=""
MACOS_FIXTURE_APP_PID=""
MACOS_BROWSER_HTTP_PID=""

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }

require_bin() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_fail "missing required command: $1"
        exit 1
    fi
}

pick_free_port() {
    python3 - "$1" <<'PY'
import socket
import sys

host = sys.argv[1]
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind((host, 0))
    print(sock.getsockname()[1])
PY
}

pick_source_ip_for_target() {
    python3 - "$1" <<'PY'
import socket
import sys

target = sys.argv[1]
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    sock.connect((target, 80))
    print(sock.getsockname()[0])
finally:
    sock.close()
PY
}

wait_for_file() {
    local path="$1"
    local attempts="${2:-180}"
    for _ in $(seq 1 "$attempts"); do
        if [[ -f "$path" ]]; then
            return 0
        fi
        sleep 0.25
    done
    return 1
}

read_handoff_field() {
    local path="$1"
    local key="$2"
    python3 - "$path" "$key" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
value = data.get(sys.argv[2])
if value is None:
    print("")
else:
    print(value)
PY
}

orb_run() {
    local -a cmd=(orbctl run --path --workdir "$ROOT_DIR")
    if [[ -n "$ORB_MACHINE" ]]; then
        cmd+=(--machine "$ORB_MACHINE")
    fi
    "${cmd[@]}" env \
        RUN_DIR_REL="$RUN_DIR_REL" \
        SPIDERWEB_HOST_IP="$ORB_IP" \
        SPIDERWEB_PORT="$SPIDERWEB_PORT" \
        LOCAL_WORKSPACE_NODE_PORT="$LOCAL_WORKSPACE_NODE_PORT" \
        REMOTE_NODE_NAME="$REMOTE_NODE_NAME" \
        BUTTON_TITLE="$BUTTON_TITLE" \
        LINUX_COMPUTER_TEXT="$LINUX_COMPUTER_TEXT" \
        MACOS_COMPUTER_TEXT="$MACOS_COMPUTER_TEXT" \
        LINUX_BROWSER_TEXT="$LINUX_BROWSER_TEXT" \
        MACOS_BROWSER_TEXT="$MACOS_BROWSER_TEXT" \
        MACOS_BROWSER_URL="$MACOS_BROWSER_URL" \
        MACOS_APP_NAME="$MACOS_FIXTURE_APP_NAME" \
        MACOS_WINDOW_TITLE="$MACOS_WINDOW_TITLE" \
        MACOS_FIXTURE_STATE_PATH="$MACOS_FIXTURE_APP_STATE" \
        bash "$LINUX_HELPER" "$@"
}

ensure_playwright_browser() {
    log_info "Ensuring Playwright Chromium is installed for the isolated macOS home ..."
    HOME="$TEMP_HOME" playwright install chromium >/dev/null
}

compile_fixture_app() {
    log_info "Compiling macOS computer fixture app ..."
    swiftc -o "$MACOS_FIXTURE_APP_BIN" "$FIXTURE_SWIFT" -framework AppKit
}

prepare_remote_export() {
    mkdir -p "$REMOTE_EXPORT_COPY"
    printf 'macOS remote export for cross-platform computer/browser demo\n' >"$REMOTE_EXPORT_COPY/README.txt"
}

write_macos_capability_manifests() {
    log_info "Writing macOS capability manifests ..."
    python3 "$WRITE_CAPABILITY_MANIFESTS" \
        --platform macos \
        --output-dir "$MACOS_CAPABILITY_MANIFEST_DIR" \
        --computer-driver "$SPIDERNODE_PREFIX/bin/spiderweb-computer-driver" \
        --browser-driver "$SPIDERNODE_PREFIX/bin/spiderweb-browser-driver" \
        --browser-state-path "$MACOS_BROWSER_DRIVER_STATE" \
        --browser-profile-dir "$MACOS_BROWSER_DRIVER_PROFILE"
}

start_browser_fixture_server() {
    log_info "Starting macOS browser fixture server ..."
    (
        cd "$BROWSER_FIXTURE_DIR"
        python3 -m http.server "$MACOS_BROWSER_FIXTURE_PORT" --bind 127.0.0.1
    ) >"$MACOS_BROWSER_HTTP_LOG" 2>&1 &
    MACOS_BROWSER_HTTP_PID="$!"
    MACOS_BROWSER_URL="http://127.0.0.1:${MACOS_BROWSER_FIXTURE_PORT}/index.html"
}

start_fixture_app() {
    log_info "Launching the deterministic macOS fixture app ..."
    SPIDER_FIXTURE_STATE_PATH="$MACOS_FIXTURE_APP_STATE" \
    SPIDER_FIXTURE_WINDOW_TITLE="$MACOS_WINDOW_TITLE" \
    SPIDER_FIXTURE_BUTTON_TITLE="$BUTTON_TITLE" \
    SPIDER_FIXTURE_INITIAL_TEXT="" \
    "$MACOS_FIXTURE_APP_BIN" >"$MACOS_FIXTURE_APP_LOG" 2>&1 &
    MACOS_FIXTURE_APP_PID="$!"

    if ! wait_for_file "$MACOS_FIXTURE_APP_STATE" 120; then
        log_fail "macOS fixture app did not create its state file"
        tail -n 100 "$MACOS_FIXTURE_APP_LOG" || true
        exit 1
    fi
}

cleanup() {
    local exit_code=$?
    if [[ -n "$LOCAL_REMOTE_NODE_PID" ]]; then
        kill "$LOCAL_REMOTE_NODE_PID" >/dev/null 2>&1 || true
        wait "$LOCAL_REMOTE_NODE_PID" >/dev/null 2>&1 || true
    fi
    if [[ -n "$MACOS_FIXTURE_APP_PID" ]]; then
        kill "$MACOS_FIXTURE_APP_PID" >/dev/null 2>&1 || true
        wait "$MACOS_FIXTURE_APP_PID" >/dev/null 2>&1 || true
    fi
    if [[ -n "$MACOS_BROWSER_HTTP_PID" ]]; then
        kill "$MACOS_BROWSER_HTTP_PID" >/dev/null 2>&1 || true
        wait "$MACOS_BROWSER_HTTP_PID" >/dev/null 2>&1 || true
    fi
    if [[ -f "$LINUX_HELPER" ]] && command -v orbctl >/dev/null 2>&1; then
        orb_run cleanup >/dev/null 2>&1 || true
    fi
    exit "$exit_code"
}
trap cleanup EXIT

main() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_fail "this cross-platform demo currently requires macOS with OrbStack"
        exit 1
    fi

    require_bin orbctl
    require_bin python3
    require_bin zig
    require_bin swiftc
    require_bin node
    require_bin playwright
    require_bin codex

    if [[ ! -f "$FIXTURE_SWIFT" || ! -d "$BROWSER_FIXTURE_DIR" ]]; then
        log_fail "missing macOS fixtures under $FIXTURE_DIR"
        exit 1
    fi

    mkdir -p "$OUTPUT_DIR" "$LOG_DIR" "$STATE_DIR" "$ARTIFACT_DIR" "$BUILD_DIR" "$TEMP_HOME"
    prepare_remote_export

    if [[ -z "$ORB_IP" ]]; then
        ORB_IP="$(orbctl list | awk '/running/ && $NF ~ /^[0-9.]+$/ {print $NF; exit}')"
    fi
    if [[ -z "$ORB_IP" ]]; then
        log_fail "could not determine a running Orb Linux machine IP"
        exit 1
    fi

    if [[ -z "$SPIDERWEB_PORT" ]]; then
        SPIDERWEB_PORT="$(pick_free_port 127.0.0.1)"
    fi

    if [[ -z "$MACOS_BROWSER_FIXTURE_PORT" ]]; then
        MACOS_BROWSER_FIXTURE_PORT="$(pick_free_port 127.0.0.1)"
    fi

    local mac_host_ip
    mac_host_ip="$(pick_source_ip_for_target "$ORB_IP")"
    if [[ -z "$mac_host_ip" ]]; then
        log_fail "could not determine a macOS source IP that can reach Orb host $ORB_IP"
        exit 1
    fi
    if [[ -z "$mac_host_ip" ]]; then
        log_fail "could not determine the macOS host IP reachable from Orb"
        exit 1
    fi
    if [[ -z "$REMOTE_NODE_PORT" ]]; then
        REMOTE_NODE_PORT="$(pick_free_port "$mac_host_ip")"
    fi

    log_info "Building macOS SpiderNode binary into isolated prefix ..."
    (
        cd "$ROOT_DIR/SpiderNode"
        zig build \
            --prefix "$SPIDERNODE_PREFIX" \
            --cache-dir "$SPIDERNODE_LOCAL_CACHE" \
            --global-cache-dir "$SPIDERNODE_GLOBAL_CACHE"
    )

    ensure_playwright_browser
    compile_fixture_app
    start_browser_fixture_server
    start_fixture_app
    write_macos_capability_manifests

    log_info "Building Linux Spiderweb/SpiderNode side in Orb ..."
    orb_run build

    log_info "Starting Linux Spiderweb host stack in Orb ..."
    orb_run start_host_stack

    local handoff_file="$ARTIFACT_DIR/control_handoff.json"
    if ! wait_for_file "$handoff_file"; then
        log_fail "Linux host stack did not write a handoff file"
        exit 1
    fi

    local control_url control_auth_token remote_invite_token
    control_url="$(read_handoff_field "$handoff_file" control_url)"
    control_auth_token="$(read_handoff_field "$handoff_file" control_auth_token)"
    remote_invite_token="$(read_handoff_field "$handoff_file" remote_invite_token)"
    if [[ -z "$control_url" || -z "$control_auth_token" || -z "$remote_invite_token" ]]; then
        log_fail "handoff file is missing required control credentials"
        cat "$handoff_file"
        exit 1
    fi

    log_info "Starting macOS remote capability node on $mac_host_ip:$REMOTE_NODE_PORT ..."
    HOME="$TEMP_HOME" \
    "$LOCAL_NODE_BIN" \
        --bind "$mac_host_ip" \
        --port "$REMOTE_NODE_PORT" \
        --export "$REMOTE_EXPORT_NAME=$REMOTE_EXPORT_COPY:rw" \
        --venoms-dir "$MACOS_CAPABILITY_MANIFEST_DIR" \
        --control-url "$control_url" \
        --control-auth-token "$control_auth_token" \
        --pair-mode invite \
        --invite-token "$remote_invite_token" \
        --node-name "$REMOTE_NODE_NAME" \
        --state-file "$STATE_DIR/macos-remote-node-state.json" \
        >"$LOCAL_REMOTE_NODE_LOG" 2>&1 &
    LOCAL_REMOTE_NODE_PID="$!"

    log_info "Running the cross-platform single-agent demo in Orb ..."
    orb_run finish_scenario

    if [[ ! -f "$ARTIFACT_DIR/cross_platform_result.json" || ! -f "$ARTIFACT_DIR/cross_platform_demo_validation.json" ]]; then
        log_fail "cross-platform demo did not produce the expected result artifacts"
        exit 1
    fi

    log_pass "Cross-platform computer/browser demo completed"
    log_info "Artifacts:"
    echo "  $handoff_file"
    echo "  $ARTIFACT_DIR/cross_platform_result.json"
    echo "  $ARTIFACT_DIR/cross_platform_demo_summary.json"
    echo "  $ARTIFACT_DIR/cross_platform_demo_validation.json"
    echo "  $ARTIFACT_DIR/targets.catalog.json"
    echo "  $ARTIFACT_DIR/final/linux/computer/last_observation.json"
    echo "  $ARTIFACT_DIR/final/macos/browser/last_dom.json"
}

main "$@"
