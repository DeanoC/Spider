# Cross-Repo E2E

This directory holds lightweight end-to-end checks that span multiple Spider repos.

## macOS Computer and Browser Node Smoke

`test-macos-computer-browser-node.sh` exercises the first macOS-only node-hosted desktop automation lane:

- Spiderweb runs locally on macOS with the bundled local node enabled
- the local node publishes `computer-main` and `browser-main`
- those providers appear in `/.spiderweb/catalog/*` but stay absent from `/.spiderweb/venoms/*` until explicitly bound
- the smoke binds:
  - `/.spiderweb/venoms/computer`
  - `/.spiderweb/venoms/browser`
- it then proves one observe + act loop for:
  - a deterministic native AppKit fixture window
  - a deterministic local browser fixture page

### Run

```bash
bash /Users/deanocalver/Documents/Projects/Spider/e2e/test-macos-computer-browser-node.sh
```

Optional overrides:

```bash
COMPUTER_INCLUDE_SCREENSHOT=1 \
BROWSER_INCLUDE_SCREENSHOT=1 \
OUTPUT_DIR=/Users/deanocalver/Documents/Projects/Spider/e2e/out/manual-computer-browser \
bash /Users/deanocalver/Documents/Projects/Spider/e2e/test-macos-computer-browser-node.sh
```

Default timestamped run directories are now treated as transient and removed automatically after a successful run. Set `KEEP_OUTPUT=1` when you want to keep a generated run directory, or provide an explicit `OUTPUT_DIR` when you want to preserve artifacts in a known location.

### Prerequisites

- macOS
- `zig`, `swiftc`, `python3`, `jq`, `open`, and `osascript`
- Playwright installed; the smoke will provision Chromium into its isolated temp home before launch
- Accessibility permission for the staged local-node driver at `.../local-node/bin/spiderweb-computer-driver`

The local-node supervisor now stages permission-sensitive drivers into a stable path under the configured Spiderweb state directory. For this smoke, that path lives under the chosen `OUTPUT_DIR`, for example:

`/Users/deanocalver/Documents/Projects/Spider/e2e/out/manual-computer-browser/ltm/local-node/bin/spiderweb-computer-driver`

Screen capture is optional by default in this smoke because it is especially permission-sensitive on local machines. Set `COMPUTER_INCLUDE_SCREENSHOT=1`, `BROWSER_INCLUDE_SCREENSHOT=1`, and optionally `REQUIRE_SCREEN_CAPTURE=1` when you want the lane to enforce screenshot artifacts too.

### Output

Each run writes a timestamped artifact directory under:

`/Users/deanocalver/Documents/Projects/Spider/e2e/out/`

Successful runs clean up those auto-generated directories by default. Failed runs are preserved for debugging, and you can keep successful artifacts too with `KEEP_OUTPUT=1` or an explicit `OUTPUT_DIR`.

Important artifacts:

- `artifacts/providers.before-bind.json`
- `artifacts/packages.before-bind.json`
- `artifacts/bindings.after-bind.json`
- `artifacts/computer.observe.result.json`
- `artifacts/computer.observe.after-act.result.json`
- `artifacts/computer.last_observation.json`
- `artifacts/computer.fixture_state.json`
- `artifacts/browser.observe.result.json`
- `artifacts/browser.last_dom.before-act.json`
- `artifacts/browser.last_dom.after-act.json`
- `artifacts/summary.json`

For the computer venom, the primary end-to-end success oracle is the post-act observation payload, especially the observed `ui_tree` text field value. The fixture state file is kept as a diagnostic artifact, but it is not the authoritative assertion source for the lane.
## Cross-Platform Node Workspace Smoke

`test-cross-platform-node-workspace.sh` exercises a mixed-platform workspace:

- Spiderweb host runs on Linux inside Orb
- a local Linux workspace node provides the workspace root export
- a macOS SpiderNode joins as a remote node
- the remote node exports a fixture folder
- Spiderweb mounts that export into the workspace at `/remote`
- the smoke runner validates the bound remote folder through the mounted workspace

### Run

```bash
bash /Users/deanocalver/Documents/Projects/Spider/e2e/test-cross-platform-node-workspace.sh
```

Optional port overrides:

```bash
SPIDERWEB_PORT=28794 \
LOCAL_WORKSPACE_NODE_PORT=28941 \
REMOTE_NODE_PORT=28942 \
bash /Users/deanocalver/Documents/Projects/Spider/e2e/test-cross-platform-node-workspace.sh
```

### Output

Each run writes a timestamped artifact directory under:

`/Users/deanocalver/Documents/Projects/Spider/e2e/out/`

Successful runs clean up those auto-generated directories by default. Failed runs are preserved for debugging, and `KEEP_OUTPUT=1` keeps successful artifacts too.

Important artifacts:

- `artifacts/control_handoff.json`
- `artifacts/workspace_result.json`
- `artifacts/remote_smoke_result.json`

### Notes

- The parent repo output directory must stay inside the shared Spider checkout so Orb can see it.
- Linux-side build products and Zig caches are isolated per run.
- The current lane is intentionally small and deterministic; it is a smoke test, not a full regression suite.

## Cross-Platform Agent Relay Smoke

`test-cross-platform-agent-relay.sh` builds on the same mixed-platform setup, then runs two Codex steps:

- Linux Codex works inside the mounted workspace and writes results into the remote bound folder at `/remote`
- macOS Codex reviews those produced files directly in the exported remote folder

This proves the full relay:

- one Spiderweb host
- two nodes
- two filesystem surfaces
- one platform producing work through Spiderweb
- the other platform reviewing the resulting files

### Run

```bash
bash /Users/deanocalver/Documents/Projects/Spider/e2e/test-cross-platform-agent-relay.sh
```
