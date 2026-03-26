#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def extract_text_values(node: dict[str, Any] | None) -> list[str]:
    if not isinstance(node, dict):
        return []
    values: list[str] = []
    if node.get("role") == "text_field":
        value = node.get("value")
        if isinstance(value, str):
            values.append(value)
    for child in node.get("children") or []:
        if isinstance(child, dict):
            values.extend(extract_text_values(child))
    return values


def ensure(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def relative_workspace_path(value: str) -> Path:
    normalized = value
    if normalized.startswith("./"):
        normalized = normalized[2:]
    elif normalized.startswith("/"):
        normalized = normalized[1:]
    return Path(normalized)


def fixture_text_value(state: dict[str, Any]) -> str:
    for key in ("text_value", "last_text"):
        value = state.get(key)
        if isinstance(value, str):
            return value
    return ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace-root", required=True)
    parser.add_argument("--summary", required=True)
    parser.add_argument("--linux-fixture-state", required=True)
    parser.add_argument("--macos-fixture-state", required=True)
    parser.add_argument("--linux-computer-text", required=True)
    parser.add_argument("--macos-computer-text", required=True)
    parser.add_argument("--linux-browser-text", required=True)
    parser.add_argument("--macos-browser-text", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    workspace_root = Path(args.workspace_root)
    summary_path = Path(args.summary)
    linux_fixture_state_path = Path(args.linux_fixture_state)
    macos_fixture_state_path = Path(args.macos_fixture_state)
    output_path = Path(args.output)

    ensure(workspace_root.exists(), f"workspace root does not exist: {workspace_root}")
    ensure(summary_path.exists(), f"summary file does not exist: {summary_path}")
    ensure(linux_fixture_state_path.exists(), f"linux fixture state does not exist: {linux_fixture_state_path}")
    ensure(macos_fixture_state_path.exists(), f"macos fixture state does not exist: {macos_fixture_state_path}")

    summary = load_json(summary_path)
    ensure(summary.get("status") == "ok", "summary status is not ok")
    ensure(summary.get("targets_catalog_path") in {"./.spiderweb/catalog/targets.json", ".spiderweb/catalog/targets.json"}, "summary does not record targets catalog usage")

    selected_targets = summary.get("selected_targets") or {}
    ensure(isinstance(selected_targets, dict), "summary selected_targets is missing")

    linux_target = selected_targets.get("linux")
    macos_target = selected_targets.get("macos")
    ensure(isinstance(linux_target, dict), "summary missing linux target entry")
    ensure(isinstance(macos_target, dict), "summary missing macos target entry")

    execution_log = summary.get("execution_log") or []
    ensure(isinstance(execution_log, list) and len(execution_log) >= 8, "summary execution_log is missing or too short")
    ensure(any("linux" in str(item).lower() for item in execution_log), "execution_log does not include linux steps")
    ensure(any("macos" in str(item).lower() for item in execution_log), "execution_log does not include macos steps")

    def require_workspace_target_path(value: Any, label: str) -> str:
        ensure(isinstance(value, str), f"{label} is missing")
        ensure("/nodes/" not in value, f"{label} should not use raw node paths")
        ensure(".spiderweb/targets/" in value, f"{label} should use stable target paths")
        return value

    linux_computer_path = require_workspace_target_path(linux_target.get("computer_path"), "linux computer_path")
    linux_browser_path = require_workspace_target_path(linux_target.get("browser_path"), "linux browser_path")
    macos_computer_path = require_workspace_target_path(macos_target.get("computer_path"), "macos computer_path")
    macos_browser_path = require_workspace_target_path(macos_target.get("browser_path"), "macos browser_path")

    targets_catalog = load_json(workspace_root / ".spiderweb" / "catalog" / "targets.json")
    ensure(isinstance(targets_catalog, list), "targets catalog is not an array")

    def find_target(target_id: str) -> dict[str, Any]:
        for item in targets_catalog:
            if isinstance(item, dict) and item.get("target_id") == target_id:
                return item
        raise SystemExit(f"target {target_id!r} not found in targets catalog")

    linux_catalog = find_target(str(linux_target.get("target_id")))
    macos_catalog = find_target(str(macos_target.get("target_id")))
    ensure(((linux_catalog.get("platform") or {}).get("os")) == "linux", "linux target is not labeled linux in targets catalog")
    ensure(((macos_catalog.get("platform") or {}).get("os")) == "macos", "macos target is not labeled macos in targets catalog")

    linux_computer_observation = load_json(workspace_root / relative_workspace_path(linux_computer_path) / "artifacts" / "last_observation.json")
    macos_computer_observation = load_json(workspace_root / relative_workspace_path(macos_computer_path) / "artifacts" / "last_observation.json")
    linux_browser_dom = load_json(workspace_root / relative_workspace_path(linux_browser_path) / "artifacts" / "last_dom.json")
    macos_browser_dom = load_json(workspace_root / relative_workspace_path(macos_browser_path) / "artifacts" / "last_dom.json")
    linux_fixture_state = load_json(linux_fixture_state_path)
    macos_fixture_state = load_json(macos_fixture_state_path)

    linux_text_values = extract_text_values(linux_computer_observation.get("ui_tree"))
    macos_text_values = extract_text_values(macos_computer_observation.get("ui_tree"))
    ensure(args.linux_computer_text in linux_text_values, f"linux computer observation missing expected text {args.linux_computer_text!r}")
    ensure(args.macos_computer_text in macos_text_values, f"macos computer observation missing expected text {args.macos_computer_text!r}")
    ensure(fixture_text_value(linux_fixture_state) == args.linux_computer_text, "linux fixture state text does not match")
    ensure(fixture_text_value(macos_fixture_state) == args.macos_computer_text, "macos fixture state text does not match")

    linux_html = str(linux_browser_dom.get("html") or "")
    macos_html = str(macos_browser_dom.get("html") or "")
    ensure(f"clicked:{args.linux_browser_text}" in linux_html, "linux browser DOM missing clicked marker")
    ensure(f"clicked:{args.macos_browser_text}" in macos_html, "macos browser DOM missing clicked marker")

    result = {
        "ok": True,
        "summary_path": str(summary_path),
        "targets": {
            "linux": {
                "target_id": linux_target.get("target_id"),
                "computer_path": linux_computer_path,
                "browser_path": linux_browser_path,
                "fixture_state": linux_fixture_state,
                "text_values": linux_text_values,
            },
            "macos": {
                "target_id": macos_target.get("target_id"),
                "computer_path": macos_computer_path,
                "browser_path": macos_browser_path,
                "fixture_state": macos_fixture_state,
                "text_values": macos_text_values,
            },
        },
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
