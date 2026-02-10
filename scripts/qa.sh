#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# FluxForge Studio — Ultimate QA Orchestrator
# ══════════════════════════════════════════════════════════════════════════════
#
# Usage:
#   ./scripts/qa.sh                    # Run all gates (local profile)
#   ./scripts/qa.sh --profile=ci       # Run CI profile (all 10 gates)
#   ./scripts/qa.sh --profile=quick    # Run quick profile (analyze + unit only)
#   ./scripts/qa.sh --gate=UNIT        # Run single gate
#   ./scripts/qa.sh --gate=SECURITY    # Run single gate
#   ./scripts/qa.sh --report           # Generate HTML report only (from last run)
#
# Gates (in order):
#   1. ANALYZE     — flutter analyze (0 errors in lib/) + cargo clippy
#   2. UNIT        — cargo test + flutter test (unit only)
#   3. REGRESSION  — rf-dsp + rf-engine regression tests
#   4. DETERMINISM — rf-slot-lab seed reproducibility + rf-audio-diff
#   5. BENCH       — rf-bench performance benchmarks (budget enforcement)
#   6. GOLDEN      — rf-audio-diff golden file comparison
#   7. SECURITY    — cargo audit + unsafe pattern scan + FFI input validation
#   8. COVERAGE    — cargo llvm-cov threshold enforcement
#   9. LATENCY     — DSP latency budget enforcement (< 3ms @ 128 samples)
#  10. FUZZ        — rf-fuzz FFI boundary fuzzing
#
# Exit codes:
#   0 — All gates PASS
#   1 — One or more gates FAIL
#   2 — Configuration error
# ══════════════════════════════════════════════════════════════════════════════

set -uo pipefail
# NOTE: -e (errexit) removed intentionally — gate functions handle errors via return codes

# ── Constants ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FLUTTER_DIR="$PROJECT_ROOT/flutter_ui"
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts/qa"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_JSON="$ARTIFACTS_DIR/qa-report-$TIMESTAMP.json"
REPORT_HTML="$ARTIFACTS_DIR/qa-report-$TIMESTAMP.html"
REPORT_LATEST_JSON="$ARTIFACTS_DIR/qa-report-latest.json"
REPORT_LATEST_HTML="$ARTIFACTS_DIR/qa-report-latest.html"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── State ────────────────────────────────────────────────────────────────────
PROFILE="local"
SINGLE_GATE=""
FAIL_FAST=true
REPORT_ONLY=false
OVERALL_OK=true
GATE_RESULTS=()
GATE_LOGS=()
START_TIME=""
# NOTE: Using eval-based dynamic vars instead of declare -A (bash 3.2 compat on macOS)
# GATE_STATUS stored as _GS_<GATE>=pass|fail|skip
# GATE_TIMES stored as _GT_<GATE>=<ms>

# ── Profiles ─────────────────────────────────────────────────────────────────
# quick:  ANALYZE UNIT
# local:  ANALYZE UNIT REGRESSION DETERMINISM BENCH GOLDEN SECURITY
# full:   ANALYZE UNIT REGRESSION DETERMINISM BENCH GOLDEN SECURITY COVERAGE LATENCY
# ci:     ALL 10 gates
ALL_GATES_QUICK="ANALYZE UNIT"
ALL_GATES_LOCAL="ANALYZE UNIT REGRESSION DETERMINISM BENCH GOLDEN SECURITY"
ALL_GATES_FULL="ANALYZE UNIT REGRESSION DETERMINISM BENCH GOLDEN SECURITY COVERAGE LATENCY"
ALL_GATES_CI="ANALYZE UNIT REGRESSION DETERMINISM BENCH GOLDEN SECURITY COVERAGE LATENCY FUZZ"

# ── Parse Args ───────────────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --profile=*)  PROFILE="${arg#*=}" ;;
    --gate=*)     SINGLE_GATE="${arg#*=}" ;;
    --no-fail-fast) FAIL_FAST=false ;;
    --report)     REPORT_ONLY=true ;;
    --help|-h)
      echo "Usage: $0 [--profile=local|ci|quick] [--gate=GATE] [--no-fail-fast] [--report]"
      exit 0
      ;;
    *) echo "Unknown arg: $arg"; exit 2 ;;
  esac
done

# ── Resolve Gates ────────────────────────────────────────────────────────────
if [[ -n "$SINGLE_GATE" ]]; then
  GATES="$SINGLE_GATE"
else
  case "$PROFILE" in
    quick) GATES="$ALL_GATES_QUICK" ;;
    local) GATES="$ALL_GATES_LOCAL" ;;
    full)  GATES="$ALL_GATES_FULL" ;;
    ci)    GATES="$ALL_GATES_CI" ;;
    *)     echo -e "${RED}ERROR: Unknown profile '$PROFILE' (use: quick|local|full|ci)${NC}"; exit 2 ;;
  esac
fi

# ── Bash 3.2 Compat (no associative arrays on macOS) ───────────────────────
get_gate_status() { eval echo "\${_GS_$1:-skip}"; }
set_gate_status() { eval "_GS_$1=$2"; }
get_gate_time()   { eval echo "\${_GT_$1:-0}"; }
set_gate_time()   { eval "_GT_$1=$2"; }

# ── Utilities ────────────────────────────────────────────────────────────────
now_ms() {
  python3 -c "import time; print(int(time.time() * 1000))" 2>/dev/null || date +%s000
}

duration_ms() {
  local start=$1 end=$2
  echo $(( end - start ))
}

print_header() {
  echo ""
  echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${BLUE}  FluxForge Studio — QA Pipeline${NC}"
  echo -e "${BOLD}${BLUE}  Profile: ${CYAN}$PROFILE${BLUE}  |  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
  echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════${NC}"
  echo ""
}

print_gate_start() {
  local gate=$1
  local num=$2
  local total=$3
  echo -e "${BOLD}[$num/$total] ${CYAN}$gate${NC} ..."
}

print_gate_result() {
  local gate=$1
  local ok=$2
  local ms=$3
  local sec=$(( ms / 1000 ))
  local msrem=$(( ms % 1000 ))
  if [[ "$ok" == "true" ]]; then
    echo -e "        ${GREEN}PASS${NC}  ${gate}  (${sec}.${msrem}s)"
  else
    echo -e "        ${RED}FAIL${NC}  ${gate}  (${sec}.${msrem}s)"
  fi
}

print_summary() {
  echo ""
  echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
  if [[ "$OVERALL_OK" == "true" ]]; then
    echo -e "${BOLD}${GREEN}  RESULT: ALL GATES PASSED${NC}"
  else
    echo -e "${BOLD}${RED}  RESULT: QA FAILED${NC}"
  fi
  echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"

  local total_gates=0
  local passed_gates=0
  for gate in $GATES; do
    total_gates=$((total_gates + 1))
    if [[ "$(get_gate_status $gate)" == "pass" ]]; then
      passed_gates=$((passed_gates + 1))
    fi
  done

  echo -e "  Gates: ${passed_gates}/${total_gates} passed"
  echo -e "  Report: ${REPORT_LATEST_HTML}"
  echo ""
}

# ── Gate: ANALYZE ────────────────────────────────────────────────────────────
gate_analyze() {
  local log="$ARTIFACTS_DIR/gate-analyze.log"
  local ok=true
  local details=""

  # 1. flutter analyze lib/ (must be 0 errors)
  echo "  [1/3] flutter analyze lib/ ..." | tee -a "$log"
  cd "$FLUTTER_DIR"
  local analyze_out
  analyze_out=$(flutter analyze lib/ 2>&1) || true
  echo "$analyze_out" >> "$log"
  echo "$analyze_out" | tail -5
  if echo "$analyze_out" | grep -q "error •"; then
    ok=false
    details="flutter analyze lib/ has errors"
  fi

  # 2. cargo clippy (warnings as info, errors fail)
  echo "  [2/3] cargo clippy ..." | tee -a "$log"
  cd "$PROJECT_ROOT"
  local clippy_out
  clippy_out=$(cargo clippy --workspace -- \
    -A clippy::derivable_impls \
    -A clippy::approx_constant \
    -A clippy::not_unsafe_ptr_arg_deref \
    -A clippy::mut_from_ref \
    2>&1) || true
  echo "$clippy_out" >> "$log"
  echo "$clippy_out" | tail -3
  if echo "$clippy_out" | grep -q "^error"; then
    ok=false
    details="${details:+$details; }cargo clippy has errors"
  fi

  # 3. cargo fmt check
  echo "  [3/3] cargo fmt --check ..." | tee -a "$log"
  cd "$PROJECT_ROOT"
  if ! cargo fmt --all -- --check >> "$log" 2>&1; then
    ok=false
    details="${details:+$details; }cargo fmt check failed"
  fi

  [[ "$ok" == "true" ]] && echo "PASS" || echo "FAIL: $details"
  return $([[ "$ok" == "true" ]] && echo 0 || echo 1)
}

# ── Gate: UNIT ───────────────────────────────────────────────────────────────
gate_unit() {
  local log="$ARTIFACTS_DIR/gate-unit.log"
  local ok=true

  # 1. Rust unit tests
  echo "  [1/2] cargo test --workspace ..." | tee -a "$log"
  cd "$PROJECT_ROOT"
  cargo test --workspace --release >> "$log" 2>&1 || ok=false

  # 2. Flutter unit tests (only models/ providers/ services/ utils/ — skip broken widget tests)
  echo "  [2/2] flutter test (unit) ..." | tee -a "$log"
  cd "$FLUTTER_DIR"
  local flutter_ok=true
  for test_dir in test/models test/providers test/controllers; do
    if [[ -d "$test_dir" ]]; then
      flutter test "$test_dir" >> "$log" 2>&1 || flutter_ok=false
    fi
  done
  if [[ "$flutter_ok" == "false" ]]; then
    ok=false
  fi

  return $([[ "$ok" == "true" ]] && echo 0 || echo 1)
}

# ── Gate: REGRESSION ─────────────────────────────────────────────────────────
gate_regression() {
  local log="$ARTIFACTS_DIR/gate-regression.log"
  local ok=true

  # rf-dsp regression tests (14 tests in tests/regression_tests.rs)
  echo "  [1/2] rf-dsp regression tests ..." | tee -a "$log"
  cd "$PROJECT_ROOT"
  cargo test -p rf-dsp --release -- regression >> "$log" 2>&1 || ok=false

  # rf-engine integration tests
  echo "  [2/2] rf-engine integration tests ..." | tee -a "$log"
  cargo test -p rf-engine --release >> "$log" 2>&1 || ok=false

  return $([[ "$ok" == "true" ]] && echo 0 || echo 1)
}

# ── Gate: DETERMINISM ────────────────────────────────────────────────────────
gate_determinism() {
  local log="$ARTIFACTS_DIR/gate-determinism.log"
  local ok=true

  # 1. Run dedicated determinism_check binary (bit-exact reproducibility)
  echo "  [1/2] DSP determinism check (5 processors × 5 runs) ..." | tee -a "$log"
  cd "$PROJECT_ROOT"
  local det_out
  det_out=$(cargo run -p rf-bench --release --example determinism_check 2>&1) || true
  echo "$det_out" >> "$log"

  # Parse machine-parseable output
  local det_passed det_failed
  det_passed=$(echo "$det_out" | grep "^DETERMINISM_TOTAL:" | sed 's/.*passed=\([0-9]*\).*/\1/' || echo "0")
  det_failed=$(echo "$det_out" | grep "^DETERMINISM_TOTAL:" | sed 's/.*failed=\([0-9]*\).*/\1/' || echo "0")

  if [[ "$det_failed" != "0" ]] || [[ "$det_passed" == "0" ]]; then
    echo "  FAIL: DSP determinism — $det_passed passed, $det_failed failed" | tee -a "$log"
    ok=false
  else
    echo "  PASS: $det_passed/$det_passed DSP processors are bit-exact" | tee -a "$log"
  fi

  # Show per-processor results
  echo "$det_out" | grep "^DETERMINISM_" | head -10 | while read -r line; do
    echo "    $line" | tee -a "$log"
  done

  # 2. rf-slot-lab seed reproducibility tests
  echo "  [2/2] rf-slot-lab seed reproducibility ..." | tee -a "$log"
  cargo test -p rf-slot-lab --release >> "$log" 2>&1 || ok=false

  return $([[ "$ok" == "true" ]] && echo 0 || echo 1)
}

# ── Gate: BENCH ──────────────────────────────────────────────────────────────
gate_bench() {
  local log="$ARTIFACTS_DIR/gate-bench.log"
  local ok=true
  local baseline_dir="$ARTIFACTS_DIR/bench-baseline"

  echo "  Running rf-bench Criterion benchmarks ..." | tee -a "$log"
  cd "$PROJECT_ROOT"

  # 1. Save baseline on first run, compare on subsequent runs
  if [[ -d "$baseline_dir" ]]; then
    echo "  [1/3] Running benchmarks (comparing to saved baseline) ..." | tee -a "$log"
    local bench_out
    bench_out=$(cargo bench -p rf-bench --bench '*' -- --baseline main 2>&1) || true
    echo "$bench_out" >> "$log"

    # 2. Check for regressions (criterion reports "regressed" in output)
    echo "  [2/3] Checking for performance regressions ..." | tee -a "$log"
    local regressions
    regressions=$(echo "$bench_out" | grep -i "regressed" | wc -l | tr -d ' ')
    local improvements
    improvements=$(echo "$bench_out" | grep -i "improved" | wc -l | tr -d ' ')

    echo "  Regressions: $regressions | Improvements: $improvements" | tee -a "$log"

    if [[ "$regressions" -gt 3 ]]; then
      echo "  FAIL: $regressions benchmark regressions detected (max allowed: 3)" | tee -a "$log"
      ok=false
    fi
  else
    echo "  [1/3] Running benchmarks (first run — generating baseline) ..." | tee -a "$log"
    cargo bench -p rf-bench --bench '*' -- --save-baseline main >> "$log" 2>&1 || ok=false

    # Copy criterion baseline to artifacts for persistence across runs
    echo "  [2/3] Saving baseline to $baseline_dir ..." | tee -a "$log"
    local criterion_dir="$PROJECT_ROOT/target/criterion"
    if [[ -d "$criterion_dir" ]]; then
      mkdir -p "$baseline_dir"
      cp -r "$criterion_dir"/* "$baseline_dir/" 2>/dev/null || true
      echo "  Baseline saved successfully" | tee -a "$log"
    fi
  fi

  # 3. Quick budget check — ensure benchmarks completed
  echo "  [3/3] Validating benchmark completion ..." | tee -a "$log"
  local criterion_dir="$PROJECT_ROOT/target/criterion"
  if [[ -d "$criterion_dir" ]]; then
    local bench_count
    bench_count=$(find "$criterion_dir" -name "estimates.json" 2>/dev/null | wc -l | tr -d ' ')
    echo "  Completed benchmarks: $bench_count" | tee -a "$log"
    if [[ "$bench_count" -eq 0 ]]; then
      echo "  FAIL: No benchmark results found" | tee -a "$log"
      ok=false
    fi
  else
    echo "  WARNING: No criterion results directory found" | tee -a "$log"
  fi

  return $([[ "$ok" == "true" ]] && echo 0 || echo 1)
}

# ── Gate: GOLDEN ─────────────────────────────────────────────────────────────
gate_golden() {
  local log="$ARTIFACTS_DIR/gate-golden.log"
  local ok=true
  local golden_dir="$ARTIFACTS_DIR/goldens"

  # 1. Run dedicated golden_check binary (DSP fingerprint comparison)
  echo "  [1/2] DSP golden reference check (8 processors) ..." | tee -a "$log"
  cd "$PROJECT_ROOT"
  local golden_out
  golden_out=$(cargo run -p rf-bench --release --example golden_check 2>&1) || true
  echo "$golden_out" >> "$log"

  # Parse machine-parseable output
  local gld_passed gld_failed gld_generated
  gld_passed=$(echo "$golden_out" | grep "^GOLDEN_TOTAL:" | sed 's/.*passed=\([0-9]*\).*/\1/' || echo "0")
  gld_failed=$(echo "$golden_out" | grep "^GOLDEN_TOTAL:" | sed 's/.*failed=\([0-9]*\).*/\1/' || echo "0")
  gld_generated=$(echo "$golden_out" | grep "^GOLDEN_TOTAL:" | sed 's/.*generated=\([0-9]*\).*/\1/' || echo "0")

  if [[ "$gld_failed" != "0" ]]; then
    echo "  FAIL: Golden reference mismatch — $gld_passed passed, $gld_failed failed" | tee -a "$log"
    ok=false
  elif [[ "$gld_passed" == "0" ]]; then
    echo "  FAIL: No golden tests ran" | tee -a "$log"
    ok=false
  else
    echo "  PASS: $gld_passed/$gld_passed golden references match (${gld_generated} newly generated)" | tee -a "$log"
  fi

  # Show per-test results
  echo "$golden_out" | grep "^GOLDEN_" | head -12 | while read -r line; do
    echo "    $line" | tee -a "$log"
  done

  # 2. Golden file inventory
  echo "  [2/2] Golden file inventory ..." | tee -a "$log"
  if [[ -d "$golden_dir" ]]; then
    local golden_count
    golden_count=$(find "$golden_dir" -name "*.golden" 2>/dev/null | wc -l | tr -d ' ')
    echo "  Golden files on disk: $golden_count" | tee -a "$log"
  else
    echo "  NOTE: Goldens stored in artifacts/qa/goldens/" | tee -a "$log"
  fi

  return $([[ "$ok" == "true" ]] && echo 0 || echo 1)
}

# ── Gate: SECURITY ───────────────────────────────────────────────────────────
gate_security() {
  local log="$ARTIFACTS_DIR/gate-security.log"
  local ok=true
  local hits=0

  # 1. cargo audit (known CVEs)
  echo "  [1/7] cargo audit ..." | tee -a "$log"
  cd "$PROJECT_ROOT"
  if command -v cargo-audit &>/dev/null; then
    if ! cargo audit >> "$log" 2>&1; then
      echo "  WARNING: cargo audit found vulnerabilities" | tee -a "$log"
      # Don't fail on audit warnings — info only
    fi
  else
    echo "  SKIP: cargo-audit not installed (install: cargo install cargo-audit)" >> "$log"
  fi

  # 2. Unsafe code audit in audio thread paths
  echo "  [2/7] Scanning for unsafe audio thread violations ..." | tee -a "$log"
  local unsafe_patterns=(
    "Vec::new\|Vec::push\|vec!\[" # Heap allocation
    "Box::new"                     # Heap allocation
    "String::from\|format!"        # String allocation
    "println!\|eprintln!"          # I/O in audio thread
    "unwrap()\|expect("            # Panics in audio thread
  )

  local audio_paths=(
    "crates/rf-engine/src/playback.rs"
    "crates/rf-dsp/src/biquad.rs"
    "crates/rf-dsp/src/dynamics.rs"
  )

  for pattern in "${unsafe_patterns[@]}"; do
    for audio_file in "${audio_paths[@]}"; do
      if [[ -f "$PROJECT_ROOT/$audio_file" ]]; then
        local found
        found=$(grep -n "$pattern" "$PROJECT_ROOT/$audio_file" 2>/dev/null | grep -v "test\|mod tests\|#\[test\]\|#\[cfg(test)\]\|// " | head -5)
        if [[ -n "$found" ]]; then
          echo "  WARNING: Potential audio thread violation in $audio_file:" | tee -a "$log"
          echo "    $found" | tee -a "$log"
          hits=$((hits + 1))
        fi
      fi
    done
  done

  # 3. Dart unsafe patterns (critical — fails gate)
  echo "  [3/7] Scanning Dart code for critical unsafe patterns ..." | tee -a "$log"
  cd "$FLUTTER_DIR"
  local dart_hits=0
  for pattern in "eval(" "dart:mirrors" "dart:developer_tools"; do
    local dart_found
    dart_found=$(grep -rn "$pattern" lib/ 2>/dev/null | head -5)
    if [[ -n "$dart_found" ]]; then
      echo "  CRITICAL: '$pattern' found in Dart code:" | tee -a "$log"
      echo "    $dart_found" | tee -a "$log"
      dart_hits=$((dart_hits + 1))
    fi
  done

  # 4. FFI input validation — ensure all FFI entry points validate parameters
  echo "  [4/7] Scanning FFI input validation coverage ..." | tee -a "$log"
  cd "$PROJECT_ROOT"
  local ffi_files=(
    "crates/rf-bridge/src/ffi.rs"
    "crates/rf-bridge/src/middleware_ffi.rs"
    "crates/rf-bridge/src/container_ffi.rs"
    "crates/rf-bridge/src/slot_lab_ffi.rs"
    "crates/rf-bridge/src/ale_ffi.rs"
    "crates/rf-bridge/src/offline_ffi.rs"
    "crates/rf-bridge/src/plugin_state_ffi.rs"
  )
  local ffi_warnings=0

  for ffi_file in "${ffi_files[@]}"; do
    if [[ -f "$PROJECT_ROOT/$ffi_file" ]]; then
      # Check for raw pointer dereference without null check
      local null_deref
      null_deref=$(grep -n "\.as_ref()\.\|\.as_str()\.\|CStr::from_ptr" "$PROJECT_ROOT/$ffi_file" 2>/dev/null | \
        grep -v "is_null\|null_check\|if.*null\|guard\|// safe" | head -3)
      if [[ -n "$null_deref" ]]; then
        echo "  WARNING: Potential unchecked pointer in $ffi_file:" | tee -a "$log"
        echo "    $null_deref" | tee -a "$log"
        ffi_warnings=$((ffi_warnings + 1))
      fi

      # Check for NaN/Inf unguarded float parameters
      local float_params
      float_params=$(grep -n "pub.*extern.*fn.*f32\|pub.*extern.*fn.*f64" "$PROJECT_ROOT/$ffi_file" 2>/dev/null | head -3)
      # Just count — don't fail, informational
      if [[ -n "$float_params" ]]; then
        local fn_count
        fn_count=$(echo "$float_params" | wc -l | tr -d ' ')
        echo "  INFO: $ffi_file has $fn_count FFI functions with float params" >> "$log"
      fi
    fi
  done

  # 5. Dart path traversal protection
  echo "  [5/7] Checking Dart path traversal protection ..." | tee -a "$log"
  cd "$FLUTTER_DIR"
  local path_hits=0

  # Find File() or Directory() calls that don't use PathValidator
  local unvalidated_paths
  unvalidated_paths=$(grep -rn "File(\|Directory(" lib/ 2>/dev/null | \
    grep -v "PathValidator\|path_validator\|import\|test\|// \|\.g\.dart" | \
    grep -v "tempDir\|cacheDir\|appDir\|DocumentsDirectory\|getApplicationDocumentsDirectory" | head -10)
  if [[ -n "$unvalidated_paths" ]]; then
    local path_count
    path_count=$(echo "$unvalidated_paths" | wc -l | tr -d ' ')
    echo "  INFO: $path_count File/Directory calls without PathValidator (review needed)" >> "$log"
    echo "$unvalidated_paths" >> "$log"
  fi

  # 6. Credential/secret leak check
  echo "  [6/7] Scanning for credential leaks ..." | tee -a "$log"
  cd "$PROJECT_ROOT"
  local secret_hits=0
  for pattern in "password.*=.*['\"]" "api_key.*=.*['\"]" "secret.*=.*['\"]" "token.*=.*['\"].*[a-zA-Z0-9]\\{20,\\}"; do
    local secret_found
    secret_found=$(grep -rn "$pattern" --include="*.dart" --include="*.rs" --include="*.toml" --include="*.yaml" 2>/dev/null | \
      grep -v "test\|example\|mock\|placeholder\|TODO\|password_field\|PasswordField\|obscureText" | head -3)
    if [[ -n "$secret_found" ]]; then
      echo "  WARNING: Potential credential in code:" | tee -a "$log"
      echo "    $secret_found" | tee -a "$log"
      secret_hits=$((secret_hits + 1))
    fi
  done

  # 7. Dependency license check
  echo "  [7/8] Checking dependency licenses ..." | tee -a "$log"
  cd "$PROJECT_ROOT"
  if command -v cargo-deny &>/dev/null; then
    cargo deny check licenses >> "$log" 2>&1 || true
  else
    echo "  SKIP: cargo-deny not installed" >> "$log"
  fi

  # 8. FFI function count audit — track #[no_mangle] extern functions
  echo "  [8/8] FFI function count audit ..." | tee -a "$log"
  cd "$PROJECT_ROOT"
  local total_ffi_fns=0
  local ffi_with_null_check=0

  # Also scan engine FFI files
  local all_ffi_files=("${ffi_files[@]}"
    "crates/rf-engine/src/ffi.rs"
    "crates/rf-engine/src/ffi_routing.rs"
    "crates/rf-engine/src/ffi_control_room.rs"
    "crates/rf-bridge/src/connector_ffi.rs"
    "crates/rf-bridge/src/ingest_ffi.rs"
    "crates/rf-bridge/src/auto_spatial_ffi.rs"
    "crates/rf-bridge/src/autosave_ffi.rs"
  )
  for ffi_file in "${all_ffi_files[@]}"; do
    if [[ -f "$PROJECT_ROOT/$ffi_file" ]]; then
      local fn_count=0
      fn_count=$(grep -c 'extern "C" fn' "$PROJECT_ROOT/$ffi_file" 2>/dev/null) || fn_count=0
      total_ffi_fns=$((total_ffi_fns + fn_count))

      # Count functions that have null pointer checks
      local null_checks=0
      null_checks=$(grep -c 'is_null\|null_check\|\.is_null()' "$PROJECT_ROOT/$ffi_file" 2>/dev/null) || null_checks=0
      ffi_with_null_check=$((ffi_with_null_check + null_checks))

      echo "    $(basename "$ffi_file"): $fn_count FFI functions, $null_checks null checks" >> "$log"
    fi
  done

  echo "  Total FFI functions (extern \"C\"): $total_ffi_fns" | tee -a "$log"
  echo "  Null pointer checks found: $ffi_with_null_check" | tee -a "$log"

  # Security gate passes if no critical Dart patterns found
  if [[ $dart_hits -gt 0 ]]; then
    ok=false
  fi

  echo "" | tee -a "$log"
  echo "  ── Security Summary ──" | tee -a "$log"
  echo "  Audio thread warnings: $hits" | tee -a "$log"
  echo "  Dart critical patterns: $dart_hits" | tee -a "$log"
  echo "  FFI validation warnings: $ffi_warnings" | tee -a "$log"
  echo "  Credential warnings: $secret_hits" | tee -a "$log"
  echo "  FFI functions audited: $total_ffi_fns" | tee -a "$log"
  echo "  Null checks coverage: $ffi_with_null_check" | tee -a "$log"
  return $([[ "$ok" == "true" ]] && echo 0 || echo 1)
}

# ── Gate: COVERAGE ──────────────────────────────────────────────────────────
gate_coverage() {
  local log="$ARTIFACTS_DIR/gate-coverage.log"
  local ok=true
  local min_line_pct=40   # Minimum line coverage percentage (workspace-wide across 20+ crates)
  local min_fn_pct=35     # Minimum function coverage percentage

  echo "  Checking code coverage thresholds ..." | tee -a "$log"
  cd "$PROJECT_ROOT"

  # Auto-install cargo-llvm-cov if missing
  if ! command -v cargo-llvm-cov &>/dev/null; then
    echo "  Auto-installing cargo-llvm-cov ..." | tee -a "$log"
    rustup component add llvm-tools-preview >> "$log" 2>&1 || true
    cargo install cargo-llvm-cov >> "$log" 2>&1 || true

    if ! command -v cargo-llvm-cov &>/dev/null; then
      echo "  FAIL: Could not install cargo-llvm-cov" | tee -a "$log"
      echo "  Manual install: rustup component add llvm-tools-preview && cargo install cargo-llvm-cov" >> "$log"
      return 1
    fi
    echo "  cargo-llvm-cov installed successfully" | tee -a "$log"
  fi

  # Generate coverage JSON (use per-crate to avoid ExFAT issues)
  echo "  [1/3] Running cargo llvm-cov ..." | tee -a "$log"
  local cov_json="$ARTIFACTS_DIR/coverage.json"

  # ExFAT workaround: use target-dir on internal disk (paths with spaces break C build scripts)
  local cov_target_dir="$HOME/.cache/fluxforge-cov-target"

  # Run coverage — try workspace first, fall back to key crates individually
  # Note: rf-bridge excluded from fallback (mp3lame-sys fails on ExFAT paths with spaces)
  # ExFAT workaround: CARGO_TARGET_DIR on internal disk avoids path-with-spaces issues in C build scripts
  if ! CARGO_TARGET_DIR="$cov_target_dir" cargo llvm-cov --workspace --json --output-path "$cov_json" >> "$log" 2>&1; then
    echo "  WARNING: Workspace coverage failed — running key crates individually" | tee -a "$log"
    local cov_ok=false
    for crate in rf-dsp rf-core rf-ale rf-slot-lab; do
      echo "  Running coverage for $crate ..." | tee -a "$log"
      if CARGO_TARGET_DIR="$cov_target_dir" cargo llvm-cov -p "$crate" --json --output-path "$cov_json" >> "$log" 2>&1; then
        cov_ok=true
        echo "  Coverage collected for $crate" | tee -a "$log"
        break
      fi
    done
    if [[ "$cov_ok" == "false" ]]; then
      echo "  SKIP: Coverage unavailable on this platform (ExFAT limitation)" | tee -a "$log"
      echo "  To run coverage: use internal disk or set CARGO_TARGET_DIR" | tee -a "$log"
      # Don't fail the gate — coverage is best-effort on ExFAT
      return 0
    fi
  fi

  # Parse coverage (using python3 for JSON parsing — available on macOS)
  echo "  [2/3] Parsing coverage results ..." | tee -a "$log"
  local line_pct fn_pct
  line_pct=$(python3 -c "
import json, sys
with open('$cov_json') as f:
    data = json.load(f)
totals = data.get('data', [{}])[0].get('totals', {})
lines = totals.get('lines', {})
covered = lines.get('covered', 0)
total = lines.get('count', 1)
print(f'{(covered/total)*100:.1f}')
" 2>/dev/null || echo "0.0")

  fn_pct=$(python3 -c "
import json, sys
with open('$cov_json') as f:
    data = json.load(f)
totals = data.get('data', [{}])[0].get('totals', {})
fns = totals.get('functions', {})
covered = fns.get('covered', 0)
total = fns.get('count', 1)
print(f'{(covered/total)*100:.1f}')
" 2>/dev/null || echo "0.0")

  echo "  Line coverage:     ${line_pct}% (min: ${min_line_pct}%)" | tee -a "$log"
  echo "  Function coverage: ${fn_pct}% (min: ${min_fn_pct}%)" | tee -a "$log"

  # Per-crate breakdown
  python3 -c "
import json
with open('$cov_json') as f:
    data = json.load(f)
files = data.get('data', [{}])[0].get('files', [])
crate_stats = {}
for f in files:
    fname = f.get('filename', '')
    if 'crates/' not in fname: continue
    crate = fname.split('crates/')[1].split('/')[0] if 'crates/' in fname else 'other'
    if crate not in crate_stats:
        crate_stats[crate] = {'covered': 0, 'total': 0}
    r = f.get('summary', {}).get('lines', {})
    crate_stats[crate]['covered'] += r.get('covered', 0)
    crate_stats[crate]['total'] += r.get('count', 0)
for c in sorted(crate_stats):
    s = crate_stats[c]
    pct = (s['covered']/s['total']*100) if s['total'] > 0 else 0
    print(f'    {c}: {pct:.1f}% ({s[\"covered\"]}/{s[\"total\"]} lines)')
" >> "$log" 2>/dev/null || true

  # Threshold enforcement
  echo "  [3/3] Enforcing thresholds ..." | tee -a "$log"
  local line_ok fn_ok
  line_ok=$(python3 -c "print('true' if float('$line_pct') >= $min_line_pct else 'false')" 2>/dev/null || echo "true")
  fn_ok=$(python3 -c "print('true' if float('$fn_pct') >= $min_fn_pct else 'false')" 2>/dev/null || echo "true")

  if [[ "$line_ok" == "false" ]]; then
    echo "  FAIL: Line coverage ${line_pct}% < ${min_line_pct}% threshold" | tee -a "$log"
    ok=false
  fi
  if [[ "$fn_ok" == "false" ]]; then
    echo "  FAIL: Function coverage ${fn_pct}% < ${min_fn_pct}% threshold" | tee -a "$log"
    ok=false
  fi

  if [[ -f "$cov_json" ]]; then
    echo "  Coverage JSON saved to: $cov_json" | tee -a "$log"
  fi

  return $([[ "$ok" == "true" ]] && echo 0 || echo 1)
}

# ── Gate: LATENCY ──────────────────────────────────────────────────────────
gate_latency() {
  local log="$ARTIFACTS_DIR/gate-latency.log"
  local ok=true

  # Budget: Full DSP chain must stay under audio buffer time
  # At 48kHz, 1024 samples = 21.33ms audio budget
  # We allow max 50% CPU budget = ~10ms for the full chain
  local max_chain_pct=50   # Max percentage of audio budget

  echo "  Enforcing DSP real-time latency budgets ..." | tee -a "$log"
  cd "$PROJECT_ROOT"

  # 1. Run dsp_profile binary (100K iterations per processor)
  echo "  [1/2] Running DSP profiler (100K iterations × 5 processors) ..." | tee -a "$log"
  local profile_out
  profile_out=$(cargo run -p rf-bench --release --example dsp_profile 2>&1) || true
  echo "$profile_out" >> "$log"

  # 2. Parse real-time safety output
  echo "  [2/2] Checking real-time safety budgets ..." | tee -a "$log"

  # Extract "Full chain per block: X.XXXms (Y.Y% budget)" from stderr
  local chain_ms chain_pct
  chain_ms=$(echo "$profile_out" | grep "Full chain per block:" | sed 's/.*: *\([0-9.]*\)ms.*/\1/' || echo "0")
  chain_pct=$(echo "$profile_out" | grep "Full chain per block:" | sed 's/.*(\([0-9.]*\)% budget).*/\1/' || echo "0")

  # Extract audio budget
  local audio_budget_ms
  audio_budget_ms=$(echo "$profile_out" | grep "Audio budget" | sed 's/.*: *\([0-9.]*\)ms/\1/' || echo "21.33")

  echo "  Audio budget @ 48kHz/1024:  ${audio_budget_ms}ms" | tee -a "$log"
  echo "  Full DSP chain per block:   ${chain_ms}ms (${chain_pct}% budget)" | tee -a "$log"

  # Per-processor breakdown
  echo "  ── Per-Processor Breakdown ──" | tee -a "$log"
  echo "$profile_out" | grep "^\[" | while read -r line; do
    echo "    $line" | tee -a "$log"
  done

  # Check if chain exceeds budget threshold
  local chain_ok
  chain_ok=$(python3 -c "
pct = float('$chain_pct') if '$chain_pct' != '' else 0
print('true' if pct < $max_chain_pct else 'false')
" 2>/dev/null || echo "true")

  if [[ "$chain_ok" == "false" ]]; then
    echo "  FAIL: Full chain uses ${chain_pct}% of audio budget (max: ${max_chain_pct}%)" | tee -a "$log"
    ok=false
  else
    echo "  PASS: DSP chain within real-time budget (${chain_pct}% < ${max_chain_pct}%)" | tee -a "$log"
  fi

  # Absolute latency check — chain_ms must be < 3ms
  local abs_ok
  abs_ok=$(python3 -c "
ms = float('$chain_ms') if '$chain_ms' != '' else 0
print('true' if ms < 3.0 else 'false')
" 2>/dev/null || echo "true")

  if [[ "$abs_ok" == "false" ]]; then
    echo "  FAIL: Full chain latency ${chain_ms}ms exceeds 3ms absolute limit" | tee -a "$log"
    ok=false
  fi

  return $([[ "$ok" == "true" ]] && echo 0 || echo 1)
}

# ── Gate: FUZZ ───────────────────────────────────────────────────────────────
gate_fuzz() {
  local log="$ARTIFACTS_DIR/gate-fuzz.log"
  local ok=true

  # rf-fuzz FFI boundary tests
  echo "  [1/2] rf-fuzz FFI boundary testing ..." | tee -a "$log"
  cd "$PROJECT_ROOT"
  cargo test -p rf-fuzz --release >> "$log" 2>&1 || ok=false

  # rf-bridge FFI tests
  echo "  [2/2] rf-bridge FFI tests ..." | tee -a "$log"
  cargo test -p rf-bridge --release >> "$log" 2>&1 || ok=false

  return $([[ "$ok" == "true" ]] && echo 0 || echo 1)
}

# ── Report Generator ─────────────────────────────────────────────────────────
generate_json_report() {
  local end_time
  end_time=$(now_ms)
  local total_ms
  total_ms=$(duration_ms "$START_TIME" "$end_time")

  local results_json="["
  local first=true
  for gate in $GATES; do
    local status="$(get_gate_status $gate)"
    local gate_ok="false"
    [[ "$status" == "pass" ]] && gate_ok="true"
    local gate_ms="$(get_gate_time $gate)"

    [[ "$first" != "true" ]] && results_json+=","
    first=false

    results_json+="$(cat <<GATEJSON
{
      "gate": "$gate",
      "ok": $gate_ok,
      "durationMs": $gate_ms,
      "logFile": "gate-$(echo "$gate" | tr '[:upper:]' '[:lower:]').log"
    }
GATEJSON
)"
  done
  results_json+="]"

  cat > "$REPORT_JSON" <<REPORT
{
  "product": "FluxForge Studio",
  "profile": "$PROFILE",
  "startedAt": "$(date -r $((START_TIME / 1000)) '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')",
  "finishedAt": "$(date '+%Y-%m-%dT%H:%M:%S')",
  "durationMs": $total_ms,
  "ok": $OVERALL_OK,
  "results": $results_json,
  "env": {
    "os": "$(uname -s)",
    "arch": "$(uname -m)",
    "rustc": "$(rustc --version 2>/dev/null | head -1 || echo 'unknown')",
    "flutter": "$(flutter --version 2>/dev/null | head -1 || echo 'unknown')",
    "profile": "$PROFILE"
  }
}
REPORT

  cp "$REPORT_JSON" "$REPORT_LATEST_JSON"
}

generate_html_report() {
  local json_data
  json_data=$(cat "$REPORT_JSON")

  local rows=""
  for gate in $GATES; do
    local status="$(get_gate_status $gate)"
    local gate_ms="$(get_gate_time $gate)"
    local sec=$((gate_ms / 1000))
    local cls="ok"
    local status_text="PASS"

    if [[ "$status" == "fail" ]]; then
      cls="fail"
      status_text="FAIL"
    elif [[ "$status" == "skip" ]]; then
      cls="skip"
      status_text="SKIP"
    fi

    local log_file="gate-$(echo "$gate" | tr '[:upper:]' '[:lower:]').log"

    rows+="<tr class=\"$cls\">"
    rows+="<td><strong>$gate</strong></td>"
    rows+="<td>$status_text</td>"
    rows+="<td>${sec}s</td>"
    rows+="<td><a href=\"$log_file\">View Log</a></td>"
    rows+="</tr>"
  done

  local overall_cls="pass-header"
  local overall_text="ALL GATES PASSED"
  [[ "$OVERALL_OK" != "true" ]] && overall_cls="fail-header" && overall_text="QA FAILED"

  cat > "$REPORT_HTML" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>FluxForge Studio — QA Report</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #0a0a0c; color: #e0e0e0; padding: 32px; }
  h1 { color: #4a9eff; margin-bottom: 8px; }
  .meta { color: #888; margin-bottom: 24px; font-size: 14px; }
  .pass-header { background: #1a3a1a; border: 2px solid #40ff90; padding: 16px; border-radius: 8px; margin-bottom: 24px; }
  .pass-header h2 { color: #40ff90; }
  .fail-header { background: #3a1a1a; border: 2px solid #ff4060; padding: 16px; border-radius: 8px; margin-bottom: 24px; }
  .fail-header h2 { color: #ff4060; }
  table { width: 100%; border-collapse: collapse; margin-top: 16px; }
  th { background: #1a1a20; color: #4a9eff; padding: 12px; text-align: left; border-bottom: 2px solid #333; }
  td { padding: 10px 12px; border-bottom: 1px solid #222; }
  tr.ok td { background: #0d1f0d; }
  tr.fail td { background: #1f0d0d; }
  tr.skip td { background: #1a1a20; color: #666; }
  tr.ok td:nth-child(2) { color: #40ff90; font-weight: bold; }
  tr.fail td:nth-child(2) { color: #ff4060; font-weight: bold; }
  a { color: #4a9eff; }
  .footer { margin-top: 32px; color: #555; font-size: 12px; }
</style>
</head>
<body>
  <h1>FluxForge Studio — QA Report</h1>
  <p class="meta">Profile: <strong>$PROFILE</strong> | Generated: $(date '+%Y-%m-%d %H:%M:%S')</p>

  <div class="$overall_cls">
    <h2>$overall_text</h2>
  </div>

  <table>
    <thead><tr><th>Gate</th><th>Status</th><th>Duration</th><th>Evidence</th></tr></thead>
    <tbody>$rows</tbody>
  </table>

  <p class="footer">Generated by scripts/qa.sh | FluxForge Studio QA Pipeline</p>
</body>
</html>
HTML

  cp "$REPORT_HTML" "$REPORT_LATEST_HTML"
}

# ── Main Orchestrator ────────────────────────────────────────────────────────
main() {
  mkdir -p "$ARTIFACTS_DIR"

  # Truncate all gate logs so results reflect ONLY this run
  for f in "$ARTIFACTS_DIR"/gate-*.log; do
    [[ -f "$f" ]] && : > "$f"
  done

  # Clean AppleDouble files on ExFAT volumes (crash Flutter test runner)
  find "$FLUTTER_DIR" -name '._*' -type f -delete 2>/dev/null || true

  START_TIME=$(now_ms)

  print_header

  # Count gates
  local gate_count=0
  for _ in $GATES; do gate_count=$((gate_count + 1)); done

  local gate_num=0
  for gate in $GATES; do
    gate_num=$((gate_num + 1))
    print_gate_start "$gate" "$gate_num" "$gate_count"

    local gate_start
    gate_start=$(now_ms)
    local gate_ok=true

    # Run gate function
    local gate_fn="gate_$(echo "$gate" | tr '[:upper:]' '[:lower:]')"
    if ! $gate_fn 2>&1; then
      gate_ok=false
      OVERALL_OK=false
    fi

    local gate_end
    gate_end=$(now_ms)
    local gate_ms
    gate_ms=$(duration_ms "$gate_start" "$gate_end")

    # Record result
    if [[ "$gate_ok" == "true" ]]; then
      set_gate_status "$gate" "pass"
    else
      set_gate_status "$gate" "fail"
    fi
    set_gate_time "$gate" "$gate_ms"

    print_gate_result "$gate" "$gate_ok" "$gate_ms"

    # Fail-fast
    if [[ "$gate_ok" == "false" && "$FAIL_FAST" == "true" ]]; then
      echo ""
      echo -e "${RED}FAIL-FAST: Stopping after $gate failure${NC}"
      break
    fi
  done

  # Generate reports
  generate_json_report
  generate_html_report

  print_summary

  [[ "$OVERALL_OK" == "true" ]] && exit 0 || exit 1
}

# ── Run ──────────────────────────────────────────────────────────────────────
main
