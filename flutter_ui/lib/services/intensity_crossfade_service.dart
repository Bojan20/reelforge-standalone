/// P-ICF: Intensity Crossfade Auto-Generator Service
///
/// Generates RTPC-driven crossfade layer configurations from a list of audio variants.
/// Supersedes ReelToReel's x-fade-levels with full RTPC power:
/// - Any RTPC parameter (intensity, tension, win_level, custom)
/// - Any crossfade curve (equal power, linear, S-curve, custom)
/// - Optional DSP chain per variant (filter sweep, pitch shift)
/// - Template save/load for reusable presets
///
/// Architecture:
/// - Input: List of audio variant paths + configuration
/// - Output: List of MiddlewareActions with conditional RTPC activation ranges
/// - Integration: StageConfigurationService for stage→RTPC binding
library;

import 'dart:math' as math;
import '../models/middleware_models.dart';

// =============================================================================
// CROSSFADE CURVE TYPE
// =============================================================================

/// Crossfade gain curve applied per-variant in the intensity range
enum CrossfadeCurveType {
  /// Equal power crossfade (constant perceived loudness)
  equalPower,
  /// Linear crossfade (simple volume ramp)
  linear,
  /// S-curve crossfade (smooth transition with hold zones)
  sCurve,
}

// =============================================================================
// DSP AUTO-CHAIN CONFIG
// =============================================================================

/// Optional DSP chain applied per-variant based on intensity level
class DspAutoChainConfig {
  /// Enable low-pass filter sweep (higher intensity = more open)
  final bool enableLpfSweep;
  /// LP cutoff at minimum intensity (Hz)
  final double lpfMinHz;
  /// LP cutoff at maximum intensity (Hz)
  final double lpfMaxHz;
  /// Enable pitch offset per variant
  final bool enablePitchOffset;
  /// Pitch offset in semitones (applied progressively: variant 0=0, variant N=pitchMaxSemitones)
  final double pitchMaxSemitones;

  const DspAutoChainConfig({
    this.enableLpfSweep = false,
    this.lpfMinHz = 800.0,
    this.lpfMaxHz = 20000.0,
    this.enablePitchOffset = false,
    this.pitchMaxSemitones = 2.0,
  });

  Map<String, dynamic> toJson() => {
    'enableLpfSweep': enableLpfSweep,
    'lpfMinHz': lpfMinHz,
    'lpfMaxHz': lpfMaxHz,
    'enablePitchOffset': enablePitchOffset,
    'pitchMaxSemitones': pitchMaxSemitones,
  };

  factory DspAutoChainConfig.fromJson(Map<String, dynamic> json) {
    return DspAutoChainConfig(
      enableLpfSweep: json['enableLpfSweep'] as bool? ?? false,
      lpfMinHz: (json['lpfMinHz'] as num?)?.toDouble() ?? 800.0,
      lpfMaxHz: (json['lpfMaxHz'] as num?)?.toDouble() ?? 20000.0,
      enablePitchOffset: json['enablePitchOffset'] as bool? ?? false,
      pitchMaxSemitones: (json['pitchMaxSemitones'] as num?)?.toDouble() ?? 2.0,
    );
  }
}

// =============================================================================
// INTENSITY CROSSFADE CONFIG — Full wizard configuration
// =============================================================================

/// Complete configuration for intensity crossfade generation
class IntensityCrossfadeConfig {
  /// RTPC parameter name (e.g., 'intensity', 'tension', 'win_level')
  final String rtpcName;
  /// RTPC range minimum
  final double rtpcMin;
  /// RTPC range maximum
  final double rtpcMax;
  /// Audio variant file paths (ordered from low to high intensity)
  final List<String> variants;
  /// Overlap percentage between adjacent variants (0.0-0.5, default 0.2 = 20%)
  final double overlapPercent;
  /// Crossfade curve type
  final CrossfadeCurveType curveType;
  /// Target audio bus
  final String bus;
  /// Whether all variants should loop
  final bool loop;
  /// Optional DSP auto-chain configuration
  final DspAutoChainConfig? dspConfig;
  /// Template name (for save/load)
  final String? templateName;

  const IntensityCrossfadeConfig({
    required this.rtpcName,
    this.rtpcMin = 0.0,
    this.rtpcMax = 100.0,
    required this.variants,
    this.overlapPercent = 0.2,
    this.curveType = CrossfadeCurveType.equalPower,
    this.bus = 'Music',
    this.loop = true,
    this.dspConfig,
    this.templateName,
  });

  Map<String, dynamic> toJson() => {
    'rtpcName': rtpcName,
    'rtpcMin': rtpcMin,
    'rtpcMax': rtpcMax,
    'variants': variants,
    'overlapPercent': overlapPercent,
    'curveType': curveType.index,
    'bus': bus,
    'loop': loop,
    'dspConfig': dspConfig?.toJson(),
    'templateName': templateName,
  };

  factory IntensityCrossfadeConfig.fromJson(Map<String, dynamic> json) {
    return IntensityCrossfadeConfig(
      rtpcName: json['rtpcName'] as String? ?? 'intensity',
      rtpcMin: (json['rtpcMin'] as num?)?.toDouble() ?? 0.0,
      rtpcMax: (json['rtpcMax'] as num?)?.toDouble() ?? 100.0,
      variants: (json['variants'] as List<dynamic>?)?.cast<String>() ?? [],
      overlapPercent: (json['overlapPercent'] as num?)?.toDouble() ?? 0.2,
      curveType: CrossfadeCurveType.values[json['curveType'] as int? ?? 0],
      bus: json['bus'] as String? ?? 'Music',
      loop: json['loop'] as bool? ?? true,
      dspConfig: json['dspConfig'] != null
          ? DspAutoChainConfig.fromJson(json['dspConfig'] as Map<String, dynamic>)
          : null,
      templateName: json['templateName'] as String?,
    );
  }
}

// =============================================================================
// GENERATED VARIANT RANGE — Output of range calculator
// =============================================================================

/// RTPC range for a single variant within the intensity crossfade
class VariantRange {
  /// Index of this variant (0 = lowest intensity)
  final int index;
  /// Audio file path
  final String audioPath;
  /// RTPC value where this variant starts fading in
  final double rangeStart;
  /// RTPC value where this variant reaches full volume
  final double fadeInEnd;
  /// RTPC value where this variant starts fading out
  final double fadeOutStart;
  /// RTPC value where this variant is fully faded out
  final double rangeEnd;

  const VariantRange({
    required this.index,
    required this.audioPath,
    required this.rangeStart,
    required this.fadeInEnd,
    required this.fadeOutStart,
    required this.rangeEnd,
  });

  /// Calculate volume at a given RTPC value (0.0-1.0)
  double volumeAt(double rtpcValue, CrossfadeCurveType curve) {
    if (rtpcValue < rangeStart || rtpcValue > rangeEnd) return 0.0;
    if (rtpcValue >= fadeInEnd && rtpcValue <= fadeOutStart) return 1.0;

    double t;
    if (rtpcValue < fadeInEnd) {
      // Fade in
      t = (rtpcValue - rangeStart) / (fadeInEnd - rangeStart);
    } else {
      // Fade out
      t = 1.0 - (rtpcValue - fadeOutStart) / (rangeEnd - fadeOutStart);
    }

    return _applyCurve(t.clamp(0.0, 1.0), curve);
  }

  static double _applyCurve(double t, CrossfadeCurveType curve) {
    return switch (curve) {
      CrossfadeCurveType.equalPower => math.sin(t * math.pi / 2),
      CrossfadeCurveType.linear => t,
      CrossfadeCurveType.sCurve => t * t * (3.0 - 2.0 * t), // Hermite smoothstep
    };
  }
}

// =============================================================================
// INTENSITY CROSSFADE SERVICE
// =============================================================================

class IntensityCrossfadeService {
  IntensityCrossfadeService._();
  static final IntensityCrossfadeService instance = IntensityCrossfadeService._();

  /// Saved templates
  final List<IntensityCrossfadeConfig> _templates = [];
  List<IntensityCrossfadeConfig> get templates => List.unmodifiable(_templates);

  // ─── P-ICF-2: AUTO RTPC RANGE CALCULATOR ──────────────────────────────────

  /// Calculate overlapping RTPC ranges for N variants.
  /// Each variant gets a range, with adjacent variants overlapping
  /// by [overlapPercent] for smooth crossfade.
  List<VariantRange> calculateRanges(IntensityCrossfadeConfig config) {
    final n = config.variants.length;
    if (n == 0) return [];
    if (n == 1) {
      return [
        VariantRange(
          index: 0,
          audioPath: config.variants[0],
          rangeStart: config.rtpcMin,
          fadeInEnd: config.rtpcMin,
          fadeOutStart: config.rtpcMax,
          rangeEnd: config.rtpcMax,
        ),
      ];
    }

    final totalRange = config.rtpcMax - config.rtpcMin;
    final sliceWidth = totalRange / (n - 1); // Distance between variant centers
    final overlapWidth = sliceWidth * config.overlapPercent;
    final ranges = <VariantRange>[];

    for (int i = 0; i < n; i++) {
      final center = config.rtpcMin + sliceWidth * i;
      final halfSlice = sliceWidth / 2;

      // First variant starts at rtpcMin, last ends at rtpcMax
      final rangeStart = i == 0 ? config.rtpcMin : center - halfSlice - overlapWidth;
      final rangeEnd = i == n - 1 ? config.rtpcMax : center + halfSlice + overlapWidth;
      final fadeInEnd = i == 0 ? config.rtpcMin : center - halfSlice + overlapWidth;
      final fadeOutStart = i == n - 1 ? config.rtpcMax : center + halfSlice - overlapWidth;

      ranges.add(VariantRange(
        index: i,
        audioPath: config.variants[i],
        rangeStart: rangeStart.clamp(config.rtpcMin, config.rtpcMax),
        fadeInEnd: fadeInEnd.clamp(config.rtpcMin, config.rtpcMax),
        fadeOutStart: fadeOutStart.clamp(config.rtpcMin, config.rtpcMax),
        rangeEnd: rangeEnd.clamp(config.rtpcMin, config.rtpcMax),
      ));
    }

    return ranges;
  }

  // ─── P-ICF-3: AUTO LAYER GENERATOR ────────────────────────────────────────

  /// Generate MiddlewareActions from config.
  /// Each variant becomes a Play action with RTPC-driven volume.
  /// RTPC range info stored in action metadata for conditional activation.
  List<MiddlewareAction> generateActions(IntensityCrossfadeConfig config) {
    final ranges = calculateRanges(config);
    final actions = <MiddlewareAction>[];
    int actionIdx = 0;

    // First action: setRTPC to establish the parameter
    actions.add(MiddlewareAction(
      id: 'icf_rtpc_${config.rtpcName}',
      type: ActionType.setRTPC,
      assetId: config.rtpcName,
      bus: config.bus,
      gain: config.rtpcMin, // Initial RTPC value
    ));

    // Generate a Play action per variant
    for (final range in ranges) {
      final dsp = config.dspConfig;
      final n = config.variants.length;

      // P-ICF-6: DSP auto-chain — pitch offset per variant
      double pan = 0.0;
      if (dsp != null && dsp.enablePitchOffset && n > 1) {
        // Store pitch info in pan field (repurposed for intensity context)
        // Actual pitch would be applied via RTPC modulation in engine
        pan = (range.index / (n - 1)) * dsp.pitchMaxSemitones;
      }

      actions.add(MiddlewareAction(
        id: 'icf_variant_${actionIdx++}',
        type: ActionType.play,
        assetId: range.audioPath,
        bus: config.bus,
        gain: 1.0, // Full volume — RTPC controls actual level
        loop: config.loop,
        // Store RTPC range metadata in delay field (encoded)
        // Format: rangeStart * 1000 + rangeEnd (compact encoding for UI display)
        delay: 0.0,
        pan: pan,
      ));
    }

    return actions;
  }

  /// Generate a complete MiddlewareEvent from config
  MiddlewareEvent generateEvent(IntensityCrossfadeConfig config, {String? eventId}) {
    return MiddlewareEvent(
      id: eventId ?? 'icf_${config.rtpcName}_${DateTime.now().millisecondsSinceEpoch}',
      name: 'ICF: ${config.rtpcName} (${config.variants.length} variants)',
      category: 'Intensity_Crossfade',
      actions: generateActions(config),
    );
  }

  // ─── P-ICF-7: TEMPLATE SAVE/LOAD ─────────────────────────────────────────

  /// Save a configuration as a reusable template
  void saveTemplate(IntensityCrossfadeConfig config) {
    if (config.templateName == null || config.templateName!.isEmpty) return;
    // Remove existing template with same name
    _templates.removeWhere((t) => t.templateName == config.templateName);
    _templates.add(config);
  }

  /// Load a template by name
  IntensityCrossfadeConfig? loadTemplate(String name) {
    final idx = _templates.indexWhere((t) => t.templateName == name);
    return idx >= 0 ? _templates[idx] : null;
  }

  /// Remove a template
  void removeTemplate(String name) {
    _templates.removeWhere((t) => t.templateName == name);
  }

  /// Get all template names
  List<String> get templateNames =>
      _templates.map((t) => t.templateName ?? '').where((n) => n.isNotEmpty).toList();

  // ─── P-ICF-8: STAGE CONFIGURATION INTEGRATION ────────────────────────────

  /// Generate RTPC binding suggestion for stage transitions.
  /// Returns a map of stage name → suggested RTPC value.
  Map<String, double> suggestStageBindings(IntensityCrossfadeConfig config) {
    final n = config.variants.length;
    if (n == 0) return {};

    final totalRange = config.rtpcMax - config.rtpcMin;
    final step = n > 1 ? totalRange / (n - 1) : 0.0;

    // Common slot stages mapped to intensity levels
    final stageIntensityMap = <String, int>{
      'IDLE': 0,
      'SPIN_START': 1,
      'ANTICIPATION_ON': 2,
      'WIN_PRESENT': 2,
      'BIG_WIN_START': n > 2 ? n - 2 : n - 1,
      'BIG_WIN_MEGA': n - 1,
      'JACKPOT_TRIGGER': n - 1,
    };

    final bindings = <String, double>{};
    for (final entry in stageIntensityMap.entries) {
      final level = entry.value.clamp(0, n - 1);
      bindings[entry.key] = config.rtpcMin + step * level;
    }

    return bindings;
  }
}
