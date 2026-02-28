/// SAM Provider — Smart Authoring Mode §13
///
/// 3 UI modes, 8 archetypes, 11 smart controls, 9-step wizard.
///
/// See: FLUXFORGE_MASTER_SPEC.md §13

import 'package:flutter/foundation.dart';
import '../../src/rust/native_ffi.dart';

/// 3 authoring modes.
enum SamAuthoringMode {
  smart,
  advanced,
  debug,
}

extension SamAuthoringModeExtension on SamAuthoringMode {
  String get displayName {
    switch (this) {
      case SamAuthoringMode.smart: return 'SMART';
      case SamAuthoringMode.advanced: return 'ADVANCED';
      case SamAuthoringMode.debug: return 'DEBUG';
    }
  }

  static SamAuthoringMode fromIndex(int index) {
    switch (index) {
      case 1: return SamAuthoringMode.advanced;
      case 2: return SamAuthoringMode.debug;
      default: return SamAuthoringMode.smart;
    }
  }
}

/// 3 smart control groups.
enum SamControlGroup {
  energy,
  clarity,
  stability,
}

extension SamControlGroupExtension on SamControlGroup {
  String get displayName {
    switch (this) {
      case SamControlGroup.energy: return 'Energy';
      case SamControlGroup.clarity: return 'Clarity';
      case SamControlGroup.stability: return 'Stability';
    }
  }

  static SamControlGroup fromIndex(int index) {
    switch (index) {
      case 1: return SamControlGroup.clarity;
      case 2: return SamControlGroup.stability;
      default: return SamControlGroup.energy;
    }
  }
}

/// 3 market targets.
enum SamMarketTarget {
  casual,
  standard,
  premium,
}

extension SamMarketTargetExtension on SamMarketTarget {
  String get displayName {
    switch (this) {
      case SamMarketTarget.casual: return 'Casual';
      case SamMarketTarget.standard: return 'Standard';
      case SamMarketTarget.premium: return 'Premium';
    }
  }
}

/// Archetype info.
class SamArchetypeInfo {
  final int index;
  final String name;
  final String description;

  const SamArchetypeInfo({
    required this.index,
    required this.name,
    required this.description,
  });
}

/// Smart control info.
class SamControlInfo {
  final int index;
  final String name;
  final SamControlGroup group;
  final double value;

  const SamControlInfo({
    required this.index,
    required this.name,
    required this.group,
    required this.value,
  });
}

/// Wizard step info.
class SamWizardStepInfo {
  final int index;
  final String name;
  final String description;

  const SamWizardStepInfo({
    required this.index,
    required this.name,
    required this.description,
  });
}

class SamProvider extends ChangeNotifier {
  final NativeFFI? _ffi;

  SamAuthoringMode _mode = SamAuthoringMode.smart;
  int _wizardStep = 0;
  double _wizardProgress = 0.0;
  int _selectedArchetype = -1;
  double _volatility = 0.5;
  double _volatilityMin = 0.0;
  double _volatilityMax = 1.0;
  SamMarketTarget _market = SamMarketTarget.standard;
  bool _autoConfigured = false;
  bool _gddImported = false;
  bool _ailPassed = false;
  double _ailScore = 0.0;
  bool _certified = false;

  List<SamArchetypeInfo> _archetypes = [];
  List<SamControlInfo> _controls = [];
  List<SamWizardStepInfo> _wizardSteps = [];

  SamProvider([this._ffi]) {
    _loadStaticData();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  SamAuthoringMode get mode => _mode;
  int get wizardStep => _wizardStep;
  double get wizardProgress => _wizardProgress;
  int get selectedArchetype => _selectedArchetype;
  bool get hasArchetype => _selectedArchetype >= 0;
  double get volatility => _volatility;
  double get volatilityMin => _volatilityMin;
  double get volatilityMax => _volatilityMax;
  SamMarketTarget get market => _market;
  bool get autoConfigured => _autoConfigured;
  bool get gddImported => _gddImported;
  bool get ailPassed => _ailPassed;
  double get ailScore => _ailScore;
  bool get certified => _certified;

  List<SamArchetypeInfo> get archetypes => List.unmodifiable(_archetypes);
  List<SamControlInfo> get controls => List.unmodifiable(_controls);
  List<SamWizardStepInfo> get wizardSteps => List.unmodifiable(_wizardSteps);

  /// Controls filtered by group.
  List<SamControlInfo> controlsByGroup(SamControlGroup group) =>
      _controls.where((c) => c.group == group).toList();

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void setMode(SamAuthoringMode mode) {
    _ffi?.samSetMode(mode.index);
    _mode = mode;
    notifyListeners();
  }

  void selectArchetype(int index) {
    _ffi?.samSelectArchetype(index);
    _refreshState();
  }

  void setVolatility(double value) {
    _ffi?.samSetVolatility(value);
    _refreshState();
  }

  void setMarket(SamMarketTarget market) {
    _ffi?.samSetMarket(market.index);
    _market = market;
    notifyListeners();
  }

  void setControlValue(int controlIndex, double value) {
    _ffi?.samSetControlValue(controlIndex, value);
    _refreshControls();
  }

  void autoConfigure() {
    _ffi?.samAutoConfigure();
    _refreshState();
  }

  void setGddImported(bool imported) {
    _ffi?.samSetGddImported(imported);
    _gddImported = imported;
    notifyListeners();
  }

  void wizardNext() {
    _ffi?.samWizardNext();
    _refreshState();
  }

  void wizardPrev() {
    _ffi?.samWizardPrev();
    _refreshState();
  }

  void setWizardStep(int step) {
    _ffi?.samSetWizardStep(step);
    _refreshState();
  }

  void reset() {
    _ffi?.samReset();
    _refreshState();
  }

  String? getStateJson() => _ffi?.samStateJson();

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL
  // ═══════════════════════════════════════════════════════════════════════════

  void _loadStaticData() {
    final ffi = _ffi;
    if (ffi == null) return;

    // Load archetypes (static)
    _archetypes = [];
    final archCount = ffi.samArchetypeCount();
    for (int i = 0; i < archCount; i++) {
      _archetypes.add(SamArchetypeInfo(
        index: i,
        name: ffi.samArchetypeName(i) ?? 'Archetype $i',
        description: ffi.samArchetypeDescription(i) ?? '',
      ));
    }

    // Load wizard steps (static)
    _wizardSteps = [];
    final stepCount = ffi.samWizardStepCount();
    for (int i = 0; i < stepCount; i++) {
      _wizardSteps.add(SamWizardStepInfo(
        index: i,
        name: ffi.samWizardStepName(i) ?? 'Step $i',
        description: ffi.samWizardStepDescription(i) ?? '',
      ));
    }

    _refreshState();
  }

  void _refreshState() {
    final ffi = _ffi;
    if (ffi == null) return;

    _mode = SamAuthoringModeExtension.fromIndex(ffi.samMode());
    _wizardStep = ffi.samWizardStep();
    _wizardProgress = ffi.samWizardProgress();
    _selectedArchetype = ffi.samSelectedArchetype();
    _volatility = ffi.samVolatility();
    _volatilityMin = ffi.samVolatilityMin();
    _volatilityMax = ffi.samVolatilityMax();
    _market = SamMarketTarget.values[ffi.samMarket().clamp(0, 2)];
    _autoConfigured = ffi.samIsAutoConfigured();
    _gddImported = ffi.samGddImported();
    _ailPassed = ffi.samAilPassed();
    _ailScore = ffi.samAilScore();
    _certified = ffi.samIsCertified();

    _refreshControls();
    notifyListeners();
  }

  void _refreshControls() {
    final ffi = _ffi;
    if (ffi == null) return;

    _controls = [];
    final count = ffi.samControlCount();
    for (int i = 0; i < count; i++) {
      final groupIdx = ffi.samControlGroup(i);
      _controls.add(SamControlInfo(
        index: i,
        name: ffi.samControlName(i) ?? 'Control $i',
        group: SamControlGroupExtension.fromIndex(groupIdx.clamp(0, 2)),
        value: ffi.samControlValue(i),
      ));
    }

    notifyListeners();
  }
}
