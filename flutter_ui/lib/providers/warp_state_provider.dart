/// Warp State Provider — Reactive Warp Marker Management
///
/// Centralizes all warp marker state for the selected clip:
/// - Quantize strength (user-adjustable, 0.0–1.0)
/// - Source BPM (auto-detected or user override)
/// - Live WarpStateSnapshot from Rust engine
/// - Reactive refresh on marker CRUD operations

import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// Quantize strength mode preset
enum WarpQuantizePreset {
  /// 25% — subtle, preserves groove feel
  subtle(0.25, 'SUBTLE'),
  /// 50% — balanced groove + grid
  medium(0.50, 'MEDIUM'),
  /// 75% — mostly quantized, slight swing
  tight(0.75, 'TIGHT'),
  /// 100% — full grid snap (no swing)
  full(1.00, 'FULL');

  final double value;
  final String label;
  const WarpQuantizePreset(this.value, this.label);
}

class WarpStateProvider extends ChangeNotifier {
  // ───────────────────────────────────────────────────────────────────────────
  // STATE
  // ───────────────────────────────────────────────────────────────────────────

  /// Current clip ID being tracked (null = no selection)
  int? _currentClipId;

  /// Live snapshot from Rust engine (null = not loaded / no markers)
  WarpStateSnapshot? _snapshot;

  /// User-controlled quantize strength (0.0 = none, 1.0 = full)
  /// Default 0.75 — tight but preserves minimal swing
  double _quantizeStrength = 0.75;

  /// User BPM override (null = use detected sourceTempo or project tempo)
  double? _userSourceBpm;

  /// True while transient detection is running (shows spinner)
  bool _detectingTransients = false;

  // ───────────────────────────────────────────────────────────────────────────
  // PUBLIC GETTERS
  // ───────────────────────────────────────────────────────────────────────────

  int? get currentClipId => _currentClipId;
  WarpStateSnapshot? get snapshot => _snapshot;
  double get quantizeStrength => _quantizeStrength;
  bool get detectingTransients => _detectingTransients;

  /// Effective source BPM: user override → detected → null
  double? get effectiveSourceBpm => _userSourceBpm ?? _snapshot?.sourceTempo;

  /// Whether warp is enabled for current clip
  bool get warpEnabled => _snapshot?.enabled ?? false;

  /// Marker count
  int get markerCount => _snapshot?.markers.length ?? 0;

  /// Transient count
  int get transientCount => _snapshot?.transients.length ?? 0;

  /// True if user has overridden source BPM
  bool get hasBpmOverride => _userSourceBpm != null;

  // ───────────────────────────────────────────────────────────────────────────
  // SELECTION
  // ───────────────────────────────────────────────────────────────────────────

  /// Called when user selects a different clip
  void selectClip(int clipId) {
    if (_currentClipId == clipId) return;
    _currentClipId = clipId;
    _userSourceBpm = null; // reset override on new clip
    _refreshFromEngine();
  }

  /// Called when clip selection is cleared
  void clearSelection() {
    _currentClipId = null;
    _snapshot = null;
    notifyListeners();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // QUANTIZE STRENGTH
  // ───────────────────────────────────────────────────────────────────────────

  /// Set quantize strength (0.0–1.0)
  void setQuantizeStrength(double v) {
    final clamped = v.clamp(0.0, 1.0);
    if ((clamped - _quantizeStrength).abs() < 0.001) return;
    _quantizeStrength = clamped;
    notifyListeners();
  }

  /// Apply a preset
  void applyPreset(WarpQuantizePreset preset) {
    setQuantizeStrength(preset.value);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // SOURCE BPM
  // ───────────────────────────────────────────────────────────────────────────

  /// Set user BPM override (null clears override → falls back to detected)
  void setUserSourceBpm(double? bpm) {
    _userSourceBpm = bpm;
    notifyListeners();
  }

  /// Clear BPM override — use detected/project tempo
  void clearBpmOverride() {
    _userSourceBpm = null;
    notifyListeners();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // WARP ENABLE/DISABLE
  // ───────────────────────────────────────────────────────────────────────────

  /// Toggle warp on current clip
  void toggleWarp() {
    final id = _currentClipId;
    if (id == null) return;
    NativeFFI.instance.clipWarpEnable(id, !warpEnabled);
    _refreshFromEngine();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TRANSIENT DETECTION
  // ───────────────────────────────────────────────────────────────────────────

  /// Run transient detection on current clip
  /// Returns number of transients found, or -1 on error
  Future<int> detectTransients({double sensitivity = 1.5}) async {
    final id = _currentClipId;
    if (id == null) return -1;

    _detectingTransients = true;
    notifyListeners();

    // Run on isolate to avoid blocking UI
    final count = await Future.microtask(
      () => NativeFFI.instance.clipDetectTransients(id, sensitivity: sensitivity),
    );

    _detectingTransients = false;
    _refreshFromEngine();
    return count;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // REFRESH
  // ───────────────────────────────────────────────────────────────────────────

  /// Refresh warp state from engine (call after any marker operation)
  void refresh() => _refreshFromEngine();

  /// Force refresh for a specific clip (used by engine_connected_layout)
  void refreshForClip(int clipId) {
    if (_currentClipId != clipId) {
      _currentClipId = clipId;
    }
    _refreshFromEngine();
  }

  void _refreshFromEngine() {
    final id = _currentClipId;
    if (id == null) {
      _snapshot = null;
      notifyListeners();
      return;
    }
    _snapshot = NativeFFI.instance.clipGetWarpState(id);
    notifyListeners();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // QUANTIZE STRENGTH LABEL
  // ───────────────────────────────────────────────────────────────────────────

  /// Human-readable strength label for UI display
  String get strengthLabel {
    final pct = (_quantizeStrength * 100).round();
    return '$pct%';
  }

  /// Nearest preset name for current strength
  String get presetLabel {
    WarpQuantizePreset best = WarpQuantizePreset.tight;
    double bestDist = double.infinity;
    for (final p in WarpQuantizePreset.values) {
      final d = (p.value - _quantizeStrength).abs();
      if (d < bestDist) {
        bestDist = d;
        best = p;
      }
    }
    return best.label;
  }
}
