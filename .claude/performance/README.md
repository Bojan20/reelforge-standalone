# FluxForge Studio Performance Documentation

**Folder:** `.claude/performance/`
**Purpose:** Comprehensive performance analysis, optimization guides, and code cleanup checklists

---

## 📄 Files

### 1. OPTIMIZATION_GUIDE.md
**Najdetaljnija analiza performansi kompletnog FluxForge Studio koda.**

**Sadržaj:**
- ✅ Analiza 132,621 linija koda (Rust + Flutter)
- ✅ Identifikovano 8 kritičnih performance bottleneck-a
- ✅ 15+ medium/low priority optimizacija
- ✅ Kompletni code snippets (before/after)
- ✅ Procenjeni gain za svaku optimizaciju
- ✅ 3-fazni implementacioni plan

**Key Findings:**
- Audio callback: **3-5% CPU redukcija** moguća
- DSP procesori: **20-40% brže** sa SIMD dispatch
- Flutter UI: **40-60% manje frame drops** sa throttling
- Binary: **10-20% manji** posle cleanup-a

**Top Priorities:**
1. 🔴 RwLock audio thread → AtomicU8 (30min, 2-3ms gain)
2. 🔴 EQ Vec alloc → Pre-allocated array (45min, 3-5% CPU)
3. 🟠 Meter rebuild storm → Throttling (45min, 30% FPS)
4. 🟠 Biquad AVX-512 dispatch (2h, 20-30% filter)

---

### 2. CODE_CLEANUP_CHECKLIST.md
**Detaljan plan za uklanjanje dead code i refactoring.**

**Sadržaj:**
- ✅ Dead code identifikacija (~2,500 lines)
- ✅ Duplicate logic mapa (~1,200 lines)
- ✅ Over-abstraction analiza (8 trait hierarchies)
- ✅ Mock code removal plan (~800 lines Flutter)
- ✅ 6-fazni execution plan sa verification

**Cleanup Scope:**
- 🗑️ Unused formats (MQA, TrueHD, DSD) → -18MB binary
- 🗑️ Old waveform renderers → -500 lines
- 🗑️ Mock engine code → -800 lines
- 🔄 Transport state pattern → Single canonical way
- 🔄 Color theme duplication → Merged
- 🎯 Processor traits → Direct impl (2-3% perf gain)

**Expected Results:**
- Lines of code: 132,621 → ~128,000 (-3.5%)
- Binary size: 2.3GB → 2.0-2.1GB (-8-13%)
- Compile time: 180s → 155-165s (-10-15%)

---

## 🚀 Quick Start

### Kako koristiti ove guide-ove:

**1. Pre implementacije bilo koje optimizacije:**
```bash
# Benchmark baseline
cargo bench > bench_before.log
cargo test --all > tests_before.log
ls -lh target/release/librf_bridge.dylib > size_before.txt
```

**2. Pročitaj relevantni guide:**
- Za performance: `OPTIMIZATION_GUIDE.md`
- Za cleanup: `CODE_CLEANUP_CHECKLIST.md`

**3. Implementiraj fix:**
- Koristi exact code snippets iz guide-a
- Testiraj posle svakog stepa
- Git commit pre i posle

**4. Verify rezultate:**
```bash
# Benchmark after
cargo bench > bench_after.log
cargo test --all > tests_after.log

# Compare
diff bench_before.log bench_after.log
diff tests_before.log tests_after.log

# Manual test
cd flutter_ui && flutter run -d macos --release
# Test: Audio playback, parameter changes, timeline scrubbing
```

---

## 📋 Implementation Order

### Faza 1: Kritične Popravke (Dan 1 — 2h)
**File:** `OPTIMIZATION_GUIDE.md` → Section "PRIORITET 1"

1. RwLock → AtomicU8 u transport (30min)
2. EQ Vec alloc fix (45min)
3. Meter provider throttling (45min)

**Expected:** 5-8% CPU redukcija, smooth UI

---

### Faza 2: SIMD Optimizacije (Dan 2-3 — 4h)
**File:** `OPTIMIZATION_GUIDE.md` → Section "PRIORITET 2"

4. Biquad AVX-512 dispatch (2h)
5. Dynamics envelope SIMD (1.5h)
6. Timeline vsync sync (1h — Flutter)

**Expected:** 20-30% brži DSP, professional feel

---

### Faza 3: Code Cleanup (Dan 4 — 4h)
**File:** `CODE_CLEANUP_CHECKLIST.md` → Phases 1-6

7. Dead code removal (30min)
8. Mock code cleanup (1h)
9. Deduplication (1h)
10. Over-abstraction fix (1.5h)

**Expected:** Cleaner codebase, faster compile, smaller binary

---

## 🔍 Tools & Commands

### Profiling
```bash
# CPU profiling
cargo flamegraph --release

# Memory profiling (macOS)
instruments -t "Allocations" target/release/fluxforge_ui

# Audio latency test
cargo test --release -- --nocapture audio_latency_test
```

### Benchmarking
```bash
# All DSP benchmarks
cargo bench --package rf-dsp

# Specific processor
cargo bench biquad_block
cargo bench eq_64band_process
cargo bench compressor_stereo
```

### Flutter Performance
```bash
# Profile mode with Skia tracing
cd flutter_ui
flutter run --profile --trace-skia

# DevTools timeline
flutter pub global activate devtools
flutter pub global run devtools
```

### Dead Code Detection
```bash
# Unused dependencies
cargo +nightly udeps

# Binary bloat analysis
cargo bloat --release --crates

# Find unused functions (Rust)
cargo +nightly rustc -- -Z print-type-sizes
```

---

## 📊 Expected Results Summary

### Pre Optimizacije
| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| Audio latency | 3-5ms | 1.5-2.5ms | cpal timing |
| DSP load | 25-30% | 15-20% | CPU profiler |
| UI frame rate | 45-55fps | 60fps solid | Flutter DevTools |
| Memory idle | 180-220MB | 150-180MB | Activity Monitor |
| Binary size | 2.3GB | 1.8-2.0GB | ls -lh |
| Compile time | 180s | 155-165s | cargo build --release |

### Posle Optimizacije (All Phases Complete)
**Audio:**
- ✅ Zero dropouts (atomic transport)
- ✅ 50% lower latency
- ✅ 30-40% CPU reduction

**UI:**
- ✅ Solid 60fps (vsync sync)
- ✅ Buttery smooth timeline
- ✅ Instant parameter response

**Code Quality:**
- ✅ Zero dead code
- ✅ Single source of truth (no duplication)
- ✅ Minimal abstraction overhead
- ✅ 15% faster compile

---

## ⚠️ Safety Rules

**Pre svake izmene:**
1. ✅ Git commit (`git add . && git commit -m "checkpoint"`)
2. ✅ Benchmark baseline (cargo bench)
3. ✅ Test suite pass (cargo test --all)
4. ✅ Manual app test (audio playback works)

**Posle svake izmene:**
1. ✅ Verify tests still pass
2. ✅ Benchmark regression check
3. ✅ Manual app test (verify no breakage)
4. ✅ Git commit sa opisom

**Ako nešto pukne:**
```bash
git reset --hard HEAD~1  # Revert to checkpoint
```

---

## 🎯 Success Criteria

**Optimizacija je uspešna ako:**
- ✅ Svi testovi prolaze (zero regressions)
- ✅ Performance gain vidljiv u benchmark-ima
- ✅ App se normalno ponaša (manual test)
- ✅ Code je čitljiviji posle izmene (ne kompleksniji)

**Optimizacija je neuspešna ako:**
- ❌ Test failures
- ❌ Performance regression (sporije od baseline)
- ❌ Audio dropouts ili UI glitches
- ❌ Code postao kompleksniji

---

## 📚 References

**Rust Performance Book:**
- https://nnethercote.github.io/perf-book/

**SIMD in Rust:**
- https://rust-lang.github.io/packed_simd/perf-guide/

**Audio Programming:**
- "Designing Audio Effect Plugins in C++" (Pirkle) — concepts apply to Rust
- "The Audio Programming Book" (Boulanger & Lazzarini)

**Flutter Performance:**
- https://docs.flutter.dev/perf/best-practices
- https://docs.flutter.dev/perf/rendering-performance

---

**Version:** 1.0
**Last Updated:** 2026-01-09
**Status:** Ready for implementation
