/// Orchestration Engine Provider — SlotLab Middleware §10
///
/// Emotion-aware orchestration that shapes timing, gain, stereo width,
/// and conflict suppression based on emotional state and priority.
///
/// Inputs:
/// - Active behaviors (from Priority Engine)
/// - Priority results (from Priority Engine)
/// - Emotional state + intensity (from Emotional State Engine)
/// - Escalation index, chain depth, win magnitude
/// - Volatility curve, session fatigue
///
/// Output decisions per behavior:
/// - Trigger delay (ms)
/// - Gain bias (dB)
/// - Stereo width scaling (0.0-2.0)
/// - Spatial bias (pan offset)
/// - Transient shaping (attack modifier)
/// - Layer blend ratios
/// - Conflict suppression
/// - Emotional modulation
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §10

import 'package:flutter/foundation.dart';
import '../../models/behavior_tree_models.dart';
import 'emotional_state_provider.dart';

// =============================================================================
// ORCHESTRATION OUTPUT (per behavior node)
// =============================================================================

class OrchestrationDecision {
  /// Target behavior node ID
  final String nodeId;

  /// Trigger delay in ms (0 = immediate)
  final int triggerDelayMs;

  /// Gain bias in dB (additive to base gain)
  final double gainBiasDb;

  /// Stereo width scaling (1.0 = neutral, 0.0 = mono, 2.0 = extra wide)
  final double stereoWidthScale;

  /// Spatial pan offset (-1.0 = full left, 1.0 = full right)
  final double spatialBias;

  /// Transient attack modifier (1.0 = neutral, >1.0 = sharper, <1.0 = softer)
  final double transientShaping;

  /// Layer blend ratios (per-layer gain multiplier, 0.0-1.0)
  final Map<String, double> layerBlendRatios;

  /// Whether this behavior should be suppressed entirely
  final bool suppressed;

  /// Reason for suppression (if suppressed)
  final String? suppressionReason;

  const OrchestrationDecision({
    required this.nodeId,
    this.triggerDelayMs = 0,
    this.gainBiasDb = 0.0,
    this.stereoWidthScale = 1.0,
    this.spatialBias = 0.0,
    this.transientShaping = 1.0,
    this.layerBlendRatios = const {},
    this.suppressed = false,
    this.suppressionReason,
  });
}

// =============================================================================
// ORCHESTRATION CONTEXT (inputs for decision making)
// =============================================================================

class OrchestrationContext {
  /// Current emotional output
  final EmotionalOutput emotionalOutput;

  /// Current escalation index (0.0-1.0)
  final double escalationIndex;

  /// Current cascade chain depth
  final int chainDepth;

  /// Win magnitude (multiplier of bet)
  final double winMagnitude;

  /// Session fatigue (0.0-1.0)
  final double sessionFatigue;

  /// Volatility index (0.0-1.0)
  final double volatilityIndex;

  const OrchestrationContext({
    this.emotionalOutput = const EmotionalOutput(),
    this.escalationIndex = 0.0,
    this.chainDepth = 0,
    this.winMagnitude = 0.0,
    this.sessionFatigue = 0.0,
    this.volatilityIndex = 0.5,
  });
}

// =============================================================================
// PROVIDER
// =============================================================================

class OrchestrationEngineProvider extends ChangeNotifier {
  /// Current orchestration context
  OrchestrationContext _context = const OrchestrationContext();

  /// Last computed decisions (cached per frame)
  final Map<String, OrchestrationDecision> _decisions = {};

  /// Decision log for diagnostics
  final List<OrchestrationLogEntry> _log = [];

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  OrchestrationContext get context => _context;
  Map<String, OrchestrationDecision> get decisions => Map.unmodifiable(_decisions);

  /// Get decision for a specific node
  OrchestrationDecision? getDecision(String nodeId) => _decisions[nodeId];

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTEXT UPDATE
  // ═══════════════════════════════════════════════════════════════════════════

  void updateContext(OrchestrationContext context) {
    _context = context;
    notifyListeners();
  }

  void updateEmotionalOutput(EmotionalOutput output) {
    _context = OrchestrationContext(
      emotionalOutput: output,
      escalationIndex: _context.escalationIndex,
      chainDepth: _context.chainDepth,
      winMagnitude: _context.winMagnitude,
      sessionFatigue: _context.sessionFatigue,
      volatilityIndex: _context.volatilityIndex,
    );
    notifyListeners();
  }

  void updateEscalation({double? index, int? chainDepth, double? winMagnitude}) {
    _context = OrchestrationContext(
      emotionalOutput: _context.emotionalOutput,
      escalationIndex: index ?? _context.escalationIndex,
      chainDepth: chainDepth ?? _context.chainDepth,
      winMagnitude: winMagnitude ?? _context.winMagnitude,
      sessionFatigue: _context.sessionFatigue,
      volatilityIndex: _context.volatilityIndex,
    );
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ORCHESTRATION DECISIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Compute orchestration decision for a behavior node
  OrchestrationDecision orchestrate(BehaviorNode node) {
    final emotional = _context.emotionalOutput;

    // Base decision
    double gainBias = 0.0;
    double stereoWidth = 1.0;
    double spatialBias = 0.0;
    double transient = 1.0;
    int delay = 0;
    bool suppressed = false;
    String? suppressReason;

    // Emotional modulation
    gainBias += emotional.escalationBias * node.emotionalWeight * 3.0; // Up to ±3 dB
    stereoWidth *= emotional.stereoWidthMod;

    // Tension increases transient sharpness
    if (emotional.tension > 0.5) {
      transient *= 1.0 + (emotional.tension - 0.5) * 0.6; // Up to 1.3x
    }

    // Escalation increases gain for high-emotional-weight nodes
    if (_context.escalationIndex > 0.3 && node.emotionalWeight > 0.5) {
      gainBias += (_context.escalationIndex - 0.3) * 2.0;
    }

    // Chain depth pushes cascade sounds wider
    if (node.category == BehaviorCategory.cascade && _context.chainDepth > 1) {
      stereoWidth *= 1.0 + _context.chainDepth * 0.1;
      spatialBias = (_context.chainDepth % 2 == 0) ? 0.2 : -0.2; // Alternate L/R
    }

    // Win magnitude boosts win sounds
    if (node.category == BehaviorCategory.win && _context.winMagnitude > 5.0) {
      gainBias += (_context.winMagnitude / 50.0).clamp(0.0, 3.0);
      stereoWidth *= 1.0 + (_context.winMagnitude / 100.0).clamp(0.0, 0.5);
    }

    // Session fatigue reduces UI and low-priority sounds
    if (_context.sessionFatigue > 0.6) {
      if (node.category == BehaviorCategory.ui) {
        gainBias -= (_context.sessionFatigue - 0.6) * 6.0; // Up to -2.4 dB
      }
      if (node.basicParams.priorityClass == BehaviorPriorityClass.ambient) {
        gainBias -= (_context.sessionFatigue - 0.6) * 3.0;
      }
    }

    // High volatility + peak emotion → suppress ambient
    if (_context.volatilityIndex > 0.8 &&
        emotional.state == EmotionalState.peak &&
        node.basicParams.priorityClass == BehaviorPriorityClass.ambient) {
      suppressed = true;
      suppressReason = 'High volatility + Peak emotion: ambient suppressed';
    }

    // Afterglow → softer transients for all except win category
    if (emotional.state == EmotionalState.afterglow && node.category != BehaviorCategory.win) {
      transient *= 0.7;
    }

    final decision = OrchestrationDecision(
      nodeId: node.id,
      triggerDelayMs: delay,
      gainBiasDb: gainBias.clamp(-12.0, 12.0),
      stereoWidthScale: stereoWidth.clamp(0.0, 2.0),
      spatialBias: spatialBias.clamp(-1.0, 1.0),
      transientShaping: transient.clamp(0.3, 2.0),
      suppressed: suppressed,
      suppressionReason: suppressReason,
    );

    _decisions[node.id] = decision;

    // Log
    _log.add(OrchestrationLogEntry(
      nodeId: node.id,
      decision: decision,
      emotionalState: emotional.state,
      timestamp: DateTime.now(),
    ));
    if (_log.length > 300) _log.removeRange(0, 150);

    return decision;
  }

  /// Clear all cached decisions
  void clearDecisions() {
    _decisions.clear();
    notifyListeners();
  }

  /// Get diagnostic log
  List<OrchestrationLogEntry> get diagnosticLog => List.unmodifiable(_log);

  void clearLog() {
    _log.clear();
    notifyListeners();
  }
}

class OrchestrationLogEntry {
  final String nodeId;
  final OrchestrationDecision decision;
  final EmotionalState emotionalState;
  final DateTime timestamp;

  const OrchestrationLogEntry({
    required this.nodeId,
    required this.decision,
    required this.emotionalState,
    required this.timestamp,
  });
}
