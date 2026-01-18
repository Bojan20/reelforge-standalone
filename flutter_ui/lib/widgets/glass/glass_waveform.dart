/// Glass Waveform Widget
///
/// Theme-aware wrapper for UltimateWaveform with Glass styling.
/// Uses specialized wrapper for Glass mode while preserving all original functionality.

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../providers/theme_mode_provider.dart';
import '../waveform/ultimate_waveform.dart';

// ==============================================================================
// THEME-AWARE WAVEFORM
// ==============================================================================

/// Theme-aware waveform that switches between Glass and Classic styles
class ThemeAwareWaveform extends StatelessWidget {
  final UltimateWaveformData data;
  final UltimateWaveformConfig config;
  final double height;
  final double zoom;
  final double scrollOffset;
  final double playheadPosition;
  final (double, double)? selection;
  final bool isStereoSplit;

  const ThemeAwareWaveform({
    super.key,
    required this.data,
    this.config = const UltimateWaveformConfig(),
    this.height = 80,
    this.zoom = 1,
    this.scrollOffset = 0,
    this.playheadPosition = 0,
    this.selection,
    this.isStereoSplit = true,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    final waveform = UltimateWaveform(
      data: data,
      config: config,
      height: height,
      zoom: zoom,
      scrollOffset: scrollOffset,
      playheadPosition: playheadPosition,
      selection: selection,
      isStereoSplit: isStereoSplit,
    );

    if (isGlassMode) {
      return GlassWaveformWrapper(
        height: height,
        child: waveform,
      );
    }

    return waveform;
  }
}

// ==============================================================================
// GLASS WAVEFORM WRAPPER
// ==============================================================================

/// Applies Glass styling specifically optimized for waveform display
class GlassWaveformWrapper extends StatelessWidget {
  final Widget child;
  final double height;
  final double blurAmount;
  final double borderRadius;

  const GlassWaveformWrapper({
    super.key,
    required this.child,
    this.height = 80,
    this.blurAmount = 4.0,
    this.borderRadius = 6.0,
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
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.04),
                Colors.black.withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Stack(
            children: [
              // Waveform content
              child,
              // Center line glow
              Positioned(
                left: 0,
                right: 0,
                top: height / 2 - 0.5,
                height: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        LiquidGlassTheme.accentCyan.withValues(alpha: 0.3),
                        LiquidGlassTheme.accentCyan.withValues(alpha: 0.5),
                        LiquidGlassTheme.accentCyan.withValues(alpha: 0.3),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
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
                        Colors.white.withValues(alpha: 0.15),
                        Colors.white.withValues(alpha: 0.2),
                        Colors.white.withValues(alpha: 0.15),
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
// GLASS WAVEFORM WITH CONFIG OVERRIDE
// ==============================================================================

/// Glass-optimized waveform config that overrides colors for Glass mode
class GlassWaveformConfig {
  /// Create a Glass-optimized config from existing config
  static UltimateWaveformConfig fromConfig(UltimateWaveformConfig config) {
    return UltimateWaveformConfig(
      style: config.style,
      primaryColor: LiquidGlassTheme.accentCyan,
      rmsColor: LiquidGlassTheme.accentBlue.withValues(alpha: 0.5),
      transientColor: LiquidGlassTheme.accentOrange,
      clippingColor: LiquidGlassTheme.accentRed,
      zeroCrossingColor: LiquidGlassTheme.accentGreen,
      showRms: config.showRms,
      showTransients: config.showTransients,
      showClipping: config.showClipping,
      showZeroCrossings: config.showZeroCrossings,
      showSampleDots: config.showSampleDots,
      use3dEffect: config.use3dEffect,
      antiAlias: config.antiAlias,
      lineWidth: config.lineWidth,
      transparentBackground: true, // Always transparent for Glass mode
    );
  }
}
