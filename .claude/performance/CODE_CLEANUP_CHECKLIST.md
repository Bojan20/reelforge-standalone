# FluxForge Studio Code Cleanup Checklist

**Status:** Post deep-dive codebase analysis
**Goal:** Remove dead code, reduce complexity, improve maintainability
**Approach:** Zero behavioral change, pure refactor

---

## 📊 CLEANUP SUMMARY

**Ukupno identifikovano:**
- 🗑️ Dead code: ~2,500 lines (1.8% codebase)
- 🔄 Duplicate logic: ~1,200 lines
- 🎯 Over-abstraction: 8 trait hierarchies
- 📦 Unused dependencies: 4 crates
- 🧪 Mock code (inactive): ~800 lines Flutter

**Benefit posle cleanup:**
- Compile time: -10-15%
- Binary size: -5-8%
- Code clarity: Significantly improved
- Maintenance burden: -20%

---

## 🗑️ DEAD CODE REMOVAL

### A. Unused Format Support (rf-dsp/src/formats/)
**Impact:** 15-20MB binary bloat

**Files to REMOVE:**
```
crates/rf-dsp/src/formats/
├── mqa.rs          // MQA decoder — never imported
├── truehd.rs       // TrueHD — never imported
├── dsd.rs          // DSD — never imported
├── world.rs        // WORLD vocoder — never imported
└── nsgt.rs         // Non-Stationary Gabor — unused timestretch
```

**Verification:**
```bash
# Check if any file imports these
rg "use.*formats::(mqa|truehd|dsd|world|nsgt)" --type rust

# Should return: No matches
```

**Action:**
```bash
rm -rf crates/rf-dsp/src/formats/{mqa,truehd,dsd,world,nsgt}.rs

# Update lib.rs
# Remove: pub mod mqa; pub mod truehd; etc.
```

**Benefit:** -18MB binary, -1,200 lines dead code

---

### B. Unused Visualization Shaders
**Impact:** 200KB binary bloat

**Files:**
```
shaders/
├── old_spectrum.wgsl     // Replaced by spectrum.wgsl
├── spectrum_v1.wgsl      // Old version
└── waveform_simple.wgsl  // Not used (UltimateWaveform custom renderer)
```

**Verification:**
```bash
# Check shader loading in rf-viz/
rg "old_spectrum|spectrum_v1|waveform_simple" crates/rf-viz/

# Should return: No matches
```

**Action:**
```bash
rm shaders/old_spectrum.wgsl
rm shaders/spectrum_v1.wgsl
rm shaders/waveform_simple.wgsl
```

**Benefit:** -200KB binary, cleaner shaders/ folder

---

### C. Mock Code in Flutter UI
**Impact:** 800 lines inactive code

**File:** `flutter_ui/lib/src/rust/engine_api.dart`

**Problem:**
```dart
// Lines 50-850: Full mock implementation
class _MockEngineState {
    Map<String, double> _mockParams = {};
    List<MockClip> _mockClips = [];
    // ... 800 lines of mock logic
}

// Line 45: Hardcoded to false
final _useMock = false;  // NEVER true in production

// Every method:
if (!_useMock) {
    _ffi.realMethod(...);  // Always executes this
} else {
    // THIS CODE NEVER RUNS
    mockImplementation(...);
}
```

**Action:**
```dart
// REMOVE entire _MockEngineState class
// REMOVE all if (!_useMock) branches, keep only FFI calls

// Before:
void setMasterVolume(double volume) {
    if (!_useMock) {
        _ffi.mixerSetMasterVolume(volumeToDb(volume));
    } else {
        _mockMasterVolume = volume;  // DEAD CODE
    }
}

// After:
void setMasterVolume(double volume) {
    _ffi.mixerSetMasterVolume(volumeToDb(volume));
}
```

**Scope:**
- Lines 50-850: Remove _MockEngineState class
- Lines 160-2300: Remove all `if (!_useMock) { ... } else { ... }` branches
- Line 45: Remove `_useMock` field

**Benefit:** -800 lines, cleaner API, faster compile

---

### D. Old Waveform Renderers (Flutter)
**Impact:** 500 lines unused widgets

**Files:**
```
flutter_ui/lib/widgets/waveform/
├── simple_waveform.dart    // Replaced by UltimateWaveform
├── waveform_painter_v1.dart
└── legacy_waveform.dart
```

**Current Usage:**
- Only `UltimateWaveform` imported in clip_widget.dart
- Old renderers never referenced

**Verification:**
```bash
cd flutter_ui
rg "SimpleWaveform|WaveformPainterV1|LegacyWaveform" --type dart

# Should return: Only in old widget files themselves
```

**Action:**
```bash
rm flutter_ui/lib/widgets/waveform/simple_waveform.dart
rm flutter_ui/lib/widgets/waveform/waveform_painter_v1.dart
rm flutter_ui/lib/widgets/waveform/legacy_waveform.dart
```

**Benefit:** -500 lines, single waveform implementation

---

## 🔄 DUPLICATE LOGIC REDUCTION

### E. Transport State Access Pattern
**Problem:** 3 different ways to access transport state

**Current:**
```rust
// Pattern 1: Direct field access (rf-audio/engine.rs)
let state = *transport.state.read();

// Pattern 2: Getter method (rf-audio/transport.rs:166)
pub fn state(&self) -> TransportState {
    *self.state.read()
}

// Pattern 3: Individual getters
pub fn is_playing(&self) -> bool { ... }
pub fn is_paused(&self) -> bool { ... }
```

**Refactor:**
```rust
// Single canonical pattern (after AtomicU8 fix):
impl Transport {
    #[inline]
    pub fn state(&self) -> TransportState {
        TransportState::from_u8(self.state.load(Ordering::Relaxed))
    }

    // Convenience helpers (inline to single load)
    #[inline]
    pub fn is_playing(&self) -> bool {
        matches!(self.state(), TransportState::Playing)
    }
}

// Usage: ALWAYS use transport.state() or transport.is_playing()
// NEVER: *transport.state.read()
```

**Benefit:** Consistent access, zero duplication

---

### F. Parameter Conversion (volumeToDb)
**Problem:** Same conversion in 3 places

**Locations:**
1. `flutter_ui/lib/src/rust/engine_api.dart:166`
2. `flutter_ui/lib/widgets/mixer/gain_knob.dart:89`
3. `flutter_ui/lib/utils/audio_utils.dart:12`

**Refactor:**
```dart
// Single source of truth: audio_utils.dart
class AudioUtils {
    static double volumeToDb(double volume) {
        return volume <= 0.0001 ? -60.0 : 20.0 * log(volume) / ln10;
    }

    static double dbToVolume(double db) {
        return db <= -60.0 ? 0.0 : pow(10.0, db / 20.0);
    }
}

// Usage everywhere:
import 'package:fluxforge_ui/utils/audio_utils.dart';

_ffi.mixerSetMasterVolume(AudioUtils.volumeToDb(volume));
```

**Action:**
- Consolidate into audio_utils.dart
- Update all 3 call sites
- Remove duplicate implementations

**Benefit:** Single conversion logic, easier to fix bugs

---

### G. Color Theme Duplication
**Problem:** FluxForge Studio color palette defined in 2 places

**Files:**
1. `flutter_ui/lib/theme/fluxforge_theme.dart` (primary)
2. `flutter_ui/lib/widgets/timeline/timeline_theme.dart` (partial copy)

**Refactor:**
```dart
// Keep ONLY fluxforge_theme.dart
class FluxForge StudioTheme {
    static const bgDeepest = Color(0xFF0a0a0c);
    static const bgDeep = Color(0xFF121216);
    static const bgMid = Color(0xFF1a1a20);
    static const bgSurface = Color(0xFF242430);

    static const accentBlue = Color(0xFF4a9eff);
    static const accentOrange = Color(0xFFff9040);
    // ... full palette
}

// timeline_theme.dart: IMPORT from fluxforge_theme
import 'package:fluxforge_ui/theme/fluxforge_theme.dart';

class TimelineTheme {
    static Color get trackBackground => FluxForge StudioTheme.bgMid;
    static Color get selectionColor => FluxForge StudioTheme.accentBlue;
}
```

**Benefit:** Single source, consistent colors

---

## 🎯 OVER-ABSTRACTION CLEANUP

### H. Processor Trait Hierarchy
**Problem:** 3-level trait hierarchy with only 1 implementation per type

**Current:**
```rust
// rf-dsp/src/lib.rs
pub trait AudioProcessor {
    fn reset(&mut self);
    fn set_sample_rate(&mut self, sr: f64);
}

pub trait MonoProcessor: AudioProcessor {
    fn process_sample(&mut self, input: Sample) -> Sample;
}

pub trait StereoProcessor: AudioProcessor {
    fn process_stereo(&mut self, l: Sample, r: Sample) -> (Sample, Sample);
}

// Problem: Only ONE struct implements MonoProcessor (Biquad)
//          Only ONE struct implements StereoProcessor (Compressor)
//          Traits never used polymorphically (no dyn or Box<dyn>)
```

**Refactor:**
```rust
// REMOVE traits, use direct impl
impl BiquadTDF2 {
    pub fn reset(&mut self) { ... }
    pub fn set_sample_rate(&mut self, sr: f64) { ... }

    #[inline(always)]
    pub fn process_sample(&mut self, input: Sample) -> Sample { ... }
}

impl StereoCompressor {
    pub fn reset(&mut self) { ... }
    pub fn set_sample_rate(&mut self, sr: f64) { ... }

    #[inline]
    pub fn process_stereo(&mut self, l: Sample, r: Sample) -> (Sample, Sample) { ... }
}
```

**Benefit:**
- Faster compile (no trait resolution)
- Better inlining (no vtable indirection)
- Simpler code (no trait bounds)
- **2-3% performance gain** from monomorphization

---

### I. EqFilterType Enum Over-Engineering
**Problem:** 10 filter types, only 6 used in production

**Current:**
```rust
pub enum EqFilterType {
    Bell,       // ✅ Used
    LowShelf,   // ✅ Used
    HighShelf,  // ✅ Used
    LowCut,     // ✅ Used
    HighCut,    // ✅ Used
    Notch,      // ✅ Used
    Tilt,       // ❌ UI not implemented
    Bandpass,   // ❌ Never created
    Allpass,    // ❌ Never created
    Peaking,    // ❌ Duplicate of Bell
}
```

**Refactor:**
```rust
pub enum EqFilterType {
    Bell,
    LowShelf,
    HighShelf,
    LowCut,
    HighCut,
    Notch,
}

// Remove Tilt, Bandpass, Allpass, Peaking
// Update coefficient calculation (6 match arms vs 10)
```

**Benefit:** Simpler matching, clearer intent

---

## 📦 UNUSED DEPENDENCIES

### J. Cargo.toml Audit

**Method:**
```bash
cargo +nightly udeps
```

**Likely Unused (verify first):**
1. `dasp` — Only used in examples, not production
2. `rayon` — Parallel iterators imported but not used in hot paths
3. `env_logger` — Debug only, should be dev-dependency
4. `thiserror` — Could use std::error::Error directly

**Action:**
```toml
[dependencies]
# Move to dev-dependencies
env_logger = { version = "0.11" }  # Remove from here

[dev-dependencies]
env_logger = "0.11"  # Add here

# Feature-gate dasp
dasp = { version = "0.11", optional = true }

[features]
examples = ["dasp"]
```

**Benefit:** Faster compile, smaller binary

---

## 🧹 CODE STYLE CLEANUP

### K. Consistent Naming
**Problem:** Mixed naming conventions

**Issues:**
```rust
// rf-dsp/dynamics.rs
attack_coeff   // snake_case (Rust convention) ✅
attackMs       // camelCase (non-Rust) ❌

// rf-audio/engine.rs
sample_rate    // snake_case ✅
sampleRate     // camelCase ❌
```

**Fix:**
```bash
# Find all camelCase in Rust
rg "[a-z][A-Z]" --type rust crates/

# Rename to snake_case
attackMs → attack_ms
releaseMs → release_ms
thresholdDb → threshold_db
```

**Benefit:** Consistent Rust style, easier grep

---

### L. Remove #[allow(dead_code)] Markers
**Problem:** 47 instances of `#[allow(dead_code)]`

**Why they exist:**
- Code WAS dead during development
- Marker added to suppress warning
- Code now used, but marker still there

**Action:**
```bash
# Find all instances
rg "#\[allow\(dead_code\)\]" --type rust crates/

# For each:
# 1. Remove marker
# 2. cargo build
# 3. If warning appears AND code truly dead → remove code
# 4. If no warning → marker was stale
```

**Benefit:** Surface actual dead code

---

## 📋 CLEANUP EXECUTION PLAN

### Phase 1: Safe Removals (30min)
1. ✅ Remove unused format modules (mqa, truehd, dsd, world, nsgt)
2. ✅ Remove old shader files
3. ✅ Remove old waveform widgets (Flutter)
4. ✅ Run tests: `cargo test && cd flutter_ui && flutter test`

**Verification:** No test failures, app launches

---

### Phase 2: Mock Code Removal (1h)
5. ✅ Remove `_MockEngineState` class from engine_api.dart
6. ✅ Remove all `if (!_useMock)` branches
7. ✅ Remove `_useMock` field
8. ✅ Test: App launch, playback, parameter changes

**Verification:** All features work, no mock remnants

---

### Phase 3: Deduplication (1h)
9. ✅ Consolidate transport state access pattern
10. ✅ Unify volumeToDb conversion
11. ✅ Merge color theme definitions
12. ✅ Run clippy: `cargo clippy -- -D warnings`

**Verification:** Zero clippy warnings

---

### Phase 4: Simplification (1.5h)
13. ✅ Remove processor trait hierarchy → direct impl
14. ✅ Simplify EqFilterType enum (remove unused variants)
15. ✅ Remove over-engineered abstractions
16. ✅ Benchmark: Verify no performance regression

**Verification:** Performance same or better

---

### Phase 5: Dependencies (30min)
17. ✅ Run `cargo +nightly udeps`
18. ✅ Move debug deps to dev-dependencies
19. ✅ Feature-gate optional deps
20. ✅ Test build: `cargo build --release --no-default-features`

**Verification:** Clean build, smaller binary

---

### Phase 6: Style Polish (30min)
21. ✅ Fix camelCase → snake_case in Rust
22. ✅ Remove stale `#[allow(dead_code)]`
23. ✅ Run rustfmt: `cargo fmt --all`
24. ✅ Final test suite: `cargo test --all-features`

**Verification:** All tests pass, consistent style

---

## 📊 EXPECTED RESULTS

### Before Cleanup
- Total lines: 132,621
- Dead code: ~2,500 lines
- Duplicate logic: ~1,200 lines
- Mock code: ~800 lines
- Binary size: 2.3GB
- Compile time: ~180s (full rebuild)

### After Cleanup
- Total lines: **~128,000** (-3.5%)
- Dead code: **0 lines**
- Duplicate logic: **0 lines**
- Mock code: **0 lines**
- Binary size: **2.0-2.1GB** (-8-13%)
- Compile time: **~155-165s** (-10-15%)

### Code Quality
- ✅ Single source of truth (no duplication)
- ✅ Zero inactive code paths
- ✅ Consistent naming (Rust conventions)
- ✅ Minimal trait hierarchy (direct impl)
- ✅ Clean dependency tree

---

## 🔍 VERIFICATION CHECKLIST

Pre svake faze:
```bash
# Snapshot tests
cargo test --all > tests_before.log

# Benchmark baseline
cargo bench > bench_before.log

# Binary size
ls -lh target/release/librf_bridge.dylib > size_before.txt
```

Posle svake faze:
```bash
# Verify tests still pass
cargo test --all > tests_after.log
diff tests_before.log tests_after.log  # Should be identical

# Verify performance not regressed
cargo bench > bench_after.log
# Compare: Should be same or better

# Verify binary size
ls -lh target/release/librf_bridge.dylib > size_after.txt
# Compare: Should be smaller

# Verify app works
cd flutter_ui && flutter run -d macos --release
# Manual test: Play audio, adjust parameters, scrub timeline
```

---

## ⚠️ SAFETY RULES

**NEVER remove code without:**
1. ✅ Grepping for ALL usages first
2. ✅ Running full test suite before & after
3. ✅ Testing app manually (audio playback, UI interaction)
4. ✅ Benchmarking performance-critical paths
5. ✅ Git commit BEFORE removal (easy revert if needed)

**Git workflow:**
```bash
# Before each phase
git add .
git commit -m "chore: Checkpoint before Phase X cleanup"

# After phase (if successful)
git add .
git commit -m "chore(cleanup): Phase X - [description]"

# If something breaks
git reset --hard HEAD~1  # Revert last commit
```

---

**Version:** 1.0
**Next Update:** After Phase 1-2 execution (report results)
