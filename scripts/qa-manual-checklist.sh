#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# FluxForge Studio — Manual QA Checklist
# ══════════════════════════════════════════════════════════════════════════════
#
# Usage:
#   ./scripts/qa-manual-checklist.sh              # Run all 8 flows
#   ./scripts/qa-manual-checklist.sh --flow=A     # Run single flow
#   ./scripts/qa-manual-checklist.sh --flow=D     # Run asset handling flow
#   ./scripts/qa-manual-checklist.sh --resume      # Resume from last checkpoint
#
# Manual QA Flows:
#   A — Project Lifecycle       (new project → save → reload → verify)
#   B — Preview Chain Safety    (spin → audio → visual sync verification)
#   C — Layering & Transitions  (ALE levels, context switches, fade curves)
#   D — Asset Handling          (import → assign → playback → export)
#   E — Undo/Redo Stress        (multi-action undo, cross-section, stress)
#   F — Multi-Section Sync      (DAW ↔ Middleware ↔ SlotLab state isolation)
#   G — Long Session Soak       (30-minute stability, memory, playback)
#   H — Regression Pack         (known-good scenarios that must never break)
#
# Exit codes:
#   0 — All flows PASS
#   1 — One or more flows FAIL
#   2 — Aborted by user
# ══════════════════════════════════════════════════════════════════════════════

set -uo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts/qa/manual"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$ARTIFACTS_DIR/manual-qa-$TIMESTAMP.md"
CHECKPOINT_FILE="$ARTIFACTS_DIR/.checkpoint"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── State ────────────────────────────────────────────────────────────────────
SINGLE_FLOW=""
RESUME=false
OVERALL_PASS=0
OVERALL_FAIL=0
OVERALL_SKIP=0
declare -A FLOW_RESULTS
ALL_FLOWS="A B C D E F G H"

# ── Parse Args ───────────────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --flow=*)   SINGLE_FLOW="${arg#*=}" ;;
    --resume)   RESUME=true ;;
    --help|-h)
      echo "Usage: $0 [--flow=A|B|C|D|E|F|G|H] [--resume]"
      exit 0
      ;;
    *) echo "Unknown arg: $arg"; exit 2 ;;
  esac
done

if [[ -n "$SINGLE_FLOW" ]]; then
  ALL_FLOWS="$SINGLE_FLOW"
fi

# ── Utilities ────────────────────────────────────────────────────────────────
prompt_check() {
  local id="$1"
  local description="$2"
  local hint="${3:-}"

  echo ""
  echo -e "  ${BOLD}${CYAN}[$id]${NC} $description"
  if [[ -n "$hint" ]]; then
    echo -e "  ${DIM}Hint: $hint${NC}"
  fi
  echo ""

  while true; do
    echo -ne "  ${YELLOW}Result? ${NC}[${GREEN}p${NC}]ass / [${RED}f${NC}]ail / [${DIM}s${NC}]kip / [${BLUE}n${NC}]ote: "
    read -r answer
    case "${answer,,}" in
      p|pass)
        echo -e "  ${GREEN}✓ PASS${NC}"
        echo "| $id | $description | PASS | |" >> "$REPORT_FILE"
        OVERALL_PASS=$((OVERALL_PASS + 1))
        return 0
        ;;
      f|fail)
        echo -ne "  ${RED}Reason: ${NC}"
        read -r reason
        echo -e "  ${RED}✗ FAIL${NC} — $reason"
        echo "| $id | $description | **FAIL** | $reason |" >> "$REPORT_FILE"
        OVERALL_FAIL=$((OVERALL_FAIL + 1))
        return 1
        ;;
      s|skip)
        echo -e "  ${DIM}— SKIP${NC}"
        echo "| $id | $description | SKIP | |" >> "$REPORT_FILE"
        OVERALL_SKIP=$((OVERALL_SKIP + 1))
        return 0
        ;;
      n|note)
        echo -ne "  ${BLUE}Note: ${NC}"
        read -r note
        echo -e "  ${BLUE}📝 Noted${NC}"
        echo "| $id | $description | NOTE | $note |" >> "$REPORT_FILE"
        ;;
      *)
        echo -e "  ${RED}Invalid. Use: p (pass), f (fail), s (skip), n (note)${NC}"
        ;;
    esac
  done
}

save_checkpoint() {
  local flow="$1"
  echo "$flow" > "$CHECKPOINT_FILE"
}

print_flow_header() {
  local id="$1"
  local name="$2"
  local desc="$3"
  echo ""
  echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${BLUE}  Flow $id: $name${NC}"
  echo -e "${DIM}  $desc${NC}"
  echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}"
}

print_prereq() {
  echo ""
  echo -e "  ${YELLOW}Prerequisites:${NC}"
  for prereq in "$@"; do
    echo -e "    ${DIM}• $prereq${NC}"
  done
  echo ""
  echo -ne "  ${YELLOW}Ready to proceed? ${NC}[Enter to continue, q to skip flow]: "
  read -r ready
  if [[ "${ready,,}" == "q" ]]; then
    return 1
  fi
  return 0
}

# ── Flow A: Project Lifecycle ──────────────────────────────────────────────
flow_a() {
  print_flow_header "A" "Project Lifecycle" "New project → Save → Reload → Verify state integrity"
  echo "" >> "$REPORT_FILE"
  echo "### Flow A: Project Lifecycle" >> "$REPORT_FILE"
  echo "| ID | Check | Result | Notes |" >> "$REPORT_FILE"
  echo "|---|---|---|---|" >> "$REPORT_FILE"

  if ! print_prereq \
    "App is running (use ./scripts/run-macos.sh)" \
    "No project is currently open"; then
    FLOW_RESULTS[A]="skip"
    return 0
  fi

  prompt_check "A.1" "Create new SlotLab project via File > New Project" \
    "Project should initialize with default 5x3 grid"

  prompt_check "A.2" "Import a GDD JSON file via GDD Import wizard" \
    "Wizard should parse and show preview dialog with grid, symbols, features"

  prompt_check "A.3" "Assign audio to at least 5 different stages (SPIN_START, REEL_STOP, WIN_PRESENT, etc.)" \
    "Drop audio files onto slots in UltimateAudioPanel or use drag-drop on mockup"

  prompt_check "A.4" "Save project (Cmd+S or File > Save)" \
    "Should save without errors, file appears on disk"

  prompt_check "A.5" "Close and reopen the project" \
    "File > Close, then File > Open"

  prompt_check "A.6" "Verify all audio assignments are preserved after reload" \
    "Check UltimateAudioPanel — all assigned slots should show audio files"

  prompt_check "A.7" "Verify GDD import data is preserved (grid dimensions, symbols)" \
    "Reel count, row count, and imported symbols should match original"

  prompt_check "A.8" "Run a spin — verify audio plays correctly" \
    "SPIN_START, REEL_STOP, WIN_PRESENT should all trigger audio"

  prompt_check "A.9" "Verify Events panel shows all created events" \
    "Events panel (right side) should list all composite events"

  save_checkpoint "A"
}

# ── Flow B: Preview Chain Safety ───────────────────────────────────────────
flow_b() {
  print_flow_header "B" "Preview Chain Safety" "Spin → Audio → Visual sync verification"
  echo "" >> "$REPORT_FILE"
  echo "### Flow B: Preview Chain Safety" >> "$REPORT_FILE"
  echo "| ID | Check | Result | Notes |" >> "$REPORT_FILE"
  echo "|---|---|---|---|" >> "$REPORT_FILE"

  if ! print_prereq \
    "App is running with a project that has audio assigned" \
    "At least SPIN_START, REEL_STOP_0..4, and WIN_PRESENT have audio"; then
    FLOW_RESULTS[B]="skip"
    return 0
  fi

  prompt_check "B.1" "Click SPIN — verify SPIN_START audio plays immediately (< 50ms)" \
    "No perceptible delay between button press and audio"

  prompt_check "B.2" "Verify REEL_SPIN_LOOP starts and loops seamlessly" \
    "No gaps or clicks in the loop"

  prompt_check "B.3" "Verify each reel stop produces audio in LEFT→RIGHT order" \
    "REEL_STOP_0 (left) → REEL_STOP_4 (right), stereo panning audible"

  prompt_check "B.4" "Verify REEL_SPIN_LOOP fades out when last reel stops" \
    "Spin loop should fade smoothly, not cut abruptly"

  prompt_check "B.5" "On a winning spin, verify WIN_PRESENT audio starts after all reels stop" \
    "No gap between last reel stop and win presentation audio"

  prompt_check "B.6" "Verify win tier plaque matches win amount (SMALL < 5x, BIG 5-15x, SUPER 15-30x)" \
    "Force outcomes with keyboard shortcuts 1-7 to test different tiers"

  prompt_check "B.7" "Verify rollup sound plays during coin counter animation" \
    "ROLLUP_TICK should play, speed matches counter"

  prompt_check "B.8" "Press SPACE during spin to STOP — verify immediate halt" \
    "Reels should stop immediately, no continued audio"

  prompt_check "B.9" "Trigger anticipation (Force outcome 6: Free Spins) — verify tension audio" \
    "Anticipation glow and audio should appear on reels 2+"

  prompt_check "B.10" "Verify NO double-spin on rapid button press" \
    "Clicking SPIN twice quickly should only trigger ONE spin"

  prompt_check "B.11" "Switch to Fullscreen (F11) — verify all audio works identically" \
    "Same audio behavior as embedded mode"

  prompt_check "B.12" "Exit Fullscreen (ESC) — verify no audio leaks" \
    "All audio should stop cleanly on exit"

  save_checkpoint "B"
}

# ── Flow C: Layering & Transitions ─────────────────────────────────────────
flow_c() {
  print_flow_header "C" "Layering & Transitions" "ALE levels, context switches, fade curves"
  echo "" >> "$REPORT_FILE"
  echo "### Flow C: Layering & Transitions" >> "$REPORT_FILE"
  echo "| ID | Check | Result | Notes |" >> "$REPORT_FILE"
  echo "|---|---|---|---|" >> "$REPORT_FILE"

  if ! print_prereq \
    "App is running" \
    "ALE system is configured with at least 2 contexts (BASE, FREESPINS)" \
    "Music layers assigned in Symbol Strip > Music Layers"; then
    FLOW_RESULTS[C]="skip"
    return 0
  fi

  prompt_check "C.1" "Verify base game music plays at L1 (lowest intensity) on project open" \
    "Check ALE panel — current level should be L1"

  prompt_check "C.2" "Trigger consecutive wins — verify ALE level increases (L1 → L2 → L3)" \
    "Use forced outcomes (key 3: Big Win) multiple times"

  prompt_check "C.3" "Trigger losses — verify ALE level decreases back (L3 → L2 → L1)" \
    "Use forced outcome (key 1: Lose) multiple times"

  prompt_check "C.4" "Trigger Free Spins (key 6) — verify context switch to FREESPINS" \
    "Music should transition smoothly, no abrupt cut"

  prompt_check "C.5" "During Free Spins, verify music layers match FS context" \
    "Different music than base game"

  prompt_check "C.6" "Exit Free Spins — verify transition back to BASE context" \
    "Smooth crossfade back to base game music"

  prompt_check "C.7" "Open ALE panel in Lower Zone — verify real-time signal monitor" \
    "Signals (winTier, momentum, etc.) should update in real-time"

  prompt_check "C.8" "Verify ducking: when WIN_PRESENT plays, music volume reduces" \
    "Music should duck during win presentation, then restore"

  prompt_check "C.9" "Open Stability panel — verify cooldown prevents rapid level changes" \
    "Multiple rapid wins should not cause level oscillation"

  save_checkpoint "C"
}

# ── Flow D: Asset Handling ─────────────────────────────────────────────────
flow_d() {
  print_flow_header "D" "Asset Handling" "Import → Assign → Playback → Export"
  echo "" >> "$REPORT_FILE"
  echo "### Flow D: Asset Handling" >> "$REPORT_FILE"
  echo "| ID | Check | Result | Notes |" >> "$REPORT_FILE"
  echo "|---|---|---|---|" >> "$REPORT_FILE"

  if ! print_prereq \
    "App is running" \
    "Have WAV, MP3, and FLAC audio files ready for import" \
    "Have a folder with 5+ audio files for batch import"; then
    FLOW_RESULTS[D]="skip"
    return 0
  fi

  prompt_check "D.1" "Import single WAV file via Audio Browser > Import File button" \
    "File should appear in Audio Pool"

  prompt_check "D.2" "Import single MP3 file — verify it appears with correct duration" \
    "Duration displayed in pool should match actual file"

  prompt_check "D.3" "Import single FLAC file — verify lossless import" \
    "File should import without quality loss"

  prompt_check "D.4" "Import folder (batch) via Import Folder button" \
    "All audio files in folder should appear in pool"

  prompt_check "D.5" "Preview audio by clicking play button on pool item" \
    "Audio should play, play icon changes to stop icon"

  prompt_check "D.6" "Drag audio file from pool to UltimateAudioPanel slot" \
    "Slot should accept the audio and show assignment"

  prompt_check "D.7" "Drag multiple files (multi-select) to a drop zone" \
    "Long-press to select multiple, drag shows file count"

  prompt_check "D.8" "Quick Assign mode: toggle, click slot, click audio" \
    "Quick Assign button in header, workflow: select slot → click audio = assigned"

  prompt_check "D.9" "Verify assigned audio plays during spin" \
    "Run a spin after assignment — audio should trigger on correct stage"

  prompt_check "D.10" "Reset audio assignments for a section (Symbol Strip reset button)" \
    "Confirmation dialog appears, assignments cleared after confirm"

  prompt_check "D.11" "Export soundbank via Bake > Package" \
    "ZIP file created with audio files and manifest"

  save_checkpoint "D"
}

# ── Flow E: Undo/Redo Stress ──────────────────────────────────────────────
flow_e() {
  print_flow_header "E" "Undo/Redo Stress" "Multi-action undo, cross-section, stress"
  echo "" >> "$REPORT_FILE"
  echo "### Flow E: Undo/Redo Stress" >> "$REPORT_FILE"
  echo "| ID | Check | Result | Notes |" >> "$REPORT_FILE"
  echo "|---|---|---|---|" >> "$REPORT_FILE"

  if ! print_prereq \
    "App is running with a project open" \
    "Undo/Redo available via Edit menu or Cmd+Z / Cmd+Shift+Z"; then
    FLOW_RESULTS[E]="skip"
    return 0
  fi

  prompt_check "E.1" "Create 5 events rapidly, then undo all 5 (Cmd+Z x5)" \
    "Events should disappear one by one in reverse order"

  prompt_check "E.2" "Redo all 5 events (Cmd+Shift+Z x5)" \
    "Events should reappear one by one in original order"

  prompt_check "E.3" "Assign audio to slot, undo, verify slot is empty" \
    "Audio assignment should be reversed"

  prompt_check "E.4" "Modify event name, undo, verify original name restored" \
    "Double-click event name → edit → Cmd+Z should restore"

  prompt_check "E.5" "Perform 50 rapid actions, then undo 50 times" \
    "No crash, no memory spike, all actions reversed"

  prompt_check "E.6" "After undo, perform a new action — redo stack should clear" \
    "Cmd+Shift+Z should do nothing after new action"

  prompt_check "E.7" "Switch sections (DAW → SlotLab → Middleware), verify undo is section-scoped" \
    "Undo in SlotLab should not affect DAW changes"

  save_checkpoint "E"
}

# ── Flow F: Multi-Section Sync ─────────────────────────────────────────────
flow_f() {
  print_flow_header "F" "Multi-Section Sync" "DAW ↔ Middleware ↔ SlotLab state isolation"
  echo "" >> "$REPORT_FILE"
  echo "### Flow F: Multi-Section Sync" >> "$REPORT_FILE"
  echo "| ID | Check | Result | Notes |" >> "$REPORT_FILE"
  echo "|---|---|---|---|" >> "$REPORT_FILE"

  if ! print_prereq \
    "App is running with a project" \
    "Audio files assigned in SlotLab" \
    "Navigate between sections using top-level tabs"; then
    FLOW_RESULTS[F]="skip"
    return 0
  fi

  prompt_check "F.1" "Start playing in DAW section, switch to SlotLab — verify DAW audio stops" \
    "UnifiedPlaybackController should pause DAW"

  prompt_check "F.2" "Start spin in SlotLab, switch to DAW — verify SlotLab audio stops" \
    "Slot audio should stop cleanly"

  prompt_check "F.3" "Create event in Middleware, verify it appears in SlotLab Events panel" \
    "Bidirectional sync via MiddlewareProvider"

  prompt_check "F.4" "Modify event layer volume in SlotLab, verify change in Middleware" \
    "Single source of truth — change reflects everywhere"

  prompt_check "F.5" "Import audio in DAW, verify it appears in Audio Pool across all sections" \
    "AudioAssetManager shared state"

  prompt_check "F.6" "Switch between sections 20 times rapidly" \
    "No crashes, no audio leaks, no state corruption"

  prompt_check "F.7" "Verify mixer state persists across section switches" \
    "Bus volumes, mute/solo states should be preserved"

  prompt_check "F.8" "Play audio in Browser preview, verify it doesn't affect other sections" \
    "Browser uses PREVIEW_ENGINE — isolated"

  save_checkpoint "F"
}

# ── Flow G: Long Session Soak ──────────────────────────────────────────────
flow_g() {
  print_flow_header "G" "Long Session Soak" "30-minute stability, memory, playback"
  echo "" >> "$REPORT_FILE"
  echo "### Flow G: Long Session Soak" >> "$REPORT_FILE"
  echo "| ID | Check | Result | Notes |" >> "$REPORT_FILE"
  echo "|---|---|---|---|" >> "$REPORT_FILE"

  if ! print_prereq \
    "App is running with full audio setup" \
    "Activity Monitor / top available for memory check" \
    "Set aside ~30 minutes for this flow"; then
    FLOW_RESULTS[G]="skip"
    return 0
  fi

  prompt_check "G.1" "Note starting memory usage of FluxForge Studio (Activity Monitor)" \
    "Record the RSS memory value"

  prompt_check "G.2" "Run 100 spins using Auto-Spin (key A)" \
    "Let auto-spin run ~3-5 minutes"

  prompt_check "G.3" "Verify no audio glitches during continuous spinning" \
    "Listen for clicks, pops, dropouts, silence gaps"

  prompt_check "G.4" "After 100 spins, check memory — should be within 2x of starting" \
    "Compare current RSS with starting value. Growth > 2x = leak"

  prompt_check "G.5" "Run 50 more spins with Turbo mode (key T)" \
    "Faster animation, audio should still be clean"

  prompt_check "G.6" "Force 10 Big Win outcomes (key 3) in succession" \
    "Celebration audio should play and stop cleanly each time"

  prompt_check "G.7" "Force 5 Free Spin triggers (key 6) in succession" \
    "Context switch audio should work every time"

  prompt_check "G.8" "After 30 minutes, verify app is still responsive" \
    "UI should not be sluggish, audio should play without delay"

  prompt_check "G.9" "Final memory check — note ending memory value" \
    "Memory should be stable (no unbounded growth)"

  prompt_check "G.10" "Save project and reload — verify no corruption" \
    "All data should survive save/load after long session"

  save_checkpoint "G"
}

# ── Flow H: Regression Pack ────────────────────────────────────────────────
flow_h() {
  print_flow_header "H" "Regression Pack" "Known-good scenarios that must never break"
  echo "" >> "$REPORT_FILE"
  echo "### Flow H: Regression Pack" >> "$REPORT_FILE"
  echo "| ID | Check | Result | Notes |" >> "$REPORT_FILE"
  echo "|---|---|---|---|" >> "$REPORT_FILE"

  if ! print_prereq \
    "App is running with audio assigned" \
    "This flow tests scenarios that have broken before"; then
    FLOW_RESULTS[H]="skip"
    return 0
  fi

  echo -e "  ${YELLOW}These checks verify known regression scenarios:${NC}"
  echo ""

  # Double-spin bug (2026-01-24)
  prompt_check "H.1" "Verify NO double-spin: click SPIN rapidly 3 times" \
    "REG: Double-spin trigger bug (2026-01-24). Only 1 spin should occur."

  # SPACE key stop in embedded mode (2026-01-26)
  prompt_check "H.2" "In embedded mode (NOT fullscreen): press SPACE to STOP during spin" \
    "REG: SPACE key stop-not-working (2026-01-26). Reels must stop immediately."

  # Reel phase infinite loop (2026-01-31)
  prompt_check "H.3" "Verify win presentation starts automatically after all reels stop" \
    "REG: Reel phase transition infinite loop (2026-01-31). No hung spinning state."

  # Animation controller race (2026-02-01)
  prompt_check "H.4" "Verify no ghost glow on stopped reels" \
    "REG: Animation controller race condition (2026-02-01). Animations stop with reels."

  # Audio cutoff prevention (2026-01-24)
  prompt_check "H.5" "Navigate away from SlotLab and back — verify audio still works on spin" \
    "REG: Audio cutoff on middleware re-registration (2026-01-24)"

  # Symbol audio re-registration (2026-01-25)
  prompt_check "H.6" "Assign symbol audio, navigate away and back — verify symbol audio persists" \
    "REG: Symbol audio lost on remount (2026-01-25)"

  # Fallback stage resolution (2026-01-24)
  prompt_check "H.7" "Assign audio to generic REEL_STOP (not per-reel) — verify all reel stops produce sound" \
    "REG: Fallback stage resolution (2026-01-24). REEL_STOP_0..4 falls back to REEL_STOP"

  # Per-reel sequential stop buffer (2026-01-25)
  prompt_check "H.8" "Run 10 spins — verify reel stop audio always plays in order L→R" \
    "REG: Sequential reel stop buffer (2026-01-25). No out-of-order audio."

  # Win line strict sequential (2026-01-24)
  prompt_check "H.9" "Force Big Win (key 3) — verify win lines show AFTER rollup completes" \
    "REG: Phase 3 starts after Phase 2 (2026-01-24). No overlap."

  # QuickSheet double commit (2026-01-23)
  prompt_check "H.10" "Drop audio on mockup element — verify exactly ONE event is created" \
    "REG: Double commitDraft (2026-01-23). Check Events panel for duplicates."

  prompt_check "H.11" "Verify anticipation triggers on reels 2+ (never reel 0)" \
    "REG: Anticipation system (2026-01-30). Force Free Spins outcome."

  prompt_check "H.12" "Verify BIG WIN is first major tier at 5x-15x bet" \
    "REG: Industry standard win tiers (2026-01-24). Not 'NICE WIN'."

  save_checkpoint "H"
}

# ── Summary ────────────────────────────────────────────────────────────────
print_final_summary() {
  local total=$((OVERALL_PASS + OVERALL_FAIL + OVERALL_SKIP))

  echo ""
  echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}  Manual QA Summary${NC}"
  echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  ${GREEN}Passed:${NC}  $OVERALL_PASS"
  echo -e "  ${RED}Failed:${NC}  $OVERALL_FAIL"
  echo -e "  ${DIM}Skipped:${NC} $OVERALL_SKIP"
  echo -e "  Total:   $total"
  echo ""

  if [[ $OVERALL_FAIL -eq 0 ]]; then
    echo -e "  ${BOLD}${GREEN}RESULT: MANUAL QA PASSED${NC}"
  else
    echo -e "  ${BOLD}${RED}RESULT: MANUAL QA FAILED ($OVERALL_FAIL failures)${NC}"
  fi

  echo ""
  echo -e "  Report: ${REPORT_FILE}"
  echo ""

  # Append summary to report
  echo "" >> "$REPORT_FILE"
  echo "---" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
  echo "## Summary" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
  echo "- **Passed:** $OVERALL_PASS" >> "$REPORT_FILE"
  echo "- **Failed:** $OVERALL_FAIL" >> "$REPORT_FILE"
  echo "- **Skipped:** $OVERALL_SKIP" >> "$REPORT_FILE"
  echo "- **Total:** $total" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
  if [[ $OVERALL_FAIL -eq 0 ]]; then
    echo "**RESULT: MANUAL QA PASSED**" >> "$REPORT_FILE"
  else
    echo "**RESULT: MANUAL QA FAILED ($OVERALL_FAIL failures)**" >> "$REPORT_FILE"
  fi
}

# ── Main ───────────────────────────────────────────────────────────────────
main() {
  mkdir -p "$ARTIFACTS_DIR"

  # Initialize report
  cat > "$REPORT_FILE" <<HEADER
# FluxForge Studio — Manual QA Report

**Date:** $(date '+%Y-%m-%d %H:%M:%S')
**Tester:** $(whoami)
**Profile:** Manual Checklist

---

HEADER

  echo ""
  echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${BLUE}  FluxForge Studio — Manual QA Checklist${NC}"
  echo -e "${BOLD}${BLUE}  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
  echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  Flows: ${CYAN}$ALL_FLOWS${NC}"
  echo -e "  For each check, enter: [p]ass, [f]ail, [s]kip, or [n]ote"
  echo ""

  # Resume logic
  local skip_until=""
  if [[ "$RESUME" == "true" && -f "$CHECKPOINT_FILE" ]]; then
    skip_until=$(cat "$CHECKPOINT_FILE")
    echo -e "  ${YELLOW}Resuming after flow $skip_until${NC}"
  fi

  local started=false
  if [[ -z "$skip_until" ]]; then
    started=true
  fi

  for flow_id in $ALL_FLOWS; do
    # Resume logic
    if [[ "$started" == "false" ]]; then
      if [[ "$flow_id" == "$skip_until" ]]; then
        started=false  # This flow was completed, skip it
        continue
      fi
      # After the checkpoint flow, start
      started=true
    fi

    # If resuming, skip completed flows
    if [[ "$RESUME" == "true" && -n "$skip_until" ]]; then
      # Check if this flow comes after the checkpoint
      local checkpoint_ord=$(printf '%d' "'$skip_until")
      local current_ord=$(printf '%d' "'$flow_id")
      if [[ $current_ord -le $checkpoint_ord ]]; then
        echo -e "  ${DIM}Skipping flow $flow_id (already completed)${NC}"
        continue
      fi
    fi

    local flow_fn="flow_$(echo "$flow_id" | tr '[:upper:]' '[:lower:]')"
    if declare -f "$flow_fn" > /dev/null 2>&1; then
      $flow_fn
    else
      echo -e "  ${RED}Unknown flow: $flow_id${NC}"
    fi
  done

  # Cleanup checkpoint
  rm -f "$CHECKPOINT_FILE"

  print_final_summary

  [[ $OVERALL_FAIL -eq 0 ]] && exit 0 || exit 1
}

# ── Run ──────────────────────────────────────────────────────────────────
main
