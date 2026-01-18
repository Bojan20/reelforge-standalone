/// Liquid Glass Theme
///
/// macOS Tahoe-inspired glassmorphism design system for FluxForge Studio.
/// Provides colors, gradients, shadows, and styling constants for glass UI.

import 'dart:ui';
import 'package:flutter/material.dart';

/// Liquid Glass design tokens and utilities
class LiquidGlassTheme {
  LiquidGlassTheme._();

  // ============================================================================
  // BLUR SETTINGS
  // ============================================================================

  /// Standard blur amount for glass panels
  static const double blurAmount = 24.0;

  /// Light blur for overlays
  static const double blurLight = 12.0;

  /// Heavy blur for modals
  static const double blurHeavy = 40.0;

  // ============================================================================
  // BASE COLORS
  // ============================================================================

  /// Deep background gradient colors
  static const Color bgGradientStart = Color(0xFF1a1a2e);
  static const Color bgGradientMid = Color(0xFF16213e);
  static const Color bgGradientEnd = Color(0xFF0f0f23);

  /// Glass tint colors
  static const Color glassTintLight = Color(0x14FFFFFF); // 8%
  static const Color glassTintMedium = Color(0x1FFFFFFF); // 12%
  static const Color glassTintStrong = Color(0x29FFFFFF); // 16%

  /// Border colors
  static const Color borderLight = Color(0x26FFFFFF); // 15%
  static const Color borderMedium = Color(0x33FFFFFF); // 20%
  static const Color borderStrong = Color(0x4DFFFFFF); // 30%

  /// Specular highlight
  static const Color specularHighlight = Color(0x4DFFFFFF); // 30%

  // ============================================================================
  // ACCENT COLORS (Same as FluxForge but with glow variants)
  // ============================================================================

  static const Color accentBlue = Color(0xFF4a9eff);
  static const Color accentOrange = Color(0xFFff9040);
  static const Color accentGreen = Color(0xFF40ff90);
  static const Color accentRed = Color(0xFFff4060);
  static const Color accentCyan = Color(0xFF40c8ff);
  static const Color accentPurple = Color(0xFFaa40ff);
  static const Color accentYellow = Color(0xFFffdd40);
  static const Color accentPink = Color(0xFFff40aa);

  /// Get glow color for accent (40% opacity)
  static Color glowFor(Color accent) => accent.withValues(alpha: 0.4);

  /// Get subtle glow (20% opacity)
  static Color subtleGlowFor(Color accent) => accent.withValues(alpha: 0.2);

  // ============================================================================
  // TEXT COLORS
  // ============================================================================

  static const Color textPrimary = Color(0xE6FFFFFF); // 90%
  static const Color textSecondary = Color(0x99FFFFFF); // 60%
  static const Color textTertiary = Color(0x66FFFFFF); // 40%
  static const Color textDisabled = Color(0x33FFFFFF); // 20%

  // ============================================================================
  // SHADOW DEFINITIONS
  // ============================================================================

  /// Standard glass panel shadow
  static List<BoxShadow> get glassShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        // Top light edge
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.05),
          blurRadius: 1,
          offset: const Offset(0, -1),
        ),
      ];

  /// Elevated glass shadow (for modals, dropdowns)
  static List<BoxShadow> get glassElevatedShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.4),
          blurRadius: 32,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.08),
          blurRadius: 1,
          offset: const Offset(0, -1),
        ),
      ];

  /// Subtle shadow for inner elements
  static List<BoxShadow> get glassInnerShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ];

  /// Active/focused element glow
  static List<BoxShadow> activeGlow(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.4),
          blurRadius: 12,
          spreadRadius: 0,
        ),
      ];

  // ============================================================================
  // GRADIENT DEFINITIONS
  // ============================================================================

  /// Background gradient for entire app
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [bgGradientStart, bgGradientMid, bgGradientEnd, bgGradientStart],
    stops: [0.0, 0.3, 0.7, 1.0],
  );

  /// Glass fill gradient (top-left to bottom-right)
  static LinearGradient glassFillGradient({double opacity = 0.08}) =>
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: opacity + 0.04),
          Colors.white.withValues(alpha: opacity),
          Colors.white.withValues(alpha: opacity - 0.02),
        ],
      );

  /// Meter gradient (vertical)
  static const LinearGradient meterGradient = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      Color(0xFF40c8ff), // Cyan
      Color(0xFF40ff90), // Green
      Color(0xFFffff40), // Yellow
      Color(0xFFff9040), // Orange
      Color(0xFFff4040), // Red
    ],
    stops: [0.0, 0.5, 0.7, 0.85, 1.0],
  );

  // ============================================================================
  // BORDER DECORATIONS
  // ============================================================================

  /// Standard glass border
  static Border get glassBorder => Border.all(
        color: borderLight,
        width: 1,
      );

  /// Focused/active glass border
  static Border glassBorderActive(Color accent) => Border.all(
        color: accent.withValues(alpha: 0.5),
        width: 1,
      );

  // ============================================================================
  // BORDER RADIUS
  // ============================================================================

  static const double radiusSmall = 6.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 20.0;

  static BorderRadius get borderRadiusSmall =>
      BorderRadius.circular(radiusSmall);
  static BorderRadius get borderRadiusMedium =>
      BorderRadius.circular(radiusMedium);
  static BorderRadius get borderRadiusLarge =>
      BorderRadius.circular(radiusLarge);

  // ============================================================================
  // ANIMATION DURATIONS
  // ============================================================================

  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 250);
  static const Duration animSlow = Duration(milliseconds: 400);

  // ============================================================================
  // INPUT STYLING
  // ============================================================================

  /// Glass-styled input decoration
  static InputDecoration glassInputDecoration({
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) =>
      InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: textTertiary, fontSize: 13),
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.25),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: borderRadiusSmall,
          borderSide: BorderSide(color: borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadiusSmall,
          borderSide: BorderSide(color: borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadiusSmall,
          borderSide: BorderSide(color: accentBlue.withValues(alpha: 0.5)),
        ),
      );

  // ============================================================================
  // BUTTON STYLING
  // ============================================================================

  /// Glass button style
  static ButtonStyle glassButtonStyle({
    Color? color,
    bool isActive = false,
  }) {
    final effectiveColor = color ?? accentBlue;
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (isActive) return effectiveColor.withValues(alpha: 0.3);
        if (states.contains(WidgetState.hovered)) {
          return Colors.white.withValues(alpha: 0.12);
        }
        return Colors.white.withValues(alpha: 0.08);
      }),
      foregroundColor: WidgetStateProperty.all(
        isActive ? effectiveColor : textPrimary,
      ),
      overlayColor: WidgetStateProperty.all(
        Colors.white.withValues(alpha: 0.1),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: borderRadiusSmall,
          side: BorderSide(
            color: isActive
                ? effectiveColor.withValues(alpha: 0.5)
                : borderLight,
          ),
        ),
      ),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }

  // ============================================================================
  // SLIDER/FADER THEME
  // ============================================================================

  static SliderThemeData glassSliderTheme({Color? activeColor}) {
    final color = activeColor ?? accentBlue;
    return SliderThemeData(
      activeTrackColor: color,
      inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
      thumbColor: color,
      overlayColor: color.withValues(alpha: 0.2),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    );
  }
}

// ==============================================================================
// GLASS FILTER WIDGET
// ==============================================================================

/// Applies blur filter to content behind
class GlassBlur extends StatelessWidget {
  final Widget child;
  final double blur;

  const GlassBlur({
    super.key,
    required this.child,
    this.blur = LiquidGlassTheme.blurAmount,
  });

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: child,
    );
  }
}
