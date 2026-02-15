/// FabFilter-Style Theme
///
/// Design language inspired by FabFilter Pro series:
/// - Dark backgrounds with subtle gradients
/// - Consistent color coding for functions
/// - Real-time visual feedback
/// - Progressive disclosure (basic → expert)

import 'package:flutter/material.dart';

/// FabFilter-inspired color palette
class FabFilterColors {
  FabFilterColors._();

  // ═══════════════════════════════════════════════════════════════════════════
  // BACKGROUNDS (6-layer depth system)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Deepest background (void, shadows)
  static const Color bgVoid = Color(0xFF08080C);

  /// Deep background (main panel bg)
  static const Color bgDeep = Color(0xFF0D0D12);

  /// Mid background (sections, zones)
  static const Color bgMid = Color(0xFF14141A);

  /// Surface (interactive elements base)
  static const Color bgSurface = Color(0xFF1A1A22);

  /// Elevated (active, selected)
  static const Color bgElevated = Color(0xFF22222C);

  /// Hover state
  static const Color bgHover = Color(0xFF2A2A38);

  // ═══════════════════════════════════════════════════════════════════════════
  // ACCENTS (Semantic meaning)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Primary blue — focus, selection, main accent
  static const Color blue = Color(0xFF4A9EFF);

  /// Orange — boost, active, warnings, EQ gain+
  static const Color orange = Color(0xFFFF9040);

  /// Cyan — cut, EQ gain-, spectrum fill
  static const Color cyan = Color(0xFF40D0FF);

  /// Green — OK, enabled, safe levels
  static const Color green = Color(0xFF50FF90);

  /// Yellow — caution, threshold, dynamics
  static const Color yellow = Color(0xFFFFE040);

  /// Red — clip, error, danger
  static const Color red = Color(0xFFFF4050);

  /// Purple — automation, special
  static const Color purple = Color(0xFFB080FF);

  /// Pink — MIDI, markers
  static const Color pink = Color(0xFFFF80B0);

  // ═══════════════════════════════════════════════════════════════════════════
  // SPECTRUM GRADIENT (bottom to top)
  // ═══════════════════════════════════════════════════════════════════════════

  static const List<Color> spectrumGradient = [
    Color(0xFF40D0FF), // Cyan - low levels
    Color(0xFF50FF90), // Green - normal
    Color(0xFFFFE040), // Yellow - caution
    Color(0xFFFF9040), // Orange - hot
    Color(0xFFFF4050), // Red - danger
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // TEXT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Primary text (max readability)
  static const Color textPrimary = Color(0xFFF0F0F4);

  /// Secondary text (labels)
  static const Color textSecondary = Color(0xFFB0B0B8);

  /// Tertiary text (hints, muted)
  static const Color textTertiary = Color(0xFF707078);

  /// Muted text (alias for textTertiary)
  static const Color textMuted = textTertiary;

  /// Disabled text
  static const Color textDisabled = Color(0xFF505058);

  /// Grid lines
  static const Color grid = Color(0xFF303040);

  /// Border (alias for borderSubtle)
  static const Color border = borderSubtle;

  // ═══════════════════════════════════════════════════════════════════════════
  // BORDERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Subtle border (separators)
  static const Color borderSubtle = Color(0xFF2A2A34);

  /// Medium border (cards)
  static const Color borderMedium = Color(0xFF3A3A46);

  /// Focus border
  static const Color borderFocus = blue;
}

/// FabFilter-style text styles
class FabFilterText {
  FabFilterText._();

  /// Panel title (e.g., "PRO-Q 4")
  static const TextStyle title = TextStyle(
    color: FabFilterColors.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.bold,
    letterSpacing: 1.2,
  );

  /// Section header
  static const TextStyle sectionHeader = TextStyle(
    color: FabFilterColors.textSecondary,
    fontSize: 10,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.8,
  );

  /// Parameter label
  static const TextStyle paramLabel = TextStyle(
    color: FabFilterColors.textTertiary,
    fontSize: 9,
    fontWeight: FontWeight.w600,
  );

  /// Parameter value
  static TextStyle paramValue(Color color) => TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Button text
  static const TextStyle button = TextStyle(
    color: FabFilterColors.textPrimary,
    fontSize: 10,
    fontWeight: FontWeight.bold,
  );
}

/// Common FabFilter-style decorations
class FabFilterDecorations {
  FabFilterDecorations._();

  /// Main panel container
  static BoxDecoration panel({bool selected = false}) => BoxDecoration(
        color: FabFilterColors.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? FabFilterColors.blue : FabFilterColors.borderSubtle,
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      );

  /// Display area (spectrum, graph)
  static BoxDecoration display() => BoxDecoration(
        color: FabFilterColors.bgVoid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FabFilterColors.borderSubtle),
      );

  /// Control section
  static BoxDecoration section() => BoxDecoration(
        color: FabFilterColors.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.borderSubtle),
      );

  /// Toggle button (inactive)
  static BoxDecoration toggleInactive() => BoxDecoration(
        color: FabFilterColors.bgSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.borderMedium),
      );

  /// Toggle button (active)
  static BoxDecoration toggleActive(Color color) => BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 1.5),
      );

  /// Chip/tag style
  static BoxDecoration chip(Color color, {bool selected = false}) =>
      BoxDecoration(
        color: selected ? color : FabFilterColors.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: selected ? 2 : 1),
      );

  /// Toggle button (alias for toggleInactive)
  static BoxDecoration toggle() => toggleInactive();
}

/// FabFilter-style text styles (convenience class)
class FabFilterTextStyles {
  FabFilterTextStyles._();

  /// Label text style
  static const TextStyle label = TextStyle(
    color: FabFilterColors.textTertiary,
    fontSize: 9,
    fontWeight: FontWeight.w600,
  );

  /// Value text style
  static const TextStyle value = TextStyle(
    color: FabFilterColors.textPrimary,
    fontSize: 11,
    fontWeight: FontWeight.bold,
  );
}

/// FabFilter-style slider theme
SliderThemeData fabFilterSliderTheme(Color activeColor) => SliderThemeData(
      trackHeight: 4,
      activeTrackColor: activeColor,
      inactiveTrackColor: FabFilterColors.borderSubtle,
      thumbColor: activeColor,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayColor: activeColor.withValues(alpha: 0.2),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      trackShape: const RoundedRectSliderTrackShape(),
    );

/// Common animation durations
class FabFilterDurations {
  FabFilterDurations._();

  /// Fast feedback (hover, press)
  static const Duration fast = Duration(milliseconds: 100);

  /// Normal transitions
  static const Duration normal = Duration(milliseconds: 200);

  /// Smooth parameter changes
  static const Duration smooth = Duration(milliseconds: 300);

  /// Slow animations (panel open/close)
  static const Duration slow = Duration(milliseconds: 400);
}

/// Common curves
class FabFilterCurves {
  FabFilterCurves._();

  /// Snappy response
  static const Curve snappy = Curves.easeOutCubic;

  /// Smooth easing
  static const Curve smooth = Curves.easeInOutCubic;

  /// Bouncy (for selection rings)
  static const Curve bouncy = Curves.elasticOut;
}

// ═══════════════════════════════════════════════════════════════════════════
// PROCESSOR-SPECIFIC COLOR MAPS
// ═══════════════════════════════════════════════════════════════════════════

/// Per-processor accent + display colors (matching real FabFilter products)
class FabFilterProcessorColors {
  FabFilterProcessorColors._();

  // ─── Pro-Q (EQ) ────────────────────────────────────────────────────────
  static const Color eqAccent = FabFilterColors.blue;
  static const Color eqBoost = FabFilterColors.orange;
  static const Color eqCut = FabFilterColors.cyan;
  static const Color eqSpectrumFill = Color(0xFF1A4060);
  static const Color eqAnalyzerLine = Color(0xFF40D0FF);
  static const Color eqCurveLine = Color(0xFFFFFFFF);

  // ─── Pro-C (Compressor) ────────────────────────────────────────────────
  static const Color compAccent = FabFilterColors.orange;
  static const Color compGainReduction = Color(0xFFFF6030);
  static const Color compThreshold = FabFilterColors.yellow;
  static const Color compEnvelope = Color(0xFF80FF60);
  static const Color compKnee = Color(0xFFFFB060);

  // ─── Pro-L (Limiter) ──────────────────────────────────────────────────
  static const Color limAccent = FabFilterColors.red;
  static const Color limGainReduction = Color(0xFFFF3040);
  static const Color limCeiling = Color(0xFFFF6040);
  static const Color limTruePeak = FabFilterColors.cyan;
  static const Color limLufs = FabFilterColors.green;

  // ─── Pro-G (Gate) ─────────────────────────────────────────────────────
  static const Color gateAccent = FabFilterColors.green;
  static const Color gateOpen = FabFilterColors.green;
  static const Color gateClosed = FabFilterColors.red;
  static const Color gateThreshold = FabFilterColors.yellow;
  static const Color gateRange = FabFilterColors.orange;

  // ─── Pro-R (Reverb) ───────────────────────────────────────────────────
  static const Color reverbAccent = FabFilterColors.purple;
  static const Color reverbDecay = Color(0xFF9060FF);
  static const Color reverbPredelay = FabFilterColors.blue;
  static const Color reverbEarlyRef = FabFilterColors.cyan;
  static const Color reverbFreeze = Color(0xFF40FFFF);

  // ─── Saturn (Saturator) ───────────────────────────────────────────────
  static const Color satAccent = FabFilterColors.orange;
  static const Color satDrive = Color(0xFFFF8020);
  static const Color satWarmth = Color(0xFFFF6040);
}

/// Metering gradient stops (bottom→top: green→yellow→orange→red)
class FabFilterGradients {
  FabFilterGradients._();

  /// Standard peak/RMS meter gradient
  static const LinearGradient meterVertical = LinearGradient(
    begin: Alignment.bottomCenter, end: Alignment.topCenter,
    colors: [
      Color(0xFF40FF60), // Green — safe
      Color(0xFF80FF40), // Yellow-green — normal
      Color(0xFFFFE040), // Yellow — caution
      Color(0xFFFF9040), // Orange — hot
      Color(0xFFFF4040), // Red — clip
    ],
    stops: [0.0, 0.4, 0.7, 0.85, 1.0],
  );

  /// GR meter gradient (inverted: red=lots of GR)
  static const LinearGradient grVertical = LinearGradient(
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
    colors: [
      Color(0xFF40FF60), // Green — little GR
      Color(0xFFFFE040), // Yellow — moderate
      Color(0xFFFF6030), // Orange — heavy
      Color(0xFFFF3040), // Red — severe
    ],
    stops: [0.0, 0.3, 0.7, 1.0],
  );

  /// Horizontal GR bar gradient
  static const LinearGradient grHorizontal = LinearGradient(
    begin: Alignment.centerRight, end: Alignment.centerLeft,
    colors: [
      Color(0xFF40FF60),
      Color(0xFFFFE040),
      Color(0xFFFF6030),
      Color(0xFFFF3040),
    ],
    stops: [0.0, 0.3, 0.7, 1.0],
  );

  /// Spectrum analyzer fill
  static LinearGradient spectrumFill(Color accent) => LinearGradient(
    begin: Alignment.bottomCenter, end: Alignment.topCenter,
    colors: [
      accent.withValues(alpha: 0.05),
      accent.withValues(alpha: 0.2),
      accent.withValues(alpha: 0.4),
    ],
  );

  /// Display background glow
  static RadialGradient displayGlow(Color accent) => RadialGradient(
    center: Alignment.center,
    radius: 0.8,
    colors: [
      accent.withValues(alpha: 0.08),
      accent.withValues(alpha: 0.02),
      Colors.transparent,
    ],
  );
}

/// Responsive breakpoints for panel layouts
class FabFilterBreakpoints {
  FabFilterBreakpoints._();

  /// Compact mode (Lower Zone, small panels)
  static const double compact = 280;

  /// Standard panel width
  static const double standard = 400;

  /// Wide panel (dual display)
  static const double wide = 600;

  /// Minimum usable height
  static const double minHeight = 180;

  /// Standard panel height
  static const double standardHeight = 300;
}
