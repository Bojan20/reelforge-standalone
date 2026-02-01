// Stage Marker Model — SlotLab Timeline Visual Markers
//
// Represents a stage event marker on the timeline (e.g., REEL_STOP_0, WIN_PRESENT).
// Markers are visual indicators that sync with SlotLab stage events.

import 'package:flutter/material.dart';

/// Marker type categories
enum StageMarkerType {
  spin,        // SPIN_START, SPIN_END
  reelStop,    // REEL_STOP_0..4
  win,         // WIN_PRESENT_*, ROLLUP_*
  feature,     // FS_TRIGGER, BONUS_ENTER
  anticipation, // ANTICIPATION_ON/OFF
  custom,      // User-defined markers
}

/// Visual stage marker on timeline
class StageMarker {
  final String id;
  final String stageId;       // e.g., 'REEL_STOP_0'
  final double timeSeconds;   // Position on timeline
  final StageMarkerType type;
  final String label;         // Display name
  final Color color;
  final bool isMuted;         // If true, stage won't trigger audio

  const StageMarker({
    required this.id,
    required this.stageId,
    required this.timeSeconds,
    required this.type,
    required this.label,
    required this.color,
    this.isMuted = false,
  });

  /// Create marker from stage ID (auto-detect type and color)
  factory StageMarker.fromStageId(String stageId, double timeSeconds) {
    final type = _detectMarkerType(stageId);
    final color = _colorForType(type);
    final label = _labelFromStageId(stageId);

    return StageMarker(
      id: '${stageId}_$timeSeconds',
      stageId: stageId,
      timeSeconds: timeSeconds,
      type: type,
      label: label,
      color: color,
    );
  }

  /// Detect marker type from stage ID
  static StageMarkerType _detectMarkerType(String stageId) {
    final upper = stageId.toUpperCase();
    if (upper.startsWith('SPIN_')) return StageMarkerType.spin;
    if (upper.startsWith('REEL_STOP')) return StageMarkerType.reelStop;
    if (upper.contains('WIN') || upper.contains('ROLLUP')) return StageMarkerType.win;
    if (upper.contains('FS_') || upper.contains('BONUS_') || upper.contains('FEATURE_')) {
      return StageMarkerType.feature;
    }
    if (upper.contains('ANTICIPATION')) return StageMarkerType.anticipation;
    return StageMarkerType.custom;
  }

  /// Color for marker type
  static Color _colorForType(StageMarkerType type) {
    switch (type) {
      case StageMarkerType.spin:
        return const Color(0xFF40FF90); // Green
      case StageMarkerType.reelStop:
        return const Color(0xFF4A9EFF); // Blue
      case StageMarkerType.win:
        return const Color(0xFFFFD700); // Gold
      case StageMarkerType.feature:
        return const Color(0xFF9370DB); // Purple
      case StageMarkerType.anticipation:
        return const Color(0xFFFF9040); // Orange
      case StageMarkerType.custom:
        return const Color(0xFF808080); // Gray
    }
  }

  /// Human-readable label from stage ID
  static String _labelFromStageId(String stageId) {
    // REEL_STOP_0 → "Reel 1"
    // WIN_PRESENT_BIG → "Big Win"
    // SPIN_START → "Spin"
    final upper = stageId.toUpperCase();

    if (upper.startsWith('REEL_STOP_')) {
      final reelIndex = int.tryParse(upper.split('_').last);
      if (reelIndex != null) return 'Reel ${reelIndex + 1}';
    }

    if (upper.startsWith('WIN_PRESENT_')) {
      final tier = upper.replaceFirst('WIN_PRESENT_', '');
      return '${tier.capitalize()} Win';
    }

    if (upper == 'SPIN_START') return 'Spin';
    if (upper == 'SPIN_END') return 'Spin End';
    if (upper == 'ANTICIPATION_ON') return 'Anticipation';

    // Default: Capitalize and remove underscores
    return stageId.replaceAll('_', ' ').capitalize();
  }

  /// Copy with modifications
  StageMarker copyWith({
    String? id,
    String? stageId,
    double? timeSeconds,
    StageMarkerType? type,
    String? label,
    Color? color,
    bool? isMuted,
  }) {
    return StageMarker(
      id: id ?? this.id,
      stageId: stageId ?? this.stageId,
      timeSeconds: timeSeconds ?? this.timeSeconds,
      type: type ?? this.type,
      label: label ?? this.label,
      color: color ?? this.color,
      isMuted: isMuted ?? this.isMuted,
    );
  }

  /// JSON serialization
  Map<String, dynamic> toJson() => {
    'id': id,
    'stageId': stageId,
    'timeSeconds': timeSeconds,
    'type': type.name,
    'label': label,
    'color': color.value,
    'isMuted': isMuted,
  };

  factory StageMarker.fromJson(Map<String, dynamic> json) {
    return StageMarker(
      id: json['id'] as String,
      stageId: json['stageId'] as String,
      timeSeconds: (json['timeSeconds'] as num).toDouble(),
      type: StageMarkerType.values.firstWhere((t) => t.name == json['type']),
      label: json['label'] as String,
      color: Color(json['color'] as int),
      isMuted: json['isMuted'] as bool? ?? false,
    );
  }
}

/// String extension for capitalization
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }
}
