/// Undo Manager for Flutter UI actions
///
/// Provides undo/redo functionality for UI-level actions like:
/// - Clip move/resize
/// - Track add/delete
/// - Parameter changes
/// - Zoom changes

import 'package:flutter/foundation.dart';

/// Base class for undoable actions
abstract class UndoableAction {
  String get description;
  void execute();
  void undo();
}

/// Clip move action
class ClipMoveAction extends UndoableAction {
  final String clipId;
  final double oldStartTime;
  final double newStartTime;
  final String? oldTrackId;
  final String? newTrackId;
  final VoidCallback onExecute;
  final VoidCallback onUndo;

  ClipMoveAction({
    required this.clipId,
    required this.oldStartTime,
    required this.newStartTime,
    this.oldTrackId,
    this.newTrackId,
    required this.onExecute,
    required this.onUndo,
  });

  @override
  String get description => 'Move clip';

  @override
  void execute() => onExecute();

  @override
  void undo() => onUndo();
}

/// Track add action
class TrackAddAction extends UndoableAction {
  final String trackId;
  final VoidCallback onExecute;
  final VoidCallback onUndo;

  TrackAddAction({
    required this.trackId,
    required this.onExecute,
    required this.onUndo,
  });

  @override
  String get description => 'Add track';

  @override
  void execute() => onExecute();

  @override
  void undo() => onUndo();
}

/// Track delete action
class TrackDeleteAction extends UndoableAction {
  final String trackId;
  final VoidCallback onExecute;
  final VoidCallback onUndo;

  TrackDeleteAction({
    required this.trackId,
    required this.onExecute,
    required this.onUndo,
  });

  @override
  String get description => 'Delete track';

  @override
  void execute() => onExecute();

  @override
  void undo() => onUndo();
}

/// Generic action for any undoable operation
class GenericUndoAction extends UndoableAction {
  final String _description;
  final VoidCallback onExecute;
  final VoidCallback onUndo;

  GenericUndoAction({
    required String description,
    required this.onExecute,
    required this.onUndo,
  }) : _description = description;

  @override
  String get description => _description;

  @override
  void execute() => onExecute();

  @override
  void undo() => onUndo();
}

/// Undo Manager - manages undo/redo stack
class UiUndoManager extends ChangeNotifier {
  static final UiUndoManager _instance = UiUndoManager._internal();
  factory UiUndoManager() => _instance;
  UiUndoManager._internal();

  static UiUndoManager get instance => _instance;

  final List<UndoableAction> _undoStack = [];
  final List<UndoableAction> _redoStack = [];
  static const int _maxStackSize = 100;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  String? get undoDescription => _undoStack.isNotEmpty ? _undoStack.last.description : null;
  String? get redoDescription => _redoStack.isNotEmpty ? _redoStack.last.description : null;

  /// Execute an action and add to undo stack
  void execute(UndoableAction action) {
    action.execute();
    _undoStack.add(action);
    _redoStack.clear(); // Clear redo stack on new action

    // Limit stack size
    if (_undoStack.length > _maxStackSize) {
      _undoStack.removeAt(0);
    }

    debugPrint('[UiUndoManager] Executed: ${action.description} (stack: ${_undoStack.length})');
    notifyListeners();
  }

  /// Add action to undo stack without executing (for actions already done)
  void record(UndoableAction action) {
    _undoStack.add(action);
    _redoStack.clear();

    if (_undoStack.length > _maxStackSize) {
      _undoStack.removeAt(0);
    }

    debugPrint('[UiUndoManager] Recorded: ${action.description} (stack: ${_undoStack.length})');
    notifyListeners();
  }

  /// Undo last action
  bool undo() {
    if (!canUndo) return false;

    final action = _undoStack.removeLast();
    action.undo();
    _redoStack.add(action);

    debugPrint('[UiUndoManager] Undo: ${action.description}');
    notifyListeners();
    return true;
  }

  /// Redo last undone action
  bool redo() {
    if (!canRedo) return false;

    final action = _redoStack.removeLast();
    action.execute();
    _undoStack.add(action);

    debugPrint('[UiUndoManager] Redo: ${action.description}');
    notifyListeners();
    return true;
  }

  /// Clear all undo/redo history
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }
}
