/// Wild Features Executor — Runtime logic for wild symbol mechanics
///
/// Handles: sticky wilds, expanding wilds, walking wilds, stacked wilds,
/// random wilds, multiplier wilds. These are modifier features that alter
/// the grid before/after evaluation, not a separate game state.
library;

import '../../../models/game_flow_models.dart';
import '../../../src/rust/native_ffi.dart' show SlotLabSpinResult;
import '../game_flow_provider.dart';

class WildFeaturesExecutor extends FeatureExecutor {
  @override
  String get blockId => 'wild_features';

  @override
  int get priority => 55; // Just above cascade

  // ─── Config ──────────────────────────────────────────────────────────────
  bool _hasStickyWilds = false;
  bool _hasExpandingWilds = false;
  bool _hasWalkingWilds = false;
  bool _hasStackedWilds = false;
  bool _hasRandomWilds = false;
  bool _hasMultiplierWilds = false;
  int _stickyDuration = 3; // Spins before sticky wild disappears (0 = permanent)
  String _walkDirection = 'left'; // left, right, random
  int _randomWildCount = 3; // Max random wilds per spin
  double _wildMultiplier = 2.0; // Multiplier on wild-included wins
  bool _activeInBaseGame = true;
  bool _activeInFreeSpins = true;
  int _wildSymbolId = 10;

  // ─── Runtime state ────────────────────────────────────────────────────
  final List<_StickyWildPosition> _stickyWildPositions = [];
  final List<_WalkingWildPosition> _walkingWildPositions = [];

  @override
  void configure(Map<String, dynamic> options) {
    _hasStickyWilds = options['hasStickyWilds'] as bool? ?? false;
    _hasExpandingWilds = options['hasExpandingWilds'] as bool? ?? false;
    _hasWalkingWilds = options['hasWalkingWilds'] as bool? ?? false;
    _hasStackedWilds = options['hasStackedWilds'] as bool? ?? false;
    _hasRandomWilds = options['hasRandomWilds'] as bool? ?? false;
    _hasMultiplierWilds = options['hasMultiplierWilds'] as bool? ?? false;
    _stickyDuration = options['stickyDuration'] as int? ?? 3;
    _walkDirection = options['walkDirection'] as String? ?? 'left';
    _randomWildCount = options['randomWildCount'] as int? ?? 3;
    _wildMultiplier =
        (options['wildMultiplier'] as num?)?.toDouble() ?? 2.0;
    _activeInBaseGame = options['activeInBaseGame'] as bool? ?? true;
    _activeInFreeSpins = options['activeInFreeSpins'] as bool? ?? true;
    _wildSymbolId = options['wildSymbolId'] as int? ?? 10;
  }

  @override
  bool shouldTrigger(SpinContext context) {
    // Check if active in current state
    if (context.currentState == GameFlowState.baseGame && !_activeInBaseGame) {
      return false;
    }
    if (context.currentState == GameFlowState.freeSpins &&
        !_activeInFreeSpins) {
      return false;
    }

    // Only trigger in states where wilds apply
    if (context.currentState != GameFlowState.baseGame &&
        context.currentState != GameFlowState.freeSpins) {
      return false;
    }

    // Check if wilds are present on the grid
    if (context.wildCount > 0) return true;

    // Random wilds can trigger even without wilds on grid
    if (_hasRandomWilds) return true;

    // Walking wilds may still be active from previous spin
    if (_hasWalkingWilds && _walkingWildPositions.isNotEmpty) return true;

    // Sticky wilds still on grid
    if (_hasStickyWilds && _stickyWildPositions.isNotEmpty) return true;

    return false;
  }

  @override
  FeatureState enter(TriggerContext context) {
    return FeatureState(
      featureId: 'wild_features',
      currentMultiplier: _hasMultiplierWilds ? _wildMultiplier : 1.0,
      customData: {
        'hasStickyWilds': _hasStickyWilds,
        'hasExpandingWilds': _hasExpandingWilds,
        'hasWalkingWilds': _hasWalkingWilds,
        'hasStackedWilds': _hasStackedWilds,
        'hasRandomWilds': _hasRandomWilds,
        'hasMultiplierWilds': _hasMultiplierWilds,
        'stickyPositions': _stickyWildPositions
            .map((p) => {'reel': p.reel, 'row': p.row, 'remaining': p.remaining})
            .toList(),
        'walkingPositions': _walkingWildPositions
            .map((p) => {'reel': p.reel, 'row': p.row})
            .toList(),
      },
    );
  }

  @override
  FeatureStepResult step(SlotLabSpinResult result, FeatureState currentState) {
    final audioStages = <String>[];
    final gridMods = <String>{};

    // 1. Process sticky wilds — decrement counters, remove expired
    if (_hasStickyWilds) {
      _processStickyWilds(result, audioStages);
    }

    // 2. Process walking wilds — move in direction
    if (_hasWalkingWilds) {
      _processWalkingWilds(result, audioStages);
    }

    // 3. Detect new wilds from result grid
    _detectNewWilds(result, audioStages);

    // 4. Expanding wilds — expand any wild to fill its reel
    if (_hasExpandingWilds) {
      _processExpandingWilds(result, audioStages, gridMods);
    }

    // Wild features don't "continue" as a state — they apply and return
    final newState = currentState.copyWith(
      customData: {
        ...currentState.customData,
        'stickyPositions': _stickyWildPositions
            .map((p) => {'reel': p.reel, 'row': p.row, 'remaining': p.remaining})
            .toList(),
        'walkingPositions': _walkingWildPositions
            .map((p) => {'reel': p.reel, 'row': p.row})
            .toList(),
      },
    );

    return FeatureStepResult(
      updatedState: newState,
      shouldContinue: false, // Wild features exit after processing
      audioStages: audioStages,
      gridModification: gridMods.isNotEmpty
          ? GridModification(
              removedPositions: gridMods,
              removalStyle: 'wild_transform',
              fillStyle: 'none',
              delayMs: 200,
            )
          : null,
    );
  }

  void _processStickyWilds(
      SlotLabSpinResult result, List<String> audioStages) {
    _stickyWildPositions.removeWhere((pos) {
      if (_stickyDuration > 0) {
        pos.remaining--;
        if (pos.remaining <= 0) {
          audioStages.add('WILD_STICKY_EXPIRE');
          return true;
        }
      }
      return false;
    });
  }

  void _processWalkingWilds(
      SlotLabSpinResult result, List<String> audioStages) {
    final toRemove = <_WalkingWildPosition>[];

    for (final pos in _walkingWildPositions) {
      switch (_walkDirection) {
        case 'left':
          pos.reel--;
        case 'right':
          pos.reel++;
        case 'random':
          // 50/50 left or right — engine decides
          pos.reel--;
      }

      // Remove if walked off grid
      if (pos.reel < 0 || pos.reel >= result.grid.length) {
        toRemove.add(pos);
        audioStages.add('WILD_WALK_OFF');
      } else {
        audioStages.add('WILD_WALK_STEP');
      }
    }

    for (final rem in toRemove) {
      _walkingWildPositions.remove(rem);
    }
  }

  void _detectNewWilds(SlotLabSpinResult result, List<String> audioStages) {
    for (int reel = 0; reel < result.grid.length; reel++) {
      for (int row = 0; row < result.grid[reel].length; row++) {
        if (result.grid[reel][row] == _wildSymbolId) {
          // Register sticky wild
          if (_hasStickyWilds) {
            final exists = _stickyWildPositions
                .any((p) => p.reel == reel && p.row == row);
            if (!exists) {
              _stickyWildPositions.add(_StickyWildPosition(
                reel: reel,
                row: row,
                remaining: _stickyDuration,
              ));
              audioStages.add('WILD_STICKY_PLACE');
            }
          }

          // Register walking wild
          if (_hasWalkingWilds) {
            final exists = _walkingWildPositions
                .any((p) => p.reel == reel && p.row == row);
            if (!exists) {
              _walkingWildPositions.add(_WalkingWildPosition(
                reel: reel,
                row: row,
              ));
              audioStages.add('WILD_WALK_CREATE');
            }
          }
        }
      }
    }
  }

  void _processExpandingWilds(
      SlotLabSpinResult result,
      List<String> audioStages,
      Set<String> gridMods) {
    for (int reel = 0; reel < result.grid.length; reel++) {
      bool hasWild = false;
      for (int row = 0; row < result.grid[reel].length; row++) {
        if (result.grid[reel][row] == _wildSymbolId) {
          hasWild = true;
          break;
        }
      }
      if (hasWild) {
        // Mark entire reel as wild
        for (int row = 0; row < result.grid[reel].length; row++) {
          gridMods.add('$reel,$row');
        }
        audioStages.add('WILD_EXPAND');
      }
    }
  }

  @override
  FeatureExitResult exit(FeatureState finalState) {
    return const FeatureExitResult(
      totalWin: 0, // Wild features don't generate own wins
      audioStages: [],
      offerGamble: false,
    );
  }

  @override
  ModifiedWinResult modifyWin(double baseWinAmount, FeatureState state) {
    if (!_hasMultiplierWilds || state.currentMultiplier <= 1.0) {
      return ModifiedWinResult(
        originalAmount: baseWinAmount,
        finalAmount: baseWinAmount,
      );
    }

    return ModifiedWinResult(
      originalAmount: baseWinAmount,
      finalAmount: baseWinAmount * state.currentMultiplier,
      appliedMultiplier: state.currentMultiplier,
      multiplierSources: ['Wild: ${state.currentMultiplier}x'],
    );
  }

  @override
  String? getCurrentAudioStage(FeatureState state) {
    return null; // Wild features don't have persistent audio stage
  }

  @override
  void dispose() {
    _stickyWildPositions.clear();
    _walkingWildPositions.clear();
    super.dispose();
  }
}

// ─── Internal position tracking ────────────────────────────────────────────

class _StickyWildPosition {
  final int reel;
  final int row;
  int remaining;

  _StickyWildPosition({
    required this.reel,
    required this.row,
    required this.remaining,
  });
}

class _WalkingWildPosition {
  int reel;
  final int row;

  _WalkingWildPosition({
    required this.reel,
    required this.row,
  });
}
