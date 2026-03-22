#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import time
from pathlib import Path


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(content)
        handle.flush()
        os.fsync(handle.fileno())

    for _ in range(100):
        written = path.read_text(encoding="utf-8")
        if written == content:
            return
        time.sleep(0.1)

    raise RuntimeError(f"failed to persist expected contents to {path}")


def run_worker(root: Path, worker_platform: str, bind_path: str) -> str:
    manifest = json.loads(read_text(root / "manifest.json"))
    task_brief = read_text(root / "task_brief.md")
    reference_notes = read_text(root / "reference_notes.txt")
    hello = read_text(root / "hello.txt").strip()
    nested = read_text(root / "nested" / "check.txt").strip()

    report = """# Worker Report

## Summary
This cross-platform relay smoke confirms that the remote export is visible through Spiderweb and can be updated from the worker side.

## Key Facts
- Scenario: cross-platform relay
- Manifest scenario: {scenario}
- Greeting: {hello}
- Nested check: {nested}
- Notes: {notes}

## Proposed Follow-up
- Keep the relay lane in CI so remote export writes stay stable across platforms.
""".format(
        scenario=manifest.get("scenario", "unknown"),
        hello=hello,
        nested=nested,
        notes=reference_notes.strip(),
    )

    summary = {
        "scenario": "agent-relay-v1",
        "worker_platform": worker_platform,
        "status": "completed",
        "reviewed_inputs": [
            "manifest.json",
            "task_brief.md",
            "reference_notes.txt",
            "hello.txt",
            "nested/check.txt",
        ],
        "output_files": ["worker_report.md"],
        "remote_bind_path": bind_path,
        "task_excerpt": task_brief.splitlines()[0],
    }

    write_text(root / "worker_report.md", report)
    write_text(root / "worker_summary.json", json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return "worker relay outputs written"


def run_reviewer(root: Path, reviewer_platform: str) -> str:
    task_brief = read_text(root / "task_brief.md")
    worker_report = read_text(root / "worker_report.md")
    worker_summary = json.loads(read_text(root / "worker_summary.json"))

    verdict = "PASS"
    gaps: list[str] = []
    if not worker_report.startswith("# Worker Report"):
        verdict = "FAIL"
        gaps.append("worker_report.md is missing the expected heading")
    if worker_summary.get("status") != "completed":
        verdict = "FAIL"
        gaps.append("worker_summary.json does not report completed status")

    gaps_block = "\n".join(f"- {item}" for item in gaps) if gaps else "- None"

    review = """# Review

## Verdict
{verdict}

## What Worked
- worker_report.md exists and summarizes the relay fixture.
- worker_summary.json exists and records the worker completion details.
- The task brief remained available to the reviewer side.

## Gaps
{gaps}

## Recommended Next Step
- Keep the Windows reviewer lane exercising the same remote export contract as the macOS reviewer lane.
""".format(
        verdict=verdict,
        gaps=gaps_block,
    )

    summary = {
        "scenario": "agent-relay-v1",
        "reviewer_platform": reviewer_platform,
        "status": "completed",
        "verdict": verdict,
        "reviewed_files": ["task_brief.md", "worker_report.md", "worker_summary.json"],
        "task_excerpt": task_brief.splitlines()[0],
    }

    write_text(root / "review.md", review)
    write_text(root / "review_summary.json", json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return f"review completed with verdict {verdict}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("worker", "reviewer"), required=True)
    parser.add_argument("--root", required=True)
    parser.add_argument("--worker-platform", default="linux")
    parser.add_argument("--reviewer-platform", default="macos")
    parser.add_argument("--remote-bind-path", default="/remote")
    parser.add_argument("--output-last-message")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if args.mode == "worker":
        message = run_worker(root, args.worker_platform, args.remote_bind_path)
    else:
        message = run_reviewer(root, args.reviewer_platform)

    if args.output_last_message:
        write_text(Path(args.output_last_message), message + "\n")

    print(message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
