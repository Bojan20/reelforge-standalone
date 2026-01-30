/// Audio Variant Group Model
///
/// Groups related audio files for A/B comparison and variant management.
/// Use case: Multiple takes of the same sound, different mix versions, etc.
///
/// Features:
/// - Group audio files by semantic relationship
/// - A/B comparison between variants
/// - Global replace variant in all events
/// - Visual diff indicators
///
/// Task: P1-01 Audio Variant Group + A/B UI

import 'package:flutter/material.dart';

/// Represents a single audio variant within a group
class AudioVariant {
  final String id;
  final String audioPath;
  final String label;
  final String? description;
  final DateTime addedAt;
  final Map<String, dynamic>? metadata; // LUFS, duration, etc.

  AudioVariant({
    required this.id,
    required this.audioPath,
    required this.label,
    this.description,
    DateTime? addedAt,
    this.metadata,
  }) : addedAt = addedAt ?? DateTime.now();

  // Helper to get metadata values
  double? get lufs => metadata?['lufs'] as double?;
  double? get truePeak => metadata?['truePeak'] as double?;
  double? get duration => metadata?['duration'] as double?;
  int? get sampleRate => metadata?['sampleRate'] as int?;

  AudioVariant copyWith({
    String? id,
    String? audioPath,
    String? label,
    String? description,
    DateTime? addedAt,
    Map<String, dynamic>? metadata,
  }) {
    return AudioVariant(
      id: id ?? this.id,
      audioPath: audioPath ?? this.audioPath,
      label: label ?? this.label,
      description: description ?? this.description,
      addedAt: addedAt ?? this.addedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'audioPath': audioPath,
      'label': label,
      if (description != null) 'description': description,
      'addedAt': addedAt.toIso8601String(),
      if (metadata != null) 'metadata': metadata,
    };
  }

  factory AudioVariant.fromJson(Map<String, dynamic> json) {
    return AudioVariant(
      id: json['id'] as String,
      audioPath: json['audioPath'] as String,
      label: json['label'] as String,
      description: json['description'] as String?,
      addedAt: DateTime.parse(json['addedAt'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioVariant &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          audioPath == other.audioPath;

  @override
  int get hashCode => Object.hash(id, audioPath);
}

/// Groups related audio variants for A/B comparison
class AudioVariantGroup {
  final String id;
  final String name;
  final String? description;
  final List<AudioVariant> variants;
  final String? activeVariantId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Color? color; // Optional color coding

  AudioVariantGroup({
    required this.id,
    required this.name,
    this.description,
    required this.variants,
    this.activeVariantId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.color,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Get the currently active variant (or first if none selected)
  AudioVariant? get activeVariant {
    if (activeVariantId != null) {
      return variants.where((v) => v.id == activeVariantId).firstOrNull;
    }
    return variants.firstOrNull;
  }

  /// Get variant by ID
  AudioVariant? getVariant(String variantId) {
    return variants.where((v) => v.id == variantId).firstOrNull;
  }

  /// Check if group contains a specific audio path
  bool containsAudioPath(String audioPath) {
    return variants.any((v) => v.audioPath == audioPath);
  }

  /// Get variant index
  int? getVariantIndex(String variantId) {
    final index = variants.indexWhere((v) => v.id == variantId);
    return index >= 0 ? index : null;
  }

  AudioVariantGroup copyWith({
    String? id,
    String? name,
    String? description,
    List<AudioVariant>? variants,
    String? activeVariantId,
    DateTime? createdAt,
    DateTime? updatedAt,
    Color? color,
  }) {
    return AudioVariantGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      variants: variants ?? this.variants,
      activeVariantId: activeVariantId ?? this.activeVariantId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      color: color ?? this.color,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      'variants': variants.map((v) => v.toJson()).toList(),
      if (activeVariantId != null) 'activeVariantId': activeVariantId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (color != null) 'color': color!.value,
    };
  }

  factory AudioVariantGroup.fromJson(Map<String, dynamic> json) {
    return AudioVariantGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      variants: (json['variants'] as List)
          .map((v) => AudioVariant.fromJson(v as Map<String, dynamic>))
          .toList(),
      activeVariantId: json['activeVariantId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      color: json['color'] != null ? Color(json['color'] as int) : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioVariantGroup &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Statistics for variant comparison
class VariantComparisonStats {
  final AudioVariant variantA;
  final AudioVariant variantB;
  final double? lufsDelta;
  final double? truePeakDelta;
  final double? durationDelta;

  const VariantComparisonStats({
    required this.variantA,
    required this.variantB,
    this.lufsDelta,
    this.truePeakDelta,
    this.durationDelta,
  });

  /// Calculate stats from two variants
  factory VariantComparisonStats.calculate(
    AudioVariant variantA,
    AudioVariant variantB,
  ) {
    double? lufsDelta;
    if (variantA.lufs != null && variantB.lufs != null) {
      lufsDelta = variantB.lufs! - variantA.lufs!;
    }

    double? truePeakDelta;
    if (variantA.truePeak != null && variantB.truePeak != null) {
      truePeakDelta = variantB.truePeak! - variantA.truePeak!;
    }

    double? durationDelta;
    if (variantA.duration != null && variantB.duration != null) {
      durationDelta = variantB.duration! - variantA.duration!;
    }

    return VariantComparisonStats(
      variantA: variantA,
      variantB: variantB,
      lufsDelta: lufsDelta,
      truePeakDelta: truePeakDelta,
      durationDelta: durationDelta,
    );
  }

  /// Format LUFS delta with sign and color indication
  String get lufsFormatted {
    if (lufsDelta == null) return '—';
    final sign = lufsDelta! >= 0 ? '+' : '';
    return '$sign${lufsDelta!.toStringAsFixed(1)} dB';
  }

  /// Format true peak delta
  String get truePeakFormatted {
    if (truePeakDelta == null) return '—';
    final sign = truePeakDelta! >= 0 ? '+' : '';
    return '$sign${truePeakDelta!.toStringAsFixed(1)} dBTP';
  }

  /// Format duration delta
  String get durationFormatted {
    if (durationDelta == null) return '—';
    final sign = durationDelta! >= 0 ? '+' : '';
    return '$sign${durationDelta!.toStringAsFixed(2)} s';
  }
}
