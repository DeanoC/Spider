#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/e2e/output-cleanup.sh"
LINUX_HELPER="$ROOT_DIR/e2e/run_linux_spiderweb_host.sh"
REMOTE_TEMPLATE_DIR="$ROOT_DIR/e2e/fixtures/agent-relay"
LINUX_WORKER_PROMPT="$ROOT_DIR/e2e/prompts/agent-relay-linux-worker.txt"
MACOS_REVIEWER_PROMPT="$ROOT_DIR/e2e/prompts/agent-relay-macos-reviewer.txt"
VALIDATOR="$ROOT_DIR/e2e/validate_agent_relay.py"

OUTPUT_DIR_WAS_EXPLICIT=0
if [[ -n "${OUTPUT_DIR+x}" ]]; then
    OUTPUT_DIR_WAS_EXPLICIT=1
else
    OUTPUT_DIR="$ROOT_DIR/e2e/out/cross-platform-agent-relay-$(date +%Y%m%d-%H%M%S)-$$"
fi
case "$OUTPUT_DIR" in
    "$ROOT_DIR"/*) RUN_DIR_REL="${OUTPUT_DIR#"$ROOT_DIR/"}" ;;
    *)
        echo "OUTPUT_DIR must live under $ROOT_DIR for Orb path sharing" >&2
        exit 1
        ;;
esac

RUN_NAME="$(basename "$OUTPUT_DIR")"
LOG_DIR="$OUTPUT_DIR/logs"
STATE_DIR="$OUTPUT_DIR/state"
ARTIFACT_DIR="$OUTPUT_DIR/artifacts"
BUILD_DIR="$OUTPUT_DIR/build/macos"
REMOTE_EXPORT_COPY="$STATE_DIR/macos-remote-export"

SPIDERNODE_PREFIX="$BUILD_DIR/spidernode-prefix"
SPIDERNODE_LOCAL_CACHE="$BUILD_DIR/spidernode-local-cache"
SPIDERNODE_GLOBAL_CACHE="$BUILD_DIR/spidernode-global-cache"
LOCAL_NODE_BIN="$SPIDERNODE_PREFIX/bin/spiderweb-fs-node"

ORB_MACHINE="${ORB_MACHINE:-}"
ORB_IP="${ORB_IP:-}"
SPIDERWEB_PORT="${SPIDERWEB_PORT:-28796}"
LOCAL_WORKSPACE_NODE_PORT="${LOCAL_WORKSPACE_NODE_PORT:-28951}"
REMOTE_NODE_PORT="${REMOTE_NODE_PORT:-28952}"
REMOTE_NODE_NAME="${REMOTE_NODE_NAME:-cross-macos-review-node}"
REMOTE_EXPORT_NAME="${REMOTE_EXPORT_NAME:-remote-smoke}"
REMOTE_BIND_PATH="/remote"
KEEP_OUTPUT="${KEEP_OUTPUT:-}"

LINUX_WORKER_JSONL="$LOG_DIR/linux-worker-codex.jsonl"
LINUX_WORKER_STDERR="$LOG_DIR/linux-worker-codex.stderr.log"
LINUX_WORKER_LAST="$ARTIFACT_DIR/linux_worker_last_message.txt"
MACOS_REVIEWER_JSONL="$LOG_DIR/macos-reviewer-codex.jsonl"
MACOS_REVIEWER_STDERR="$LOG_DIR/macos-reviewer-codex.stderr.log"
MACOS_REVIEWER_LAST="$ARTIFACT_DIR/macos_reviewer_last_message.txt"
RELAY_VALIDATION_JSON="$ARTIFACT_DIR/agent_relay_validation.json"

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
        REMOTE_BIND_PATH="/remote" \
        bash "$LINUX_HELPER" "$@"
}

orb_run_linux_worker_codex() {
    local prompt_rel="${LINUX_WORKER_PROMPT#"$ROOT_DIR/"}"
    local linux_mount="/tmp/$RUN_NAME/mountpoint"
    local artifact_dir="$ROOT_DIR/$RUN_DIR_REL/artifacts"
    local log_dir="$ROOT_DIR/$RUN_DIR_REL/logs"
    local -a cmd=(orbctl run --path --workdir "$ROOT_DIR")
    if [[ -n "$ORB_MACHINE" ]]; then
        cmd+=(--machine "$ORB_MACHINE")
    fi
    "${cmd[@]}" bash -lc "
set -euo pipefail
mkdir -p $(printf '%q' "$artifact_dir") $(printf '%q' "$log_dir")
cat $(printf '%q' "$ROOT_DIR/$prompt_rel") | \
codex exec \
  --json \
  --skip-git-repo-check \
  --dangerously-bypass-approvals-and-sandbox \
  --ephemeral \
  --color never \
  --add-dir $(printf '%q' "$artifact_dir") \
  -C $(printf '%q' "$linux_mount") \
  -o $(printf '%q' "$LINUX_WORKER_LAST") \
  - \
  >$(printf '%q' "$LINUX_WORKER_JSONL") \
  2>$(printf '%q' "$LINUX_WORKER_STDERR")
"
}

copy_remote_template() {
    python3 - "$REMOTE_TEMPLATE_DIR" "$REMOTE_EXPORT_COPY" <<'PY'
from pathlib import Path
import shutil
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
if dst.exists():
    shutil.rmtree(dst)
shutil.copytree(src, dst)
PY
}

run_macos_reviewer_codex() {
    cat "$MACOS_REVIEWER_PROMPT" | \
        codex exec \
            --json \
            --skip-git-repo-check \
            --dangerously-bypass-approvals-and-sandbox \
            --ephemeral \
            --color never \
            --add-dir "$ARTIFACT_DIR" \
            -C "$REMOTE_EXPORT_COPY" \
            -o "$MACOS_REVIEWER_LAST" \
            - \
            >"$MACOS_REVIEWER_JSONL" \
            2>"$MACOS_REVIEWER_STDERR"
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
        log_fail "the initial agent relay lane currently requires macOS with OrbStack"
        exit 1
    fi

    require_bin orbctl
    require_bin python3
    require_bin zig
    require_bin codex

    mkdir -p "$OUTPUT_DIR" "$LOG_DIR" "$STATE_DIR" "$ARTIFACT_DIR" "$BUILD_DIR"
    copy_remote_template

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
        --export "$REMOTE_EXPORT_NAME=$REMOTE_EXPORT_COPY:rw" \
        --control-url "$control_url" \
        --control-auth-token "$control_auth_token" \
        --pair-mode invite \
        --invite-token "$remote_invite_token" \
        --node-name "$REMOTE_NODE_NAME" \
        --state-file "$STATE_DIR/macos-remote-node-state.json" \
        >"$LOCAL_REMOTE_NODE_LOG" 2>&1 &
    LOCAL_REMOTE_NODE_PID="$!"

    log_info "Preparing mounted workspace in Orb ..."
    orb_run finish_scenario

    log_info "Running Linux worker Codex in the mounted workspace ..."
    orb_run_linux_worker_codex
    if [[ ! -f "$REMOTE_EXPORT_COPY/worker_report.md" || ! -f "$REMOTE_EXPORT_COPY/worker_summary.json" ]]; then
        log_fail "Linux worker did not produce the expected remote outputs"
        exit 1
    fi
    log_pass "Linux worker wrote results through Spiderweb into the remote export"

    log_info "Running macOS reviewer Codex against the remote export ..."
    run_macos_reviewer_codex

    log_info "Validating cross-platform relay outputs ..."
    python3 "$VALIDATOR" \
        --remote-root "$REMOTE_EXPORT_COPY" \
        --output "$RELAY_VALIDATION_JSON"

    log_pass "Cross-platform agent relay smoke completed"
    log_info "Artifacts:"
    echo "  $handoff_file"
    echo "  $ARTIFACT_DIR/workspace_result.json"
    echo "  $ARTIFACT_DIR/remote_smoke_result.json"
    echo "  $RELAY_VALIDATION_JSON"
    echo "  $LINUX_WORKER_LAST"
    echo "  $MACOS_REVIEWER_LAST"
}

main "$@"
