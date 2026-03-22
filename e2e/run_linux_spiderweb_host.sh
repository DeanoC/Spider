#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RUN_DIR_REL="${RUN_DIR_REL:?RUN_DIR_REL is required}"
RUN_DIR="$ROOT_DIR/$RUN_DIR_REL"
RUN_NAME="$(basename "$RUN_DIR")"
LOG_DIR="$RUN_DIR/logs"
STATE_DIR="$RUN_DIR/state"
ARTIFACT_DIR="$RUN_DIR/artifacts"
BUILD_DIR="$RUN_DIR/build/orb"
WORKSPACE_EXPORT_ROOT="$RUN_DIR/workspace-export"

SPIDERWEB_HOST_IP="${SPIDERWEB_HOST_IP:?SPIDERWEB_HOST_IP is required}"
SPIDERWEB_PORT="${SPIDERWEB_PORT:?SPIDERWEB_PORT is required}"
LOCAL_WORKSPACE_NODE_PORT="${LOCAL_WORKSPACE_NODE_PORT:?LOCAL_WORKSPACE_NODE_PORT is required}"
LINUX_TMP_ROOT="/tmp/${RUN_NAME}"
MOUNT_POINT="$LINUX_TMP_ROOT/mountpoint"

SPIDERWEB_BIND_ADDR="${SPIDERWEB_BIND_ADDR:-0.0.0.0}"
LOCAL_NODE_BIND_ADDR="${LOCAL_NODE_BIND_ADDR:-0.0.0.0}"

LOCAL_WORKSPACE_NODE_NAME="${LOCAL_WORKSPACE_NODE_NAME:-cross-linux-workspace-node}"
REMOTE_NODE_NAME="${REMOTE_NODE_NAME:-cross-macos-remote-node}"
REMOTE_EXPORT_NAME="${REMOTE_EXPORT_NAME:-remote-smoke}"
REMOTE_MOUNT_PATH="${REMOTE_MOUNT_PATH:-/imports/remote-smoke}"
REMOTE_BIND_PATH="${REMOTE_BIND_PATH:-/remote}"

SPIDERNODE_PREFIX="$BUILD_DIR/spidernode-prefix"
SPIDERWEB_PREFIX="$BUILD_DIR/spiderweb-prefix"
SPIDERNODE_LOCAL_CACHE="$BUILD_DIR/spidernode-local-cache"
SPIDERNODE_GLOBAL_CACHE="$BUILD_DIR/spidernode-global-cache"
SPIDERWEB_LOCAL_CACHE="$BUILD_DIR/spiderweb-local-cache"
SPIDERWEB_GLOBAL_CACHE="$BUILD_DIR/spiderweb-global-cache"

SPIDERNODE_BIN="$SPIDERNODE_PREFIX/bin/spiderweb-fs-node"
SPIDERWEB_BIN="$SPIDERWEB_PREFIX/bin/spiderweb"
CONTROL_BIN="$SPIDERWEB_PREFIX/bin/spiderweb-control"
FS_MOUNT_BIN="$SPIDERWEB_PREFIX/bin/spiderweb-fs-mount"

SPIDERWEB_RUNTIME_ROOT="$STATE_DIR/spiderweb-root"
SPIDERWEB_LTM_DIR="$STATE_DIR/runtime"
SPIDERWEB_CONFIG_FILE="$STATE_DIR/spiderweb.json"
AUTH_TOKENS_FILE="$SPIDERWEB_LTM_DIR/auth_tokens.json"
HANDOFF_FILE="$ARTIFACT_DIR/control_handoff.json"
RESULT_FILE="$ARTIFACT_DIR/workspace_result.json"

SPIDERWEB_LOG="$LOG_DIR/spiderweb.log"
LOCAL_WORKSPACE_NODE_LOG="$LOG_DIR/linux-workspace-node.log"
MOUNT_LOG="$LOG_DIR/linux-mount.log"
SPIDERWEB_PID_FILE="$STATE_DIR/spiderweb.pid"
LOCAL_WORKSPACE_NODE_PID_FILE="$STATE_DIR/linux-workspace-node.pid"
MOUNT_PID_FILE="$STATE_DIR/mount.pid"

CONTROL_URL_LOCAL="ws://127.0.0.1:$SPIDERWEB_PORT"
CONTROL_URL_REMOTE="ws://$SPIDERWEB_HOST_IP:$SPIDERWEB_PORT"

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

run_with_timeout() {
    local seconds="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" "$@"
    else
        "$@"
    fi
}

json_query() {
    local json="$1"
    local path="$2"
    python3 - "$json" "$path" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
path = sys.argv[2].split(".")
cur = data
for part in path:
    if not part:
        continue
    if isinstance(cur, list):
        cur = cur[int(part)]
    else:
        cur = cur[part]
if isinstance(cur, bool):
    print("true" if cur else "false")
elif cur is None:
    print("")
elif isinstance(cur, (dict, list)):
    print(json.dumps(cur))
else:
    print(cur)
PY
}

load_access_token() {
    if [[ ! -f "$AUTH_TOKENS_FILE" ]]; then
        return 1
    fi
    python3 - "$AUTH_TOKENS_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
token = str(data.get("access_token") or "").strip()
if token:
    print(token)
PY
}

control_call() {
    local auth_token="$1"
    local op="$2"
    local payload="${3-}"
    local output
    if [[ -n "$payload" ]]; then
        output="$(run_with_timeout 10 "$CONTROL_BIN" --url "$CONTROL_URL_LOCAL" --auth-token "$auth_token" "$op" "$payload" 2>&1)" || {
            echo "$output" >&2
            return 1
        }
    else
        output="$(run_with_timeout 10 "$CONTROL_BIN" --url "$CONTROL_URL_LOCAL" --auth-token "$auth_token" "$op" 2>&1)" || {
            echo "$output" >&2
            return 1
        }
    fi
    printf '%s\n' "$output"
}

wait_for_control_ready() {
    local auth_token=""
    local reply=""
    for _ in $(seq 1 180); do
        auth_token="$(load_access_token || true)"
        if [[ -z "$auth_token" ]]; then
            sleep 0.2
            continue
        fi
        reply="$(control_call "$auth_token" node_list 2>/dev/null || true)"
        if [[ -n "$reply" ]]; then
            printf '%s' "$auth_token"
            return 0
        fi
        sleep 0.2
    done
    return 1
}

wait_for_node_join() {
    local auth_token="$1"
    local node_name="$2"
    local result_var="$3"
    local reply=""
    local node_id=""
    for _ in $(seq 1 180); do
        reply="$(control_call "$auth_token" node_list 2>/dev/null || true)"
        if [[ -z "$reply" ]]; then
            sleep 0.2
            continue
        fi
        node_id="$(python3 - "$reply" "$node_name" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1]).get("payload") or {}
target = sys.argv[2]
for node in payload.get("nodes") or []:
    if node.get("node_name") == target:
        print(node.get("node_id") or "")
        break
PY
)"
        if [[ -n "$node_id" ]]; then
            printf -v "$result_var" '%s' "$node_id"
            return 0
        fi
        sleep 0.2
    done
    return 1
}

wait_for_workspace_file() {
    local path="$1"
    for _ in $(seq 1 180); do
        if [[ -f "$path" ]]; then
            return 0
        fi
        sleep 0.2
    done
    return 1
}

kill_pidfile() {
    local pidfile="$1"
    if [[ ! -f "$pidfile" ]]; then
        return 0
    fi
    local pid
    pid="$(cat "$pidfile" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
        kill "$pid" >/dev/null 2>&1 || true
        wait "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$pidfile"
}

ensure_layout() {
    mkdir -p "$RUN_DIR" "$LOG_DIR" "$STATE_DIR" "$ARTIFACT_DIR" "$WORKSPACE_EXPORT_ROOT" "$LINUX_TMP_ROOT" "$MOUNT_POINT"
}

build_binaries() {
    require_bin zig
    ensure_layout
    mkdir -p "$BUILD_DIR"

    log_info "Building SpiderNode Linux binaries into isolated prefix ..."
    (
        cd "$ROOT_DIR/SpiderNode"
        zig build \
            --prefix "$SPIDERNODE_PREFIX" \
            --cache-dir "$SPIDERNODE_LOCAL_CACHE" \
            --global-cache-dir "$SPIDERNODE_GLOBAL_CACHE"
    )

    log_info "Building Spiderweb Linux binaries into isolated prefix ..."
    (
        cd "$ROOT_DIR/Spiderweb"
        zig build \
            --prefix "$SPIDERWEB_PREFIX" \
            --cache-dir "$SPIDERWEB_LOCAL_CACHE" \
            --global-cache-dir "$SPIDERWEB_GLOBAL_CACHE"
    )
}

start_host_stack() {
    ensure_layout
    require_bin python3

    cat > "$SPIDERWEB_CONFIG_FILE" <<EOF
{
  "provider": {
    "name": "openai",
    "model": "gpt-4o-mini"
  },
  "runtime": {
    "default_agent_id": "default",
    "state_directory": "$SPIDERWEB_LTM_DIR",
    "state_db_filename": "runtime-state.db",
    "spider_web_root": "$SPIDERWEB_RUNTIME_ROOT"
  }
}
EOF

    log_info "Starting Linux Spiderweb host on $CONTROL_URL_REMOTE ..."
    nohup env SPIDERWEB_CONFIG="$SPIDERWEB_CONFIG_FILE" \
        "$SPIDERWEB_BIN" \
        --bind "$SPIDERWEB_BIND_ADDR" \
        --port "$SPIDERWEB_PORT" \
        >"$SPIDERWEB_LOG" 2>&1 </dev/null &
    echo "$!" > "$SPIDERWEB_PID_FILE"

    local auth_token
    auth_token="$(wait_for_control_ready)" || {
        log_fail "Linux Spiderweb host did not become ready"
        tail -n 200 "$SPIDERWEB_LOG" || true
        exit 1
    }
    log_pass "Linux Spiderweb host is ready"

    local local_invite_resp local_invite_token
    local_invite_resp="$(control_call "$auth_token" node_invite_create)"
    local_invite_token="$(json_query "$local_invite_resp" "payload.invite_token")"

    log_info "Starting Linux workspace node ..."
    nohup "$SPIDERNODE_BIN" \
        --bind "$LOCAL_NODE_BIND_ADDR" \
        --port "$LOCAL_WORKSPACE_NODE_PORT" \
        --export "workspace=$WORKSPACE_EXPORT_ROOT:rw" \
        --control-url "$CONTROL_URL_LOCAL" \
        --control-auth-token "$auth_token" \
        --pair-mode invite \
        --invite-token "$local_invite_token" \
        --node-name "$LOCAL_WORKSPACE_NODE_NAME" \
        --state-file "$STATE_DIR/linux-workspace-node-state.json" \
        >"$LOCAL_WORKSPACE_NODE_LOG" 2>&1 </dev/null &
    echo "$!" > "$LOCAL_WORKSPACE_NODE_PID_FILE"

    local local_workspace_node_id=""
    if ! wait_for_node_join "$auth_token" "$LOCAL_WORKSPACE_NODE_NAME" local_workspace_node_id; then
        log_fail "Linux workspace node did not join Spiderweb"
        tail -n 200 "$LOCAL_WORKSPACE_NODE_LOG" || true
        exit 1
    fi
    log_pass "Linux workspace node joined as $local_workspace_node_id"

    local remote_invite_resp remote_invite_token
    remote_invite_resp="$(control_call "$auth_token" node_invite_create)"
    remote_invite_token="$(json_query "$remote_invite_resp" "payload.invite_token")"

    python3 - "$HANDOFF_FILE" "$CONTROL_URL_REMOTE" "$auth_token" "$remote_invite_token" "$REMOTE_NODE_NAME" "$REMOTE_EXPORT_NAME" "$REMOTE_MOUNT_PATH" "$REMOTE_BIND_PATH" "$local_workspace_node_id" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
payload = {
    "control_url": sys.argv[2],
    "control_auth_token": sys.argv[3],
    "remote_invite_token": sys.argv[4],
    "remote_node_name": sys.argv[5],
    "remote_export_name": sys.argv[6],
    "remote_mount_path": sys.argv[7],
    "remote_bind_path": sys.argv[8],
    "local_workspace_node_id": sys.argv[9],
}
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

finish_scenario() {
    require_bin python3
    local auth_token
    auth_token="$(load_access_token)" || {
        log_fail "missing Spiderweb access token"
        exit 1
    }

    local local_workspace_node_id=""
    local remote_node_id=""
    if [[ -f "$HANDOFF_FILE" ]]; then
        local_workspace_node_id="$(python3 - "$HANDOFF_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
print(data.get("local_workspace_node_id") or "")
PY
)"
    fi
    if [[ -z "$local_workspace_node_id" ]]; then
        log_fail "missing local workspace node id handoff"
        exit 1
    fi

    if ! wait_for_node_join "$auth_token" "$REMOTE_NODE_NAME" remote_node_id; then
        log_fail "remote macOS node did not join Spiderweb"
        exit 1
    fi
    log_pass "Remote macOS node joined as $remote_node_id"

    local workspace_up_payload workspace_up_resp workspace_id workspace_token
    workspace_up_payload="$(python3 - "$LOCAL_WORKSPACE_NODE_NAME" "$local_workspace_node_id" "$remote_node_id" "$REMOTE_EXPORT_NAME" "$REMOTE_MOUNT_PATH" <<'PY'
import json
import sys

payload = {
    "name": "Cross Platform Node Workspace",
    "vision": "Linux Spiderweb host with remote macOS node export",
    "template_id": "dev",
    "activate": True,
    "desired_mounts": [
        {
            "mount_path": "/nodes/local/fs",
            "node_id": sys.argv[2],
            "export_name": "workspace",
        },
        {
            "mount_path": sys.argv[5],
            "node_id": sys.argv[3],
            "export_name": sys.argv[4],
        },
    ],
}
print(json.dumps(payload, separators=(",", ":")))
PY
)"
    workspace_up_resp="$(control_call "$auth_token" workspace_up "$workspace_up_payload")"
    printf '%s\n' "$workspace_up_resp" > "$ARTIFACT_DIR/workspace_up.json"
    workspace_id="$(json_query "$workspace_up_resp" "payload.workspace_id")"
    workspace_token="$(python3 - "$workspace_up_resp" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1]).get("payload") or {}
print(payload.get("workspace_token") or "")
PY
)"

    local bind_payload bind_resp
    bind_payload="$(python3 - "$workspace_id" "$workspace_token" "$REMOTE_BIND_PATH" "$REMOTE_MOUNT_PATH" <<'PY'
import json
import sys

payload = {
    "workspace_id": sys.argv[1],
    "bind_path": sys.argv[3],
    "target_path": sys.argv[4],
}
if sys.argv[2]:
    payload["workspace_token"] = sys.argv[2]
print(json.dumps(payload, separators=(",", ":")))
PY
)"
    bind_resp="$(control_call "$auth_token" workspace_bind_set "$bind_payload")"
    printf '%s\n' "$bind_resp" > "$ARTIFACT_DIR/workspace_bind_set.json"

    local status_payload
    status_payload="$(control_call "$auth_token" workspace_status "$(python3 - "$workspace_id" <<'PY'
import json
import sys
print(json.dumps({"workspace_id": sys.argv[1]}, separators=(",", ":")))
PY
)")"
    printf '%s\n' "$status_payload" > "$ARTIFACT_DIR/workspace_status.control.json"

    log_info "Mounting workspace namespace on Linux host ..."
    nohup "$FS_MOUNT_BIN" \
        --namespace-url "$CONTROL_URL_LOCAL" \
        --workspace-id "$workspace_id" \
        --auth-token "$auth_token" \
        --agent-id cross-platform-e2e \
        --session-key remote-node-smoke \
        mount "$MOUNT_POINT" >"$MOUNT_LOG" 2>&1 </dev/null &
    echo "$!" > "$MOUNT_PID_FILE"

    if ! wait_for_workspace_file "$MOUNT_POINT/remote/run_remote_smoke.py"; then
        log_fail "workspace mount did not expose the bound remote folder"
        tail -n 200 "$MOUNT_LOG" || true
        exit 1
    fi
    log_pass "Workspace mount exposed the remote bind at /remote"

    python3 "$MOUNT_POINT/remote/run_remote_smoke.py" \
        --workspace-root "$MOUNT_POINT" \
        --remote-root "$MOUNT_POINT/remote" \
        --output "$ARTIFACT_DIR/remote_smoke_result.json"

    python3 - "$RESULT_FILE" "$workspace_id" "$workspace_token" "$remote_node_id" "$REMOTE_BIND_PATH" "$REMOTE_MOUNT_PATH" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = {
    "workspace_id": sys.argv[2],
    "workspace_token_present": bool(sys.argv[3]),
    "remote_node_id": sys.argv[4],
    "remote_bind_path": sys.argv[5],
    "remote_mount_path": sys.argv[6],
}
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

cleanup_host_stack() {
    if command -v mountpoint >/dev/null 2>&1 && mountpoint -q "$MOUNT_POINT"; then
        fusermount3 -u "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi
    kill_pidfile "$MOUNT_PID_FILE"
    kill_pidfile "$LOCAL_WORKSPACE_NODE_PID_FILE"
    kill_pidfile "$SPIDERWEB_PID_FILE"
    rm -rf "$LINUX_TMP_ROOT"
}

usage() {
    cat <<EOF
Usage: $0 <build|start_host_stack|finish_scenario|cleanup>
EOF
}

main() {
    require_bin python3

    local cmd="${1-}"
    case "$cmd" in
        build)
            build_binaries
            ;;
        start_host_stack)
            start_host_stack
            ;;
        finish_scenario)
            finish_scenario
            ;;
        cleanup)
            cleanup_host_stack
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
