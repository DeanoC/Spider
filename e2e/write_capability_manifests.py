#!/usr/bin/env python3

import argparse
import json
from pathlib import Path
from typing import Optional


def build_manifest(
    *,
    platform: str,
    package_id: str,
    venom_id: str,
    kind: str,
    executable_path: str,
    browser_state_path: Optional[str] = None,
    browser_profile_dir: Optional[str] = None,
    browser_env: Optional[dict] = None,
) -> dict:
    if kind == "computer":
        categories = ["desktop", "automation", platform]
        requirements = {
            "host_capabilities": (
                ["linux_atspi", "x11_display"]
                if platform == "linux"
                else ["macos_accessibility", "screen_capture"]
            )
        }
        capabilities = {
            "invoke": True,
            "discoverable": True,
            "observe": True,
            "act": True,
            "operations": ["observe", "act"],
            "device": "desktop",
        }
        schema = {
            "model": "computer-observe-act-v1",
            "control": {"invoke": "control/invoke.json"},
            "result": "result.json",
            "status": "status.json",
            "health": "health.json",
            "artifacts": {
                "observation": "artifacts/last_observation.json",
                "screenshot": "artifacts/last_screenshot.png",
            },
            "ops": {
                "observe": {"arguments": {"include_screenshot": "bool (optional)"}},
                "act": {
                    "arguments": {
                        "action": "focus_window|activate|primary_tap|text_input|key_combo",
                        "app_name": "string (required for activate/focus_window)",
                        "window_title": "string (required for focus_window)",
                        "button_title": "string (required for primary_tap)",
                        "text": "string (required for text_input)",
                        "key": "string (required for key_combo)",
                        "modifiers": "string[] (optional for key_combo)",
                    }
                },
            },
        }
        invoke_template = {"op": "observe", "arguments": {"include_screenshot": True}}
        help_md = (
            "Linux desktop automation driver.\n"
            "Write JSON payloads to control/invoke.json with op observe or act.\n"
            "Observation artifacts are refreshed under artifacts/.\n"
            if platform == "linux"
            else "macOS desktop automation driver.\n"
            "Write JSON payloads to control/invoke.json with op observe or act.\n"
            "Observation artifacts are refreshed under artifacts/.\n"
        )
    elif kind == "browser":
        categories = ["browser", "automation", platform]
        requirements = {
            "host_capabilities": (
                ["managed_browser", "x11_display"]
                if platform == "linux"
                else ["managed_browser"]
            )
        }
        capabilities = {
            "invoke": True,
            "discoverable": True,
            "observe": True,
            "act": True,
            "operations": ["observe", "act"],
            "device": "browser",
        }
        schema = {
            "model": "browser-observe-act-v1",
            "control": {"invoke": "control/invoke.json"},
            "result": "result.json",
            "status": "status.json",
            "health": "health.json",
            "artifacts": {
                "observation": "artifacts/last_observation.json",
                "screenshot": "artifacts/last_screenshot.png",
                "dom": "artifacts/last_dom.json",
            },
            "ops": {
                "observe": {
                    "arguments": {
                        "include_dom": "bool (optional)",
                        "include_screenshot": "bool (optional)",
                    }
                },
                "act": {
                    "arguments": {
                        "action": "navigate|activate_tab|click|text_input|key_combo",
                        "url": "string (required for navigate)",
                        "tab_index": "number (required for activate_tab)",
                        "selector": "string (required for click/text_input)",
                        "text": "string (required for text_input)",
                        "key": "string (required for key_combo)",
                        "modifiers": "string[] (optional for key_combo)",
                    }
                },
            },
        }
        invoke_template = {
            "op": "observe",
            "arguments": {"include_dom": True, "include_screenshot": True},
        }
        help_md = (
            "Linux browser automation driver.\n"
            "Write JSON payloads to control/invoke.json with op observe or act.\n"
            "Observation artifacts are refreshed under artifacts/.\n"
            if platform == "linux"
            else "macOS browser automation driver.\n"
            "Write JSON payloads to control/invoke.json with op observe or act.\n"
            "Observation artifacts are refreshed under artifacts/.\n"
        )
    else:
        raise ValueError(f"unsupported kind: {kind}")

    runtime = {
        "type": "native_proc",
        "abi": "namespace-driver-v1",
        "executable_path": executable_path,
        "timeout_ms": 60000,
    }
    if kind == "browser" and browser_state_path and browser_profile_dir:
        runtime_env = {
            "SPIDERWEB_BROWSER_STATE_PATH": browser_state_path,
            "SPIDERWEB_BROWSER_PROFILE_DIR": browser_profile_dir,
        }
        if browser_env:
            runtime_env.update(browser_env)
        runtime["env"] = runtime_env

    return {
        "venom_id": venom_id,
        "package_id": package_id,
        "kind": kind,
        "version": "1",
        "enabled": True,
        "state": "online",
        "categories": categories,
        "host_roles": ["node"],
        "binding_scopes": ["workspace"],
        "runtime_kind": "native",
        "requirements": requirements,
        "endpoints": [f"/nodes/{{node_id}}/venoms/{venom_id}"],
        "mounts": [
            {
                "mount_id": venom_id,
                "mount_path": f"/nodes/{{node_id}}/venoms/{venom_id}",
                "state": "online",
            }
        ],
        "capabilities": capabilities,
        "ops": {
            "model": "namespace",
            "invoke": "control/invoke.json",
            "paths": {"invoke": "control/invoke.json"},
        },
        "runtime": runtime,
        "permissions": {
            "default": "deny-by-default",
            "allow_roles": ["admin", "user"],
            "scope": "workspace",
            "requires_user_consent": True,
            "platform": platform,
        },
        "schema": schema,
        "invoke_template": invoke_template,
        "help_md": help_md,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", required=True, choices=("linux", "macos"))
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--computer-driver", required=True)
    parser.add_argument("--browser-driver", required=True)
    parser.add_argument("--browser-state-path", required=True)
    parser.add_argument("--browser-profile-dir", required=True)
    parser.add_argument("--browser-env", action="append", default=[])
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    browser_env = {}
    for entry in args.browser_env:
        if "=" not in entry:
            raise SystemExit(f"invalid --browser-env entry: {entry!r}")
        key, value = entry.split("=", 1)
        if not key:
            raise SystemExit(f"invalid --browser-env entry: {entry!r}")
        browser_env[key] = value

    computer_manifest = build_manifest(
        platform=args.platform,
        package_id="computer",
        venom_id="computer-main",
        kind="computer",
        executable_path=args.computer_driver,
    )
    browser_manifest = build_manifest(
        platform=args.platform,
        package_id="browser",
        venom_id="browser-main",
        kind="browser",
        executable_path=args.browser_driver,
        browser_state_path=args.browser_state_path,
        browser_profile_dir=args.browser_profile_dir,
        browser_env=browser_env,
    )

    (output_dir / "computer.json").write_text(
        json.dumps(computer_manifest, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
    )
    (output_dir / "browser.json").write_text(
        json.dumps(browser_manifest, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
