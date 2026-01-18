/// Glass Timeline Ultimate — Complete Theme-Aware Timeline System
///
/// Ultimate Glass/Classic switching for ALL timeline components.
/// Uses a universal wrapper approach for maximum flexibility.
///
/// Philosophy: Best solution, not simplest. Full Glass aesthetics.

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../theme/liquid_glass_theme.dart';

// ==============================================================================
// GLASS TIMELINE WRAPPER — Universal styling for timeline components
// ==============================================================================

/// Premium Glass wrapper optimized for timeline components
class GlassTimelineUltimateWrapper extends StatelessWidget {
  final Widget child;
  final double blurAmount;
  final double borderRadius;
  final bool showBorder;
  final bool showShadow;
  final bool subtle;
  final Color? accentColor;

  const GlassTimelineUltimateWrapper({
    super.key,
    required this.child,
    this.blurAmount = 8.0,
    this.borderRadius = 6.0,
    this.showBorder = true,
    this.showShadow = true,
    this.subtle = false,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? LiquidGlassTheme.accentBlue;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: blurAmount,
          sigmaY: blurAmount,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: subtle
                  ? [
                      Colors.white.withValues(alpha: 0.03),
                      Colors.black.withValues(alpha: 0.04),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.06),
                      Colors.white.withValues(alpha: 0.03),
                      Colors.black.withValues(alpha: 0.05),
                    ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: showBorder
                ? Border.all(color: Colors.white.withValues(alpha: 0.10))
                : null,
            boxShadow: showShadow
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: accent.withValues(alpha: 0.04),
                      blurRadius: 24,
                      spreadRadius: -4,
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Universal theme-aware wrapper that applies Glass styling when in Glass mode
class ThemeAwareTimelineWidget extends StatelessWidget {
  final Widget child;
  final double blurAmount;
  final double borderRadius;
  final bool showBorder;
  final bool showShadow;
  final bool subtle;
  final Color? accentColor;

  const ThemeAwareTimelineWidget({
    super.key,
    required this.child,
    this.blurAmount = 8.0,
    this.borderRadius = 6.0,
    this.showBorder = true,
    this.showShadow = true,
    this.subtle = false,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return GlassTimelineUltimateWrapper(
        blurAmount: blurAmount,
        borderRadius: borderRadius,
        showBorder: showBorder,
        showShadow: showShadow,
        subtle: subtle,
        accentColor: accentColor,
        child: child,
      );
    }
    return child;
  }
}

// ==============================================================================
// SPECIALIZED TIMELINE GLASS WRAPPERS
// ==============================================================================

/// Glass wrapper for main Timeline widget
class GlassTimelineContainer extends StatelessWidget {
  final Widget child;

  const GlassTimelineContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ThemeAwareTimelineWidget(
      borderRadius: 0,
      showBorder: false,
      showShadow: false,
      subtle: true,
      child: child,
    );
  }
}

/// Glass wrapper for track lanes
class GlassTrackLaneWrapper extends StatelessWidget {
  final Widget child;
  final Color? trackColor;
  final bool isSelected;

  const GlassTrackLaneWrapper({
    super.key,
    required this.child,
    this.trackColor,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return ClipRRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: isSelected ? 0.06 : 0.02),
                  Colors.black.withValues(alpha: 0.04),
                ],
              ),
              border: Border(
                left: BorderSide(
                  color: (trackColor ?? LiquidGlassTheme.accentBlue)
                      .withValues(alpha: isSelected ? 0.6 : 0.3),
                  width: 2,
                ),
              ),
            ),
            child: child,
          ),
        ),
      );
    }
    return child;
  }
}

/// Glass wrapper for clips
class GlassClipWrapper extends StatelessWidget {
  final Widget child;
  final Color? clipColor;
  final bool isSelected;
  final bool isMuted;

  const GlassClipWrapper({
    super.key,
    required this.child,
    this.clipColor,
    this.isSelected = false,
    this.isMuted = false,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final color = clipColor ?? LiquidGlassTheme.accentBlue;

    if (isGlassMode) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: isMuted ? 0.05 : 0.15),
                  color.withValues(alpha: isMuted ? 0.02 : 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected
                    ? color.withValues(alpha: 0.8)
                    : color.withValues(alpha: 0.4),
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        ),
      );
    }
    return child;
  }
}

/// Glass wrapper for waveform minimap
class GlassMinimapWrapper extends StatelessWidget {
  final Widget child;

  const GlassMinimapWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ThemeAwareTimelineWidget(
      borderRadius: 0,
      showBorder: true,
      blurAmount: 10.0,
      child: child,
    );
  }
}

/// Glass wrapper for video track
class GlassVideoTrackWrapper extends StatelessWidget {
  final Widget child;

  const GlassVideoTrackWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ThemeAwareTimelineWidget(
      borderRadius: 0,
      showBorder: false,
      blurAmount: 6.0,
      accentColor: const Color(0xFF9C27B0), // Video purple
      child: child,
    );
  }
}

/// Glass wrapper for comping lanes
class GlassCompingLaneWrapper extends StatelessWidget {
  final Widget child;
  final bool isActiveLane;
  final Color? laneColor;

  const GlassCompingLaneWrapper({
    super.key,
    required this.child,
    this.isActiveLane = false,
    this.laneColor,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final color = laneColor ?? LiquidGlassTheme.accentBlue;

    if (isGlassMode) {
      return ClipRRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: isActiveLane ? 0.08 : 0.02),
                  Colors.black.withValues(alpha: 0.03),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            child: child,
          ),
        ),
      );
    }
    return child;
  }
}

/// Glass wrapper for crossfade overlays
class GlassCrossfadeWrapper extends StatelessWidget {
  final Widget child;

  const GlassCrossfadeWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ThemeAwareTimelineWidget(
      borderRadius: 4,
      blurAmount: 8.0,
      showShadow: true,
      accentColor: LiquidGlassTheme.accentPurple,
      child: child,
    );
  }
}

/// Glass wrapper for stretch overlay
class GlassStretchWrapper extends StatelessWidget {
  final Widget child;
  final double stretchRatio;

  const GlassStretchWrapper({
    super.key,
    required this.child,
    this.stretchRatio = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    // Cyan for compress, orange for expand
    final color = stretchRatio < 1.0
        ? LiquidGlassTheme.accentCyan
        : stretchRatio > 1.0
            ? LiquidGlassTheme.accentOrange
            : LiquidGlassTheme.accentBlue;

    return ThemeAwareTimelineWidget(
      borderRadius: 4,
      blurAmount: 6.0,
      accentColor: color,
      child: child,
    );
  }
}

/// Glass wrapper for freeze overlay
class GlassFreezeWrapper extends StatelessWidget {
  final Widget child;
  final bool isFrozen;
  final bool isProcessing;

  const GlassFreezeWrapper({
    super.key,
    required this.child,
    this.isFrozen = false,
    this.isProcessing = false,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode && (isFrozen || isProcessing)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  LiquidGlassTheme.accentCyan.withValues(alpha: 0.15),
                  LiquidGlassTheme.accentBlue.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: LiquidGlassTheme.accentCyan.withValues(alpha: 0.5),
              ),
            ),
            child: child,
          ),
        ),
      );
    }
    return child;
  }
}

/// Glass wrapper for warp handles
class GlassWarpHandleWrapper extends StatelessWidget {
  final Widget child;

  const GlassWarpHandleWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ThemeAwareTimelineWidget(
      borderRadius: 4,
      blurAmount: 6.0,
      accentColor: LiquidGlassTheme.accentGreen,
      child: child,
    );
  }
}

/// Glass wrapper for time stretch editor
class GlassTimeStretchEditorWrapper extends StatelessWidget {
  final Widget child;

  const GlassTimeStretchEditorWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ThemeAwareTimelineWidget(
      borderRadius: 8,
      blurAmount: 12.0,
      showShadow: true,
      child: child,
    );
  }
}

/// Glass wrapper for selection range
class GlassSelectionRangeWrapper extends StatelessWidget {
  final Widget child;

  const GlassSelectionRangeWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Selection overlay doesn't need Glass wrapper - it's transparent by design
    return child;
  }
}

// ==============================================================================
// GLASS PLAYHEAD
// ==============================================================================

/// Premium Glass-styled playhead indicator
class GlassPlayhead extends StatelessWidget {
  final double height;
  final bool isPlaying;

  const GlassPlayhead({
    super.key,
    required this.height,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return SizedBox(
        width: 3,
        height: height,
        child: Stack(
          children: [
            // Glow effect
            Container(
              width: 3,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: LiquidGlassTheme.accentRed.withValues(alpha: 0.6),
                    blurRadius: isPlaying ? 12 : 8,
                    spreadRadius: isPlaying ? 2 : 0,
                  ),
                ],
              ),
            ),
            // Core line
            Container(
              width: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    LiquidGlassTheme.accentRed,
                    LiquidGlassTheme.accentRed.withValues(alpha: 0.8),
                    LiquidGlassTheme.accentOrange.withValues(alpha: 0.6),
                  ],
                ),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      );
    }

    // Classic playhead
    return Container(
      width: 2,
      height: height,
      color: const Color(0xFFFF4040),
    );
  }
}

// ==============================================================================
// GLASS LOOP REGION
// ==============================================================================

/// Premium Glass-styled loop region indicator
class GlassLoopRegion extends StatelessWidget {
  final double width;
  final double height;
  final bool isEnabled;

  const GlassLoopRegion({
    super.key,
    required this.width,
    required this.height,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode && isEnabled) {
      return ClipRRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  LiquidGlassTheme.accentBlue.withValues(alpha: 0.12),
                  LiquidGlassTheme.accentBlue.withValues(alpha: 0.06),
                ],
              ),
              border: Border(
                left: BorderSide(
                  color: LiquidGlassTheme.accentBlue.withValues(alpha: 0.7),
                  width: 2,
                ),
                right: BorderSide(
                  color: LiquidGlassTheme.accentBlue.withValues(alpha: 0.7),
                  width: 2,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Classic loop region
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF4A9EFF).withValues(alpha: 0.15),
        border: const Border(
          left: BorderSide(color: Color(0xFF4A9EFF), width: 2),
          right: BorderSide(color: Color(0xFF4A9EFF), width: 2),
        ),
      ),
    );
  }
}
