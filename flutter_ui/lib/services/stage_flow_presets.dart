/// P-DSF Built-in Flow Presets — Factory preset graphs for common game types
///
/// 6 presets matching spec sections 6.1–6.6:
///   1. Classic 5-Reel Base Game
///   2. Cascade/Tumble Flow
///   3. Hold & Win Flow
///   4. Jackpot Progressive Flow
///   5. Free Spins Flow
///   6. Pick Bonus Flow
library;

import '../models/stage_flow_models.dart';

/// Factory for all built-in flow presets.
class StageFlowPresets {
  StageFlowPresets._();

  static final DateTime _epoch = DateTime(2026, 1, 1);

  static List<FlowPreset> getAll() => [
    classic5Reel(),
    cascadeTumble(),
    holdAndWin(),
    jackpotProgressive(),
    freeSpins(),
    pickBonus(),
  ];

  // ═════════════════════════════════════════════════════════════════════
  // 6.1 Classic 5-Reel Base Game
  // ═════════════════════════════════════════════════════════════════════

  static FlowPreset classic5Reel() {
    final nodes = <StageFlowNode>[
      _coreNode('n_spin_start', 'SPIN_START', x: 0, y: 200),
      _coreNode('n_reel_spin', 'REEL_SPIN_LOOP', x: 160, y: 200,
          timing: const TimingConfig(durationMs: 1000)),
      _coreNode('n_reel_stop_0', 'REEL_STOP_0', x: 320, y: 200,
          timing: const TimingConfig(durationMs: 100)),
      _coreNode('n_reel_stop_1', 'REEL_STOP_1', x: 440, y: 200,
          timing: const TimingConfig(delayMs: 370, durationMs: 100)),
      _coreNode('n_reel_stop_2', 'REEL_STOP_2', x: 560, y: 200,
          timing: const TimingConfig(delayMs: 370, durationMs: 100)),
      _coreNode('n_reel_stop_3', 'REEL_STOP_3', x: 680, y: 200,
          timing: const TimingConfig(delayMs: 370, durationMs: 100)),
      _coreNode('n_reel_stop_4', 'REEL_STOP_4', x: 800, y: 200,
          timing: const TimingConfig(delayMs: 370, durationMs: 100)),
      _coreNode('n_eval_wins', 'EVALUATE_WINS', x: 960, y: 200),
      // Gate: win > 0?
      _gateNode('n_gate_win', 'win_check', x: 1120, y: 200,
          enterCondition: 'win_amount > 0'),
      // Win path
      _stageNode('n_win_present', 'WIN_PRESENT', x: 1280, y: 100,
          timing: const TimingConfig(durationMs: 500)),
      // Gate: big win?
      _gateNode('n_gate_bigwin', 'bigwin_check', x: 1440, y: 100,
          enterCondition: 'win_ratio >= 20.0'),
      // Big win path
      _stageNode('n_bigwin_intro', 'BIG_WIN_INTRO', x: 1600, y: 0,
          timing: const TimingConfig(durationMs: 500)),
      _stageNode('n_bigwin_tier', 'BIG_WIN_TIER', x: 1760, y: 0,
          timing: const TimingConfig(durationMs: 4000)),
      _stageNode('n_bigwin_end', 'BIG_WIN_END', x: 1920, y: 0,
          timing: const TimingConfig(durationMs: 4000)),
      // Normal win: fork (parallel rollup + winline)
      _forkNode('n_fork_winpres', 'win_fork', x: 1600, y: 200),
      _stageNode('n_winline_show', 'WIN_LINE_SHOW', x: 1760, y: 140,
          timing: const TimingConfig(durationMs: 1050)),
      _stageNode('n_rollup_start', 'ROLLUP_START', x: 1760, y: 260,
          timing: const TimingConfig(durationMs: 1500)),
      _joinNode('n_join_winpres', 'win_join', x: 1920, y: 200),
      // Collect
      _stageNode('n_win_collect', 'WIN_COLLECT', x: 2080, y: 200,
          timing: const TimingConfig(durationMs: 300)),
      // End
      _coreNode('n_spin_end', 'SPIN_END', x: 2240, y: 200),
    ];

    final edges = <StageFlowEdge>[
      _edge('e1', 'n_spin_start', 'n_reel_spin'),
      _edge('e2', 'n_reel_spin', 'n_reel_stop_0'),
      _edge('e3', 'n_reel_stop_0', 'n_reel_stop_1'),
      _edge('e4', 'n_reel_stop_1', 'n_reel_stop_2'),
      _edge('e5', 'n_reel_stop_2', 'n_reel_stop_3'),
      _edge('e6', 'n_reel_stop_3', 'n_reel_stop_4'),
      _edge('e7', 'n_reel_stop_4', 'n_eval_wins'),
      _edge('e8', 'n_eval_wins', 'n_gate_win'),
      // Gate: win > 0 → true path
      _edgeTyped('e9', 'n_gate_win', 'n_win_present', EdgeType.onTrue),
      // Gate: win > 0 → false path → spin end
      _edgeTyped('e10', 'n_gate_win', 'n_spin_end', EdgeType.onFalse),
      // Win present → big win gate
      _edge('e11', 'n_win_present', 'n_gate_bigwin'),
      // Big win → true
      _edgeTyped('e12', 'n_gate_bigwin', 'n_bigwin_intro', EdgeType.onTrue),
      _edge('e13', 'n_bigwin_intro', 'n_bigwin_tier'),
      _edge('e14', 'n_bigwin_tier', 'n_bigwin_end'),
      _edge('e15', 'n_bigwin_end', 'n_win_collect'),
      // Normal win → fork
      _edgeTyped('e16', 'n_gate_bigwin', 'n_fork_winpres', EdgeType.onFalse),
      // Fork → parallel branches
      _edgeTyped('e17', 'n_fork_winpres', 'n_winline_show', EdgeType.parallel),
      _edgeTyped('e18', 'n_fork_winpres', 'n_rollup_start', EdgeType.parallel),
      // Parallel → join
      _edge('e19', 'n_winline_show', 'n_join_winpres'),
      _edge('e20', 'n_rollup_start', 'n_join_winpres'),
      // Join → collect
      _edge('e21', 'n_join_winpres', 'n_win_collect'),
      // Collect → end
      _edge('e22', 'n_win_collect', 'n_spin_end'),
    ];

    return _preset(
      'preset_classic_5reel',
      'Classic 5-Reel',
      'Standard 5-reel base game flow with big win branching and parallel rollup.',
      FlowPresetCategory.baseGame,
      nodes,
      edges,
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 6.2 Cascade/Tumble Flow
  // ═════════════════════════════════════════════════════════════════════

  static FlowPreset cascadeTumble() {
    final nodes = <StageFlowNode>[
      _coreNode('n_spin_start', 'SPIN_START', x: 0, y: 200),
      _coreNode('n_reel_spin', 'REEL_SPIN_LOOP', x: 160, y: 200,
          timing: const TimingConfig(durationMs: 1000)),
      _coreNode('n_reel_stop_0', 'REEL_STOP_0', x: 320, y: 200,
          timing: const TimingConfig(durationMs: 100)),
      _coreNode('n_reel_stop_1', 'REEL_STOP_1', x: 440, y: 200,
          timing: const TimingConfig(delayMs: 370, durationMs: 100)),
      _coreNode('n_reel_stop_2', 'REEL_STOP_2', x: 560, y: 200,
          timing: const TimingConfig(delayMs: 370, durationMs: 100)),
      _coreNode('n_reel_stop_3', 'REEL_STOP_3', x: 680, y: 200,
          timing: const TimingConfig(delayMs: 370, durationMs: 100)),
      _coreNode('n_reel_stop_4', 'REEL_STOP_4', x: 800, y: 200,
          timing: const TimingConfig(delayMs: 370, durationMs: 100)),
      _coreNode('n_eval_wins', 'EVALUATE_WINS', x: 960, y: 200),
      _gateNode('n_gate_win', 'win_check', x: 1120, y: 200,
          enterCondition: 'win_amount > 0'),
      _stageNode('n_win_line', 'WIN_LINE_SHOW', x: 1280, y: 100,
          timing: const TimingConfig(durationMs: 1050)),
      _stageNode('n_cascade_start', 'CASCADE_START', x: 1440, y: 100,
          timing: const TimingConfig(durationMs: 200)),
      _stageNode('n_symbol_pop', 'CASCADE_SYMBOL_POP', x: 1600, y: 100,
          timing: const TimingConfig(durationMs: 400)),
      _stageNode('n_tumble_drop', 'TUMBLE_DROP', x: 1760, y: 100,
          timing: const TimingConfig(durationMs: 500)),
      _stageNode('n_tumble_land', 'TUMBLE_LAND', x: 1920, y: 100,
          timing: const TimingConfig(durationMs: 200)),
      _gateNode('n_gate_cascade', 'cascade_check', x: 2080, y: 100,
          enterCondition: 'cascade_step <= 10 && win_amount > 0'),
      _stageNode('n_cascade_end', 'CASCADE_END', x: 2240, y: 200,
          timing: const TimingConfig(durationMs: 200)),
      _stageNode('n_rollup', 'ROLLUP_START', x: 2400, y: 200,
          timing: const TimingConfig(durationMs: 1500)),
      _stageNode('n_win_collect', 'WIN_COLLECT', x: 2560, y: 200,
          timing: const TimingConfig(durationMs: 300)),
      _coreNode('n_spin_end', 'SPIN_END', x: 2720, y: 200),
    ];

    final edges = <StageFlowEdge>[
      _edge('e1', 'n_spin_start', 'n_reel_spin'),
      _edge('e2', 'n_reel_spin', 'n_reel_stop_0'),
      _edge('e3', 'n_reel_stop_0', 'n_reel_stop_1'),
      _edge('e4', 'n_reel_stop_1', 'n_reel_stop_2'),
      _edge('e5', 'n_reel_stop_2', 'n_reel_stop_3'),
      _edge('e6', 'n_reel_stop_3', 'n_reel_stop_4'),
      _edge('e7', 'n_reel_stop_4', 'n_eval_wins'),
      _edge('e8', 'n_eval_wins', 'n_gate_win'),
      _edgeTyped('e9', 'n_gate_win', 'n_win_line', EdgeType.onTrue),
      _edgeTyped('e10', 'n_gate_win', 'n_spin_end', EdgeType.onFalse),
      _edge('e11', 'n_win_line', 'n_cascade_start'),
      _edge('e12', 'n_cascade_start', 'n_symbol_pop'),
      _edge('e13', 'n_symbol_pop', 'n_tumble_drop'),
      _edge('e14', 'n_tumble_drop', 'n_tumble_land'),
      _edge('e15', 'n_tumble_land', 'n_gate_cascade'),
      // Cascade continue → loop back to eval
      _edgeTyped('e16', 'n_gate_cascade', 'n_eval_wins', EdgeType.onTrue),
      // Cascade end
      _edgeTyped('e17', 'n_gate_cascade', 'n_cascade_end', EdgeType.onFalse),
      _edge('e18', 'n_cascade_end', 'n_rollup'),
      _edge('e19', 'n_rollup', 'n_win_collect'),
      _edge('e20', 'n_win_collect', 'n_spin_end'),
    ];

    return _preset(
      'preset_cascade_tumble',
      'Cascade / Tumble',
      'Tumble mechanics with symbol pop, drop, and cascade loop.',
      FlowPresetCategory.cascading,
      nodes,
      edges,
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 6.3 Hold & Win Flow
  // ═════════════════════════════════════════════════════════════════════

  static FlowPreset holdAndWin() {
    final nodes = <StageFlowNode>[
      _gateNode('n_gate_trigger', 'hold_trigger_check', x: 0, y: 200,
          enterCondition: 'bonus_count >= 6'),
      _stageNode('n_hold_trigger', 'HOLD_TRIGGER', x: 200, y: 100,
          timing: const TimingConfig(durationMs: 500)),
      _stageNode('n_hold_enter', 'HOLD_ENTER', x: 400, y: 100,
          timing: const TimingConfig(durationMs: 800)),
      _stageNode('n_hold_music', 'HOLD_MUSIC', x: 600, y: 100,
          timing: const TimingConfig.instant()),
      _gateNode('n_gate_spins', 'hold_spins_check', x: 800, y: 100,
          enterCondition: 'hold_spins_remaining > 0'),
      _stageNode('n_hold_spin', 'HOLD_SPIN', x: 1000, y: 50,
          timing: const TimingConfig(durationMs: 500)),
      _stageNode('n_hold_stop', 'HOLD_RESPIN_STOP', x: 1200, y: 50,
          timing: const TimingConfig(durationMs: 300)),
      _gateNode('n_gate_coin', 'coin_landed_check', x: 1400, y: 50,
          enterCondition: 'bonus_count > 0'),
      _stageNode('n_coin_land', 'HOLD_SYMBOL_LAND', x: 1600, y: 0,
          timing: const TimingConfig(durationMs: 400)),
      _gateNode('n_gate_grid', 'grid_full_check', x: 1800, y: 100,
          enterCondition: 'balance > 0'),
      _stageNode('n_grid_full', 'HOLD_GRID_FULL', x: 2000, y: 0,
          timing: const TimingConfig(durationMs: 1000)),
      _stageNode('n_jackpot_grand', 'JACKPOT_GRAND', x: 2200, y: 0,
          timing: const TimingConfig(durationMs: 3000)),
      _stageNode('n_hold_exit', 'HOLD_EXIT', x: 2000, y: 200,
          timing: const TimingConfig(durationMs: 500)),
    ];

    final edges = <StageFlowEdge>[
      _edgeTyped('e1', 'n_gate_trigger', 'n_hold_trigger', EdgeType.onTrue),
      _edge('e2', 'n_hold_trigger', 'n_hold_enter'),
      _edge('e3', 'n_hold_enter', 'n_hold_music'),
      _edge('e4', 'n_hold_music', 'n_gate_spins'),
      _edgeTyped('e5', 'n_gate_spins', 'n_hold_spin', EdgeType.onTrue),
      _edgeTyped('e6', 'n_gate_spins', 'n_gate_grid', EdgeType.onFalse),
      _edge('e7', 'n_hold_spin', 'n_hold_stop'),
      _edge('e8', 'n_hold_stop', 'n_gate_coin'),
      _edgeTyped('e9', 'n_gate_coin', 'n_coin_land', EdgeType.onTrue),
      _edgeTyped('e10', 'n_gate_coin', 'n_gate_spins', EdgeType.onFalse),
      _edge('e11', 'n_coin_land', 'n_gate_spins'),
      _edgeTyped('e12', 'n_gate_grid', 'n_grid_full', EdgeType.onTrue),
      _edgeTyped('e13', 'n_gate_grid', 'n_hold_exit', EdgeType.onFalse),
      _edge('e14', 'n_grid_full', 'n_jackpot_grand'),
      _edge('e15', 'n_jackpot_grand', 'n_hold_exit'),
    ];

    return _preset(
      'preset_hold_and_win',
      'Hold & Win',
      'Hold & Win / Cash on Reels feature with respin loop and jackpot grand.',
      FlowPresetCategory.holdAndWin,
      nodes,
      edges,
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 6.4 Jackpot Progressive Flow
  // ═════════════════════════════════════════════════════════════════════

  static FlowPreset jackpotProgressive() {
    final nodes = <StageFlowNode>[
      _stageNode('n_jp_trigger', 'JACKPOT_TRIGGER', x: 0, y: 200,
          timing: const TimingConfig(durationMs: 500)),
      _stageNode('n_jp_buildup', 'JACKPOT_BUILDUP', x: 200, y: 200,
          timing: const TimingConfig(durationMs: 2000)),
      _gateNode('n_gate_level', 'jackpot_level_check', x: 400, y: 200,
          enterCondition: "jackpot_level != 'none'"),
      _stageNode('n_jp_mini', 'JACKPOT_MINI', x: 600, y: 0,
          timing: const TimingConfig(durationMs: 1500),
          enterCondition: "jackpot_level == 'mini'"),
      _stageNode('n_jp_minor', 'JACKPOT_MINOR', x: 600, y: 100,
          timing: const TimingConfig(durationMs: 2000),
          enterCondition: "jackpot_level == 'minor'"),
      _stageNode('n_jp_major', 'JACKPOT_MAJOR', x: 600, y: 200,
          timing: const TimingConfig(durationMs: 3000),
          enterCondition: "jackpot_level == 'major'"),
      _stageNode('n_jp_grand', 'JACKPOT_GRAND', x: 600, y: 300,
          timing: const TimingConfig(durationMs: 5000),
          enterCondition: "jackpot_level == 'grand'"),
      _stageNode('n_jp_celebration', 'JACKPOT_CELEBRATION', x: 800, y: 300,
          timing: const TimingConfig(durationMs: 3000)),
      _stageNode('n_jp_present', 'JACKPOT_PRESENT', x: 1000, y: 200,
          timing: const TimingConfig(durationMs: 2000)),
      _stageNode('n_jp_reveal', 'JACKPOT_REVEAL', x: 1200, y: 200,
          timing: const TimingConfig(durationMs: 1500)),
      _stageNode('n_jp_end', 'JACKPOT_END', x: 1400, y: 200,
          timing: const TimingConfig(durationMs: 500)),
    ];

    final edges = <StageFlowEdge>[
      _edge('e1', 'n_jp_trigger', 'n_jp_buildup'),
      _edge('e2', 'n_jp_buildup', 'n_gate_level'),
      _edgeTyped('e3', 'n_gate_level', 'n_jp_mini', EdgeType.onTrue,
          condition: "jackpot_level == 'mini'"),
      _edgeTyped('e4', 'n_gate_level', 'n_jp_minor', EdgeType.onTrue,
          condition: "jackpot_level == 'minor'"),
      _edgeTyped('e5', 'n_gate_level', 'n_jp_major', EdgeType.onTrue,
          condition: "jackpot_level == 'major'"),
      _edgeTyped('e6', 'n_gate_level', 'n_jp_grand', EdgeType.onTrue,
          condition: "jackpot_level == 'grand'"),
      _edge('e7', 'n_jp_mini', 'n_jp_present'),
      _edge('e8', 'n_jp_minor', 'n_jp_present'),
      _edge('e9', 'n_jp_major', 'n_jp_present'),
      _edge('e10', 'n_jp_grand', 'n_jp_celebration'),
      _edge('e11', 'n_jp_celebration', 'n_jp_present'),
      _edge('e12', 'n_jp_present', 'n_jp_reveal'),
      _edge('e13', 'n_jp_reveal', 'n_jp_end'),
    ];

    return _preset(
      'preset_jackpot_progressive',
      'Jackpot Progressive',
      'Multi-tier jackpot reveal with buildup, level routing, and celebration.',
      FlowPresetCategory.jackpotPresentation,
      nodes,
      edges,
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 6.5 Free Spins Flow
  // ═════════════════════════════════════════════════════════════════════

  static FlowPreset freeSpins() {
    final nodes = <StageFlowNode>[
      _stageNode('n_fs_trigger', 'FS_TRIGGER', x: 0, y: 200,
          timing: const TimingConfig(durationMs: 500)),
      _stageNode('n_fs_enter', 'FS_ENTER', x: 200, y: 200,
          timing: const TimingConfig(durationMs: 1000)),
      _stageNode('n_fs_music', 'FS_MUSIC', x: 400, y: 200,
          timing: const TimingConfig.instant()),
      _gateNode('n_gate_fs', 'fs_remaining_check', x: 600, y: 200,
          enterCondition: 'is_free_spin'),
      _stageNode('n_fs_spin', 'FS_SPIN_START', x: 800, y: 200,
          timing: const TimingConfig.instant()),
      _coreNode('n_reel_spin', 'REEL_SPIN_LOOP', x: 1000, y: 200,
          timing: const TimingConfig(durationMs: 1000)),
      _coreNode('n_reel_stop_0', 'REEL_STOP_0', x: 1160, y: 200,
          timing: const TimingConfig(durationMs: 100)),
      _coreNode('n_reel_stop_1', 'REEL_STOP_1', x: 1280, y: 200,
          timing: const TimingConfig(delayMs: 370, durationMs: 100)),
      _coreNode('n_reel_stop_2', 'REEL_STOP_2', x: 1400, y: 200,
          timing: const TimingConfig(delayMs: 370, durationMs: 100)),
      _coreNode('n_reel_stop_3', 'REEL_STOP_3', x: 1520, y: 200,
          timing: const TimingConfig(delayMs: 370, durationMs: 100)),
      _coreNode('n_reel_stop_4', 'REEL_STOP_4', x: 1640, y: 200,
          timing: const TimingConfig(delayMs: 370, durationMs: 100)),
      _coreNode('n_eval_wins', 'EVALUATE_WINS', x: 1800, y: 200),
      _gateNode('n_gate_retrigger', 'retrigger_check', x: 2000, y: 100,
          enterCondition: 'scatter_count >= 3 && is_free_spin'),
      _stageNode('n_fs_retrigger', 'FS_RETRIGGER', x: 2200, y: 100,
          timing: const TimingConfig(durationMs: 1000)),
      _gateNode('n_gate_fs_win', 'fs_win_check', x: 2000, y: 300,
          enterCondition: 'win_amount > 0'),
      _stageNode('n_win_present', 'WIN_PRESENT', x: 2200, y: 300,
          timing: const TimingConfig(durationMs: 500)),
      _stageNode('n_rollup', 'ROLLUP_START', x: 2400, y: 300,
          timing: const TimingConfig(durationMs: 1500)),
      _stageNode('n_win_collect', 'WIN_COLLECT', x: 2600, y: 300,
          timing: const TimingConfig(durationMs: 300)),
      _stageNode('n_fs_spin_end', 'FS_SPIN_END', x: 2800, y: 200,
          timing: const TimingConfig.instant()),
      _stageNode('n_fs_exit', 'FS_EXIT', x: 3000, y: 200,
          timing: const TimingConfig(durationMs: 1000)),
    ];

    final edges = <StageFlowEdge>[
      _edge('e1', 'n_fs_trigger', 'n_fs_enter'),
      _edge('e2', 'n_fs_enter', 'n_fs_music'),
      _edge('e3', 'n_fs_music', 'n_gate_fs'),
      _edgeTyped('e4', 'n_gate_fs', 'n_fs_spin', EdgeType.onTrue),
      _edgeTyped('e5', 'n_gate_fs', 'n_fs_exit', EdgeType.onFalse),
      _edge('e6', 'n_fs_spin', 'n_reel_spin'),
      _edge('e7', 'n_reel_spin', 'n_reel_stop_0'),
      _edge('e8', 'n_reel_stop_0', 'n_reel_stop_1'),
      _edge('e9', 'n_reel_stop_1', 'n_reel_stop_2'),
      _edge('e10', 'n_reel_stop_2', 'n_reel_stop_3'),
      _edge('e11', 'n_reel_stop_3', 'n_reel_stop_4'),
      _edge('e12', 'n_reel_stop_4', 'n_eval_wins'),
      _edge('e13', 'n_eval_wins', 'n_gate_retrigger'),
      _edgeTyped('e14', 'n_gate_retrigger', 'n_fs_retrigger', EdgeType.onTrue),
      _edgeTyped('e15', 'n_gate_retrigger', 'n_gate_fs_win', EdgeType.onFalse),
      _edge('e16', 'n_fs_retrigger', 'n_gate_fs_win'),
      _edgeTyped('e17', 'n_gate_fs_win', 'n_win_present', EdgeType.onTrue),
      _edgeTyped('e18', 'n_gate_fs_win', 'n_fs_spin_end', EdgeType.onFalse),
      _edge('e19', 'n_win_present', 'n_rollup'),
      _edge('e20', 'n_rollup', 'n_win_collect'),
      _edge('e21', 'n_win_collect', 'n_fs_spin_end'),
      _edge('e22', 'n_fs_spin_end', 'n_gate_fs'),
      _edge('e23', 'n_fs_exit', 'n_fs_exit'), // Terminal — self-reference removed
    ];

    // Remove self-referencing edge
    final cleanEdges = edges.where((e) => e.sourceNodeId != e.targetNodeId).toList();

    return _preset(
      'preset_free_spins',
      'Free Spins',
      'Free spins feature with retrigger, per-spin win handling, and exit.',
      FlowPresetCategory.freeSpins,
      nodes,
      cleanEdges,
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 6.6 Pick Bonus Flow
  // ═════════════════════════════════════════════════════════════════════

  static FlowPreset pickBonus() {
    final nodes = <StageFlowNode>[
      _stageNode('n_bonus_trigger', 'BONUS_TRIGGER', x: 0, y: 200,
          timing: const TimingConfig(durationMs: 500)),
      _stageNode('n_bonus_enter', 'BONUS_ENTER', x: 200, y: 200,
          timing: const TimingConfig(durationMs: 800)),
      _gateNode('n_gate_picks', 'picks_remaining_check', x: 400, y: 200,
          enterCondition: 'bonus_count > 0'),
      _stageNode('n_bonus_step', 'BONUS_STEP', x: 600, y: 200,
          timing: const TimingConfig(durationMs: 500)),
      _stageNode('n_bonus_reveal', 'BONUS_REVEAL', x: 800, y: 200,
          timing: const TimingConfig(durationMs: 800)),
      _gateNode('n_gate_grand', 'grand_prize_check', x: 1000, y: 200,
          enterCondition: 'win_ratio >= 100.0'),
      _stageNode('n_bonus_exit', 'BONUS_EXIT', x: 1200, y: 200,
          timing: const TimingConfig(durationMs: 500)),
      _stageNode('n_win_present', 'WIN_PRESENT', x: 1400, y: 200,
          timing: const TimingConfig(durationMs: 500)),
      _stageNode('n_rollup', 'ROLLUP_START', x: 1600, y: 200,
          timing: const TimingConfig(durationMs: 1500)),
      _stageNode('n_win_collect', 'WIN_COLLECT', x: 1800, y: 200,
          timing: const TimingConfig(durationMs: 300)),
    ];

    final edges = <StageFlowEdge>[
      _edge('e1', 'n_bonus_trigger', 'n_bonus_enter'),
      _edge('e2', 'n_bonus_enter', 'n_gate_picks'),
      _edgeTyped('e3', 'n_gate_picks', 'n_bonus_step', EdgeType.onTrue),
      _edgeTyped('e4', 'n_gate_picks', 'n_bonus_exit', EdgeType.onFalse),
      _edge('e5', 'n_bonus_step', 'n_bonus_reveal'),
      _edge('e6', 'n_bonus_reveal', 'n_gate_grand'),
      _edgeTyped('e7', 'n_gate_grand', 'n_bonus_exit', EdgeType.onTrue),
      _edgeTyped('e8', 'n_gate_grand', 'n_gate_picks', EdgeType.onFalse),
      _edge('e9', 'n_bonus_exit', 'n_win_present'),
      _edge('e10', 'n_win_present', 'n_rollup'),
      _edge('e11', 'n_rollup', 'n_win_collect'),
    ];

    return _preset(
      'preset_pick_bonus',
      'Pick Bonus',
      'Pick bonus feature with reveal loop and grand prize early exit.',
      FlowPresetCategory.bonusGame,
      nodes,
      edges,
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════════

  static StageFlowNode _coreNode(
    String id,
    String stageId, {
    required double x,
    required double y,
    TimingConfig timing = const TimingConfig(),
  }) {
    return StageFlowNode(
      id: id,
      stageId: stageId,
      type: StageFlowNodeType.stage,
      layer: FlowLayer.engineCore,
      locked: true,
      timing: timing,
      x: x,
      y: y,
    );
  }

  static StageFlowNode _stageNode(
    String id,
    String stageId, {
    required double x,
    required double y,
    TimingConfig timing = const TimingConfig(),
    String? enterCondition,
  }) {
    return StageFlowNode(
      id: id,
      stageId: stageId,
      type: StageFlowNodeType.stage,
      layer: FlowLayer.audioMapping,
      timing: timing,
      enterCondition: enterCondition,
      x: x,
      y: y,
    );
  }

  static StageFlowNode _gateNode(
    String id,
    String stageId, {
    required double x,
    required double y,
    String? enterCondition,
  }) {
    return StageFlowNode(
      id: id,
      stageId: stageId,
      type: StageFlowNodeType.gate,
      layer: FlowLayer.audioMapping,
      enterCondition: enterCondition,
      x: x,
      y: y,
    );
  }

  static StageFlowNode _forkNode(
    String id,
    String stageId, {
    required double x,
    required double y,
  }) {
    return StageFlowNode(
      id: id,
      stageId: stageId,
      type: StageFlowNodeType.fork,
      layer: FlowLayer.audioMapping,
      x: x,
      y: y,
    );
  }

  static StageFlowNode _joinNode(
    String id,
    String stageId, {
    required double x,
    required double y,
  }) {
    return StageFlowNode(
      id: id,
      stageId: stageId,
      type: StageFlowNodeType.join,
      layer: FlowLayer.audioMapping,
      x: x,
      y: y,
    );
  }

  static StageFlowEdge _edge(String id, String source, String target) {
    return StageFlowEdge(id: id, sourceNodeId: source, targetNodeId: target);
  }

  static StageFlowEdge _edgeTyped(
    String id,
    String source,
    String target,
    EdgeType type, {
    String? condition,
  }) {
    return StageFlowEdge(
      id: id,
      sourceNodeId: source,
      targetNodeId: target,
      type: type,
      condition: condition,
    );
  }

  static FlowPreset _preset(
    String id,
    String name,
    String description,
    FlowPresetCategory category,
    List<StageFlowNode> nodes,
    List<StageFlowEdge> edges,
  ) {
    return FlowPreset(
      id: id,
      name: name,
      description: description,
      category: category,
      graph: StageFlowGraph(
        id: '${id}_graph',
        name: name,
        description: description,
        nodes: nodes,
        edges: edges,
        variables: BuiltInRuntimeVariables.all,
        createdAt: _epoch,
        modifiedAt: _epoch,
      ),
      createdAt: _epoch,
      isBuiltIn: true,
    );
  }
}
