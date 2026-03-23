#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${SPIDER_E2E_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONTROL_URL="${CONTROL_URL:-ws://127.0.0.1:18790/}"
CONTROL_BIN="${CONTROL_BIN:-/Applications/Spiderweb.app/Contents/Resources/spiderweb-control}"
AUTH_TOKEN="${SPIDERWEB_AUTH_TOKEN:-${AUTH_TOKEN:-}}"

WORKSPACE_ID=""
REMOTE_NODE_ID="${REMOTE_NODE_ID:-}"
REMOTE_NODE_NAME="${REMOTE_NODE_NAME:-ws1-orb-remote-node}"
REMOTE_EXPORT_NAME="${REMOTE_EXPORT_NAME:-remote-smoke}"
REMOTE_EXPORT_ROOT="${REMOTE_EXPORT_ROOT:-$ROOT_DIR/e2e/fixtures/remote-smoke}"
RELAY_TEMPLATE_DIR="${RELAY_TEMPLATE_DIR:-$ROOT_DIR/e2e/fixtures/agent-relay}"
REMOTE_MOUNT_PATH="${REMOTE_MOUNT_PATH:-/imports/remote-smoke}"
REMOTE_BIND_PATH="${REMOTE_BIND_PATH:-/remote}"
MOUNT_POINT="${MOUNT_POINT:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1" >&2; }

usage() {
    cat <<EOF
Usage:
  $(basename "$0") --workspace-id <id> [options]

Options:
  --workspace-id <id>        Existing mounted workspace to prepare (required)
  --mount-point <path>       Mounted workspace path to verify after setup
  --control-url <ws-url>     Spiderweb control URL (default: $CONTROL_URL)
  --auth-token <token>       Spiderweb access token (default: SPIDERWEB_AUTH_TOKEN)
  --control-bin <path>       spiderweb-control binary (default: $CONTROL_BIN)
  --remote-node-id <id>      Remote node id to use directly
  --remote-node-name <name>  Remote node name lookup (default: $REMOTE_NODE_NAME)
  --remote-export-name <n>   Export name on the remote node (default: $REMOTE_EXPORT_NAME)
  --remote-export-root <p>   Local exported fixture dir (default: $REMOTE_EXPORT_ROOT)
  --relay-template-dir <p>   Relay template dir to sync from (default: $RELAY_TEMPLATE_DIR)
  --remote-mount-path <p>    Workspace mount path (default: $REMOTE_MOUNT_PATH)
  --remote-bind-path <p>     Workspace bind path (default: $REMOTE_BIND_PATH)
EOF
}

require_bin() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_fail "missing required command: $1"
        exit 1
    fi
}

control_call() {
    local op="$1"
    local payload="${2-}"
    if [[ -n "$payload" ]]; then
        "$CONTROL_BIN" --url "$CONTROL_URL" --auth-token "$AUTH_TOKEN" "$op" "$payload"
    else
        "$CONTROL_BIN" --url "$CONTROL_URL" --auth-token "$AUTH_TOKEN" "$op"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace-id)
            WORKSPACE_ID="${2:?missing value for --workspace-id}"
            shift 2
            ;;
        --mount-point)
            MOUNT_POINT="${2:?missing value for --mount-point}"
            shift 2
            ;;
        --control-url)
            CONTROL_URL="${2:?missing value for --control-url}"
            shift 2
            ;;
        --auth-token)
            AUTH_TOKEN="${2:?missing value for --auth-token}"
            shift 2
            ;;
        --control-bin)
            CONTROL_BIN="${2:?missing value for --control-bin}"
            shift 2
            ;;
        --remote-node-id)
            REMOTE_NODE_ID="${2:?missing value for --remote-node-id}"
            shift 2
            ;;
        --remote-node-name)
            REMOTE_NODE_NAME="${2:?missing value for --remote-node-name}"
            shift 2
            ;;
        --remote-export-name)
            REMOTE_EXPORT_NAME="${2:?missing value for --remote-export-name}"
            shift 2
            ;;
        --remote-export-root)
            REMOTE_EXPORT_ROOT="${2:?missing value for --remote-export-root}"
            shift 2
            ;;
        --relay-template-dir)
            RELAY_TEMPLATE_DIR="${2:?missing value for --relay-template-dir}"
            shift 2
            ;;
        --remote-mount-path)
            REMOTE_MOUNT_PATH="${2:?missing value for --remote-mount-path}"
            shift 2
            ;;
        --remote-bind-path)
            REMOTE_BIND_PATH="${2:?missing value for --remote-bind-path}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_fail "unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$WORKSPACE_ID" ]]; then
    log_fail "--workspace-id is required"
    usage
    exit 1
fi

if [[ -z "$AUTH_TOKEN" ]]; then
    log_fail "missing Spiderweb access token; set SPIDERWEB_AUTH_TOKEN or pass --auth-token"
    exit 1
fi

require_bin python3

if [[ ! -x "$CONTROL_BIN" ]]; then
    log_fail "control binary not found or not executable: $CONTROL_BIN"
    exit 1
fi
if [[ ! -d "$RELAY_TEMPLATE_DIR" ]]; then
    log_fail "relay template dir not found: $RELAY_TEMPLATE_DIR"
    exit 1
fi
if [[ ! -d "$REMOTE_EXPORT_ROOT" ]]; then
    log_fail "remote export root not found: $REMOTE_EXPORT_ROOT"
    exit 1
fi

log_info "Syncing relay fixture into the exported remote fixture ..."
python3 - "$RELAY_TEMPLATE_DIR" "$REMOTE_EXPORT_ROOT" <<'PY'
from pathlib import Path
import shutil
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

for stale in [
    "worker_report.md",
    "worker_summary.json",
    "review.md",
    "review_summary.json",
    "_probe.txt",
]:
    path = dst / stale
    if path.exists():
        path.unlink()

for stale in ["nested/._check.txt"]:
    path = dst.joinpath(*stale.split("/"))
    if path.exists():
        path.unlink()

for item in src.rglob("*"):
    relative = item.relative_to(src)
    target = dst / relative
    if item.is_dir():
        target.mkdir(parents=True, exist_ok=True)
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item, target)

(dst / "worker_report.md").write_text("PENDING relay worker output\n", encoding="utf-8")
(dst / "worker_summary.json").write_text("{\"status\":\"pending\"}\n", encoding="utf-8")
PY

log_info "Checking workspace and node state ..."
workspace_status_json="$(control_call workspace_status "$(python3 - "$WORKSPACE_ID" <<'PY'
import json
import sys
print(json.dumps({"workspace_id": sys.argv[1]}, separators=(",", ":")))
PY
)")"
node_list_json="$(control_call node_list '{}')"

if [[ -z "$REMOTE_NODE_ID" ]]; then
    REMOTE_NODE_ID="$(python3 - "$node_list_json" "$REMOTE_NODE_NAME" <<'PY'
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
fi

if [[ -z "$REMOTE_NODE_ID" ]]; then
    log_fail "could not resolve remote node; pass --remote-node-id or ensure node '$REMOTE_NODE_NAME' is online"
    exit 1
fi

log_info "Applying remote mount and bind to workspace $WORKSPACE_ID ..."
control_call workspace_mount_set "$(python3 - "$WORKSPACE_ID" "$REMOTE_NODE_ID" "$REMOTE_EXPORT_NAME" "$REMOTE_MOUNT_PATH" <<'PY'
import json
import sys
print(json.dumps({
    "workspace_id": sys.argv[1],
    "node_id": sys.argv[2],
    "export_name": sys.argv[3],
    "mount_path": sys.argv[4],
}, separators=(",", ":")))
PY
)" >/dev/null

control_call workspace_bind_set "$(python3 - "$WORKSPACE_ID" "$REMOTE_BIND_PATH" "$REMOTE_MOUNT_PATH" <<'PY'
import json
import sys
print(json.dumps({
    "workspace_id": sys.argv[1],
    "bind_path": sys.argv[2],
    "target_path": sys.argv[3],
}, separators=(",", ":")))
PY
)" >/dev/null

status_after_json="$(control_call workspace_status "$(python3 - "$WORKSPACE_ID" <<'PY'
import json
import sys
print(json.dumps({"workspace_id": sys.argv[1]}, separators=(",", ":")))
PY
)")"
binds_after_json="$(control_call workspace_bind_list "$(python3 - "$WORKSPACE_ID" <<'PY'
import json
import sys
print(json.dumps({"workspace_id": sys.argv[1]}, separators=(",", ":")))
PY
)")"

python3 - "$status_after_json" "$binds_after_json" "$REMOTE_BIND_PATH" "$REMOTE_MOUNT_PATH" "$REMOTE_NODE_ID" "$REMOTE_EXPORT_NAME" <<'PY'
import json
import sys

reply = json.loads(sys.argv[1])
bind_reply = json.loads(sys.argv[2])
payload = reply.get("payload") or {}
bind_payload = bind_reply.get("payload") or {}
bind_path = sys.argv[3]
mount_path = sys.argv[4]
node_id = sys.argv[5]
export_name = sys.argv[6]

mounts = payload.get("mounts") or []
binds = bind_payload.get("binds") or []

mount_ok = any(
    item.get("mount_path") == mount_path and
    item.get("node_id") == node_id and
    item.get("export_name") == export_name
    for item in mounts
)
bind_ok = any(
    item.get("bind_path") == bind_path and
    item.get("target_path") == mount_path
    for item in binds
)

if not mount_ok:
    raise SystemExit("workspace mount was not applied as expected")
if not bind_ok:
    raise SystemExit("workspace bind was not applied as expected")

print(json.dumps({
    "workspace_id": payload.get("workspace_id"),
    "mounts_total": (payload.get("availability") or {}).get("mounts_total"),
    "online": (payload.get("availability") or {}).get("online"),
    "drift_count": (payload.get("drift") or {}).get("count"),
}, indent=2))
PY

if [[ -n "$MOUNT_POINT" ]]; then
    log_info "Verifying mounted workspace path $MOUNT_POINT ..."
    python3 - "$MOUNT_POINT" "$REMOTE_BIND_PATH" <<'PY'
from pathlib import Path
import sys
import time

mount_root = Path(sys.argv[1])
bind_rel = sys.argv[2].lstrip("/")
remote_root = mount_root / bind_rel

required = [
    remote_root / "manifest.json",
    remote_root / "task_brief.md",
    remote_root / "reference_notes.txt",
    remote_root / "hello.txt",
    remote_root / "nested" / "check.txt",
]

deadline = time.time() + 10.0
while time.time() < deadline:
    if all(path.exists() for path in required):
        break
    time.sleep(0.2)

missing = [str(path) for path in required if not path.exists()]
if missing:
    raise SystemExit("mounted workspace is missing expected relay files: " + ", ".join(missing))

probe = remote_root / "_setup_probe.txt"
(remote_root / "worker_report.md").write_text("PENDING relay worker output\n", encoding="utf-8")
(remote_root / "worker_summary.json").write_text("{\"status\":\"pending\"}\n", encoding="utf-8")
print(remote_root)
PY
fi

log_pass "Workspace $WORKSPACE_ID is configured for the agent relay demo"
echo "workspace_id=$WORKSPACE_ID"
echo "remote_node_id=$REMOTE_NODE_ID"
echo "remote_mount_path=$REMOTE_MOUNT_PATH"
echo "remote_bind_path=$REMOTE_BIND_PATH"
if [[ -n "$MOUNT_POINT" ]]; then
    echo "mount_point=$MOUNT_POINT"
fi
