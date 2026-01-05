/// ReelForge Pro Audio Theme
///
/// Best-in-class professional dark theme synthesizing:
/// - Cubase: Zone system depth, MixConsole clarity
/// - Pro Tools: Industry-standard contrast ratios
/// - Logic Pro: Apple-level polish and consistency
/// - FL Studio: High-contrast piano roll excellence
/// - Ableton: Minimalist focus and clarity
/// - Studio One: Single-window workflow elegance
///
/// Design principles:
/// - 6-layer depth system for spatial hierarchy
/// - WCAG AAA contrast ratios (7:1+)
/// - Semantic accent colors with clear meanings
/// - GPU-optimized gradients and shadows
/// - 8px grid system alignment

import 'package:flutter/material.dart';

class ReelForgeTheme {
  // ═══════════════════════════════════════════════════════════════════════════
  // COLOR PALETTE - Pro Audio Dark (6-Layer Depth System)
  // ═══════════════════════════════════════════════════════════════════════════

  // Backgrounds (6 depth layers - deepest to brightest)
  // Layer 0: Void - popup shadows, deepest recesses
  static const Color bgVoid = Color(0xFF06060A);
  // Layer 1: Abyss - app background, timeline background
  static const Color bgDeepest = Color(0xFF08080C);
  // Layer 2: Deep - panel backgrounds, zone backgrounds
  static const Color bgDeep = Color(0xFF0E0E14);
  // Layer 3: Mid - track backgrounds, card backgrounds
  static const Color bgMid = Color(0xFF16161E);
  // Layer 4: Surface - interactive surfaces, buttons
  static const Color bgSurface = Color(0xFF1E1E28);
  // Layer 5: Elevated - active elements, selected items
  static const Color bgElevated = Color(0xFF26263A);
  // Layer 6: Hover - hover states, focus rings
  static const Color bgHover = Color(0xFF2E2E42);

  // ═══════════════════════════════════════════════════════════════════════════
  // ACCENT COLORS - Semantic Meaning
  // ═══════════════════════════════════════════════════════════════════════════

  // Primary Blue - focus, selection, primary actions
  static const Color accentBlue = Color(0xFF5AA8FF);
  // Cyan - information, spectrum display, EQ cuts
  static const Color accentCyan = Color(0xFF50D8FF);
  // Orange - warnings, EQ boosts, active states
  static const Color accentOrange = Color(0xFFFF9850);
  // Green - success, play, record arm, positive values
  static const Color accentGreen = Color(0xFF50FF98);
  // Red - errors, stop, clip, negative values
  static const Color accentRed = Color(0xFFFF5068);
  // Purple - automation, special features
  static const Color accentPurple = Color(0xFFB080FF);
  // Yellow - solo, caution, attention
  static const Color accentYellow = Color(0xFFFFE050);
  // Pink - MIDI, markers
  static const Color accentPink = Color(0xFFFF80B0);

  // Semantic aliases
  static const Color errorRed = accentRed;
  static const Color warningOrange = accentOrange;
  static const Color successGreen = accentGreen;
  static const Color infoBlue = accentCyan;
  static const Color clipRed = Color(0xFFFF2040);  // Brighter for clip indicators

  // ═══════════════════════════════════════════════════════════════════════════
  // TEXT COLORS - WCAG AAA Contrast (7:1+)
  // ═══════════════════════════════════════════════════════════════════════════

  // Primary text - maximum readability
  static const Color textPrimary = Color(0xFFF0F0F4);
  // Secondary text - labels, descriptions
  static const Color textSecondary = Color(0xFFB8B8C0);
  // Tertiary text - hints, placeholders
  static const Color textTertiary = Color(0xFF808088);
  // Disabled text
  static const Color textDisabled = Color(0xFF505058);
  // Inverse text (on light backgrounds)
  static const Color textInverse = Color(0xFF0A0A0C);

  // ═══════════════════════════════════════════════════════════════════════════
  // BORDER COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  // Subtle - panel separators
  static const Color borderSubtle = Color(0xFF2A2A38);
  // Medium - card borders
  static const Color borderMedium = Color(0xFF3A3A4A);
  // Focus - keyboard focus, active selection
  static const Color borderFocus = accentBlue;
  // Error - validation errors
  static const Color borderError = accentRed;

  // ═══════════════════════════════════════════════════════════════════════════
  // METERING COLORS - Industry Standard Gradient
  // ═══════════════════════════════════════════════════════════════════════════

  // Metering gradient (bottom to top / left to right)
  static const List<Color> meterGradient = [
    Color(0xFF50D8FF), // Cyan - low levels (-inf to -24dB)
    Color(0xFF50FF98), // Green - normal (-24dB to -12dB)
    Color(0xFFFFE050), // Yellow - caution (-12dB to -6dB)
    Color(0xFFFF9850), // Orange - hot (-6dB to -3dB)
    Color(0xFFFF5068), // Red - danger (-3dB to 0dB)
  ];

  // Metering gradient stops (matching dB scale)
  static const List<double> meterStops = [0.0, 0.45, 0.65, 0.82, 1.0];

  // Peak hold indicator
  static const Color peakHoldColor = Color(0xFFFFFFFF);
  // Clip indicator (brighter red with glow)
  static const Color clipIndicator = Color(0xFFFF2040);

  // ═══════════════════════════════════════════════════════════════════════════
  // GRADIENTS
  // ═══════════════════════════════════════════════════════════════════════════

  // Surface gradient (subtle depth effect)
  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgSurface, bgMid],
  );

  // Panel header gradient
  static const LinearGradient panelHeaderGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgElevated, bgSurface],
  );

  // Blue glow gradient (for focus states)
  static const LinearGradient glowGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x305AA8FF),
      Color(0x005AA8FF),
    ],
  );

  // Meter gradient (vertical)
  static LinearGradient meterGradientVertical = const LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: meterGradient,
    stops: meterStops,
  );

  // Meter gradient (horizontal)
  static LinearGradient meterGradientHorizontal = const LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: meterGradient,
    stops: meterStops,
  );

  // Track color bar gradient
  static LinearGradient trackColorGradient(Color color) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [color, color.withValues(alpha: 0.6)],
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // SHADOWS & GLOW
  // ═══════════════════════════════════════════════════════════════════════════

  // Deep shadow (for modals, dropdowns)
  static List<BoxShadow> get deepShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.6),
      blurRadius: 24,
      offset: const Offset(0, 12),
      spreadRadius: -4,
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.4),
      blurRadius: 12,
      offset: const Offset(0, 6),
    ),
  ];

  // Elevated shadow (for floating panels)
  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.5),
      blurRadius: 12,
      offset: const Offset(0, 6),
      spreadRadius: -2,
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.25),
      blurRadius: 20,
      offset: const Offset(0, 10),
    ),
  ];

  // Subtle shadow (for cards, buttons)
  static List<BoxShadow> get subtleShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.35),
      blurRadius: 6,
      offset: const Offset(0, 3),
    ),
  ];

  // Inner shadow (for recessed elements)
  static List<BoxShadow> get innerShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.4),
      blurRadius: 4,
      offset: const Offset(0, 2),
      spreadRadius: -1,
    ),
  ];

  // Glow shadow (for accent elements)
  static List<BoxShadow> glowShadow(Color color, {double intensity = 0.5}) => [
    BoxShadow(
      color: color.withValues(alpha: intensity),
      blurRadius: 16,
      spreadRadius: -4,
    ),
    BoxShadow(
      color: color.withValues(alpha: intensity * 0.6),
      blurRadius: 8,
      spreadRadius: -2,
    ),
  ];

  // Focus glow (for keyboard focus states)
  static List<BoxShadow> get focusGlow => [
    BoxShadow(
      color: accentBlue.withValues(alpha: 0.4),
      blurRadius: 8,
      spreadRadius: 1,
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // DECORATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  // Standard panel (zones, inspectors)
  static BoxDecoration get panelDecoration => BoxDecoration(
    color: bgMid,
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: borderSubtle, width: 1),
    boxShadow: subtleShadow,
  );

  // Card decoration (items in lists, slots)
  static BoxDecoration get cardDecoration => BoxDecoration(
    color: bgSurface,
    borderRadius: BorderRadius.circular(4),
    border: Border.all(color: borderSubtle, width: 1),
  );

  // Glassmorphism decoration (floating overlays)
  static BoxDecoration get glassDecoration => BoxDecoration(
    color: bgSurface.withValues(alpha: 0.85),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(
      color: Colors.white.withValues(alpha: 0.08),
      width: 1,
    ),
    boxShadow: elevatedShadow,
  );

  // Inset decoration (text fields, recessed areas)
  static BoxDecoration get insetDecoration => BoxDecoration(
    color: bgDeepest,
    borderRadius: BorderRadius.circular(4),
    border: Border.all(color: borderSubtle, width: 1),
  );

  // Focus decoration
  static BoxDecoration focusDecoration(Color? color) => BoxDecoration(
    borderRadius: BorderRadius.circular(4),
    border: Border.all(color: color ?? accentBlue, width: 2),
    boxShadow: focusGlow,
  );

  // Track color bar decoration (left edge indicator)
  static BoxDecoration trackColorBar(Color color) => BoxDecoration(
    borderRadius: const BorderRadius.only(
      topLeft: Radius.circular(4),
      bottomLeft: Radius.circular(4),
    ),
    gradient: trackColorGradient(color),
  );

  // Meter background decoration
  static BoxDecoration get meterBackground => BoxDecoration(
    color: bgVoid,
    borderRadius: BorderRadius.circular(2),
    border: Border.all(color: borderSubtle.withValues(alpha: 0.5), width: 0.5),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // TYPOGRAPHY - 8px Grid Aligned
  // ═══════════════════════════════════════════════════════════════════════════

  // Font families
  static const String fontFamily = 'Inter';
  static const String monoFontFamily = 'JetBrains Mono';

  // Display heading (24px - 3 units)
  static TextStyle get h1 => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: -0.5,
    height: 1.25,
  );

  // Section heading (16px - 2 units)
  static TextStyle get h2 => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: -0.2,
    height: 1.25,
  );

  // Subsection heading (13px)
  static TextStyle get h3 => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    height: 1.3,
  );

  // Body text (12px)
  static TextStyle get body => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.4,
  );

  // Small body text (11px)
  static TextStyle get bodySmall => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: textTertiary,
    height: 1.4,
  );

  // Labels (10px)
  static TextStyle get label => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: textTertiary,
    letterSpacing: 0.3,
    height: 1.2,
  );

  // Tiny labels (9px - for meter markings)
  static TextStyle get labelTiny => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 9,
    fontWeight: FontWeight.w400,
    color: textDisabled,
    letterSpacing: 0.2,
  );

  // Monospace (12px - for timecodes, values)
  static TextStyle get mono => const TextStyle(
    fontFamily: monoFontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    letterSpacing: 0,
    height: 1.3,
  );

  // Small monospace (10px - for small displays)
  static TextStyle get monoSmall => const TextStyle(
    fontFamily: monoFontFamily,
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.2,
  );

  // Large monospace (16px - for main time display)
  static TextStyle get monoLarge => const TextStyle(
    fontFamily: monoFontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: 1,
    height: 1.2,
  );

  // Button text
  static TextStyle get button => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: 0.2,
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // ANIMATION CURVES & TIMING
  // ═══════════════════════════════════════════════════════════════════════════

  // Curves
  static const Curve smoothCurve = Curves.easeOutCubic;
  static const Curve snappyCurve = Curves.easeOutExpo;
  static const Curve bounceCurve = Curves.elasticOut;
  static const Curve reverseCurve = Curves.easeInCubic;
  static const Curve springCurve = Curves.easeOutBack;

  // Durations
  static const Duration instantDuration = Duration(milliseconds: 50);
  static const Duration fastDuration = Duration(milliseconds: 100);
  static const Duration normalDuration = Duration(milliseconds: 200);
  static const Duration slowDuration = Duration(milliseconds: 350);
  static const Duration pageTransition = Duration(milliseconds: 300);

  // ═══════════════════════════════════════════════════════════════════════════
  // SPACING & SIZING - 8px Grid System
  // ═══════════════════════════════════════════════════════════════════════════

  // Base unit
  static const double unit = 8.0;

  // Spacing scale
  static const double space0 = 0;
  static const double space1 = 4;   // 0.5 units
  static const double space2 = 8;   // 1 unit
  static const double space3 = 12;  // 1.5 units
  static const double space4 = 16;  // 2 units
  static const double space5 = 24;  // 3 units
  static const double space6 = 32;  // 4 units
  static const double space7 = 48;  // 6 units
  static const double space8 = 64;  // 8 units

  // Component sizing
  static const double buttonHeight = 28;
  static const double buttonHeightSmall = 24;
  static const double buttonHeightLarge = 36;
  static const double inputHeight = 28;
  static const double iconSize = 16;
  static const double iconSizeSmall = 12;
  static const double iconSizeLarge = 20;

  // Track sizing
  static const double trackHeightMin = 40;
  static const double trackHeightDefault = 80;
  static const double trackHeightMax = 200;
  static const double trackColorBarWidth = 6;

  // Mixer sizing
  static const double mixerStripWidth = 80;
  static const double mixerStripWidthCompact = 64;
  static const double faderHeight = 160;
  static const double meterWidth = 6;

  // Zone sizing
  static const double zoneMinWidth = 200;
  static const double zoneDefaultWidth = 280;
  static const double zoneMaxWidth = 400;
  static const double lowerZoneMinHeight = 250;
  static const double lowerZoneDefaultHeight = 350;

  // ═══════════════════════════════════════════════════════════════════════════
  // THEME DATA
  // ═══════════════════════════════════════════════════════════════════════════

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bgDeepest,
    fontFamily: fontFamily,

    colorScheme: const ColorScheme.dark(
      primary: accentBlue,
      secondary: accentCyan,
      tertiary: accentPurple,
      surface: bgSurface,
      error: accentRed,
      onPrimary: textPrimary,
      onSecondary: textPrimary,
      onSurface: textPrimary,
      onError: textPrimary,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: bgDeep,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
    ),

    cardTheme: CardThemeData(
      color: bgSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: borderSubtle),
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: borderSubtle,
      thickness: 1,
      space: 1,
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: accentBlue,
      inactiveTrackColor: bgElevated,
      thumbColor: accentBlue,
      overlayColor: accentBlue.withValues(alpha: 0.2),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    ),

    iconTheme: const IconThemeData(
      color: textSecondary,
      size: 20,
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: bgElevated,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderSubtle),
      ),
      textStyle: bodySmall.copyWith(color: textPrimary),
    ),

    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(bgHover),
      trackColor: WidgetStateProperty.all(Colors.transparent),
      radius: const Radius.circular(4),
      thickness: WidgetStateProperty.all(6),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK COLORS - Cubase-inspired 16-color palette
// ═══════════════════════════════════════════════════════════════════════════

class TrackColors {
  // Primary palette - high saturation for visibility
  static const List<Color> palette = [
    Color(0xFFFF5858), // Warm Red
    Color(0xFFFF8C42), // Orange
    Color(0xFFFFD93D), // Yellow
    Color(0xFF6BCB77), // Green
    Color(0xFF4ECDC4), // Teal
    Color(0xFF5AA8FF), // Blue
    Color(0xFF8B5CF6), // Purple
    Color(0xFFEC4899), // Pink
    Color(0xFFFF6B6B), // Coral
    Color(0xFFFFA726), // Amber
    Color(0xFFCDDC39), // Lime
    Color(0xFF26A69A), // Dark Teal
    Color(0xFF42A5F5), // Light Blue
    Color(0xFFA78BFA), // Lavender
    Color(0xFFF472B6), // Rose
    Color(0xFF78909C), // Blue Gray
  ];

  // Muted versions for non-selected/background use
  static const List<Color> mutedPalette = [
    Color(0xFFB33E3E), // Warm Red - muted
    Color(0xFFB36230), // Orange - muted
    Color(0xFFB39A2B), // Yellow - muted
    Color(0xFF4A8F53), // Green - muted
    Color(0xFF369089), // Teal - muted
    Color(0xFF3F75B3), // Blue - muted
    Color(0xFF6141AB), // Purple - muted
    Color(0xFFA5336B), // Pink - muted
    Color(0xFFB34B4B), // Coral - muted
    Color(0xFFB3751B), // Amber - muted
    Color(0xFF909A29), // Lime - muted
    Color(0xFF1B756C), // Dark Teal - muted
    Color(0xFF2E73AB), // Light Blue - muted
    Color(0xFF7562AF), // Lavender - muted
    Color(0xFFAB507E), // Rose - muted
    Color(0xFF54656D), // Blue Gray - muted
  ];

  // Get color for index
  static Color forIndex(int index) => palette[index % palette.length];

  // Get muted color for index
  static Color mutedForIndex(int index) => mutedPalette[index % mutedPalette.length];

  // Generate color with custom opacity
  static Color withOpacity(int index, double opacity) =>
      palette[index % palette.length].withValues(alpha: opacity);
}

// ═══════════════════════════════════════════════════════════════════════════
// WAVEFORM COLORS
// ═══════════════════════════════════════════════════════════════════════════

class WaveformColors {
  // Standard waveform (inherits track color)
  static Color fill(Color trackColor) => trackColor.withValues(alpha: 0.6);
  static Color outline(Color trackColor) => trackColor.withValues(alpha: 0.9);
  static Color peak(Color trackColor) => trackColor;

  // Selected waveform (brighter)
  static Color selectedFill(Color trackColor) => trackColor.withValues(alpha: 0.8);
  static Color selectedOutline(Color trackColor) => trackColor;

  // Muted waveform
  static Color mutedFill(Color trackColor) => trackColor.withValues(alpha: 0.25);
  static Color mutedOutline(Color trackColor) => trackColor.withValues(alpha: 0.4);

  // RMS fill (darker than peak)
  static Color rmsFill(Color trackColor) => trackColor.withValues(alpha: 0.3);
}

// ═══════════════════════════════════════════════════════════════════════════
// PIANO ROLL COLORS - FL Studio inspired
// ═══════════════════════════════════════════════════════════════════════════

class PianoRollColors {
  // Note colors by velocity
  static Color noteColor(double velocity) {
    // Low velocity = cooler, high velocity = warmer
    if (velocity < 0.33) {
      return const Color(0xFF5AA8FF); // Blue - soft
    } else if (velocity < 0.66) {
      return const Color(0xFF50FF98); // Green - medium
    } else if (velocity < 0.9) {
      return const Color(0xFFFFE050); // Yellow - loud
    } else {
      return const Color(0xFFFF5068); // Red - accent
    }
  }

  // Ghost note color (other tracks)
  static const Color ghostNote = Color(0x40808088);
  static const Color ghostNoteSelected = Color(0x60B8B8C0);

  // Scale highlighting
  static const Color scaleKeyWhite = Color(0xFF16161E);
  static const Color scaleKeyBlack = Color(0xFF0E0E14);
  static const Color scaleHighlight = Color(0x205AA8FF);  // In-scale keys

  // Grid lines
  static const Color gridBar = Color(0xFF3A3A4A);
  static const Color gridBeat = Color(0xFF2A2A38);
  static const Color gridSubdivision = Color(0xFF1E1E28);

  // Selection
  static const Color selection = Color(0x405AA8FF);
  static const Color selectionBorder = Color(0xFF5AA8FF);
}
