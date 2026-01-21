// Macro Control Provider
//
// Multi-parameter macro knobs (like Serum, Vital, Ableton):
// - Single knob controls multiple parameters
// - Per-target depth and curve
// - Bipolar/unipolar mapping
// - MIDI learn support
// - Macro pages for organization
//
// Use cases:
// - "Intensity" knob → drive + saturation + high freq boost
// - "Width" knob → stereo width + reverb amount + delay feedback
// - "Morph" knob → blend between two sound designs

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Mapping curve type for macro targets
enum MacroCurve {
  linear,       // Direct 1:1 mapping
  exponential,  // Slow start, fast end
  logarithmic,  // Fast start, slow end
  sCurve,       // Smooth S-curve
  step,         // Stepped/quantized
}

/// A parameter target for a macro
class MacroTarget {
  final String id;
  final int trackId;          // -1 for master/global
  final String parameterName;
  final String? pluginId;     // Plugin instance ID (null = track/mixer param)

  // Mapping range
  final double minValue;      // Target value when macro = 0
  final double maxValue;      // Target value when macro = 1
  final bool bipolar;         // Macro 0.5 = center (for bidirectional control)

  // Curve
  final MacroCurve curve;
  final double curveAmount;   // Curve intensity (0-1)

  // Enabled
  final bool enabled;

  const MacroTarget({
    required this.id,
    required this.trackId,
    required this.parameterName,
    this.pluginId,
    this.minValue = 0.0,
    this.maxValue = 1.0,
    this.bipolar = false,
    this.curve = MacroCurve.linear,
    this.curveAmount = 0.5,
    this.enabled = true,
  });

  MacroTarget copyWith({
    String? id,
    int? trackId,
    String? parameterName,
    String? pluginId,
    double? minValue,
    double? maxValue,
    bool? bipolar,
    MacroCurve? curve,
    double? curveAmount,
    bool? enabled,
  }) {
    return MacroTarget(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      parameterName: parameterName ?? this.parameterName,
      pluginId: pluginId ?? this.pluginId,
      minValue: minValue ?? this.minValue,
      maxValue: maxValue ?? this.maxValue,
      bipolar: bipolar ?? this.bipolar,
      curve: curve ?? this.curve,
      curveAmount: curveAmount ?? this.curveAmount,
      enabled: enabled ?? this.enabled,
    );
  }

  /// Calculate target value from macro value (0-1)
  double calculateValue(double macroValue) {
    if (!enabled) return minValue;

    double t = macroValue.clamp(0.0, 1.0);

    // Apply curve
    switch (curve) {
      case MacroCurve.linear:
        break;
      case MacroCurve.exponential:
        t = _exponentialCurve(t, curveAmount);
        break;
      case MacroCurve.logarithmic:
        t = _logarithmicCurve(t, curveAmount);
        break;
      case MacroCurve.sCurve:
        t = _sCurve(t, curveAmount);
        break;
      case MacroCurve.step:
        t = _stepCurve(t, curveAmount);
        break;
    }

    // Apply bipolar mapping
    if (bipolar) {
      // Macro 0.5 = center, 0 = min, 1 = max
      final center = (minValue + maxValue) / 2;
      if (macroValue < 0.5) {
        return center + (minValue - center) * (1 - macroValue * 2);
      } else {
        return center + (maxValue - center) * ((macroValue - 0.5) * 2);
      }
    }

    // Linear interpolation
    return minValue + t * (maxValue - minValue);
  }

  double _exponentialCurve(double t, double amount) {
    final exp = 1 + amount * 3; // 1 to 4
    return (t * t * t).clamp(0.0, 1.0);
  }

  double _logarithmicCurve(double t, double amount) {
    if (t <= 0) return 0;
    return (1 + (t - 1).abs() * amount).clamp(0.0, 1.0);
  }

  double _sCurve(double t, double amount) {
    // Smoothstep with adjustable steepness
    final steepness = 1 + amount * 4;
    final centered = (t - 0.5) * steepness;
    return (0.5 + centered / (1 + centered.abs() * 2)).clamp(0.0, 1.0);
  }

  double _stepCurve(double t, double amount) {
    final steps = (2 + amount * 14).round(); // 2 to 16 steps
    return (t * steps).floor() / (steps - 1);
  }

  /// Get display name
  String get displayName {
    if (pluginId != null) {
      return '$pluginId: $parameterName';
    }
    return 'Track $trackId: $parameterName';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MACRO CONTROL
// ═══════════════════════════════════════════════════════════════════════════════

/// A single macro control (knob)
class MacroControl {
  final String id;
  final String name;
  final Color color;

  // Current value (0-1)
  final double value;
  final double defaultValue;

  // Targets
  final List<MacroTarget> targets;

  // MIDI learn
  final int? midiCC;        // Assigned CC number
  final int? midiChannel;   // MIDI channel (1-16, null = omni)

  // Display
  final String? label;      // Custom label (e.g., "Intensity", "Width")
  final IconData? icon;

  // Smoothing
  final double smoothing;   // Parameter smoothing (0-1, for avoiding zipper noise)

  const MacroControl({
    required this.id,
    required this.name,
    this.color = const Color(0xFF4A9EFF),
    this.value = 0.0,
    this.defaultValue = 0.0,
    this.targets = const [],
    this.midiCC,
    this.midiChannel,
    this.label,
    this.icon,
    this.smoothing = 0.1,
  });

  MacroControl copyWith({
    String? id,
    String? name,
    Color? color,
    double? value,
    double? defaultValue,
    List<MacroTarget>? targets,
    int? midiCC,
    int? midiChannel,
    String? label,
    IconData? icon,
    double? smoothing,
  }) {
    return MacroControl(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      value: value ?? this.value,
      defaultValue: defaultValue ?? this.defaultValue,
      targets: targets ?? this.targets,
      midiCC: midiCC ?? this.midiCC,
      midiChannel: midiChannel ?? this.midiChannel,
      label: label ?? this.label,
      icon: icon ?? this.icon,
      smoothing: smoothing ?? this.smoothing,
    );
  }

  /// Get all calculated target values
  Map<String, double> getTargetValues() {
    final result = <String, double>{};
    for (final target in targets) {
      if (target.enabled) {
        result[target.id] = target.calculateValue(value);
      }
    }
    return result;
  }

  /// Get display value (formatted)
  String get displayValue => '${(value * 100).round()}%';
}

// ═══════════════════════════════════════════════════════════════════════════════
// MACRO PAGE
// ═══════════════════════════════════════════════════════════════════════════════

/// A page of macro controls (for organization)
class MacroPage {
  final String id;
  final String name;
  final List<String> macroIds;  // Order of macros on this page
  final int columns;            // Grid layout columns

  const MacroPage({
    required this.id,
    required this.name,
    this.macroIds = const [],
    this.columns = 4,
  });

  MacroPage copyWith({
    String? id,
    String? name,
    List<String>? macroIds,
    int? columns,
  }) {
    return MacroPage(
      id: id ?? this.id,
      name: name ?? this.name,
      macroIds: macroIds ?? this.macroIds,
      columns: columns ?? this.columns,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

class MacroControlProvider extends ChangeNotifier {
  // All macros by ID
  final Map<String, MacroControl> _macros = {};

  // Macro pages
  final Map<String, MacroPage> _pages = {};

  // Active page
  String? _activePageId;

  // MIDI learn mode
  bool _midiLearnMode = false;
  String? _midiLearnTargetMacroId;

  // Selected macro for editing
  String? _selectedMacroId;

  // Global enable
  bool _enabled = true;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get enabled => _enabled;
  bool get midiLearnMode => _midiLearnMode;
  String? get midiLearnTargetMacroId => _midiLearnTargetMacroId;
  String? get selectedMacroId => _selectedMacroId;
  String? get activePageId => _activePageId;

  List<MacroControl> get macros => _macros.values.toList();
  List<MacroPage> get pages => _pages.values.toList();

  MacroControl? getMacro(String id) => _macros[id];
  MacroPage? getPage(String id) => _pages[id];
  MacroPage? get activePage =>
      _activePageId != null ? _pages[_activePageId] : null;

  /// Get macros for active page
  List<MacroControl> get activeMacros {
    final page = activePage;
    if (page == null) return macros;
    return page.macroIds
        .map((id) => _macros[id])
        .whereType<MacroControl>()
        .toList();
  }

  /// Find macro by MIDI CC
  MacroControl? getMacroByMidiCC(int cc, [int? channel]) {
    return _macros.values.cast<MacroControl?>().firstWhere(
      (m) => m?.midiCC == cc && (channel == null || m?.midiChannel == channel),
      orElse: () => null,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GLOBAL CONTROLS
  // ═══════════════════════════════════════════════════════════════════════════

  void setEnabled(bool value) {
    _enabled = value;
    notifyListeners();
  }

  void toggleEnabled() {
    _enabled = !_enabled;
    notifyListeners();
  }

  void selectMacro(String? macroId) {
    _selectedMacroId = macroId;
    notifyListeners();
  }

  void setActivePage(String? pageId) {
    _activePageId = pageId;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MACRO MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create new macro
  MacroControl addMacro({
    String? name,
    Color? color,
    double defaultValue = 0.0,
  }) {
    final id = 'macro_${DateTime.now().millisecondsSinceEpoch}';
    final macroNumber = _macros.length + 1;

    final macro = MacroControl(
      id: id,
      name: name ?? 'Macro $macroNumber',
      color: color ?? _getDefaultColor(macroNumber),
      value: defaultValue,
      defaultValue: defaultValue,
    );

    _macros[id] = macro;

    // Add to active page if exists
    if (_activePageId != null) {
      final page = _pages[_activePageId]!;
      _pages[_activePageId!] = page.copyWith(
        macroIds: [...page.macroIds, id],
      );
    }

    notifyListeners();
    return macro;
  }

  /// Update macro
  void updateMacro(MacroControl macro) {
    _macros[macro.id] = macro;
    notifyListeners();
  }

  /// Delete macro
  void deleteMacro(String macroId) {
    _macros.remove(macroId);

    // Remove from all pages
    for (final pageId in _pages.keys.toList()) {
      final page = _pages[pageId]!;
      if (page.macroIds.contains(macroId)) {
        _pages[pageId] = page.copyWith(
          macroIds: page.macroIds.where((id) => id != macroId).toList(),
        );
      }
    }

    if (_selectedMacroId == macroId) _selectedMacroId = null;
    notifyListeners();
  }

  /// Set macro value
  void setMacroValue(String macroId, double value) {
    final macro = _macros[macroId];
    if (macro == null) return;

    _macros[macroId] = macro.copyWith(value: value.clamp(0.0, 1.0));
    notifyListeners();
  }

  /// Reset macro to default
  void resetMacro(String macroId) {
    final macro = _macros[macroId];
    if (macro == null) return;

    _macros[macroId] = macro.copyWith(value: macro.defaultValue);
    notifyListeners();
  }

  /// Reset all macros
  void resetAllMacros() {
    for (final macroId in _macros.keys.toList()) {
      final macro = _macros[macroId]!;
      _macros[macroId] = macro.copyWith(value: macro.defaultValue);
    }
    notifyListeners();
  }

  Color _getDefaultColor(int index) {
    const colors = [
      Color(0xFF4A9EFF),  // Blue
      Color(0xFFFF9040),  // Orange
      Color(0xFF40FF90),  // Green
      Color(0xFFFF4060),  // Red
      Color(0xFFAA40FF),  // Purple
      Color(0xFF40C8FF),  // Cyan
      Color(0xFFFFDD40),  // Yellow
      Color(0xFFFF40FF),  // Magenta
    ];
    return colors[(index - 1) % colors.length];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TARGET MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add target to macro
  MacroTarget addTarget(
    String macroId, {
    required int trackId,
    required String parameterName,
    String? pluginId,
    double minValue = 0.0,
    double maxValue = 1.0,
    bool bipolar = false,
  }) {
    final macro = _macros[macroId];
    if (macro == null) throw StateError('Macro not found');

    final targetId = 'target_${DateTime.now().millisecondsSinceEpoch}';
    final target = MacroTarget(
      id: targetId,
      trackId: trackId,
      parameterName: parameterName,
      pluginId: pluginId,
      minValue: minValue,
      maxValue: maxValue,
      bipolar: bipolar,
    );

    _macros[macroId] = macro.copyWith(targets: [...macro.targets, target]);
    notifyListeners();
    return target;
  }

  /// Update target
  void updateTarget(String macroId, MacroTarget target) {
    final macro = _macros[macroId];
    if (macro == null) return;

    final targets = macro.targets.map((t) {
      return t.id == target.id ? target : t;
    }).toList();

    _macros[macroId] = macro.copyWith(targets: targets);
    notifyListeners();
  }

  /// Remove target from macro
  void removeTarget(String macroId, String targetId) {
    final macro = _macros[macroId];
    if (macro == null) return;

    final targets = macro.targets.where((t) => t.id != targetId).toList();
    _macros[macroId] = macro.copyWith(targets: targets);
    notifyListeners();
  }

  /// Toggle target enabled
  void toggleTargetEnabled(String macroId, String targetId) {
    final macro = _macros[macroId];
    if (macro == null) return;

    final targets = macro.targets.map((t) {
      if (t.id == targetId) {
        return t.copyWith(enabled: !t.enabled);
      }
      return t;
    }).toList();

    _macros[macroId] = macro.copyWith(targets: targets);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAGE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create new page
  MacroPage addPage({String? name, int columns = 4}) {
    final id = 'page_${DateTime.now().millisecondsSinceEpoch}';
    final page = MacroPage(
      id: id,
      name: name ?? 'Page ${_pages.length + 1}',
      columns: columns,
    );

    _pages[id] = page;
    _activePageId ??= id;
    notifyListeners();
    return page;
  }

  /// Update page
  void updatePage(MacroPage page) {
    _pages[page.id] = page;
    notifyListeners();
  }

  /// Delete page
  void deletePage(String pageId) {
    _pages.remove(pageId);
    if (_activePageId == pageId) {
      _activePageId = _pages.isNotEmpty ? _pages.keys.first : null;
    }
    notifyListeners();
  }

  /// Add macro to page
  void addMacroToPage(String pageId, String macroId) {
    final page = _pages[pageId];
    if (page == null) return;

    if (!page.macroIds.contains(macroId)) {
      _pages[pageId] = page.copyWith(macroIds: [...page.macroIds, macroId]);
      notifyListeners();
    }
  }

  /// Remove macro from page
  void removeMacroFromPage(String pageId, String macroId) {
    final page = _pages[pageId];
    if (page == null) return;

    _pages[pageId] = page.copyWith(
      macroIds: page.macroIds.where((id) => id != macroId).toList(),
    );
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MIDI LEARN
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start MIDI learn mode for a macro
  void startMidiLearn(String macroId) {
    _midiLearnMode = true;
    _midiLearnTargetMacroId = macroId;
    notifyListeners();
  }

  /// Cancel MIDI learn
  void cancelMidiLearn() {
    _midiLearnMode = false;
    _midiLearnTargetMacroId = null;
    notifyListeners();
  }

  /// Process incoming MIDI CC (for MIDI learn)
  void processMidiCC(int cc, int channel, int value) {
    if (_midiLearnMode && _midiLearnTargetMacroId != null) {
      // Assign CC to macro
      final macro = _macros[_midiLearnTargetMacroId]!;
      _macros[_midiLearnTargetMacroId!] = macro.copyWith(
        midiCC: cc,
        midiChannel: channel,
      );

      // Exit learn mode
      _midiLearnMode = false;
      _midiLearnTargetMacroId = null;
      notifyListeners();
      return;
    }

    // Normal operation - find macro by CC and update value
    final macro = getMacroByMidiCC(cc, channel);
    if (macro != null && _enabled) {
      setMacroValue(macro.id, value / 127.0);
    }
  }

  /// Clear MIDI assignment
  void clearMidiAssignment(String macroId) {
    final macro = _macros[macroId];
    if (macro == null) return;

    _macros[macroId] = MacroControl(
      id: macro.id,
      name: macro.name,
      color: macro.color,
      value: macro.value,
      defaultValue: macro.defaultValue,
      targets: macro.targets,
      midiCC: null,
      midiChannel: null,
      label: macro.label,
      icon: macro.icon,
      smoothing: macro.smoothing,
    );
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GET CURRENT VALUES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all current target values from all macros
  Map<String, double> getAllTargetValues() {
    if (!_enabled) return {};

    final result = <String, double>{};
    for (final macro in _macros.values) {
      result.addAll(macro.getTargetValues());
    }
    return result;
  }

  /// Get target value for specific parameter
  double? getTargetValue(int trackId, String parameterName, [String? pluginId]) {
    if (!_enabled) return null;

    for (final macro in _macros.values) {
      for (final target in macro.targets) {
        if (target.trackId == trackId &&
            target.parameterName == parameterName &&
            target.pluginId == pluginId &&
            target.enabled) {
          return target.calculateValue(macro.value);
        }
      }
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() {
    return {
      'enabled': _enabled,
      'activePageId': _activePageId,
      'macros': _macros.values.map((m) => _macroToJson(m)).toList(),
      'pages': _pages.values.map((p) => _pageToJson(p)).toList(),
    };
  }

  void loadFromJson(Map<String, dynamic> json) {
    _enabled = json['enabled'] ?? true;
    _activePageId = json['activePageId'];

    _macros.clear();
    if (json['macros'] != null) {
      for (final m in json['macros']) {
        final macro = _macroFromJson(m);
        _macros[macro.id] = macro;
      }
    }

    _pages.clear();
    if (json['pages'] != null) {
      for (final p in json['pages']) {
        final page = _pageFromJson(p);
        _pages[page.id] = page;
      }
    }

    notifyListeners();
  }

  Map<String, dynamic> _macroToJson(MacroControl m) {
    return {
      'id': m.id,
      'name': m.name,
      'color': m.color.toARGB32(),
      'value': m.value,
      'defaultValue': m.defaultValue,
      'targets': m.targets.map((t) => _targetToJson(t)).toList(),
      'midiCC': m.midiCC,
      'midiChannel': m.midiChannel,
      'label': m.label,
      'smoothing': m.smoothing,
    };
  }

  MacroControl _macroFromJson(Map<String, dynamic> json) {
    return MacroControl(
      id: json['id'],
      name: json['name'] ?? 'Macro',
      color: Color(json['color'] ?? 0xFF4A9EFF),
      value: (json['value'] ?? 0.0).toDouble(),
      defaultValue: (json['defaultValue'] ?? 0.0).toDouble(),
      targets: (json['targets'] as List?)
              ?.map((t) => _targetFromJson(t))
              .toList() ??
          [],
      midiCC: json['midiCC'],
      midiChannel: json['midiChannel'],
      label: json['label'],
      smoothing: (json['smoothing'] ?? 0.1).toDouble(),
    );
  }

  Map<String, dynamic> _targetToJson(MacroTarget t) {
    return {
      'id': t.id,
      'trackId': t.trackId,
      'parameterName': t.parameterName,
      'pluginId': t.pluginId,
      'minValue': t.minValue,
      'maxValue': t.maxValue,
      'bipolar': t.bipolar,
      'curve': t.curve.index,
      'curveAmount': t.curveAmount,
      'enabled': t.enabled,
    };
  }

  MacroTarget _targetFromJson(Map<String, dynamic> json) {
    return MacroTarget(
      id: json['id'],
      trackId: json['trackId'] ?? 0,
      parameterName: json['parameterName'] ?? '',
      pluginId: json['pluginId'],
      minValue: (json['minValue'] ?? 0.0).toDouble(),
      maxValue: (json['maxValue'] ?? 1.0).toDouble(),
      bipolar: json['bipolar'] ?? false,
      curve: MacroCurve.values[json['curve'] ?? 0],
      curveAmount: (json['curveAmount'] ?? 0.5).toDouble(),
      enabled: json['enabled'] ?? true,
    );
  }

  Map<String, dynamic> _pageToJson(MacroPage p) {
    return {
      'id': p.id,
      'name': p.name,
      'macroIds': p.macroIds,
      'columns': p.columns,
    };
  }

  MacroPage _pageFromJson(Map<String, dynamic> json) {
    return MacroPage(
      id: json['id'],
      name: json['name'] ?? 'Page',
      macroIds: (json['macroIds'] as List?)?.cast<String>() ?? [],
      columns: json['columns'] ?? 4,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESET
  // ═══════════════════════════════════════════════════════════════════════════

  void reset() {
    _macros.clear();
    _pages.clear();
    _activePageId = null;
    _midiLearnMode = false;
    _midiLearnTargetMacroId = null;
    _selectedMacroId = null;
    _enabled = true;
    notifyListeners();
  }

}
