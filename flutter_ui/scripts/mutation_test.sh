#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# HELIX Mutation Guard — Layer 6
# ═══════════════════════════════════════════════════════════════════════════
#
# MUTATION TESTING: Verifies that the test suite actually catches bugs.
#
# Strategy: Namerno pokvarimo kritičan kod, pokrenemo testove.
# Ako testovi ne padnu → test je beskoristan.
# Ako padnu → test je validan guard.
#
# Usage:
#   cd flutter_ui
#   bash scripts/mutation_test.sh
#
# Options:
#   --target helix    Test only HELIX mutations
#   --target spin     Test only spin logic mutations
#   --target rtpc     Test only RTPC mutations
#   --fast            Samo najkritičnije mutacije
#   --report          Generiši HTML report
#
# Exit codes:
#   0 = sve mutacije uhvaćene (test suite je validan)
#   1 = neke mutacije prošle (test suite ima rupe)
#   2 = build error
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Config ───────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELIX_FILE="$PROJECT_ROOT/lib/screens/helix_screen.dart"
BACKUP_SUFFIX=".mutation_backup"
REPORT_FILE="$PROJECT_ROOT/mutation_report_$(date +%Y%m%d_%H%M%S).json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Mutation counters
MUTATIONS_TESTED=0
MUTATIONS_CAUGHT=0
MUTATIONS_SURVIVED=0
SURVIVED_MUTATIONS=()

# ─── Parse args ───────────────────────────────────────────────────────────
TARGET="all"
FAST_MODE=false
GENERATE_REPORT=false

for arg in "$@"; do
  case "$arg" in
    --target) ;;
    helix|spin|rtpc|dna) TARGET="$arg" ;;
    --fast) FAST_MODE=true ;;
    --report) GENERATE_REPORT=true ;;
  esac
done

# ─── Helpers ──────────────────────────────────────────────────────────────

log_info()    { echo -e "${CYAN}[MUTANT]${RESET} $1"; }
log_success() { echo -e "${GREEN}[CAUGHT]${RESET} $1"; }
log_warn()    { echo -e "${YELLOW}[SURVIVED]${RESET} $1"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $1"; }
log_header()  { echo -e "\n${BOLD}${CYAN}══ $1 ══${RESET}"; }

backup_file() {
  local file="$1"
  cp "$file" "${file}${BACKUP_SUFFIX}"
}

restore_file() {
  local file="$1"
  if [[ -f "${file}${BACKUP_SUFFIX}" ]]; then
    cp "${file}${BACKUP_SUFFIX}" "$file"
    rm "${file}${BACKUP_SUFFIX}"
  fi
}

apply_mutation() {
  local file="$1"
  local search="$2"
  local replacement="$3"
  sed -i '' "s|$search|$replacement|g" "$file"
}

run_test_suite() {
  local test_file="$1"
  local timeout="${2:-180}"
  # Returns 0 if tests PASS, 1 if tests FAIL (which is what we want for mutations)
  if timeout "$timeout" flutter test "$test_file" -d macos --no-pub 2>&1 | tail -5; then
    return 0  # Tests passed (mutation survived)
  else
    return 1  # Tests failed (mutation caught) ✓
  fi
}

test_mutation() {
  local description="$1"
  local file="$2"
  local search="$3"
  local replacement="$4"
  local test_file="${5:-integration_test/tests/helix_section_test.dart}"

  MUTATIONS_TESTED=$((MUTATIONS_TESTED + 1))
  log_info "M$MUTATIONS_TESTED: $description"

  # Backup
  backup_file "$file"

  # Apply mutation
  apply_mutation "$file" "$search" "$replacement"

  # Check if mutation actually changed anything
  if diff -q "$file" "${file}${BACKUP_SUFFIX}" > /dev/null 2>&1; then
    log_warn "M$MUTATIONS_TESTED: Mutation pattern not found, skipping"
    restore_file "$file"
    MUTATIONS_TESTED=$((MUTATIONS_TESTED - 1))
    return 0
  fi

  # Run tests
  local result
  if flutter analyze --no-pub 2>&1 | grep -q "error"; then
    # Mutation caused compile error — doesn't count
    log_info "M$MUTATIONS_TESTED: Mutation caused compile error (irrelevant)"
    restore_file "$file"
    MUTATIONS_TESTED=$((MUTATIONS_TESTED - 1))
    return 0
  fi

  if run_test_suite "$test_file" > /dev/null 2>&1; then
    # Tests PASSED with mutant code — mutation SURVIVED (BAD)
    log_warn "M$MUTATIONS_TESTED: $description → SURVIVED ⚠️"
    MUTATIONS_SURVIVED=$((MUTATIONS_SURVIVED + 1))
    SURVIVED_MUTATIONS+=("$description")
  else
    # Tests FAILED with mutant code — mutation CAUGHT (GOOD) ✓
    log_success "M$MUTATIONS_TESTED: $description → CAUGHT ✓"
    MUTATIONS_CAUGHT=$((MUTATIONS_CAUGHT + 1))
  fi

  # Restore original
  restore_file "$file"
}

# ─── Cleanup trap ─────────────────────────────────────────────────────────
cleanup() {
  # Restore all backup files in case of interrupt
  for backup in "$PROJECT_ROOT"/lib/**/*.mutation_backup; do
    if [[ -f "$backup" ]]; then
      original="${backup%${BACKUP_SUFFIX}}"
      cp "$backup" "$original"
      rm "$backup"
      log_info "Restored: $original"
    fi
  done
}
trap cleanup EXIT INT TERM

# ─── Pre-flight ───────────────────────────────────────────────────────────
log_header "HELIX Mutation Guard — Layer 6"
echo "Target: $TARGET | Fast: $FAST_MODE | Report: $GENERATE_REPORT"
echo "Project: $PROJECT_ROOT"

cd "$PROJECT_ROOT"

log_info "Running baseline tests (must pass before mutations)..."
if ! flutter test integration_test/tests/helix_section_test.dart -d macos --no-pub 2>&1 | tail -3; then
  log_error "Baseline tests FAILED. Fix tests before running mutation guard."
  exit 2
fi
log_success "Baseline: ALL TESTS PASS ✓"

# ─── MUTATION GROUP 1: SPIN LOGIC ─────────────────────────────────────────
if [[ "$TARGET" == "all" || "$TARGET" == "spin" ]]; then
  log_header "Mutation Group 1: Spin Logic"

  test_mutation \
    "SLAM guard negated (canSlam → !canSlam)" \
    "$HELIX_FILE" \
    "if (canSlam)" \
    "if (!canSlam)"

  test_mutation \
    "SKIP guard negated (canSkip → !canSkip)" \
    "$HELIX_FILE" \
    "if (canSkip)" \
    "if (!canSkip)"

  test_mutation \
    "Spin button always disabled (canSpin → false)" \
    "$HELIX_FILE" \
    "canSpin: true" \
    "canSpin: false"

  test_mutation \
    "Auto-spin count off-by-one (> 0 → >= 0)" \
    "$HELIX_FILE" \
    "_autoSpinCount > 0" \
    "_autoSpinCount >= 0"

  if [[ "$FAST_MODE" == false ]]; then
    test_mutation \
      "Spin disabled during win (inverted guard)" \
      "$HELIX_FILE" \
      "_isSpinning = true" \
      "_isSpinning = false"

    test_mutation \
      "SLAM button hidden when should be visible" \
      "$HELIX_FILE" \
      "_isSpinning && _showSlamButton" \
      "_isSpinning && !_showSlamButton"
  fi
fi

# ─── MUTATION GROUP 2: RTPC FORMULAS ──────────────────────────────────────
if [[ "$TARGET" == "all" || "$TARGET" == "rtpc" ]]; then
  log_header "Mutation Group 2: RTPC Formulas"

  test_mutation \
    "RTPC reel formula: reel*4+i → reel*4+row*4+i (collision bug)" \
    "$HELIX_FILE" \
    "widget.reel \* 4 + i" \
    "widget.reel * 4 + widget.row * 4 + i"

  test_mutation \
    "RTPC value clamp removed (0.0..1.0 → unbounded)" \
    "$HELIX_FILE" \
    ".clamp(0.0, 1.0)" \
    ""

  test_mutation \
    "RTPC label wrong param (TENSION → CHAOS)" \
    "$HELIX_FILE" \
    "'TENSION'" \
    "'WRONG_PARAM'"

  if [[ "$FAST_MODE" == false ]]; then
    test_mutation \
      "RTPC slider max value halved (1.0 → 0.5)" \
      "$HELIX_FILE" \
      "max: 1.0," \
      "max: 0.5,"

    test_mutation \
      "RTPC value inverted (value → 1.0 - value)" \
      "$HELIX_FILE" \
      "_rtpcTension" \
      "(1.0 - _rtpcTension)"
  fi
fi

# ─── MUTATION GROUP 3: AUDIO BINDING ──────────────────────────────────────
if [[ "$TARGET" == "all" || "$TARGET" == "helix" ]]; then
  log_header "Mutation Group 3: Audio Binding"

  test_mutation \
    "SlotEventLayer volume set to 0 instead of 1.0" \
    "$HELIX_FILE" \
    "volume: 1.0" \
    "volume: 0.0"

  test_mutation \
    "Audio path not assigned (empty string)" \
    "$HELIX_FILE" \
    "audioPath: path" \
    "audioPath: ''"

  test_mutation \
    "Auto-bind disabled by default (false → true)" \
    "$HELIX_FILE" \
    "loop: false" \
    "loop: true"

  if [[ "$FAST_MODE" == false ]]; then
    test_mutation \
      "Event layer actionType wrong ('Play' → 'Stop')" \
      "$HELIX_FILE" \
      "actionType: 'Play'" \
      "actionType: 'Stop'"

    test_mutation \
      "Auto-bind folder path ignored (empty)" \
      "$HELIX_FILE" \
      "_audioDnaFolder" \
      "''"
  fi
fi

# ─── MUTATION GROUP 4: DNA PERSISTENCE ────────────────────────────────────
if [[ "$TARGET" == "all" || "$TARGET" == "dna" ]]; then
  log_header "Mutation Group 4: DNA Persistence"

  test_mutation \
    "DNA brand not saved (brand: '' instead of brand)" \
    "$HELIX_FILE" \
    "brand: _dnaBrand" \
    "brand: ''"

  test_mutation \
    "DNA BPM min/max swapped" \
    "$HELIX_FILE" \
    "bpmMin: _dnaBpmMin" \
    "bpmMin: _dnaBpmMax"

  test_mutation \
    "Win escalation set to 0 (ignored)" \
    "$HELIX_FILE" \
    "winEscalation: _dnaWinEscalation" \
    "winEscalation: 0"

  if [[ "$FAST_MODE" == false ]]; then
    test_mutation \
      "DNA instruments not saved (empty list)" \
      "$HELIX_FILE" \
      "instruments: _dnaInstruments" \
      "instruments: []"
  fi
fi

# ─── MUTATION GROUP 5: ESC SAFETY ─────────────────────────────────────────
if [[ "$TARGET" == "all" || "$TARGET" == "helix" ]]; then
  log_header "Mutation Group 5: ESC Safety (HELIX must never close on ESC)"

  test_mutation \
    "ESC closes HELIX (canPop: true)" \
    "$HELIX_FILE" \
    "canPop: false" \
    "canPop: true"

  if [[ "$FAST_MODE" == false ]]; then
    test_mutation \
      "Close handler removed" \
      "$HELIX_FILE" \
      "onWillPop: () async => false" \
      "onWillPop: () async => true"
  fi
fi

# ─── RESULTS ──────────────────────────────────────────────────────────────
log_header "MUTATION GUARD RESULTS"

echo ""
echo -e "  Total mutations tested: ${BOLD}$MUTATIONS_TESTED${RESET}"
echo -e "  Caught by tests:        ${GREEN}${BOLD}$MUTATIONS_CAUGHT${RESET}"
echo -e "  Survived (rupe):        ${RED}${BOLD}$MUTATIONS_SURVIVED${RESET}"

if [[ $MUTATIONS_TESTED -gt 0 ]]; then
  SCORE=$(( MUTATIONS_CAUGHT * 100 / MUTATIONS_TESTED ))
  echo -e "  Mutation score:         ${BOLD}${SCORE}%${RESET}"
fi

if [[ ${#SURVIVED_MUTATIONS[@]} -gt 0 ]]; then
  echo ""
  echo -e "${RED}${BOLD}⚠️  SURVIVED MUTATIONS (test rupe):${RESET}"
  for mutation in "${SURVIVED_MUTATIONS[@]}"; do
    echo -e "  ${RED}→${RESET} $mutation"
  done
  echo ""
  echo -e "${YELLOW}Action: Dodaj testove koji pokrivaju ove slučajeve!${RESET}"
fi

# ─── JSON Report ──────────────────────────────────────────────────────────
if [[ "$GENERATE_REPORT" == true ]]; then
  cat > "$REPORT_FILE" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target": "$TARGET",
  "fast_mode": $FAST_MODE,
  "total": $MUTATIONS_TESTED,
  "caught": $MUTATIONS_CAUGHT,
  "survived": $MUTATIONS_SURVIVED,
  "score_percent": $(( MUTATIONS_TESTED > 0 ? MUTATIONS_CAUGHT * 100 / MUTATIONS_TESTED : 0 )),
  "survived_list": [$(printf '"%s",' "${SURVIVED_MUTATIONS[@]}" | sed 's/,$//')]
}
EOF
  log_info "Report saved: $REPORT_FILE"
fi

# ─── Exit code ────────────────────────────────────────────────────────────
if [[ $MUTATIONS_SURVIVED -gt 0 ]]; then
  echo ""
  echo -e "${RED}${BOLD}❌ MUTATION GUARD FAILED — $MUTATIONS_SURVIVED mutations survived${RESET}"
  exit 1
else
  echo ""
  echo -e "${GREEN}${BOLD}✅ MUTATION GUARD PASSED — sve mutacije uhvaćene${RESET}"
  exit 0
fi
