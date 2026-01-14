// Clip Gain Envelope Provider
//
// Per-clip gain automation (pre-fader):
// - Volume envelope drawn directly on clip
// - Non-destructive gain changes
// - Different from track automation (which is post-fader)
// - Cubase "Volume Curve" / Pro Tools "Clip Gain Line"
//
// Use cases:
// - Ride vocal levels within a take
// - Fix inconsistent dynamics before compression
// - Create smooth fades that move with the clip

import 'package:flutter/foundation.dart';
import 'dart:math' as math;

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Curve type for gain envelope segments
enum GainEnvelopeCurve {
  linear,       // Straight line
  exponential,  // Fast attack/slow decay feel
  logarithmic,  // Slow attack/fast decay feel
  sCurve,       // Smooth S-curve
}

/// A single point in the gain envelope
class GainEnvelopePoint {
  final String id;
  final double position;    // 0-1 relative position within clip
  final double gain;        // Gain value in dB (-inf to +12)
  final GainEnvelopeCurve curveToNext;
  final bool selected;

  const GainEnvelopePoint({
    required this.id,
    required this.position,
    required this.gain,
    this.curveToNext = GainEnvelopeCurve.linear,
    this.selected = false,
  });

  GainEnvelopePoint copyWith({
    String? id,
    double? position,
    double? gain,
    GainEnvelopeCurve? curveToNext,
    bool? selected,
  }) {
    return GainEnvelopePoint(
      id: id ?? this.id,
      position: position ?? this.position,
      gain: gain ?? this.gain,
      curveToNext: curveToNext ?? this.curveToNext,
      selected: selected ?? this.selected,
    );
  }

  /// Convert gain dB to linear multiplier
  double get linearGain {
    if (gain <= -60) return 0.0;
    return math.pow(10, gain / 20).toDouble();
  }

  /// Format gain for display
  String get displayGain {
    if (gain <= -60) return '-∞ dB';
    return '${gain.toStringAsFixed(1)} dB';
  }
}

/// Gain envelope for a single clip
class ClipGainEnvelope {
  final String clipId;
  final List<GainEnvelopePoint> points;
  final bool enabled;
  final bool visible;

  const ClipGainEnvelope({
    required this.clipId,
    this.points = const [],
    this.enabled = true,
    this.visible = true,
  });

  ClipGainEnvelope copyWith({
    String? clipId,
    List<GainEnvelopePoint>? points,
    bool? enabled,
    bool? visible,
  }) {
    return ClipGainEnvelope(
      clipId: clipId ?? this.clipId,
      points: points ?? this.points,
      enabled: enabled ?? this.enabled,
      visible: visible ?? this.visible,
    );
  }

  /// Check if envelope has any points
  bool get hasPoints => points.isNotEmpty;

  /// Get point count
  int get pointCount => points.length;

  /// Get selected points
  List<GainEnvelopePoint> get selectedPoints =>
      points.where((p) => p.selected).toList();

  /// Calculate gain at position (0-1)
  double getGainAtPosition(double position) {
    if (!enabled || points.isEmpty) return 0.0; // 0 dB

    // Clamp position
    position = position.clamp(0.0, 1.0);

    // Find surrounding points
    GainEnvelopePoint? before;
    GainEnvelopePoint? after;

    for (final point in points) {
      if (point.position <= position) {
        before = point;
      }
      if (point.position >= position && after == null) {
        after = point;
      }
    }

    // Handle edge cases
    if (before == null && after == null) return 0.0;
    if (before == null) return after!.gain;
    if (after == null) return before.gain;
    if (before.position == after.position) return before.gain;

    // Interpolate
    final t = (position - before.position) / (after.position - before.position);
    return _interpolateGain(before, after, t);
  }

  /// Calculate linear gain at position
  double getLinearGainAtPosition(double position) {
    final db = getGainAtPosition(position);
    if (db <= -60) return 0.0;
    return math.pow(10, db / 20).toDouble();
  }

  double _interpolateGain(GainEnvelopePoint from, GainEnvelopePoint to, double t) {
    switch (from.curveToNext) {
      case GainEnvelopeCurve.linear:
        return from.gain + t * (to.gain - from.gain);

      case GainEnvelopeCurve.exponential:
        final curved = t * t;
        return from.gain + curved * (to.gain - from.gain);

      case GainEnvelopeCurve.logarithmic:
        final curved = math.sqrt(t);
        return from.gain + curved * (to.gain - from.gain);

      case GainEnvelopeCurve.sCurve:
        final curved = t * t * (3 - 2 * t);
        return from.gain + curved * (to.gain - from.gain);
    }
  }

  /// Get envelope as list of samples for waveform display
  List<double> toSamples(int sampleCount) {
    final samples = <double>[];
    for (int i = 0; i < sampleCount; i++) {
      final position = i / (sampleCount - 1);
      samples.add(getLinearGainAtPosition(position));
    }
    return samples;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

class ClipGainEnvelopeProvider extends ChangeNotifier {
  // Envelopes by clip ID
  final Map<String, ClipGainEnvelope> _envelopes = {};

  // Global state
  bool _enabled = true;
  bool _showEnvelopes = true;

  // Editing state
  String? _editingClipId;
  final Set<String> _selectedPointIds = {};

  // Default gain range
  static const double minGain = -60.0;  // dB
  static const double maxGain = 12.0;   // dB

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get enabled => _enabled;
  bool get showEnvelopes => _showEnvelopes;
  String? get editingClipId => _editingClipId;
  Set<String> get selectedPointIds => Set.unmodifiable(_selectedPointIds);

  /// Get envelope for clip
  ClipGainEnvelope? getEnvelope(String clipId) => _envelopes[clipId];

  /// Check if clip has envelope
  bool hasEnvelope(String clipId) => _envelopes.containsKey(clipId);

  /// Get gain at position for clip
  double getGainAtPosition(String clipId, double position) {
    if (!_enabled) return 0.0;
    return _envelopes[clipId]?.getGainAtPosition(position) ?? 0.0;
  }

  /// Get linear gain at position for clip
  double getLinearGainAtPosition(String clipId, double position) {
    if (!_enabled) return 1.0;
    return _envelopes[clipId]?.getLinearGainAtPosition(position) ?? 1.0;
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

  void setShowEnvelopes(bool value) {
    _showEnvelopes = value;
    notifyListeners();
  }

  void toggleShowEnvelopes() {
    _showEnvelopes = !_showEnvelopes;
    notifyListeners();
  }

  void startEditing(String clipId) {
    _editingClipId = clipId;
    _selectedPointIds.clear();
    notifyListeners();
  }

  void stopEditing() {
    _editingClipId = null;
    _selectedPointIds.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ENVELOPE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create or get envelope for clip
  ClipGainEnvelope ensureEnvelope(String clipId) {
    if (!_envelopes.containsKey(clipId)) {
      _envelopes[clipId] = ClipGainEnvelope(clipId: clipId);
      notifyListeners();
    }
    return _envelopes[clipId]!;
  }

  /// Delete envelope for clip
  void deleteEnvelope(String clipId) {
    _envelopes.remove(clipId);
    if (_editingClipId == clipId) {
      _editingClipId = null;
    }
    notifyListeners();
  }

  /// Toggle envelope visibility for clip
  void toggleEnvelopeVisibility(String clipId) {
    final env = _envelopes[clipId];
    if (env != null) {
      _envelopes[clipId] = env.copyWith(visible: !env.visible);
      notifyListeners();
    }
  }

  /// Toggle envelope enabled for clip
  void toggleEnvelopeEnabled(String clipId) {
    final env = _envelopes[clipId];
    if (env != null) {
      _envelopes[clipId] = env.copyWith(enabled: !env.enabled);
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POINT MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add point to envelope
  GainEnvelopePoint addPoint(
    String clipId, {
    required double position,
    required double gain,
    GainEnvelopeCurve curve = GainEnvelopeCurve.linear,
  }) {
    ensureEnvelope(clipId);

    final id = 'pt_${DateTime.now().millisecondsSinceEpoch}';
    final point = GainEnvelopePoint(
      id: id,
      position: position.clamp(0.0, 1.0),
      gain: gain.clamp(minGain, maxGain),
      curveToNext: curve,
    );

    final env = _envelopes[clipId]!;
    final points = [...env.points, point];
    points.sort((a, b) => a.position.compareTo(b.position));

    _envelopes[clipId] = env.copyWith(points: points);
    notifyListeners();
    return point;
  }

  /// Add point by clicking on envelope (auto-calculate gain)
  GainEnvelopePoint addPointAtPosition(String clipId, double position) {
    final env = _envelopes[clipId];
    final currentGain = env?.getGainAtPosition(position) ?? 0.0;
    return addPoint(clipId, position: position, gain: currentGain);
  }

  /// Update point
  void updatePoint(String clipId, GainEnvelopePoint point) {
    final env = _envelopes[clipId];
    if (env == null) return;

    final points = env.points.map((p) {
      if (p.id == point.id) {
        return point.copyWith(
          position: point.position.clamp(0.0, 1.0),
          gain: point.gain.clamp(minGain, maxGain),
        );
      }
      return p;
    }).toList();

    points.sort((a, b) => a.position.compareTo(b.position));
    _envelopes[clipId] = env.copyWith(points: points);
    notifyListeners();
  }

  /// Move point
  void movePoint(String clipId, String pointId, double newPosition, double newGain) {
    final env = _envelopes[clipId];
    if (env == null) return;

    final point = env.points.cast<GainEnvelopePoint?>().firstWhere(
      (p) => p?.id == pointId,
      orElse: () => null,
    );
    if (point == null) return;

    updatePoint(clipId, point.copyWith(position: newPosition, gain: newGain));
  }

  /// Delete point
  void deletePoint(String clipId, String pointId) {
    final env = _envelopes[clipId];
    if (env == null) return;

    final points = env.points.where((p) => p.id != pointId).toList();
    _envelopes[clipId] = env.copyWith(points: points);
    _selectedPointIds.remove(pointId);
    notifyListeners();
  }

  /// Delete selected points
  void deleteSelectedPoints(String clipId) {
    final env = _envelopes[clipId];
    if (env == null) return;

    final points = env.points.where((p) => !_selectedPointIds.contains(p.id)).toList();
    _envelopes[clipId] = env.copyWith(points: points);
    _selectedPointIds.clear();
    notifyListeners();
  }

  /// Set point curve type
  void setPointCurve(String clipId, String pointId, GainEnvelopeCurve curve) {
    final env = _envelopes[clipId];
    if (env == null) return;

    final points = env.points.map((p) {
      if (p.id == pointId) {
        return p.copyWith(curveToNext: curve);
      }
      return p;
    }).toList();

    _envelopes[clipId] = env.copyWith(points: points);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SELECTION
  // ═══════════════════════════════════════════════════════════════════════════

  void selectPoint(String pointId) {
    _selectedPointIds.add(pointId);
    notifyListeners();
  }

  void deselectPoint(String pointId) {
    _selectedPointIds.remove(pointId);
    notifyListeners();
  }

  void togglePointSelection(String pointId) {
    if (_selectedPointIds.contains(pointId)) {
      _selectedPointIds.remove(pointId);
    } else {
      _selectedPointIds.add(pointId);
    }
    notifyListeners();
  }

  void selectAllPoints(String clipId) {
    final env = _envelopes[clipId];
    if (env == null) return;

    _selectedPointIds.clear();
    for (final p in env.points) {
      _selectedPointIds.add(p.id);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedPointIds.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BATCH OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Apply gain offset to all points
  void offsetGain(String clipId, double offsetDb) {
    final env = _envelopes[clipId];
    if (env == null) return;

    final points = env.points.map((p) {
      return p.copyWith(gain: (p.gain + offsetDb).clamp(minGain, maxGain));
    }).toList();

    _envelopes[clipId] = env.copyWith(points: points);
    notifyListeners();
  }

  /// Scale gain (multiply)
  void scaleGain(String clipId, double factor) {
    final env = _envelopes[clipId];
    if (env == null) return;

    final points = env.points.map((p) {
      // Convert to linear, scale, convert back to dB
      final linear = p.linearGain * factor;
      final db = linear <= 0 ? minGain : 20 * math.log(linear) / math.ln10;
      return p.copyWith(gain: db.clamp(minGain, maxGain));
    }).toList();

    _envelopes[clipId] = env.copyWith(points: points);
    notifyListeners();
  }

  /// Flatten envelope (set all points to average)
  void flattenEnvelope(String clipId) {
    final env = _envelopes[clipId];
    if (env == null || env.points.isEmpty) return;

    final avgGain = env.points.map((p) => p.gain).reduce((a, b) => a + b) / env.points.length;

    final points = env.points.map((p) {
      return p.copyWith(gain: avgGain);
    }).toList();

    _envelopes[clipId] = env.copyWith(points: points);
    notifyListeners();
  }

  /// Invert envelope (flip around 0 dB)
  void invertEnvelope(String clipId) {
    final env = _envelopes[clipId];
    if (env == null) return;

    final points = env.points.map((p) {
      return p.copyWith(gain: (-p.gain).clamp(minGain, maxGain));
    }).toList();

    _envelopes[clipId] = env.copyWith(points: points);
    notifyListeners();
  }

  /// Clear all points (reset to flat)
  void clearEnvelope(String clipId) {
    final env = _envelopes[clipId];
    if (env == null) return;

    _envelopes[clipId] = env.copyWith(points: []);
    _selectedPointIds.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create fade in
  void createFadeIn(String clipId, double duration, {double startGain = -60, double endGain = 0}) {
    ensureEnvelope(clipId);

    final points = [
      GainEnvelopePoint(
        id: 'pt_${DateTime.now().millisecondsSinceEpoch}_0',
        position: 0,
        gain: startGain,
        curveToNext: GainEnvelopeCurve.logarithmic,
      ),
      GainEnvelopePoint(
        id: 'pt_${DateTime.now().millisecondsSinceEpoch}_1',
        position: duration.clamp(0.0, 1.0),
        gain: endGain,
      ),
    ];

    _envelopes[clipId] = _envelopes[clipId]!.copyWith(points: points);
    notifyListeners();
  }

  /// Create fade out
  void createFadeOut(String clipId, double duration, {double startGain = 0, double endGain = -60}) {
    ensureEnvelope(clipId);

    final startPos = (1.0 - duration).clamp(0.0, 1.0);
    final points = [
      GainEnvelopePoint(
        id: 'pt_${DateTime.now().millisecondsSinceEpoch}_0',
        position: startPos,
        gain: startGain,
        curveToNext: GainEnvelopeCurve.exponential,
      ),
      GainEnvelopePoint(
        id: 'pt_${DateTime.now().millisecondsSinceEpoch}_1',
        position: 1.0,
        gain: endGain,
      ),
    ];

    _envelopes[clipId] = _envelopes[clipId]!.copyWith(points: points);
    notifyListeners();
  }

  /// Create crossfade (for overlapping clips)
  void createCrossfade(String clipId, double fadeLength, bool fadeIn) {
    if (fadeIn) {
      createFadeIn(clipId, fadeLength);
    } else {
      createFadeOut(clipId, fadeLength);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COPY / PASTE
  // ═══════════════════════════════════════════════════════════════════════════

  List<GainEnvelopePoint>? _clipboard;

  /// Copy envelope from clip
  void copyEnvelope(String clipId) {
    final env = _envelopes[clipId];
    if (env == null) return;
    _clipboard = List.from(env.points);
  }

  /// Paste envelope to clip
  void pasteEnvelope(String clipId) {
    if (_clipboard == null || _clipboard!.isEmpty) return;

    ensureEnvelope(clipId);

    // Generate new IDs for pasted points
    final points = _clipboard!.map((p) => p.copyWith(
      id: 'pt_${DateTime.now().millisecondsSinceEpoch}_${p.id}',
      selected: false,
    )).toList();

    _envelopes[clipId] = _envelopes[clipId]!.copyWith(points: points);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() {
    return {
      'enabled': _enabled,
      'showEnvelopes': _showEnvelopes,
      'envelopes': _envelopes.entries.map((e) => {
        'clipId': e.key,
        'enabled': e.value.enabled,
        'visible': e.value.visible,
        'points': e.value.points.map((p) => {
          'id': p.id,
          'position': p.position,
          'gain': p.gain,
          'curve': p.curveToNext.index,
        }).toList(),
      }).toList(),
    };
  }

  void loadFromJson(Map<String, dynamic> json) {
    _enabled = json['enabled'] ?? true;
    _showEnvelopes = json['showEnvelopes'] ?? true;

    _envelopes.clear();
    if (json['envelopes'] != null) {
      for (final e in json['envelopes']) {
        final clipId = e['clipId'] as String;
        final points = (e['points'] as List?)?.map((p) => GainEnvelopePoint(
          id: p['id'],
          position: (p['position'] ?? 0.0).toDouble(),
          gain: (p['gain'] ?? 0.0).toDouble(),
          curveToNext: GainEnvelopeCurve.values[p['curve'] ?? 0],
        )).toList() ?? [];

        _envelopes[clipId] = ClipGainEnvelope(
          clipId: clipId,
          enabled: e['enabled'] ?? true,
          visible: e['visible'] ?? true,
          points: points,
        );
      }
    }

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESET
  // ═══════════════════════════════════════════════════════════════════════════

  void reset() {
    _envelopes.clear();
    _enabled = true;
    _showEnvelopes = true;
    _editingClipId = null;
    _selectedPointIds.clear();
    _clipboard = null;
    notifyListeners();
  }
}
