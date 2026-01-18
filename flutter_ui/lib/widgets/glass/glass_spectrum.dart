/// Glass Spectrum Analyzer
///
/// Theme-aware wrapper for spectrum analyzer with Glass styling.
/// Uses GlassPanelWrapper for Glass mode while preserving all original functionality.

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../providers/theme_mode_provider.dart';
import '../spectrum/spectrum_analyzer.dart';

// ==============================================================================
// THEME-AWARE SPECTRUM ANALYZER
// ==============================================================================

/// Theme-aware spectrum analyzer that switches between Glass and Classic styles
class ThemeAwareSpectrumAnalyzer extends StatelessWidget {
  final double? width;
  final double? height;
  final SpectrumConfig config;
  final Float64List? data;
  final double sampleRate;
  final bool showControls;
  final ValueChanged<SpectrumConfig>? onConfigChanged;

  const ThemeAwareSpectrumAnalyzer({
    super.key,
    this.width,
    this.height,
    this.config = const SpectrumConfig(),
    this.data,
    this.sampleRate = 48000,
    this.showControls = false,
    this.onConfigChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    final analyzer = SpectrumAnalyzer(
      width: width,
      height: height,
      config: config,
      data: data,
      sampleRate: sampleRate,
      showControls: showControls,
      onConfigChanged: onConfigChanged,
    );

    if (isGlassMode) {
      return GlassSpectrumWrapper(child: analyzer);
    }

    return analyzer;
  }
}

// ==============================================================================
// GLASS SPECTRUM WRAPPER
// ==============================================================================

/// Applies Glass styling specifically optimized for spectrum analyzers
class GlassSpectrumWrapper extends StatelessWidget {
  final Widget child;
  final double blurAmount;
  final double borderRadius;

  const GlassSpectrumWrapper({
    super.key,
    required this.child,
    this.blurAmount = LiquidGlassTheme.blurLight,
    this.borderRadius = LiquidGlassTheme.radiusMedium,
  });

  @override
  Widget build(BuildContext context) {
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
              colors: [
                Colors.white.withValues(alpha: 0.05),
                Colors.white.withValues(alpha: 0.02),
                Colors.black.withValues(alpha: 0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: LiquidGlassTheme.accentCyan.withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: LiquidGlassTheme.accentCyan.withValues(alpha: 0.1),
                blurRadius: 20,
                spreadRadius: -5,
              ),
            ],
          ),
          child: Stack(
            children: [
              // Spectrum glow effect (subtle cyan glow at bottom)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 60,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        LiquidGlassTheme.accentCyan.withValues(alpha: 0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // Main content
              child,
              // Top specular highlight
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.2),
                        Colors.white.withValues(alpha: 0.3),
                        Colors.white.withValues(alpha: 0.2),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// GLASS SPECTRUM DISPLAY (Standalone without controls)
// ==============================================================================

/// Minimal glass-styled spectrum display for embedding
class GlassSpectrumDisplay extends StatelessWidget {
  final double? width;
  final double? height;
  final Float64List? data;
  final double sampleRate;
  final SpectrumConfig config;

  const GlassSpectrumDisplay({
    super.key,
    this.width,
    this.height,
    this.data,
    this.sampleRate = 48000,
    this.config = const SpectrumConfig(),
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    final display = SpectrumAnalyzer(
      width: width,
      height: height,
      config: config,
      data: data,
      sampleRate: sampleRate,
      showControls: false,
    );

    if (isGlassMode) {
      return GlassSpectrumWrapper(
        blurAmount: 8.0,
        borderRadius: 8.0,
        child: display,
      );
    }

    return display;
  }
}
