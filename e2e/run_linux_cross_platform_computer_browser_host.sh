#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${SPIDER_E2E_ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

RUN_DIR_REL="${RUN_DIR_REL:?RUN_DIR_REL is required}"
RUN_DIR="$ROOT_DIR/$RUN_DIR_REL"
RUN_NAME="$(basename "$RUN_DIR")"
LOG_DIR="$RUN_DIR/logs"
STATE_DIR="$RUN_DIR/state"
ARTIFACT_DIR="$RUN_DIR/artifacts"

SPIDERWEB_HOST_IP="${SPIDERWEB_HOST_IP:?SPIDERWEB_HOST_IP is required}"
SPIDERWEB_PORT="${SPIDERWEB_PORT:?SPIDERWEB_PORT is required}"
LOCAL_WORKSPACE_NODE_PORT="${LOCAL_WORKSPACE_NODE_PORT:-}"

LINUX_TMP_ROOT="/tmp/${RUN_NAME}"
BUILD_DIR="$LINUX_TMP_ROOT/build/orb"
WORKSPACE_EXPORT_ROOT="$LINUX_TMP_ROOT/workspace-export"
MOUNT_POINT="$LINUX_TMP_ROOT/mountpoint"

SPIDERWEB_BIND_ADDR="${SPIDERWEB_BIND_ADDR:-0.0.0.0}"
LOCAL_NODE_BIND_ADDR="${LOCAL_NODE_BIND_ADDR:-0.0.0.0}"

LOCAL_WORKSPACE_NODE_NAME="${LOCAL_WORKSPACE_NODE_NAME:-cross-linux-computer-browser-node}"
REMOTE_NODE_NAME="${REMOTE_NODE_NAME:-cross-macos-computer-browser-node}"

LINUX_TARGET_ID="${LINUX_TARGET_ID:-linux}"
MACOS_TARGET_ID="${MACOS_TARGET_ID:-macos}"

LINUX_BROWSER_PORT="${LINUX_BROWSER_PORT:-}"
LINUX_FIXTURE_APP_NAME="${LINUX_FIXTURE_APP_NAME:-SpiderLinuxComputerFixture}"
LINUX_WINDOW_TITLE="${LINUX_WINDOW_TITLE:-Spider Linux Computer Fixture}"
BUTTON_TITLE="${BUTTON_TITLE:-Press Fixture Button}"

LINUX_COMPUTER_TEXT="${LINUX_COMPUTER_TEXT:-Hello from Linux target}"
MACOS_COMPUTER_TEXT="${MACOS_COMPUTER_TEXT:-Hello from macOS target}"
LINUX_BROWSER_TEXT="${LINUX_BROWSER_TEXT:-linux browser demo}"
MACOS_BROWSER_TEXT="${MACOS_BROWSER_TEXT:-mac browser demo}"

MACOS_BROWSER_URL="${MACOS_BROWSER_URL:-}"
MACOS_APP_NAME="${MACOS_APP_NAME:-SpiderCrossPlatformComputerFixture}"
MACOS_WINDOW_TITLE="${MACOS_WINDOW_TITLE:-}"
MACOS_FIXTURE_STATE_PATH="${MACOS_FIXTURE_STATE_PATH:-}"

LINUX_FIXTURE_SCRIPT="$ROOT_DIR/e2e/fixtures/linux-computer-browser/linux_computer_fixture.py"
BROWSER_FIXTURE_DIR="$ROOT_DIR/e2e/fixtures/macos-computer-browser/browser_fixture"
PROMPT_TEMPLATE="$ROOT_DIR/e2e/prompts/cross_platform_computer_browser_agent.txt"
HELPER_TEMPLATE="$ROOT_DIR/e2e/cross_platform_demo_runner.py.tmpl"
VALIDATOR="$ROOT_DIR/e2e/validate_cross_platform_computer_browser.py"
WRITE_CAPABILITY_MANIFESTS="$ROOT_DIR/e2e/write_capability_manifests.py"

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
SPIDERWEB_STATE_DIR="$STATE_DIR/runtime"
SPIDERWEB_CONFIG_FILE="$STATE_DIR/spiderweb.json"
AUTH_TOKENS_FILE="$SPIDERWEB_STATE_DIR/auth_tokens.json"
HANDOFF_FILE="$ARTIFACT_DIR/control_handoff.json"
RESULT_FILE="$ARTIFACT_DIR/cross_platform_result.json"

LINUX_BROWSER_URL=""
LINUX_FIXTURE_STATE="$ARTIFACT_DIR/linux-computer-fixture-state.json"
LINUX_PROMPT_FILE="$ARTIFACT_DIR/cross-platform-computer-browser-prompt.txt"
LINUX_HELPER_FILE="$ARTIFACT_DIR/run_cross_platform_demo.py"
LINUX_CAPABILITY_MANIFEST_DIR="$STATE_DIR/linux-node-services.d"
LINUX_BROWSER_STATE_PATH="$STATE_DIR/linux-browser-driver/state.json"
LINUX_BROWSER_PROFILE_DIR="$STATE_DIR/linux-browser-driver/profile"
LINUX_SHARED_DATA_DIR="$STATE_DIR/shared-data"
LINUX_CODEX_JSONL="$LOG_DIR/cross-platform-codex.jsonl"
LINUX_CODEX_STDERR="$LOG_DIR/cross-platform-codex.stderr.log"
LINUX_CODEX_LAST="$ARTIFACT_DIR/cross-platform-codex-last-message.txt"
LINUX_SUMMARY_PATH="$MOUNT_POINT/cross_platform_demo_summary.json"
VALIDATION_JSON="$ARTIFACT_DIR/cross_platform_demo_validation.json"

SPIDERWEB_LOG="$LOG_DIR/spiderweb.log"
LOCAL_WORKSPACE_NODE_LOG="$LOG_DIR/linux-workspace-node.log"
MOUNT_LOG="$LOG_DIR/linux-mount.log"
LINUX_DESKTOP_LOG="$LOG_DIR/linux-desktop-session.log"

SPIDERWEB_PID_FILE="$STATE_DIR/spiderweb.pid"
LOCAL_WORKSPACE_NODE_PID_FILE="$STATE_DIR/linux-workspace-node.pid"
MOUNT_PID_FILE="$STATE_DIR/mount.pid"

NPM_GLOBAL_PREFIX="$STATE_DIR/npm-global"
PLAYWRIGHT_BROWSERS_PATH="$STATE_DIR/ms-playwright"
LINUX_NODE_HOME="$STATE_DIR/linux-node-home"
LINUX_DISPLAY="${LINUX_DISPLAY:-}"

CONTROL_URL_LOCAL="ws://127.0.0.1:${SPIDERWEB_PORT}"
CONTROL_URL_REMOTE="ws://${SPIDERWEB_HOST_IP}:${SPIDERWEB_PORT}"

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
cur = data
for part in sys.argv[2].split("."):
    if not part:
        continue
    if isinstance(cur, list):
        cur = cur[int(part)]
    else:
        cur = cur.get(part)
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
        output="$(run_with_timeout 15 "$CONTROL_BIN" --url "$CONTROL_URL_LOCAL" --auth-token "$auth_token" "$op" "$payload" 2>&1)" || {
            echo "$output" >&2
            return 1
        }
    else
        output="$(run_with_timeout 15 "$CONTROL_BIN" --url "$CONTROL_URL_LOCAL" --auth-token "$auth_token" "$op" 2>&1)" || {
            echo "$output" >&2
            return 1
        }
    fi
    printf '%s\n' "$output"
}

wait_for_control_ready() {
    local auth_token=""
    local reply=""
    for _ in $(seq 1 240); do
        auth_token="$(load_access_token || true)"
        if [[ -z "$auth_token" ]]; then
            sleep 0.25
            continue
        fi
        reply="$(control_call "$auth_token" node_list 2>/dev/null || true)"
        if [[ -n "$reply" ]]; then
            printf '%s' "$auth_token"
            return 0
        fi
        sleep 0.25
    done
    return 1
}

wait_for_node_join() {
    local auth_token="$1"
    local node_name="$2"
    local result_var="$3"
    local reply=""
    local node_id=""
    for _ in $(seq 1 240); do
        reply="$(control_call "$auth_token" node_list 2>/dev/null || true)"
        if [[ -z "$reply" ]]; then
            sleep 0.25
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
        sleep 0.25
    done
    return 1
}

wait_for_workspace_file() {
    local path="$1"
    local attempts="${2:-240}"
    for _ in $(seq 1 "$attempts"); do
        if [[ -e "$path" ]]; then
            return 0
        fi
        sleep 0.25
    done
    return 1
}

extract_demo_summary_from_codex_jsonl() {
    local jsonl_path="$1"
    local output_path="$2"
    python3 - "$jsonl_path" "$output_path" <<'PY'
import json
import sys
from pathlib import Path

jsonl_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])

def parse_summary(text: str):
    stripped = text.strip()
    if not stripped:
        return None
    candidates = [stripped]
    start = stripped.find("{")
    end = stripped.rfind("}")
    if start != -1 and end > start:
        candidates.append(stripped[start:end + 1])
    for candidate in candidates:
        try:
            parsed = json.loads(candidate)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict) and parsed.get("status") == "ok":
            return parsed
    return None

summary = None
for raw_line in jsonl_path.read_text(encoding="utf-8").splitlines():
    if not raw_line.strip():
        continue
    try:
        event = json.loads(raw_line)
    except json.JSONDecodeError:
        continue
    item = event.get("item") if event.get("type") == "item.completed" else None
    if not isinstance(item, dict):
        continue
    if item.get("type") != "command_execution":
        continue
    command = str(item.get("command") or "")
    if "python3 ./demo/run_cross_platform_demo.py" not in command:
        continue
    parsed = parse_summary(str(item.get("aggregated_output") or ""))
    if parsed is not None:
        summary = parsed

if summary is None:
    raise SystemExit("could not extract cross-platform demo summary from Codex JSONL")

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"summary_path": str(output_path), "status": summary.get("status")}, indent=2))
PY
}

pick_free_port() {
    python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

pick_free_display() {
    python3 - <<'PY'
from pathlib import Path
import subprocess

for display_num in range(95, 196):
    lock_path = Path(f"/tmp/.X{display_num}-lock")
    if lock_path.exists():
        continue
    display = f":{display_num}"
    probe = subprocess.run(
        ["bash", "-lc", f"xdpyinfo -display {display} >/dev/null 2>&1"],
        check=False,
    )
    if probe.returncode != 0:
        print(display)
        break
else:
    raise SystemExit("no free X display found")
PY
}

dump_target_mount_debug() {
    local root="$1"
    echo "--- mounted providers.json ---" >&2
    if [[ -f "$root/.spiderweb/catalog/providers.json" ]]; then
        cat "$root/.spiderweb/catalog/providers.json" >&2 || true
    else
        echo "missing $root/.spiderweb/catalog/providers.json" >&2
    fi
    echo >&2
    echo "--- mounted workspace_binds.json ---" >&2
    if [[ -f "$root/.spiderweb/workspace_binds.json" ]]; then
        cat "$root/.spiderweb/workspace_binds.json" >&2 || true
    else
        echo "missing $root/.spiderweb/workspace_binds.json" >&2
    fi
    echo >&2
    echo "--- mounted targets.json ---" >&2
    if [[ -f "$root/.spiderweb/catalog/targets.json" ]]; then
        cat "$root/.spiderweb/catalog/targets.json" >&2 || true
    else
        echo "missing $root/.spiderweb/catalog/targets.json" >&2
    fi
    echo >&2
    echo "--- mounted .spiderweb/targets tree ---" >&2
    if [[ -d "$root/.spiderweb/targets" ]]; then
        find "$root/.spiderweb/targets" -maxdepth 4 -print >&2 2>/dev/null || true
    else
        echo "missing $root/.spiderweb/targets" >&2
    fi
    echo >&2
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

write_shared_data_seed_files() {
    python3 - "$LINUX_SHARED_DATA_DIR" "$LINUX_TARGET_ID" "$MACOS_TARGET_ID" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
linux_target = sys.argv[2]
macos_target = sys.argv[3]
root.mkdir(parents=True, exist_ok=True)

(root / "world_seed.json").write_text(
    json.dumps(
        {
            "targets": [
                {"id": linux_target, "platform": "linux", "capabilities": ["computer", "browser"]},
                {"id": macos_target, "platform": "macos", "capabilities": ["computer", "browser"]},
            ]
        },
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)
(root / "items_seed.json").write_text(
    json.dumps(
        {
            "artifacts": [
                "cross_platform_demo_summary.json",
                "artifacts/final/linux/computer/last_observation.json",
                "artifacts/final/linux/browser/last_dom.json",
                "artifacts/final/macos/computer/last_observation.json",
                "artifacts/final/macos/browser/last_dom.json",
            ]
        },
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)
(root / "puzzle_seed.json").write_text(
    json.dumps(
        {
            "checks": [
                "linux and macos targets must both be exercised",
                "computer and browser must both be used on each target",
                "summary file must reflect distinct platform outcomes",
            ]
        },
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)
PY
}

ensure_linux_capability_runtime() {
    require_bin python3
    local -a apt_prefix=()
    if [[ "$(id -u)" != "0" ]]; then
        require_bin sudo
        apt_prefix=(sudo)
    fi
    local need_install=0
    if ! command -v Xvfb >/dev/null 2>&1; then need_install=1; fi
    if ! command -v npm >/dev/null 2>&1; then need_install=1; fi
    if ! python3 - <<'PY' >/dev/null 2>&1
import gi
import pyatspi
PY
    then
        need_install=1
    fi

    if [[ "$need_install" == "1" ]]; then
        log_info "Installing Linux desktop/browser runtime dependencies ..."
        "${apt_prefix[@]}" apt-get update
        DEBIAN_FRONTEND=noninteractive "${apt_prefix[@]}" apt-get install -y \
            dbus-x11 \
            gir1.2-gtk-3.0 \
            nodejs \
            npm \
            python3-gi \
            python3-pyatspi \
            x11-utils \
            xvfb
    fi

    mkdir -p "$NPM_GLOBAL_PREFIX" "$PLAYWRIGHT_BROWSERS_PATH" "$LINUX_NODE_HOME"
    local npm_env=(
        "HOME=$LINUX_NODE_HOME"
        "NPM_CONFIG_PREFIX=$NPM_GLOBAL_PREFIX"
        "PLAYWRIGHT_BROWSERS_PATH=$PLAYWRIGHT_BROWSERS_PATH"
        "PATH=$NPM_GLOBAL_PREFIX/bin:$PATH"
    )
    if [[ ! -d "$NPM_GLOBAL_PREFIX/lib/node_modules/playwright" ]]; then
        log_info "Installing Playwright into isolated Linux runtime prefix ..."
        env "${npm_env[@]}" npm install -g playwright >/dev/null
    fi
    if ! compgen -G "$PLAYWRIGHT_BROWSERS_PATH/chromium-*" >/dev/null; then
        log_info "Installing Chromium for the Linux browser target ..."
        env "${npm_env[@]}" "$NPM_GLOBAL_PREFIX/bin/playwright" install chromium >/dev/null
    fi
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
    ensure_linux_capability_runtime
    write_shared_data_seed_files

    if [[ -z "$LOCAL_WORKSPACE_NODE_PORT" ]]; then
        LOCAL_WORKSPACE_NODE_PORT="$(pick_free_port)"
    fi
    if [[ -z "$LINUX_BROWSER_PORT" ]]; then
        LINUX_BROWSER_PORT="$(pick_free_port)"
    fi
    if [[ -z "$LINUX_DISPLAY" ]]; then
        LINUX_DISPLAY="$(pick_free_display)"
    fi
    LINUX_BROWSER_URL="http://127.0.0.1:${LINUX_BROWSER_PORT}/index.html"

    cat > "$SPIDERWEB_CONFIG_FILE" <<EOF
{
  "provider": {
    "name": "openai",
    "model": "gpt-4o-mini"
  },
  "runtime": {
    "default_agent_id": "default",
    "state_directory": "$SPIDERWEB_STATE_DIR",
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

    log_info "Writing Linux capability manifests ..."
    python3 "$WRITE_CAPABILITY_MANIFESTS" \
        --platform linux \
        --output-dir "$LINUX_CAPABILITY_MANIFEST_DIR" \
        --computer-driver "$SPIDERNODE_PREFIX/bin/spiderweb-computer-driver" \
        --browser-driver "$SPIDERNODE_PREFIX/bin/spiderweb-browser-driver" \
        --browser-state-path "$LINUX_BROWSER_STATE_PATH" \
        --browser-profile-dir "$LINUX_BROWSER_PROFILE_DIR" \
        --browser-env "NODE_PATH=$NPM_GLOBAL_PREFIX/lib/node_modules" \
        --browser-env "PLAYWRIGHT_BROWSERS_PATH=$PLAYWRIGHT_BROWSERS_PATH"

    log_info "Starting Linux desktop session, fixtures, and capability node ..."
    nohup env \
        HOME="$LINUX_NODE_HOME" \
        NPM_CONFIG_PREFIX="$NPM_GLOBAL_PREFIX" \
        PLAYWRIGHT_BROWSERS_PATH="$PLAYWRIGHT_BROWSERS_PATH" \
        PATH="$NPM_GLOBAL_PREFIX/bin:$PATH" \
        SPIDER_FIXTURE_APP_NAME="$LINUX_FIXTURE_APP_NAME" \
        SPIDER_FIXTURE_STATE_PATH="$LINUX_FIXTURE_STATE" \
        SPIDER_FIXTURE_WINDOW_TITLE="$LINUX_WINDOW_TITLE" \
        SPIDER_FIXTURE_BUTTON_TITLE="$BUTTON_TITLE" \
        SPIDER_FIXTURE_INITIAL_TEXT="" \
        dbus-run-session bash -lc "
set -euo pipefail
export DISPLAY='$LINUX_DISPLAY'
export NO_AT_BRIDGE=0
export GTK_MODULES='gail:atk-bridge'
Xvfb '$LINUX_DISPLAY' -screen 0 1280x900x24 -ac >/tmp/${RUN_NAME}-xvfb.log 2>&1 &
XVFB_PID=\$!
cleanup() {
  if [[ -n \${NODE_PID:-} ]]; then kill \$NODE_PID >/dev/null 2>&1 || true; fi
  kill \$XVFB_PID >/dev/null 2>&1 || true
  if [[ -n \${FIXTURE_PID:-} ]]; then kill \$FIXTURE_PID >/dev/null 2>&1 || true; fi
  if [[ -n \${HTTP_PID:-} ]]; then kill \$HTTP_PID >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT
for _ in \$(seq 1 120); do
  if xdpyinfo -display '$LINUX_DISPLAY' >/dev/null 2>&1; then break; fi
  sleep 0.25
done
$(printf '%q' "$SPIDERNODE_BIN") \
  --bind $(printf '%q' "$LOCAL_NODE_BIND_ADDR") \
  --port $(printf '%q' "$LOCAL_WORKSPACE_NODE_PORT") \
  --export workspace=$(printf '%q' "$WORKSPACE_EXPORT_ROOT"):rw \
  --export shared=$(printf '%q' "$LINUX_SHARED_DATA_DIR"):ro \
  --venoms-dir $(printf '%q' "$LINUX_CAPABILITY_MANIFEST_DIR") \
  --control-url $(printf '%q' "$CONTROL_URL_LOCAL") \
  --control-auth-token $(printf '%q' "$auth_token") \
  --pair-mode invite \
  --invite-token $(printf '%q' "$local_invite_token") \
  --node-name $(printf '%q' "$LOCAL_WORKSPACE_NODE_NAME") \
  --state-file $(printf '%q' "$STATE_DIR/linux-workspace-node-state.json") &
NODE_PID=\$!
sleep 1
python3 - <<'PY' >/dev/null 2>&1 || true
import time

try:
    import pyatspi
except Exception:
    raise SystemExit(0)

for _ in range(20):
    try:
        pyatspi.Registry.getDesktop(0)
        break
    except Exception:
        time.sleep(0.25)
PY
sleep 1
python3 $(printf '%q' "$LINUX_FIXTURE_SCRIPT") >/tmp/${RUN_NAME}-linux-computer-fixture.log 2>&1 &
FIXTURE_PID=\$!
sleep 1
if ! kill -0 \$FIXTURE_PID >/dev/null 2>&1; then
  cat /tmp/${RUN_NAME}-linux-computer-fixture.log >&2 || true
  exit 1
fi
(cd $(printf '%q' "$BROWSER_FIXTURE_DIR") && python3 -m http.server $(printf '%q' "$LINUX_BROWSER_PORT") --bind 127.0.0.1) >/tmp/${RUN_NAME}-linux-browser-fixture.log 2>&1 &
HTTP_PID=\$!
wait \$NODE_PID
" >"$LINUX_DESKTOP_LOG" 2>&1 </dev/null &
    echo "$!" > "$LOCAL_WORKSPACE_NODE_PID_FILE"

    local local_workspace_node_id=""
    if ! wait_for_node_join "$auth_token" "$LOCAL_WORKSPACE_NODE_NAME" local_workspace_node_id; then
        log_fail "Linux workspace node did not join Spiderweb"
        tail -n 200 "$LINUX_DESKTOP_LOG" || true
        exit 1
    fi
    log_pass "Linux workspace node joined as $local_workspace_node_id"

    local remote_invite_resp remote_invite_token
    remote_invite_resp="$(control_call "$auth_token" node_invite_create)"
    remote_invite_token="$(json_query "$remote_invite_resp" "payload.invite_token")"

    python3 - "$HANDOFF_FILE" "$CONTROL_URL_REMOTE" "$auth_token" "$remote_invite_token" "$REMOTE_NODE_NAME" "$local_workspace_node_id" "$LINUX_BROWSER_URL" "$LINUX_WINDOW_TITLE" "$BUTTON_TITLE" "$LINUX_FIXTURE_APP_NAME" <<'PY'
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
    "local_workspace_node_id": sys.argv[6],
    "linux_browser_url": sys.argv[7],
    "linux_window_title": sys.argv[8],
    "button_title": sys.argv[9],
    "linux_app_name": sys.argv[10],
}
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

render_prompt() {
    python3 - "$PROMPT_TEMPLATE" "$LINUX_PROMPT_FILE" "$LINUX_BROWSER_URL" "$MACOS_BROWSER_URL" "$LINUX_WINDOW_TITLE" "$MACOS_APP_NAME" "$MACOS_WINDOW_TITLE" "$BUTTON_TITLE" "$LINUX_COMPUTER_TEXT" "$MACOS_COMPUTER_TEXT" "$LINUX_BROWSER_TEXT" "$MACOS_BROWSER_TEXT" <<'PY'
from pathlib import Path
import sys

template = Path(sys.argv[1]).read_text(encoding="utf-8")
replacements = {
    "__LINUX_BROWSER_URL__": sys.argv[3],
    "__MACOS_BROWSER_URL__": sys.argv[4],
    "__LINUX_WINDOW_TITLE__": sys.argv[5],
    "__MACOS_APP_NAME__": sys.argv[6],
    "__MACOS_WINDOW_TITLE__": sys.argv[7],
    "__BUTTON_TITLE__": sys.argv[8],
    "__LINUX_COMPUTER_TEXT__": sys.argv[9],
    "__MACOS_COMPUTER_TEXT__": sys.argv[10],
    "__LINUX_BROWSER_TEXT__": sys.argv[11],
    "__MACOS_BROWSER_TEXT__": sys.argv[12],
}
for key, value in replacements.items():
    template = template.replace(key, value)
Path(sys.argv[2]).write_text(template, encoding="utf-8")
PY
}

render_helper() {
    python3 - "$HELPER_TEMPLATE" "$LINUX_HELPER_FILE" "$LINUX_BROWSER_URL" "$MACOS_BROWSER_URL" "$LINUX_WINDOW_TITLE" "$MACOS_APP_NAME" "$MACOS_WINDOW_TITLE" "$BUTTON_TITLE" "$LINUX_COMPUTER_TEXT" "$MACOS_COMPUTER_TEXT" "$LINUX_BROWSER_TEXT" "$MACOS_BROWSER_TEXT" <<'PY'
from pathlib import Path
import sys

template = Path(sys.argv[1]).read_text(encoding="utf-8")
replacements = {
    "__LINUX_BROWSER_URL__": sys.argv[3],
    "__MACOS_BROWSER_URL__": sys.argv[4],
    "__LINUX_WINDOW_TITLE__": sys.argv[5],
    "__MACOS_APP_NAME__": sys.argv[6],
    "__MACOS_WINDOW_TITLE__": sys.argv[7],
    "__BUTTON_TITLE__": sys.argv[8],
    "__LINUX_COMPUTER_TEXT__": sys.argv[9],
    "__MACOS_COMPUTER_TEXT__": sys.argv[10],
    "__LINUX_BROWSER_TEXT__": sys.argv[11],
    "__MACOS_BROWSER_TEXT__": sys.argv[12],
}
for key, value in replacements.items():
    template = template.replace(key, value)
Path(sys.argv[2]).write_text(template, encoding="utf-8")
PY
}

finish_scenario() {
    require_bin python3
    require_bin codex
    if [[ -z "$MACOS_BROWSER_URL" || -z "$MACOS_WINDOW_TITLE" || -z "$MACOS_FIXTURE_STATE_PATH" ]]; then
        log_fail "MACOS_BROWSER_URL, MACOS_WINDOW_TITLE, and MACOS_FIXTURE_STATE_PATH are required for finish_scenario"
        exit 1
    fi

    if [[ -z "$LINUX_BROWSER_URL" && -n "$LINUX_BROWSER_PORT" ]]; then
        LINUX_BROWSER_URL="http://127.0.0.1:${LINUX_BROWSER_PORT}/index.html"
    fi
    if [[ -z "$LINUX_BROWSER_URL" && -f "$HANDOFF_FILE" ]]; then
        LINUX_BROWSER_URL="$(python3 - "$HANDOFF_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
print(data.get("linux_browser_url") or "")
PY
)"
    fi

    local auth_token
    auth_token="$(load_access_token)" || {
        log_fail "missing Spiderweb access token"
        exit 1
    }

    local local_workspace_node_id=""
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

    local remote_node_id=""
    if ! wait_for_node_join "$auth_token" "$REMOTE_NODE_NAME" remote_node_id; then
        log_fail "remote macOS node did not join Spiderweb"
        exit 1
    fi
    log_pass "Remote macOS node joined as $remote_node_id"

    local workspace_up_payload workspace_up_resp workspace_id workspace_token
    workspace_up_payload="$(python3 - "$local_workspace_node_id" <<'PY'
import json
import sys

payload = {
    "name": "Cross Platform Computer Browser Demo",
    "vision": "Single agent controls Linux and macOS computer/browser targets through stable Spiderweb target binds",
    "template_id": "dev",
    "activate": True,
    "desired_mounts": [
        {
            "mount_path": "/nodes/local/fs",
            "node_id": sys.argv[1],
            "export_name": "workspace"
        },
        {
            "mount_path": "/shared_data",
            "node_id": sys.argv[1],
            "export_name": "shared"
        }
    ]
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

    render_prompt
    render_helper
    cp "$LINUX_HELPER_FILE" "$WORKSPACE_EXPORT_ROOT/run_cross_platform_demo.py"

    local bind_specs=(
        "/.spiderweb/targets/${LINUX_TARGET_ID}/computer:/nodes/${local_workspace_node_id}/venoms/computer-main"
        "/.spiderweb/targets/${LINUX_TARGET_ID}/browser:/nodes/${local_workspace_node_id}/venoms/browser-main"
        "/.spiderweb/targets/${MACOS_TARGET_ID}/computer:/nodes/${remote_node_id}/venoms/computer-main"
        "/.spiderweb/targets/${MACOS_TARGET_ID}/browser:/nodes/${remote_node_id}/venoms/browser-main"
        "/demo/run_cross_platform_demo.py:/nodes/local/fs/run_cross_platform_demo.py"
    )
    local bind_path=""
    local target_path=""
    for spec in "${bind_specs[@]}"; do
        bind_path="${spec%%:*}"
        target_path="${spec#*:}"
        control_call "$auth_token" workspace_bind_set "$(python3 - "$workspace_id" "$workspace_token" "$bind_path" "$target_path" <<'PY'
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
)" >/dev/null
    done

    log_info "Mounting workspace namespace on Linux host ..."
    nohup "$FS_MOUNT_BIN" \
        --namespace-url "$CONTROL_URL_LOCAL" \
        --workspace-id "$workspace_id" \
        --auth-token "$auth_token" \
        --agent-id cross-platform-computer-browser-demo \
        --session-key cross-platform-computer-browser-demo \
        mount "$MOUNT_POINT" >"$MOUNT_LOG" 2>&1 </dev/null &
    echo "$!" > "$MOUNT_PID_FILE"

    if ! wait_for_workspace_file "$MOUNT_POINT/.spiderweb/catalog/targets.json"; then
        log_fail "workspace mount did not expose targets.json"
        tail -n 200 "$MOUNT_LOG" || true
        exit 1
    fi
    if ! wait_for_workspace_file "$MOUNT_POINT/.spiderweb/targets/${LINUX_TARGET_ID}/computer/control/invoke.json"; then
        log_fail "linux computer target did not appear in the mounted workspace"
        dump_target_mount_debug "$MOUNT_POINT"
        tail -n 200 "$MOUNT_LOG" >&2 || true
        exit 1
    fi
    if ! wait_for_workspace_file "$MOUNT_POINT/.spiderweb/targets/${MACOS_TARGET_ID}/browser/control/invoke.json"; then
        log_fail "macOS browser target did not appear in the mounted workspace"
        dump_target_mount_debug "$MOUNT_POINT"
        tail -n 200 "$MOUNT_LOG" >&2 || true
        exit 1
    fi
    if ! wait_for_workspace_file "$MOUNT_POINT/demo/run_cross_platform_demo.py"; then
        log_fail "workspace helper script did not appear in the mounted workspace"
        dump_target_mount_debug "$MOUNT_POINT"
        exit 1
    fi

    log_info "Running single-agent Codex demo in the mounted workspace ..."
    cat "$LINUX_PROMPT_FILE" | \
        codex exec \
            --json \
            --skip-git-repo-check \
            --dangerously-bypass-approvals-and-sandbox \
            --ephemeral \
            --color never \
            -C "$MOUNT_POINT" \
            -o "$LINUX_CODEX_LAST" \
            - \
            >"$LINUX_CODEX_JSONL" \
            2>"$LINUX_CODEX_STDERR"

    local validator_summary_path="$ARTIFACT_DIR/cross_platform_demo_summary.json"
    if [[ -s "$LINUX_SUMMARY_PATH" ]]; then
        cp "$LINUX_SUMMARY_PATH" "$validator_summary_path"
    else
        log_info "Mounted workspace summary file was missing or empty; extracting summary from Codex JSON output ..."
        if ! extract_demo_summary_from_codex_jsonl "$LINUX_CODEX_JSONL" "$validator_summary_path"; then
            log_fail "Codex run did not produce an extractable cross-platform summary"
            tail -n 200 "$LINUX_CODEX_STDERR" || true
            exit 1
        fi
    fi
    cp "$MOUNT_POINT/.spiderweb/catalog/targets.json" "$ARTIFACT_DIR/targets.catalog.json"
    cp "$MACOS_FIXTURE_STATE_PATH" "$ARTIFACT_DIR/macos-computer-fixture-state.json"
    mkdir -p "$ARTIFACT_DIR/final/linux/computer" "$ARTIFACT_DIR/final/linux/browser" "$ARTIFACT_DIR/final/macos/computer" "$ARTIFACT_DIR/final/macos/browser"
    cp "$MOUNT_POINT/.spiderweb/targets/${LINUX_TARGET_ID}/computer/artifacts/last_observation.json" "$ARTIFACT_DIR/final/linux/computer/last_observation.json"
    cp "$MOUNT_POINT/.spiderweb/targets/${LINUX_TARGET_ID}/browser/artifacts/last_dom.json" "$ARTIFACT_DIR/final/linux/browser/last_dom.json"
    cp "$MOUNT_POINT/.spiderweb/targets/${MACOS_TARGET_ID}/computer/artifacts/last_observation.json" "$ARTIFACT_DIR/final/macos/computer/last_observation.json"
    cp "$MOUNT_POINT/.spiderweb/targets/${MACOS_TARGET_ID}/browser/artifacts/last_dom.json" "$ARTIFACT_DIR/final/macos/browser/last_dom.json"

    log_info "Validating cross-platform demo outputs ..."
    python3 "$VALIDATOR" \
        --workspace-root "$MOUNT_POINT" \
        --summary "$validator_summary_path" \
        --linux-fixture-state "$LINUX_FIXTURE_STATE" \
        --macos-fixture-state "$ARTIFACT_DIR/macos-computer-fixture-state.json" \
        --linux-computer-text "$LINUX_COMPUTER_TEXT" \
        --macos-computer-text "$MACOS_COMPUTER_TEXT" \
        --linux-browser-text "$LINUX_BROWSER_TEXT" \
        --macos-browser-text "$MACOS_BROWSER_TEXT" \
        --output "$VALIDATION_JSON"

    python3 - "$RESULT_FILE" "$workspace_id" "$remote_node_id" "$local_workspace_node_id" "$LINUX_BROWSER_URL" "$MACOS_BROWSER_URL" <<'PY'
import json
import sys
from pathlib import Path

payload = {
    "workspace_id": sys.argv[2],
    "remote_node_id": sys.argv[3],
    "local_workspace_node_id": sys.argv[4],
    "linux_browser_url": sys.argv[5],
    "macos_browser_url": sys.argv[6],
}
path = Path(sys.argv[1])
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
