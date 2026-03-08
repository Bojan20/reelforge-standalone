/// Config Undo Manager — Snapshot-based undo/redo for CONFIG tab
///
/// Captures full JSON snapshots of:
/// - Win tier configuration (SlotWinConfiguration)
/// - Scene transition configs (Map of String to SceneTransitionConfig)
/// - Symbol artwork assignments (Map of symbolId to artworkPath)
///
/// 100-step stack, follows SlotLabUndoProvider pattern.
/// Merge window: 500ms — rapid slider drags collapse into single undo entry.

import 'package:flutter/foundation.dart';

/// Categories of CONFIG mutations for undo description
enum ConfigUndoCategory {
  winTier('Win Tier'),
  bigWinTier('Big Win Tier'),
  winConfig('Win Config'),
  transition('Transition'),
  symbolArtwork('Symbol Artwork');

  final String label;
  const ConfigUndoCategory(this.label);
}

/// Full CONFIG state snapshot
class ConfigSnapshot {
  final Map<String, dynamic> winConfigJson;
  final Map<String, Map<String, dynamic>> transitionConfigsJson;
  final Map<String, dynamic> defaultTransitionJson;
  final Map<String, String?> symbolArtwork;

  const ConfigSnapshot({
    required this.winConfigJson,
    required this.transitionConfigsJson,
    required this.defaultTransitionJson,
    required this.symbolArtwork,
  });

  Map<String, dynamic> toJson() => {
    'winConfig': winConfigJson,
    'transitionConfigs': transitionConfigsJson,
    'defaultTransition': defaultTransitionJson,
    'symbolArtwork': symbolArtwork,
  };

  factory ConfigSnapshot.fromJson(Map<String, dynamic> json) {
    return ConfigSnapshot(
      winConfigJson: json['winConfig'] as Map<String, dynamic>? ?? {},
      transitionConfigsJson: (json['transitionConfigs'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v as Map<String, dynamic>)) ?? {},
      defaultTransitionJson: json['defaultTransition'] as Map<String, dynamic>? ?? {},
      symbolArtwork: (json['symbolArtwork'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v as String?)) ?? {},
    );
  }
}

/// Single undo entry
class ConfigUndoEntry {
  final String id;
  final ConfigUndoCategory category;
  final String description;
  final DateTime timestamp;
  final ConfigSnapshot beforeState;
  final ConfigSnapshot afterState;

  const ConfigUndoEntry({
    required this.id,
    required this.category,
    required this.description,
    required this.timestamp,
    required this.beforeState,
    required this.afterState,
  });
}

/// Config Undo Manager — 100-step snapshot stack
class ConfigUndoManager extends ChangeNotifier {
  final List<ConfigUndoEntry> _undoStack = [];
  final List<ConfigUndoEntry> _redoStack = [];
  static const int _maxStackSize = 100;
  static const int _mergeWindowMs = 500;

  /// Callback to capture current state
  ConfigSnapshot Function()? onCaptureState;

  /// Callback to restore state from snapshot
  void Function(ConfigSnapshot snapshot)? onRestoreState;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;
  String? get undoDescription => _undoStack.isNotEmpty ? _undoStack.last.description : null;
  String? get redoDescription => _redoStack.isNotEmpty ? _redoStack.last.description : null;

  // ═══════════════════════════════════════════════════════════════════════════
  // RECORD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Capture state before mutation. Returns snapshot for pairing with recordAfter.
  ConfigSnapshot captureBeforeState() {
    assert(onCaptureState != null, 'onCaptureState must be set');
    return onCaptureState!();
  }

  /// Record a mutation. Call AFTER the change is applied.
  void recordAfter({
    required ConfigSnapshot beforeState,
    required ConfigUndoCategory category,
    required String description,
  }) {
    final afterState = onCaptureState!();
    final now = DateTime.now();

    // Merge window: collapse rapid changes of same category AND description
    // (description includes tier name, so different tiers won't merge)
    if (_undoStack.isNotEmpty) {
      final last = _undoStack.last;
      if (last.category == category &&
          last.description == description &&
          now.difference(last.timestamp).inMilliseconds < _mergeWindowMs) {
        // Replace last entry's afterState, keep original beforeState
        _undoStack[_undoStack.length - 1] = ConfigUndoEntry(
          id: last.id,
          category: category,
          description: description,
          timestamp: now,
          beforeState: last.beforeState,
          afterState: afterState,
        );
        _redoStack.clear();
        notifyListeners();
        return;
      }
    }

    final entry = ConfigUndoEntry(
      id: '${now.millisecondsSinceEpoch}',
      category: category,
      description: description,
      timestamp: now,
      beforeState: beforeState,
      afterState: afterState,
    );

    _undoStack.add(entry);
    if (_undoStack.length > _maxStackSize) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UNDO / REDO
  // ═══════════════════════════════════════════════════════════════════════════

  void undo() {
    if (!canUndo || onRestoreState == null) return;
    final entry = _undoStack.removeLast();
    _redoStack.add(entry);
    onRestoreState!(entry.beforeState);
    notifyListeners();
  }

  void redo() {
    if (!canRedo || onRestoreState == null) return;
    final entry = _redoStack.removeLast();
    _undoStack.add(entry);
    onRestoreState!(entry.afterState);
    notifyListeners();
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  /// Clear capture/restore callbacks to release provider references.
  /// Called from SlotLab dispose() to prevent closure memory leaks.
  void clearCallbacks() {
    onCaptureState = null;
    onRestoreState = null;
  }

  /// Handle Cmd+Z / Cmd+Shift+Z. Returns true if handled.
  bool handleUndoKey(bool isShiftPressed) {
    if (isShiftPressed && canRedo) {
      redo();
      return true;
    } else if (!isShiftPressed && canUndo) {
      undo();
      return true;
    }
    return false;
  }
}
