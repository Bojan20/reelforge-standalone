## 🔄 CI/CD Pipeline (2026-01-22) ✅

Kompletni GitHub Actions workflow za build, test i release.

**Location:** `.github/workflows/ci.yml`

### Jobs

| Job | Runner | Description |
|-----|--------|-------------|
| `check` | ubuntu-latest | Code quality (rustfmt, clippy) |
| `build` | matrix (4 OS) | Cross-platform Rust build + tests |
| `macos-universal` | macos-14 | Universal binary (ARM64 + x64) |
| `bench` | ubuntu-latest | Performance benchmarks |
| `security` | ubuntu-latest | cargo-audit security scan |
| `docs` | ubuntu-latest | Rust documentation build |
| `flutter-tests` | macos-latest | Flutter analyze + tests + coverage |
| `build-wasm` | ubuntu-latest | WASM build (wasm-pack) |
| `regression-tests` | ubuntu-latest | DSP + engine regression tests |
| `audio-quality-tests` | ubuntu-latest | Audio quality verification |
| `flutter-build-macos` | macos-14 | Full macOS app build |
| `release` | ubuntu-latest | Create release archives |

### Build Matrix

| OS | Target | Artifact |
|----|--------|----------|
| macOS 14 | aarch64-apple-darwin | reelforge-macos-arm64 |
| macOS 13 | x86_64-apple-darwin | reelforge-macos-x64 |
| Windows | x86_64-pc-windows-msvc | reelforge-windows-x64 |
| Ubuntu | x86_64-unknown-linux-gnu | reelforge-linux-x64 |

### Regression Tests

**DSP Tests:** `crates/rf-dsp/tests/regression_tests.rs` (~400 LOC)

| Test | Description |
|------|-------------|
| `test_biquad_lowpass_impulse_response` | Verifies filter impulse response |
| `test_biquad_highpass_dc_rejection` | DC offset rejection |
| `test_biquad_stability` | Numerical stability under extreme conditions |
| `test_compressor_gain_reduction` | Gain reduction accuracy |
| `test_limiter_ceiling` | True peak limiting |
| `test_gate_silence` | Gate closes to silence |
| `test_stereo_pan_law` | Equal power pan law |
| `test_stereo_width` | Width processing |
| `test_processing_determinism` | Bit-exact reproducibility |
| `test_state_independence` | Multiple instance isolation |
| `test_denormal_handling` | Denormal flushing |
| `test_coefficient_quantization` | Filter coefficient precision |
| `test_peak_detection` | Peak meter accuracy |
| `test_rms_calculation` | RMS meter accuracy |

**Total:** 39 tests (25 integration + 14 regression)

### Triggers

- Push to `main`, `develop`, `feature/**`
- Pull requests to `main`, `develop`
- Release creation
- Manual dispatch

---

