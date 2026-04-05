/// Metering Preset Model (P10.1.17)
///
/// Save/load metering configurations:
/// - Ballistics (peak hold, decay rate)
/// - Scale (dB range, reference level)
/// - Colors (gradient, clip indicator)
/// - Mode presets (Broadcast, Music, Mastering, Film)
///
/// Enables standardized metering across different contexts.
library;

import 'dart:ui' show Color;

/// Schema version for forward compatibility
const int kMeteringPresetSchemaVersion = 1;

// ═══════════════════════════════════════════════════════════════════════════
// METERING BALLISTICS
// ═══════════════════════════════════════════════════════════════════════════

/// Ballistics configuration for meters
class MeteringBallistics {
  final double peakHoldTimeMs; // Time to hold peak (0 = off, 1500 = typical)
  final double peakDecayRate; // Decay rate per frame (0.01 - 0.2)
  final double meterDecayRate; // Decay multiplier (0.7 - 0.95)
  final double attackTimeMs; // Rise time (0 = instant, 10 = smooth)
  final double releaseTimeMs; // Fall time (100 - 500 typical)

  const MeteringBallistics({
    this.peakHoldTimeMs = 1500,
    this.peakDecayRate = 0.05,
    this.meterDecayRate = 0.85,
    this.attackTimeMs = 0,
    this.releaseTimeMs = 300,
  });

  Map<String, dynamic> toJson() => {
        'peakHoldTimeMs': peakHoldTimeMs,
        'peakDecayRate': peakDecayRate,
        'meterDecayRate': meterDecayRate,
        'attackTimeMs': attackTimeMs,
        'releaseTimeMs': releaseTimeMs,
      };

  factory MeteringBallistics.fromJson(Map<String, dynamic> json) {
    return MeteringBallistics(
      peakHoldTimeMs: (json['peakHoldTimeMs'] as num?)?.toDouble() ?? 1500,
      peakDecayRate: (json['peakDecayRate'] as num?)?.toDouble() ?? 0.05,
      meterDecayRate: (json['meterDecayRate'] as num?)?.toDouble() ?? 0.85,
      attackTimeMs: (json['attackTimeMs'] as num?)?.toDouble() ?? 0,
      releaseTimeMs: (json['releaseTimeMs'] as num?)?.toDouble() ?? 300,
    );
  }

  MeteringBallistics copyWith({
    double? peakHoldTimeMs,
    double? peakDecayRate,
    double? meterDecayRate,
    double? attackTimeMs,
    double? releaseTimeMs,
  }) {
    return MeteringBallistics(
      peakHoldTimeMs: peakHoldTimeMs ?? this.peakHoldTimeMs,
      peakDecayRate: peakDecayRate ?? this.peakDecayRate,
      meterDecayRate: meterDecayRate ?? this.meterDecayRate,
      attackTimeMs: attackTimeMs ?? this.attackTimeMs,
      releaseTimeMs: releaseTimeMs ?? this.releaseTimeMs,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// METERING SCALE
// ═══════════════════════════════════════════════════════════════════════════

/// Scale configuration for meters
class MeteringScale {
  final double minDb; // Bottom of scale (-60 to -40)
  final double maxDb; // Top of scale (0 to +6)
  final double referenceDb; // 0dB reference point
  final double warningDb; // Yellow zone start (-6 to -3)
  final double clipDb; // Red/clip zone start (-1 to 0)
  final bool showLufs; // Show LUFS scale
  final double targetLufs; // Target LUFS level (-14 for streaming)

  const MeteringScale({
    this.minDb = -60,
    this.maxDb = 0,
    this.referenceDb = 0,
    this.warningDb = -6,
    this.clipDb = -1,
    this.showLufs = false,
    this.targetLufs = -14,
  });

  Map<String, dynamic> toJson() => {
        'minDb': minDb,
        'maxDb': maxDb,
        'referenceDb': referenceDb,
        'warningDb': warningDb,
        'clipDb': clipDb,
        'showLufs': showLufs,
        'targetLufs': targetLufs,
      };

  factory MeteringScale.fromJson(Map<String, dynamic> json) {
    return MeteringScale(
      minDb: (json['minDb'] as num?)?.toDouble() ?? -60,
      maxDb: (json['maxDb'] as num?)?.toDouble() ?? 0,
      referenceDb: (json['referenceDb'] as num?)?.toDouble() ?? 0,
      warningDb: (json['warningDb'] as num?)?.toDouble() ?? -6,
      clipDb: (json['clipDb'] as num?)?.toDouble() ?? -1,
      showLufs: json['showLufs'] as bool? ?? false,
      targetLufs: (json['targetLufs'] as num?)?.toDouble() ?? -14,
    );
  }

  MeteringScale copyWith({
    double? minDb,
    double? maxDb,
    double? referenceDb,
    double? warningDb,
    double? clipDb,
    bool? showLufs,
    double? targetLufs,
  }) {
    return MeteringScale(
      minDb: minDb ?? this.minDb,
      maxDb: maxDb ?? this.maxDb,
      referenceDb: referenceDb ?? this.referenceDb,
      warningDb: warningDb ?? this.warningDb,
      clipDb: clipDb ?? this.clipDb,
      showLufs: showLufs ?? this.showLufs,
      targetLufs: targetLufs ?? this.targetLufs,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// METERING COLORS
// ═══════════════════════════════════════════════════════════════════════════

/// Color configuration for meters
class MeteringColors {
  final int normalColor; // Green zone
  final int warningColor; // Yellow zone
  final int clipColor; // Red zone
  final int peakHoldColor; // Peak hold indicator
  final int backgroundColor; // Meter background
  final int gridColor; // Scale grid lines

  const MeteringColors({
    this.normalColor = 0xFF4ADE80, // Green
    this.warningColor = 0xFFF59E0B, // Yellow/Amber
    this.clipColor = 0xFFEF4444, // Red
    this.peakHoldColor = 0xFFFFFFFF, // White
    this.backgroundColor = 0xFF1A1A20, // Dark gray
    this.gridColor = 0xFF3A3A40, // Mid gray
  });

  Color get normal => Color(normalColor);
  Color get warning => Color(warningColor);
  Color get clip => Color(clipColor);
  Color get peakHold => Color(peakHoldColor);
  Color get background => Color(backgroundColor);
  Color get grid => Color(gridColor);

  Map<String, dynamic> toJson() => {
        'normalColor': normalColor,
        'warningColor': warningColor,
        'clipColor': clipColor,
        'peakHoldColor': peakHoldColor,
        'backgroundColor': backgroundColor,
        'gridColor': gridColor,
      };

  factory MeteringColors.fromJson(Map<String, dynamic> json) {
    return MeteringColors(
      normalColor: json['normalColor'] as int? ?? 0xFF4ADE80,
      warningColor: json['warningColor'] as int? ?? 0xFFF59E0B,
      clipColor: json['clipColor'] as int? ?? 0xFFEF4444,
      peakHoldColor: json['peakHoldColor'] as int? ?? 0xFFFFFFFF,
      backgroundColor: json['backgroundColor'] as int? ?? 0xFF1A1A20,
      gridColor: json['gridColor'] as int? ?? 0xFF3A3A40,
    );
  }

  MeteringColors copyWith({
    int? normalColor,
    int? warningColor,
    int? clipColor,
    int? peakHoldColor,
    int? backgroundColor,
    int? gridColor,
  }) {
    return MeteringColors(
      normalColor: normalColor ?? this.normalColor,
      warningColor: warningColor ?? this.warningColor,
      clipColor: clipColor ?? this.clipColor,
      peakHoldColor: peakHoldColor ?? this.peakHoldColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      gridColor: gridColor ?? this.gridColor,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// METERING PRESET
// ═══════════════════════════════════════════════════════════════════════════

/// Complete metering preset
class MeteringPreset {
  final int schemaVersion;
  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;

  final MeteringBallistics ballistics;
  final MeteringScale scale;
  final MeteringColors colors;

  const MeteringPreset({
    this.schemaVersion = kMeteringPresetSchemaVersion,
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    this.ballistics = const MeteringBallistics(),
    this.scale = const MeteringScale(),
    this.colors = const MeteringColors(),
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'ballistics': ballistics.toJson(),
        'scale': scale.toJson(),
        'colors': colors.toJson(),
      };

  factory MeteringPreset.fromJson(Map<String, dynamic> json) {
    return MeteringPreset(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled',
      description: json['description'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      ballistics: json['ballistics'] != null
          ? MeteringBallistics.fromJson(json['ballistics'] as Map<String, dynamic>)
          : const MeteringBallistics(),
      scale: json['scale'] != null
          ? MeteringScale.fromJson(json['scale'] as Map<String, dynamic>)
          : const MeteringScale(),
      colors: json['colors'] != null
          ? MeteringColors.fromJson(json['colors'] as Map<String, dynamic>)
          : const MeteringColors(),
    );
  }

  MeteringPreset copyWith({
    int? schemaVersion,
    String? id,
    String? name,
    String? description,
    DateTime? createdAt,
    MeteringBallistics? ballistics,
    MeteringScale? scale,
    MeteringColors? colors,
  }) {
    return MeteringPreset(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      ballistics: ballistics ?? this.ballistics,
      scale: scale ?? this.scale,
      colors: colors ?? this.colors,
    );
  }

  /// Generate unique ID
  static String generateId() => 'meter_${DateTime.now().millisecondsSinceEpoch}';
}

// ═══════════════════════════════════════════════════════════════════════════
// BUILT-IN PRESETS
// ═══════════════════════════════════════════════════════════════════════════

/// Built-in metering presets for different contexts
class MeteringPresets {
  MeteringPresets._();

  /// Broadcast standard (EBU R128, -23 LUFS target)
  static final broadcast = MeteringPreset(
    id: 'builtin_broadcast',
    name: 'Broadcast',
    description: 'EBU R128 broadcast standard (-23 LUFS)',
    createdAt: DateTime(2026, 1, 1),
    ballistics: const MeteringBallistics(
      peakHoldTimeMs: 3000,
      peakDecayRate: 0.03,
      meterDecayRate: 0.9,
      attackTimeMs: 5,
      releaseTimeMs: 400,
    ),
    scale: const MeteringScale(
      minDb: -60,
      maxDb: 0,
      warningDb: -9,
      clipDb: -1,
      showLufs: true,
      targetLufs: -23,
    ),
    colors: const MeteringColors(
      normalColor: 0xFF22C55E, // Green
      warningColor: 0xFFEAB308, // Yellow
      clipColor: 0xFFDC2626, // Red
    ),
  );

  /// Music production (louder, streaming target -14 LUFS)
  static final music = MeteringPreset(
    id: 'builtin_music',
    name: 'Music',
    description: 'Music production and streaming (-14 LUFS target)',
    createdAt: DateTime(2026, 1, 1),
    ballistics: const MeteringBallistics(
      peakHoldTimeMs: 1500,
      peakDecayRate: 0.05,
      meterDecayRate: 0.85,
      attackTimeMs: 0,
      releaseTimeMs: 300,
    ),
    scale: const MeteringScale(
      minDb: -60,
      maxDb: 0,
      warningDb: -6,
      clipDb: -0.5,
      showLufs: true,
      targetLufs: -14,
    ),
    colors: const MeteringColors(
      normalColor: 0xFF4ADE80, // Light green
      warningColor: 0xFFF59E0B, // Amber
      clipColor: 0xFFEF4444, // Red
    ),
  );

  /// Mastering (precise, headroom focused)
  static final mastering = MeteringPreset(
    id: 'builtin_mastering',
    name: 'Mastering',
    description: 'Mastering with true peak focus',
    createdAt: DateTime(2026, 1, 1),
    ballistics: const MeteringBallistics(
      peakHoldTimeMs: 5000, // Longer peak hold
      peakDecayRate: 0.02,
      meterDecayRate: 0.92,
      attackTimeMs: 0,
      releaseTimeMs: 500,
    ),
    scale: const MeteringScale(
      minDb: -48,
      maxDb: 3, // Show headroom above 0
      warningDb: -3,
      clipDb: -0.1, // Very strict clipping threshold
      showLufs: true,
      targetLufs: -14,
    ),
    colors: const MeteringColors(
      normalColor: 0xFF3B82F6, // Blue
      warningColor: 0xFFF97316, // Orange
      clipColor: 0xFFFF0000, // Bright red
      peakHoldColor: 0xFFFFD700, // Gold
    ),
  );

  /// Film post-production (dialogue norm -24 LUFS)
  static final film = MeteringPreset(
    id: 'builtin_film',
    name: 'Film',
    description: 'Film/TV post-production (-24 LUFS dialogue norm)',
    createdAt: DateTime(2026, 1, 1),
    ballistics: const MeteringBallistics(
      peakHoldTimeMs: 2000,
      peakDecayRate: 0.04,
      meterDecayRate: 0.88,
      attackTimeMs: 5,
      releaseTimeMs: 350,
    ),
    scale: const MeteringScale(
      minDb: -60,
      maxDb: 0,
      warningDb: -12, // More conservative for film
      clipDb: -2,
      showLufs: true,
      targetLufs: -24,
    ),
    colors: const MeteringColors(
      normalColor: 0xFF10B981, // Teal
      warningColor: 0xFFFBBF24, // Amber
      clipColor: 0xFFF87171, // Light red
    ),
  );

  /// List of all built-in presets
  static List<MeteringPreset> get all => [broadcast, music, mastering, film];
}
