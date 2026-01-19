/// Glass Slot Lab — Theme-Aware Wrappers for Slot Lab Components
///
/// Premium Glass/Classic switching for all Slot Lab widgets.
/// Follows same pattern as glass_timeline_ultimate.dart
///
/// Components covered:
/// - SlotPreviewWidget (reel display)
/// - StageTraceWidget (stage timeline)
/// - EventLogPanel (event list)
/// - ForcedOutcomePanel (test buttons)

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../theme/liquid_glass_theme.dart';

// ==============================================================================
// BASE GLASS WRAPPER — Slot Lab optimized
// ==============================================================================

/// Premium Glass wrapper optimized for Slot Lab components
class GlassSlotLabWrapper extends StatelessWidget {
  final Widget child;
  final double blurAmount;
  final double borderRadius;
  final bool showBorder;
  final bool showShadow;
  final bool subtle;
  final Color? accentColor;
  final bool isActive;

  const GlassSlotLabWrapper({
    super.key,
    required this.child,
    this.blurAmount = 10.0,
    this.borderRadius = 8.0,
    this.showBorder = true,
    this.showShadow = true,
    this.subtle = false,
    this.accentColor,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? LiquidGlassTheme.accentPurple;

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
                      Colors.white.withValues(alpha: 0.02),
                      Colors.black.withValues(alpha: 0.03),
                    ]
                  : isActive
                      ? [
                          accent.withValues(alpha: 0.12),
                          accent.withValues(alpha: 0.06),
                          Colors.black.withValues(alpha: 0.05),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.05),
                          Colors.white.withValues(alpha: 0.02),
                          Colors.black.withValues(alpha: 0.04),
                        ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: showBorder
                ? Border.all(
                    color: isActive
                        ? accent.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.08),
                    width: isActive ? 1.5 : 1.0,
                  )
                : null,
            boxShadow: showShadow
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                    if (isActive)
                      BoxShadow(
                        color: accent.withValues(alpha: 0.15),
                        blurRadius: 30,
                        spreadRadius: -5,
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

/// Theme-aware wrapper that applies Glass styling when in Glass mode
class ThemeAwareSlotLabWidget extends StatelessWidget {
  final Widget child;
  final double blurAmount;
  final double borderRadius;
  final bool showBorder;
  final bool showShadow;
  final bool subtle;
  final Color? accentColor;
  final bool isActive;

  const ThemeAwareSlotLabWidget({
    super.key,
    required this.child,
    this.blurAmount = 10.0,
    this.borderRadius = 8.0,
    this.showBorder = true,
    this.showShadow = true,
    this.subtle = false,
    this.accentColor,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return GlassSlotLabWrapper(
        blurAmount: blurAmount,
        borderRadius: borderRadius,
        showBorder: showBorder,
        showShadow: showShadow,
        subtle: subtle,
        accentColor: accentColor,
        isActive: isActive,
        child: child,
      );
    }
    return child;
  }
}

// ==============================================================================
// SPECIALIZED SLOT LAB WRAPPERS
// ==============================================================================

/// Glass wrapper for SlotPreviewWidget (reel display)
class GlassSlotPreviewWrapper extends StatelessWidget {
  final Widget child;
  final bool isSpinning;
  final bool hasWin;

  const GlassSlotPreviewWrapper({
    super.key,
    required this.child,
    this.isSpinning = false,
    this.hasWin = false,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      final Color accentColor;
      if (hasWin) {
        accentColor = LiquidGlassTheme.accentGreen;
      } else if (isSpinning) {
        accentColor = LiquidGlassTheme.accentBlue;
      } else {
        accentColor = LiquidGlassTheme.accentPurple;
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accentColor.withValues(alpha: hasWin ? 0.15 : 0.08),
                  Colors.black.withValues(alpha: 0.2),
                  accentColor.withValues(alpha: hasWin ? 0.10 : 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasWin
                    ? accentColor.withValues(alpha: 0.6)
                    : accentColor.withValues(alpha: 0.3),
                width: hasWin ? 2 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                if (hasWin)
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.3),
                    blurRadius: 40,
                    spreadRadius: -10,
                  ),
                if (isSpinning)
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.2),
                    blurRadius: 20,
                  ),
              ],
            ),
            child: child,
          ),
        ),
      );
    }
    return child;
  }
}

/// Glass wrapper for individual reel in SlotPreviewWidget
class GlassReelWrapper extends StatelessWidget {
  final Widget child;
  final int reelIndex;
  final bool isSpinning;
  final bool isWinning;

  const GlassReelWrapper({
    super.key,
    required this.child,
    required this.reelIndex,
    this.isSpinning = false,
    this.isWinning = false,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: isWinning ? 0.08 : 0.03),
                  Colors.black.withValues(alpha: 0.1),
                  Colors.white.withValues(alpha: isWinning ? 0.06 : 0.02),
                ],
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isWinning
                    ? LiquidGlassTheme.accentGreen.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.06),
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

/// Glass wrapper for StageTraceWidget (stage timeline)
class GlassStageTraceWrapper extends StatelessWidget {
  final Widget child;
  final bool isPlaying;

  const GlassStageTraceWrapper({
    super.key,
    required this.child,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    return ThemeAwareSlotLabWidget(
      borderRadius: 8,
      blurAmount: 8.0,
      showShadow: true,
      accentColor: isPlaying
          ? LiquidGlassTheme.accentCyan
          : LiquidGlassTheme.accentBlue,
      isActive: isPlaying,
      child: child,
    );
  }
}

/// Glass wrapper for individual stage event in timeline
class GlassStageEventWrapper extends StatelessWidget {
  final Widget child;
  final String stageType;
  final bool isCurrent;
  final bool isCompleted;

  const GlassStageEventWrapper({
    super.key,
    required this.child,
    required this.stageType,
    this.isCurrent = false,
    this.isCompleted = false,
  });

  Color _getStageColor() {
    final type = stageType.toLowerCase();

    if (type.contains('spin')) return LiquidGlassTheme.accentBlue;
    if (type.contains('reel')) return LiquidGlassTheme.accentCyan;
    if (type.contains('win') || type.contains('bigwin')) {
      return LiquidGlassTheme.accentGreen;
    }
    if (type.contains('jackpot')) return LiquidGlassTheme.accentOrange;
    if (type.contains('feature') || type.contains('bonus')) {
      return LiquidGlassTheme.accentPurple;
    }
    if (type.contains('anticipation')) return LiquidGlassTheme.accentYellow;
    if (type.contains('cascade')) return LiquidGlassTheme.accentCyan;

    return LiquidGlassTheme.accentBlue;
  }

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final color = _getStageColor();

    if (isGlassMode) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isCurrent
                    ? [
                        color.withValues(alpha: 0.25),
                        color.withValues(alpha: 0.15),
                      ]
                    : isCompleted
                        ? [
                            color.withValues(alpha: 0.08),
                            color.withValues(alpha: 0.04),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.04),
                            Colors.black.withValues(alpha: 0.02),
                          ],
              ),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isCurrent
                    ? color.withValues(alpha: 0.7)
                    : color.withValues(alpha: isCompleted ? 0.3 : 0.15),
                width: isCurrent ? 1.5 : 1.0,
              ),
              boxShadow: isCurrent
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

/// Glass wrapper for EventLogPanel
class GlassEventLogWrapper extends StatelessWidget {
  final Widget child;

  const GlassEventLogWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ThemeAwareSlotLabWidget(
      borderRadius: 8,
      blurAmount: 6.0,
      subtle: true,
      showShadow: false,
      child: child,
    );
  }
}

/// Glass wrapper for individual event log entry
class GlassEventLogEntryWrapper extends StatelessWidget {
  final Widget child;
  final bool isError;
  final bool isWarning;
  final bool isSuccess;

  const GlassEventLogEntryWrapper({
    super.key,
    required this.child,
    this.isError = false,
    this.isWarning = false,
    this.isSuccess = false,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      final Color accentColor;
      if (isError) {
        accentColor = LiquidGlassTheme.accentRed;
      } else if (isWarning) {
        accentColor = LiquidGlassTheme.accentOrange;
      } else if (isSuccess) {
        accentColor = LiquidGlassTheme.accentGreen;
      } else {
        accentColor = LiquidGlassTheme.accentBlue;
      }

      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              accentColor.withValues(alpha: 0.08),
              Colors.transparent,
            ],
          ),
          border: Border(
            left: BorderSide(
              color: accentColor.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
        ),
        child: child,
      );
    }
    return child;
  }
}

/// Glass wrapper for ForcedOutcomePanel
class GlassForcedOutcomePanelWrapper extends StatelessWidget {
  final Widget child;

  const GlassForcedOutcomePanelWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ThemeAwareSlotLabWidget(
      borderRadius: 8,
      blurAmount: 8.0,
      showShadow: true,
      accentColor: LiquidGlassTheme.accentPurple,
      child: child,
    );
  }
}

/// Glass wrapper for individual forced outcome button
class GlassForcedOutcomeButtonWrapper extends StatelessWidget {
  final Widget child;
  final String outcomeType;
  final bool isHovered;
  final bool isPressed;

  const GlassForcedOutcomeButtonWrapper({
    super.key,
    required this.child,
    required this.outcomeType,
    this.isHovered = false,
    this.isPressed = false,
  });

  Color _getOutcomeColor() {
    final type = outcomeType.toLowerCase();

    if (type.contains('lose')) return LiquidGlassTheme.accentRed;
    if (type.contains('small')) return LiquidGlassTheme.accentGreen;
    if (type.contains('medium')) return LiquidGlassTheme.accentCyan;
    if (type.contains('big')) return LiquidGlassTheme.accentBlue;
    if (type.contains('mega')) return LiquidGlassTheme.accentPurple;
    if (type.contains('epic')) return LiquidGlassTheme.accentOrange;
    if (type.contains('ultra')) return LiquidGlassTheme.accentYellow;
    if (type.contains('jackpot')) return LiquidGlassTheme.accentOrange;
    if (type.contains('free')) return LiquidGlassTheme.accentCyan;
    if (type.contains('near')) return LiquidGlassTheme.accentYellow;
    if (type.contains('cascade')) return LiquidGlassTheme.accentCyan;

    return LiquidGlassTheme.accentBlue;
  }

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final color = _getOutcomeColor();

    if (isGlassMode) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isPressed
                    ? [
                        color.withValues(alpha: 0.35),
                        color.withValues(alpha: 0.20),
                      ]
                    : isHovered
                        ? [
                            color.withValues(alpha: 0.20),
                            color.withValues(alpha: 0.10),
                          ]
                        : [
                            color.withValues(alpha: 0.12),
                            color.withValues(alpha: 0.06),
                          ],
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: color.withValues(alpha: isPressed ? 0.8 : isHovered ? 0.5 : 0.3),
                width: isPressed ? 1.5 : 1.0,
              ),
              boxShadow: isHovered || isPressed
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.25),
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

/// Glass wrapper for win celebration overlay
class GlassWinCelebrationWrapper extends StatelessWidget {
  final Widget child;
  final int winTier; // 1-4 (BigWin, MegaWin, EpicWin, UltraWin)

  const GlassWinCelebrationWrapper({
    super.key,
    required this.child,
    required this.winTier,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      final Color primaryColor;
      final Color secondaryColor;
      final double glowIntensity;

      switch (winTier) {
        case 1: // BigWin
          primaryColor = LiquidGlassTheme.accentGreen;
          secondaryColor = LiquidGlassTheme.accentCyan;
          glowIntensity = 0.3;
        case 2: // MegaWin
          primaryColor = LiquidGlassTheme.accentBlue;
          secondaryColor = LiquidGlassTheme.accentPurple;
          glowIntensity = 0.4;
        case 3: // EpicWin
          primaryColor = LiquidGlassTheme.accentPurple;
          secondaryColor = LiquidGlassTheme.accentOrange;
          glowIntensity = 0.5;
        case >= 4: // UltraWin
          primaryColor = LiquidGlassTheme.accentOrange;
          secondaryColor = LiquidGlassTheme.accentYellow;
          glowIntensity = 0.6;
        default:
          primaryColor = LiquidGlassTheme.accentGreen;
          secondaryColor = LiquidGlassTheme.accentCyan;
          glowIntensity = 0.3;
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  primaryColor.withValues(alpha: 0.2),
                  secondaryColor.withValues(alpha: 0.15),
                  primaryColor.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withValues(alpha: glowIntensity),
                  blurRadius: 40,
                  spreadRadius: -10,
                ),
                BoxShadow(
                  color: secondaryColor.withValues(alpha: glowIntensity * 0.5),
                  blurRadius: 60,
                  spreadRadius: -20,
                ),
              ],
            ),
            child: child,
          ),
        ),
      );
    }
    return child;
  }
}
