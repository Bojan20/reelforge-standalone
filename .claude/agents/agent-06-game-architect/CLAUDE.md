# Agent 6: GameArchitect

## Role
Dart game flow, feature composition, behavior tree, simulation, math model.

## File Ownership (~60 files)

### Game Flow (5)
- `flutter_ui/lib/providers/slot_lab/game_flow_provider.dart` — FSM: BASE_GAME → FREE_SPINS → CASCADING → BONUS
- `flutter_ui/lib/providers/slot_lab/game_flow_integration.dart`
- `flutter_ui/lib/providers/slot_lab/stage_flow_provider.dart`
- `flutter_ui/lib/providers/slot_lab/transition_system_provider.dart`
- `flutter_ui/lib/providers/slot_lab/pacing_engine_provider.dart`

### Feature Executors (10)
- `flutter_ui/lib/executors/bonus_game_executor.dart`
- `flutter_ui/lib/executors/free_spins_executor.dart`
- `flutter_ui/lib/executors/cascade_executor.dart`
- `flutter_ui/lib/executors/hold_and_win_executor.dart`
- `flutter_ui/lib/executors/wild_features_executor.dart`
- `flutter_ui/lib/executors/collector_executor.dart`
- `flutter_ui/lib/executors/respin_executor.dart`
- `flutter_ui/lib/executors/gamble_executor.dart`
- `flutter_ui/lib/executors/multiplier_executor.dart`
- `flutter_ui/lib/executors/jackpot_executor.dart`

### Behavior Tree + AI (4)
- `flutter_ui/lib/providers/slot_lab/behavior_tree_provider.dart` (22+ node types, 300+ engine hooks)
- `flutter_ui/lib/providers/slot_lab/behavior_coverage_provider.dart`
- `flutter_ui/lib/providers/slot_lab/trigger_layer_provider.dart`
- `flutter_ui/lib/providers/slot_lab/context_layer_provider.dart`

### Simulation + Config (9)
- `flutter_ui/lib/providers/slot_lab/simulation_engine_provider.dart`
- `flutter_ui/lib/providers/slot_lab/feature_composer_provider.dart`
- `flutter_ui/lib/providers/slot_lab/slotlab_template_provider.dart`
- `flutter_ui/lib/providers/slot_lab/slotlab_export_provider.dart`
- `flutter_ui/lib/providers/slot_lab/ail_provider.dart`
- `flutter_ui/lib/providers/slot_lab/drc_provider.dart`
- `flutter_ui/lib/providers/slot_lab/sam_provider.dart`
- `flutter_ui/lib/providers/slot_lab/gad_provider.dart`
- `flutter_ui/lib/providers/slot_lab/sss_provider.dart`

### Models (2)
- `flutter_ui/lib/models/slot_lab_models.dart`
- `flutter_ui/lib/models/win_tier_config.dart`

### Game Design Widgets (25+)
- `flutter_ui/lib/widgets/slot_lab/` — game_flow_overlay, game_model_editor, win_tier_config_panel, win_celebration_designer, behavior_tree_widget, scenario_controls, scenario_editor, forced_outcome_panel, feature_builder_panel
- `flutter_ui/lib/widgets/slot_lab/bonus/` (4 files) — bonus_simulator, gamble_simulator, pick_bonus, hold_and_win_visualizer
- `flutter_ui/lib/widgets/slot_lab/` — sfx_pipeline_wizard, stage_editor_dialog, stage_timing_editor, transition_config_panel, gdd_import_panel, gdd_import_wizard, gdd_preview_dialog

## Critical Rules
1. Win tier: data-driven (`P5 WinTierConfig`), NEVER hardcode labels/colors/icons/durations
2. `_bigWinEndFired` guard — prevents double BIG_WIN_END trigger on skip during end hold
3. BIG_WIN_END composite ITSELF handles stopping BIG_WIN_START (NOT manual stopEvent)
4. Free spins auto-spin: balance NOT deducted during free spins (`_isInFreeSpins` guard)
5. Behavior tree coverage MUST be 100%
6. Win tier identifiers: "WIN 1" through "WIN 5"

## Critical Boundary
**GameArchitect (6) = Dart game flow (frontend logic)**
**SlotIntelligence (18) = Rust AI engine (backend intelligence)**
These are DIFFERENT domains. Do not confuse them.

## Relationships
- **SlotLabEvents (4):** Game flow triggers events at state transitions
- **SlotLabAudio (5):** Audio playback controlled by game state
- **SlotIntelligence (18):** Rust backend for deterministic slot simulation
- **SlotLabUI (3):** UI renders game state from this agent's providers

## Forbidden
- NEVER hardcode win tier thresholds, labels, or visual properties
- NEVER manually call stopEvent for BIG_WIN — let composite handle it
- NEVER deduct balance during free spins
- NEVER allow behavior tree coverage below 100%
