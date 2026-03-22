#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def resolve_output(workspace_root: Path, requested: str) -> Path:
    output_path = Path(requested)
    if output_path.is_absolute():
        return output_path
    return workspace_root / output_path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace-root", required=True)
    parser.add_argument("--remote-root", required=True)
    parser.add_argument("--output", default="remote_smoke_result.json")
    args = parser.parse_args()

    workspace_root = Path(args.workspace_root).resolve()
    remote_root = Path(args.remote_root).resolve()
    output_path = resolve_output(workspace_root, args.output)

    manifest_path = remote_root / "manifest.json"
    hello_path = remote_root / "hello.txt"
    nested_path = remote_root / "nested" / "check.txt"

    checks: list[dict] = [
        {
            "check": "workspace_root_exists",
            "ok": workspace_root.is_dir(),
            "detail": str(workspace_root),
        },
        {
            "check": "remote_root_exists",
            "ok": remote_root.is_dir(),
            "detail": str(remote_root),
        },
        {
            "check": "manifest_exists",
            "ok": manifest_path.is_file(),
            "detail": str(manifest_path),
        },
        {
            "check": "hello_exists",
            "ok": hello_path.is_file(),
            "detail": str(hello_path),
        },
        {
            "check": "nested_exists",
            "ok": nested_path.is_file(),
            "detail": str(nested_path),
        },
    ]

    payload = {
        "ok": False,
        "checks": checks,
    }

    if not all(item["ok"] for item in checks):
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1

    manifest = load_json(manifest_path)
    hello_text = hello_path.read_text(encoding="utf-8").strip()
    nested_text = nested_path.read_text(encoding="utf-8").strip()

    checks.extend(
        [
            {
                "check": "manifest_scenario",
                "ok": manifest.get("scenario") == "remote-smoke-v1",
                "detail": manifest.get("scenario"),
            },
            {
                "check": "manifest_required_files",
                "ok": manifest.get("required_files") == ["hello.txt", "nested/check.txt"],
                "detail": manifest.get("required_files"),
            },
            {
                "check": "hello_contents",
                "ok": hello_text == "hello from the remote node fixture",
                "detail": hello_text,
            },
            {
                "check": "nested_contents",
                "ok": nested_text == "remote smoke fixture nested check",
                "detail": nested_text,
            },
        ]
    )

    relative_remote = None
    try:
        relative_remote = remote_root.relative_to(workspace_root)
    except ValueError:
        relative_remote = None

    checks.append(
        {
            "check": "remote_bound_inside_workspace",
            "ok": relative_remote is not None and str(relative_remote) == "remote",
            "detail": None if relative_remote is None else str(relative_remote),
        }
    )

    payload = {
        "ok": all(item["ok"] for item in checks),
        "checks": checks,
        "workspace_root": str(workspace_root),
        "remote_root": str(remote_root),
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
