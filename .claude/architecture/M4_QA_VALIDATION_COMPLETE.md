# M4: QA & Validation — COMPLETE

**Date:** 2026-01-23
**Status:** 100% Complete (9/9 tasks)

---

## Overview

M4 introduces comprehensive QA and validation infrastructure for FluxForge Studio, covering:
- Audio regression testing with spectral analysis
- FFI fuzzing for robustness
- Performance benchmarking
- Code coverage tracking
- Release automation

---

## Crates Created

| Crate | Path | LOC | Tests | Purpose |
|-------|------|-----|-------|---------|
| **rf-audio-diff** | `crates/rf-audio-diff/` | ~950 | 37 | FFT-based spectral audio comparison |
| **rf-fuzz** | `crates/rf-fuzz/` | ~580 | 12 | FFI fuzzing framework |
| **rf-bench** | `crates/rf-bench/` | ~470 | 4 | Criterion performance benchmarks |
| **rf-coverage** | `crates/rf-coverage/` | ~650 | 14 | Coverage parsing, thresholds, trends |
| **rf-release** | `crates/rf-release/` | ~900 | 17 | Version, changelog, packaging |

**Total:** ~3,550 LOC, 84 tests

---

## P5.1: Audio Diff Tool (Spectral)

### Location
`crates/rf-audio-diff/`

### Files
```
src/
├── lib.rs          # Main exports, quick_compare(), files_match()
├── config.rs       # DiffConfig with presets
├── loader.rs       # Audio file loading (symphonia/hound)
├── spectral.rs     # FFT analysis, A-weighting
├── metrics.rs      # Time/spectral/perceptual metrics
├── analysis.rs     # AudioAnalysis combining all metrics
├── diff.rs         # AudioDiff::compare() main API
└── report.rs       # Text/JSON/Markdown/JUnit reports
```

### API
```rust
use rf_audio_diff::{AudioDiff, DiffConfig, DiffResult};

// Quick comparison
let result = AudioDiff::compare("reference.wav", "test.wav", &DiffConfig::default())?;

if result.is_pass() {
    println!("Audio matches within tolerance");
} else {
    println!("Differences: {:?}", result.summary());
}

// Presets
let strict = DiffConfig::strict();        // Bit-exact
let perceptual = DiffConfig::perceptual(); // Human-audible differences
let dsp = DiffConfig::dsp_regression();    // DSP testing
```

### Features
- **Spectral Analysis**: FFT-based frequency domain comparison
- **A-Weighting**: Perceptual loudness curve
- **Metrics**: Peak, RMS, correlation, spectral centroid, flatness
- **Tolerances**: Configurable per-metric thresholds

---

## P5.2: Golden File Management

### Location
`crates/rf-audio-diff/src/golden.rs`

### API
```rust
use rf_audio_diff::{GoldenStore, GoldenMetadata};

let store = GoldenStore::new("test_fixtures/golden")?;

// Register golden file
store.register("compressor_output", "path/to/reference.wav", GoldenMetadata {
    version: "1.0.0".into(),
    generator: "rf-dsp compressor".into(),
    ..Default::default()
})?;

// Compare against golden
let result = store.compare("compressor_output", "path/to/test.wav")?;

// Batch comparison
let batch = store.compare_all("path/to/test_outputs/")?;
```

### Features
- **Metadata Tracking**: Version, generator, timestamp
- **Batch Comparison**: Compare multiple files at once
- **Update Workflow**: Controlled golden file updates
- **JSON Export**: Machine-readable results

---

## P5.3: Visual Regression Tests

### Location
`flutter_ui/test/visual_regression/`

### Files
```
visual_regression/
├── visual_test_helper.dart    # Test utilities
└── widget_golden_tests.dart   # Widget golden tests
```

### API
```dart
// Run golden tests
flutter test --update-goldens test/visual_regression/

// Compare against existing
flutter test test/visual_regression/
```

### Covered Widgets
- Knob (various states)
- Fader (vertical/horizontal)
- Meter (peak/RMS)
- Color palette
- EQ band
- Waveform display

---

## P5.4: FFI Fuzzing Framework

### Location
`crates/rf-fuzz/`

### Files
```
src/
├── lib.rs         # Main exports, quick_fuzz()
├── config.rs      # FuzzConfig with presets
├── generators.rs  # Input generators with edge cases
├── harness.rs     # FuzzRunner, panic catching
└── report.rs      # FuzzReport formats
```

### API
```rust
use rf_fuzz::{FuzzConfig, FuzzRunner};

let config = FuzzConfig::ci()
    .with_seed(42)
    .with_iterations(10_000);

let runner = FuzzRunner::new(config);

// Fuzz f64 inputs
let result = runner.fuzz_f64(|x| {
    my_dsp_function(x)  // Should not panic
});

// Fuzz with validation
let result = runner.fuzz_with_validation(
    |gen| gen.audio_samples(256),
    |samples| process_audio(samples),
    |input, output| {
        // Validate output
        if output.iter().any(|s| s.is_nan()) {
            Err("Output contains NaN".into())
        } else {
            Ok(())
        }
    },
);

assert!(result.passed);
```

### Edge Cases Generated
```rust
// f64 edge cases
[0.0, -0.0, NaN, Infinity, -Infinity, MIN, MAX, MIN_POSITIVE, EPSILON, -EPSILON]

// Audio-specific
[silence, DC offset, impulse, sine, noise, square, edge_cases]
```

### Features
- **Reproducible**: Seeded RNG (ChaCha8)
- **Panic Catching**: Safe fuzzing
- **Edge Cases**: NaN, Inf, boundaries
- **Audio Generators**: Frequency, gain, pan, samples

---

## P5.5: Determinism Validation

### Location
`crates/rf-audio-diff/src/determinism.rs`

### API
```rust
use rf_audio_diff::{DeterminismValidator, DeterminismConfig};

let validator = DeterminismValidator::new(DeterminismConfig {
    iterations: 10,
    compare_bits: true,
    ..Default::default()
});

let result = validator.validate(&input_samples, |input| {
    my_dsp_processor.process(input)
});

assert!(result.is_deterministic);
```

### Features
- **Bit-Exact**: Compare output bits across runs
- **Multiple Iterations**: Detect non-determinism
- **Float Comparison**: Handle -0.0 vs 0.0

---

## P5.6: Audio Quality Gates

### Location
`crates/rf-audio-diff/src/quality_gates.rs`

### API
```rust
use rf_audio_diff::{QualityGateConfig, QualityGateRunner};

// Use preset
let config = QualityGateConfig::streaming();  // -14 LUFS, -1 dBTP
let config = QualityGateConfig::broadcast();  // -23 LUFS, -2 dBTP
let config = QualityGateConfig::mastering();  // Custom targets

// Run gates
let runner = QualityGateRunner::new(config);
let result = runner.check("output.wav")?;

if !result.passed {
    for failure in &result.failures {
        eprintln!("FAIL: {}", failure);
    }
}
```

### Quality Checks
| Check | Description |
|-------|-------------|
| **Loudness** | LUFS target with tolerance |
| **Peak** | True peak / sample peak limit |
| **Dynamic Range** | Min/max range |
| **Silence** | Max silence duration |
| **Clipping** | Clip detection |
| **DC Offset** | Max DC offset |
| **Stereo** | Correlation threshold |
| **Frequency** | Energy distribution |

### Presets
```rust
QualityGateConfig::streaming()   // Spotify/Apple Music (-14 LUFS)
QualityGateConfig::broadcast()   // EBU R128 (-23 LUFS)
QualityGateConfig::mastering()   // CD mastering
QualityGateConfig::game_audio()  // Game audio (wide dynamic range)
```

---

## P5.7: Performance Benchmarks

### Location
`crates/rf-bench/`

### Files
```
src/
├── lib.rs         # Main exports
├── generators.rs  # Test data generators
└── utils.rs       # Throughput metrics

benches/
├── dsp_benchmarks.rs     # DSP processor benchmarks
├── simd_benchmarks.rs    # SIMD vs scalar comparisons
└── buffer_benchmarks.rs  # Memory operation benchmarks
```

### Running Benchmarks
```bash
# All benchmarks
cargo bench -p rf-bench

# Specific benchmark
cargo bench -p rf-bench -- dsp

# With baseline
cargo bench -p rf-bench -- --save-baseline main
cargo bench -p rf-bench -- --baseline main
```

### DSP Benchmarks
| Benchmark | Description |
|-----------|-------------|
| `biquad_lowpass` | Single biquad filter |
| `biquad_peaking` | Peaking EQ filter |
| `biquad_cascade_4` | 4-band EQ cascade |
| `compressor` | Dynamics compression |
| `limiter` | Peak limiting |
| `stereo_panner` | Stereo panning |
| `stereo_width` | Width processing |
| `gain_ramp` | Gain automation |

### SIMD Benchmarks
| Benchmark | Comparison |
|-----------|------------|
| `gain_scalar_vs_simd` | Scalar vs AVX2 gain |
| `sum_scalar_vs_simd` | Buffer summation |
| `peak_scalar_vs_simd` | Peak detection |
| `mix_scalar_vs_simd` | Buffer mixing |

### Buffer Benchmarks
| Benchmark | Description |
|-----------|-------------|
| `buffer_copy` | Clone vs copy_from_slice vs ptr_copy |
| `buffer_alloc` | vec! vs with_capacity vs box |
| `ring_buffer` | Push/pop single vs slice |
| `buffer_zero` | fill vs iter vs write_bytes |
| `inplace_vs_outofplace` | Processing patterns |

---

## P5.8: Coverage Reporting

### Location
`crates/rf-coverage/`

### Files
```
src/
├── lib.rs         # Main exports, quick API
├── parser.rs      # llvm-cov JSON parsing
├── thresholds.rs  # Coverage threshold checking
├── report.rs      # Report generation
└── trends.rs      # Coverage trend tracking
```

### API
```rust
use rf_coverage::{CoverageData, CoverageThreshold, CoverageReport, TrendAnalysis};

// Load coverage data
let data = CoverageData::from_file("coverage.json")?;

// Check thresholds
let threshold = CoverageThreshold::strict();  // 80% line/function
let result = threshold.check(&data);

if !result.passed {
    eprintln!("{}", result.ci_output());
    std::process::exit(1);
}

// Generate report
let report = CoverageReport::new(data)
    .with_title("FluxForge Coverage")
    .with_threshold(result);

report.save("coverage.html", ReportFormat::Html)?;

// Track trends
let mut trends = TrendAnalysis::load("coverage_history.json")?;
trends.add(CoverageTrend::from_data(&data).with_commit("abc1234"));
trends.save("coverage_history.json")?;
```

### Threshold Presets
```rust
CoverageThreshold::default()  // 70% line/function
CoverageThreshold::strict()   // 80% line/function
CoverageThreshold::relaxed()  // 50% line/function
CoverageThreshold::audio()    // DSP-aware (lower for complex code)
```

### Report Formats
- **Text**: Console output
- **Markdown**: GitHub PR comments
- **HTML**: Visual report
- **JSON**: Machine-readable
- **JUnit**: CI integration

### Trend Analysis
```rust
let summary = trends.summary();
println!("Current: {:.1}%", summary.current);
println!("Change: {:+.1}%", summary.change.unwrap_or(0.0));
println!("Trend: {}", if summary.is_improving { "📈" } else { "📉" });
```

---

## P5.9: Release Automation

### Location
`crates/rf-release/`

### Files
```
src/
├── lib.rs         # ReleaseManager, ReleasePlan
├── version.rs     # Semantic versioning
├── changelog.rs   # Conventional commit parsing
└── packaging.rs   # Multi-platform packaging
```

### Version Management
```rust
use rf_release::{Version, BumpType};

let v: Version = "1.2.3".parse()?;
let v = v.bump(BumpType::Minor);      // 1.3.0
let v = v.with_prerelease("alpha.1"); // 1.3.0-alpha.1
let v = v.promote();                   // 1.3.0

assert!(v > "1.2.0".parse()?);
```

### Changelog Generation
```rust
use rf_release::{ChangelogGenerator, ChangelogEntry, ChangeType};

// Parse conventional commit
let entry = ChangelogEntry::from_commit(
    "feat(dsp): add new compressor",
    Some("abc1234".into()),
    Some("Author".into()),
);

assert_eq!(entry.change_type, ChangeType::Feature);
assert_eq!(entry.scope, Some("dsp".into()));

// Generate changelog
let generator = ChangelogGenerator::new()
    .since_tag("v1.0.0");

let entries = generator.from_commits(&commits);
```

### Change Types
| Type | Prefix | Emoji |
|------|--------|-------|
| Feature | `feat` | ✨ |
| Fix | `fix` | 🐛 |
| Docs | `docs` | 📝 |
| Style | `style` | 💄 |
| Refactor | `refactor` | ♻️ |
| Perf | `perf` | ⚡ |
| Test | `test` | ✅ |
| Build | `build` | 👷 |
| Chore | `chore` | 🔧 |
| Breaking | `feat!` | 💥 |

### Packaging
```rust
use rf_release::{PackageConfig, ReleasePackage, Platform};

let config = PackageConfig {
    name: "fluxforge-studio".into(),
    version: Version::new(1, 0, 0),
    platforms: vec![
        Platform::MacOsArm64,
        Platform::MacOsX64,
        Platform::WindowsX64,
        Platform::LinuxX64,
    ],
    ..Default::default()
};

let mut package = ReleasePackage::new(config);
let artifacts = package.build_all()?;

// Generate manifest
let manifest = package.manifest();
println!("{}", manifest.to_json());
println!("{}", manifest.to_markdown());
```

### Platform Targets
| Platform | Target Triple | Extension |
|----------|---------------|-----------|
| macOS ARM64 | `aarch64-apple-darwin` | `.tar.gz` |
| macOS x64 | `x86_64-apple-darwin` | `.tar.gz` |
| Windows x64 | `x86_64-pc-windows-msvc` | `.zip` |
| Linux x64 | `x86_64-unknown-linux-gnu` | `.tar.gz` |

---

## CI/CD Integration

### GitHub Actions Workflow

The CI workflow at `.github/workflows/ci.yml` now includes:

```yaml
# Coverage check
- name: Generate Coverage
  run: cargo llvm-cov --json --output-path coverage.json

- name: Check Coverage Threshold
  run: |
    cargo run -p rf-coverage -- check coverage.json --threshold 70

# Benchmarks
- name: Run Benchmarks
  run: cargo bench -p rf-bench -- --noplot

# Quality Gates (for audio files)
- name: Audio Quality Check
  run: |
    cargo run -p rf-audio-diff -- gate output.wav --preset streaming

# Regression Tests
- name: DSP Regression
  run: cargo test -p rf-dsp -- regression
```

---

## Dependencies Added

### Workspace Cargo.toml
```toml
[workspace.members]
# QA & Testing Infrastructure
"crates/rf-audio-diff",
"crates/rf-fuzz",
"crates/rf-bench",
"crates/rf-coverage",
"crates/rf-release",
```

### New Dependencies
| Crate | Version | Used By |
|-------|---------|---------|
| `criterion` | 0.5 | rf-bench |
| `rand_chacha` | 0.9 | rf-fuzz |
| `regex` | 1.11 | rf-coverage, rf-release |
| `toml` | 0.8 | rf-release |

---

## Test Summary

| Crate | Tests | Status |
|-------|-------|--------|
| rf-audio-diff | 37 | ✅ Pass |
| rf-fuzz | 12 | ✅ Pass |
| rf-bench | 4 | ✅ Pass |
| rf-coverage | 14 | ✅ Pass |
| rf-release | 17 | ✅ Pass |
| **Total** | **84** | ✅ All Pass |

---

## Usage Examples

### CI Pipeline Example
```bash
#!/bin/bash
set -e

# Build
cargo build --release

# Run tests
cargo test --all

# Check coverage
cargo llvm-cov --json -o coverage.json
cargo run -p rf-coverage -- check coverage.json --threshold 70

# Run benchmarks (optional, compare to baseline)
cargo bench -p rf-bench -- --baseline main

# Fuzz FFI (quick CI mode)
cargo test -p rf-fuzz

# Audio quality gates (if applicable)
for f in output/*.wav; do
    cargo run -p rf-audio-diff -- gate "$f" --preset streaming
done

echo "✅ All checks passed"
```

### Release Script Example
```bash
#!/bin/bash
VERSION=$1

# Bump version
cargo run -p rf-release -- bump $VERSION

# Generate changelog
cargo run -p rf-release -- changelog --since v$(cargo run -p rf-release -- previous)

# Build packages
cargo run -p rf-release -- package --all-platforms

# Create manifest
cargo run -p rf-release -- manifest > dist/manifest.json

echo "✅ Release $VERSION ready"
```

---

## Next Steps (M5)

With M4 complete, the following phases remain:

1. **M5: Documentation & Polish** — API docs, tutorials, examples
2. **M6: Production Hardening** — Error handling, logging, monitoring
3. **M7: Release** — Final testing, packaging, distribution

---

**M4: QA & Validation — COMPLETE** ✅
