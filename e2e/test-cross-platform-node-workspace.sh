#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/e2e/output-cleanup.sh"
LINUX_HELPER="$ROOT_DIR/e2e/run_linux_spiderweb_host.sh"
REMOTE_FIXTURE_DIR="$ROOT_DIR/e2e/fixtures/remote-smoke"

OUTPUT_DIR_WAS_EXPLICIT=0
if [[ -n "${OUTPUT_DIR+x}" ]]; then
    OUTPUT_DIR_WAS_EXPLICIT=1
else
    OUTPUT_DIR="$ROOT_DIR/e2e/out/cross-platform-node-workspace-$(date +%Y%m%d-%H%M%S)-$$"
fi
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

SPIDERNODE_PREFIX="$BUILD_DIR/spidernode-prefix"
SPIDERNODE_LOCAL_CACHE="$BUILD_DIR/spidernode-local-cache"
SPIDERNODE_GLOBAL_CACHE="$BUILD_DIR/spidernode-global-cache"
LOCAL_NODE_BIN="$SPIDERNODE_PREFIX/bin/spiderweb-fs-node"

ORB_MACHINE="${ORB_MACHINE:-}"
ORB_IP="${ORB_IP:-}"
SPIDERWEB_PORT="${SPIDERWEB_PORT:-28790}"
LOCAL_WORKSPACE_NODE_PORT="${LOCAL_WORKSPACE_NODE_PORT:-28911}"
REMOTE_NODE_PORT="${REMOTE_NODE_PORT:-28912}"
REMOTE_NODE_NAME="${REMOTE_NODE_NAME:-cross-macos-remote-node}"
REMOTE_EXPORT_NAME="${REMOTE_EXPORT_NAME:-remote-smoke}"
KEEP_OUTPUT="${KEEP_OUTPUT:-}"

LOCAL_REMOTE_NODE_LOG="$LOG_DIR/macos-remote-node.log"
LOCAL_REMOTE_NODE_PID=""

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
    for _ in $(seq 1 180); do
        if [[ -f "$path" ]]; then
            return 0
        fi
        sleep 0.2
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
        REMOTE_EXPORT_NAME="$REMOTE_EXPORT_NAME" \
        bash "$LINUX_HELPER" "$@"
}

cleanup() {
    local exit_code=$?
    if [[ -n "$LOCAL_REMOTE_NODE_PID" ]]; then
        kill "$LOCAL_REMOTE_NODE_PID" >/dev/null 2>&1 || true
        wait "$LOCAL_REMOTE_NODE_PID" >/dev/null 2>&1 || true
    fi
    if [[ -f "$LINUX_HELPER" ]] && command -v orbctl >/dev/null 2>&1; then
        orb_run cleanup >/dev/null 2>&1 || true
    fi
    e2e_cleanup_output_dir "$exit_code" "$OUTPUT_DIR" "$OUTPUT_DIR_WAS_EXPLICIT" "$KEEP_OUTPUT"
    exit "$exit_code"
}
trap cleanup EXIT

main() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_fail "the initial cross-platform lane currently requires macOS with OrbStack"
        exit 1
    fi

    require_bin orbctl
    require_bin python3
    require_bin zig

    if [[ ! -f "$REMOTE_FIXTURE_DIR/run_remote_smoke.py" ]]; then
        log_fail "missing remote smoke fixture at $REMOTE_FIXTURE_DIR"
        exit 1
    fi

    mkdir -p "$OUTPUT_DIR" "$LOG_DIR" "$STATE_DIR" "$ARTIFACT_DIR" "$BUILD_DIR"

    if [[ -z "$ORB_IP" ]]; then
        ORB_IP="$(orbctl list | awk '/running/ {print $NF; exit}')"
    fi
    if [[ -z "$ORB_IP" ]]; then
        log_fail "could not determine a running Orb Linux machine IP"
        exit 1
    fi

    local mac_host_ip
    mac_host_ip="$(pick_source_ip_for_target "$ORB_IP")"
    if [[ -z "$mac_host_ip" ]]; then
        log_fail "could not determine the macOS host IP reachable from Orb"
        exit 1
    fi

    log_info "Building macOS SpiderNode binary into isolated prefix ..."
    (
        cd "$ROOT_DIR/SpiderNode"
        zig build \
            --prefix "$SPIDERNODE_PREFIX" \
            --cache-dir "$SPIDERNODE_LOCAL_CACHE" \
            --global-cache-dir "$SPIDERNODE_GLOBAL_CACHE"
    )

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

    log_info "Starting macOS remote export node on $mac_host_ip:$REMOTE_NODE_PORT ..."
    "$LOCAL_NODE_BIN" \
        --bind "$mac_host_ip" \
        --port "$REMOTE_NODE_PORT" \
        --export "$REMOTE_EXPORT_NAME=$REMOTE_FIXTURE_DIR:rw" \
        --control-url "$control_url" \
        --control-auth-token "$control_auth_token" \
        --pair-mode invite \
        --invite-token "$remote_invite_token" \
        --node-name "$REMOTE_NODE_NAME" \
        --state-file "$STATE_DIR/macos-remote-node-state.json" \
        >"$LOCAL_REMOTE_NODE_LOG" 2>&1 &
    LOCAL_REMOTE_NODE_PID="$!"

    log_info "Finishing cross-platform workspace scenario in Orb ..."
    orb_run finish_scenario

    local result_file="$ARTIFACT_DIR/workspace_result.json"
    local remote_smoke_file="$ARTIFACT_DIR/remote_smoke_result.json"
    if [[ ! -f "$result_file" || ! -f "$remote_smoke_file" ]]; then
        log_fail "scenario completed without the expected result artifacts"
        exit 1
    fi

    log_pass "Cross-platform node workspace smoke completed"
    log_info "Artifacts:"
    echo "  $handoff_file"
    echo "  $result_file"
    echo "  $remote_smoke_file"
}

main "$@"
