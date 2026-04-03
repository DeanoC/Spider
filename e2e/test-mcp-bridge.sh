#!/usr/bin/env bash
# End-to-end test for spiderweb-mcp-bridge.
#
# Exercises the MCP bridge binary against a real MCP server
# (@modelcontextprotocol/server-filesystem) using a temporary fixture directory.
#
# Requirements: zig, node, npx, python or python3

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/e2e/output-cleanup.sh"
SPIDERWEB_DIR="$ROOT_DIR/Spiderweb"

OUTPUT_DIR_WAS_EXPLICIT=0
if [[ -n "${OUTPUT_DIR+x}" ]]; then
    OUTPUT_DIR_WAS_EXPLICIT=1
else
    OUTPUT_DIR="$ROOT_DIR/e2e/out/mcp-bridge-$(date +%Y%m%d-%H%M%S)-$$"
fi
LOG_DIR="$OUTPUT_DIR/logs"
ARTIFACT_DIR="$OUTPUT_DIR/artifacts"
KEEP_OUTPUT="${KEEP_OUTPUT:-}"

MCP_BRIDGE="$SPIDERWEB_DIR/zig-out/bin/spiderweb-mcp-bridge"
# On Windows the binary has an .exe extension
if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == CYGWIN* || "$(uname -s)" == MSYS* ]]; then
    MCP_BRIDGE="${MCP_BRIDGE}.exe"
    IS_WINDOWS=true
else
    IS_WINDOWS=false
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }

# Detect python binary (python3 on Linux/macOS, python on Windows)
PYTHON=""
for p in python3 python; do
    if command -v "$p" >/dev/null 2>&1 && "$p" --version 2>&1 | grep -q "^Python 3"; then
        PYTHON="$p"
        break
    fi
done

require_bin() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_fail "missing required command: $1"
        exit 1
    fi
}

# Convert a Unix path to a native OS path for use as MCP server arg and file paths.
# On Windows, uses cygpath; on Unix, identity.
native_path() {
    if [[ "$IS_WINDOWS" == "true" ]] && command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        echo "$1"
    fi
}

# Build a JSON payload using Python for correct escaping of paths/strings.
make_payload() {
    "$PYTHON" - "$@" <<'PY'
import json, sys, os
args = sys.argv[1:]
payload = {}
i = 0
while i < len(args):
    if args[i] == '--op':
        payload['op'] = args[i+1]; i += 2
    elif args[i] == '--tool':
        payload['tool'] = args[i+1]; i += 2
    elif args[i] == '--arg':
        k, v = args[i+1].split('=', 1); payload.setdefault('arguments', {})[k] = v; i += 2
    else:
        i += 1
print(json.dumps(payload))
PY
}

# Run the bridge with given JSON payload and save stdout/stderr to files.
run_bridge() {
    local out_file="$1"
    local err_file="$2"
    local payload="$3"
    shift 3
    echo "$payload" | "$MCP_BRIDGE" -- "$@" > "$out_file" 2>"$err_file"
}

# Assert JSON file has "ok": true.
assert_ok() {
    local file="$1"
    local label="$2"
    local ok
    ok=$("$PYTHON" - "$file" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
print(str(d.get('ok')).lower())
PY
)
    if [[ "$ok" != "true" ]]; then
        log_fail "$label: expected ok=true"
        "$PYTHON" - "$file" <<'PY' >&2
import sys
with open(sys.argv[1]) as f:
    print(f.read())
PY
        exit 1
    fi
}

# Extract a top-level field from a JSON file as a string.
json_field() {
    local file="$1"
    local field="$2"
    "$PYTHON" - "$file" "$field" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
v = d.get(sys.argv[2])
if v is None:
    print("")
elif isinstance(v, (dict, list)):
    print(json.dumps(v))
else:
    print(v)
PY
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        log_fail "$label: expected to contain '$needle'"
        echo "  Got: $haystack" >&2
        exit 1
    fi
}

cleanup() {
    local exit_code=$?
    if [[ -n "${FIXTURE_DIR:-}" && -d "$FIXTURE_DIR" ]]; then
        rm -rf "$FIXTURE_DIR"
    fi
    e2e_cleanup_output_dir "$exit_code" "$OUTPUT_DIR" "$OUTPUT_DIR_WAS_EXPLICIT" "$KEEP_OUTPUT"
    exit "$exit_code"
}
trap cleanup EXIT

main() {
    require_bin zig
    require_bin node
    require_bin npx

    if [[ -z "$PYTHON" ]]; then
        log_fail "python3 or python (3.x) is required but not found"
        exit 1
    fi

    mkdir -p "$OUTPUT_DIR" "$LOG_DIR" "$ARTIFACT_DIR"

    # ---- Build ----
    log_info "Building spiderweb-mcp-bridge ..."
    (
        cd "$SPIDERWEB_DIR"
        zig build \
            --cache-dir "$OUTPUT_DIR/zig-cache" \
            2>"$LOG_DIR/zig-build.log"
    ) || true  # other targets may fail on this platform; we only need mcp-bridge

    if [[ ! -f "$MCP_BRIDGE" ]]; then
        log_fail "spiderweb-mcp-bridge binary not found at: $MCP_BRIDGE"
        cat "$LOG_DIR/zig-build.log" >&2
        exit 1
    fi
    log_pass "Build succeeded"

    # ---- Fixture directory ----
    FIXTURE_DIR="$(mktemp -d)"
    echo "hello from mcp" > "$FIXTURE_DIR/hello.txt"
    echo '{"name":"test","value":42}' > "$FIXTURE_DIR/data.json"

    # Native path for passing to the MCP server (Windows needs backslashes)
    FIXTURE_NATIVE="$(native_path "$FIXTURE_DIR")"
    log_info "Fixture dir: $FIXTURE_NATIVE"

    # Pre-install the MCP server package to avoid slow first-run download timing.
    log_info "Pre-installing @modelcontextprotocol/server-filesystem ..."
    npx --yes @modelcontextprotocol/server-filesystem --version \
        > "$LOG_DIR/npx-prefetch.log" 2>&1 || true

    # ---- Test 1: tools/list ----
    log_info "Test 1: tools/list"
    local t1_out="$ARTIFACT_DIR/tools-list.json"
    local payload1
    payload1="$(make_payload --op tools/list)"
    run_bridge "$t1_out" "$LOG_DIR/test1-stderr.log" "$payload1" \
        npx -y @modelcontextprotocol/server-filesystem "$FIXTURE_NATIVE"

    assert_ok "$t1_out" "tools/list"
    local result1
    result1="$(json_field "$t1_out" "result")"
    assert_contains "$result1" "tools" "tools/list result has tools key"
    assert_contains "$result1" "read_file" "tools/list includes read_file"
    assert_contains "$result1" "list_directory" "tools/list includes list_directory"
    log_pass "tools/list returned expected tool listing"

    # ---- Test 2: tools/call — list_directory ----
    log_info "Test 2: tools/call list_directory"
    local t2_out="$ARTIFACT_DIR/list-directory.json"
    local payload2
    payload2="$(make_payload --op tools/call --tool list_directory --arg "path=$FIXTURE_NATIVE")"
    run_bridge "$t2_out" "$LOG_DIR/test2-stderr.log" "$payload2" \
        npx -y @modelcontextprotocol/server-filesystem "$FIXTURE_NATIVE"

    assert_ok "$t2_out" "tools/call list_directory"
    local result2
    result2="$(json_field "$t2_out" "result")"
    assert_contains "$result2" "hello.txt" "list_directory result contains hello.txt"
    assert_contains "$result2" "data.json" "list_directory result contains data.json"
    log_pass "list_directory returned expected files"

    # ---- Test 3: tools/call — read_file ----
    log_info "Test 3: tools/call read_file hello.txt"
    local t3_out="$ARTIFACT_DIR/read-file.json"
    local payload3
    payload3="$(make_payload --op tools/call --tool read_file --arg "path=${FIXTURE_NATIVE}/hello.txt")"
    if [[ "$IS_WINDOWS" == "true" ]]; then
        payload3="$(make_payload --op tools/call --tool read_file --arg "path=${FIXTURE_NATIVE}\\hello.txt")"
    fi
    run_bridge "$t3_out" "$LOG_DIR/test3-stderr.log" "$payload3" \
        npx -y @modelcontextprotocol/server-filesystem "$FIXTURE_NATIVE"

    assert_ok "$t3_out" "tools/call read_file"
    local result3
    result3="$(json_field "$t3_out" "result")"
    assert_contains "$result3" "hello from mcp" "read_file result contains expected content"
    log_pass "read_file returned expected content"

    # ---- Test 4: default op (omit 'op' field, defaults to tools/call) ----
    log_info "Test 4: default op (no 'op' field)"
    local t4_out="$ARTIFACT_DIR/default-op.json"
    local payload4
    payload4="$(make_payload --tool list_directory --arg "path=$FIXTURE_NATIVE")"
    run_bridge "$t4_out" "$LOG_DIR/test4-stderr.log" "$payload4" \
        npx -y @modelcontextprotocol/server-filesystem "$FIXTURE_NATIVE"

    assert_ok "$t4_out" "default op"
    local result4
    result4="$(json_field "$t4_out" "result")"
    assert_contains "$result4" "hello.txt" "default op result contains hello.txt"
    log_pass "default op (tools/call) works correctly"

    # ---- Test 5: error response — missing required tool field ----
    log_info "Test 5: error response for missing tool field"
    local t5_out="$ARTIFACT_DIR/missing-tool.json"
    echo '{"op":"tools/call"}' | "$MCP_BRIDGE" -- \
        npx -y @modelcontextprotocol/server-filesystem "$FIXTURE_NATIVE" \
        > "$t5_out" 2>"$LOG_DIR/test5-stderr.log" || true

    local ok5
    ok5=$("$PYTHON" - "$t5_out" <<'PY' 2>/dev/null || echo "invalid"
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
print(str(d.get('ok')).lower())
PY
)
    if [[ "$ok5" != "false" ]]; then
        log_fail "missing tool field: expected ok=false, got '$ok5'"
        "$PYTHON" - "$t5_out" <<'PY' >&2
import sys
with open(sys.argv[1]) as f:
    print(f.read())
PY
        exit 1
    fi
    log_pass "missing tool field returns ok=false error response"

    # ---- Test 6: unknown MCP tool returns valid response ----
    log_info "Test 6: unknown MCP tool"
    local t6_out="$ARTIFACT_DIR/unknown-tool.json"
    local payload6
    payload6="$(make_payload --op tools/call --tool nonexistent_xyz --arg "path=$FIXTURE_NATIVE")"
    echo "$payload6" | "$MCP_BRIDGE" -- \
        npx -y @modelcontextprotocol/server-filesystem "$FIXTURE_NATIVE" \
        > "$t6_out" 2>"$LOG_DIR/test6-stderr.log" || true

    if ! "$PYTHON" - "$t6_out" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    json.load(f)
PY
    then
        log_fail "unknown tool: response is not valid JSON"
        "$PYTHON" - "$t6_out" <<'PY' >&2
import sys
with open(sys.argv[1]) as f:
    print(f.read())
PY
        exit 1
    fi
    log_pass "unknown tool returns valid JSON response"

    echo ""
    log_pass "All MCP bridge e2e tests passed"
    log_info "Artifacts written to: $ARTIFACT_DIR"
}

main "$@"
