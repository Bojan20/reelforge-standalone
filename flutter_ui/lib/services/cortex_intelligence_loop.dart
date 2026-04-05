/// CORTEX Intelligence Loop — The Brain That SEES and THINKS
///
/// Combines Vision (eyes) + AI Mixing (analysis) + MixerProvider (hands)
/// into a continuous intelligence loop:
///
/// 1. SEES — captures mixer/timeline state via CortexVisionService
/// 2. THINKS — analyzes what it sees via AiMixingService
/// 3. ACTS — applies suggestions via MixerProvider (when approved)
/// 4. LEARNS — tracks which suggestions helped (acceptance rate)
///
/// The loop runs periodically or on-demand. It's the first step toward
/// CORTEX being truly autonomous — not just responding to commands,
/// but proactively detecting and solving mixing problems.
///
/// Created: 2026-04-05 (CORTEX Intelligence)
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ai_mixing_service.dart';
import 'cortex_vision_service.dart';
import '../providers/mixer_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// INTELLIGENCE EVENT — What the loop observed and decided
// ═══════════════════════════════════════════════════════════════════════════

/// A single intelligence cycle result
class IntelligenceCycleResult {
  final DateTime timestamp;
  final int tracksAnalyzed;
  final int suggestionsGenerated;
  final int criticalIssues;
  final double mixScore;
  final GenreProfile detectedGenre;
  final String? visionSnapshotPath;
  final Duration analysisTime;

  const IntelligenceCycleResult({
    required this.timestamp,
    required this.tracksAnalyzed,
    required this.suggestionsGenerated,
    required this.criticalIssues,
    required this.mixScore,
    required this.detectedGenre,
    this.visionSnapshotPath,
    required this.analysisTime,
  });

  bool get hasCriticalIssues => criticalIssues > 0;

  @override
  String toString() =>
      'IntelligenceCycle($tracksAnalyzed tracks, score=$mixScore, '
      '${suggestionsGenerated} suggestions, ${criticalIssues} critical)';
}

// ═══════════════════════════════════════════════════════════════════════════
// CORTEX INTELLIGENCE LOOP
// ═══════════════════════════════════════════════════════════════════════════

/// The brain loop that connects CORTEX's eyes (vision) to its
/// analytical mind (AI mixing) and its hands (mixer provider).
class CortexIntelligenceLoop extends ChangeNotifier {
  CortexIntelligenceLoop._();
  static final instance = CortexIntelligenceLoop._();

  // ─── Dependencies ──────────────────────────────────────────────────────

  final CortexVisionService _vision = CortexVisionService.instance;
  final AiMixingService _mixing = AiMixingService.instance;
  MixerProvider? _mixer;

  // ─── State ─────────────────────────────────────────────────────────────

  Timer? _loopTimer;
  bool _running = false;
  bool _analyzing = false;

  /// History of intelligence cycles (most recent first)
  final List<IntelligenceCycleResult> _history = [];
  static const int _maxHistory = 100;

  /// Statistics
  int _totalCycles = 0;
  int _totalSuggestions = 0;
  int _appliedSuggestions = 0;

  // ─── Getters ───────────────────────────────────────────────────────────

  bool get isRunning => _running;
  bool get isAnalyzing => _analyzing;
  List<IntelligenceCycleResult> get history => List.unmodifiable(_history);
  IntelligenceCycleResult? get lastResult => _history.isNotEmpty ? _history.first : null;
  int get totalCycles => _totalCycles;
  int get totalSuggestions => _totalSuggestions;
  int get appliedSuggestions => _appliedSuggestions;
  double get acceptanceRate =>
      _totalSuggestions > 0 ? _appliedSuggestions / _totalSuggestions : 0.0;

  // ─── Lifecycle ─────────────────────────────────────────────────────────

  /// Connect the loop to a MixerProvider (required for analysis)
  void connect(MixerProvider mixer) {
    _mixer = mixer;
    _mixing.connectMixer(mixer);
  }

  /// Disconnect from mixer
  void disconnect() {
    stop();
    _mixer = null;
    _mixing.disconnectMixer();
  }

  /// Start the intelligence loop with periodic analysis
  ///
  /// Default interval: 30 seconds. The loop:
  /// 1. Captures a vision snapshot of the mixer
  /// 2. Pulls live metering data from MixerProvider
  /// 3. Runs AI analysis
  /// 4. Stores results for UI display
  void start({Duration interval = const Duration(seconds: 30)}) {
    if (_running) return;
    if (_mixer == null) return;

    _running = true;
    notifyListeners();

    // Run immediately, then periodically
    _runCycle();
    _loopTimer = Timer.periodic(interval, (_) => _runCycle());
  }

  /// Stop the intelligence loop
  void stop() {
    _loopTimer?.cancel();
    _loopTimer = null;
    _running = false;
    notifyListeners();
  }

  /// Run a single analysis cycle on-demand
  Future<IntelligenceCycleResult?> runOnce() async {
    if (_mixer == null) return null;
    return _runCycle();
  }

  /// Record that the user applied a suggestion (for learning)
  void recordApplied() {
    _appliedSuggestions++;
    notifyListeners();
  }

  // ─── Core Loop ─────────────────────────────────────────────────────────

  Future<IntelligenceCycleResult?> _runCycle() async {
    if (_analyzing) return null; // Skip if already running

    _analyzing = true;
    notifyListeners();

    final stopwatch = Stopwatch()..start();

    try {
      // STEP 1: EYES — capture mixer vision snapshot
      String? snapshotPath;
      final mixerSnapshot = await _vision.capture('mixer');
      if (mixerSnapshot != null) {
        snapshotPath = mixerSnapshot.filePath;
        _vision.recordEvent(
          type: VisionEventType.stateChange,
          description: 'Intelligence loop: mixer captured',
          snapshot: mixerSnapshot,
        );
      }

      // STEP 2: THINK — run AI analysis on live mixer data
      final analysis = await _mixing.analyzeProject();

      stopwatch.stop();

      // STEP 3: RECORD — store cycle result
      final result = IntelligenceCycleResult(
        timestamp: DateTime.now(),
        tracksAnalyzed: analysis.tracks.length,
        suggestionsGenerated: analysis.suggestions.length,
        criticalIssues: analysis.criticalCount,
        mixScore: analysis.overallScore,
        detectedGenre: analysis.detectedGenre,
        visionSnapshotPath: snapshotPath,
        analysisTime: stopwatch.elapsed,
      );

      _history.insert(0, result);
      if (_history.length > _maxHistory) {
        _history.removeLast();
      }

      _totalCycles++;
      _totalSuggestions += analysis.suggestions.length;

      _analyzing = false;
      notifyListeners();

      return result;
    } catch (e) {
      debugPrint('[CortexIntelligence] Cycle failed: $e');
      _analyzing = false;
      notifyListeners();
      return null;
    }
  }

  // ─── Cleanup ───────────────────────────────────────────────────────────

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
