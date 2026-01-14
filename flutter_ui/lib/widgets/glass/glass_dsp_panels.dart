/// Glass DSP Panels
///
/// Theme-aware wrappers for DSP processor panels.
/// Applies Glass styling overlay in Glass mode while preserving
/// all original functionality.

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../providers/theme_mode_provider.dart';
import '../dsp/pro_eq_panel.dart';
import '../dsp/dynamics_panel.dart';
import '../dsp/spatial_panel.dart';
import '../dsp/reverb_panel.dart';
import '../dsp/delay_panel.dart';
import '../dsp/analog_eq_panel.dart';
import '../dsp/channel_strip_panel.dart';
import '../dsp/convolution_ultra_panel.dart';
import '../dsp/gpu_settings_panel.dart';
import '../dsp/linear_phase_eq_panel.dart';
import '../dsp/mastering_panel.dart';
import '../dsp/ml_processor_panel.dart';
import '../dsp/multiband_panel.dart';
import '../dsp/pitch_correction_panel.dart';
import '../dsp/restoration_panel.dart';
import '../dsp/room_correction_panel.dart';
import '../dsp/saturation_panel.dart';
import '../dsp/sidechain_panel.dart';
import '../dsp/spectral_panel.dart';
import '../dsp/stereo_eq_panel.dart';
import '../dsp/stereo_imager_panel.dart';
import '../dsp/surround_panner_panel.dart';
import '../dsp/time_stretch_panel.dart';
import '../dsp/transient_panel.dart';
import '../dsp/ultra_eq_panel.dart';
import '../dsp/wavelet_panel.dart';

// ==============================================================================
// GLASS PANEL WRAPPER
// ==============================================================================

/// Applies Glass styling to any DSP panel
class GlassDspPanelWrapper extends StatelessWidget {
  final Widget child;
  final double blurAmount;
  final double borderRadius;

  const GlassDspPanelWrapper({
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
                Colors.white.withValues(alpha: 0.06),
                Colors.white.withValues(alpha: 0.03),
                Colors.black.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: LiquidGlassTheme.borderLight),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ==============================================================================
// THEME-AWARE PRO EQ PANEL
// ==============================================================================

class ThemeAwareProEqPanel extends StatelessWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareProEqPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    final panel = ProEqPanel(
      trackId: trackId,
      sampleRate: sampleRate,
      onSettingsChanged: onSettingsChanged,
    );

    if (isGlassMode) {
      return GlassDspPanelWrapper(child: panel);
    }

    return panel;
  }
}

// ==============================================================================
// THEME-AWARE DYNAMICS PANEL
// ==============================================================================

class ThemeAwareDynamicsPanel extends StatelessWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareDynamicsPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    final panel = DynamicsPanel(
      trackId: trackId,
      sampleRate: sampleRate,
      onSettingsChanged: onSettingsChanged,
    );

    if (isGlassMode) {
      return GlassDspPanelWrapper(child: panel);
    }

    return panel;
  }
}

// ==============================================================================
// THEME-AWARE SPATIAL PANEL
// ==============================================================================

class ThemeAwareSpatialPanel extends StatelessWidget {
  final int trackId;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareSpatialPanel({
    super.key,
    required this.trackId,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    final panel = SpatialPanel(
      trackId: trackId,
      onSettingsChanged: onSettingsChanged,
    );

    if (isGlassMode) {
      return GlassDspPanelWrapper(child: panel);
    }

    return panel;
  }
}

// ==============================================================================
// THEME-AWARE REVERB PANEL
// ==============================================================================

class ThemeAwareReverbPanel extends StatelessWidget {
  final int trackId;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareReverbPanel({
    super.key,
    required this.trackId,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    final panel = ReverbPanel(
      trackId: trackId,
      onSettingsChanged: onSettingsChanged,
    );

    if (isGlassMode) {
      return GlassDspPanelWrapper(child: panel);
    }

    return panel;
  }
}

// ==============================================================================
// THEME-AWARE DELAY PANEL
// ==============================================================================

class ThemeAwareDelayPanel extends StatelessWidget {
  final int trackId;
  final double bpm;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareDelayPanel({
    super.key,
    required this.trackId,
    this.bpm = 120.0,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    final panel = DelayPanel(
      trackId: trackId,
      bpm: bpm,
      sampleRate: sampleRate,
      onSettingsChanged: onSettingsChanged,
    );

    if (isGlassMode) {
      return GlassDspPanelWrapper(child: panel);
    }

    return panel;
  }
}

// ==============================================================================
// THEME-AWARE ANALOG EQ PANEL
// ==============================================================================

class ThemeAwareAnalogEqPanel extends StatelessWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareAnalogEqPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = AnalogEqPanel(
      trackId: trackId,
      sampleRate: sampleRate,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE CHANNEL STRIP PANEL
// ==============================================================================

class ThemeAwareChannelStripPanel extends StatelessWidget {
  final int trackId;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareChannelStripPanel({
    super.key,
    required this.trackId,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = ChannelStripPanel(
      trackId: trackId,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE CONVOLUTION ULTRA PANEL
// ==============================================================================

class ThemeAwareConvolutionUltraPanel extends StatelessWidget {
  final IrFileInfo? irA;
  final IrFileInfo? irB;
  final double morphBlend;
  final ConvolutionMode mode;
  final IrMorphMode morphMode;
  final double wetLevel;
  final double dryLevel;
  final double preDelay;
  final bool enableMorphing;
  final ValueChanged<String>? onLoadIrA;
  final ValueChanged<String>? onLoadIrB;
  final ValueChanged<double>? onMorphBlendChanged;
  final ValueChanged<ConvolutionMode>? onModeChanged;
  final ValueChanged<IrMorphMode>? onMorphModeChanged;
  final ValueChanged<double>? onWetChanged;
  final ValueChanged<double>? onDryChanged;
  final ValueChanged<double>? onPreDelayChanged;
  final ValueChanged<bool>? onMorphingToggled;
  final VoidCallback? onDeconvolutionWizard;
  final VoidCallback? onClose;

  const ThemeAwareConvolutionUltraPanel({
    super.key,
    this.irA,
    this.irB,
    this.morphBlend = 0.0,
    this.mode = ConvolutionMode.standard,
    this.morphMode = IrMorphMode.crossfade,
    this.wetLevel = 0.5,
    this.dryLevel = 0.5,
    this.preDelay = 0.0,
    this.enableMorphing = false,
    this.onLoadIrA,
    this.onLoadIrB,
    this.onMorphBlendChanged,
    this.onModeChanged,
    this.onMorphModeChanged,
    this.onWetChanged,
    this.onDryChanged,
    this.onPreDelayChanged,
    this.onMorphingToggled,
    this.onDeconvolutionWizard,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = ConvolutionUltraPanel(
      irA: irA,
      irB: irB,
      morphBlend: morphBlend,
      mode: mode,
      morphMode: morphMode,
      wetLevel: wetLevel,
      dryLevel: dryLevel,
      preDelay: preDelay,
      enableMorphing: enableMorphing,
      onLoadIrA: onLoadIrA,
      onLoadIrB: onLoadIrB,
      onMorphBlendChanged: onMorphBlendChanged,
      onModeChanged: onModeChanged,
      onMorphModeChanged: onMorphModeChanged,
      onWetChanged: onWetChanged,
      onDryChanged: onDryChanged,
      onPreDelayChanged: onPreDelayChanged,
      onMorphingToggled: onMorphingToggled,
      onDeconvolutionWizard: onDeconvolutionWizard,
      onClose: onClose,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE GPU SETTINGS PANEL
// ==============================================================================

class ThemeAwareGpuSettingsPanel extends StatelessWidget {
  final GpuDeviceInfo? deviceInfo;
  final GpuProcessingMode currentMode;
  final GpuPerformanceStats stats;
  final ValueChanged<GpuProcessingMode>? onModeChanged;
  final ValueChanged<int>? onFftSizeChanged;
  final VoidCallback? onClose;

  const ThemeAwareGpuSettingsPanel({
    super.key,
    this.deviceInfo,
    this.currentMode = GpuProcessingMode.cpuOnly,
    this.stats = const GpuPerformanceStats(),
    this.onModeChanged,
    this.onFftSizeChanged,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = GpuSettingsPanel(
      deviceInfo: deviceInfo,
      currentMode: currentMode,
      stats: stats,
      onModeChanged: onModeChanged,
      onFftSizeChanged: onFftSizeChanged,
      onClose: onClose,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE LINEAR PHASE EQ PANEL
// ==============================================================================

class ThemeAwareLinearPhaseEqPanel extends StatelessWidget {
  final int trackId;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareLinearPhaseEqPanel({
    super.key,
    required this.trackId,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = LinearPhaseEqPanel(
      trackId: trackId,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE MASTERING PANEL
// ==============================================================================

class ThemeAwareMasteringPanel extends StatelessWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareMasteringPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = MasteringPanel(
      trackId: trackId,
      sampleRate: sampleRate,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE ML PROCESSOR PANEL
// ==============================================================================

class ThemeAwareMlProcessorPanel extends StatelessWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onProcessingStart;
  final VoidCallback? onProcessingComplete;

  const ThemeAwareMlProcessorPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onProcessingStart,
    this.onProcessingComplete,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = MlProcessorPanel(
      trackId: trackId,
      sampleRate: sampleRate,
      onProcessingStart: onProcessingStart,
      onProcessingComplete: onProcessingComplete,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE MULTIBAND PANEL
// ==============================================================================

class ThemeAwareMultibandPanel extends StatelessWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareMultibandPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = MultibandPanel(
      trackId: trackId,
      sampleRate: sampleRate,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE PITCH CORRECTION PANEL
// ==============================================================================

class ThemeAwarePitchCorrectionPanel extends StatelessWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const ThemeAwarePitchCorrectionPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = PitchCorrectionPanel(
      trackId: trackId,
      sampleRate: sampleRate,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE RESTORATION PANEL
// ==============================================================================

class ThemeAwareRestorationPanel extends StatelessWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareRestorationPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = RestorationPanel(
      trackId: trackId,
      sampleRate: sampleRate,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE ROOM CORRECTION PANEL
// ==============================================================================

class ThemeAwareRoomCorrectionPanel extends StatelessWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareRoomCorrectionPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = RoomCorrectionPanel(
      trackId: trackId,
      sampleRate: sampleRate,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE SATURATION PANEL
// ==============================================================================

class ThemeAwareSaturationPanel extends StatelessWidget {
  final int trackId;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareSaturationPanel({
    super.key,
    required this.trackId,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = SaturationPanel(
      trackId: trackId,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE SIDECHAIN PANEL
// ==============================================================================

class ThemeAwareSidechainPanel extends StatelessWidget {
  final int processorId;
  final List<SidechainSourceInfo> availableSources;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareSidechainPanel({
    super.key,
    required this.processorId,
    this.availableSources = const [],
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = SidechainPanel(
      processorId: processorId,
      availableSources: availableSources,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE SPECTRAL PANEL
// ==============================================================================

class ThemeAwareSpectralPanel extends StatelessWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareSpectralPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = SpectralPanel(
      trackId: trackId,
      sampleRate: sampleRate,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE STEREO EQ PANEL
// ==============================================================================

class ThemeAwareStereoEqPanel extends StatelessWidget {
  final int trackId;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareStereoEqPanel({
    super.key,
    required this.trackId,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = StereoEqPanel(
      trackId: trackId,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE STEREO IMAGER PANEL
// ==============================================================================

class ThemeAwareStereoImagerPanel extends StatelessWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareStereoImagerPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = StereoImagerPanel(
      trackId: trackId,
      sampleRate: sampleRate,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE SURROUND PANNER PANEL
// ==============================================================================

class ThemeAwareSurroundPannerPanel extends StatelessWidget {
  final int trackId;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareSurroundPannerPanel({
    super.key,
    required this.trackId,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = SurroundPannerPanel(
      trackId: trackId,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE TIME STRETCH PANEL
// ==============================================================================

class ThemeAwareTimeStretchPanel extends StatelessWidget {
  final int clipId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareTimeStretchPanel({
    super.key,
    required this.clipId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = TimeStretchPanel(
      clipId: clipId,
      sampleRate: sampleRate,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE TRANSIENT PANEL
// ==============================================================================

class ThemeAwareTransientPanel extends StatelessWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareTransientPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = TransientPanel(
      trackId: trackId,
      sampleRate: sampleRate,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE ULTRA EQ PANEL
// ==============================================================================

class ThemeAwareUltraEqPanel extends StatelessWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareUltraEqPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = UltraEqPanel(
      trackId: trackId,
      sampleRate: sampleRate,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE WAVELET PANEL
// ==============================================================================

class ThemeAwareWaveletPanel extends StatelessWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const ThemeAwareWaveletPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = WaveletPanel(
      trackId: trackId,
      sampleRate: sampleRate,
      onSettingsChanged: onSettingsChanged,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// GLASS SECTION HEADER (reusable for DSP panels)
// ==============================================================================

class GlassSectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget? trailing;

  const GlassSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (!isGlassMode) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: Colors.white70),
              const SizedBox(width: 8),
            ],
            Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            if (trailing != null) ...[
              const Spacer(),
              trailing!,
            ],
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.08),
                Colors.white.withValues(alpha: 0.04),
              ],
            ),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: LiquidGlassTheme.textSecondary),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: TextStyle(
                  color: LiquidGlassTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              if (trailing != null) ...[
                const Spacer(),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// GLASS PARAMETER ROW (reusable for DSP controls)
// ==============================================================================

class GlassParameterRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? control;
  final Color? accentColor;

  const GlassParameterRow({
    super.key,
    required this.label,
    required this.value,
    this.control,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (!isGlassMode) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
            Expanded(
              flex: 3,
              child: control ?? Text(
                value,
                style: TextStyle(
                  color: accentColor ?? Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: LiquidGlassTheme.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: control ?? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: (accentColor ?? LiquidGlassTheme.accentBlue).withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                value,
                style: TextStyle(
                  color: accentColor ?? LiquidGlassTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==============================================================================
// GLASS TOGGLE BUTTON (for DSP bypass, etc.)
// ==============================================================================

class GlassToggleButton extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;
  final IconData? icon;
  final Color? activeColor;

  const GlassToggleButton({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.icon,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final color = activeColor ?? LiquidGlassTheme.accentBlue;

    if (!isGlassMode) {
      return GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: value ? color : Colors.white12,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: value ? Colors.white : Colors.white54),
                if (label != null) const SizedBox(width: 6),
              ],
              if (label != null)
                Text(
                  label!,
                  style: TextStyle(
                    color: value ? Colors.white : Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: AnimatedContainer(
            duration: LiquidGlassTheme.animFast,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: value
                  ? LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.6),
                        color.withValues(alpha: 0.4),
                      ],
                    )
                  : null,
              color: value ? null : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: value ? color : Colors.white.withValues(alpha: 0.2),
              ),
              boxShadow: value
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 14,
                    color: value ? LiquidGlassTheme.textPrimary : LiquidGlassTheme.textTertiary,
                  ),
                  if (label != null) const SizedBox(width: 6),
                ],
                if (label != null)
                  Text(
                    label!,
                    style: TextStyle(
                      color: value ? LiquidGlassTheme.textPrimary : LiquidGlassTheme.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
