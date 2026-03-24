#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPIDERWEB_DIR="$ROOT_DIR/Spiderweb"

FIXTURE_DIR="$ROOT_DIR/e2e/fixtures/macos-computer-browser"
FIXTURE_SWIFT="$FIXTURE_DIR/ComputerFixtureApp.swift"
BROWSER_FIXTURE_DIR="$FIXTURE_DIR/browser_fixture"

OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/e2e/out/macos-computer-browser-node-$(date +%Y%m%d-%H%M%S)-$$}"
LOG_DIR="$OUTPUT_DIR/logs"
STATE_DIR="$OUTPUT_DIR/state"
ARTIFACT_DIR="$OUTPUT_DIR/artifacts"
BUILD_DIR="$OUTPUT_DIR/build"
TEMP_HOME="$OUTPUT_DIR/home"
LTM_DIR="$OUTPUT_DIR/ltm"
SPIDERWEB_RUNTIME_ROOT="$OUTPUT_DIR/spiderweb-root"
WORKSPACE_EXPORT_ROOT="$OUTPUT_DIR/workspace-export"

SPIDERWEB_PORT="${SPIDERWEB_PORT:-}"
BROWSER_FIXTURE_PORT="${BROWSER_FIXTURE_PORT:-}"
CONTROL_URL=""

KEEP_TEMP="${KEEP_TEMP:-0}"
SKIP_BUILD="${SKIP_BUILD:-0}"
COMPUTER_INCLUDE_SCREENSHOT="${COMPUTER_INCLUDE_SCREENSHOT:-0}"
BROWSER_INCLUDE_SCREENSHOT="${BROWSER_INCLUDE_SCREENSHOT:-0}"
REQUIRE_SCREEN_CAPTURE="${REQUIRE_SCREEN_CAPTURE:-0}"

FIXTURE_WINDOW_TITLE="${FIXTURE_WINDOW_TITLE:-Spider Computer Fixture Window}"
FIXTURE_BUTTON_TITLE="${FIXTURE_BUTTON_TITLE:-Press Fixture Button}"
COMPUTER_TYPED_TEXT="${COMPUTER_TYPED_TEXT:-Hello from Spiderweb}"
BROWSER_TYPED_TEXT="${BROWSER_TYPED_TEXT:-browser venom works}"

SPIDERWEB_BIN="$SPIDERWEB_DIR/zig-out/bin/spiderweb"
CONTROL_BIN="$SPIDERWEB_DIR/zig-out/bin/spiderweb-control"
FS_MOUNT_BIN="$SPIDERWEB_DIR/zig-out/bin/spiderweb-fs-mount"
CONFIG_FILE="$OUTPUT_DIR/spiderweb.json"
AUTH_TOKENS_FILE="$LTM_DIR/auth_tokens.json"
SPIDERWEB_LOG="$LOG_DIR/spiderweb.log"
HTTP_LOG="$LOG_DIR/browser-fixture-http.log"
FIXTURE_APP_LOG="$LOG_DIR/computer-fixture.log"
FIXTURE_APP_BIN="$BUILD_DIR/SpiderComputerFixture"
FIXTURE_APP_STATE="$STATE_DIR/computer-fixture-state.json"

SPIDERWEB_PID=""
HTTP_PID=""
FIXTURE_APP_PID=""

SPIDERWEB_AUTH_TOKEN=""
WORKSPACE_ID=""
WORKSPACE_TOKEN=""
LOCAL_NODE_ID=""
BROWSER_APP_NAME=""
BROWSER_URL=""

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1" >&2; }

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

load_access_token() {
    python3 - "$AUTH_TOKENS_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)
print(str(data.get("access_token") or "").strip())
PY
}

wait_for_control_ready() {
    for _ in $(seq 1 240); do
        if [[ -f "$AUTH_TOKENS_FILE" ]]; then
            SPIDERWEB_AUTH_TOKEN="$(load_access_token || true)"
            if [[ -n "$SPIDERWEB_AUTH_TOKEN" ]]; then
                if "$CONTROL_BIN" --url "$CONTROL_URL" --auth-token "$SPIDERWEB_AUTH_TOKEN" node_list '{}' >/dev/null 2>&1; then
                    return 0
                fi
            fi
        fi
        sleep 0.25
    done
    return 1
}

control_call() {
    local op="$1"
    local payload="${2-}"
    if [[ -n "$payload" ]]; then
        "$CONTROL_BIN" --url "$CONTROL_URL" --auth-token "$SPIDERWEB_AUTH_TOKEN" "$op" "$payload"
    else
        "$CONTROL_BIN" --url "$CONTROL_URL" --auth-token "$SPIDERWEB_AUTH_TOKEN" "$op"
    fi
}

fs_call() {
    "$FS_MOUNT_BIN" --workspace-url "$CONTROL_URL" --auth-token "$SPIDERWEB_AUTH_TOKEN" --workspace-id "$WORKSPACE_ID" "$@"
}

wait_for_path() {
    local path="$1"
    local attempts="${2:-120}"
    for _ in $(seq 1 "$attempts"); do
        if fs_call getattr "$path" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.25
    done
    return 1
}

wait_for_fs_contains() {
    local path="$1"
    local needle="$2"
    local attempts="${3:-120}"
    local content=""
    for _ in $(seq 1 "$attempts"); do
        content="$(fs_call cat "$path" 2>/dev/null || true)"
        if [[ "$content" == *"$needle"* ]]; then
            return 0
        fi
        sleep 0.25
    done
    return 1
}

resolve_local_node_id() {
    local node_list_json
    node_list_json="$(control_call node_list '{}')"
    python3 - "$node_list_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1]).get("payload") or {}
nodes = payload.get("nodes") or []
if not nodes:
    print("")
    raise SystemExit(0)

preferred = None
for node in nodes:
    if (node.get("node_name") or "") == "spiderweb-local":
        preferred = node
        break
if preferred is None:
    preferred = nodes[0]
print(preferred.get("node_id") or "")
PY
}

wait_for_local_node() {
    for _ in $(seq 1 180); do
        LOCAL_NODE_ID="$(resolve_local_node_id || true)"
        if [[ -n "$LOCAL_NODE_ID" ]]; then
            return 0
        fi
        sleep 0.25
    done
    return 1
}

resolve_browser_app() {
    python3 - <<'PY'
from pathlib import Path

known = [
    ("Google Chrome", Path("/Applications/Google Chrome.app")),
    ("Chromium", Path("/Applications/Chromium.app")),
    ("Brave Browser", Path("/Applications/Brave Browser.app")),
]
for name, path in known:
    if path.exists():
        print(name)
        break
PY
}

compile_fixture_app() {
    log_info "Compiling macOS computer fixture app ..."
    swiftc -o "$FIXTURE_APP_BIN" "$FIXTURE_SWIFT" -framework AppKit
}

start_browser_fixture_server() {
    log_info "Starting local browser fixture server ..."
    (
        cd "$BROWSER_FIXTURE_DIR"
        python3 -m http.server "$BROWSER_FIXTURE_PORT" --bind 127.0.0.1
    ) >"$HTTP_LOG" 2>&1 &
    HTTP_PID="$!"
    BROWSER_URL="http://127.0.0.1:$BROWSER_FIXTURE_PORT/index.html"
}

start_spiderweb() {
    cat >"$CONFIG_FILE" <<EOF
{
  "provider": {
    "name": "openai",
    "model": "gpt-4o-mini"
  },
  "runtime": {
    "default_agent_id": "default",
    "state_directory": "$LTM_DIR",
    "state_db_filename": "runtime-state.db",
    "spider_web_root": "$SPIDERWEB_RUNTIME_ROOT",
    "local_node": {
      "export_path": "$WORKSPACE_EXPORT_ROOT"
    }
  }
}
EOF

    log_info "Starting Spiderweb on $CONTROL_URL ..."
    (
        cd "$SPIDERWEB_DIR"
        HOME="$TEMP_HOME" \
        SPIDERWEB_CONFIG="$CONFIG_FILE" \
        "$SPIDERWEB_BIN" \
            --bind 127.0.0.1 \
            --port "$SPIDERWEB_PORT"
    ) >"$SPIDERWEB_LOG" 2>&1 &
    SPIDERWEB_PID="$!"

    if ! wait_for_control_ready; then
        log_fail "Spiderweb did not become ready"
        tail -n 200 "$SPIDERWEB_LOG" || true
        exit 1
    fi
}

create_workspace() {
    local workspace_up_payload workspace_up_json
    workspace_up_payload="$(python3 - "$LOCAL_NODE_ID" <<'PY'
import json
import sys

print(json.dumps({
    "name": "macOS Computer Browser Node",
    "vision": "Local macOS node publishes explicit-bind computer and browser venoms",
    "template_id": "dev",
    "activate": True,
    "desired_mounts": [
        {
            "mount_path": "/nodes/local/fs",
            "node_id": sys.argv[1],
            "export_name": "workspace"
        }
    ]
}, separators=(",", ":")))
PY
)"
    workspace_up_json="$(control_call workspace_up "$workspace_up_payload")"
    WORKSPACE_ID="$(python3 - "$workspace_up_json" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1]).get("payload") or {}
print(payload.get("workspace_id") or "")
PY
)"
    WORKSPACE_TOKEN="$(python3 - "$workspace_up_json" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1]).get("payload") or {}
print(payload.get("workspace_token") or "")
PY
)"
    if [[ -z "$WORKSPACE_ID" ]]; then
        log_fail "workspace_up did not return a workspace id"
        printf '%s\n' "$workspace_up_json" >&2
        exit 1
    fi
    printf '%s\n' "$workspace_up_json" >"$ARTIFACT_DIR/workspace_up.json"
    log_pass "Workspace created: $WORKSPACE_ID"
}

wait_for_catalog_publication() {
    log_info "Waiting for node-published computer/browser providers to appear in the workspace catalog ..."
    for _ in $(seq 1 180); do
        local providers_json packages_json
        providers_json="$(fs_call cat "/.spiderweb/catalog/providers.json" 2>/dev/null || true)"
        packages_json="$(fs_call cat "/.spiderweb/catalog/packages.json" 2>/dev/null || true)"
        if [[ -n "$providers_json" && -n "$packages_json" ]]; then
            if jq -e '
                (map(.package_id) | index("computer")) != null and
                (map(.package_id) | index("browser")) != null and
                (map(.venom_id) | index("computer-main")) != null and
                (map(.venom_id) | index("browser-main")) != null
            ' >/dev/null <<<"$providers_json" && \
               jq -e '
                (map(.package_id) | index("computer")) != null and
                (map(.package_id) | index("browser")) != null
            ' >/dev/null <<<"$packages_json"; then
                printf '%s\n' "$providers_json" >"$ARTIFACT_DIR/providers.before-bind.json"
                printf '%s\n' "$packages_json" >"$ARTIFACT_DIR/packages.before-bind.json"
                return 0
            fi
        fi
        sleep 0.25
    done
    return 1
}

assert_absent_before_bind() {
    log_info "Asserting computer/browser are still absent from the public venom aliases before bind ..."
    if fs_call getattr "/.spiderweb/venoms/computer" >/dev/null 2>&1; then
        log_fail "computer alias is present before bind"
        exit 1
    fi
    if fs_call getattr "/.spiderweb/venoms/browser" >/dev/null 2>&1; then
        log_fail "browser alias is present before bind"
        exit 1
    fi
    local venoms_json
    venoms_json="$(fs_call cat "/.spiderweb/venoms/VENOMS.json")"
    printf '%s\n' "$venoms_json" >"$ARTIFACT_DIR/venoms.before-bind.json"
    if [[ "$venoms_json" == *"/.spiderweb/venoms/computer"* || "$venoms_json" == *"/.spiderweb/venoms/browser"* ]]; then
        log_fail "VENOMS.json advertised computer/browser before bind"
        exit 1
    fi
}

bind_capabilities() {
    log_info "Binding computer and browser aliases into the workspace ..."
    control_call workspace_bind_set "$(python3 - "$WORKSPACE_ID" "$WORKSPACE_TOKEN" "$LOCAL_NODE_ID" <<'PY'
import json
import sys

payload = {
    "workspace_id": sys.argv[1],
    "bind_path": "/.spiderweb/venoms/computer",
    "target_path": f"/nodes/{sys.argv[3]}/venoms/computer-main",
}
if sys.argv[2]:
    payload["workspace_token"] = sys.argv[2]
print(json.dumps(payload, separators=(",", ":")))
PY
)" >/dev/null

    control_call workspace_bind_set "$(python3 - "$WORKSPACE_ID" "$WORKSPACE_TOKEN" "$LOCAL_NODE_ID" <<'PY'
import json
import sys

payload = {
    "workspace_id": sys.argv[1],
    "bind_path": "/.spiderweb/venoms/browser",
    "target_path": f"/nodes/{sys.argv[3]}/venoms/browser-main",
}
if sys.argv[2]:
    payload["workspace_token"] = sys.argv[2]
print(json.dumps(payload, separators=(",", ":")))
PY
)" >/dev/null

    if ! wait_for_path "/.spiderweb/venoms/computer/control/invoke.json"; then
        log_fail "computer invoke path did not appear after bind"
        exit 1
    fi
    if ! wait_for_path "/.spiderweb/venoms/browser/control/invoke.json"; then
        log_fail "browser invoke path did not appear after bind"
        exit 1
    fi

    local bindings_json venoms_json
    bindings_json="$(fs_call cat "/.spiderweb/catalog/bindings.json")"
    venoms_json="$(fs_call cat "/.spiderweb/venoms/VENOMS.json")"
    printf '%s\n' "$bindings_json" >"$ARTIFACT_DIR/bindings.after-bind.json"
    printf '%s\n' "$venoms_json" >"$ARTIFACT_DIR/venoms.after-bind.json"
    if [[ "$venoms_json" != *"/.spiderweb/venoms/computer"* || "$venoms_json" != *"/.spiderweb/venoms/browser"* ]]; then
        log_fail "VENOMS.json did not advertise bound computer/browser aliases"
        exit 1
    fi
}

start_fixture_app() {
    log_info "Launching the deterministic macOS fixture app ..."
    SPIDER_FIXTURE_STATE_PATH="$FIXTURE_APP_STATE" \
    SPIDER_FIXTURE_WINDOW_TITLE="$FIXTURE_WINDOW_TITLE" \
    SPIDER_FIXTURE_BUTTON_TITLE="$FIXTURE_BUTTON_TITLE" \
    SPIDER_FIXTURE_INITIAL_TEXT="" \
    "$FIXTURE_APP_BIN" >"$FIXTURE_APP_LOG" 2>&1 &
    FIXTURE_APP_PID="$!"

    for _ in $(seq 1 120); do
        if [[ -f "$FIXTURE_APP_STATE" ]]; then
            return 0
        fi
        sleep 0.25
    done
    log_fail "fixture app did not create its state file"
    tail -n 50 "$FIXTURE_APP_LOG" || true
    exit 1
}

invoke_venom() {
    local alias="$1"
    local payload="$2"
    fs_call write "/.spiderweb/venoms/$alias/control/invoke.json" "$payload" >/dev/null
    sleep 1
    fs_call cat "/.spiderweb/venoms/$alias/result.json"
}

run_computer_flow() {
    log_info "Running computer observe ..."
    local observe_payload observe_json
    observe_payload="$(python3 - "$COMPUTER_INCLUDE_SCREENSHOT" <<'PY'
import json
import sys
print(json.dumps({
    "op": "observe",
    "arguments": {
        "include_screenshot": sys.argv[1] == "1"
    }
}, separators=(",", ":")))
PY
)"
    observe_json="$(invoke_venom "computer" "$observe_payload")"
    printf '%s\n' "$observe_json" >"$ARTIFACT_DIR/computer.observe.result.json"

    local accessibility
    accessibility="$(jq -r '(.health.permissions.accessibility // .status.permissions.accessibility // false)' <<<"$observe_json")"
    if [[ "$accessibility" != "true" ]]; then
        log_fail "computer observe reported accessibility not granted; allow $(cd "$SPIDERWEB_DIR" && pwd)/zig-out/bin/spiderweb-computer-driver in System Settings > Privacy & Security > Accessibility"
        exit 1
    fi

    if ! wait_for_path "/.spiderweb/venoms/computer/artifacts/last_observation.json"; then
        log_fail "computer observation artifact was not created"
        exit 1
    fi
    local observation_json
    observation_json="$(fs_call cat "/.spiderweb/venoms/computer/artifacts/last_observation.json")"
    printf '%s\n' "$observation_json" >"$ARTIFACT_DIR/computer.last_observation.json"
    if [[ "$observation_json" != *"$FIXTURE_WINDOW_TITLE"* ]]; then
        log_fail "computer observation did not include the fixture window title"
        exit 1
    fi

    if [[ "$COMPUTER_INCLUDE_SCREENSHOT" == "1" || "$REQUIRE_SCREEN_CAPTURE" == "1" ]]; then
        if ! wait_for_path "/.spiderweb/venoms/computer/artifacts/last_screenshot.png"; then
            log_fail "computer screenshot artifact was not created"
            exit 1
        fi
    fi

    log_info "Running computer activate ..."
    invoke_venom "computer" "$(python3 - <<'PY'
import json
print(json.dumps({
    "op": "act",
    "arguments": {
        "action": "activate",
        "app_name": "SpiderComputerFixture"
    }
}, separators=(",", ":")))
PY
)" >/dev/null

    log_info "Running computer primary_tap ..."
    invoke_venom "computer" "$(python3 - "$FIXTURE_BUTTON_TITLE" <<'PY'
import json
import sys
print(json.dumps({
    "op": "act",
    "arguments": {
        "action": "primary_tap",
        "button_title": sys.argv[1]
    }
}, separators=(",", ":")))
PY
)" >/dev/null

    log_info "Running computer text_input ..."
    invoke_venom "computer" "$(python3 - "$COMPUTER_TYPED_TEXT" <<'PY'
import json
import sys
print(json.dumps({
    "op": "act",
    "arguments": {
        "action": "text_input",
        "text": sys.argv[1]
    }
}, separators=(",", ":")))
PY
)" >/dev/null

    python3 - "$FIXTURE_APP_STATE" "$COMPUTER_TYPED_TEXT" <<'PY'
import json
import sys
import time
from pathlib import Path

state_path = Path(sys.argv[1])
expected_text = sys.argv[2]
deadline = time.time() + 10.0

while time.time() < deadline:
    if state_path.exists():
        data = json.loads(state_path.read_text(encoding="utf-8"))
        if int(data.get("button_press_count") or 0) >= 1 and data.get("last_text") == expected_text:
            print(json.dumps(data, indent=2))
            raise SystemExit(0)
    time.sleep(0.25)

raise SystemExit("fixture app state did not reflect the expected button press and typed text")
PY
    cp "$FIXTURE_APP_STATE" "$ARTIFACT_DIR/computer.fixture_state.json"
}

run_browser_flow() {
    log_info "Launching browser fixture target ..."
    open -a "$BROWSER_APP_NAME" "about:blank" >/dev/null 2>&1 || true
    sleep 2

    log_info "Running browser navigate ..."
    invoke_venom "browser" "$(python3 - "$BROWSER_URL" <<'PY'
import json
import sys
print(json.dumps({
    "op": "act",
    "arguments": {
        "action": "navigate",
        "url": sys.argv[1]
    }
}, separators=(",", ":")))
PY
)" >/dev/null

    log_info "Running browser observe ..."
    local observe_payload observe_json
    observe_payload="$(python3 - "$BROWSER_INCLUDE_SCREENSHOT" <<'PY'
import json
import sys
print(json.dumps({
    "op": "observe",
    "arguments": {
        "include_dom": True,
        "include_screenshot": sys.argv[1] == "1"
    }
}, separators=(",", ":")))
PY
)"
    observe_json="$(invoke_venom "browser" "$observe_payload")"
    printf '%s\n' "$observe_json" >"$ARTIFACT_DIR/browser.observe.result.json"
    if [[ "$observe_json" != *"Spider Browser Fixture"* || "$observe_json" != *"$BROWSER_URL"* ]]; then
        log_fail "browser observe did not report the expected title/url"
        exit 1
    fi
    if ! wait_for_path "/.spiderweb/venoms/browser/artifacts/last_dom.json"; then
        log_fail "browser DOM artifact was not created"
        exit 1
    fi
    local dom_json
    dom_json="$(fs_call cat "/.spiderweb/venoms/browser/artifacts/last_dom.json")"
    printf '%s\n' "$dom_json" >"$ARTIFACT_DIR/browser.last_dom.before-act.json"
    if [[ "$dom_json" != *"Spider Browser Fixture"* ]]; then
        log_fail "browser DOM artifact did not include the fixture title"
        exit 1
    fi
    if [[ "$BROWSER_INCLUDE_SCREENSHOT" == "1" || "$REQUIRE_SCREEN_CAPTURE" == "1" ]]; then
        if ! wait_for_path "/.spiderweb/venoms/browser/artifacts/last_screenshot.png"; then
            log_fail "browser screenshot artifact was not created"
            exit 1
        fi
    fi

    log_info "Running browser text_input ..."
    invoke_venom "browser" "$(python3 - "$BROWSER_TYPED_TEXT" <<'PY'
import json
import sys
print(json.dumps({
    "op": "act",
    "arguments": {
        "action": "text_input",
        "selector": "#fixture-input",
        "text": sys.argv[1]
    }
}, separators=(",", ":")))
PY
)" >/dev/null

    log_info "Running browser click ..."
    invoke_venom "browser" "$(python3 - <<'PY'
import json
print(json.dumps({
    "op": "act",
    "arguments": {
        "action": "click",
        "selector": "#fixture-button"
    }
}, separators=(",", ":")))
PY
)" >/dev/null

    log_info "Running browser observe after act ..."
    observe_json="$(invoke_venom "browser" "$observe_payload")"
    printf '%s\n' "$observe_json" >"$ARTIFACT_DIR/browser.observe.after-act.result.json"
    dom_json="$(fs_call cat "/.spiderweb/venoms/browser/artifacts/last_dom.json")"
    printf '%s\n' "$dom_json" >"$ARTIFACT_DIR/browser.last_dom.after-act.json"
    if [[ "$dom_json" != *"clicked:$BROWSER_TYPED_TEXT"* ]]; then
        log_fail "browser DOM artifact did not show the expected clicked marker"
        exit 1
    fi
}

cleanup() {
    local exit_code=$?
    if [[ -n "$FIXTURE_APP_PID" ]]; then
        kill "$FIXTURE_APP_PID" >/dev/null 2>&1 || true
        wait "$FIXTURE_APP_PID" >/dev/null 2>&1 || true
    fi
    if [[ -n "$HTTP_PID" ]]; then
        kill "$HTTP_PID" >/dev/null 2>&1 || true
        wait "$HTTP_PID" >/dev/null 2>&1 || true
    fi
    if [[ -n "$SPIDERWEB_PID" ]]; then
        kill "$SPIDERWEB_PID" >/dev/null 2>&1 || true
        wait "$SPIDERWEB_PID" >/dev/null 2>&1 || true
    fi
    if [[ "$KEEP_TEMP" != "1" && -d "$OUTPUT_DIR" ]]; then
        rm -rf "$OUTPUT_DIR"
    fi
    exit "$exit_code"
}
trap cleanup EXIT

main() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_fail "this smoke lane currently requires macOS"
        exit 1
    fi

    require_bin python3
    require_bin jq
    require_bin zig
    require_bin swiftc
    require_bin open
    require_bin osascript

    if [[ ! -f "$FIXTURE_SWIFT" || ! -d "$BROWSER_FIXTURE_DIR" ]]; then
        log_fail "missing macOS computer/browser fixtures under $FIXTURE_DIR"
        exit 1
    fi

    mkdir -p "$OUTPUT_DIR" "$LOG_DIR" "$STATE_DIR" "$ARTIFACT_DIR" "$BUILD_DIR" "$TEMP_HOME" "$LTM_DIR" "$SPIDERWEB_RUNTIME_ROOT" "$WORKSPACE_EXPORT_ROOT"
    printf 'workspace fixture root\n' >"$WORKSPACE_EXPORT_ROOT/README.txt"

    if [[ -z "$SPIDERWEB_PORT" ]]; then
        SPIDERWEB_PORT="$(pick_free_port 127.0.0.1)"
    fi
    if [[ -z "$BROWSER_FIXTURE_PORT" ]]; then
        while true; do
            BROWSER_FIXTURE_PORT="$(pick_free_port 127.0.0.1)"
            if [[ "$BROWSER_FIXTURE_PORT" != "$SPIDERWEB_PORT" ]]; then
                break
            fi
        done
    fi
    CONTROL_URL="ws://127.0.0.1:$SPIDERWEB_PORT/"

    if [[ "$SKIP_BUILD" != "1" ]]; then
        log_info "Building Spiderweb with bundled local-node drivers ..."
        (
            cd "$SPIDERWEB_DIR"
            zig build
        )
    fi

    for bin in "$SPIDERWEB_BIN" "$CONTROL_BIN" "$FS_MOUNT_BIN"; do
        if [[ ! -x "$bin" ]]; then
            log_fail "missing required Spiderweb binary: $bin"
            exit 1
        fi
    done

    compile_fixture_app
    start_browser_fixture_server
    start_spiderweb

    if ! wait_for_local_node; then
        log_fail "could not resolve the local Spiderweb node id"
        exit 1
    fi
    log_pass "Local node resolved as $LOCAL_NODE_ID"

    BROWSER_APP_NAME="$(resolve_browser_app || true)"
    if [[ -z "$BROWSER_APP_NAME" ]]; then
        log_fail "no supported browser app found; install Google Chrome, Chromium, or Brave Browser"
        exit 1
    fi
    log_pass "Browser app resolved as $BROWSER_APP_NAME"

    create_workspace

    if ! wait_for_catalog_publication; then
        log_fail "computer/browser providers never appeared in the workspace catalog"
        tail -n 200 "$SPIDERWEB_LOG" || true
        exit 1
    fi
    log_pass "computer/browser providers are published in the catalog"

    assert_absent_before_bind
    log_pass "computer/browser remain explicit-bind-only before workspace bind"

    bind_capabilities
    log_pass "computer/browser aliases are bound and reachable through canonical venom paths"

    start_fixture_app
    run_computer_flow
    log_pass "computer observe + act loop succeeded"

    run_browser_flow
    log_pass "browser observe + act loop succeeded"

    python3 - "$ARTIFACT_DIR/summary.json" "$WORKSPACE_ID" "$LOCAL_NODE_ID" "$BROWSER_URL" <<'PY'
import json
import sys

summary = {
    "workspace_id": sys.argv[2],
    "local_node_id": sys.argv[3],
    "browser_url": sys.argv[4],
    "computer_alias": "/.spiderweb/venoms/computer",
    "browser_alias": "/.spiderweb/venoms/browser",
    "artifacts": {
        "providers_before_bind": "providers.before-bind.json",
        "packages_before_bind": "packages.before-bind.json",
        "bindings_after_bind": "bindings.after-bind.json",
        "computer_observe_result": "computer.observe.result.json",
        "computer_last_observation": "computer.last_observation.json",
        "computer_fixture_state": "computer.fixture_state.json",
        "browser_observe_result": "browser.observe.result.json",
        "browser_last_dom_before_act": "browser.last_dom.before-act.json",
        "browser_last_dom_after_act": "browser.last_dom.after-act.json",
    },
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(summary, handle, indent=2)
PY

    log_pass "macOS computer/browser node smoke completed"
    log_info "Artifacts are under $OUTPUT_DIR"
}

main "$@"
