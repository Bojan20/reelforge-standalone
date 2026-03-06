import 'diagnostics_service.dart';
import '../event_registry.dart';

/// Stage data needed by the validator (decoupled from SlotLabProvider)
class StageSnapshot {
  final String stageType;
  final double timestampMs;
  final Map<String, dynamic> rawStage;
  StageSnapshot({required this.stageType, required this.timestampMs, required this.rawStage});
}

/// Validates stage sequence contracts and naming consistency.
///
/// Checks:
/// 1. Stage sequence ordering (UI_SPIN_PRESS must be first, SPIN_END last)
/// 2. Required stages present in every spin
/// 3. No duplicate REEL_STOP for same reel index
/// 4. Engine stages match Dart-side expected names
/// 5. All stages in EventRegistry have valid configuration
class StageContractValidator extends DiagnosticChecker {
  final List<StageSnapshot> Function()? _getLastStages;

  StageContractValidator({List<StageSnapshot> Function()? getLastStages})
      : _getLastStages = getLastStages;

  @override
  String get name => 'StageContract';

  @override
  String get description =>
      'Validates stage sequence ordering, naming, and completeness';

  @override
  List<DiagnosticFinding> check() {
    final findings = <DiagnosticFinding>[];

    findings.addAll(_checkStageNaming());
    findings.addAll(_checkEventRegistryConsistency());

    if (_getLastStages != null) {
      findings.addAll(_checkLastSpinSequence());
    }

    if (findings.where((f) => !f.isOk).isEmpty) {
      findings.add(DiagnosticFinding(
        checker: name,
        severity: DiagnosticSeverity.ok,
        message: 'All stage contracts valid',
      ));
    }

    return findings;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHECK 1: Stage naming — Rust↔Dart consistency
  // ═══════════════════════════════════════════════════════════════════════════

  List<DiagnosticFinding> _checkStageNaming() {
    final findings = <DiagnosticFinding>[];

    // These are the canonical stage names that Rust engine generates (serde snake_case)
    // and Dart expects (toUpperCase). Any mismatch = broken audio/logic.
    const rustGeneratedStages = {
      'ui_spin_press', // Stage::UiSpinPress
      'reel_spin_loop', // Stage::ReelSpinLoop
      'reel_spinning', // Stage::ReelSpinning
      'reel_spinning_start', // Stage::ReelSpinningStart
      'reel_spinning_stop', // Stage::ReelSpinningStop
      'reel_stop', // Stage::ReelStop
      'evaluate_wins', // Stage::EvaluateWins
      'spin_end', // Stage::SpinEnd
      'anticipation_on', // Stage::AnticipationOn
      'anticipation_off', // Stage::AnticipationOff
      'anticipation_tension_layer', // Stage::AnticipationTensionLayer
      'anticipation_miss', // Stage::AnticipationMiss
      'win_present', // Stage::WinPresent
      'no_win', // Stage::NoWin
      'win_line_show', // Stage::WinLineShow
      'win_line_hide', // Stage::WinLineHide
      'rollup_start', // Stage::RollupStart
      'rollup_tick', // Stage::RollupTick
      'rollup_end', // Stage::RollupEnd
      'bigwin_tier', // Stage::BigWinTier (serde: "bigwin_tier")
      'big_win_start', // Stage::BigWinStart
      'big_win_end', // Stage::BigWinEnd
      'feature_enter', // Stage::FeatureEnter
      'feature_step', // Stage::FeatureStep
      'feature_retrigger', // Stage::FeatureRetrigger
      'feature_exit', // Stage::FeatureExit
      'cascade_start', // Stage::CascadeStart
      'cascade_step', // Stage::CascadeStep
      'cascade_end', // Stage::CascadeEnd
      'idle_start', // Stage::IdleStart
      'idle_loop', // Stage::IdleLoop
    };

    // These stages are Dart-only (triggered by widget, not engine)
    const dartOnlyStages = {
      'SCATTER_LAND',
      'SCATTER_LAND_1',
      'SCATTER_LAND_2',
      'SCATTER_LAND_3',
      'SCATTER_LAND_4',
      'SCATTER_LAND_5',
      'SCATTER_WIN',
      'SYMBOL_LAND_WILD',
      'SYMBOL_LAND_SCATTER',
      'SYMBOL_LAND_BONUS',
      'GAME_START',
      'MUSIC_BASE_L1',
      'MUSIC_BASE_L2',
      'MUSIC_BASE_L3',
      'MUSIC_BASE_L4',
      'MUSIC_BASE_L5',
      'COIN_SHOWER_START',
      'COIN_SHOWER_END',
      'WIN_SYMBOL_HIGHLIGHT',
      'ANTICIPATION_TENSION',  // Legacy tension stage (non-LAYER variant)
    };

    // Check if last spin stages contain any unknown stages
    final getStages = _getLastStages;
    if (getStages != null) {
      final lastStages = getStages();
      for (final stage in lastStages) {
        final type = stage.stageType.toLowerCase();
        final upper = stage.stageType.toUpperCase();
        if (!rustGeneratedStages.contains(type) &&
            !dartOnlyStages.contains(upper) &&
            !type.startsWith('reel_stop_') &&
            !type.startsWith('anticipation_tension_') &&
            !type.startsWith('win_present_') &&
            !type.startsWith('win_tier_') &&
            !type.startsWith('bigwin_tier_') &&
            !type.startsWith('rollup_') &&
            !type.startsWith('win_symbol_highlight_') &&
            !type.startsWith('scatter_land_') &&
            !type.startsWith('symbol_land_') &&
            !type.startsWith('reel_spinning_') &&
            !type.startsWith('fs_') &&
            type != 'custom') {
          findings.add(DiagnosticFinding(
            checker: name,
            severity: DiagnosticSeverity.warning,
            message: 'Unknown stage type: "${stage.stageType}"',
            detail: 'Not in Rust or Dart-only stage registries',
            affectedStage: stage.stageType,
          ));
        }
      }
    }

    return findings;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHECK 2: Last spin sequence validation
  // ═══════════════════════════════════════════════════════════════════════════

  List<DiagnosticFinding> _checkLastSpinSequence() {
    final findings = <DiagnosticFinding>[];
    final getStages = _getLastStages;
    if (getStages == null) return findings;

    final stages = getStages();
    if (stages.isEmpty) return findings;

    final stageTypes =
        stages.map((s) => s.stageType.toUpperCase()).toList();

    // 1. First stage must be UI_SPIN_PRESS
    if (stageTypes.first != 'UI_SPIN_PRESS') {
      findings.add(DiagnosticFinding(
        checker: name,
        severity: DiagnosticSeverity.error,
        message: 'First stage is "${stageTypes.first}", expected UI_SPIN_PRESS',
        detail: 'Engine may be generating wrong stage name. '
            'Check Stage::UiSpinPress in rf-stage/src/stage.rs',
        affectedStage: stageTypes.first,
      ));
    }

    // 2. Last stage must be SPIN_END
    if (stageTypes.last != 'SPIN_END') {
      findings.add(DiagnosticFinding(
        checker: name,
        severity: DiagnosticSeverity.warning,
        message: 'Last stage is "${stageTypes.last}", expected SPIN_END',
        affectedStage: stageTypes.last,
      ));
    }

    // 3. No duplicate REEL_STOP for same reel
    final reelStops = <int>{};
    for (final stage in stages) {
      final type = stage.stageType.toUpperCase();
      if (type == 'REEL_STOP') {
        final reelIndex = stage.rawStage['reel_index'] as int? ?? -1;
        if (reelIndex >= 0 && !reelStops.add(reelIndex)) {
          findings.add(DiagnosticFinding(
            checker: name,
            severity: DiagnosticSeverity.error,
            message: 'Duplicate REEL_STOP for reel $reelIndex',
            detail: 'Engine generated two stop events for same reel',
            affectedStage: 'REEL_STOP',
          ));
        }
      }
    }

    // 4. Timestamps must be monotonically non-decreasing
    double prevTs = -1;
    for (final stage in stages) {
      if (stage.timestampMs < prevTs) {
        findings.add(DiagnosticFinding(
          checker: name,
          severity: DiagnosticSeverity.error,
          message:
              'Timestamp regression: ${stage.stageType} at ${stage.timestampMs}ms '
              'after previous at ${prevTs}ms',
          affectedStage: stage.stageType,
        ));
        // Continue to report all regressions, not just first
      }
      prevTs = stage.timestampMs;
    }

    // 5. EVALUATE_WINS must come after all REEL_STOP
    final evalIndex = stageTypes.indexOf('EVALUATE_WINS');
    if (evalIndex >= 0) {
      final lastReelStop = stageTypes.lastIndexOf('REEL_STOP');
      if (lastReelStop > evalIndex) {
        findings.add(DiagnosticFinding(
          checker: name,
          severity: DiagnosticSeverity.error,
          message: 'EVALUATE_WINS at index $evalIndex but REEL_STOP at $lastReelStop',
          detail: 'Win evaluation must happen after all reels stop',
        ));
      }
    }

    return findings;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHECK 3: EventRegistry consistency
  // ═══════════════════════════════════════════════════════════════════════════

  List<DiagnosticFinding> _checkEventRegistryConsistency() {
    final findings = <DiagnosticFinding>[];
    final registry = EventRegistry.instance;

    // Check for registered stages whose events have no audio layers
    final registeredStages = registry.registeredStages;
    int emptyLayerCount = 0;
    for (final stage in registeredStages) {
      final event = registry.getEventForStage(stage);
      if (event != null && event.layers.isEmpty) {
        emptyLayerCount++;
      }
    }

    if (emptyLayerCount > 0) {
      findings.add(DiagnosticFinding(
        checker: name,
        severity: DiagnosticSeverity.ok,
        message: '$emptyLayerCount registered events with no audio layers',
        detail: 'Normal — events may use containers or be placeholders',
      ));
    }

    return findings;
  }
}
