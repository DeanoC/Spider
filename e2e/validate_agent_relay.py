#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--remote-root", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    remote_root = Path(args.remote_root).resolve()
    output_path = Path(args.output).resolve()

    worker_report = remote_root / "worker_report.md"
    worker_summary = remote_root / "worker_summary.json"
    review_md = remote_root / "review.md"
    review_summary = remote_root / "review_summary.json"

    checks: list[dict] = [
        {"check": "remote_root_exists", "ok": remote_root.is_dir(), "detail": str(remote_root)},
        {"check": "worker_report_exists", "ok": worker_report.is_file(), "detail": str(worker_report)},
        {"check": "worker_summary_exists", "ok": worker_summary.is_file(), "detail": str(worker_summary)},
        {"check": "review_md_exists", "ok": review_md.is_file(), "detail": str(review_md)},
        {"check": "review_summary_exists", "ok": review_summary.is_file(), "detail": str(review_summary)},
    ]

    payload = {"ok": False, "checks": checks}
    if not all(item["ok"] for item in checks):
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1

    worker_report_text = worker_report.read_text(encoding="utf-8")
    worker_summary_payload = load_json(worker_summary)
    review_text = review_md.read_text(encoding="utf-8")
    review_summary_payload = load_json(review_summary)

    checks.extend(
        [
            {"check": "worker_heading", "ok": worker_report_text.startswith("# Worker Report"), "detail": None},
            {"check": "worker_mentions_relay", "ok": "cross-platform relay" in worker_report_text, "detail": None},
            {"check": "worker_mentions_hello", "ok": "hello from the remote node fixture" in worker_report_text, "detail": None},
            {"check": "worker_mentions_nested", "ok": "remote smoke fixture nested check" in worker_report_text, "detail": None},
            {"check": "worker_summary_scenario", "ok": worker_summary_payload.get("scenario") == "agent-relay-v1", "detail": worker_summary_payload.get("scenario")},
            {"check": "worker_summary_platform", "ok": worker_summary_payload.get("worker_platform") == "linux", "detail": worker_summary_payload.get("worker_platform")},
            {"check": "worker_summary_status", "ok": worker_summary_payload.get("status") == "completed", "detail": worker_summary_payload.get("status")},
            {"check": "review_heading", "ok": review_text.startswith("# Review"), "detail": None},
            {"check": "review_mentions_pass", "ok": "PASS" in review_text, "detail": None},
            {"check": "review_mentions_worker_files", "ok": "worker_report.md" in review_text and "worker_summary.json" in review_text, "detail": None},
            {"check": "review_summary_scenario", "ok": review_summary_payload.get("scenario") == "agent-relay-v1", "detail": review_summary_payload.get("scenario")},
            {"check": "review_summary_platform", "ok": review_summary_payload.get("reviewer_platform") == "macos", "detail": review_summary_payload.get("reviewer_platform")},
            {"check": "review_summary_status", "ok": review_summary_payload.get("status") == "completed", "detail": review_summary_payload.get("status")},
            {"check": "review_summary_verdict", "ok": review_summary_payload.get("verdict") == "PASS", "detail": review_summary_payload.get("verdict")},
        ]
    )

    payload = {
        "ok": all(item["ok"] for item in checks),
        "checks": checks,
        "remote_root": str(remote_root),
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
