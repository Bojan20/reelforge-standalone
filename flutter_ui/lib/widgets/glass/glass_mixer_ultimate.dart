/// Glass Mixer Ultimate — Complete Theme-Aware Mixer System
///
/// Ultimate Glass/Classic switching for ALL mixer components.
/// Uses a universal wrapper approach for maximum flexibility.
///
/// Philosophy: Best solution, not simplest. Full Glass aesthetics.

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../theme/liquid_glass_theme.dart';

// ==============================================================================
// GLASS MIXER WRAPPER — Premium styling for mixer components
// ==============================================================================

/// Premium Glass wrapper optimized for mixer components
class GlassMixerUltimateWrapper extends StatelessWidget {
  final Widget child;
  final double blurAmount;
  final double borderRadius;
  final bool showBorder;
  final bool showShadow;
  final bool showGlow;
  final Color? glowColor;
  final Color? accentColor;

  const GlassMixerUltimateWrapper({
    super.key,
    required this.child,
    this.blurAmount = 10.0,
    this.borderRadius = 8.0,
    this.showBorder = true,
    this.showShadow = true,
    this.showGlow = false,
    this.glowColor,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? LiquidGlassTheme.accentBlue;
    final glow = glowColor ?? accent;

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
                Colors.white.withValues(alpha: 0.07),
                Colors.white.withValues(alpha: 0.03),
                Colors.black.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: showBorder
                ? Border.all(color: Colors.white.withValues(alpha: 0.12))
                : null,
            boxShadow: [
              if (showShadow)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              if (showGlow)
                BoxShadow(
                  color: glow.withValues(alpha: 0.10),
                  blurRadius: 30,
                  spreadRadius: -5,
                ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Universal theme-aware mixer wrapper
class ThemeAwareMixerWidget extends StatelessWidget {
  final Widget child;
  final double blurAmount;
  final double borderRadius;
  final bool showBorder;
  final bool showShadow;
  final bool showGlow;
  final Color? glowColor;
  final Color? accentColor;

  const ThemeAwareMixerWidget({
    super.key,
    required this.child,
    this.blurAmount = 10.0,
    this.borderRadius = 8.0,
    this.showBorder = true,
    this.showShadow = true,
    this.showGlow = false,
    this.glowColor,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return GlassMixerUltimateWrapper(
        blurAmount: blurAmount,
        borderRadius: borderRadius,
        showBorder: showBorder,
        showShadow: showShadow,
        showGlow: showGlow,
        glowColor: glowColor,
        accentColor: accentColor,
        child: child,
      );
    }
    return child;
  }
}

// ==============================================================================
// SPECIALIZED MIXER GLASS WRAPPERS
// ==============================================================================

/// Glass wrapper for the main mixer container
class GlassMixerContainer extends StatelessWidget {
  final Widget child;

  const GlassMixerContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ThemeAwareMixerWidget(
      borderRadius: 0,
      showBorder: false,
      showGlow: true,
      child: child,
    );
  }
}

/// Glass wrapper for channel strips
class GlassChannelStripWrapper extends StatelessWidget {
  final Widget child;
  final Color? stripColor;
  final bool isSelected;
  final bool isMuted;
  final bool isSoloed;
  final bool isArmed;

  const GlassChannelStripWrapper({
    super.key,
    required this.child,
    this.stripColor,
    this.isSelected = false,
    this.isMuted = false,
    this.isSoloed = false,
    this.isArmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final color = stripColor ?? LiquidGlassTheme.accentBlue;

    if (isGlassMode) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: isSelected ? 0.10 : 0.05),
                  Colors.black.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected
                    ? color.withValues(alpha: 0.6)
                    : isSoloed
                        ? LiquidGlassTheme.accentYellow.withValues(alpha: 0.4)
                        : isMuted
                            ? LiquidGlassTheme.accentRed.withValues(alpha: 0.3)
                            : isArmed
                                ? LiquidGlassTheme.accentRed.withValues(alpha: 0.5)
                                : Colors.white.withValues(alpha: 0.08),
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
                if (isSelected)
                  BoxShadow(
                    color: color.withValues(alpha: 0.15),
                    blurRadius: 16,
                    spreadRadius: -2,
                  ),
                if (isArmed)
                  BoxShadow(
                    color: LiquidGlassTheme.accentRed.withValues(alpha: 0.2),
                    blurRadius: 12,
                    spreadRadius: -2,
                  ),
              ],
            ),
            child: Stack(
              children: [
                child,
                // Color bar at top
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          color,
                          color.withValues(alpha: 0.6),
                        ],
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(5),
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
    return child;
  }
}

/// Glass wrapper for VCA strips
class GlassVcaStripWrapper extends StatelessWidget {
  final Widget child;
  final Color? vcaColor;
  final bool isSelected;
  final bool isMuted;

  const GlassVcaStripWrapper({
    super.key,
    required this.child,
    this.vcaColor,
    this.isSelected = false,
    this.isMuted = false,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final color = vcaColor ?? LiquidGlassTheme.accentGreen;

    if (isGlassMode) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected
                    ? color.withValues(alpha: 0.6)
                    : color.withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: color.withValues(alpha: 0.08),
                  blurRadius: 16,
                  spreadRadius: -4,
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

/// Glass wrapper for master strip
class GlassMasterStripWrapper extends StatelessWidget {
  final Widget child;

  const GlassMasterStripWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  LiquidGlassTheme.accentOrange.withValues(alpha: 0.10),
                  Colors.white.withValues(alpha: 0.04),
                  Colors.black.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: LiquidGlassTheme.accentOrange.withValues(alpha: 0.4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: LiquidGlassTheme.accentOrange.withValues(alpha: 0.1),
                  blurRadius: 20,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: Stack(
              children: [
                child,
                // Master color bar
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          LiquidGlassTheme.accentOrange,
                          LiquidGlassTheme.accentYellow,
                        ],
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(7),
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
    return child;
  }
}

/// Glass wrapper for control room panel
class GlassControlRoomWrapper extends StatelessWidget {
  final Widget child;

  const GlassControlRoomWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ThemeAwareMixerWidget(
      borderRadius: 12,
      showGlow: true,
      glowColor: LiquidGlassTheme.accentCyan,
      child: child,
    );
  }
}

/// Glass wrapper for insert/send slots
class GlassSlotWrapper extends StatelessWidget {
  final Widget child;
  final bool hasPlugin;
  final bool isBypassed;

  const GlassSlotWrapper({
    super.key,
    required this.child,
    this.hasPlugin = false,
    this.isBypassed = false,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: hasPlugin
                ? [
                    LiquidGlassTheme.accentBlue.withValues(alpha: 0.15),
                    LiquidGlassTheme.accentBlue.withValues(alpha: 0.05),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.02),
                    Colors.black.withValues(alpha: 0.03),
                  ],
          ),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isBypassed
                ? LiquidGlassTheme.accentOrange.withValues(alpha: 0.5)
                : hasPlugin
                    ? LiquidGlassTheme.accentBlue.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: child,
      );
    }
    return child;
  }
}

/// Glass wrapper for plugin browser
class GlassPluginBrowserWrapper extends StatelessWidget {
  final Widget child;

  const GlassPluginBrowserWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ThemeAwareMixerWidget(
      borderRadius: 12,
      blurAmount: 15.0,
      showGlow: true,
      child: child,
    );
  }
}

/// Glass wrapper for sidechain panel
class GlassSidechainWrapper extends StatelessWidget {
  final Widget child;
  final bool isEnabled;

  const GlassSidechainWrapper({
    super.key,
    required this.child,
    this.isEnabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return ThemeAwareMixerWidget(
      borderRadius: 8,
      showGlow: isEnabled,
      glowColor: LiquidGlassTheme.accentOrange,
      child: child,
    );
  }
}

// ==============================================================================
// GLASS METERING COMPONENTS
// ==============================================================================

/// Premium Glass meter strip with glow effects
class GlassMeterStrip extends StatelessWidget {
  final double peakL;
  final double peakR;
  final double? rmsL;
  final double? rmsR;
  final double width;
  final double height;
  final bool showPeakHold;
  final bool showRms;
  final VoidCallback? onResetPeaks;

  const GlassMeterStrip({
    super.key,
    required this.peakL,
    required this.peakR,
    this.rmsL,
    this.rmsR,
    this.width = 24,
    this.height = 200,
    this.showPeakHold = true,
    this.showRms = true,
    this.onResetPeaks,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.4),
                  Colors.black.withValues(alpha: 0.6),
                ],
              ),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: GestureDetector(
              onDoubleTap: onResetPeaks,
              child: CustomPaint(
                painter: _GlassMeterPainter(
                  peakL: peakL,
                  peakR: peakR,
                  rmsL: rmsL ?? 0,
                  rmsR: rmsR ?? 0,
                  showRms: showRms,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Classic mode - simpler meter
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(2),
      ),
      child: GestureDetector(
        onDoubleTap: onResetPeaks,
        child: CustomPaint(
          painter: _ClassicMeterPainter(peakL: peakL, peakR: peakR),
        ),
      ),
    );
  }
}

class _GlassMeterPainter extends CustomPainter {
  final double peakL;
  final double peakR;
  final double rmsL;
  final double rmsR;
  final bool showRms;

  _GlassMeterPainter({
    required this.peakL,
    required this.peakR,
    required this.rmsL,
    required this.rmsR,
    required this.showRms,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final meterWidth = (size.width - 4) / 2;

    // Gradient colors
    const colors = [
      Color(0xFF40E0FF), // Cyan
      Color(0xFF40FF90), // Green
      Color(0xFFFFFF40), // Yellow
      Color(0xFFFF9040), // Orange
      Color(0xFFFF4040), // Red
    ];
    const stops = [0.0, 0.4, 0.7, 0.85, 1.0];

    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: colors,
      stops: stops,
    );

    // Left meter
    _drawMeter(canvas, Rect.fromLTWH(1, 0, meterWidth, size.height), peakL,
        gradient);

    // Right meter
    _drawMeter(
        canvas,
        Rect.fromLTWH(size.width - meterWidth - 1, 0, meterWidth, size.height),
        peakR,
        gradient);

    // RMS overlay
    if (showRms) {
      final rmsPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;

      final rmsHeightL = size.height * rmsL.clamp(0.0, 1.0);
      final rmsHeightR = size.height * rmsR.clamp(0.0, 1.0);

      canvas.drawRect(
        Rect.fromLTWH(1, size.height - rmsHeightL, meterWidth, rmsHeightL),
        rmsPaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(size.width - meterWidth - 1, size.height - rmsHeightR,
            meterWidth, rmsHeightR),
        rmsPaint,
      );
    }
  }

  void _drawMeter(
      Canvas canvas, Rect rect, double level, LinearGradient gradient) {
    final meterHeight = rect.height * level.clamp(0.0, 1.2);
    if (meterHeight <= 0) return;

    final meterRect = Rect.fromLTWH(
      rect.left,
      rect.bottom - meterHeight,
      rect.width,
      meterHeight,
    );

    canvas.drawRect(
      meterRect,
      Paint()..shader = gradient.createShader(rect),
    );

    // Glow effect at peak
    if (level > 0.7) {
      final glowColor = level > 0.9
          ? const Color(0xFFFF4040)
          : level > 0.8
              ? const Color(0xFFFF9040)
              : const Color(0xFFFFFF40);

      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.bottom - meterHeight, rect.width, 2),
        Paint()
          ..color = glowColor
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  @override
  bool shouldRepaint(_GlassMeterPainter oldDelegate) =>
      peakL != oldDelegate.peakL ||
      peakR != oldDelegate.peakR ||
      rmsL != oldDelegate.rmsL ||
      rmsR != oldDelegate.rmsR;
}

class _ClassicMeterPainter extends CustomPainter {
  final double peakL;
  final double peakR;

  _ClassicMeterPainter({required this.peakL, required this.peakR});

  @override
  void paint(Canvas canvas, Size size) {
    final meterWidth = (size.width - 2) / 2;

    const gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        Color(0xFF40C8FF),
        Color(0xFF40FF90),
        Color(0xFFFFFF40),
        Color(0xFFFF9040),
        Color(0xFFFF4040),
      ],
      stops: [0.0, 0.4, 0.7, 0.85, 1.0],
    );

    final rectL = Rect.fromLTWH(0, 0, meterWidth, size.height);
    final rectR =
        Rect.fromLTWH(size.width - meterWidth, 0, meterWidth, size.height);

    // Left
    final heightL = size.height * peakL.clamp(0.0, 1.2);
    if (heightL > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - heightL, meterWidth, heightL),
        Paint()..shader = gradient.createShader(rectL),
      );
    }

    // Right
    final heightR = size.height * peakR.clamp(0.0, 1.2);
    if (heightR > 0) {
      canvas.drawRect(
        Rect.fromLTWH(size.width - meterWidth, size.height - heightR,
            meterWidth, heightR),
        Paint()..shader = gradient.createShader(rectR),
      );
    }
  }

  @override
  bool shouldRepaint(_ClassicMeterPainter oldDelegate) =>
      peakL != oldDelegate.peakL || peakR != oldDelegate.peakR;
}

// ==============================================================================
// GLASS MIXER KNOB
// ==============================================================================

/// Premium Glass-styled mixer knob
class GlassMixerKnob extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final double size;
  final Color? color;
  final bool bipolar;
  final String? label;
  final ValueChanged<double>? onChanged;
  final VoidCallback? onReset;

  const GlassMixerKnob({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.size = 40,
    this.color,
    this.bipolar = false,
    this.label,
    this.onChanged,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final knobColor = color ?? LiquidGlassTheme.accentBlue;
    final normalizedValue = (value - min) / (max - min);

    if (isGlassMode) {
      return GestureDetector(
        onVerticalDragUpdate: (details) {
          if (onChanged != null) {
            final delta = -details.delta.dy / 100;
            final newValue = (value + delta * (max - min)).clamp(min, max);
            onChanged!(newValue);
          }
        },
        onDoubleTap: onReset,
        child: Container(
          width: size,
          height: size + (label != null ? 14 : 0),
          child: Column(
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.3),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                  border: Border.all(
                    color: knobColor.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                    BoxShadow(
                      color: knobColor.withValues(alpha: 0.2),
                      blurRadius: 12,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: CustomPaint(
                  painter: _GlassKnobPainter(
                    value: normalizedValue,
                    color: knobColor,
                    bipolar: bipolar,
                  ),
                ),
              ),
              if (label != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    label!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 9,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Classic knob (simpler)
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (onChanged != null) {
          final delta = -details.delta.dy / 100;
          final newValue = (value + delta * (max - min)).clamp(min, max);
          onChanged!(newValue);
        }
      },
      onDoubleTap: onReset,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF2A2A30),
          border: Border.all(color: const Color(0xFF3A3A40)),
        ),
        child: CustomPaint(
          painter: _ClassicKnobPainter(
            value: normalizedValue,
            color: knobColor,
            bipolar: bipolar,
          ),
        ),
      ),
    );
  }
}

class _GlassKnobPainter extends CustomPainter {
  final double value;
  final Color color;
  final bool bipolar;

  _GlassKnobPainter({
    required this.value,
    required this.color,
    required this.bipolar,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      2.4, // ~135 degrees
      4.9, // ~280 degrees sweep
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // Value arc
    final startAngle = bipolar ? 3.93 : 2.4; // Center for bipolar, bottom-left for normal
    final sweepAngle = bipolar
        ? (value - 0.5) * 4.9
        : value * 4.9;

    if (sweepAngle.abs() > 0.01) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    // Indicator dot
    final angle = 2.4 + value * 4.9;
    final indicatorPos = Offset(
      center.dx + (radius - 6) * cos(angle),
      center.dy + (radius - 6) * sin(angle),
    );
    canvas.drawCircle(
      indicatorPos,
      3,
      Paint()..color = Colors.white,
    );
  }

  double cos(double radians) => radians.cos();
  double sin(double radians) => radians.sin();

  @override
  bool shouldRepaint(_GlassKnobPainter oldDelegate) =>
      value != oldDelegate.value || color != oldDelegate.color;
}

class _ClassicKnobPainter extends CustomPainter {
  final double value;
  final Color color;
  final bool bipolar;

  _ClassicKnobPainter({
    required this.value,
    required this.color,
    required this.bipolar,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;

    // Value arc
    final startAngle = bipolar ? 3.93 : 2.4;
    final sweepAngle = bipolar
        ? (value - 0.5) * 4.9
        : value * 4.9;

    if (sweepAngle.abs() > 0.01) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Center dot
    canvas.drawCircle(center, 2, Paint()..color = color.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(_ClassicKnobPainter oldDelegate) =>
      value != oldDelegate.value || color != oldDelegate.color;
}

// Helper extension for math
extension on double {
  double cos() => (this * 180 / 3.14159).round() % 360 == 0
      ? 1.0
      : (this * 180 / 3.14159).round() % 360 == 180
          ? -1.0
          : _cosineValue(this);
  double sin() => _sineValue(this);
}

double _cosineValue(double radians) {
  // Taylor series approximation
  double x = radians % (2 * 3.14159);
  if (x > 3.14159) x -= 2 * 3.14159;
  double result = 1.0;
  double term = 1.0;
  for (int i = 1; i <= 10; i++) {
    term *= -x * x / ((2 * i - 1) * (2 * i));
    result += term;
  }
  return result;
}

double _sineValue(double radians) {
  return _cosineValue(radians - 3.14159 / 2);
}
