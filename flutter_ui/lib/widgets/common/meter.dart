/// Unified Audio Meter Widget
///
/// Professional audio level meter combining:
/// - Peak and RMS display modes
/// - Smooth or LED-segmented rendering
/// - Peak hold with configurable decay
/// - Clip indicator with glow effect
/// - Vertical and horizontal orientation
/// - Stereo L/R metering
/// - dB scale markings
/// - GPU-accelerated CustomPainter

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

// ════════════════════════════════════════════════════════════════════════════
// TYPES
// ════════════════════════════════════════════════════════════════════════════

/// Meter display style
enum MeterStyle {
  /// Smooth gradient bar
  smooth,
  /// LED-style segments
  segmented,
  /// Vintage VU style (slower ballistics)
  vu,
}

/// Meter display mode
enum MeterMode {
  /// Peak level only
  peak,
  /// RMS level only
  rms,
  /// Both peak and RMS overlaid
  both,
}

/// Audio levels data class
class AudioLevels {
  /// Peak level (0.0 to 1.0+)
  final double peak;
  /// RMS level (0.0 to 1.0+)
  final double rms;
  /// Peak level in dB
  final double peakDb;
  /// RMS level in dB
  final double rmsDb;
  /// Stereo left peak (optional)
  final double? peakL;
  /// Stereo right peak (optional)
  final double? peakR;

  const AudioLevels({
    this.peak = 0,
    this.rms = 0,
    this.peakDb = -60,
    this.rmsDb = -60,
    this.peakL,
    this.peakR,
  });

  factory AudioLevels.zero() => const AudioLevels();

  factory AudioLevels.fromDb(double peakDb, [double? rmsDb]) {
    return AudioLevels(
      peak: peakDb > -120 ? math.pow(10, peakDb / 20).toDouble() : 0,
      rms: (rmsDb ?? peakDb) > -120 ? math.pow(10, (rmsDb ?? peakDb) / 20).toDouble() : 0,
      peakDb: peakDb,
      rmsDb: rmsDb ?? peakDb,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ════════════════════════════════════════════════════════════════════════════

const _scaleMarks = [-60.0, -48.0, -36.0, -24.0, -18.0, -12.0, -6.0, -3.0, 0.0, 3.0, 6.0];

// ════════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ════════════════════════════════════════════════════════════════════════════

class Meter extends StatefulWidget {
  /// Level in dB (if using simple API)
  final double? levelDb;

  /// Full audio levels (if using advanced API)
  final AudioLevels? levels;

  /// External peak hold value in dB
  final double? peakHoldDb;

  /// Whether clipping is detected
  final bool isClipping;

  /// Meter orientation
  final Axis orientation;

  /// Visual style
  final MeterStyle style;

  /// Display mode
  final MeterMode mode;

  /// Stereo pair display
  final bool stereo;

  /// Right channel level in dB (for stereo)
  final double? rightLevelDb;

  /// Width of the meter
  final double width;

  /// Height of the meter
  final double height;

  /// Minimum dB value
  final double minDb;

  /// Maximum dB value
  final double maxDb;

  /// Number of LED segments (for segmented style)
  final int segments;

  /// Show dB scale labels
  final bool showScale;

  /// Peak hold time in milliseconds
  final double peakHoldTime;

  /// Peak decay rate in dB per frame
  final double peakDecayRate;

  /// Background color
  final Color? backgroundColor;

  /// Callback when meter is clicked (e.g., to reset peak hold)
  final VoidCallback? onTap;

  const Meter({
    super.key,
    this.levelDb,
    this.levels,
    this.peakHoldDb,
    this.isClipping = false,
    this.orientation = Axis.vertical,
    this.style = MeterStyle.smooth,
    this.mode = MeterMode.peak,
    this.stereo = false,
    this.rightLevelDb,
    this.width = 8,
    this.height = 120,
    this.minDb = -60,
    this.maxDb = 6,
    this.segments = 30,
    this.showScale = false,
    this.peakHoldTime = 1500,
    this.peakDecayRate = 0.5,
    this.backgroundColor,
    this.onTap,
  });

  /// Simple vertical meter
  const Meter.simple({
    super.key,
    required double level,
    double? peakHold,
    bool clipping = false,
    double thickness = 8,
    double height = 100,
  }) : levelDb = level,
       levels = null,
       peakHoldDb = peakHold,
       isClipping = clipping,
       orientation = Axis.vertical,
       style = MeterStyle.smooth,
       mode = MeterMode.peak,
       stereo = false,
       rightLevelDb = null,
       width = thickness,
       this.height = height,
       minDb = -60,
       maxDb = 6,
       segments = 30,
       showScale = false,
       peakHoldTime = 1500,
       peakDecayRate = 0.5,
       backgroundColor = null,
       onTap = null;

  /// Stereo meter pair
  const Meter.stereo({
    super.key,
    required double leftDb,
    required double rightDb,
    double? leftPeak,
    double? rightPeak,
    bool leftClip = false,
    bool rightClip = false,
    double width = 24,
    double height = 120,
    bool showLabels = true,
  }) : levelDb = leftDb,
       levels = null,
       peakHoldDb = leftPeak,
       isClipping = leftClip,
       orientation = Axis.vertical,
       style = MeterStyle.smooth,
       mode = MeterMode.peak,
       stereo = true,
       rightLevelDb = rightDb,
       this.width = width,
       this.height = height,
       minDb = -60,
       maxDb = 6,
       segments = 30,
       showScale = showLabels,
       peakHoldTime = 1500,
       peakDecayRate = 0.5,
       backgroundColor = null,
       onTap = null;

  @override
  State<Meter> createState() => _MeterState();
}

class _MeterState extends State<Meter> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _peakHoldL = -60;
  double _peakHoldR = -60;
  DateTime _peakHoldTimeL = DateTime.now();
  DateTime _peakHoldTimeR = DateTime.now();
  bool _clipL = false;
  bool _clipR = false;
  DateTime _clipTimeL = DateTime.now();
  DateTime _clipTimeR = DateTime.now();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16), // ~60fps
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _getCurrentLevelDb() {
    if (widget.levels != null) {
      return widget.mode == MeterMode.rms
          ? widget.levels!.rmsDb
          : widget.levels!.peakDb;
    }
    return widget.levelDb ?? widget.minDb;
  }

  double _getCurrentRightDb() {
    if (widget.levels?.peakR != null) {
      final peakR = widget.levels!.peakR!;
      return peakR > 0 ? 20 * math.log(peakR) / math.ln10 : widget.minDb;
    }
    return widget.rightLevelDb ?? _getCurrentLevelDb();
  }

  void _updatePeakHold() {
    final now = DateTime.now();
    final levelDbL = _getCurrentLevelDb();
    final levelDbR = _getCurrentRightDb();

    // Left channel peak hold
    if (widget.peakHoldDb != null) {
      _peakHoldL = widget.peakHoldDb!;
    } else {
      if (levelDbL > _peakHoldL) {
        _peakHoldL = levelDbL;
        _peakHoldTimeL = now;
      } else if (now.difference(_peakHoldTimeL).inMilliseconds > widget.peakHoldTime) {
        _peakHoldL = math.max(widget.minDb, _peakHoldL - widget.peakDecayRate);
      }
    }

    // Right channel peak hold
    if (widget.stereo) {
      if (levelDbR > _peakHoldR) {
        _peakHoldR = levelDbR;
        _peakHoldTimeR = now;
      } else if (now.difference(_peakHoldTimeR).inMilliseconds > widget.peakHoldTime) {
        _peakHoldR = math.max(widget.minDb, _peakHoldR - widget.peakDecayRate);
      }
    }

    // Clip detection
    if (widget.isClipping || levelDbL >= widget.maxDb - 0.1) {
      _clipL = true;
      _clipTimeL = now;
    } else if (now.difference(_clipTimeL).inMilliseconds > 2000) {
      _clipL = false;
    }

    if (widget.stereo && (levelDbR >= widget.maxDb - 0.1)) {
      _clipR = true;
      _clipTimeR = now;
    } else if (now.difference(_clipTimeR).inMilliseconds > 2000) {
      _clipR = false;
    }
  }

  double _dbToNormalized(double db) {
    return ((db - widget.minDb) / (widget.maxDb - widget.minDb)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.onTap?.call();
        // Reset peak hold on tap
        setState(() {
          _peakHoldL = widget.minDb;
          _peakHoldR = widget.minDb;
          _clipL = false;
          _clipR = false;
        });
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          _updatePeakHold();

          if (widget.stereo) {
            return _buildStereoMeter();
          }

          return RepaintBoundary(
            child: CustomPaint(
              size: Size(widget.width, widget.height),
              painter: _MeterPainter(
                level: _dbToNormalized(_getCurrentLevelDb()),
                rmsLevel: widget.mode == MeterMode.both && widget.levels != null
                    ? _dbToNormalized(widget.levels!.rmsDb)
                    : null,
                peakHold: _dbToNormalized(_peakHoldL),
                isClipping: _clipL,
                orientation: widget.orientation,
                style: widget.style,
                mode: widget.mode,
                segments: widget.segments,
                backgroundColor: widget.backgroundColor ?? ReelForgeTheme.bgDeepest,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStereoMeter() {
    final isVertical = widget.orientation == Axis.vertical;
    final meterThickness = isVertical
        ? (widget.width - 4) / 2
        : (widget.height - 4) / 2;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Column(
        children: [
          if (widget.showScale && isVertical)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text('L', style: ReelForgeTheme.label),
                  Text('R', style: ReelForgeTheme.label),
                ],
              ),
            ),
          Expanded(
            child: Row(
              children: [
                // Left meter
                Expanded(
                  child: CustomPaint(
                    size: Size(meterThickness, double.infinity),
                    painter: _MeterPainter(
                      level: _dbToNormalized(_getCurrentLevelDb()),
                      peakHold: _dbToNormalized(_peakHoldL),
                      isClipping: _clipL,
                      orientation: widget.orientation,
                      style: widget.style,
                      mode: widget.mode,
                      segments: widget.segments,
                      backgroundColor: widget.backgroundColor ?? ReelForgeTheme.bgDeepest,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                // Right meter
                Expanded(
                  child: CustomPaint(
                    size: Size(meterThickness, double.infinity),
                    painter: _MeterPainter(
                      level: _dbToNormalized(_getCurrentRightDb()),
                      peakHold: _dbToNormalized(_peakHoldR),
                      isClipping: _clipR,
                      orientation: widget.orientation,
                      style: widget.style,
                      mode: widget.mode,
                      segments: widget.segments,
                      backgroundColor: widget.backgroundColor ?? ReelForgeTheme.bgDeepest,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTER
// ════════════════════════════════════════════════════════════════════════════

class _MeterPainter extends CustomPainter {
  final double level;
  final double? rmsLevel;
  final double peakHold;
  final bool isClipping;
  final Axis orientation;
  final MeterStyle style;
  final MeterMode mode;
  final int segments;
  final Color backgroundColor;

  _MeterPainter({
    required this.level,
    this.rmsLevel,
    required this.peakHold,
    required this.isClipping,
    required this.orientation,
    required this.style,
    required this.mode,
    required this.segments,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final isVertical = orientation == Axis.vertical;
    final rect = Offset.zero & size;

    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = backgroundColor,
    );

    // Choose rendering style
    switch (style) {
      case MeterStyle.smooth:
        _drawSmoothMeter(canvas, size, isVertical);
        break;
      case MeterStyle.segmented:
      case MeterStyle.vu:
        _drawSegmentedMeter(canvas, size, isVertical);
        break;
    }

    // Peak hold indicator
    if (peakHold > 0.01) {
      _drawPeakHold(canvas, size, isVertical);
    }

    // Clip indicator
    if (isClipping) {
      _drawClipIndicator(canvas, size, isVertical);
    }
  }

  void _drawSmoothMeter(Canvas canvas, Size size, bool isVertical) {
    if (level <= 0) return;

    final gradient = _createGradient(isVertical);

    final levelRect = isVertical
        ? Rect.fromLTWH(0, size.height * (1 - level), size.width, size.height * level)
        : Rect.fromLTWH(0, 0, size.width * level, size.height);

    final paint = Paint()
      ..shader = gradient.createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(levelRect, const Radius.circular(2)),
      paint,
    );

    // Glow at top
    final glowPaint = Paint()
      ..color = _getColorForLevel(level).withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    if (isVertical) {
      canvas.drawRect(
        Rect.fromLTWH(0, size.height * (1 - level), size.width, 4),
        glowPaint,
      );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(size.width * level - 4, 0, 4, size.height),
        glowPaint,
      );
    }

    // RMS overlay (if both mode)
    if (rmsLevel != null && rmsLevel! > 0) {
      final rmsRect = isVertical
          ? Rect.fromLTWH(
              size.width * 0.25,
              size.height * (1 - rmsLevel!),
              size.width * 0.5,
              size.height * rmsLevel!,
            )
          : Rect.fromLTWH(
              0,
              size.height * 0.25,
              size.width * rmsLevel!,
              size.height * 0.5,
            );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rmsRect, const Radius.circular(1)),
        Paint()..color = ReelForgeTheme.accentBlue.withValues(alpha: 0.7),
      );
    }
  }

  void _drawSegmentedMeter(Canvas canvas, Size size, bool isVertical) {
    const gap = 1.0;
    final segmentSize = isVertical
        ? (size.height - gap * (segments - 1)) / segments
        : (size.width - gap * (segments - 1)) / segments;

    final activeSegments = (level * segments).ceil();

    for (int i = 0; i < segments; i++) {
      final isActive = i < activeSegments;
      final segmentLevel = i / segments;
      final color = _getColorForLevel(segmentLevel);

      final paint = Paint()
        ..color = isActive ? color : color.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill;

      final segmentRect = isVertical
          ? Rect.fromLTWH(
              0,
              size.height - (i + 1) * (segmentSize + gap) + gap,
              size.width,
              segmentSize,
            )
          : Rect.fromLTWH(
              i * (segmentSize + gap),
              0,
              segmentSize,
              size.height,
            );

      canvas.drawRRect(
        RRect.fromRectAndRadius(segmentRect, const Radius.circular(1)),
        paint,
      );
    }
  }

  void _drawPeakHold(Canvas canvas, Size size, bool isVertical) {
    final paint = Paint()
      ..color = ReelForgeTheme.textPrimary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (isVertical) {
      final y = size.height * (1 - peakHold);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    } else {
      final x = size.width * peakHold;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  void _drawClipIndicator(Canvas canvas, Size size, bool isVertical) {
    final clipRect = isVertical
        ? Rect.fromLTWH(0, 0, size.width, 4)
        : Rect.fromLTWH(size.width - 4, 0, 4, size.height);

    canvas.drawRect(clipRect, Paint()..color = ReelForgeTheme.accentRed);

    // Glow
    canvas.drawRect(
      clipRect,
      Paint()
        ..color = ReelForgeTheme.accentRed.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  LinearGradient _createGradient(bool isVertical) {
    final colors = [
      ReelForgeTheme.accentCyan,
      ReelForgeTheme.accentGreen,
      const Color(0xFFFFFF40),
      ReelForgeTheme.accentOrange,
      ReelForgeTheme.accentRed,
    ];
    const stops = [0.0, 0.5, 0.7, 0.85, 1.0];

    return isVertical
        ? LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: colors,
            stops: stops,
          )
        : LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: colors,
            stops: stops,
          );
  }

  Color _getColorForLevel(double lvl) {
    if (lvl < 0.5) {
      return Color.lerp(ReelForgeTheme.accentCyan, ReelForgeTheme.accentGreen, lvl * 2)!;
    } else if (lvl < 0.7) {
      return Color.lerp(ReelForgeTheme.accentGreen, const Color(0xFFFFFF40), (lvl - 0.5) * 5)!;
    } else if (lvl < 0.85) {
      return Color.lerp(const Color(0xFFFFFF40), ReelForgeTheme.accentOrange, (lvl - 0.7) * 6.67)!;
    } else {
      return Color.lerp(ReelForgeTheme.accentOrange, ReelForgeTheme.accentRed, (lvl - 0.85) * 6.67)!;
    }
  }

  @override
  bool shouldRepaint(_MeterPainter oldDelegate) =>
      level != oldDelegate.level ||
      rmsLevel != oldDelegate.rmsLevel ||
      peakHold != oldDelegate.peakHold ||
      isClipping != oldDelegate.isClipping;
}

// ════════════════════════════════════════════════════════════════════════════
// PRESETS
// ════════════════════════════════════════════════════════════════════════════

class MeterPreset {
  final double minDb;
  final double maxDb;
  final MeterMode mode;
  final MeterStyle style;

  const MeterPreset({
    required this.minDb,
    required this.maxDb,
    required this.mode,
    required this.style,
  });

  static const standard = MeterPreset(
    minDb: -60,
    maxDb: 6,
    mode: MeterMode.peak,
    style: MeterStyle.smooth,
  );

  static const broadcast = MeterPreset(
    minDb: -60,
    maxDb: 0,
    mode: MeterMode.both,
    style: MeterStyle.segmented,
  );

  static const vintage = MeterPreset(
    minDb: -40,
    maxDb: 3,
    mode: MeterMode.rms,
    style: MeterStyle.vu,
  );
}

// ════════════════════════════════════════════════════════════════════════════
// LEGACY COMPATIBILITY
// ════════════════════════════════════════════════════════════════════════════

/// Legacy AudioMeter compatibility wrapper
@Deprecated('Use Meter instead')
class AudioMeter extends Meter {
  const AudioMeter({
    super.key,
    required double levelDb,
    double? peakHoldDb,
    bool isClipping = false,
    Axis orientation = Axis.vertical,
    double thickness = 8,
    bool showScale = false,
    int? segments,
  }) : super(
         levelDb: levelDb,
         peakHoldDb: peakHoldDb,
         isClipping: isClipping,
         orientation: orientation,
         width: thickness,
         style: segments != null ? MeterStyle.segmented : MeterStyle.smooth,
         segments: segments ?? 30,
         showScale: showScale,
       );
}

/// Legacy StereoMeter compatibility wrapper
@Deprecated('Use Meter.stereo instead')
class StereoMeter extends StatelessWidget {
  final double leftDb;
  final double rightDb;
  final double? leftPeakDb;
  final double? rightPeakDb;
  final bool leftClipping;
  final bool rightClipping;
  final double width;
  final double height;
  final bool showLabels;

  const StereoMeter({
    super.key,
    required this.leftDb,
    required this.rightDb,
    this.leftPeakDb,
    this.rightPeakDb,
    this.leftClipping = false,
    this.rightClipping = false,
    this.width = 24,
    this.height = 120,
    this.showLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    return Meter(
      levelDb: leftDb,
      rightLevelDb: rightDb,
      peakHoldDb: leftPeakDb,
      isClipping: leftClipping,
      stereo: true,
      width: width,
      height: height,
      showScale: showLabels,
    );
  }
}
