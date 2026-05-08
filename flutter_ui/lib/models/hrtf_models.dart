/// HRTF Models — Anthropometric profile + database metadata
///
/// Mirror of the Rust `rf_spatial::binaural::AnthropometricProfile` plus a
/// lightweight metadata record for the live HRTF database.

import 'dart:convert';

// ═══════════════════════════════════════════════════════════════════════════
// ANTHROPOMETRIC PROFILE
// ═══════════════════════════════════════════════════════════════════════════

/// Physical measurements that drive the personalized HRTF generator.
///
/// Field ranges (biologically plausible adults):
/// * `headWidthMm` — temple-to-temple, 120–190
/// * `headDepthMm` — nasion-to-inion, 140–250
/// * `pinnaHeightMm` — outer-ear height, 35–95
/// * `pinnaWidthMm` — outer-ear width, 15–45
/// * `cavumConchaDepthMm` — concha bowl depth, 4–25
/// * `headCircumferenceMm` — supraorbital circumference, 480–680
/// * `interTragalDistanceMm` — tragus-to-tragus, 100–180
/// * `noseBridgeProminenceMm` — glabella forward projection, 4–28
class AnthropometricProfile {
  final double headWidthMm;
  final double headDepthMm;
  final double pinnaHeightMm;
  final double pinnaWidthMm;
  final double cavumConchaDepthMm;
  final double headCircumferenceMm;
  final double interTragalDistanceMm;
  final double noseBridgeProminenceMm;

  const AnthropometricProfile({
    required this.headWidthMm,
    required this.headDepthMm,
    required this.pinnaHeightMm,
    required this.pinnaWidthMm,
    required this.cavumConchaDepthMm,
    required this.headCircumferenceMm,
    required this.interTragalDistanceMm,
    required this.noseBridgeProminenceMm,
  });

  /// CIPIC database average (European male) — also the Rust default.
  static const cipicAverage = AnthropometricProfile(
    headWidthMm: 154.0,
    headDepthMm: 196.0,
    pinnaHeightMm: 66.0,
    pinnaWidthMm: 28.0,
    cavumConchaDepthMm: 12.5,
    headCircumferenceMm: 570.0,
    interTragalDistanceMm: 140.0,
    noseBridgeProminenceMm: 14.0,
  );

  /// Smaller-than-average (statistically representative female).
  static const small = AnthropometricProfile(
    headWidthMm: 142.0,
    headDepthMm: 180.0,
    pinnaHeightMm: 58.0,
    pinnaWidthMm: 25.0,
    cavumConchaDepthMm: 10.5,
    headCircumferenceMm: 540.0,
    interTragalDistanceMm: 128.0,
    noseBridgeProminenceMm: 11.0,
  );

  /// Larger-than-average (P95 male).
  static const large = AnthropometricProfile(
    headWidthMm: 168.0,
    headDepthMm: 212.0,
    pinnaHeightMm: 74.0,
    pinnaWidthMm: 32.0,
    cavumConchaDepthMm: 14.5,
    headCircumferenceMm: 600.0,
    interTragalDistanceMm: 152.0,
    noseBridgeProminenceMm: 17.0,
  );

  AnthropometricProfile copyWith({
    double? headWidthMm,
    double? headDepthMm,
    double? pinnaHeightMm,
    double? pinnaWidthMm,
    double? cavumConchaDepthMm,
    double? headCircumferenceMm,
    double? interTragalDistanceMm,
    double? noseBridgeProminenceMm,
  }) =>
      AnthropometricProfile(
        headWidthMm: headWidthMm ?? this.headWidthMm,
        headDepthMm: headDepthMm ?? this.headDepthMm,
        pinnaHeightMm: pinnaHeightMm ?? this.pinnaHeightMm,
        pinnaWidthMm: pinnaWidthMm ?? this.pinnaWidthMm,
        cavumConchaDepthMm: cavumConchaDepthMm ?? this.cavumConchaDepthMm,
        headCircumferenceMm: headCircumferenceMm ?? this.headCircumferenceMm,
        interTragalDistanceMm:
            interTragalDistanceMm ?? this.interTragalDistanceMm,
        noseBridgeProminenceMm:
            noseBridgeProminenceMm ?? this.noseBridgeProminenceMm,
      );

  Map<String, dynamic> toJson() => {
        'head_width_mm': headWidthMm,
        'head_depth_mm': headDepthMm,
        'pinna_height_mm': pinnaHeightMm,
        'pinna_width_mm': pinnaWidthMm,
        'cavum_concha_depth_mm': cavumConchaDepthMm,
        'head_circumference_mm': headCircumferenceMm,
        'inter_tragal_distance_mm': interTragalDistanceMm,
        'nose_bridge_prominence_mm': noseBridgeProminenceMm,
      };

  String toJsonString() => jsonEncode(toJson());

  factory AnthropometricProfile.fromJson(Map<String, dynamic> j) =>
      AnthropometricProfile(
        headWidthMm: (j['head_width_mm'] as num).toDouble(),
        headDepthMm: (j['head_depth_mm'] as num).toDouble(),
        pinnaHeightMm: (j['pinna_height_mm'] as num).toDouble(),
        pinnaWidthMm: (j['pinna_width_mm'] as num).toDouble(),
        cavumConchaDepthMm: (j['cavum_concha_depth_mm'] as num).toDouble(),
        headCircumferenceMm: (j['head_circumference_mm'] as num).toDouble(),
        interTragalDistanceMm: (j['inter_tragal_distance_mm'] as num).toDouble(),
        noseBridgeProminenceMm:
            (j['nose_bridge_prominence_mm'] as num).toDouble(),
      );

  factory AnthropometricProfile.fromJsonString(String s) =>
      AnthropometricProfile.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnthropometricProfile &&
          other.headWidthMm == headWidthMm &&
          other.headDepthMm == headDepthMm &&
          other.pinnaHeightMm == pinnaHeightMm &&
          other.pinnaWidthMm == pinnaWidthMm &&
          other.cavumConchaDepthMm == cavumConchaDepthMm &&
          other.headCircumferenceMm == headCircumferenceMm &&
          other.interTragalDistanceMm == interTragalDistanceMm &&
          other.noseBridgeProminenceMm == noseBridgeProminenceMm;

  @override
  int get hashCode => Object.hash(
        headWidthMm,
        headDepthMm,
        pinnaHeightMm,
        pinnaWidthMm,
        cavumConchaDepthMm,
        headCircumferenceMm,
        interTragalDistanceMm,
        noseBridgeProminenceMm,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// HRTF DATABASE METADATA
// ═══════════════════════════════════════════════════════════════════════════

/// Live state of the in-memory HRTF database (after a successful generate
/// or load).  All fields are read directly from the Rust side via the
/// `hrtf_metadata_json` FFI.
class HrtfDatabaseMetadata {
  final int sampleRate;
  final int filterLength;
  final int measurementCount;

  const HrtfDatabaseMetadata({
    required this.sampleRate,
    required this.filterLength,
    required this.measurementCount,
  });

  factory HrtfDatabaseMetadata.fromJsonString(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    return HrtfDatabaseMetadata(
      sampleRate: (j['sample_rate'] as num).toInt(),
      filterLength: (j['filter_length'] as num).toInt(),
      measurementCount: (j['measurement_count'] as num).toInt(),
    );
  }
}
