/// ReelForge Pro Audio Theme
///
/// Professional dark theme inspired by Cubase, Pro Tools, and Ableton
/// with modern glassmorphism and subtle gradients.

import 'package:flutter/material.dart';

class ReelForgeTheme {
  // ═══════════════════════════════════════════════════════════════════════════
  // COLOR PALETTE - Pro Audio Dark
  // ═══════════════════════════════════════════════════════════════════════════

  // Backgrounds (depth layers)
  static const Color bgDeepest = Color(0xFF0A0A0C);
  static const Color bgDeep = Color(0xFF121216);
  static const Color bgMid = Color(0xFF1A1A20);
  static const Color bgSurface = Color(0xFF242430);
  static const Color bgElevated = Color(0xFF2A2A38);
  static const Color bgHover = Color(0xFF32323F);

  // Accents
  static const Color accentBlue = Color(0xFF4A9EFF);
  static const Color accentOrange = Color(0xFFFF9040);
  static const Color accentGreen = Color(0xFF40FF90);
  static const Color accentRed = Color(0xFFFF4060);
  static const Color accentCyan = Color(0xFF40C8FF);
  static const Color accentPurple = Color(0xFF9B6DFF);
  static const Color accentYellow = Color(0xFFFFD940);

  // Semantic colors (aliases for common use cases)
  static const Color errorRed = accentRed;
  static const Color warningOrange = accentOrange;
  static const Color successGreen = accentGreen;

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0B8);
  static const Color textTertiary = Color(0xFF707078);
  static const Color textDisabled = Color(0xFF505058);

  // Borders
  static const Color borderSubtle = Color(0xFF2A2A35);
  static const Color borderMedium = Color(0xFF3A3A48);
  static const Color borderFocus = Color(0xFF4A9EFF);

  // Metering gradient colors
  static const List<Color> meterGradient = [
    Color(0xFF40C8FF), // Cyan - low
    Color(0xFF40FF90), // Green
    Color(0xFFFFFF40), // Yellow
    Color(0xFFFF9040), // Orange
    Color(0xFFFF4040), // Red - clip
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // GRADIENTS
  // ═══════════════════════════════════════════════════════════════════════════

  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgSurface, bgMid],
  );

  static const LinearGradient glowGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x204A9EFF),
      Color(0x004A9EFF),
    ],
  );

  static LinearGradient meterGradientVertical = const LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: meterGradient,
    stops: [0.0, 0.5, 0.7, 0.85, 1.0],
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // SHADOWS & GLOW
  // ═══════════════════════════════════════════════════════════════════════════

  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.4),
      blurRadius: 8,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.2),
      blurRadius: 16,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> glowShadow(Color color, {double intensity = 0.4}) => [
    BoxShadow(
      color: color.withValues(alpha: intensity),
      blurRadius: 12,
      spreadRadius: -2,
    ),
  ];

  static List<BoxShadow> get subtleShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.3),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // DECORATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  static BoxDecoration get panelDecoration => BoxDecoration(
    color: bgMid,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: borderSubtle, width: 1),
    boxShadow: subtleShadow,
  );

  static BoxDecoration get cardDecoration => BoxDecoration(
    color: bgSurface,
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: borderSubtle, width: 1),
  );

  static BoxDecoration get glassDecoration => BoxDecoration(
    color: bgSurface.withValues(alpha: 0.8),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(
      color: Colors.white.withValues(alpha: 0.1),
      width: 1,
    ),
    boxShadow: elevatedShadow,
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // TYPOGRAPHY
  // ═══════════════════════════════════════════════════════════════════════════

  static const String fontFamily = 'Inter';
  static const String monoFontFamily = 'JetBrains Mono';

  static TextStyle get h1 => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: -0.5,
  );

  static TextStyle get h2 => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: -0.3,
  );

  static TextStyle get h3 => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static TextStyle get body => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  static TextStyle get bodySmall => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: textTertiary,
  );

  static TextStyle get label => const TextStyle(
    fontFamily: fontFamily,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: textTertiary,
    letterSpacing: 0.5,
  );

  static TextStyle get mono => const TextStyle(
    fontFamily: monoFontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  static TextStyle get monoSmall => const TextStyle(
    fontFamily: monoFontFamily,
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // ANIMATION CURVES
  // ═══════════════════════════════════════════════════════════════════════════

  static const Curve smoothCurve = Curves.easeOutCubic;
  static const Curve bounceCurve = Curves.elasticOut;
  static const Curve snappyCurve = Curves.easeOutExpo;

  static const Duration fastDuration = Duration(milliseconds: 150);
  static const Duration normalDuration = Duration(milliseconds: 250);
  static const Duration slowDuration = Duration(milliseconds: 400);

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
// TRACK COLORS
// ═══════════════════════════════════════════════════════════════════════════

class TrackColors {
  static const List<Color> palette = [
    Color(0xFFE74C3C), // Red
    Color(0xFF9B59B6), // Purple
    Color(0xFF3498DB), // Blue
    Color(0xFF2ECC71), // Green
    Color(0xFFF39C12), // Orange
    Color(0xFF1ABC9C), // Teal
    Color(0xFFE67E22), // Dark Orange
    Color(0xFFC0392B), // Dark Red
    Color(0xFF8E44AD), // Dark Purple
    Color(0xFF27AE60), // Dark Green
  ];

  static Color forIndex(int index) => palette[index % palette.length];
}
