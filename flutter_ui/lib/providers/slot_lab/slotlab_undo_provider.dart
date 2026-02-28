/// SlotLab Undo/Redo Provider — Middleware §30
///
/// Global 100-step undo/redo stack for all SlotLab operations.
/// Tracks behavior tree changes, sound assignments, parameter edits,
/// context overrides, and configuration changes.
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §30

import 'package:flutter/foundation.dart';

/// Types of undoable operations
enum UndoOperationType {
  nodeParamChange,
  soundAssignment,
  soundRemoval,
  contextOverride,
  playbackModeChange,
  variantConfigChange,
  transitionRuleChange,
  templateApply,
  autoBind,
  bulkOperation,
}

/// A single undoable action
class UndoAction {
  final String id;
  final UndoOperationType type;
  final String description;
  final DateTime timestamp;

  /// Serialized state BEFORE the action (for undo)
  final Map<String, dynamic> beforeState;

  /// Serialized state AFTER the action (for redo)
  final Map<String, dynamic> afterState;

  /// Affected node IDs
  final List<String> affectedNodeIds;

  const UndoAction({
    required this.id,
    required this.type,
    required this.description,
    required this.timestamp,
    required this.beforeState,
    required this.afterState,
    this.affectedNodeIds = const [],
  });
}

class SlotLabUndoProvider extends ChangeNotifier {
  final List<UndoAction> _undoStack = [];
  final List<UndoAction> _redoStack = [];
  static const int _maxStackSize = 100;

  /// Callback to apply state (set by the coordinator)
  Function(Map<String, dynamic>)? onApplyState;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;

  String? get undoDescription => _undoStack.isNotEmpty ? _undoStack.last.description : null;
  String? get redoDescription => _redoStack.isNotEmpty ? _redoStack.last.description : null;

  List<UndoAction> get undoHistory => List.unmodifiable(_undoStack);

  // ═══════════════════════════════════════════════════════════════════════════
  // OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Record a new action (push to undo stack, clear redo)
  void record(UndoAction action) {
    _undoStack.add(action);
    _redoStack.clear();

    // Enforce max stack size
    while (_undoStack.length > _maxStackSize) {
      _undoStack.removeAt(0);
    }

    notifyListeners();
  }

  /// Convenience method to record from before/after state snapshots
  void recordChange({
    required UndoOperationType type,
    required String description,
    required Map<String, dynamic> beforeState,
    required Map<String, dynamic> afterState,
    List<String> affectedNodeIds = const [],
  }) {
    record(UndoAction(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      description: description,
      timestamp: DateTime.now(),
      beforeState: beforeState,
      afterState: afterState,
      affectedNodeIds: affectedNodeIds,
    ));
  }

  /// Undo last action
  bool undo() {
    if (!canUndo) return false;

    final action = _undoStack.removeLast();
    _redoStack.add(action);

    // Apply before state
    onApplyState?.call(action.beforeState);

    notifyListeners();
    return true;
  }

  /// Redo last undone action
  bool redo() {
    if (!canRedo) return false;

    final action = _redoStack.removeLast();
    _undoStack.add(action);

    // Apply after state
    onApplyState?.call(action.afterState);

    notifyListeners();
    return true;
  }

  /// Clear all history
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }
}
