/// Theme Mode Provider — P3.2 Custom Themes
///
/// Manages switching between theme modes:
/// - Dark (default pro-audio theme)
/// - Light (for bright environments)
/// - High Contrast (accessibility)
/// - Liquid Glass (premium visual style)
///
/// Includes persistence via SharedPreferences.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// THEME MODE ENUM
// ═══════════════════════════════════════════════════════════════════════════════

enum AppThemeMode {
  dark('Dark', 'Pro-audio dark theme'),
  light('Light', 'Light theme for bright environments'),
  highContrast('High Contrast', 'Enhanced visibility for accessibility'),
  liquidGlass('Liquid Glass', 'Premium glass morphism style');

  final String label;
  final String description;
  const AppThemeMode(this.label, this.description);

  // Legacy alias
  static AppThemeMode get classic => AppThemeMode.dark;
}

// ═══════════════════════════════════════════════════════════════════════════════
// THEME MODE PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

class ThemeModeProvider extends ChangeNotifier {
  static const String _prefsKey = 'app_theme_mode';

  AppThemeMode _mode = AppThemeMode.dark;
  bool _isInitialized = false;

  AppThemeMode get mode => _mode;

  // Convenience getters
  bool get isDarkMode => _mode == AppThemeMode.dark;
  bool get isLightMode => _mode == AppThemeMode.light;
  bool get isHighContrastMode => _mode == AppThemeMode.highContrast;
  bool get isGlassMode => _mode == AppThemeMode.liquidGlass;

  // Legacy aliases
  bool get isClassicMode => _mode == AppThemeMode.dark;

  /// Initialize and load persisted theme
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_prefsKey);
      if (savedMode != null) {
        // Handle legacy 'classic' value
        final modeName = savedMode == 'classic' ? 'dark' : savedMode;
        _mode = AppThemeMode.values.firstWhere(
          (m) => m.name == modeName,
          orElse: () => AppThemeMode.dark,
        );
      }
    } catch (e) {
      // Use default on error
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Set theme mode and persist
  Future<void> setMode(AppThemeMode mode) async {
    if (_mode == mode) return;

    _mode = mode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (e) {
      // Ignore persistence errors
    }
  }

  /// Toggle between Dark and Light modes
  void toggleDarkLight() {
    if (_mode == AppThemeMode.light) {
      setMode(AppThemeMode.dark);
    } else {
      setMode(AppThemeMode.light);
    }
  }

  /// Cycle through all modes
  void cycleMode() {
    final currentIndex = AppThemeMode.values.indexOf(_mode);
    final nextIndex = (currentIndex + 1) % AppThemeMode.values.length;
    setMode(AppThemeMode.values[nextIndex]);
  }

  // Legacy methods for compatibility
  void setGlassMode() => setMode(AppThemeMode.liquidGlass);
  void setClassicMode() => setMode(AppThemeMode.dark);

  void toggleMode() {
    if (_mode == AppThemeMode.liquidGlass) {
      setMode(AppThemeMode.dark);
    } else {
      setMode(AppThemeMode.liquidGlass);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LIGHT THEME COLORS
// ═══════════════════════════════════════════════════════════════════════════════

class LightThemeColors {
  // Backgrounds (light to dark)
  static const Color bgDeepest = Color(0xFFFFFFFF);
  static const Color bgDeep = Color(0xFFF8F8FA);
  static const Color bgMid = Color(0xFFF0F0F4);
  static const Color bgSurface = Color(0xFFE8E8EE);
  static const Color bgElevated = Color(0xFFE0E0E8);
  static const Color bgHover = Color(0xFFD8D8E0);

  // Text colors (dark on light)
  static const Color textPrimary = Color(0xFF1A1A24);
  static const Color textSecondary = Color(0xFF404050);
  static const Color textTertiary = Color(0xFF606070);
  static const Color textDisabled = Color(0xFF909098);

  // Accents (slightly darker for light background)
  static const Color accentBlue = Color(0xFF2D7DD2);
  static const Color accentCyan = Color(0xFF00A5B5);
  static const Color accentOrange = Color(0xFFE07020);
  static const Color accentGreen = Color(0xFF20A060);
  static const Color accentRed = Color(0xFFD03050);
  static const Color accentPurple = Color(0xFF7040B0);
  static const Color accentYellow = Color(0xFFD0A000);

  // Borders
  static const Color borderSubtle = Color(0xFFD0D0D8);
  static const Color borderMedium = Color(0xFFB8B8C0);
  static const Color borderFocus = accentBlue;

  // Section accents
  static const Color dawAccent = Color(0xFF2D7DD2);
  static const Color middlewareAccent = Color(0xFFE07020);
  static const Color slotLabAccent = Color(0xFF00A5B5);

  // Semantic
  static const Color success = Color(0xFF20A060);
  static const Color warning = Color(0xFFD0A000);
  static const Color error = Color(0xFFD03050);
}

// ═══════════════════════════════════════════════════════════════════════════════
// HIGH CONTRAST THEME COLORS
// ═══════════════════════════════════════════════════════════════════════════════

class HighContrastColors {
  // Backgrounds (pure black to gray)
  static const Color bgDeepest = Color(0xFF000000);
  static const Color bgDeep = Color(0xFF0A0A0A);
  static const Color bgMid = Color(0xFF141414);
  static const Color bgSurface = Color(0xFF1E1E1E);
  static const Color bgElevated = Color(0xFF282828);
  static const Color bgHover = Color(0xFF323232);

  // Text colors (pure white, high contrast)
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFE0E0E0);
  static const Color textTertiary = Color(0xFFC0C0C0);
  static const Color textDisabled = Color(0xFF808080);

  // Accents (maximum saturation for visibility)
  static const Color accentBlue = Color(0xFF00AAFF);
  static const Color accentCyan = Color(0xFF00FFFF);
  static const Color accentOrange = Color(0xFFFF8000);
  static const Color accentGreen = Color(0xFF00FF80);
  static const Color accentRed = Color(0xFFFF0040);
  static const Color accentPurple = Color(0xFFAA00FF);
  static const Color accentYellow = Color(0xFFFFFF00);

  // Borders (higher visibility)
  static const Color borderSubtle = Color(0xFF505050);
  static const Color borderMedium = Color(0xFF707070);
  static const Color borderFocus = accentBlue;

  // Section accents
  static const Color dawAccent = Color(0xFF00AAFF);
  static const Color middlewareAccent = Color(0xFFFF8000);
  static const Color slotLabAccent = Color(0xFF00FFFF);

  // Semantic (maximum visibility)
  static const Color success = Color(0xFF00FF80);
  static const Color warning = Color(0xFFFFFF00);
  static const Color error = Color(0xFFFF0040);
}

// ═══════════════════════════════════════════════════════════════════════════════
// THEME DATA GENERATORS
// ═══════════════════════════════════════════════════════════════════════════════

class AppThemes {
  /// Get ThemeData for the specified mode
  static ThemeData getTheme(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.dark:
        return _darkTheme;
      case AppThemeMode.light:
        return _lightTheme;
      case AppThemeMode.highContrast:
        return _highContrastTheme;
      case AppThemeMode.liquidGlass:
        return _darkTheme; // Glass uses dark base with overlays
    }
  }

  /// Dark theme (default)
  static ThemeData get _darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF08080C),
    fontFamily: 'Inter',

    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF5AA8FF),
      secondary: Color(0xFF50D8FF),
      tertiary: Color(0xFFB080FF),
      surface: Color(0xFF1E1E28),
      error: Color(0xFFFF5068),
      onPrimary: Color(0xFFF0F0F4),
      onSecondary: Color(0xFFF0F0F4),
      onSurface: Color(0xFFF0F0F4),
      onError: Color(0xFFF0F0F4),
    ),

    cardTheme: CardThemeData(
      color: const Color(0xFF1E1E28),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF2A2A38)),
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: Color(0xFF2A2A38),
      thickness: 1,
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: const Color(0xFF5AA8FF),
      inactiveTrackColor: const Color(0xFF26263A),
      thumbColor: const Color(0xFF5AA8FF),
      overlayColor: const Color(0xFF5AA8FF).withOpacity(0.2),
      trackHeight: 4,
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xFF26263A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF2A2A38)),
      ),
      textStyle: const TextStyle(
        color: Color(0xFFF0F0F4),
        fontSize: 11,
      ),
    ),
  );

  /// Light theme
  static ThemeData get _lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: LightThemeColors.bgDeepest,
    fontFamily: 'Inter',

    colorScheme: ColorScheme.light(
      primary: LightThemeColors.accentBlue,
      secondary: LightThemeColors.accentCyan,
      tertiary: LightThemeColors.accentPurple,
      surface: LightThemeColors.bgSurface,
      error: LightThemeColors.accentRed,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: LightThemeColors.textPrimary,
      onError: Colors.white,
    ),

    cardTheme: CardThemeData(
      color: LightThemeColors.bgDeep,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: LightThemeColors.borderSubtle),
      ),
    ),

    dividerTheme: DividerThemeData(
      color: LightThemeColors.borderSubtle,
      thickness: 1,
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: LightThemeColors.accentBlue,
      inactiveTrackColor: LightThemeColors.bgElevated,
      thumbColor: LightThemeColors.accentBlue,
      overlayColor: LightThemeColors.accentBlue.withOpacity(0.2),
      trackHeight: 4,
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: LightThemeColors.bgSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LightThemeColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      textStyle: TextStyle(
        color: LightThemeColors.textPrimary,
        fontSize: 11,
      ),
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: LightThemeColors.bgDeep,
      foregroundColor: LightThemeColors.textPrimary,
      elevation: 0,
    ),
  );

  /// High contrast theme
  static ThemeData get _highContrastTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: HighContrastColors.bgDeepest,
    fontFamily: 'Inter',

    colorScheme: ColorScheme.dark(
      primary: HighContrastColors.accentBlue,
      secondary: HighContrastColors.accentCyan,
      tertiary: HighContrastColors.accentPurple,
      surface: HighContrastColors.bgSurface,
      error: HighContrastColors.accentRed,
      onPrimary: HighContrastColors.textPrimary,
      onSecondary: HighContrastColors.textPrimary,
      onSurface: HighContrastColors.textPrimary,
      onError: HighContrastColors.textPrimary,
    ),

    cardTheme: CardThemeData(
      color: HighContrastColors.bgSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: HighContrastColors.borderMedium, width: 2),
      ),
    ),

    dividerTheme: DividerThemeData(
      color: HighContrastColors.borderMedium,
      thickness: 2,
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: HighContrastColors.accentBlue,
      inactiveTrackColor: HighContrastColors.bgElevated,
      thumbColor: HighContrastColors.accentBlue,
      overlayColor: HighContrastColors.accentBlue.withOpacity(0.3),
      trackHeight: 6,
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: HighContrastColors.bgSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: HighContrastColors.borderMedium, width: 2),
      ),
      textStyle: TextStyle(
        color: HighContrastColors.textPrimary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// THEME-AWARE COLOR HELPER
// ═══════════════════════════════════════════════════════════════════════════════

/// Helper to get colors based on current theme mode
class ThemeColors {
  final AppThemeMode mode;

  const ThemeColors(this.mode);

  // Backgrounds
  Color get bgDeepest => switch (mode) {
    AppThemeMode.light => LightThemeColors.bgDeepest,
    AppThemeMode.highContrast => HighContrastColors.bgDeepest,
    _ => const Color(0xFF08080C),
  };

  Color get bgDeep => switch (mode) {
    AppThemeMode.light => LightThemeColors.bgDeep,
    AppThemeMode.highContrast => HighContrastColors.bgDeep,
    _ => const Color(0xFF0E0E14),
  };

  Color get bgMid => switch (mode) {
    AppThemeMode.light => LightThemeColors.bgMid,
    AppThemeMode.highContrast => HighContrastColors.bgMid,
    _ => const Color(0xFF16161E),
  };

  Color get bgSurface => switch (mode) {
    AppThemeMode.light => LightThemeColors.bgSurface,
    AppThemeMode.highContrast => HighContrastColors.bgSurface,
    _ => const Color(0xFF1E1E28),
  };

  // Text
  Color get textPrimary => switch (mode) {
    AppThemeMode.light => LightThemeColors.textPrimary,
    AppThemeMode.highContrast => HighContrastColors.textPrimary,
    _ => const Color(0xFFF0F0F4),
  };

  Color get textSecondary => switch (mode) {
    AppThemeMode.light => LightThemeColors.textSecondary,
    AppThemeMode.highContrast => HighContrastColors.textSecondary,
    _ => const Color(0xFFB8B8C0),
  };

  Color get textMuted => switch (mode) {
    AppThemeMode.light => LightThemeColors.textTertiary,
    AppThemeMode.highContrast => HighContrastColors.textTertiary,
    _ => const Color(0xFF808088),
  };

  // Accents
  Color get accentBlue => switch (mode) {
    AppThemeMode.light => LightThemeColors.accentBlue,
    AppThemeMode.highContrast => HighContrastColors.accentBlue,
    _ => const Color(0xFF5AA8FF),
  };

  Color get accentGreen => switch (mode) {
    AppThemeMode.light => LightThemeColors.accentGreen,
    AppThemeMode.highContrast => HighContrastColors.accentGreen,
    _ => const Color(0xFF50FF98),
  };

  Color get accentOrange => switch (mode) {
    AppThemeMode.light => LightThemeColors.accentOrange,
    AppThemeMode.highContrast => HighContrastColors.accentOrange,
    _ => const Color(0xFFFF9850),
  };

  Color get accentRed => switch (mode) {
    AppThemeMode.light => LightThemeColors.accentRed,
    AppThemeMode.highContrast => HighContrastColors.accentRed,
    _ => const Color(0xFFFF5068),
  };

  // Borders
  Color get border => switch (mode) {
    AppThemeMode.light => LightThemeColors.borderSubtle,
    AppThemeMode.highContrast => HighContrastColors.borderSubtle,
    _ => const Color(0xFF2A2A38),
  };

  // Section accents
  Color get dawAccent => switch (mode) {
    AppThemeMode.light => LightThemeColors.dawAccent,
    AppThemeMode.highContrast => HighContrastColors.dawAccent,
    _ => const Color(0xFF4A9EFF),
  };

  Color get middlewareAccent => switch (mode) {
    AppThemeMode.light => LightThemeColors.middlewareAccent,
    AppThemeMode.highContrast => HighContrastColors.middlewareAccent,
    _ => const Color(0xFFFF9040),
  };

  Color get slotLabAccent => switch (mode) {
    AppThemeMode.light => LightThemeColors.slotLabAccent,
    AppThemeMode.highContrast => HighContrastColors.slotLabAccent,
    _ => const Color(0xFF40C8FF),
  };

  // Semantic
  Color get success => switch (mode) {
    AppThemeMode.light => LightThemeColors.success,
    AppThemeMode.highContrast => HighContrastColors.success,
    _ => const Color(0xFF50FF98),
  };

  Color get warning => switch (mode) {
    AppThemeMode.light => LightThemeColors.warning,
    AppThemeMode.highContrast => HighContrastColors.warning,
    _ => const Color(0xFFFF9850),
  };

  Color get error => switch (mode) {
    AppThemeMode.light => LightThemeColors.error,
    AppThemeMode.highContrast => HighContrastColors.error,
    _ => const Color(0xFFFF5068),
  };
}
