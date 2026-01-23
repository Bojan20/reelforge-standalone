# FluxForge QA Tools Guide

Comprehensive guide for using FluxForge's quality assurance and testing infrastructure.

---

## Overview

FluxForge M4 QA suite provides 6 specialized crates for testing, validation, and release automation:

| Crate | Purpose | Key Features |
|-------|---------|--------------|
| `rf-fuzz` | FFI fuzzing | Random input generation, crash detection |
| `rf-audio-diff` | Audio comparison | Spectral analysis, golden file testing |
| `rf-bench` | Performance | Criterion benchmarks, SIMD comparisons |
| `rf-coverage` | Code coverage | llvm-cov parsing, threshold enforcement |
| `rf-release` | Release automation | Versioning, changelog, packaging |
| `rf-offline` | Batch processing | Bounce, stems, normalization |

---

## rf-fuzz — FFI Fuzzing Framework

### Quick Start

```rust
use rf_fuzz::{quick_fuzz, fuzz_f64, FuzzConfig, FuzzRunner};

// Quick fuzz with 1000 iterations
let result = quick_fuzz(1000, |bytes| {
    // Your FFI function
    unsafe { process_audio(bytes.as_ptr(), bytes.len()) }
});

println!("Passed: {}, Failed: {}", result.passed, result.failed);
```

### Configuration

```rust
let config = FuzzConfig::default()
    .with_iterations(10_000)
    .with_seed(12345)           // Reproducible fuzzing
    .with_timeout_ms(1000)      // 1 second timeout
    .with_min_size(0)
    .with_max_size(4096);

let runner = FuzzRunner::new(config);
```

### Audio-Specific Fuzzing

```rust
// Fuzz with f64 audio samples
let result = fuzz_f64(5000, |sample| {
    // Test with edge cases: NaN, Inf, denormals
    process_sample(sample)
});

// Fuzz with buffer sizes
let result = runner.fuzz_buffer_sizes(|buffer| {
    process_buffer(&buffer)
}, 1..4096);
```

### CI Integration

```bash
# Run fuzz tests with report
cargo test -p rf-fuzz --release -- --test-threads=1

# Generate fuzz report
cargo run -p rf-fuzz -- --report fuzz-report.json
```

---

## rf-audio-diff — Audio Comparison Tool

### Quick Comparison

```rust
use rf_audio_diff::{quick_compare, files_match, DiffConfig};

// Simple pass/fail check
if files_match("reference.wav", "test.wav")? {
    println!("Audio matches!");
}

// Detailed comparison
let result = quick_compare("reference.wav", "test.wav")?;
println!("Max difference: {} dB", result.max_diff_db());
```

### Spectral Analysis

```rust
use rf_audio_diff::{AudioDiff, DiffConfig};

let config = DiffConfig::default()
    .with_fft_size(4096)
    .with_tolerance_db(-60.0)      // -60 dB tolerance
    .with_frequency_weighting(true); // A-weighting

let result = AudioDiff::compare("ref.wav", "test.wav", &config)?;

// Spectral metrics
println!("Spectral correlation: {:.4}", result.spectral_correlation());
println!("Frequency bins with diff: {}", result.bins_over_threshold());
```

### Golden File Testing

```rust
use rf_audio_diff::{GoldenStore, GoldenCompareResult};

let store = GoldenStore::new("tests/golden/")?;

// Save reference
store.save("compressor_test", &audio_data, metadata)?;

// Compare against golden
let result = store.compare("compressor_test", &test_data)?;
match result {
    GoldenCompareResult::Match => println!("✅ Matches golden"),
    GoldenCompareResult::Diff(details) => println!("❌ Differs: {:?}", details),
    GoldenCompareResult::Missing => println!("⚠️ No golden file"),
}
```

### Quality Gates

```rust
use rf_audio_diff::{QualityGateConfig, QualityGateRunner};

let gates = QualityGateConfig::default()
    .with_lufs_target(-14.0, 0.5)      // -14 LUFS ±0.5
    .with_true_peak_max(-1.0)           // -1 dBTP max
    .with_dynamic_range_min(8.0)        // 8 LU minimum DR
    .with_clipping_threshold(0);        // Zero samples over 0 dBFS

let runner = QualityGateRunner::new(gates);
let result = runner.check("output.wav")?;

if result.passed {
    println!("✅ All quality gates passed");
} else {
    for failure in result.failures {
        println!("❌ {}: {}", failure.gate, failure.message);
    }
}
```

### Determinism Validation

```rust
use rf_audio_diff::{DeterminismValidator, DeterminismConfig};

let config = DeterminismConfig::default()
    .with_runs(10)                    // Run 10 times
    .with_tolerance(1e-15);           // Bit-exact within tolerance

let validator = DeterminismValidator::new(config);

let result = validator.check(|| {
    // Your DSP processing function
    process_audio(&input)
})?;

if result.is_deterministic {
    println!("✅ Processing is deterministic");
} else {
    println!("❌ Non-determinism detected at sample {}", result.first_diff_sample);
}
```

---

## rf-bench — Performance Benchmarks

### Running Benchmarks

```bash
# All benchmarks
cargo bench -p rf-bench

# Specific group
cargo bench -p rf-bench -- dsp
cargo bench -p rf-bench -- simd
cargo bench -p rf-bench -- buffer

# With baseline comparison
cargo bench -p rf-bench -- --save-baseline main
# ... make changes ...
cargo bench -p rf-bench -- --baseline main
```

### Custom Benchmarks

```rust
use rf_bench::{generate_stereo, generate_mono, ThroughputMetrics};

// Generate test data
let stereo = generate_stereo(48000, 1.0); // 1 second at 48kHz
let mono = generate_mono(44100, 0.5);     // 0.5 seconds at 44.1kHz

// Measure throughput
let metrics = ThroughputMetrics::measure(|| {
    process_audio(&stereo)
}, 100); // 100 iterations

println!("Throughput: {:.2} samples/sec", metrics.samples_per_second);
println!("Latency: {:.2} µs", metrics.avg_latency_us);
```

### Quick Benchmarks

```rust
use rf_bench::QuickBench;

let bench = QuickBench::new("Compressor");
bench.run(1000, || {
    compressor.process(&buffer)
});

// Output: Compressor: avg=45.2µs, min=42.1µs, max=89.3µs
```

---

## rf-coverage — Coverage Reporting

### Generating Coverage

```bash
# Install cargo-llvm-cov
cargo install cargo-llvm-cov

# Generate coverage data
cargo llvm-cov --json --output-path coverage.json

# Or with HTML report
cargo llvm-cov --html --output-dir coverage/
```

### Parsing Coverage

```rust
use rf_coverage::{CoverageData, CoverageSummary, coverage_summary};

// Quick summary
let summary = coverage_summary("coverage.json")?;
println!("{}", summary.one_line());
// Output: Lines: 85.5%, Functions: 90.0%, Branches: 75.0% (45/50 files)

// Detailed data
let data = CoverageData::from_file("coverage.json")?;
println!("Total line coverage: {:.1}%", data.total_line_coverage());

// Per-file breakdown
for file in data.files() {
    println!("{}: {:.1}%", file.name, file.line_coverage());
}
```

### Threshold Enforcement

```rust
use rf_coverage::{CoverageThreshold, ThresholdResult};

// Default thresholds (70% line, 60% function)
let threshold = CoverageThreshold::default();

// Strict thresholds for CI
let strict = CoverageThreshold::strict(); // 80% line, 75% function

// Custom thresholds
let custom = CoverageThreshold::new()
    .with_line_coverage(85.0)
    .with_function_coverage(80.0)
    .with_branch_coverage(70.0)
    .with_per_file_minimum(50.0);

let result = custom.check(&data);
if !result.passed {
    for failure in &result.failures {
        eprintln!("Coverage failure: {}", failure);
    }
    std::process::exit(1);
}
```

### Report Generation

```rust
use rf_coverage::{CoverageReport, ReportFormat};

let report = CoverageReport::new(data);

// Generate different formats
let markdown = report.generate(ReportFormat::Markdown);
let html = report.generate(ReportFormat::Html);
let json = report.generate(ReportFormat::Json);
let badge = report.generate(ReportFormat::Badge);

// Save markdown report
std::fs::write("COVERAGE.md", markdown)?;
```

### Trend Tracking

```rust
use rf_coverage::{CoverageTrend, TrendAnalysis};

let mut trend = CoverageTrend::load("coverage-history.json")?;

// Add new data point
trend.add(data.total_line_coverage(), "v0.2.0");

// Analyze trend
let analysis = trend.analyze();
println!("Coverage delta: {:+.1}%", analysis.delta);
println!("Trend: {:?}", analysis.direction); // Improving, Declining, Stable

// Save for next run
trend.save("coverage-history.json")?;
```

---

## rf-release — Release Automation

### Version Management

```rust
use rf_release::{Version, BumpType};

let version = Version::parse("1.2.3")?;
println!("Current: {}", version); // 1.2.3

// Bump versions
let patch = version.bump(BumpType::Patch);  // 1.2.4
let minor = version.bump(BumpType::Minor);  // 1.3.0
let major = version.bump(BumpType::Major);  // 2.0.0

// Prerelease
let alpha = version.with_prerelease("alpha.1"); // 1.2.3-alpha.1
let stable = alpha.promote();                    // 1.2.3

// Git tag
println!("Tag: {}", version.git_tag()); // v1.2.3
```

### Changelog Generation

```rust
use rf_release::{ChangelogGenerator, ChangelogEntry, ChangeType};

let generator = ChangelogGenerator::new()
    .since_tag("v0.1.0")
    .with_authors(true);

let entries = generator.from_commits(&[
    ("abc1234".into(), "Author".into(), "feat(dsp): add compressor".into()),
    ("def5678".into(), "Author".into(), "fix(engine): memory leak".into()),
    ("ghi9012".into(), "Author".into(), "docs: update README".into()),
]);

for entry in &entries {
    println!("{} {}", entry.change_type.emoji(), entry.message);
}
// ✨ add compressor
// 🐛 memory leak
// 📝 update README
```

### Release Packaging

```rust
use rf_release::{ReleasePackage, PackageConfig, Platform};

let config = PackageConfig {
    name: "fluxforge-studio".into(),
    version: Version::parse("0.2.0")?,
    platforms: vec![
        Platform::MacOsArm64,
        Platform::MacOsX64,
        Platform::WindowsX64,
        Platform::LinuxX64,
    ],
    ..Default::default()
};

let mut package = ReleasePackage::new(config);

// Build all platforms
let artifacts = package.build_all()?;

// Generate manifest
let manifest = package.manifest();
println!("{}", manifest.to_markdown());
```

### Release Manager

```rust
use rf_release::{ReleaseManager, ReleaseConfig, BumpType};

let config = ReleaseConfig {
    version: Version::parse("0.1.0")?,
    crates: vec!["rf-core", "rf-dsp", "rf-engine", "rf-bridge"]
        .into_iter().map(String::from).collect(),
    flutter_path: Some("flutter_ui".into()),
    ..Default::default()
};

let mut manager = ReleaseManager::new(config);

// Prepare release
manager.bump(BumpType::Minor);
manager.set_prerelease("beta.1");

let plan = manager.prepare()?;
println!("{}", plan.to_markdown());
```

---

## rf-offline — Batch Processing

### Simple Bounce

```rust
use rf_offline::{OfflineProcessor, OfflineJob, OutputFormat, NormalizationMode};

let processor = OfflineProcessor::new();

let job = OfflineJob::new()
    .input("session/mixdown.wav")
    .output("exports/final.wav")
    .format(OutputFormat::Wav { bit_depth: 24 })
    .sample_rate(48000)
    .normalize(NormalizationMode::Lufs { target: -14.0 })
    .build();

let result = processor.process(job).await?;
println!("Exported: {} ({:.1}s)", result.output_path, result.duration);
```

### Stem Export

```rust
let stems = vec!["drums", "bass", "vocals", "synths", "fx"];

for stem in stems {
    let job = OfflineJob::new()
        .input(&format!("session/{}.wav", stem))
        .output(&format!("stems/{}_stem.wav", stem))
        .format(OutputFormat::Wav { bit_depth: 24 })
        .normalize(NormalizationMode::Peak { ceiling: -1.0 })
        .build();

    processor.queue(job);
}

// Process all in parallel
let results = processor.process_all().await?;
```

### Format Conversion

```rust
// WAV to FLAC
let job = OfflineJob::new()
    .input("source.wav")
    .output("output.flac")
    .format(OutputFormat::Flac { compression: 8 })
    .build();

// WAV to MP3
let job = OfflineJob::new()
    .input("source.wav")
    .output("output.mp3")
    .format(OutputFormat::Mp3 {
        bitrate: 320,
        vbr: false
    })
    .build();
```

---

## CI/CD Integration

### GitHub Actions Example

```yaml
name: QA Pipeline

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run fuzz tests
        run: cargo test -p rf-fuzz --release

      - name: Run benchmarks
        run: cargo bench -p rf-bench -- --noplot

      - name: Generate coverage
        run: |
          cargo install cargo-llvm-cov
          cargo llvm-cov --json --output-path coverage.json

      - name: Check coverage threshold
        run: cargo run -p rf-coverage -- check coverage.json --min-line 80

      - name: Audio regression tests
        run: cargo test -p rf-audio-diff --release
```

### Pre-commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Run quick fuzz
cargo test -p rf-fuzz --release -- quick_fuzz

# Check coverage doesn't regress
cargo llvm-cov --json --output-path /tmp/coverage.json
cargo run -p rf-coverage -- check /tmp/coverage.json --trend coverage-history.json
```

---

## Best Practices

### 1. Fuzz Testing
- Run fuzzing with multiple seeds
- Include edge cases: NaN, Inf, denormals, empty buffers
- Fuzz at release optimization level

### 2. Audio Comparison
- Use spectral comparison for perceptual similarity
- Use sample-exact for determinism testing
- Keep golden files versioned

### 3. Performance
- Always benchmark on release builds
- Use baseline comparisons
- Track trends over time

### 4. Coverage
- Aim for 80%+ line coverage
- Don't chase 100% — focus on critical paths
- Track trends, not absolute numbers

### 5. Release
- Use semantic versioning
- Generate changelogs from commits
- Automate artifact creation

---

## Troubleshooting

### Fuzz tests timing out
```rust
// Increase timeout
let config = FuzzConfig::default().with_timeout_ms(5000);
```

### Coverage data not found
```bash
# Ensure instrumentation is enabled
RUSTFLAGS="-C instrument-coverage" cargo test
```

### Benchmark variance too high
```bash
# Increase sample size
cargo bench -- --sample-size 100 --measurement-time 10
```

### Golden file mismatch after upgrade
```bash
# Regenerate golden files
REGENERATE_GOLDEN=1 cargo test -p rf-audio-diff
```
