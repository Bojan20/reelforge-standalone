/// Project History Provider
///
/// Undo/Redo system using command pattern:
/// - Stack-based history
/// - Maximum 20 states
/// - Deep clone on save

import 'dart:convert';
import 'package:flutter/foundation.dart';

// ============ Types ============

/// Serializable project state for history
class ProjectSnapshot {
  final String data;
  final DateTime timestamp;
  final String? label;

  const ProjectSnapshot({
    required this.data,
    required this.timestamp,
    this.label,
  });
}

// ============ Provider ============

class ProjectHistoryProvider extends ChangeNotifier {
  final List<ProjectSnapshot> _history = [];
  int _historyIndex = -1;
  static const int _maxHistory = 20;

  bool get canUndo => _historyIndex > 0;
  bool get canRedo => _historyIndex < _history.length - 1;
  int get historyLength => _history.length;
  int get currentIndex => _historyIndex;

  /// Save current state to history
  void saveToHistory(dynamic project, {String? label}) {
    // Serialize to JSON string (deep clone)
    final data = jsonEncode(project);

    // Remove any redo states
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }

    // Add new state
    _history.add(ProjectSnapshot(
      data: data,
      timestamp: DateTime.now(),
      label: label,
    ));

    // Trim to max size
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
    }

    _historyIndex = _history.length - 1;
    notifyListeners();
  }

  /// Undo - return previous state or null
  String? undo() {
    if (!canUndo) return null;

    _historyIndex--;
    notifyListeners();
    return _history[_historyIndex].data;
  }

  /// Redo - return next state or null
  String? redo() {
    if (!canRedo) return null;

    _historyIndex++;
    notifyListeners();
    return _history[_historyIndex].data;
  }

  /// Get current state data
  String? get currentState {
    if (_historyIndex < 0 || _historyIndex >= _history.length) return null;
    return _history[_historyIndex].data;
  }

  /// Reset history
  void reset() {
    _history.clear();
    _historyIndex = -1;
    notifyListeners();
  }

  /// Get history entries for display
  List<({int index, String label, DateTime timestamp})> getHistoryEntries() {
    return _history.asMap().entries.map((e) {
      return (
        index: e.key,
        label: e.value.label ?? 'State ${e.key + 1}',
        timestamp: e.value.timestamp,
      );
    }).toList();
  }

  /// Jump to specific history index
  String? jumpTo(int index) {
    if (index < 0 || index >= _history.length) return null;

    _historyIndex = index;
    notifyListeners();
    return _history[_historyIndex].data;
  }
}
