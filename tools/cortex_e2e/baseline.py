#!/usr/bin/env python3
"""
CortexEye E2E Baseline — visual regression detector for FluxForge Studio.

Modes:
    record   capture snapshots of N key screens, store perceptual hashes
    verify   capture fresh snapshots, diff against stored baselines (Hamming)
    list     show stored baseline manifest
    clean    delete baselines

Requires:
    - CortexEye HTTP service running on :26200
    - FluxForge Studio app live (process running)
    - Python: PIL + imagehash

Hash threshold (Hamming distance over phash 8x8 = 64 bits):
    < 5    identical
    5-10   minor (anti-alias jitter, cursor blink) — PASS
    > 10   regression — FAIL

Usage:
    tools/cortex_e2e/baseline.py record
    tools/cortex_e2e/baseline.py verify
    tools/cortex_e2e/baseline.py list
"""

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

try:
    from PIL import Image
    import imagehash
except ImportError as e:
    sys.stderr.write(f"missing dep: {e}\n  pip3 install --user --break-system-packages Pillow imagehash\n")
    sys.exit(2)

import urllib.request
import urllib.parse

EYE_BASE = os.environ.get("CORTEX_EYE", "http://localhost:26200")
ROOT = Path(__file__).resolve().parent
BASELINE_DIR = ROOT / "baselines"
MANIFEST = BASELINE_DIR / "manifest.json"

# Hamming threshold — above this we report regression
THRESHOLD = int(os.environ.get("CORTEX_E2E_THRESHOLD", "10"))

# Screens to capture. Each entry:
#   key      stable identifier (also filename stem)
#   nav      list of HTTP calls to perform before snap (sets app state)
#   wait_ms  millis to wait after navigation, before snap
SCREENS = [
    {
        "key": "00_initial",
        "nav": [],
        "wait_ms": 500,
        "description": "App at launch / current state",
    },
    {
        "key": "01_daw_compose",
        "nav": [("POST", "/hands/key", {"key": "Meta+Shift+1"})],
        "wait_ms": 700,
        "description": "DAW Composition layout (Cmd+Shift+1)",
    },
    {
        "key": "02_daw_focus",
        "nav": [("POST", "/hands/key", {"key": "Meta+Shift+2"})],
        "wait_ms": 700,
        "description": "DAW Focus layout (Cmd+Shift+2)",
    },
    {
        "key": "03_daw_mixing",
        "nav": [("POST", "/hands/key", {"key": "Meta+Shift+3"})],
        "wait_ms": 700,
        "description": "DAW Mixing layout (Cmd+Shift+3)",
    },
    {
        "key": "04_helix_mini",
        "nav": [("POST", "/hands/key", {"key": "Meta+Shift+M"})],
        "wait_ms": 700,
        "description": "HELIX mini-mode toggle (Cmd+Shift+M)",
    },
    {
        "key": "05_helix_full",
        "nav": [("POST", "/hands/key", {"key": "Meta+Shift+M"})],
        "wait_ms": 700,
        "description": "HELIX expand back (Cmd+Shift+M again)",
    },
]


def http(method, path, body=None, *, raw=False, timeout=10):
    url = EYE_BASE + path
    data = None
    headers = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, method=method, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        payload = r.read()
        if raw:
            return r.status, payload
        try:
            return r.status, json.loads(payload)
        except json.JSONDecodeError:
            return r.status, payload.decode("utf-8", errors="replace")


def health_check():
    try:
        status, body = http("GET", "/health")
    except Exception as e:
        sys.stderr.write(f"CortexEye unreachable at {EYE_BASE}: {e}\n")
        sys.exit(3)
    if status != 200 or (isinstance(body, dict) and body.get("status") != "ok"):
        sys.stderr.write(f"CortexEye unhealthy: {body}\n")
        sys.exit(3)


def fluxforge_alive():
    """Verify FluxForge Studio process is running."""
    r = subprocess.run(
        ["pgrep", "-f", "FluxForge Studio"],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        sys.stderr.write("FluxForge Studio is not running.\n  Run BUILD first.\n")
        sys.exit(4)


def snap(out_path: Path) -> dict:
    status, png = http("GET", "/eye/snapshot?region=full_window", raw=True)
    if status != 200:
        raise RuntimeError(f"snapshot failed: HTTP {status}")
    out_path.write_bytes(png)
    img = Image.open(out_path)
    return {
        "path": str(out_path.relative_to(ROOT.parent.parent)),
        "size_bytes": len(png),
        "resolution": f"{img.width}x{img.height}",
        "phash": str(imagehash.phash(img)),
        "ahash": str(imagehash.average_hash(img)),
        "dhash": str(imagehash.dhash(img)),
    }


def navigate(actions):
    for method, path, body in actions:
        try:
            http(method, path, body)
        except Exception as e:
            sys.stderr.write(f"nav {method} {path} failed: {e}\n")


def cmd_record(args):
    health_check()
    fluxforge_alive()
    BASELINE_DIR.mkdir(parents=True, exist_ok=True)
    manifest = {
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "threshold": THRESHOLD,
        "screens": [],
    }
    for s in SCREENS:
        navigate(s["nav"])
        time.sleep(s["wait_ms"] / 1000.0)
        out = BASELINE_DIR / f"{s['key']}.png"
        meta = snap(out)
        meta["key"] = s["key"]
        meta["description"] = s["description"]
        manifest["screens"].append(meta)
        print(f"  [+] {s['key']}: {meta['phash']}  {meta['resolution']}")
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"baseline manifest: {MANIFEST}")
    print(f"  {len(manifest['screens'])} screen(s) recorded")


def cmd_verify(args):
    health_check()
    fluxforge_alive()
    if not MANIFEST.exists():
        sys.stderr.write("no baseline manifest — run `record` first\n")
        sys.exit(5)
    base = json.loads(MANIFEST.read_text())
    base_by_key = {s["key"]: s for s in base["screens"]}
    threshold = base.get("threshold", THRESHOLD)

    fresh_dir = BASELINE_DIR / "_fresh"
    fresh_dir.mkdir(exist_ok=True)
    report = {
        "verified_at": datetime.now(timezone.utc).isoformat(),
        "threshold": threshold,
        "baseline_recorded_at": base["recorded_at"],
        "results": [],
        "regressions": [],
    }
    for s in SCREENS:
        if s["key"] not in base_by_key:
            print(f"  [!] {s['key']}: not in baseline — record again")
            continue
        navigate(s["nav"])
        time.sleep(s["wait_ms"] / 1000.0)
        out = fresh_dir / f"{s['key']}.png"
        meta = snap(out)
        bm = base_by_key[s["key"]]
        ph_dist = int(imagehash.hex_to_hash(meta["phash"]) - imagehash.hex_to_hash(bm["phash"]))
        dh_dist = int(imagehash.hex_to_hash(meta["dhash"]) - imagehash.hex_to_hash(bm["dhash"]))
        worst = max(ph_dist, dh_dist)
        verdict = "PASS" if worst <= threshold else "FAIL"
        result = {
            "key": s["key"],
            "phash_distance": ph_dist,
            "dhash_distance": dh_dist,
            "worst": worst,
            "verdict": verdict,
            "fresh_phash": meta["phash"],
            "baseline_phash": bm["phash"],
        }
        report["results"].append(result)
        print(f"  [{verdict}] {s['key']:18s}  phash={ph_dist:2d}  dhash={dh_dist:2d}")
        if verdict == "FAIL":
            report["regressions"].append(s["key"])

    out_report = BASELINE_DIR / f"verify_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    out_report.write_text(json.dumps(report, indent=2) + "\n")
    print(f"\nreport: {out_report}")
    if report["regressions"]:
        print(f"FAIL: {len(report['regressions'])} regression(s): {report['regressions']}")
        sys.exit(1)
    print("PASS — no visual regressions")


def cmd_list(args):
    if not MANIFEST.exists():
        print("(no baseline)")
        return
    base = json.loads(MANIFEST.read_text())
    print(f"recorded_at: {base['recorded_at']}")
    print(f"threshold:   {base['threshold']}")
    print()
    for s in base["screens"]:
        print(f"  {s['key']:18s} {s['phash']}  {s['resolution']}  {s.get('description','')}")


def cmd_clean(args):
    if not BASELINE_DIR.exists():
        return
    for f in BASELINE_DIR.iterdir():
        if f.is_file():
            f.unlink()
        elif f.is_dir():
            for ff in f.iterdir():
                ff.unlink()
            f.rmdir()
    print(f"cleaned {BASELINE_DIR}")


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("record")
    sub.add_parser("verify")
    sub.add_parser("list")
    sub.add_parser("clean")
    args = p.parse_args()
    {"record": cmd_record, "verify": cmd_verify, "list": cmd_list, "clean": cmd_clean}[args.cmd](args)


if __name__ == "__main__":
    main()
