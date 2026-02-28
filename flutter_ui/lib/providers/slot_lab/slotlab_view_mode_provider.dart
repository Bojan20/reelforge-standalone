/// SlotLab View Mode Provider — Middleware §16
///
/// Manages the 4 view modes for SlotLab:
/// - Build (default, 90% of time) — behavior tree + inspector + coverage
/// - Flow — state machine visualization, transition diagram
/// - Simulation — simulated spins, statistical analysis
/// - Diagnostic — raw hooks, gate log, AUREXIS params, voice pool
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §16

import 'package:flutter/foundation.dart';

/// The 4 SlotLab view modes
enum SlotLabViewMode {
  /// Primary authoring mode — behavior tree, inspector, coverage, AutoBind
  build,
  /// Visualization mode — state flow diagram, emotional arc, transitions
  flow,
  /// Testing mode — simulated spins, statistical analysis, coverage reports
  simulation,
  /// Debug mode — raw hooks, gate log, AUREXIS live params, voice pool
  diagnostic,
}

extension SlotLabViewModeExtension on SlotLabViewMode {
  String get displayName {
    switch (this) {
      case SlotLabViewMode.build: return 'Build';
      case SlotLabViewMode.flow: return 'Flow';
      case SlotLabViewMode.simulation: return 'Simulation';
      case SlotLabViewMode.diagnostic: return 'Diagnostic';
    }
  }

  String get description {
    switch (this) {
      case SlotLabViewMode.build: return 'Author audio behaviors and assign sounds';
      case SlotLabViewMode.flow: return 'Visualize state flow and emotional arc';
      case SlotLabViewMode.simulation: return 'Simulate spins and analyze statistics';
      case SlotLabViewMode.diagnostic: return 'Debug raw hooks, gates, and AUREXIS';
    }
  }

  String get shortLabel {
    switch (this) {
      case SlotLabViewMode.build: return 'BLD';
      case SlotLabViewMode.flow: return 'FLW';
      case SlotLabViewMode.simulation: return 'SIM';
      case SlotLabViewMode.diagnostic: return 'DGN';
    }
  }

  /// Icon code point (Material Icons)
  int get iconCodePoint {
    switch (this) {
      case SlotLabViewMode.build: return 0xe1b1; // build
      case SlotLabViewMode.flow: return 0xe574; // account_tree
      case SlotLabViewMode.simulation: return 0xe8b8; // science
      case SlotLabViewMode.diagnostic: return 0xe868; // bug_report
    }
  }
}

/// Parameter disclosure tier (§19)
enum ParameterDisclosureTier {
  /// Basic: gain, priority, bus route, layer group
  basic,
  /// Advanced: escalation, spatial, energy, fade policy
  advanced,
  /// Expert: raw hook override, AUREXIS bias, execution priority
  expert,
}

extension ParameterDisclosureTierExtension on ParameterDisclosureTier {
  String get displayName {
    switch (this) {
      case ParameterDisclosureTier.basic: return 'Basic';
      case ParameterDisclosureTier.advanced: return 'Advanced';
      case ParameterDisclosureTier.expert: return 'Expert';
    }
  }

  String get description {
    switch (this) {
      case ParameterDisclosureTier.basic: return 'Essential parameters for all users';
      case ParameterDisclosureTier.advanced: return 'Detailed parameters for experienced users';
      case ParameterDisclosureTier.expert: return 'Full control including raw overrides';
    }
  }
}

class SlotLabViewModeProvider extends ChangeNotifier {
  /// Current view mode
  SlotLabViewMode _currentMode = SlotLabViewMode.build;

  /// Previous mode (for quick-switch back)
  SlotLabViewMode _previousMode = SlotLabViewMode.build;

  /// Current parameter disclosure tier
  ParameterDisclosureTier _parameterTier = ParameterDisclosureTier.basic;

  /// Whether the mode switcher bar is visible
  bool _showModeSwitcher = true;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  SlotLabViewMode get currentMode => _currentMode;
  SlotLabViewMode get previousMode => _previousMode;
  ParameterDisclosureTier get parameterTier => _parameterTier;
  bool get showModeSwitcher => _showModeSwitcher;

  bool get isBuildMode => _currentMode == SlotLabViewMode.build;
  bool get isFlowMode => _currentMode == SlotLabViewMode.flow;
  bool get isSimulationMode => _currentMode == SlotLabViewMode.simulation;
  bool get isDiagnosticMode => _currentMode == SlotLabViewMode.diagnostic;

  bool get isBasicTier => _parameterTier == ParameterDisclosureTier.basic;
  bool get isAdvancedTier => _parameterTier == ParameterDisclosureTier.advanced;
  bool get isExpertTier => _parameterTier == ParameterDisclosureTier.expert;

  // ═══════════════════════════════════════════════════════════════════════════
  // MODE SWITCHING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Switch to a new view mode
  void setMode(SlotLabViewMode mode) {
    if (_currentMode == mode) return;
    _previousMode = _currentMode;
    _currentMode = mode;
    notifyListeners();
  }

  /// Toggle back to previous mode
  void togglePreviousMode() {
    final temp = _currentMode;
    _currentMode = _previousMode;
    _previousMode = temp;
    notifyListeners();
  }

  /// Cycle to next mode
  void cycleMode() {
    final nextIndex = (_currentMode.index + 1) % SlotLabViewMode.values.length;
    setMode(SlotLabViewMode.values[nextIndex]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PARAMETER TIER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set parameter disclosure tier
  void setParameterTier(ParameterDisclosureTier tier) {
    if (_parameterTier == tier) return;
    _parameterTier = tier;
    notifyListeners();
  }

  /// Cycle parameter tier
  void cycleParameterTier() {
    final nextIndex = (_parameterTier.index + 1) % ParameterDisclosureTier.values.length;
    _parameterTier = ParameterDisclosureTier.values[nextIndex];
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UI OPTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void setShowModeSwitcher(bool value) {
    if (_showModeSwitcher == value) return;
    _showModeSwitcher = value;
    notifyListeners();
  }
}
