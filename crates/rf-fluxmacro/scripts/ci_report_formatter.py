#!/usr/bin/env python3
# ============================================================================
# FluxMacro CI Report Formatter — FM-52
# ============================================================================
# Generates PR-ready markdown comments from FluxMacro --ci JSON output.
# Usage: python3 ci_report_formatter.py --json-input <file> --output <file>
#        [--commit <sha>] [--pr-number <num>]
# ============================================================================

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description="FluxMacro CI Report Formatter")
    parser.add_argument(
        "--json-input",
        required=True,
        help="Path to FluxMacro --ci JSON output file (or /dev/stdin)",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Path to write the markdown report",
    )
    parser.add_argument("--commit", default="", help="Git commit SHA")
    parser.add_argument("--pr-number", default="", help="PR number")
    parser.add_argument(
        "--title",
        default="FluxMacro CI Report",
        help="Report title",
    )
    return parser.parse_args()


def load_json(path: str) -> dict:
    """Load JSON from file path, handling /dev/stdin and process substitution."""
    try:
        with open(path, "r") as f:
            text = f.read().strip()
        if not text:
            return {"error": "Empty input", "success": False}
        return json.loads(text)
    except json.JSONDecodeError as e:
        return {"error": f"Invalid JSON: {e}", "success": False}
    except FileNotFoundError:
        return {"error": f"File not found: {path}", "success": False}
    except Exception as e:
        return {"error": str(e), "success": False}


def format_status_badge(success: bool) -> str:
    if success:
        return "![PASS](https://img.shields.io/badge/FluxMacro-PASS-brightgreen)"
    return "![FAIL](https://img.shields.io/badge/FluxMacro-FAIL-red)"


def format_duration(ms: int) -> str:
    if ms < 1000:
        return f"{ms}ms"
    return f"{ms / 1000:.1f}s"


def format_hash(h: str) -> str:
    if len(h) > 12:
        return h[:12]
    return h


def build_qa_table(qa_results: list) -> str:
    if not qa_results:
        return "_No QA tests executed_\n"

    lines = [
        "| Test | Result | Duration | Details |",
        "|------|--------|----------|---------|",
    ]
    passed = 0
    failed = 0
    for r in qa_results:
        is_pass = r.get("passed", False)
        icon = "PASS" if is_pass else "FAIL"
        name = r.get("test_name", r.get("test", "unknown"))
        dur = format_duration(r.get("duration_ms", 0))
        details = r.get("details", "")
        lines.append(f"| `{name}` | {icon} | {dur} | {details} |")
        if is_pass:
            passed += 1
        else:
            failed += 1

    lines.append("")
    lines.append(f"**Total:** {passed} passed, {failed} failed out of {passed + failed}")
    return "\n".join(lines) + "\n"


def build_artifacts_list(artifacts) -> str:
    if not artifacts:
        return "_No artifacts generated_\n"

    # artifacts can be list of strings or dict keys
    if isinstance(artifacts, dict):
        items = list(artifacts.keys())
    elif isinstance(artifacts, list):
        items = artifacts
    else:
        return "_No artifacts generated_\n"

    if not items:
        return "_No artifacts generated_\n"

    lines = []
    for item in sorted(items):
        lines.append(f"- `{item}`")
    return "\n".join(lines) + "\n"


def build_warnings_section(warnings: list) -> str:
    if not warnings:
        return ""
    lines = ["\n### Warnings\n"]
    for w in warnings:
        lines.append(f"- {w}")
    return "\n".join(lines) + "\n"


def build_errors_section(errors: list) -> str:
    if not errors:
        return ""
    lines = ["\n### Errors\n"]
    for e in errors:
        lines.append(f"- {e}")
    return "\n".join(lines) + "\n"


def generate_report(data: dict, commit: str, pr_number: str, title: str) -> str:
    """Generate markdown report from FluxMacro --ci JSON output."""
    lines = []

    # Check for error case (no actual run data)
    if "error" in data and not data.get("success", False):
        lines.append(f"## {title}")
        lines.append("")
        lines.append(format_status_badge(False))
        lines.append("")
        lines.append(f"**Error:** {data['error']}")
        if commit:
            lines.append(f"\n**Commit:** `{commit[:8]}`")
        lines.append(f"\n---\n_Generated at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}_")
        return "\n".join(lines)

    success = data.get("success", False)
    game_id = data.get("game_id", "unknown")
    seed = data.get("seed", 0)
    run_hash = data.get("run_hash", "")
    duration_ms = data.get("duration_ms", 0)
    qa_passed = data.get("qa_passed", 0)
    qa_failed = data.get("qa_failed", 0)
    artifacts = data.get("artifacts", [])
    warnings = data.get("warnings", [])
    errors = data.get("errors", [])
    qa_results = data.get("results", [])  # From qa command

    # Header
    lines.append(f"## {title}")
    lines.append("")
    lines.append(format_status_badge(success))
    lines.append("")

    # Summary table
    lines.append("### Summary\n")
    lines.append("| Key | Value |")
    lines.append("|-----|-------|")
    lines.append(f"| **Game** | `{game_id}` |")
    lines.append(f"| **Status** | {'PASS' if success else 'FAIL'} |")
    lines.append(f"| **Duration** | {format_duration(duration_ms)} |")
    lines.append(f"| **Seed** | `{seed}` |")
    if run_hash:
        lines.append(f"| **Hash** | `{format_hash(run_hash)}` |")
    lines.append(f"| **QA** | {qa_passed}/{qa_passed + qa_failed} passed |")
    if commit:
        lines.append(f"| **Commit** | `{commit[:8]}` |")
    if pr_number:
        lines.append(f"| **PR** | #{pr_number} |")
    lines.append("")

    # QA Results
    if qa_results:
        lines.append("### QA Results\n")
        lines.append(build_qa_table(qa_results))

    # Artifacts
    if artifacts:
        lines.append("### Artifacts\n")
        lines.append(build_artifacts_list(artifacts))

    # Warnings
    lines.append(build_warnings_section(warnings))

    # Errors
    lines.append(build_errors_section(errors))

    # Footer
    lines.append("\n---")
    lines.append(f"_Generated by FluxMacro CI at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}_")

    return "\n".join(lines)


def main():
    args = parse_args()
    data = load_json(args.json_input)
    report = generate_report(data, args.commit, args.pr_number, args.title)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(report)

    # Also print to stdout for CI visibility
    print(report)

    # Exit with appropriate code
    if data.get("success", False):
        sys.exit(0)
    elif "error" in data:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()
