/// Chain History Service — Undo / Redo + A/B Snapshot
///
/// Thin Flutter wrapper around the Rust `chain_history_ffi` layer.
/// Polls status once per operation (no timer) via `chainHistoryStatus`.
///
/// Usage:
///   final svc = ChainHistoryService.instance;
///   await svc.undo(trackId);
///   svc.saveA(trackId);
///   svc.restoreA(trackId);
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart' show NativeFFI;

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════

class ChainHistoryStatus {
  final int trackId;
  final int undoDepth;
  final int redoDepth;
  final String? undoLabel;
  final String? redoLabel;
  final bool aSet;
  final bool bSet;
  final String? aLabel;
  final String? bLabel;

  const ChainHistoryStatus({
    required this.trackId,
    required this.undoDepth,
    required this.redoDepth,
    this.undoLabel,
    this.redoLabel,
    required this.aSet,
    required this.bSet,
    this.aLabel,
    this.bLabel,
  });

  factory ChainHistoryStatus.empty(int trackId) => ChainHistoryStatus(
        trackId: trackId,
        undoDepth: 0,
        redoDepth: 0,
        aSet: false,
        bSet: false,
      );

  factory ChainHistoryStatus.fromJson(Map<String, dynamic> j) =>
      ChainHistoryStatus(
        trackId: (j['track_id'] as num).toInt(),
        undoDepth: (j['undo_depth'] as num?)?.toInt() ?? 0,
        redoDepth: (j['redo_depth'] as num?)?.toInt() ?? 0,
        undoLabel: j['undo_label'] as String?,
        redoLabel: j['redo_label'] as String?,
        aSet: j['a_set'] as bool? ?? false,
        bSet: j['b_set'] as bool? ?? false,
        aLabel: j['a_label'] as String?,
        bLabel: j['b_label'] as String?,
      );

  bool get canUndo => undoDepth > 0;
  bool get canRedo => redoDepth > 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════

class ChainHistoryService extends ChangeNotifier {
  ChainHistoryService._();
  static final ChainHistoryService instance = ChainHistoryService._();

  // Per-track cached status (refreshed after every mutating operation)
  final Map<int, ChainHistoryStatus> _statusCache = {};

  // ─── Status ────────────────────────────────────────────────────────────

  ChainHistoryStatus statusFor(int trackId) =>
      _statusCache[trackId] ?? ChainHistoryStatus.empty(trackId);

  void _refresh(int trackId) {
    final raw = NativeFFI.instance.chainHistoryStatus(trackId);
    if (raw == null) {
      _statusCache.remove(trackId);
    } else {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        _statusCache[trackId] = ChainHistoryStatus.fromJson(j);
      } catch (_) {
        _statusCache.remove(trackId);
      }
    }
    notifyListeners();
  }

  // ─── Undo / Redo ───────────────────────────────────────────────────────

  /// Undo the most recent chain apply for [trackId].
  /// Returns the parsed result JSON map, or null on failure.
  Map<String, dynamic>? undo(int trackId) {
    final raw = NativeFFI.instance.chainUndoJson(trackId);
    _refresh(trackId);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Redo the most recently undone apply for [trackId].
  Map<String, dynamic>? redo(int trackId) {
    final raw = NativeFFI.instance.chainRedoJson(trackId);
    _refresh(trackId);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void clearHistory(int trackId) {
    NativeFFI.instance.chainHistoryClear(trackId);
    _refresh(trackId);
  }

  void clearAll() {
    NativeFFI.instance.chainHistoryClearAll();
    _statusCache.clear();
    notifyListeners();
  }

  // ─── A/B ───────────────────────────────────────────────────────────────

  /// Capture current engine chain → A slot.
  void saveA(int trackId) {
    NativeFFI.instance.chainAbSaveA(trackId);
    _refresh(trackId);
  }

  /// Capture current engine chain → B slot.
  void saveB(int trackId) {
    NativeFFI.instance.chainAbSaveB(trackId);
    _refresh(trackId);
  }

  /// Restore A slot → engine (pushes current to undo).
  Map<String, dynamic>? restoreA(int trackId) {
    final raw = NativeFFI.instance.chainAbRestoreA(trackId);
    _refresh(trackId);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Restore B slot → engine.
  Map<String, dynamic>? restoreB(int trackId) {
    final raw = NativeFFI.instance.chainAbRestoreB(trackId);
    _refresh(trackId);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Swap A↔B slot labels in memory (no engine change).
  void swapAB(int trackId) {
    NativeFFI.instance.chainAbSwap(trackId);
    _refresh(trackId);
  }

  // ─── Force refresh ─────────────────────────────────────────────────────

  /// Refresh cached status from Rust (call after external chain modifications).
  void refresh(int trackId) => _refresh(trackId);
}
