#!/bin/bash
# Agent Merge Script — Automated Conflict Resolution
# Usage: ./merge_agents.sh
# Purpose: Merge 4 agent outputs with specialist-wins strategy

set -e

PROJECT_ROOT="/Volumes/Bojan - T7/DevVault/Projects/fluxforge-studio"
FLUTTER_ROOT="$PROJECT_ROOT/flutter_ui"
MERGE_DIR="/tmp/p1_agent_merge"
LOG_FILE="$PROJECT_ROOT/.claude/AGENT_MERGE_LOG.txt"

echo "🔀 P1 Agent Merge — Starting" | tee "$LOG_FILE"
echo "Date: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Create merge workspace
rm -rf "$MERGE_DIR" 2>/dev/null || true
mkdir -p "$MERGE_DIR"/{audio,profiling,ux_middleware,generic}

echo "📂 Merge workspace created: $MERGE_DIR" | tee -a "$LOG_FILE"

# ═══════════════════════════════════════════════════════════════════════
# AUDIO DESIGNER FILES (ad3ea72 wins)
# ═══════════════════════════════════════════════════════════════════════

echo "" | tee -a "$LOG_FILE"
echo "🎵 AUDIO DESIGNER BATCH (ad3ea72):" | tee -a "$LOG_FILE"

AUDIO_FILES=(
  "models/audio_variant_group.dart"
  "services/audio_variant_service.dart"
  "widgets/audio/variant_group_panel.dart"
  "services/lufs_normalization_service.dart"
  "widgets/audio/waveform_zoom_control.dart"
)

for file in "${AUDIO_FILES[@]}"; do
  src="$FLUTTER_ROOT/lib/$file"
  if [ -f "$src" ]; then
    cp "$src" "$MERGE_DIR/audio/"
    echo "  ✅ $file" | tee -a "$LOG_FILE"
  else
    echo "  ⚠️ MISSING: $file" | tee -a "$LOG_FILE"
  fi
done

# ═══════════════════════════════════════════════════════════════════════
# PROFILING TOOLS FILES (a97bcb5 wins)
# ═══════════════════════════════════════════════════════════════════════

echo "" | tee -a "$LOG_FILE"
echo "📊 PROFILING TOOLS BATCH (a97bcb5):" | tee -a "$LOG_FILE"

PROFILING_FILES=(
  "services/latency_profiler.dart"
  "services/voice_steal_tracker.dart"
  "services/stage_resolution_tracer.dart"
  "services/dsp_load_attributor.dart"
  "widgets/profiler/latency_breakdown_panel.dart"
  "widgets/profiler/voice_steal_panel.dart"
  "widgets/profiler/stage_trace_detective.dart"
  "widgets/profiler/dsp_load_panel.dart"
)

for file in "${PROFILING_FILES[@]}"; do
  src="$FLUTTER_ROOT/lib/$file"
  if [ -f "$src" ]; then
    cp "$src" "$MERGE_DIR/profiling/"
    echo "  ✅ $file" | tee -a "$LOG_FILE"
  else
    echo "  ⚠️ MISSING: $file" | tee -a "$LOG_FILE"
  fi
done

# ═══════════════════════════════════════════════════════════════════════
# UX + MIDDLEWARE FILES (a564b14 wins)
# ═══════════════════════════════════════════════════════════════════════

echo "" | tee -a "$LOG_FILE"
echo "🎨 UX + MIDDLEWARE BATCH (a564b14):" | tee -a "$LOG_FILE"

UX_FILES=(
  "widgets/common/undo_history_panel.dart"
  "services/event_dependency_analyzer.dart"
  "widgets/middleware/event_dependency_graph.dart"
  "widgets/lower_zone/smart_tab_organizer.dart"
  "widgets/common/enhanced_drag_overlay.dart"
  "services/timeline_state_persistence.dart"
  "services/container_evaluation_logger.dart"
)

for file in "${UX_FILES[@]}"; do
  src="$FLUTTER_ROOT/lib/$file"
  if [ -f "$src" ]; then
    cp "$src" "$MERGE_DIR/ux_middleware/"
    echo "  ✅ $file" | tee -a "$LOG_FILE"
  else
    echo "  ⚠️ MISSING: $file" | tee -a "$LOG_FILE"
  fi
done

# ═══════════════════════════════════════════════════════════════════════
# GENERIC FILES (a412900 only, no conflicts)
# ═══════════════════════════════════════════════════════════════════════

echo "" | tee -a "$LOG_FILE"
echo "🔧 GENERIC BATCH (a412900 — no conflicts):" | tee -a "$LOG_FILE"

GENERIC_FILES=(
  "services/scripting/json_rpc_server.dart"
  "services/scripting/lua_interpreter.dart"
  "models/feature_template.dart"
  "services/feature_template_service.dart"
  "widgets/slot_lab/feature_template_panel.dart"
  "services/volatility_calculator.dart"
  "services/test_combinator_service.dart"
  "services/timing_validator.dart"
  "widgets/dsp/frequency_response_overlay.dart"
  "widgets/plugin/pdc_visualizer.dart"
)

for file in "${GENERIC_FILES[@]}"; do
  src="$FLUTTER_ROOT/lib/$file"
  if [ -f "$src" ]; then
    cp "$src" "$MERGE_DIR/generic/"
    echo "  ✅ $file" | tee -a "$LOG_FILE"
  else
    echo "  ⚠️ MISSING: $file" | tee -a "$LOG_FILE"
  fi
done

# ═══════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════

echo "" | tee -a "$LOG_FILE"
echo "📊 MERGE SUMMARY:" | tee -a "$LOG_FILE"
echo "  Audio Designer files: $(ls "$MERGE_DIR/audio" 2>/dev/null | wc -l)" | tee -a "$LOG_FILE"
echo "  Profiling files: $(ls "$MERGE_DIR/profiling" 2>/dev/null | wc -l)" | tee -a "$LOG_FILE"
echo "  UX/Middleware files: $(ls "$MERGE_DIR/ux_middleware" 2>/dev/null | wc -l)" | tee -a "$LOG_FILE"
echo "  Generic files: $(ls "$MERGE_DIR/generic" 2>/dev/null | wc -l)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

TOTAL=$(find "$MERGE_DIR" -name "*.dart" | wc -l)
echo "  TOTAL FILES: $TOTAL" | tee -a "$LOG_FILE"

# ═══════════════════════════════════════════════════════════════════════
# VERIFICATION
# ═══════════════════════════════════════════════════════════════════════

echo "" | tee -a "$LOG_FILE"
echo "🧪 Running flutter analyze..." | tee -a "$LOG_FILE"

cd "$FLUTTER_ROOT"
if flutter analyze 2>&1 | grep -q "No issues found"; then
  echo "  ✅ No errors!" | tee -a "$LOG_FILE"
else
  echo "  ⚠️ Errors detected — review needed" | tee -a "$LOG_FILE"
  flutter analyze 2>&1 | tail -10 | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "✅ Merge complete — Review $LOG_FILE for details" | tee -a "$LOG_FILE"
echo "Workspace: $MERGE_DIR"
