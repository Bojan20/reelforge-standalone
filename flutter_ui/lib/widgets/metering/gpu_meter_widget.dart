/// GPU-Accelerated Meter Widget
///
/// Ultimate 120fps audio level meter using CustomPainter for GPU-accelerated rendering.
///
/// Features:
/// - CustomPainter-based rendering (GPU accelerated)
/// - Gradient rendering (green → yellow → red)
/// - Peak hold with configurable decay
/// - Vertical and horizontal orientations
/// - Scale markers (-60, -40, -20, -10, -6, -3, 0 dB)
/// - Minimal CPU overhead via optimized shouldRepaint
/// - RepaintBoundary isolation for 120fps performance
/// - Smooth ballistics with configurable attack/release
/// - RMS overlay mode for loudness visualization
/// - Clip indicators with glow effect
///
/// Target: 120fps smooth rendering with < 1ms paint time

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ENUMS & TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Meter display style
enum GpuMeterStyle {
  /// Smooth gradient bar (default, fastest)
  smooth,

  /// LED-style segmented display
  segmented,

  /// VU-style with slower ballistics
  vu,
}

/// Meter orientation
enum GpuMeterOrientation {
  /// Vertical meter (standard mixer)
  vertical,

  /// Horizontal meter (transport bar, compact UI)
  horizontal,
}

/// Ballistics preset for meter response
enum GpuMeterBallistics {
  /// Peak meter: instant attack, 1.5s release (Pro Tools style)
  peak,

  /// PPM: 10ms attack, 1.5s release (EBU)
  ppm,

  /// VU: 300ms integration (analog VU)
  vu,

  /// Custom ballistics
  custom,
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════

/// Meter levels data (immutable for efficient comparison)
@immutable
class GpuMeterLevels {
  /// Peak level (0.0 = -inf, 1.0 = 0dBFS, >1.0 = clip)
  final double peak;

  /// RMS level (0.0 to 1.0+)
  final double rms;

  /// Right channel peak (for stereo)
  final double? peakR;

  /// Right channel RMS (for stereo)
  final double? rmsR;

  /// Clipping detected
  final bool clipped;

  const GpuMeterLevels({
    this.peak = 0,
    this.rms = 0,
    this.peakR,
    this.rmsR,
    this.clipped = false,
  });

  /// Create from dB values
  factory GpuMeterLevels.fromDb(double peakDb, [double? rmsDb]) {
    return GpuMeterLevels(
      peak: peakDb > -120 ? math.pow(10, peakDb / 20).toDouble() : 0,
      rms: (rmsDb ?? peakDb) > -120
          ? math.pow(10, (rmsDb ?? peakDb) / 20).toDouble()
          : 0,
      clipped: peakDb >= 0,
    );
  }

  /// Create stereo levels from dB
  factory GpuMeterLevels.stereoFromDb(
    double peakDbL,
    double peakDbR, [
    double? rmsDbL,
    double? rmsDbR,
  ]) {
    return GpuMeterLevels(
      peak: peakDbL > -120 ? math.pow(10, peakDbL / 20).toDouble() : 0,
      rms: (rmsDbL ?? peakDbL) > -120
          ? math.pow(10, (rmsDbL ?? peakDbL) / 20).toDouble()
          : 0,
      peakR: peakDbR > -120 ? math.pow(10, peakDbR / 20).toDouble() : 0,
      rmsR: (rmsDbR ?? peakDbR) > -120
          ? math.pow(10, (rmsDbR ?? peakDbR) / 20).toDouble()
          : 0,
      clipped: peakDbL >= 0 || peakDbR >= 0,
    );
  }

  static const zero = GpuMeterLevels();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GpuMeterLevels &&
          peak == other.peak &&
          rms == other.rms &&
          peakR == other.peakR &&
          rmsR == other.rmsR &&
          clipped == other.clipped;

  @override
  int get hashCode => Object.hash(peak, rms, peakR, rmsR, clipped);
}

/// Configuration for meter appearance
@immutable
class GpuMeterConfig {
  /// Minimum dB value (-60 default)
  final double minDb;

  /// Maximum dB value (+6 default)
  final double maxDb;

  /// Peak hold time in milliseconds
  final int peakHoldMs;

  /// Peak decay rate in dB per second
  final double peakDecayDbPerSec;

  /// Attack time in milliseconds (for ballistics)
  final double attackMs;

  /// Release time in milliseconds (for ballistics)
  final double releaseMs;

  /// Number of segments (for segmented style)
  final int segments;

  /// Show RMS overlay
  final bool showRms;

  /// Show scale labels
  final bool showScale;

  /// Scale label positions
  final List<double> scaleMarks;

  const GpuMeterConfig({
    this.minDb = -60,
    this.maxDb = 6,
    this.peakHoldMs = 1500,
    this.peakDecayDbPerSec = 30,
    this.attackMs = 0.1,
    this.releaseMs = 300,
    this.segments = 30,
    this.showRms = false,
    this.showScale = false,
    this.scaleMarks = const [-60, -40, -20, -10, -6, -3, 0],
  });

  /// Pro Tools-style peak meter
  /// 1.5s peak hold, 26 dB/s decay, instant attack, 300ms release
  static const proTools = GpuMeterConfig(
    minDb: -60,
    maxDb: 6,
    peakHoldMs: 1500,
    peakDecayDbPerSec: 26,
    attackMs: 0,
    releaseMs: 300,
  );

  /// EBU PPM meter
  static const ppm = GpuMeterConfig(
    minDb: -60,
    maxDb: 0,
    peakHoldMs: 1500,
    peakDecayDbPerSec: 24,
    attackMs: 10,
    releaseMs: 600,
  );

  /// VU meter
  static const vu = GpuMeterConfig(
    minDb: -40,
    maxDb: 3,
    peakHoldMs: 0,
    peakDecayDbPerSec: 0,
    attackMs: 300,
    releaseMs: 300,
    showRms: true,
  );

  /// Compact mixer — Pro Tools ballistics, no scale labels
  /// 1.5s peak hold, 26 dB/s decay, instant attack, 300ms release
  static const compact = GpuMeterConfig(
    minDb: -60,
    maxDb: 6,
    peakHoldMs: 1500,
    peakDecayDbPerSec: 26,
    attackMs: 0,
    releaseMs: 300,
    showScale: false,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// GPU METER WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// GPU-accelerated audio level meter
///
/// Usage:
/// ```dart
/// GpuMeter(
///   levels: GpuMeterLevels(peak: 0.5, rms: 0.3),
///   width: 12,
///   height: 200,
/// )
/// ```
class GpuMeter extends StatefulWidget {
  /// Current meter levels (used as fallback when peakReader is null)
  final GpuMeterLevels levels;

  /// Direct peak reader callback — called on EVERY Ticker frame (120fps).
  /// Returns (peakL, peakR) read directly from FFI/SharedMemory.
  /// When set, bypasses widget.levels.peak entirely for zero-latency metering.
  /// This is the Pro Tools / Cubase approach: meter reads audio data on its
  /// own schedule, not gated by parent widget rebuild cycles.
  final (double, double) Function()? peakReader;

  /// Meter width
  final double width;

  /// Meter height
  final double height;

  /// Display style
  final GpuMeterStyle style;

  /// Orientation
  final GpuMeterOrientation orientation;

  /// Configuration preset
  final GpuMeterConfig config;

  /// Whether meter is muted (shows no level)
  final bool muted;

  /// Stereo mode (renders L/R bars)
  final bool stereo;

  /// Callback when meter is tapped (e.g., to reset peaks)
  final VoidCallback? onTap;

  /// Background color override
  final Color? backgroundColor;

  const GpuMeter({
    super.key,
    required this.levels,
    this.peakReader,
    this.width = 12,
    this.height = 200,
    this.style = GpuMeterStyle.smooth,
    this.orientation = GpuMeterOrientation.vertical,
    this.config = const GpuMeterConfig(),
    this.muted = false,
    this.stereo = false,
    this.onTap,
    this.backgroundColor,
  });

  /// Simple mono meter
  GpuMeter.simple({
    super.key,
    required double level,
    this.peakReader,
    this.width = 8,
    this.height = 120,
    this.muted = false,
    this.onTap,
    this.backgroundColor,
  })  : levels = GpuMeterLevels(peak: level),
        style = GpuMeterStyle.smooth,
        orientation = GpuMeterOrientation.vertical,
        config = const GpuMeterConfig(),
        stereo = false;

  /// Stereo meter pair
  GpuMeter.stereo({
    super.key,
    required double peakL,
    required double peakR,
    this.peakReader,
    this.width = 24,
    this.height = 200,
    this.muted = false,
    this.onTap,
    this.backgroundColor,
  })  : levels = GpuMeterLevels(peak: peakL, peakR: peakR),
        style = GpuMeterStyle.smooth,
        orientation = GpuMeterOrientation.vertical,
        config = const GpuMeterConfig(),
        stereo = true;

  @override
  State<GpuMeter> createState() => _GpuMeterState();
}

class _GpuMeterState extends State<GpuMeter>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;

  // Smoothed values (for ballistics)
  double _smoothedL = 0;
  double _smoothedR = 0;

  // Peak hold values
  double _peakHoldL = 0;
  double _peakHoldR = 0;
  DateTime _peakHoldTimeL = DateTime.now();
  DateTime _peakHoldTimeR = DateTime.now();

  // Clip state — Pro Tools: infinite hold, click to clear
  bool _clippedL = false;
  bool _clippedR = false;

  // Last frame time for delta calculation
  Duration _lastFrameTime = Duration.zero;

  // ValueNotifier drives CustomPaint repaint WITHOUT widget rebuild.
  // setState() on every ticker frame was causing full build() traversal —
  // this approach only triggers CustomPainter.paint(), skipping the widget tree.
  late final _MeterRepaintNotifier _repaintNotifier;

  @override
  void initState() {
    super.initState();
    _repaintNotifier = _MeterRepaintNotifier();
    // Use Ticker for 120fps updates (more efficient than AnimationController)
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaintNotifier.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    // Calculate delta time for frame-rate independent updates
    final deltaMs = (elapsed - _lastFrameTime).inMicroseconds / 1000.0;
    _lastFrameTime = elapsed;

    // Skip if delta is too small or too large (first frame or pause)
    if (deltaMs < 1 || deltaMs > 100) return;

    final config = widget.config;

    // Calculate ballistics coefficients (frame-rate independent)
    final attackCoef =
        1.0 - math.exp(-deltaMs / math.max(config.attackMs, 0.01));
    final releaseCoef =
        1.0 - math.exp(-deltaMs / math.max(config.releaseMs, 1));

    // Get target levels — prefer peakReader (120fps direct FFI read) over widget props
    double targetL, targetR;
    if (widget.peakReader != null && !widget.muted) {
      try {
        final (pL, pR) = widget.peakReader!();
        targetL = pL;
        targetR = pR;
      } catch (_) {
        targetL = widget.levels.peak;
        targetR = widget.levels.peakR ?? widget.levels.peak;
      }
    } else {
      targetL = widget.muted ? 0.0 : widget.levels.peak;
      targetR =
          widget.muted ? 0.0 : (widget.levels.peakR ?? widget.levels.peak);
    }

    // Cubase-style noise floor gate threshold (~-80dB linear ≈ 0.0001)
    // Below this, meter is completely invisible — no residual flicker
    const double kNoiseFloorGate = 0.0001;

    // Apply ballistics (attack/release smoothing)
    if (targetL > _smoothedL) {
      _smoothedL += (targetL - _smoothedL) * attackCoef;
    } else {
      _smoothedL += (targetL - _smoothedL) * releaseCoef;
    }

    if (targetR > _smoothedR) {
      _smoothedR += (targetR - _smoothedR) * attackCoef;
    } else {
      _smoothedR += (targetR - _smoothedR) * releaseCoef;
    }

    // Snap to zero when below noise floor — prevents asymptotic decay residue
    if (_smoothedL < kNoiseFloorGate) _smoothedL = 0;
    if (_smoothedR < kNoiseFloorGate) _smoothedR = 0;

    // Update peak hold
    final now = DateTime.now();
    _updatePeakHold(targetL, targetR, now, deltaMs, config);
    _updateClipState(targetL, targetR);

    // Notify CustomPaint to repaint — NO setState, NO widget rebuild.
    // Only the CustomPainter.paint() method runs, skipping the entire build() tree.
    _repaintNotifier.notify();
  }

  void _updatePeakHold(
    double targetL,
    double targetR,
    DateTime now,
    double deltaMs,
    GpuMeterConfig config,
  ) {
    // Left channel
    if (targetL > _peakHoldL) {
      _peakHoldL = targetL;
      _peakHoldTimeL = now;
    } else if (config.peakHoldMs > 0) {
      final holdElapsed = now.difference(_peakHoldTimeL).inMilliseconds;
      if (holdElapsed > config.peakHoldMs) {
        // Decay peak hold
        final decayDb = config.peakDecayDbPerSec * deltaMs / 1000.0;
        final currentDb = _peakHoldL > 0
            ? 20.0 * math.log(_peakHoldL) / math.ln10
            : config.minDb;
        final newDb = math.max(config.minDb, currentDb - decayDb);
        _peakHoldL = newDb > config.minDb
            ? math.pow(10, newDb / 20.0).toDouble()
            : 0;
      }
    }

    // Right channel
    if (targetR > _peakHoldR) {
      _peakHoldR = targetR;
      _peakHoldTimeR = now;
    } else if (config.peakHoldMs > 0) {
      final holdElapsed = now.difference(_peakHoldTimeR).inMilliseconds;
      if (holdElapsed > config.peakHoldMs) {
        final decayDb = config.peakDecayDbPerSec * deltaMs / 1000.0;
        final currentDb = _peakHoldR > 0
            ? 20.0 * math.log(_peakHoldR) / math.ln10
            : config.minDb;
        final newDb = math.max(config.minDb, currentDb - decayDb);
        _peakHoldR = newDb > config.minDb
            ? math.pow(10, newDb / 20.0).toDouble()
            : 0;
      }
    }
  }

  void _updateClipState(double targetL, double targetR) {
    // Pro Tools behavior: clip indicator holds FOREVER until user clicks to clear
    if (widget.levels.clipped || targetL >= 1.0) {
      _clippedL = true;
    }
    if (widget.levels.clipped || targetR >= 1.0) {
      _clippedR = true;
    }
  }

  void _resetPeaks() {
    setState(() {
      _peakHoldL = 0;
      _peakHoldR = 0;
      _clippedL = false;
      _clippedR = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.onTap?.call();
        _resetPeaks();
      },
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(widget.width, widget.height),
          painter: _GpuMeterLivePainter(
            state: this,
            config: widget.config,
            style: widget.style,
            orientation: widget.orientation,
            stereo: widget.stereo,
            backgroundColor: widget.backgroundColor ?? FluxForgeTheme.bgDeepest,
            repaintNotifier: _repaintNotifier,
          ),
          willChange: true,
          isComplex: false,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// REPAINT NOTIFIER — triggers CustomPaint.paint() without widget rebuild
// ═══════════════════════════════════════════════════════════════════════════

class _MeterRepaintNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

// ═══════════════════════════════════════════════════════════════════════════
// LIVE METER PAINTER — reads state directly, driven by _MeterRepaintNotifier
// ═══════════════════════════════════════════════════════════════════════════

/// Reads smoothed meter values directly from [_GpuMeterState] on every paint.
/// Repaint is triggered by [_MeterRepaintNotifier], NOT by setState/build.
/// This eliminates widget tree rebuild overhead on every ticker frame.
class _GpuMeterLivePainter extends CustomPainter {
  final _GpuMeterState state;
  final GpuMeterConfig config;
  final GpuMeterStyle style;
  final GpuMeterOrientation orientation;
  final bool stereo;
  final Color backgroundColor;

  _GpuMeterLivePainter({
    required this.state,
    required this.config,
    required this.style,
    required this.orientation,
    required this.stereo,
    required this.backgroundColor,
    required _MeterRepaintNotifier repaintNotifier,
  }) : super(repaint: repaintNotifier);

  @override
  void paint(Canvas canvas, Size size) {
    // Delegate to the static painting logic in _GpuMeterPainter
    final painter = _GpuMeterPainter(
      levelL: state._smoothedL,
      levelR: stereo ? state._smoothedR : state._smoothedL,
      rmsL: state.widget.levels.rms,
      rmsR: state.widget.levels.rmsR ?? state.widget.levels.rms,
      peakHoldL: state._peakHoldL,
      peakHoldR: state._peakHoldR,
      clippedL: state._clippedL,
      clippedR: state._clippedR,
      config: config,
      style: style,
      orientation: orientation,
      stereo: stereo,
      backgroundColor: backgroundColor,
    );
    painter.paint(canvas, size);
  }

  @override
  bool shouldRepaint(_GpuMeterLivePainter oldDelegate) {
    // Always repaint when notifier fires — the notifier IS our repaint trigger.
    // The notifier only fires when meter values actually change (via _onTick).
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GPU METER PAINTER (static, used by live painter)
// ═══════════════════════════════════════════════════════════════════════════

class _GpuMeterPainter extends CustomPainter {
  final double levelL;
  final double levelR;
  final double rmsL;
  final double rmsR;
  final double peakHoldL;
  final double peakHoldR;
  final bool clippedL;
  final bool clippedR;
  final GpuMeterConfig config;
  final GpuMeterStyle style;
  final GpuMeterOrientation orientation;
  final bool stereo;
  final Color backgroundColor;

  // Pre-computed gradient (cached for performance)
  static LinearGradient? _cachedGradientV;
  static LinearGradient? _cachedGradientH;

  _GpuMeterPainter({
    required this.levelL,
    required this.levelR,
    required this.rmsL,
    required this.rmsR,
    required this.peakHoldL,
    required this.peakHoldR,
    required this.clippedL,
    required this.clippedR,
    required this.config,
    required this.style,
    required this.orientation,
    required this.stereo,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final isVertical = orientation == GpuMeterOrientation.vertical;
    final rect = Offset.zero & size;

    // Draw background
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = backgroundColor,
    );

    if (stereo) {
      _paintStereo(canvas, size, isVertical);
    } else {
      _paintMono(canvas, size, isVertical);
    }

    // Draw scale markers if enabled
    if (config.showScale) {
      _paintScaleMarkers(canvas, size, isVertical);
    }
  }

  void _paintMono(Canvas canvas, Size size, bool isVertical) {
    final rect = Offset.zero & size;

    // Draw level bar
    switch (style) {
      case GpuMeterStyle.smooth:
        _paintSmoothBar(canvas, rect, levelL, rmsL, isVertical);
        break;
      case GpuMeterStyle.segmented:
        _paintSegmentedBar(canvas, rect, levelL, isVertical);
        break;
      case GpuMeterStyle.vu:
        _paintVuBar(canvas, rect, levelL, rmsL, isVertical);
        break;
    }

    // Peak hold line
    if (peakHoldL > 0.001) {
      _paintPeakHold(canvas, rect, peakHoldL, isVertical);
    }

    // Clip indicator
    if (clippedL) {
      _paintClipIndicator(canvas, rect, isVertical);
    }
  }

  void _paintStereo(Canvas canvas, Size size, bool isVertical) {
    final gap = 2.0;
    final barWidth = isVertical ? (size.width - gap) / 2 : size.width;
    final barHeight = isVertical ? size.height : (size.height - gap) / 2;

    // Left meter rect
    final leftRect = isVertical
        ? Rect.fromLTWH(0, 0, barWidth, size.height)
        : Rect.fromLTWH(0, 0, size.width, barHeight);

    // Right meter rect
    final rightRect = isVertical
        ? Rect.fromLTWH(barWidth + gap, 0, barWidth, size.height)
        : Rect.fromLTWH(0, barHeight + gap, size.width, barHeight);

    // Paint left channel
    _paintSmoothBar(canvas, leftRect, levelL, rmsL, isVertical);
    if (peakHoldL > 0.001) {
      _paintPeakHold(canvas, leftRect, peakHoldL, isVertical);
    }
    if (clippedL) {
      _paintClipIndicator(canvas, leftRect, isVertical);
    }

    // Paint right channel
    _paintSmoothBar(canvas, rightRect, levelR, rmsR, isVertical);
    if (peakHoldR > 0.001) {
      _paintPeakHold(canvas, rightRect, peakHoldR, isVertical);
    }
    if (clippedR) {
      _paintClipIndicator(canvas, rightRect, isVertical);
    }
  }

  void _paintSmoothBar(
    Canvas canvas,
    Rect rect,
    double level,
    double rms,
    bool isVertical,
  ) {
    // Cubase-style: completely invisible below noise floor (~-80dB)
    if (level < 0.0001) return;

    final normalizedLevel = _linearToNormalized(level);
    final gradient = _getGradient(isVertical);

    final levelRect = isVertical
        ? Rect.fromLTWH(
            rect.left + 1,
            rect.top + rect.height * (1 - normalizedLevel),
            rect.width - 2,
            rect.height * normalizedLevel,
          )
        : Rect.fromLTWH(
            rect.left,
            rect.top + 1,
            rect.width * normalizedLevel,
            rect.height - 2,
          );

    // Main level bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(levelRect, const Radius.circular(1)),
      Paint()..shader = gradient.createShader(rect),
    );

    // Glow at peak
    final glowColor = _getColorForLevel(normalizedLevel);
    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    if (isVertical) {
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left + 1,
          rect.top + rect.height * (1 - normalizedLevel),
          rect.width - 2,
          3,
        ),
        glowPaint,
      );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left + rect.width * normalizedLevel - 3,
          rect.top + 1,
          3,
          rect.height - 2,
        ),
        glowPaint,
      );
    }

    // RMS overlay (if enabled)
    if (config.showRms && rms > 0) {
      final normalizedRms = _linearToNormalized(rms);
      final rmsRect = isVertical
          ? Rect.fromLTWH(
              rect.left + rect.width * 0.3,
              rect.top + rect.height * (1 - normalizedRms),
              rect.width * 0.4,
              rect.height * normalizedRms,
            )
          : Rect.fromLTWH(
              rect.left,
              rect.top + rect.height * 0.3,
              rect.width * normalizedRms,
              rect.height * 0.4,
            );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rmsRect, const Radius.circular(1)),
        Paint()..color = FluxForgeTheme.accentBlue.withValues(alpha: 0.6),
      );
    }
  }

  void _paintSegmentedBar(
    Canvas canvas,
    Rect rect,
    double level,
    bool isVertical,
  ) {
    final segments = config.segments;
    const gap = 1.0;
    final segmentSize = isVertical
        ? (rect.height - gap * (segments - 1)) / segments
        : (rect.width - gap * (segments - 1)) / segments;

    final normalizedLevel = _linearToNormalized(level);
    final activeSegments = (normalizedLevel * segments).ceil();

    for (int i = 0; i < segments; i++) {
      final isActive = i < activeSegments;
      final segmentLevel = i / segments;
      final color = _getColorForLevel(segmentLevel);

      final paint = Paint()
        ..color = isActive ? color : color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;

      final segmentRect = isVertical
          ? Rect.fromLTWH(
              rect.left + 1,
              rect.top + rect.height - (i + 1) * (segmentSize + gap) + gap,
              rect.width - 2,
              segmentSize,
            )
          : Rect.fromLTWH(
              rect.left + i * (segmentSize + gap),
              rect.top + 1,
              segmentSize,
              rect.height - 2,
            );

      canvas.drawRRect(
        RRect.fromRectAndRadius(segmentRect, const Radius.circular(1)),
        paint,
      );
    }
  }

  void _paintVuBar(
    Canvas canvas,
    Rect rect,
    double level,
    double rms,
    bool isVertical,
  ) {
    // VU meters primarily show RMS with peak overlay
    if (rms > 0) {
      final normalizedRms = _linearToNormalized(rms);

      final rmsRect = isVertical
          ? Rect.fromLTWH(
              rect.left + 2,
              rect.top + rect.height * (1 - normalizedRms),
              rect.width - 4,
              rect.height * normalizedRms,
            )
          : Rect.fromLTWH(
              rect.left,
              rect.top + 2,
              rect.width * normalizedRms,
              rect.height - 4,
            );

      // Warm VU color
      canvas.drawRRect(
        RRect.fromRectAndRadius(rmsRect, const Radius.circular(2)),
        Paint()..color = const Color(0xFFFFCC00),
      );
    }

    // Peak indicator (thin line)
    if (level > 0) {
      final normalizedPeak = _linearToNormalized(level);
      final peakPaint = Paint()
        ..color = level > 1.0 ? FluxForgeTheme.accentRed : Colors.white
        ..strokeWidth = 2;

      if (isVertical) {
        final y = rect.top + rect.height * (1 - normalizedPeak);
        canvas.drawLine(
          Offset(rect.left + 2, y),
          Offset(rect.right - 2, y),
          peakPaint,
        );
      } else {
        final x = rect.left + rect.width * normalizedPeak;
        canvas.drawLine(
          Offset(x, rect.top + 2),
          Offset(x, rect.bottom - 2),
          peakPaint,
        );
      }
    }
  }

  void _paintPeakHold(
    Canvas canvas,
    Rect rect,
    double peakHold,
    bool isVertical,
  ) {
    final normalized = _linearToNormalized(peakHold);
    final color = peakHold > 1.0 ? FluxForgeTheme.accentRed : Colors.white;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;

    if (isVertical) {
      final y = rect.top + rect.height * (1 - normalized);
      canvas.drawLine(
        Offset(rect.left + 1, y),
        Offset(rect.right - 1, y),
        paint,
      );
    } else {
      final x = rect.left + rect.width * normalized;
      canvas.drawLine(
        Offset(x, rect.top + 1),
        Offset(x, rect.bottom - 1),
        paint,
      );
    }
  }

  void _paintClipIndicator(Canvas canvas, Rect rect, bool isVertical) {
    final clipRect = isVertical
        ? Rect.fromLTWH(rect.left, rect.top, rect.width, 4)
        : Rect.fromLTWH(rect.right - 4, rect.top, 4, rect.height);

    // Solid clip indicator
    canvas.drawRect(clipRect, Paint()..color = FluxForgeTheme.accentRed);

    // Glow effect
    canvas.drawRect(
      clipRect,
      Paint()
        ..color = FluxForgeTheme.accentRed.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  void _paintScaleMarkers(Canvas canvas, Size size, bool isVertical) {
    final textStyle = ui.TextStyle(
      color: FluxForgeTheme.textTertiary,
      fontSize: 8,
    );

    for (final db in config.scaleMarks) {
      final normalized = _dbToNormalized(db);

      // Draw tick mark
      final tickPaint = Paint()
        ..color = FluxForgeTheme.textTertiary.withValues(alpha: 0.4)
        ..strokeWidth = 1;

      if (isVertical) {
        final y = size.height * (1 - normalized);
        canvas.drawLine(
          Offset(0, y),
          Offset(3, y),
          tickPaint,
        );

        // Draw label (on left side)
        if (config.showScale) {
          final label = db == 0 ? '0' : db.toInt().toString();
          final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 8))
            ..pushStyle(textStyle)
            ..addText(label);
          final paragraph = builder.build()
            ..layout(const ui.ParagraphConstraints(width: 20));
          // Labels would be drawn to the left of the meter
        }
      } else {
        final x = size.width * normalized;
        canvas.drawLine(
          Offset(x, size.height - 3),
          Offset(x, size.height),
          tickPaint,
        );
      }
    }
  }

  double _linearToNormalized(double linear) {
    if (linear <= 0) return 0;
    final db = 20.0 * math.log(linear) / math.ln10;
    return _dbToNormalized(db);
  }

  double _dbToNormalized(double db) {
    return ((db - config.minDb) / (config.maxDb - config.minDb)).clamp(0.0, 1.0);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Pro Tools 3-zone color scheme:
  //   Green (#22B14C → #55CC55)  — safe zone (up to -12 dB, ~73% of range)
  //   Yellow (#CCCC00 → #FFCC00) — caution (-12 dB to -3 dB)
  //   Red (#FF2020 → #FF4040)    — danger (-3 dB to clip)
  //
  // dB-to-normalized breakpoints (with minDb=-60, maxDb=6):
  //   -12 dB → (−12 − (−60)) / (6 − (−60)) = 48/66 ≈ 0.727
  //    -3 dB → (−3 − (−60)) / (6 − (−60)) = 57/66 ≈ 0.864
  //     0 dB → (0 − (−60)) / (6 − (−60))  = 60/66 ≈ 0.909
  // ═══════════════════════════════════════════════════════════════════════

  static const _kGreen = Color(0xFF22B14C);
  static const _kGreenBright = Color(0xFF55CC55);
  static const _kYellow = Color(0xFFCCCC00);
  static const _kYellowBright = Color(0xFFFFCC00);
  static const _kRed = Color(0xFFFF2020);
  static const _kRedBright = Color(0xFFFF4040);

  // Normalized positions for zone boundaries
  static const _kYellowStart = 0.727; // -12 dB
  static const _kRedStart = 0.864; // -3 dB

  LinearGradient _getGradient(bool isVertical) {
    if (isVertical) {
      _cachedGradientV ??= const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          _kGreen,
          _kGreenBright,
          _kYellow,
          _kYellowBright,
          _kRed,
          _kRedBright,
        ],
        stops: [
          0.0,
          _kYellowStart - 0.01, // green zone
          _kYellowStart,         // yellow starts
          _kRedStart - 0.01,     // yellow zone
          _kRedStart,            // red starts
          1.0,                   // red zone
        ],
      );
      return _cachedGradientV!;
    } else {
      _cachedGradientH ??= const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          _kGreen,
          _kGreenBright,
          _kYellow,
          _kYellowBright,
          _kRed,
          _kRedBright,
        ],
        stops: [
          0.0,
          _kYellowStart - 0.01,
          _kYellowStart,
          _kRedStart - 0.01,
          _kRedStart,
          1.0,
        ],
      );
      return _cachedGradientH!;
    }
  }

  Color _getColorForLevel(double normalized) {
    if (normalized < _kYellowStart) {
      return Color.lerp(
        _kGreen,
        _kGreenBright,
        normalized / _kYellowStart,
      )!;
    } else if (normalized < _kRedStart) {
      return Color.lerp(
        _kYellow,
        _kYellowBright,
        (normalized - _kYellowStart) / (_kRedStart - _kYellowStart),
      )!;
    } else {
      return Color.lerp(
        _kRed,
        _kRedBright,
        (normalized - _kRedStart) / (1.0 - _kRedStart),
      )!;
    }
  }

  @override
  bool shouldRepaint(_GpuMeterPainter oldDelegate) {
    // Optimized comparison - only repaint if levels changed significantly
    // Threshold of 0.001 = ~0.08dB - imperceptible visually
    const threshold = 0.001;

    return (levelL - oldDelegate.levelL).abs() > threshold ||
        (levelR - oldDelegate.levelR).abs() > threshold ||
        (peakHoldL - oldDelegate.peakHoldL).abs() > threshold ||
        (peakHoldR - oldDelegate.peakHoldR).abs() > threshold ||
        clippedL != oldDelegate.clippedL ||
        clippedR != oldDelegate.clippedR ||
        style != oldDelegate.style ||
        stereo != oldDelegate.stereo;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEREO METER BAR (Convenience Widget)
// ═══════════════════════════════════════════════════════════════════════════

/// Stereo meter with L/R labels
class GpuStereoMeter extends StatelessWidget {
  final double peakL;
  final double peakR;
  final double? rmsL;
  final double? rmsR;
  final double width;
  final double height;
  final bool showLabels;
  final bool muted;
  final VoidCallback? onTap;

  const GpuStereoMeter({
    super.key,
    required this.peakL,
    required this.peakR,
    this.rmsL,
    this.rmsR,
    this.width = 32,
    this.height = 200,
    this.showLabels = true,
    this.muted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        children: [
          if (showLabels)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text('L', style: FluxForgeTheme.label),
                  Text('R', style: FluxForgeTheme.label),
                ],
              ),
            ),
          Expanded(
            child: GpuMeter(
              levels: GpuMeterLevels(
                peak: peakL,
                peakR: peakR,
                rms: rmsL ?? 0,
                rmsR: rmsR ?? 0,
              ),
              width: width,
              height: showLabels ? height - 16 : height,
              stereo: true,
              muted: muted,
              onTap: onTap,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HORIZONTAL METER (for transport bar)
// ═══════════════════════════════════════════════════════════════════════════

/// Horizontal meter for compact displays
class GpuHorizontalMeter extends StatelessWidget {
  final double level;
  final double? peakHold;
  final double width;
  final double height;
  final bool showScale;

  const GpuHorizontalMeter({
    super.key,
    required this.level,
    this.peakHold,
    this.width = 200,
    this.height = 12,
    this.showScale = false,
  });

  @override
  Widget build(BuildContext context) {
    return GpuMeter(
      levels: GpuMeterLevels(peak: level),
      width: width,
      height: height,
      orientation: GpuMeterOrientation.horizontal,
      config: GpuMeterConfig(
        showScale: showScale,
        scaleMarks: const [-40, -20, -10, -6, -3, 0],
      ),
    );
  }
}
