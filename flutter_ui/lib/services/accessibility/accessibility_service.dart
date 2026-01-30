/// Accessibility Service
///
/// Core accessibility features for SlotLab:
/// - High contrast mode support
/// - Screen reader announcements
/// - Focus indication enhancement
/// - Color blindness simulation
/// - Text scaling support
///
/// Created: 2026-01-30 (P4.20)

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show HSLColor;
import 'package:flutter/semantics.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ACCESSIBILITY SETTINGS
// ═══════════════════════════════════════════════════════════════════════════

/// High contrast mode options
enum HighContrastMode {
  /// Normal colors (default)
  off,

  /// Increased contrast for better visibility
  increased,

  /// Maximum contrast (black/white emphasis)
  maximum,
}

extension HighContrastModeExtension on HighContrastMode {
  String get displayName {
    switch (this) {
      case HighContrastMode.off:
        return 'Normal';
      case HighContrastMode.increased:
        return 'Increased';
      case HighContrastMode.maximum:
        return 'Maximum';
    }
  }

  String get description {
    switch (this) {
      case HighContrastMode.off:
        return 'Standard color scheme';
      case HighContrastMode.increased:
        return 'Enhanced contrast for better visibility';
      case HighContrastMode.maximum:
        return 'Black and white emphasis';
    }
  }

  /// Contrast multiplier for UI elements
  double get contrastMultiplier {
    switch (this) {
      case HighContrastMode.off:
        return 1.0;
      case HighContrastMode.increased:
        return 1.3;
      case HighContrastMode.maximum:
        return 1.6;
    }
  }
}

/// Color blindness simulation modes
enum ColorBlindnessMode {
  /// Normal vision
  none,

  /// Red-green (most common)
  protanopia,

  /// Green-red
  deuteranopia,

  /// Blue-yellow
  tritanopia,

  /// Complete color blindness
  achromatopsia,
}

extension ColorBlindnessModeExtension on ColorBlindnessMode {
  String get displayName {
    switch (this) {
      case ColorBlindnessMode.none:
        return 'None';
      case ColorBlindnessMode.protanopia:
        return 'Protanopia (Red-Green)';
      case ColorBlindnessMode.deuteranopia:
        return 'Deuteranopia (Green-Red)';
      case ColorBlindnessMode.tritanopia:
        return 'Tritanopia (Blue-Yellow)';
      case ColorBlindnessMode.achromatopsia:
        return 'Achromatopsia (Grayscale)';
    }
  }

  String get description {
    switch (this) {
      case ColorBlindnessMode.none:
        return 'Normal color vision';
      case ColorBlindnessMode.protanopia:
        return 'Difficulty distinguishing red and green';
      case ColorBlindnessMode.deuteranopia:
        return 'Difficulty distinguishing green and red';
      case ColorBlindnessMode.tritanopia:
        return 'Difficulty distinguishing blue and yellow';
      case ColorBlindnessMode.achromatopsia:
        return 'Complete color blindness (rare)';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ACCESSIBILITY SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for managing accessibility features
class AccessibilityService extends ChangeNotifier {
  AccessibilityService._();
  static final instance = AccessibilityService._();

  static const _prefsKeyHighContrast = 'accessibility_high_contrast';
  static const _prefsKeyColorBlindness = 'accessibility_color_blindness';
  static const _prefsKeyScreenReaderEnabled = 'accessibility_screen_reader';
  static const _prefsKeyFocusHighlight = 'accessibility_focus_highlight';
  static const _prefsKeyTextScale = 'accessibility_text_scale';
  static const _prefsKeyLargePointer = 'accessibility_large_pointer';

  // State
  HighContrastMode _highContrastMode = HighContrastMode.off;
  ColorBlindnessMode _colorBlindnessMode = ColorBlindnessMode.none;
  bool _screenReaderEnabled = false;
  bool _focusHighlightEnabled = true;
  double _textScale = 1.0;
  bool _largePointerEnabled = false;
  bool _initialized = false;

  // Getters
  HighContrastMode get highContrastMode => _highContrastMode;
  ColorBlindnessMode get colorBlindnessMode => _colorBlindnessMode;
  bool get screenReaderEnabled => _screenReaderEnabled;
  bool get focusHighlightEnabled => _focusHighlightEnabled;
  double get textScale => _textScale;
  bool get largePointerEnabled => _largePointerEnabled;
  bool get initialized => _initialized;

  // Convenience getters
  bool get isHighContrastEnabled => _highContrastMode != HighContrastMode.off;
  bool get isColorBlindnessSimulated =>
      _colorBlindnessMode != ColorBlindnessMode.none;
  double get contrastMultiplier => _highContrastMode.contrastMultiplier;

  /// Initialize the service
  Future<void> init() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      final highContrastIndex = prefs.getInt(_prefsKeyHighContrast);
      if (highContrastIndex != null &&
          highContrastIndex < HighContrastMode.values.length) {
        _highContrastMode = HighContrastMode.values[highContrastIndex];
      }

      final colorBlindnessIndex = prefs.getInt(_prefsKeyColorBlindness);
      if (colorBlindnessIndex != null &&
          colorBlindnessIndex < ColorBlindnessMode.values.length) {
        _colorBlindnessMode = ColorBlindnessMode.values[colorBlindnessIndex];
      }

      _screenReaderEnabled =
          prefs.getBool(_prefsKeyScreenReaderEnabled) ?? false;
      _focusHighlightEnabled =
          prefs.getBool(_prefsKeyFocusHighlight) ?? true;
      _textScale = prefs.getDouble(_prefsKeyTextScale) ?? 1.0;
      _largePointerEnabled = prefs.getBool(_prefsKeyLargePointer) ?? false;

      _initialized = true;
      notifyListeners();
      debugPrint('[AccessibilityService] Initialized');
    } catch (e) {
      debugPrint('[AccessibilityService] Init error: $e');
      _initialized = true;
    }
  }

  /// Save preferences
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKeyHighContrast, _highContrastMode.index);
      await prefs.setInt(_prefsKeyColorBlindness, _colorBlindnessMode.index);
      await prefs.setBool(_prefsKeyScreenReaderEnabled, _screenReaderEnabled);
      await prefs.setBool(_prefsKeyFocusHighlight, _focusHighlightEnabled);
      await prefs.setDouble(_prefsKeyTextScale, _textScale);
      await prefs.setBool(_prefsKeyLargePointer, _largePointerEnabled);
    } catch (e) {
      debugPrint('[AccessibilityService] Save error: $e');
    }
  }

  /// Set high contrast mode
  Future<void> setHighContrastMode(HighContrastMode mode) async {
    if (_highContrastMode == mode) return;
    _highContrastMode = mode;
    await _save();
    notifyListeners();
    debugPrint('[AccessibilityService] High contrast: $mode');
  }

  /// Set color blindness simulation mode
  Future<void> setColorBlindnessMode(ColorBlindnessMode mode) async {
    if (_colorBlindnessMode == mode) return;
    _colorBlindnessMode = mode;
    await _save();
    notifyListeners();
    debugPrint('[AccessibilityService] Color blindness mode: $mode');
  }

  /// Enable/disable screen reader support
  Future<void> setScreenReaderEnabled(bool enabled) async {
    if (_screenReaderEnabled == enabled) return;
    _screenReaderEnabled = enabled;
    await _save();
    notifyListeners();
    debugPrint('[AccessibilityService] Screen reader: $enabled');
  }

  /// Enable/disable enhanced focus highlight
  Future<void> setFocusHighlightEnabled(bool enabled) async {
    if (_focusHighlightEnabled == enabled) return;
    _focusHighlightEnabled = enabled;
    await _save();
    notifyListeners();
    debugPrint('[AccessibilityService] Focus highlight: $enabled');
  }

  /// Set text scale factor (0.8 - 2.0)
  Future<void> setTextScale(double scale) async {
    final clamped = scale.clamp(0.8, 2.0);
    if (_textScale == clamped) return;
    _textScale = clamped;
    await _save();
    notifyListeners();
    debugPrint('[AccessibilityService] Text scale: $clamped');
  }

  /// Enable/disable large pointer
  Future<void> setLargePointerEnabled(bool enabled) async {
    if (_largePointerEnabled == enabled) return;
    _largePointerEnabled = enabled;
    await _save();
    notifyListeners();
    debugPrint('[AccessibilityService] Large pointer: $enabled');
  }

  /// Announce message for screen readers
  void announce(String message, {bool assertive = false}) {
    if (!_screenReaderEnabled) return;

    SemanticsService.announce(
      message,
      TextDirection.ltr,
      assertiveness:
          assertive ? Assertiveness.assertive : Assertiveness.polite,
    );
    debugPrint('[AccessibilityService] Announced: $message');
  }

  /// Apply color blindness simulation to a color
  Color simulateColorBlindness(Color color) {
    if (_colorBlindnessMode == ColorBlindnessMode.none) return color;

    final r = color.red / 255.0;
    final g = color.green / 255.0;
    final b = color.blue / 255.0;

    double newR, newG, newB;

    switch (_colorBlindnessMode) {
      case ColorBlindnessMode.none:
        return color;

      case ColorBlindnessMode.protanopia:
        // Protanopia (no red cones)
        newR = 0.567 * r + 0.433 * g + 0.0 * b;
        newG = 0.558 * r + 0.442 * g + 0.0 * b;
        newB = 0.0 * r + 0.242 * g + 0.758 * b;
        break;

      case ColorBlindnessMode.deuteranopia:
        // Deuteranopia (no green cones)
        newR = 0.625 * r + 0.375 * g + 0.0 * b;
        newG = 0.700 * r + 0.300 * g + 0.0 * b;
        newB = 0.0 * r + 0.300 * g + 0.700 * b;
        break;

      case ColorBlindnessMode.tritanopia:
        // Tritanopia (no blue cones)
        newR = 0.950 * r + 0.050 * g + 0.0 * b;
        newG = 0.0 * r + 0.433 * g + 0.567 * b;
        newB = 0.0 * r + 0.475 * g + 0.525 * b;
        break;

      case ColorBlindnessMode.achromatopsia:
        // Complete color blindness (grayscale)
        final gray = 0.299 * r + 0.587 * g + 0.114 * b;
        newR = gray;
        newG = gray;
        newB = gray;
        break;
    }

    return Color.fromARGB(
      color.alpha,
      (newR.clamp(0.0, 1.0) * 255).round(),
      (newG.clamp(0.0, 1.0) * 255).round(),
      (newB.clamp(0.0, 1.0) * 255).round(),
    );
  }

  /// Apply high contrast adjustment to a color
  Color applyHighContrast(Color color, {bool isBackground = false}) {
    if (_highContrastMode == HighContrastMode.off) return color;

    // Calculate luminance
    final luminance = color.computeLuminance();

    if (_highContrastMode == HighContrastMode.maximum) {
      // Maximum contrast: push to black or white
      if (isBackground) {
        return luminance > 0.5 ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
      } else {
        return luminance > 0.5 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
      }
    }

    // Increased contrast: enhance saturation and brightness difference
    final hsl = HSLColor.fromColor(color);
    final newLightness = luminance > 0.5
        ? (hsl.lightness + 0.15).clamp(0.0, 1.0)
        : (hsl.lightness - 0.15).clamp(0.0, 1.0);
    final newSaturation = (hsl.saturation * 1.2).clamp(0.0, 1.0);

    return hsl
        .withLightness(newLightness)
        .withSaturation(newSaturation)
        .toColor();
  }

  /// Get focus indicator color based on settings
  Color getFocusIndicatorColor() {
    if (!_focusHighlightEnabled) {
      return const Color(0x00000000); // Transparent
    }

    if (_highContrastMode == HighContrastMode.maximum) {
      return const Color(0xFFFFFF00); // Bright yellow
    }

    return const Color(0xFF4A9EFF); // Default blue
  }

  /// Get focus indicator width based on settings
  double getFocusIndicatorWidth() {
    if (!_focusHighlightEnabled) return 0.0;
    if (_highContrastMode == HighContrastMode.maximum) return 3.0;
    if (_highContrastMode == HighContrastMode.increased) return 2.5;
    return 2.0;
  }
}
