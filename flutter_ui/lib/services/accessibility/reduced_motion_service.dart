/// Reduced Motion Service
///
/// Accessibility service for users who prefer reduced motion:
/// - System preference detection (prefers-reduced-motion)
/// - Manual override toggle
/// - Animation duration scaling
/// - Particle effect reduction
/// - Smooth transition alternatives
///
/// Created: 2026-01-30 (P4.21)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// REDUCED MOTION SETTINGS
// ═══════════════════════════════════════════════════════════════════════════

/// Motion reduction level
enum MotionLevel {
  /// Full animations (default)
  full,

  /// Reduced animations (shorter durations, simpler curves)
  reduced,

  /// Minimal animations (instant transitions where possible)
  minimal,

  /// No animations (completely static)
  none,
}

extension MotionLevelExtension on MotionLevel {
  String get displayName {
    switch (this) {
      case MotionLevel.full:
        return 'Full Motion';
      case MotionLevel.reduced:
        return 'Reduced Motion';
      case MotionLevel.minimal:
        return 'Minimal Motion';
      case MotionLevel.none:
        return 'No Motion';
    }
  }

  String get description {
    switch (this) {
      case MotionLevel.full:
        return 'All animations and effects enabled';
      case MotionLevel.reduced:
        return 'Shorter animations, fewer particles';
      case MotionLevel.minimal:
        return 'Essential animations only';
      case MotionLevel.none:
        return 'No animations, instant transitions';
    }
  }

  /// Duration multiplier for animations
  double get durationMultiplier {
    switch (this) {
      case MotionLevel.full:
        return 1.0;
      case MotionLevel.reduced:
        return 0.5;
      case MotionLevel.minimal:
        return 0.2;
      case MotionLevel.none:
        return 0.0;
    }
  }

  /// Particle count multiplier
  double get particleMultiplier {
    switch (this) {
      case MotionLevel.full:
        return 1.0;
      case MotionLevel.reduced:
        return 0.3;
      case MotionLevel.minimal:
        return 0.1;
      case MotionLevel.none:
        return 0.0;
    }
  }

  /// Whether to use crossfades instead of complex animations
  bool get preferCrossfade {
    return this != MotionLevel.full;
  }

  /// Whether to show particles at all
  bool get showParticles {
    return this == MotionLevel.full || this == MotionLevel.reduced;
  }

  /// Whether reel animations should be simplified
  bool get simplifyReelAnimation {
    return this == MotionLevel.minimal || this == MotionLevel.none;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// REDUCED MOTION SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for managing reduced motion preferences
class ReducedMotionService extends ChangeNotifier {
  ReducedMotionService._();
  static final instance = ReducedMotionService._();

  static const _prefsKeyMotionLevel = 'accessibility_motion_level';
  static const _prefsKeyFollowSystem = 'accessibility_follow_system';

  // State
  MotionLevel _motionLevel = MotionLevel.full;
  bool _followSystemPreference = true;
  bool _systemPrefersReducedMotion = false;
  bool _initialized = false;

  // Getters
  MotionLevel get motionLevel => _effectiveMotionLevel;
  MotionLevel get userMotionLevel => _motionLevel;
  bool get followSystemPreference => _followSystemPreference;
  bool get systemPrefersReducedMotion => _systemPrefersReducedMotion;
  bool get initialized => _initialized;

  /// Effective motion level (considering system preference)
  MotionLevel get _effectiveMotionLevel {
    if (_followSystemPreference && _systemPrefersReducedMotion) {
      return MotionLevel.reduced;
    }
    return _motionLevel;
  }

  // Convenience getters
  double get durationMultiplier => _effectiveMotionLevel.durationMultiplier;
  double get particleMultiplier => _effectiveMotionLevel.particleMultiplier;
  bool get preferCrossfade => _effectiveMotionLevel.preferCrossfade;
  bool get showParticles => _effectiveMotionLevel.showParticles;
  bool get simplifyReelAnimation => _effectiveMotionLevel.simplifyReelAnimation;

  /// Initialize the service
  Future<void> init() async {
    if (_initialized) return;

    try {
      // Detect system preference
      _detectSystemPreference();

      // Load saved preferences
      final prefs = await SharedPreferences.getInstance();

      final levelIndex = prefs.getInt(_prefsKeyMotionLevel);
      if (levelIndex != null && levelIndex < MotionLevel.values.length) {
        _motionLevel = MotionLevel.values[levelIndex];
      }

      _followSystemPreference = prefs.getBool(_prefsKeyFollowSystem) ?? true;

      _initialized = true;
      notifyListeners();
      debugPrint('[ReducedMotionService] Initialized: $_effectiveMotionLevel');
    } catch (e) {
      debugPrint('[ReducedMotionService] Init error: $e');
      _initialized = true;
    }
  }

  /// Detect system reduced motion preference
  void _detectSystemPreference() {
    // Check if system prefers reduced motion
    // This uses the accessibility features of the platform
    try {
      // Check via MediaQuery if available, otherwise default to false
      // Note: Full detection requires BuildContext, so we default here
      // and can update via updateFromContext() when context is available
      _systemPrefersReducedMotion = false;
    } catch (e) {
      _systemPrefersReducedMotion = false;
    }
  }

  /// Update system preference from BuildContext
  void updateFromContext(BuildContext context) {
    try {
      final mediaQuery = MediaQuery.maybeOf(context);
      final prefersReducedMotion = mediaQuery?.disableAnimations ?? false;
      if (_systemPrefersReducedMotion != prefersReducedMotion) {
        _systemPrefersReducedMotion = prefersReducedMotion;
        notifyListeners();
      }
    } catch (e) {
      // Ignore errors
    }
  }

  /// Set motion level
  Future<void> setMotionLevel(MotionLevel level) async {
    if (_motionLevel == level) return;

    _motionLevel = level;
    await _save();
    notifyListeners();
    debugPrint('[ReducedMotionService] Motion level: $level');
  }

  /// Set whether to follow system preference
  Future<void> setFollowSystemPreference(bool follow) async {
    if (_followSystemPreference == follow) return;

    _followSystemPreference = follow;
    await _save();
    notifyListeners();
    debugPrint('[ReducedMotionService] Follow system: $follow');
  }

  /// Save preferences
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKeyMotionLevel, _motionLevel.index);
      await prefs.setBool(_prefsKeyFollowSystem, _followSystemPreference);
    } catch (e) {
      debugPrint('[ReducedMotionService] Save error: $e');
    }
  }

  /// Scale a duration based on motion level
  Duration scaleDuration(Duration original) {
    if (_effectiveMotionLevel == MotionLevel.none) {
      return Duration.zero;
    }
    final scaled = original.inMicroseconds * durationMultiplier;
    return Duration(microseconds: scaled.round());
  }

  /// Get scaled animation duration in milliseconds
  int scaleMs(int originalMs) {
    if (_effectiveMotionLevel == MotionLevel.none) return 0;
    return (originalMs * durationMultiplier).round();
  }

  /// Get scaled particle count
  int scaleParticleCount(int originalCount) {
    return (originalCount * particleMultiplier).round();
  }

  /// Check if a specific animation type should be shown
  bool shouldAnimate(AnimationType type) {
    switch (type) {
      case AnimationType.essential:
        // Always show essential animations (except in none mode)
        return _effectiveMotionLevel != MotionLevel.none;

      case AnimationType.decorative:
        // Only show decorative animations in full mode
        return _effectiveMotionLevel == MotionLevel.full;

      case AnimationType.feedback:
        // Show feedback animations unless minimal/none
        return _effectiveMotionLevel == MotionLevel.full ||
            _effectiveMotionLevel == MotionLevel.reduced;

      case AnimationType.transition:
        // Show transitions unless none mode
        return _effectiveMotionLevel != MotionLevel.none;

      case AnimationType.loading:
        // Always show loading indicators
        return true;

      case AnimationType.particle:
        return showParticles;

      case AnimationType.parallax:
        // Only in full mode
        return _effectiveMotionLevel == MotionLevel.full;

      case AnimationType.reelSpin:
        // Simplify in minimal/none
        return !simplifyReelAnimation;
    }
  }
}

/// Types of animations for conditional display
enum AnimationType {
  /// Essential UI animations (e.g., button press feedback)
  essential,

  /// Decorative animations (e.g., background effects)
  decorative,

  /// Feedback animations (e.g., success/error indicators)
  feedback,

  /// Page/panel transitions
  transition,

  /// Loading indicators
  loading,

  /// Particle effects
  particle,

  /// Parallax effects
  parallax,

  /// Slot reel spinning
  reelSpin,
}

// ═══════════════════════════════════════════════════════════════════════════
// REDUCED MOTION WRAPPER WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Wrapper that applies reduced motion settings to child animations
class ReducedMotionBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, ReducedMotionService service) builder;

  const ReducedMotionBuilder({
    super.key,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ReducedMotionService.instance,
      builder: (context, _) => builder(context, ReducedMotionService.instance),
    );
  }
}

/// Animated container that respects reduced motion
class MotionAwareAnimatedContainer extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;
  final AlignmentGeometry? alignment;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Decoration? decoration;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final Matrix4? transform;
  final AlignmentGeometry? transformAlignment;
  final Clip clipBehavior;

  const MotionAwareAnimatedContainer({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.easeInOut,
    this.alignment,
    this.padding,
    this.color,
    this.decoration,
    this.width,
    this.height,
    this.constraints,
    this.transform,
    this.transformAlignment,
    this.clipBehavior = Clip.none,
  });

  @override
  Widget build(BuildContext context) {
    final service = ReducedMotionService.instance;
    final scaledDuration = service.scaleDuration(duration);

    if (scaledDuration == Duration.zero) {
      // No animation - return regular container
      return Container(
        alignment: alignment,
        padding: padding,
        color: color,
        decoration: decoration,
        width: width,
        height: height,
        constraints: constraints,
        transform: transform,
        transformAlignment: transformAlignment,
        clipBehavior: clipBehavior,
        child: child,
      );
    }

    return AnimatedContainer(
      duration: scaledDuration,
      curve: curve,
      alignment: alignment,
      padding: padding,
      color: color,
      decoration: decoration,
      width: width,
      height: height,
      constraints: constraints,
      transform: transform,
      transformAlignment: transformAlignment,
      clipBehavior: clipBehavior,
      child: child,
    );
  }
}

/// Animated opacity that respects reduced motion
class MotionAwareAnimatedOpacity extends StatelessWidget {
  final Widget child;
  final double opacity;
  final Duration duration;
  final Curve curve;

  const MotionAwareAnimatedOpacity({
    super.key,
    required this.child,
    required this.opacity,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.easeInOut,
  });

  @override
  Widget build(BuildContext context) {
    final service = ReducedMotionService.instance;
    final scaledDuration = service.scaleDuration(duration);

    if (scaledDuration == Duration.zero) {
      return Opacity(opacity: opacity, child: child);
    }

    return AnimatedOpacity(
      duration: scaledDuration,
      curve: curve,
      opacity: opacity,
      child: child,
    );
  }
}
