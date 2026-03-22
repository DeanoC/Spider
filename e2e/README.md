# Cross-Repo E2E

This directory holds lightweight end-to-end checks that span multiple Spider repos.

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
