/// Symbol Audio Batch Replace Service
///
/// P12.1.1: Batch operations for symbol audio in SlotLab:
/// - Replace audio across all symbols matching a pattern
/// - Find and replace audio paths
/// - Preview before applying changes
/// - Undo/redo support
///
/// Usage:
/// ```dart
/// final service = SymbolAudioBatchService.instance;
///
/// // Find all symbols using a specific audio
/// final matches = service.findSymbolsByAudio(assignments, 'old_sound.wav');
///
/// // Preview replacement
/// final preview = service.previewReplace(assignments, 'old', 'new');
///
/// // Apply batch replacement
/// final result = service.batchReplace(assignments, pattern: 'old', replacement: 'new');
/// ```

import 'package:flutter/foundation.dart';
import '../models/slot_lab_models.dart';

/// Result of a batch operation
class BatchOperationResult {
  /// Number of items modified
  final int modifiedCount;

  /// Total items checked
  final int totalChecked;

  /// Modified assignments (for undo)
  final List<SymbolAudioAssignment> modifiedAssignments;

  /// Original assignments before modification (for undo)
  final List<SymbolAudioAssignment> originalAssignments;

  /// Error message if operation failed
  final String? error;

  const BatchOperationResult({
    required this.modifiedCount,
    required this.totalChecked,
    required this.modifiedAssignments,
    required this.originalAssignments,
    this.error,
  });

  /// Whether operation was successful
  bool get success => error == null;

  /// Whether any items were modified
  bool get hasChanges => modifiedCount > 0;

  @override
  String toString() =>
      'BatchOperationResult(modified: $modifiedCount/$totalChecked, error: $error)';
}

/// Preview entry for batch replacement
class BatchPreviewEntry {
  /// Symbol ID
  final String symbolId;

  /// Context (land, win, expand, etc.)
  final String context;

  /// Original audio path
  final String originalPath;

  /// New audio path after replacement
  final String newPath;

  /// Whether this entry will be modified
  final bool willModify;

  const BatchPreviewEntry({
    required this.symbolId,
    required this.context,
    required this.originalPath,
    required this.newPath,
    required this.willModify,
  });

  @override
  String toString() =>
      'BatchPreviewEntry($symbolId.$context: $originalPath -> $newPath)';
}

/// Match filter for finding symbols
enum MatchFilter {
  /// Match by exact audio path
  exactPath,

  /// Match by filename pattern (contains)
  filenameContains,

  /// Match by symbol type
  symbolType,

  /// Match by context
  context,

  /// Match by regex pattern on path
  regex,
}

/// Symbol Audio Batch Replace Service — Singleton
class SymbolAudioBatchService extends ChangeNotifier {
  // ─── Singleton ───────────────────────────────────────────────────────────────
  static SymbolAudioBatchService? _instance;
  static SymbolAudioBatchService get instance =>
      _instance ??= SymbolAudioBatchService._();

  SymbolAudioBatchService._();

  // ─── Undo History ────────────────────────────────────────────────────────────
  final List<BatchOperationResult> _undoStack = [];
  final List<BatchOperationResult> _redoStack = [];
  static const int _maxUndoHistory = 20;

  /// Check if undo is available
  bool get canUndo => _undoStack.isNotEmpty;

  /// Check if redo is available
  bool get canRedo => _redoStack.isNotEmpty;

  /// Get undo description
  String? get undoDescription {
    if (_undoStack.isEmpty) return null;
    final last = _undoStack.last;
    return 'Undo: Replace ${last.modifiedCount} audio assignments';
  }

  /// Get redo description
  String? get redoDescription {
    if (_redoStack.isEmpty) return null;
    final last = _redoStack.last;
    return 'Redo: Replace ${last.modifiedCount} audio assignments';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FIND OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Find all symbol audio assignments matching a specific audio path
  List<SymbolAudioAssignment> findByExactPath(
    List<SymbolAudioAssignment> assignments,
    String audioPath,
  ) {
    return assignments.where((a) => a.audioPath == audioPath).toList();
  }

  /// Find all symbol audio assignments where path contains pattern
  List<SymbolAudioAssignment> findByPathContains(
    List<SymbolAudioAssignment> assignments,
    String pattern, {
    bool caseSensitive = false,
  }) {
    final searchPattern = caseSensitive ? pattern : pattern.toLowerCase();
    return assignments.where((a) {
      final path = caseSensitive ? a.audioPath : a.audioPath.toLowerCase();
      return path.contains(searchPattern);
    }).toList();
  }

  /// Find all symbol audio assignments for a specific symbol
  List<SymbolAudioAssignment> findBySymbolId(
    List<SymbolAudioAssignment> assignments,
    String symbolId,
  ) {
    return assignments.where((a) => a.symbolId == symbolId).toList();
  }

  /// Find all symbol audio assignments for a specific context
  List<SymbolAudioAssignment> findByContext(
    List<SymbolAudioAssignment> assignments,
    String context,
  ) {
    return assignments.where((a) => a.context == context).toList();
  }

  /// Find symbol audio using regex pattern
  List<SymbolAudioAssignment> findByRegex(
    List<SymbolAudioAssignment> assignments,
    String regexPattern,
  ) {
    try {
      final regex = RegExp(regexPattern);
      return assignments.where((a) => regex.hasMatch(a.audioPath)).toList();
    } catch (e) {
      debugPrint('[SymbolAudioBatch] Invalid regex: $regexPattern - $e');
      return [];
    }
  }

  /// Find symbols with missing audio (path doesn't exist)
  List<SymbolAudioAssignment> findWithMissingAudio(
    List<SymbolAudioAssignment> assignments,
  ) {
    return assignments.where((a) => a.audioPath.isEmpty).toList();
  }

  /// Find duplicate audio assignments (same audio used for multiple symbols)
  Map<String, List<SymbolAudioAssignment>> findDuplicates(
    List<SymbolAudioAssignment> assignments,
  ) {
    final pathMap = <String, List<SymbolAudioAssignment>>{};
    for (final assignment in assignments) {
      if (assignment.audioPath.isNotEmpty) {
        pathMap.putIfAbsent(assignment.audioPath, () => []).add(assignment);
      }
    }
    // Return only entries with duplicates
    pathMap.removeWhere((_, list) => list.length < 2);
    return pathMap;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PREVIEW OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Preview replacement operation without modifying
  List<BatchPreviewEntry> previewReplace(
    List<SymbolAudioAssignment> assignments, {
    required String pattern,
    required String replacement,
    bool caseSensitive = false,
    bool useRegex = false,
  }) {
    final entries = <BatchPreviewEntry>[];

    for (final assignment in assignments) {
      String newPath;

      if (useRegex) {
        try {
          final regex = RegExp(pattern);
          newPath = assignment.audioPath.replaceAll(regex, replacement);
        } catch (_) {
          newPath = assignment.audioPath;
        }
      } else if (caseSensitive) {
        newPath = assignment.audioPath.replaceAll(pattern, replacement);
      } else {
        newPath = _replaceIgnoreCase(assignment.audioPath, pattern, replacement);
      }

      entries.add(BatchPreviewEntry(
        symbolId: assignment.symbolId,
        context: assignment.context,
        originalPath: assignment.audioPath,
        newPath: newPath,
        willModify: newPath != assignment.audioPath,
      ));
    }

    return entries;
  }

  /// Preview setting all assignments to a single audio file
  List<BatchPreviewEntry> previewSetAll(
    List<SymbolAudioAssignment> assignments,
    String newAudioPath,
  ) {
    return assignments
        .map((a) => BatchPreviewEntry(
              symbolId: a.symbolId,
              context: a.context,
              originalPath: a.audioPath,
              newPath: newAudioPath,
              willModify: a.audioPath != newAudioPath,
            ))
        .toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BATCH MODIFICATION OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Batch replace audio paths matching a pattern
  ///
  /// Returns the list of modified assignments (to update provider)
  BatchOperationResult batchReplace(
    List<SymbolAudioAssignment> assignments, {
    required String pattern,
    required String replacement,
    bool caseSensitive = false,
    bool useRegex = false,
    bool recordUndo = true,
  }) {
    final originalAssignments = <SymbolAudioAssignment>[];
    final modifiedAssignments = <SymbolAudioAssignment>[];

    for (final assignment in assignments) {
      String newPath;

      if (useRegex) {
        try {
          final regex = RegExp(pattern);
          newPath = assignment.audioPath.replaceAll(regex, replacement);
        } catch (e) {
          return BatchOperationResult(
            modifiedCount: 0,
            totalChecked: assignments.length,
            modifiedAssignments: [],
            originalAssignments: [],
            error: 'Invalid regex pattern: $e',
          );
        }
      } else if (caseSensitive) {
        newPath = assignment.audioPath.replaceAll(pattern, replacement);
      } else {
        newPath = _replaceIgnoreCase(assignment.audioPath, pattern, replacement);
      }

      if (newPath != assignment.audioPath) {
        originalAssignments.add(assignment);
        modifiedAssignments.add(assignment.copyWith(audioPath: newPath));
      }
    }

    final result = BatchOperationResult(
      modifiedCount: modifiedAssignments.length,
      totalChecked: assignments.length,
      modifiedAssignments: modifiedAssignments,
      originalAssignments: originalAssignments,
    );

    if (recordUndo && result.hasChanges) {
      _pushUndo(result);
    }

    debugPrint(
        '[SymbolAudioBatch] Replaced $pattern with $replacement: ${result.modifiedCount}/${result.totalChecked}');
    return result;
  }

  /// Set all assignments in a list to use a single audio file
  BatchOperationResult setAllToAudio(
    List<SymbolAudioAssignment> assignments,
    String newAudioPath, {
    bool recordUndo = true,
  }) {
    final originalAssignments = <SymbolAudioAssignment>[];
    final modifiedAssignments = <SymbolAudioAssignment>[];

    for (final assignment in assignments) {
      if (assignment.audioPath != newAudioPath) {
        originalAssignments.add(assignment);
        modifiedAssignments.add(assignment.copyWith(audioPath: newAudioPath));
      }
    }

    final result = BatchOperationResult(
      modifiedCount: modifiedAssignments.length,
      totalChecked: assignments.length,
      modifiedAssignments: modifiedAssignments,
      originalAssignments: originalAssignments,
    );

    if (recordUndo && result.hasChanges) {
      _pushUndo(result);
    }

    debugPrint(
        '[SymbolAudioBatch] Set all to $newAudioPath: ${result.modifiedCount}/${result.totalChecked}');
    return result;
  }

  /// Clear audio from all assignments in a list
  BatchOperationResult clearAll(
    List<SymbolAudioAssignment> assignments, {
    bool recordUndo = true,
  }) {
    return setAllToAudio(assignments, '', recordUndo: recordUndo);
  }

  /// Apply volume change to all assignments
  BatchOperationResult batchSetVolume(
    List<SymbolAudioAssignment> assignments,
    double volume, {
    bool recordUndo = true,
  }) {
    final clampedVolume = volume.clamp(0.0, 2.0);
    final originalAssignments = <SymbolAudioAssignment>[];
    final modifiedAssignments = <SymbolAudioAssignment>[];

    for (final assignment in assignments) {
      if (assignment.volume != clampedVolume) {
        originalAssignments.add(assignment);
        modifiedAssignments.add(assignment.copyWith(volume: clampedVolume));
      }
    }

    final result = BatchOperationResult(
      modifiedCount: modifiedAssignments.length,
      totalChecked: assignments.length,
      modifiedAssignments: modifiedAssignments,
      originalAssignments: originalAssignments,
    );

    if (recordUndo && result.hasChanges) {
      _pushUndo(result);
    }

    debugPrint(
        '[SymbolAudioBatch] Set volume to $clampedVolume: ${result.modifiedCount}/${result.totalChecked}');
    return result;
  }

  /// Apply pan change to all assignments
  BatchOperationResult batchSetPan(
    List<SymbolAudioAssignment> assignments,
    double pan, {
    bool recordUndo = true,
  }) {
    final clampedPan = pan.clamp(-1.0, 1.0);
    final originalAssignments = <SymbolAudioAssignment>[];
    final modifiedAssignments = <SymbolAudioAssignment>[];

    for (final assignment in assignments) {
      if (assignment.pan != clampedPan) {
        originalAssignments.add(assignment);
        modifiedAssignments.add(assignment.copyWith(pan: clampedPan));
      }
    }

    final result = BatchOperationResult(
      modifiedCount: modifiedAssignments.length,
      totalChecked: assignments.length,
      modifiedAssignments: modifiedAssignments,
      originalAssignments: originalAssignments,
    );

    if (recordUndo && result.hasChanges) {
      _pushUndo(result);
    }

    debugPrint(
        '[SymbolAudioBatch] Set pan to $clampedPan: ${result.modifiedCount}/${result.totalChecked}');
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UNDO/REDO
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get assignments to restore for undo
  /// Returns null if no undo available
  List<SymbolAudioAssignment>? undo() {
    if (_undoStack.isEmpty) return null;

    final operation = _undoStack.removeLast();
    _redoStack.add(operation);
    notifyListeners();

    debugPrint('[SymbolAudioBatch] Undo: ${operation.modifiedCount} assignments');
    return operation.originalAssignments;
  }

  /// Get assignments to restore for redo
  /// Returns null if no redo available
  List<SymbolAudioAssignment>? redo() {
    if (_redoStack.isEmpty) return null;

    final operation = _redoStack.removeLast();
    _undoStack.add(operation);
    notifyListeners();

    debugPrint('[SymbolAudioBatch] Redo: ${operation.modifiedCount} assignments');
    return operation.modifiedAssignments;
  }

  /// Clear all undo/redo history
  void clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  void _pushUndo(BatchOperationResult result) {
    _undoStack.add(result);
    _redoStack.clear(); // Clear redo on new action

    // Trim if exceeds max size
    while (_undoStack.length > _maxUndoHistory) {
      _undoStack.removeAt(0);
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Case-insensitive string replace
  String _replaceIgnoreCase(String source, String pattern, String replacement) {
    if (pattern.isEmpty) return source;

    final lowerSource = source.toLowerCase();
    final lowerPattern = pattern.toLowerCase();

    final result = StringBuffer();
    int lastIndex = 0;

    int index = lowerSource.indexOf(lowerPattern);
    while (index >= 0) {
      result.write(source.substring(lastIndex, index));
      result.write(replacement);
      lastIndex = index + pattern.length;
      index = lowerSource.indexOf(lowerPattern, lastIndex);
    }
    result.write(source.substring(lastIndex));

    return result.toString();
  }

  /// Get statistics about symbol audio assignments
  Map<String, dynamic> getStatistics(List<SymbolAudioAssignment> assignments) {
    final contexts = <String, int>{};
    final symbols = <String, int>{};
    final uniquePaths = <String>{};
    int emptyCount = 0;

    for (final a in assignments) {
      contexts[a.context] = (contexts[a.context] ?? 0) + 1;
      symbols[a.symbolId] = (symbols[a.symbolId] ?? 0) + 1;
      if (a.audioPath.isNotEmpty) {
        uniquePaths.add(a.audioPath);
      } else {
        emptyCount++;
      }
    }

    return {
      'totalAssignments': assignments.length,
      'uniqueAudioFiles': uniquePaths.length,
      'emptyAssignments': emptyCount,
      'assignmentsByContext': contexts,
      'assignmentsBySymbol': symbols,
    };
  }
}
