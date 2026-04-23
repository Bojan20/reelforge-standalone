# Agent 10: BuildOps

## Role
Build pipeline, cargo, xcodebuild, dylib, codesign, CI, offline processing, testing infra, benchmarks, WASM.

## File Ownership (~50 files)

### Build Files
- `Cargo.toml`, `rust-toolchain.toml`, `run-dev.sh`
- `flutter_ui/macos/copy_native_libs.sh`, `flutter_ui/scripts/bundle_dylibs.sh`
- `flutter_ui/macos/Runner/Scripts/clean_xattrs.sh`
- `flutter_ui/macos/Podfile`, `flutter_ui/pubspec.yaml`

### Rust Crates
- `crates/rf-offline/` (11 files) — batch processing, bouncing, stem export, native encoders
- `crates/rf-audio-diff/` (11 files) — FFT spectral comparison, regression testing
- `crates/rf-bench/` (3 files) — Criterion benchmarking
- `crates/rf-coverage/` (5 files) — code coverage analysis
- `crates/rf-fuzz/` (8 files) — randomized FFI fuzzing
- `crates/rf-release/` (4 files) — version management, packaging
- `crates/rf-wasm/` (1 file) — Web Audio API binding

## Build Procedure (MANDATORY ORDER)
1. Kill previous: `pkill -9 -f "FluxForge Studio"`
2. `cargo build --release`
3. Copy dylibs to `flutter_ui/macos/Frameworks/`
4. `cd flutter_ui && flutter analyze` — MUST 0 errors
5. `xcodebuild` with `~/Library/Developer/Xcode/DerivedData/FluxForge-macos`
6. Copy dylibs to app bundle Frameworks/
7. `open` app

## Critical Rules
1. **NEVER** `flutter run` — only xcodebuild + open .app
2. **ALWAYS** `~/Library/Developer/Xcode/DerivedData/` (HOME)
3. ExFAT: `._*` files cause codesign errors → clean_xattrs.sh
4. Homebrew: use `$(brew --prefix)`, NEVER hardcode /opt/homebrew/

## Known Bugs (ALL FIXED)
| # | Severity | Description | Location |
|---|----------|-------------|----------|
| 8 | CRITICAL | edition = "2024" | Cargo.toml:51 |
| 15 | HIGH | Hardcoded Homebrew paths | copy_native_libs.sh:29-30 |
| 22 | MEDIUM | wgpu poll unused Result | gpu.rs:273,495,690 |
| 83 | MEDIUM | Offline no pre-dither check | encoder.rs:70-74 |
| 84 | MEDIUM | bundle_dylibs.sh no cycle detection | bundle_dylibs.sh:23 |

## Forbidden
- NEVER use flutter run
- NEVER use /Library/Developer/ (without ~/)
- NEVER skip dylib copy step
- NEVER build without flutter analyze passing
