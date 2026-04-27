# CortexEye E2E Baseline

Visual regression detector for FluxForge Studio. Captures full-window snapshots of N key UI states via the CortexEye HTTP API, fingerprints them with perceptual hashes (`phash`, `dhash`), and compares against a stored baseline.

## Prereqs

- FluxForge Studio app running (process `FluxForge Studio`)
- CortexEye service on `:26200` (started with the app)
- Python 3 + Pillow + imagehash

```bash
pip3 install --user --break-system-packages Pillow imagehash
```

## Use

```bash
# Capture a fresh baseline (overwrites manifest)
tools/cortex_e2e/baseline.py record

# Diff current state against baseline
tools/cortex_e2e/baseline.py verify

# Show stored baseline
tools/cortex_e2e/baseline.py list

# Drop everything
tools/cortex_e2e/baseline.py clean
```

`verify` exit codes: `0` PASS, `1` regression, `3` CortexEye unreachable, `4` app not running, `5` no baseline yet.

## Threshold

Hamming distance over 64-bit perceptual hash (override via `CORTEX_E2E_THRESHOLD`):

| distance | meaning |
|----------|---------|
| `< 5`    | identical |
| `5–10`   | minor (cursor blink, AA jitter) — PASS |
| `> 10`   | regression — FAIL |

Default threshold is `10`. Cursor position, ticker animations, and meter pixel jitter all sit comfortably below it.

## Screens

Defined in `SCREENS` at the top of `baseline.py`. Each entry navigates via CortexHands keypresses, waits for the layout to settle, and snapshots the full window. Add screens by appending to that list; rerun `record` to refresh the manifest.
