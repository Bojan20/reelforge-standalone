/// Variant Manager Service
///
/// Manages multiple audio file variants per stage.
/// Supports Random, Sequence, and Manual selection modes.
///
/// Use cases:
/// - Multiple takes for same stage (spin_01.wav, spin_02.wav, spin_03.wav)
/// - Random variation for replay value
/// - Sequence cycling for progression
///
/// Task: SL-LP-P1.4
library;

import 'dart:math';
import 'package:flutter/foundation.dart';

enum VariantSelectionMode { random, sequence, manual }

class AudioVariant {
  final String path;
  final String name;
  final double weight; // For weighted random (1.0 = normal)

  const AudioVariant({
    required this.path,
    required this.name,
    this.weight = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'weight': weight,
  };

  factory AudioVariant.fromJson(Map<String, dynamic> json) => AudioVariant(
    path: json['path'] as String,
    name: json['name'] as String,
    weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
  );
}

class StageVariants {
  final String stage;
  final List<AudioVariant> variants;
  final VariantSelectionMode mode;
  int _sequenceIndex = 0;

  StageVariants({
    required this.stage,
    required this.variants,
    this.mode = VariantSelectionMode.random,
  });

  /// Get next variant based on mode
  AudioVariant? getNext(Random? random) {
    if (variants.isEmpty) return null;

    switch (mode) {
      case VariantSelectionMode.random:
        return _getRandomVariant(random ?? Random());
      case VariantSelectionMode.sequence:
        return _getSequenceVariant();
      case VariantSelectionMode.manual:
        return variants.first; // Return first, UI will override
    }
  }

  AudioVariant _getRandomVariant(Random random) {
    // Weighted random selection
    final totalWeight = variants.fold<double>(0, (sum, v) => sum + v.weight);
    var value = random.nextDouble() * totalWeight;

    for (final variant in variants) {
      value -= variant.weight;
      if (value <= 0) return variant;
    }

    return variants.last; // Fallback
  }

  AudioVariant _getSequenceVariant() {
    final variant = variants[_sequenceIndex];
    _sequenceIndex = (_sequenceIndex + 1) % variants.length;
    return variant;
  }

  Map<String, dynamic> toJson() => {
    'stage': stage,
    'variants': variants.map((v) => v.toJson()).toList(),
    'mode': mode.name,
    'sequenceIndex': _sequenceIndex,
  };

  factory StageVariants.fromJson(Map<String, dynamic> json) => StageVariants(
    stage: json['stage'] as String,
    variants: (json['variants'] as List)
        .map((e) => AudioVariant.fromJson(e as Map<String, dynamic>))
        .toList(),
    mode: VariantSelectionMode.values.firstWhere(
      (m) => m.name == json['mode'],
      orElse: () => VariantSelectionMode.random,
    ),
  ).._sequenceIndex = json['sequenceIndex'] as int? ?? 0;
}

/// Variant Manager — Singleton service
class VariantManager extends ChangeNotifier {
  static final VariantManager instance = VariantManager._();
  VariantManager._();

  final Map<String, StageVariants> _variants = {};
  final Random _random = Random();

  /// Get all stages with variants
  List<String> get stagesWithVariants => _variants.keys.toList();

  /// Check if stage has variants
  bool hasVariants(String stage) => _variants.containsKey(stage);

  /// Get variant count for stage
  int getVariantCount(String stage) => _variants[stage]?.variants.length ?? 0;

  /// Add variant to stage
  void addVariant(String stage, AudioVariant variant) {
    if (!_variants.containsKey(stage)) {
      _variants[stage] = StageVariants(stage: stage, variants: []);
    }
    _variants[stage]!.variants.add(variant);
    notifyListeners();
  }

  /// Remove variant from stage
  void removeVariant(String stage, int index) {
    if (_variants.containsKey(stage)) {
      _variants[stage]!.variants.removeAt(index);
      if (_variants[stage]!.variants.isEmpty) {
        _variants.remove(stage);
      }
      notifyListeners();
    }
  }

  /// Set selection mode for stage
  void setMode(String stage, VariantSelectionMode mode) {
    if (_variants.containsKey(stage)) {
      _variants[stage] = StageVariants(
        stage: stage,
        variants: _variants[stage]!.variants,
        mode: mode,
      );
      notifyListeners();
    }
  }

  /// Get next audio path for stage (respects mode)
  String? getNext(String stage) {
    return _variants[stage]?.getNext(_random)?.path;
  }

  /// Get specific variant by index
  String? getVariant(String stage, int index) {
    final variants = _variants[stage]?.variants;
    if (variants == null || index >= variants.length) return null;
    return variants[index].path;
  }

  /// Get all variants for stage
  List<AudioVariant> getVariants(String stage) {
    return _variants[stage]?.variants ?? [];
  }

  /// Clear all variants for stage
  void clearStage(String stage) {
    _variants.remove(stage);
    notifyListeners();
  }

  /// Clear all variants
  void clearAll() {
    _variants.clear();
    notifyListeners();
  }

  /// Import from JSON
  void importFromJson(Map<String, dynamic> json) {
    _variants.clear();
    for (final entry in (json['stages'] as List)) {
      final stageVariants = StageVariants.fromJson(entry as Map<String, dynamic>);
      _variants[stageVariants.stage] = stageVariants;
    }
    notifyListeners();
  }

  /// Export to JSON
  Map<String, dynamic> toJson() => {
    'stages': _variants.values.map((v) => v.toJson()).toList(),
  };
}
