/// Panel Undo Manager — Local Undo Stack per Panel
///
/// P2.2: Provides panel-specific undo/redo functionality.
///
/// Each DSP panel or editor can have its own undo history, separate from
/// the global UiUndoManager. This allows:
/// - Independent undo stacks per panel
/// - Panel-specific keyboard shortcuts (Cmd+Z within panel)
/// - Session-scoped history (cleared when panel closes)
/// - Parameter change grouping
///
/// Usage:
/// ```dart
/// final undoManager = PanelUndoManager(panelId: 'eq_panel_track_0');
///
/// // Record a parameter change
/// undoManager.recordParameterChange(
///   parameterId: 'band_0_freq',
///   oldValue: 1000.0,
///   newValue: 2000.0,
///   description: 'Change Band 1 Frequency',
/// );
///
/// // Undo
/// undoManager.undo();
///
/// // Redo
/// undoManager.redo();
/// ```

import 'dart:async';
import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PANEL UNDO ACTION
// ═══════════════════════════════════════════════════════════════════════════════

/// Base class for panel-level undoable actions
abstract class PanelUndoAction {
  final String panelId;
  final String description;
  final DateTime timestamp;

  PanelUndoAction({
    required this.panelId,
    required this.description,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  void execute();
  void undo();

  /// Merge with another action of the same type (for continuous changes like dragging)
  bool canMergeWith(PanelUndoAction other) => false;
  PanelUndoAction mergeWith(PanelUndoAction other) => this;
}

/// Parameter change action (e.g., knob turn, slider move)
class ParameterChangeAction extends PanelUndoAction {
  final String parameterId;
  final dynamic oldValue;
  final dynamic newValue;
  final void Function(dynamic value)? onApply;

  ParameterChangeAction({
    required super.panelId,
    required this.parameterId,
    required this.oldValue,
    required this.newValue,
    required super.description,
    this.onApply,
    super.timestamp,
  });

  @override
  void execute() {
    onApply?.call(newValue);
  }

  @override
  void undo() {
    onApply?.call(oldValue);
  }

  @override
  bool canMergeWith(PanelUndoAction other) {
    if (other is! ParameterChangeAction) return false;
    if (other.parameterId != parameterId) return false;
    if (other.panelId != panelId) return false;
    // Only merge if within 500ms
    final timeDiff = timestamp.difference(other.timestamp).abs();
    return timeDiff.inMilliseconds < 500;
  }

  @override
  PanelUndoAction mergeWith(PanelUndoAction other) {
    if (other is! ParameterChangeAction) return this;
    // Keep the original oldValue, but use our newValue
    return ParameterChangeAction(
      panelId: panelId,
      parameterId: parameterId,
      oldValue: other.oldValue,
      newValue: newValue,
      description: description,
      onApply: onApply,
      timestamp: other.timestamp,
    );
  }
}

/// Batch parameter change (e.g., preset load, reset all)
class BatchParameterChangeAction extends PanelUndoAction {
  final Map<String, dynamic> oldValues;
  final Map<String, dynamic> newValues;
  final void Function(Map<String, dynamic> values)? onApply;

  BatchParameterChangeAction({
    required super.panelId,
    required this.oldValues,
    required this.newValues,
    required super.description,
    this.onApply,
    super.timestamp,
  });

  @override
  void execute() {
    onApply?.call(newValues);
  }

  @override
  void undo() {
    onApply?.call(oldValues);
  }
}

/// EQ band add/remove action
class EqBandAction extends PanelUndoAction {
  final int bandIndex;
  final Map<String, dynamic>? bandData;
  final bool isAdd;
  final void Function(int index, Map<String, dynamic>? data, bool add)? onApply;

  EqBandAction({
    required super.panelId,
    required this.bandIndex,
    required this.bandData,
    required this.isAdd,
    required super.description,
    this.onApply,
    super.timestamp,
  });

  @override
  void execute() {
    onApply?.call(bandIndex, bandData, isAdd);
  }

  @override
  void undo() {
    onApply?.call(bandIndex, bandData, !isAdd);
  }
}

/// Preset change action
class PresetChangeAction extends PanelUndoAction {
  final String? oldPresetId;
  final String? newPresetId;
  final Map<String, dynamic> oldState;
  final Map<String, dynamic> newState;
  final void Function(String? presetId, Map<String, dynamic> state)? onApply;

  PresetChangeAction({
    required super.panelId,
    required this.oldPresetId,
    required this.newPresetId,
    required this.oldState,
    required this.newState,
    required super.description,
    this.onApply,
    super.timestamp,
  });

  @override
  void execute() {
    onApply?.call(newPresetId, newState);
  }

  @override
  void undo() {
    onApply?.call(oldPresetId, oldState);
  }
}

/// A/B state switch action
class ABSwitchAction extends PanelUndoAction {
  final bool wasStateA;
  final Map<String, dynamic> stateA;
  final Map<String, dynamic> stateB;
  final void Function(bool isStateA, Map<String, dynamic> state)? onApply;

  ABSwitchAction({
    required super.panelId,
    required this.wasStateA,
    required this.stateA,
    required this.stateB,
    required super.description,
    this.onApply,
    super.timestamp,
  });

  @override
  void execute() {
    final newState = !wasStateA;
    onApply?.call(newState, newState ? stateA : stateB);
  }

  @override
  void undo() {
    onApply?.call(wasStateA, wasStateA ? stateA : stateB);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PANEL UNDO MANAGER
// ═══════════════════════════════════════════════════════════════════════════════

/// Panel-local undo manager
class PanelUndoManager extends ChangeNotifier {
  final String panelId;
  final int maxStackSize;
  final Duration mergeWindow;

  final List<PanelUndoAction> _undoStack = [];
  final List<PanelUndoAction> _redoStack = [];

  // Merge timer for continuous changes
  Timer? _mergeTimer;
  PanelUndoAction? _pendingAction;

  PanelUndoManager({
    required this.panelId,
    this.maxStackSize = 50,
    this.mergeWindow = const Duration(milliseconds: 500),
  });

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  String? get undoDescription => _undoStack.isNotEmpty ? _undoStack.last.description : null;
  String? get redoDescription => _redoStack.isNotEmpty ? _redoStack.last.description : null;

  int get undoStackSize => _undoStack.length;
  int get redoStackSize => _redoStack.length;

  List<PanelUndoAction> get undoHistory => _undoStack.reversed.toList();
  List<PanelUndoAction> get redoHistory => _redoStack.toList();

  /// Record a parameter change with automatic merging for continuous changes
  void recordParameterChange({
    required String parameterId,
    required dynamic oldValue,
    required dynamic newValue,
    required String description,
    void Function(dynamic value)? onApply,
    bool merge = true,
  }) {
    final action = ParameterChangeAction(
      panelId: panelId,
      parameterId: parameterId,
      oldValue: oldValue,
      newValue: newValue,
      description: description,
      onApply: onApply,
    );

    if (merge) {
      _recordWithMerge(action);
    } else {
      _recordAction(action);
    }
  }

  /// Record a batch parameter change (preset load, reset)
  void recordBatchChange({
    required Map<String, dynamic> oldValues,
    required Map<String, dynamic> newValues,
    required String description,
    void Function(Map<String, dynamic> values)? onApply,
  }) {
    _flushPendingAction();
    _recordAction(BatchParameterChangeAction(
      panelId: panelId,
      oldValues: oldValues,
      newValues: newValues,
      description: description,
      onApply: onApply,
    ));
  }

  /// Record an EQ band add/remove
  void recordEqBandChange({
    required int bandIndex,
    Map<String, dynamic>? bandData,
    required bool isAdd,
    required String description,
    void Function(int index, Map<String, dynamic>? data, bool add)? onApply,
  }) {
    _flushPendingAction();
    _recordAction(EqBandAction(
      panelId: panelId,
      bandIndex: bandIndex,
      bandData: bandData,
      isAdd: isAdd,
      description: description,
      onApply: onApply,
    ));
  }

  /// Record a preset change
  void recordPresetChange({
    String? oldPresetId,
    String? newPresetId,
    required Map<String, dynamic> oldState,
    required Map<String, dynamic> newState,
    required String description,
    void Function(String? presetId, Map<String, dynamic> state)? onApply,
  }) {
    _flushPendingAction();
    _recordAction(PresetChangeAction(
      panelId: panelId,
      oldPresetId: oldPresetId,
      newPresetId: newPresetId,
      oldState: oldState,
      newState: newState,
      description: description,
      onApply: onApply,
    ));
  }

  /// Record an A/B switch
  void recordABSwitch({
    required bool wasStateA,
    required Map<String, dynamic> stateA,
    required Map<String, dynamic> stateB,
    required String description,
    void Function(bool isStateA, Map<String, dynamic> state)? onApply,
  }) {
    _flushPendingAction();
    _recordAction(ABSwitchAction(
      panelId: panelId,
      wasStateA: wasStateA,
      stateA: stateA,
      stateB: stateB,
      description: description,
      onApply: onApply,
    ));
  }

  /// Execute and record a generic action
  void execute(PanelUndoAction action) {
    _flushPendingAction();
    action.execute();
    _recordAction(action);
  }

  /// Record an already-executed action
  void record(PanelUndoAction action) {
    _flushPendingAction();
    _recordAction(action);
  }

  /// Undo last action
  bool undo() {
    _flushPendingAction();
    if (!canUndo) return false;

    final action = _undoStack.removeLast();
    action.undo();
    _redoStack.add(action);

    debugPrint('[PanelUndoManager:$panelId] Undo: ${action.description}');
    notifyListeners();
    return true;
  }

  /// Redo last undone action
  bool redo() {
    _flushPendingAction();
    if (!canRedo) return false;

    final action = _redoStack.removeLast();
    action.execute();
    _undoStack.add(action);

    debugPrint('[PanelUndoManager:$panelId] Redo: ${action.description}');
    notifyListeners();
    return true;
  }

  /// Clear all history
  void clear() {
    _flushPendingAction();
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  /// Undo to a specific point
  void undoTo(int index) {
    _flushPendingAction();
    final countToUndo = index + 1;
    for (int i = 0; i < countToUndo && canUndo; i++) {
      undo();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRIVATE METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  void _recordAction(PanelUndoAction action) {
    _undoStack.add(action);
    _redoStack.clear();

    // Limit stack size
    while (_undoStack.length > maxStackSize) {
      _undoStack.removeAt(0);
    }

    notifyListeners();
  }

  void _recordWithMerge(PanelUndoAction action) {
    _mergeTimer?.cancel();

    if (_pendingAction != null && _pendingAction!.canMergeWith(action)) {
      // Merge with pending action
      _pendingAction = action.mergeWith(_pendingAction!);
    } else {
      // Flush previous pending action
      if (_pendingAction != null) {
        _recordAction(_pendingAction!);
      }
      _pendingAction = action;
    }

    // Schedule flush
    _mergeTimer = Timer(mergeWindow, _flushPendingAction);
  }

  void _flushPendingAction() {
    _mergeTimer?.cancel();
    _mergeTimer = null;

    if (_pendingAction != null) {
      _recordAction(_pendingAction!);
      _pendingAction = null;
    }
  }

  @override
  void dispose() {
    _mergeTimer?.cancel();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PANEL UNDO REGISTRY — Global registry for panel undo managers
// ═══════════════════════════════════════════════════════════════════════════════

/// Registry for managing multiple panel undo managers
class PanelUndoRegistry {
  static final PanelUndoRegistry _instance = PanelUndoRegistry._internal();
  factory PanelUndoRegistry() => _instance;
  PanelUndoRegistry._internal();

  static PanelUndoRegistry get instance => _instance;

  final Map<String, PanelUndoManager> _managers = {};

  /// Get or create undo manager for a panel
  PanelUndoManager getManager(String panelId) {
    return _managers.putIfAbsent(
      panelId,
      () => PanelUndoManager(panelId: panelId),
    );
  }

  /// Remove undo manager for a panel (clears history)
  void removeManager(String panelId) {
    final manager = _managers.remove(panelId);
    manager?.dispose();
  }

  /// Clear all managers
  void clearAll() {
    for (final manager in _managers.values) {
      manager.dispose();
    }
    _managers.clear();
  }

  /// Get all active panel IDs
  List<String> get activePanels => _managers.keys.toList();

  /// Check if a panel has undo history
  bool hasUndoHistory(String panelId) {
    return _managers[panelId]?.canUndo ?? false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PANEL UNDO MIXIN — Easy integration with StatefulWidgets
// ═══════════════════════════════════════════════════════════════════════════════

/// Helper class for integrating panel undo with a StatefulWidget
///
/// Usage:
/// ```dart
/// class _MyPanelState extends State<MyPanel> {
///   late final PanelUndoHelper _undoHelper;
///
///   @override
///   void initState() {
///     super.initState();
///     _undoHelper = PanelUndoHelper(
///       panelId: 'my_panel',
///       onChanged: () => setState(() {}),
///     );
///   }
///
///   @override
///   void dispose() {
///     _undoHelper.dispose();
///     super.dispose();
///   }
/// }
/// ```
class PanelUndoHelper {
  final String panelId;
  final VoidCallback? onChanged;
  final PanelUndoManager manager;

  PanelUndoHelper({
    required this.panelId,
    this.onChanged,
  }) : manager = PanelUndoRegistry.instance.getManager(panelId) {
    if (onChanged != null) {
      manager.addListener(onChanged!);
    }
  }

  /// Record a parameter change
  void recordParam(String parameterId, dynamic oldValue, dynamic newValue, String description) {
    manager.recordParameterChange(
      parameterId: parameterId,
      oldValue: oldValue,
      newValue: newValue,
      description: description,
    );
  }

  /// Handle Cmd+Z / Cmd+Shift+Z within panel
  bool handleUndoKey(bool isShiftPressed) {
    if (isShiftPressed) {
      return manager.redo();
    } else {
      return manager.undo();
    }
  }

  void dispose() {
    if (onChanged != null) {
      manager.removeListener(onChanged!);
    }
  }
}
