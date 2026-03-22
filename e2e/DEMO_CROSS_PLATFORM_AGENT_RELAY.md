# Manual Demo: Cross-Platform Agent Relay

This guide walks through the same cross-platform relay flow as the automated smoke test, but in a way that is easier to drive live during a demo.

It proves this full path:

- one Spiderweb host
- one Linux workspace node
- one macOS remote node
- one remote folder exported from macOS into Spiderweb
- one Linux Codex run writing results through Spiderweb into that remote folder
- one macOS Codex run reviewing those results locally from the exported folder

The current recommended demo lane is:

- Spiderweb host: Linux in Orb
- worker Codex: Linux in Orb
- remote node: macOS host
- reviewer Codex: macOS host

## Prerequisites

- macOS host with:
  - `orbctl`
  - `zig`
  - `python3`
  - `codex`
- a running Orb Linux machine
- working Codex login on both sides:

```bash
codex login status
orbctl run bash -lc 'codex login status'
```

- this repo checked out at:

```bash
/Users/deanocalver/Documents/Projects/Spider
```

## Pick a Run Directory and Ports

Use a fresh run directory and fresh ports each time.

```bash
export SPIDER_ROOT=/Users/deanocalver/Documents/Projects/Spider
export RUN_DIR="$SPIDER_ROOT/e2e/out/manual-agent-relay-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN_DIR"/{artifacts,logs,state}

export SPIDERWEB_PORT=28820
export LOCAL_WORKSPACE_NODE_PORT=28920
export REMOTE_NODE_PORT=28921
```

The helper script expects a path relative to the parent repo:

```bash
export RUN_DIR_REL="${RUN_DIR#"$SPIDER_ROOT/"}"
```

## Discover the Orb Linux IP

```bash
export ORB_IP="$(orbctl list | awk '/running/ {print $NF; exit}')"
echo "$ORB_IP"
```

Find the macOS host IP that Orb can reach:

```bash
export MAC_HOST_IP="$(python3 - "$ORB_IP" <<'PY'
import socket
import sys

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    sock.connect((sys.argv[1], 80))
    print(sock.getsockname()[0])
finally:
    sock.close()
PY
)"
echo "$MAC_HOST_IP"
```

## Build macOS SpiderNode

```bash
export MAC_BUILD_DIR="$RUN_DIR/build/macos"
export MAC_SPIDERNODE_PREFIX="$MAC_BUILD_DIR/spidernode-prefix"
export MAC_SPIDERNODE_LOCAL_CACHE="$MAC_BUILD_DIR/spidernode-local-cache"
export MAC_SPIDERNODE_GLOBAL_CACHE="$MAC_BUILD_DIR/spidernode-global-cache"

mkdir -p "$MAC_BUILD_DIR"

(
  cd "$SPIDER_ROOT/SpiderNode"
  zig build \
    --prefix "$MAC_SPIDERNODE_PREFIX" \
    --cache-dir "$MAC_SPIDERNODE_LOCAL_CACHE" \
    --global-cache-dir "$MAC_SPIDERNODE_GLOBAL_CACHE"
)
```

The binary you will use later is:

```bash
export MAC_NODE_BIN="$MAC_SPIDERNODE_PREFIX/bin/spiderweb-fs-node"
```

## Build Linux Spiderweb and SpiderNode in Orb

The Linux-side helper already knows how to do this in isolated prefixes and caches.

```bash
orbctl run --path --workdir "$SPIDER_ROOT" env \
  RUN_DIR_REL="$RUN_DIR_REL" \
  SPIDERWEB_HOST_IP="$ORB_IP" \
  SPIDERWEB_PORT="$SPIDERWEB_PORT" \
  LOCAL_WORKSPACE_NODE_PORT="$LOCAL_WORKSPACE_NODE_PORT" \
  REMOTE_NODE_NAME="demo-macos-review-node" \
  REMOTE_EXPORT_NAME="remote-smoke" \
  bash "$SPIDER_ROOT/e2e/run_linux_spiderweb_host.sh" build
```

## Prepare a Writable Remote Export Copy on macOS

Copy the relay fixture into a per-run writable folder.

```bash
export REMOTE_EXPORT_COPY="$RUN_DIR/state/macos-remote-export"

python3 - "$SPIDER_ROOT/e2e/fixtures/agent-relay" "$REMOTE_EXPORT_COPY" <<'PY'
from pathlib import Path
import shutil
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
if dst.exists():
    shutil.rmtree(dst)
shutil.copytree(src, dst)
PY
```

## Start Linux Spiderweb and the Linux Workspace Node

This helper starts:

- the Linux Spiderweb host
- the Linux workspace node exporting a writable workspace root
- writes control credentials to `artifacts/control_handoff.json`

```bash
orbctl run --path --workdir "$SPIDER_ROOT" env \
  RUN_DIR_REL="$RUN_DIR_REL" \
  SPIDERWEB_HOST_IP="$ORB_IP" \
  SPIDERWEB_PORT="$SPIDERWEB_PORT" \
  LOCAL_WORKSPACE_NODE_PORT="$LOCAL_WORKSPACE_NODE_PORT" \
  REMOTE_NODE_NAME="demo-macos-review-node" \
  REMOTE_EXPORT_NAME="remote-smoke" \
  bash "$SPIDER_ROOT/e2e/run_linux_spiderweb_host.sh" start_host_stack
```

Inspect the handoff file:

```bash
cat "$RUN_DIR/artifacts/control_handoff.json"
```

Capture the key values:

```bash
export CONTROL_URL="$(python3 - "$RUN_DIR/artifacts/control_handoff.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], "r", encoding="utf-8"))["control_url"])
PY
)"

export CONTROL_AUTH_TOKEN="$(python3 - "$RUN_DIR/artifacts/control_handoff.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], "r", encoding="utf-8"))["control_auth_token"])
PY
)"

export REMOTE_INVITE_TOKEN="$(python3 - "$RUN_DIR/artifacts/control_handoff.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], "r", encoding="utf-8"))["remote_invite_token"])
PY
)"
```

## Start the macOS Remote Node

This node exports the writable macOS relay folder to Spiderweb.

```bash
"$MAC_NODE_BIN" \
  --bind "$MAC_HOST_IP" \
  --port "$REMOTE_NODE_PORT" \
  --export "remote-smoke=$REMOTE_EXPORT_COPY:rw" \
  --control-url "$CONTROL_URL" \
  --control-auth-token "$CONTROL_AUTH_TOKEN" \
  --pair-mode invite \
  --invite-token "$REMOTE_INVITE_TOKEN" \
  --node-name "demo-macos-review-node" \
  --state-file "$RUN_DIR/state/macos-remote-node-state.json" \
  >"$RUN_DIR/logs/macos-remote-node.log" 2>&1 &

export MAC_REMOTE_NODE_PID=$!
echo "$MAC_REMOTE_NODE_PID" > "$RUN_DIR/state/macos-remote-node.pid"
```

## Prepare the Mounted Workspace on Linux

This helper waits for the remote node join, runs `workspace_up`, applies the `/remote` bind, mounts the namespace, and leaves the workspace mounted under Linux `/tmp/<run-name>/mountpoint`.

```bash
orbctl run --path --workdir "$SPIDER_ROOT" env \
  RUN_DIR_REL="$RUN_DIR_REL" \
  SPIDERWEB_HOST_IP="$ORB_IP" \
  SPIDERWEB_PORT="$SPIDERWEB_PORT" \
  LOCAL_WORKSPACE_NODE_PORT="$LOCAL_WORKSPACE_NODE_PORT" \
  REMOTE_NODE_NAME="demo-macos-review-node" \
  REMOTE_EXPORT_NAME="remote-smoke" \
  bash "$SPIDER_ROOT/e2e/run_linux_spiderweb_host.sh" finish_scenario
```

At this point:

- the Linux mounted workspace root is:

```bash
export LINUX_MOUNT_ROOT="/tmp/$(basename "$RUN_DIR")/mountpoint"
```

- the remote export should be visible inside the mounted workspace at:

```bash
echo "$LINUX_MOUNT_ROOT/remote"
```

You can inspect it directly:

```bash
orbctl run bash -lc "find $(printf '%q' "$LINUX_MOUNT_ROOT/remote") -maxdepth 2 -type f | sort"
```

## Run the Linux Worker Codex Step

This Codex run works inside the mounted workspace and writes:

- `remote/worker_report.md`
- `remote/worker_summary.json`

```bash
cat "$SPIDER_ROOT/e2e/prompts/agent-relay-linux-worker.txt" | \
orbctl run --path --workdir "$SPIDER_ROOT" bash -lc "
set -euo pipefail
cat | codex exec \
  --json \
  --skip-git-repo-check \
  --dangerously-bypass-approvals-and-sandbox \
  --ephemeral \
  --color never \
  --add-dir $(printf '%q' "$RUN_DIR/artifacts") \
  -C $(printf '%q' "$LINUX_MOUNT_ROOT") \
  -o $(printf '%q' "$RUN_DIR/artifacts/linux_worker_last_message.txt") \
  - \
  >$(printf '%q' "$RUN_DIR/logs/linux-worker-codex.jsonl") \
  2>$(printf '%q' "$RUN_DIR/logs/linux-worker-codex.stderr.log")
"
```

Confirm that the macOS-exported folder received the worker files:

```bash
find "$REMOTE_EXPORT_COPY" -maxdepth 1 -type f | sort
```

Review them:

```bash
sed -n '1,220p' "$REMOTE_EXPORT_COPY/worker_report.md"
sed -n '1,220p' "$REMOTE_EXPORT_COPY/worker_summary.json"
```

## Run the macOS Reviewer Codex Step

This Codex run works directly in the local macOS exported folder and writes:

- `review.md`
- `review_summary.json`

```bash
cat "$SPIDER_ROOT/e2e/prompts/agent-relay-macos-reviewer.txt" | \
codex exec \
  --json \
  --skip-git-repo-check \
  --dangerously-bypass-approvals-and-sandbox \
  --ephemeral \
  --color never \
  --add-dir "$RUN_DIR/artifacts" \
  -C "$REMOTE_EXPORT_COPY" \
  -o "$RUN_DIR/artifacts/macos_reviewer_last_message.txt" \
  - \
  >"$RUN_DIR/logs/macos-reviewer-codex.jsonl" \
  2>"$RUN_DIR/logs/macos-reviewer-codex.stderr.log"
```

Review the results:

```bash
sed -n '1,220p' "$REMOTE_EXPORT_COPY/review.md"
sed -n '1,220p' "$REMOTE_EXPORT_COPY/review_summary.json"
```

## Validate the Demo Outputs

```bash
python3 "$SPIDER_ROOT/e2e/validate_agent_relay.py" \
  --remote-root "$REMOTE_EXPORT_COPY" \
  --output "$RUN_DIR/artifacts/agent_relay_validation.json"
```

Read the validator result:

```bash
sed -n '1,240p' "$RUN_DIR/artifacts/agent_relay_validation.json"
```

You should see:

- worker outputs present
- review outputs present
- worker platform = `linux`
- reviewer platform = `macos`
- review verdict = `PASS`
- top-level `"ok": true`

## Useful Demo Artifacts

- handoff: [control_handoff.json](/Users/deanocalver/Documents/Projects/Spider/e2e/out/cross-platform-agent-relay-20260322-213154-27385/artifacts/control_handoff.json)
- workspace metadata: [workspace_result.json](/Users/deanocalver/Documents/Projects/Spider/e2e/out/cross-platform-agent-relay-20260322-213154-27385/artifacts/workspace_result.json)
- base mount check: [remote_smoke_result.json](/Users/deanocalver/Documents/Projects/Spider/e2e/out/cross-platform-agent-relay-20260322-213154-27385/artifacts/remote_smoke_result.json)
- final relay validation: [agent_relay_validation.json](/Users/deanocalver/Documents/Projects/Spider/e2e/out/cross-platform-agent-relay-20260322-213154-27385/artifacts/agent_relay_validation.json)

Those links point to the latest successful example run from development, but your live run will create its own fresh timestamped directory under:

```bash
/Users/deanocalver/Documents/Projects/Spider/e2e/out/
```

## Cleanup

Stop the macOS remote node:

```bash
if [[ -n "${MAC_REMOTE_NODE_PID:-}" ]]; then
  kill "$MAC_REMOTE_NODE_PID" || true
fi
```

Tell the Linux helper to unmount and stop Spiderweb plus the Linux workspace node:

```bash
orbctl run --path --workdir "$SPIDER_ROOT" env \
  RUN_DIR_REL="$RUN_DIR_REL" \
  SPIDERWEB_HOST_IP="$ORB_IP" \
  SPIDERWEB_PORT="$SPIDERWEB_PORT" \
  LOCAL_WORKSPACE_NODE_PORT="$LOCAL_WORKSPACE_NODE_PORT" \
  REMOTE_NODE_NAME="demo-macos-review-node" \
  REMOTE_EXPORT_NAME="remote-smoke" \
  bash "$SPIDER_ROOT/e2e/run_linux_spiderweb_host.sh" cleanup
```

## Optional One-Liner

If you just want the full automated version after the manual demo, run:

```bash
bash /Users/deanocalver/Documents/Projects/Spider/e2e/test-cross-platform-agent-relay.sh
```
