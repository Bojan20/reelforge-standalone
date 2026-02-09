# QA Fixtures

Test fixtures for FluxForge Studio QA pipeline.

## Files

| Fixture | Purpose | Used By |
|---------|---------|---------|
| `minimal-slotlab-project.json` | Minimal SlotLab project with 10 events, 7 symbols, 2 contexts | Manual QA Flow A (Project Lifecycle) |
| `minimal-gdd.json` | Minimal GDD for import wizard testing | Manual QA Flow A, Automated regression |

## Audio Placeholders

Fixtures use `__placeholder__/` paths for audio files. Replace with real audio paths when running manual QA, or use the `qa/audio/` directory if generated test tones are available.

## Usage

```bash
# Load fixture in automated tests
cargo test -p rf-slot-lab -- --test-data qa/fixtures/minimal-gdd.json

# Use in manual QA
./scripts/qa-manual-checklist.sh --flow=A
```
