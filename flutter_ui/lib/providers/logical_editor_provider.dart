// Project Logical Editor Provider
//
// Cubase-style batch operations on MIDI and audio:
// - Filter: Select events based on conditions
// - Action: Transform selected events
// - Presets: Save and recall complex operations
//
// Examples:
// - Select all notes below velocity 20, delete them
// - Double velocity of all notes on beat 1
// - Transpose all C notes up an octave
// - Randomize timing by ±10 ticks

import 'package:flutter/foundation.dart';
import 'dart:math' as math;

// ═══════════════════════════════════════════════════════════════════════════════
// FILTER CONDITIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Property to filter on
enum FilterProperty {
  // MIDI Note properties
  pitch,          // Note number (0-127)
  velocity,       // Velocity (0-127)
  length,         // Note length (ticks)
  position,       // Position (ticks or bars.beats)
  channel,        // MIDI channel (1-16)

  // Audio clip properties
  clipGain,       // Clip gain (dB)
  clipLength,     // Clip length (seconds)
  clipPosition,   // Clip position (seconds)
  clipName,       // Clip name (string match)

  // Common
  selected,       // Selection state
  muted,          // Mute state
}

/// Comparison operator
enum FilterOperator {
  equals,
  notEquals,
  greaterThan,
  greaterOrEqual,
  lessThan,
  lessOrEqual,
  inRange,        // Between two values
  notInRange,
  contains,       // String contains
  startsWith,     // String starts with
  endsWith,       // String ends with
}

/// A single filter condition
class FilterCondition {
  final String id;
  final FilterProperty property;
  final FilterOperator operator;
  final dynamic value1;       // Primary value
  final dynamic value2;       // Secondary value (for range)
  final bool enabled;

  const FilterCondition({
    required this.id,
    required this.property,
    required this.operator,
    required this.value1,
    this.value2,
    this.enabled = true,
  });

  FilterCondition copyWith({
    String? id,
    FilterProperty? property,
    FilterOperator? operator,
    dynamic value1,
    dynamic value2,
    bool? enabled,
  }) {
    return FilterCondition(
      id: id ?? this.id,
      property: property ?? this.property,
      operator: operator ?? this.operator,
      value1: value1 ?? this.value1,
      value2: value2 ?? this.value2,
      enabled: enabled ?? this.enabled,
    );
  }

  /// Evaluate condition against a value
  bool evaluate(dynamic targetValue) {
    if (!enabled) return true;

    switch (operator) {
      case FilterOperator.equals:
        return targetValue == value1;

      case FilterOperator.notEquals:
        return targetValue != value1;

      case FilterOperator.greaterThan:
        return (targetValue as num) > (value1 as num);

      case FilterOperator.greaterOrEqual:
        return (targetValue as num) >= (value1 as num);

      case FilterOperator.lessThan:
        return (targetValue as num) < (value1 as num);

      case FilterOperator.lessOrEqual:
        return (targetValue as num) <= (value1 as num);

      case FilterOperator.inRange:
        final v = targetValue as num;
        return v >= (value1 as num) && v <= (value2 as num);

      case FilterOperator.notInRange:
        final v = targetValue as num;
        return v < (value1 as num) || v > (value2 as num);

      case FilterOperator.contains:
        return (targetValue as String).contains(value1 as String);

      case FilterOperator.startsWith:
        return (targetValue as String).startsWith(value1 as String);

      case FilterOperator.endsWith:
        return (targetValue as String).endsWith(value1 as String);
    }
  }

  /// Get display string
  String get displayString {
    final propName = property.name;
    final opStr = _operatorString(operator);

    if (operator == FilterOperator.inRange || operator == FilterOperator.notInRange) {
      return '$propName $opStr $value1 and $value2';
    }
    return '$propName $opStr $value1';
  }

  String _operatorString(FilterOperator op) {
    switch (op) {
      case FilterOperator.equals:
        return '=';
      case FilterOperator.notEquals:
        return '≠';
      case FilterOperator.greaterThan:
        return '>';
      case FilterOperator.greaterOrEqual:
        return '≥';
      case FilterOperator.lessThan:
        return '<';
      case FilterOperator.lessOrEqual:
        return '≤';
      case FilterOperator.inRange:
        return 'between';
      case FilterOperator.notInRange:
        return 'not between';
      case FilterOperator.contains:
        return 'contains';
      case FilterOperator.startsWith:
        return 'starts with';
      case FilterOperator.endsWith:
        return 'ends with';
    }
  }
}

/// How to combine multiple conditions
enum FilterCombineMode {
  and,    // All conditions must match
  or,     // Any condition must match
}

// ═══════════════════════════════════════════════════════════════════════════════
// ACTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Action type
enum LogicalActionType {
  // Value operations
  set,            // Set to specific value
  add,            // Add value
  subtract,       // Subtract value
  multiply,       // Multiply value
  divide,         // Divide value
  random,         // Randomize within range

  // Special operations
  delete,         // Delete matching events
  mute,           // Mute matching events
  unmute,         // Unmute matching events
  select,         // Select matching events
  deselect,       // Deselect matching events
  quantize,       // Quantize to grid
  legato,         // Extend notes to next note
  fixedLength,    // Set fixed length
}

/// Target property for action
enum ActionTarget {
  pitch,
  velocity,
  length,
  position,
  channel,
  clipGain,
  selection,
  mute,
}

/// A single action to perform
class LogicalAction {
  final String id;
  final LogicalActionType type;
  final ActionTarget target;
  final dynamic value1;
  final dynamic value2;     // For random range
  final bool enabled;

  const LogicalAction({
    required this.id,
    required this.type,
    required this.target,
    this.value1,
    this.value2,
    this.enabled = true,
  });

  LogicalAction copyWith({
    String? id,
    LogicalActionType? type,
    ActionTarget? target,
    dynamic value1,
    dynamic value2,
    bool? enabled,
  }) {
    return LogicalAction(
      id: id ?? this.id,
      type: type ?? this.type,
      target: target ?? this.target,
      value1: value1 ?? this.value1,
      value2: value2 ?? this.value2,
      enabled: enabled ?? this.enabled,
    );
  }

  /// Apply action to value
  dynamic apply(dynamic currentValue) {
    if (!enabled) return currentValue;

    switch (type) {
      case LogicalActionType.set:
        return value1;

      case LogicalActionType.add:
        return (currentValue as num) + (value1 as num);

      case LogicalActionType.subtract:
        return (currentValue as num) - (value1 as num);

      case LogicalActionType.multiply:
        return (currentValue as num) * (value1 as num);

      case LogicalActionType.divide:
        final divisor = value1 as num;
        if (divisor == 0) return currentValue;
        return (currentValue as num) / divisor;

      case LogicalActionType.random:
        final min = value1 as num;
        final max = value2 as num;
        return min + math.Random().nextDouble() * (max - min);

      case LogicalActionType.delete:
      case LogicalActionType.mute:
      case LogicalActionType.unmute:
      case LogicalActionType.select:
      case LogicalActionType.deselect:
      case LogicalActionType.quantize:
      case LogicalActionType.legato:
      case LogicalActionType.fixedLength:
        // These are special operations, not value transforms
        return currentValue;
    }
  }

  /// Get display string
  String get displayString {
    switch (type) {
      case LogicalActionType.set:
        return 'Set ${target.name} to $value1';
      case LogicalActionType.add:
        return 'Add $value1 to ${target.name}';
      case LogicalActionType.subtract:
        return 'Subtract $value1 from ${target.name}';
      case LogicalActionType.multiply:
        return 'Multiply ${target.name} by $value1';
      case LogicalActionType.divide:
        return 'Divide ${target.name} by $value1';
      case LogicalActionType.random:
        return 'Randomize ${target.name} between $value1 and $value2';
      case LogicalActionType.delete:
        return 'Delete';
      case LogicalActionType.mute:
        return 'Mute';
      case LogicalActionType.unmute:
        return 'Unmute';
      case LogicalActionType.select:
        return 'Select';
      case LogicalActionType.deselect:
        return 'Deselect';
      case LogicalActionType.quantize:
        return 'Quantize to $value1';
      case LogicalActionType.legato:
        return 'Legato';
      case LogicalActionType.fixedLength:
        return 'Set length to $value1';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRESET
// ═══════════════════════════════════════════════════════════════════════════════

/// A complete logical editor preset
class LogicalEditorPreset {
  final String id;
  final String name;
  final String? description;
  final String? category;

  final List<FilterCondition> filters;
  final FilterCombineMode filterMode;

  final List<LogicalAction> actions;

  final bool isFactory;   // Built-in preset

  const LogicalEditorPreset({
    required this.id,
    required this.name,
    this.description,
    this.category,
    this.filters = const [],
    this.filterMode = FilterCombineMode.and,
    this.actions = const [],
    this.isFactory = false,
  });

  LogicalEditorPreset copyWith({
    String? id,
    String? name,
    String? description,
    String? category,
    List<FilterCondition>? filters,
    FilterCombineMode? filterMode,
    List<LogicalAction>? actions,
    bool? isFactory,
  }) {
    return LogicalEditorPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      filters: filters ?? this.filters,
      filterMode: filterMode ?? this.filterMode,
      actions: actions ?? this.actions,
      isFactory: isFactory ?? this.isFactory,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

class LogicalEditorProvider extends ChangeNotifier {
  // Current working preset
  LogicalEditorPreset _currentPreset = LogicalEditorPreset(
    id: 'current',
    name: 'Untitled',
  );

  // Saved presets
  final Map<String, LogicalEditorPreset> _presets = {};

  // Factory presets
  final Map<String, LogicalEditorPreset> _factoryPresets = {};

  // Last executed result
  int _lastMatchCount = 0;
  int _lastAffectedCount = 0;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  LogicalEditorPreset get currentPreset => _currentPreset;
  List<FilterCondition> get filters => _currentPreset.filters;
  List<LogicalAction> get actions => _currentPreset.actions;
  FilterCombineMode get filterMode => _currentPreset.filterMode;

  int get lastMatchCount => _lastMatchCount;
  int get lastAffectedCount => _lastAffectedCount;

  List<LogicalEditorPreset> get userPresets =>
      _presets.values.where((p) => !p.isFactory).toList();

  List<LogicalEditorPreset> get factoryPresets =>
      _factoryPresets.values.toList();

  List<LogicalEditorPreset> get allPresets => [
    ..._factoryPresets.values,
    ..._presets.values,
  ];

  /// Get presets by category
  Map<String, List<LogicalEditorPreset>> get presetsByCategory {
    final result = <String, List<LogicalEditorPreset>>{};
    for (final preset in allPresets) {
      final category = preset.category ?? 'Uncategorized';
      result.putIfAbsent(category, () => []).add(preset);
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CURRENT PRESET EDITING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Reset to empty preset
  void resetPreset() {
    _currentPreset = LogicalEditorPreset(
      id: 'current',
      name: 'Untitled',
    );
    notifyListeners();
  }

  /// Set preset name
  void setPresetName(String name) {
    _currentPreset = _currentPreset.copyWith(name: name);
    notifyListeners();
  }

  /// Set filter combine mode
  void setFilterMode(FilterCombineMode mode) {
    _currentPreset = _currentPreset.copyWith(filterMode: mode);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FILTER MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add filter condition
  FilterCondition addFilter({
    required FilterProperty property,
    required FilterOperator operator,
    required dynamic value1,
    dynamic value2,
  }) {
    final id = 'filter_${DateTime.now().millisecondsSinceEpoch}';
    final filter = FilterCondition(
      id: id,
      property: property,
      operator: operator,
      value1: value1,
      value2: value2,
    );

    _currentPreset = _currentPreset.copyWith(
      filters: [..._currentPreset.filters, filter],
    );
    notifyListeners();
    return filter;
  }

  /// Update filter
  void updateFilter(FilterCondition filter) {
    final filters = _currentPreset.filters.map((f) {
      return f.id == filter.id ? filter : f;
    }).toList();

    _currentPreset = _currentPreset.copyWith(filters: filters);
    notifyListeners();
  }

  /// Remove filter
  void removeFilter(String filterId) {
    final filters = _currentPreset.filters.where((f) => f.id != filterId).toList();
    _currentPreset = _currentPreset.copyWith(filters: filters);
    notifyListeners();
  }

  /// Toggle filter enabled
  void toggleFilterEnabled(String filterId) {
    final filters = _currentPreset.filters.map((f) {
      if (f.id == filterId) {
        return f.copyWith(enabled: !f.enabled);
      }
      return f;
    }).toList();

    _currentPreset = _currentPreset.copyWith(filters: filters);
    notifyListeners();
  }

  /// Clear all filters
  void clearFilters() {
    _currentPreset = _currentPreset.copyWith(filters: []);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTION MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add action
  LogicalAction addAction({
    required LogicalActionType type,
    required ActionTarget target,
    dynamic value1,
    dynamic value2,
  }) {
    final id = 'action_${DateTime.now().millisecondsSinceEpoch}';
    final action = LogicalAction(
      id: id,
      type: type,
      target: target,
      value1: value1,
      value2: value2,
    );

    _currentPreset = _currentPreset.copyWith(
      actions: [..._currentPreset.actions, action],
    );
    notifyListeners();
    return action;
  }

  /// Update action
  void updateAction(LogicalAction action) {
    final actions = _currentPreset.actions.map((a) {
      return a.id == action.id ? action : a;
    }).toList();

    _currentPreset = _currentPreset.copyWith(actions: actions);
    notifyListeners();
  }

  /// Remove action
  void removeAction(String actionId) {
    final actions = _currentPreset.actions.where((a) => a.id != actionId).toList();
    _currentPreset = _currentPreset.copyWith(actions: actions);
    notifyListeners();
  }

  /// Toggle action enabled
  void toggleActionEnabled(String actionId) {
    final actions = _currentPreset.actions.map((a) {
      if (a.id == actionId) {
        return a.copyWith(enabled: !a.enabled);
      }
      return a;
    }).toList();

    _currentPreset = _currentPreset.copyWith(actions: actions);
    notifyListeners();
  }

  /// Clear all actions
  void clearActions() {
    _currentPreset = _currentPreset.copyWith(actions: []);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRESET MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Save current preset
  String savePreset({String? name, String? category}) {
    final id = 'preset_${DateTime.now().millisecondsSinceEpoch}';
    final preset = _currentPreset.copyWith(
      id: id,
      name: name ?? _currentPreset.name,
      category: category,
      isFactory: false,
    );

    _presets[id] = preset;
    notifyListeners();
    return id;
  }

  /// Load preset
  void loadPreset(String presetId) {
    final preset = _presets[presetId] ?? _factoryPresets[presetId];
    if (preset != null) {
      _currentPreset = preset.copyWith(id: 'current');
      notifyListeners();
    }
  }

  /// Delete preset
  void deletePreset(String presetId) {
    _presets.remove(presetId);
    notifyListeners();
  }

  /// Duplicate preset
  String duplicatePreset(String presetId) {
    final original = _presets[presetId] ?? _factoryPresets[presetId];
    if (original == null) throw StateError('Preset not found');

    final newId = 'preset_${DateTime.now().millisecondsSinceEpoch}';
    final copy = original.copyWith(
      id: newId,
      name: '${original.name} (Copy)',
      isFactory: false,
    );

    _presets[newId] = copy;
    notifyListeners();
    return newId;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXECUTION (Placeholder - actual execution depends on timeline/MIDI data)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if event matches all filters
  bool matchesFilters(Map<FilterProperty, dynamic> eventProperties) {
    if (_currentPreset.filters.isEmpty) return true;

    final enabledFilters = _currentPreset.filters.where((f) => f.enabled);
    if (enabledFilters.isEmpty) return true;

    if (_currentPreset.filterMode == FilterCombineMode.and) {
      // All filters must match
      for (final filter in enabledFilters) {
        final value = eventProperties[filter.property];
        if (value == null || !filter.evaluate(value)) {
          return false;
        }
      }
      return true;
    } else {
      // Any filter must match
      for (final filter in enabledFilters) {
        final value = eventProperties[filter.property];
        if (value != null && filter.evaluate(value)) {
          return true;
        }
      }
      return false;
    }
  }

  /// Apply actions to event properties
  Map<ActionTarget, dynamic> applyActions(Map<ActionTarget, dynamic> properties) {
    final result = Map<ActionTarget, dynamic>.from(properties);

    for (final action in _currentPreset.actions) {
      if (!action.enabled) continue;

      if (result.containsKey(action.target)) {
        result[action.target] = action.apply(result[action.target]);
      }
    }

    return result;
  }

  /// Set last execution results
  void setExecutionResults(int matchCount, int affectedCount) {
    _lastMatchCount = matchCount;
    _lastAffectedCount = affectedCount;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FACTORY PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  void _initFactoryPresets() {
    // Delete low velocity notes
    _factoryPresets['factory_delete_low_vel'] = LogicalEditorPreset(
      id: 'factory_delete_low_vel',
      name: 'Delete Low Velocity Notes',
      description: 'Delete notes with velocity below 20',
      category: 'Cleanup',
      filters: [
        FilterCondition(
          id: 'f1',
          property: FilterProperty.velocity,
          operator: FilterOperator.lessThan,
          value1: 20,
        ),
      ],
      actions: [
        LogicalAction(
          id: 'a1',
          type: LogicalActionType.delete,
          target: ActionTarget.velocity,
        ),
      ],
      isFactory: true,
    );

    // Double velocity
    _factoryPresets['factory_double_vel'] = LogicalEditorPreset(
      id: 'factory_double_vel',
      name: 'Double Velocity',
      description: 'Multiply all velocities by 2',
      category: 'Velocity',
      filters: [],
      actions: [
        LogicalAction(
          id: 'a1',
          type: LogicalActionType.multiply,
          target: ActionTarget.velocity,
          value1: 2.0,
        ),
      ],
      isFactory: true,
    );

    // Humanize velocity
    _factoryPresets['factory_humanize_vel'] = LogicalEditorPreset(
      id: 'factory_humanize_vel',
      name: 'Humanize Velocity',
      description: 'Add random ±10 to velocity',
      category: 'Humanize',
      filters: [],
      actions: [
        LogicalAction(
          id: 'a1',
          type: LogicalActionType.random,
          target: ActionTarget.velocity,
          value1: -10,
          value2: 10,
        ),
      ],
      isFactory: true,
    );

    // Select all muted
    _factoryPresets['factory_select_muted'] = LogicalEditorPreset(
      id: 'factory_select_muted',
      name: 'Select Muted Events',
      description: 'Select all muted notes/clips',
      category: 'Selection',
      filters: [
        FilterCondition(
          id: 'f1',
          property: FilterProperty.muted,
          operator: FilterOperator.equals,
          value1: true,
        ),
      ],
      actions: [
        LogicalAction(
          id: 'a1',
          type: LogicalActionType.select,
          target: ActionTarget.selection,
        ),
      ],
      isFactory: true,
    );

    // Transpose up octave
    _factoryPresets['factory_transpose_up'] = LogicalEditorPreset(
      id: 'factory_transpose_up',
      name: 'Transpose Up Octave',
      description: 'Move all notes up 12 semitones',
      category: 'Pitch',
      filters: [],
      actions: [
        LogicalAction(
          id: 'a1',
          type: LogicalActionType.add,
          target: ActionTarget.pitch,
          value1: 12,
        ),
      ],
      isFactory: true,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() {
    return {
      'currentPreset': _presetToJson(_currentPreset),
      'presets': _presets.values.map((p) => _presetToJson(p)).toList(),
    };
  }

  void loadFromJson(Map<String, dynamic> json) {
    if (json['currentPreset'] != null) {
      _currentPreset = _presetFromJson(json['currentPreset']);
    }

    _presets.clear();
    if (json['presets'] != null) {
      for (final p in json['presets']) {
        final preset = _presetFromJson(p);
        _presets[preset.id] = preset;
      }
    }

    _initFactoryPresets();
    notifyListeners();
  }

  Map<String, dynamic> _presetToJson(LogicalEditorPreset p) {
    return {
      'id': p.id,
      'name': p.name,
      'description': p.description,
      'category': p.category,
      'filterMode': p.filterMode.index,
      'isFactory': p.isFactory,
      'filters': p.filters.map((f) => {
        'id': f.id,
        'property': f.property.index,
        'operator': f.operator.index,
        'value1': f.value1,
        'value2': f.value2,
        'enabled': f.enabled,
      }).toList(),
      'actions': p.actions.map((a) => {
        'id': a.id,
        'type': a.type.index,
        'target': a.target.index,
        'value1': a.value1,
        'value2': a.value2,
        'enabled': a.enabled,
      }).toList(),
    };
  }

  LogicalEditorPreset _presetFromJson(Map<String, dynamic> json) {
    return LogicalEditorPreset(
      id: json['id'] ?? 'preset',
      name: json['name'] ?? 'Preset',
      description: json['description'],
      category: json['category'],
      filterMode: FilterCombineMode.values[json['filterMode'] ?? 0],
      isFactory: json['isFactory'] ?? false,
      filters: (json['filters'] as List?)?.map((f) => FilterCondition(
        id: f['id'],
        property: FilterProperty.values[f['property'] ?? 0],
        operator: FilterOperator.values[f['operator'] ?? 0],
        value1: f['value1'],
        value2: f['value2'],
        enabled: f['enabled'] ?? true,
      )).toList() ?? [],
      actions: (json['actions'] as List?)?.map((a) => LogicalAction(
        id: a['id'],
        type: LogicalActionType.values[a['type'] ?? 0],
        target: ActionTarget.values[a['target'] ?? 0],
        value1: a['value1'],
        value2: a['value2'],
        enabled: a['enabled'] ?? true,
      )).toList() ?? [],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INIT / RESET
  // ═══════════════════════════════════════════════════════════════════════════

  LogicalEditorProvider() {
    _initFactoryPresets();
  }

  void reset() {
    _currentPreset = LogicalEditorPreset(id: 'current', name: 'Untitled');
    _presets.clear();
    _lastMatchCount = 0;
    _lastAffectedCount = 0;
    _initFactoryPresets();
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
