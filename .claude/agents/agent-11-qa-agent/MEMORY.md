# Agent 11: QAAgent — Memory

## Accumulated Knowledge
- 84/84 bugs fixed as of 2026-04-21
- flutter analyze: 0 errors, 0 warnings
- 52 SlotLab P5 win tier config test failures (known, not blocking)
- Integration tests fail on ExFAT macOS (infrastructure issue)
- Cargo clippy: clean (41 warnings resolved)

## Verified Correct (QA Audit 2026-03-30)
- EventRegistry single source of truth
- FaderCurve math (all edge cases)
- Pan semantics (L=-1.0, R=+1.0 correct)
- Biquad TDF-II + SIMD fallback
- GetIt DI (70+ providers, no circular deps)
- Casino-grade determinism (FNV-1a + SHA-256)
- All AnimationControllers in initState/dispose
