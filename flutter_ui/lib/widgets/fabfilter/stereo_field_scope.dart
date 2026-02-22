/// Enhanced Stereo Field Scope — iZotope Ozone Level
///
/// Professional vectorscope/stereo field visualization:
/// - Trail buffer (ring buffer of L/R peak snapshots for persistence/decay)
/// - Glow effects on signal dots
/// - Phase state classification with color-coded indicator
/// - Stereo field ellipse with rotation/pan/balance
/// - Per-band correlation overlay (multiband mode)
///
/// Reusable across both single-band and multiband imager panels.

import 'dart:math' as math;
import 'dart:collection';
import 'package:flutter/material.dart';
import 'fabfilter_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PHASE STATE
// ═══════════════════════════════════════════════════════════════════════════

enum StereoPhaseState {
  mono,        // correlation > 0.85
  narrow,      // correlation 0.5–0.85
  stereo,      // correlation 0.0–0.5
  wide,        // correlation -0.3–0.0
  phaseIssue,  // correlation < -0.3
}

StereoPhaseState classifyPhaseState(double correlation) {
  if (correlation > 0.85) return StereoPhaseState.mono;
  if (correlation > 0.5) return StereoPhaseState.narrow;
  if (correlation > 0.0) return StereoPhaseState.stereo;
  if (correlation > -0.3) return StereoPhaseState.wide;
  return StereoPhaseState.phaseIssue;
}

String phaseStateLabel(StereoPhaseState state) {
  return switch (state) {
    StereoPhaseState.mono => 'MONO',
    StereoPhaseState.narrow => 'NARROW',
    StereoPhaseState.stereo => 'STEREO',
    StereoPhaseState.wide => 'WIDE',
    StereoPhaseState.phaseIssue => 'PHASE!',
  };
}

Color phaseStateColor(StereoPhaseState state) {
  return switch (state) {
    StereoPhaseState.mono => FabFilterColors.blue,
    StereoPhaseState.narrow => FabFilterColors.cyan,
    StereoPhaseState.stereo => FabFilterColors.green,
    StereoPhaseState.wide => FabFilterColors.yellow,
    StereoPhaseState.phaseIssue => FabFilterColors.red,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// TRAIL SAMPLE — a snapshot of L/R peak values for persistence effect
// ═══════════════════════════════════════════════════════════════════════════

class _TrailSample {
  final double peakL;
  final double peakR;
  final double age; // 0.0 = newest, 1.0 = oldest (computed during paint)

  const _TrailSample(this.peakL, this.peakR, [this.age = 0.0]);
}

// ═══════════════════════════════════════════════════════════════════════════
// STEREO FIELD SCOPE WIDGET (StatefulWidget for trail buffer management)
// ═══════════════════════════════════════════════════════════════════════════

class StereoFieldScope extends StatefulWidget {
  /// Left channel peak level (0.0–1.0+)
  final double peakL;

  /// Right channel peak level (0.0–1.0+)
  final double peakR;

  /// L/R correlation (-1.0 to +1.0)
  final double correlation;

  /// Stereo width (0=mono, 1=stereo, 2=wide)
  final double width;

  /// Pan position (-1 to +1)
  final double pan;

  /// Balance position (-1 to +1)
  final double balance;

  /// Rotation in degrees
  final double rotationDeg;

  /// Which processing modules are enabled
  final bool enableWidth;
  final bool enablePanner;
  final bool enableBalance;
  final bool enableRotation;

  /// Accent color (typically FabFilterColors.cyan)
  final Color accent;

  /// Per-band correlations for multiband overlay (optional)
  final List<double>? bandCorrelations;

  /// Number of active bands (for multiband overlay)
  final int? numBands;

  /// Band colors (for multiband overlay)
  final List<Color>? bandColors;

  /// Selected band index (for multiband highlight)
  final int? selectedBand;

  /// Trail buffer size (number of history samples)
  final int trailLength;

  /// Show phase state badge
  final bool showPhaseState;

  const StereoFieldScope({
    super.key,
    required this.peakL,
    required this.peakR,
    required this.correlation,
    this.width = 1.0,
    this.pan = 0.0,
    this.balance = 0.0,
    this.rotationDeg = 0.0,
    this.enableWidth = true,
    this.enablePanner = false,
    this.enableBalance = false,
    this.enableRotation = false,
    this.accent = FabFilterColors.cyan,
    this.bandCorrelations,
    this.numBands,
    this.bandColors,
    this.selectedBand,
    this.trailLength = 48,
    this.showPhaseState = true,
  });

  @override
  State<StereoFieldScope> createState() => _StereoFieldScopeState();
}

class _StereoFieldScopeState extends State<StereoFieldScope> {
  final Queue<_TrailSample> _trail = Queue();

  @override
  void didUpdateWidget(StereoFieldScope old) {
    super.didUpdateWidget(old);
    // Push new sample if peaks changed (signal is active)
    final hasPeak = widget.peakL > 0.001 || widget.peakR > 0.001;
    if (hasPeak && (widget.peakL != old.peakL || widget.peakR != old.peakR)) {
      _trail.addFirst(_TrailSample(widget.peakL, widget.peakR));
      while (_trail.length > widget.trailLength) {
        _trail.removeLast();
      }
    } else if (!hasPeak && _trail.isNotEmpty) {
      // Decay trail when silent
      if (_trail.length > 2) _trail.removeLast();
    }
  }

  @override
  Widget build(BuildContext context) {
    final phaseState = classifyPhaseState(widget.correlation);
    return Stack(
      children: [
        CustomPaint(
          painter: _StereoFieldPainter(
            peakL: widget.peakL,
            peakR: widget.peakR,
            correlation: widget.correlation,
            width: widget.width,
            pan: widget.pan,
            balance: widget.balance,
            rotationDeg: widget.rotationDeg,
            enableWidth: widget.enableWidth,
            enablePanner: widget.enablePanner,
            enableBalance: widget.enableBalance,
            enableRotation: widget.enableRotation,
            accent: widget.accent,
            trail: _trail.toList(),
            bandCorrelations: widget.bandCorrelations,
            numBands: widget.numBands,
            bandColors: widget.bandColors,
            selectedBand: widget.selectedBand,
          ),
          size: Size.infinite,
        ),
        if (widget.showPhaseState)
          Positioned(
            bottom: 4,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: phaseStateColor(phaseState).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: phaseStateColor(phaseState).withValues(alpha: 0.4),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  phaseStateLabel(phaseState),
                  style: TextStyle(
                    color: phaseStateColor(phaseState),
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'JetBrains Mono',
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEREO FIELD PAINTER — iZotope Ozone Level
// ═══════════════════════════════════════════════════════════════════════════

class _StereoFieldPainter extends CustomPainter {
  final double peakL, peakR, correlation;
  final double width, pan, balance, rotationDeg;
  final bool enableWidth, enablePanner, enableBalance, enableRotation;
  final Color accent;
  final List<_TrailSample> trail;
  final List<double>? bandCorrelations;
  final int? numBands;
  final List<Color>? bandColors;
  final int? selectedBand;

  _StereoFieldPainter({
    required this.peakL,
    required this.peakR,
    required this.correlation,
    required this.width,
    required this.pan,
    required this.balance,
    required this.rotationDeg,
    required this.enableWidth,
    required this.enablePanner,
    required this.enableBalance,
    required this.enableRotation,
    required this.accent,
    required this.trail,
    this.bandCorrelations,
    this.numBands,
    this.bandColors,
    this.selectedBand,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(cx, cy) - 10;
    if (radius <= 0) return;

    _drawBackground(canvas, cx, cy, radius);
    _drawGrid(canvas, cx, cy, radius);
    _drawLabels(canvas, cx, cy, radius);
    _drawStereoField(canvas, cx, cy, radius);
    _drawTrail(canvas, cx, cy, radius);
    _drawSignalDot(canvas, cx, cy, radius);
    if (bandCorrelations != null && numBands != null && numBands! > 0) {
      _drawBandCorrelationArc(canvas, cx, cy, radius);
    }
    _drawCorrelationArc(canvas, cx, cy, radius);
  }

  // ─── BACKGROUND ─────────────────────────────────────────────────────

  void _drawBackground(Canvas canvas, double cx, double cy, double radius) {
    // Subtle radial gradient background
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.04),
          Colors.white.withValues(alpha: 0.01),
          Colors.transparent,
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius));
    canvas.drawCircle(Offset(cx, cy), radius, bgPaint);

    // Outer ring
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75;
    canvas.drawCircle(Offset(cx, cy), radius, ringPaint);

    // Inner guide circles (25%, 50%, 75%)
    final guidePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (final frac in [0.25, 0.5, 0.75]) {
      canvas.drawCircle(Offset(cx, cy), radius * frac, guidePaint);
    }
  }

  // ─── GRID ───────────────────────────────────────────────────────────

  void _drawGrid(Canvas canvas, double cx, double cy, double radius) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 0.5;

    // L-R horizontal axis
    canvas.drawLine(Offset(cx - radius, cy), Offset(cx + radius, cy), gridPaint);
    // Center vertical axis
    canvas.drawLine(Offset(cx, cy - radius), Offset(cx, cy + radius), gridPaint);

    // Diagonal M/S axes (45°)
    final diag = radius * 0.707;
    final diagPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(cx - diag, cy - diag),
      Offset(cx + diag, cy + diag),
      diagPaint,
    );
    canvas.drawLine(
      Offset(cx + diag, cy - diag),
      Offset(cx - diag, cy + diag),
      diagPaint,
    );
  }

  // ─── LABELS ─────────────────────────────────────────────────────────

  void _drawLabels(Canvas canvas, double cx, double cy, double radius) {
    final lColor = Colors.white.withValues(alpha: 0.35);
    final mColor = Colors.white.withValues(alpha: 0.2);
    // L/R on horizontal axis
    _drawText(canvas, 'L', Offset(cx - radius - 10, cy - 5), lColor, 9);
    _drawText(canvas, 'R', Offset(cx + radius + 3, cy - 5), lColor, 9);
    // M at top, S at left of top
    _drawText(canvas, 'M', Offset(cx + radius * 0.72, cy - radius * 0.72 - 10), mColor, 8);
    _drawText(canvas, 'S', Offset(cx - radius * 0.72 - 8, cy - radius * 0.72 - 10), mColor, 8);
  }

  // ─── STEREO FIELD ELLIPSE ───────────────────────────────────────────

  void _drawStereoField(Canvas canvas, double cx, double cy, double radius) {
    final effectiveWidth = enableWidth ? width : 1.0;
    final effectivePan = enablePanner ? pan : 0.0;
    final effectiveBalance = enableBalance ? balance : 0.0;
    final rotRad = enableRotation ? rotationDeg * math.pi / 180.0 : 0.0;

    // Width controls ellipse shape:
    // 0 = vertical line (mono), 1 = circle (stereo), 2 = horizontal line (extra wide)
    final spreadH = radius * 0.55 * effectiveWidth.clamp(0.0, 2.0);
    final spreadV = radius * 0.55 * (2.0 - effectiveWidth).clamp(0.0, 2.0);

    // Pan shifts center, balance tilts level
    final panOffset = effectivePan * radius * 0.4;
    final balL = 1.0 - effectiveBalance.clamp(0.0, 1.0);
    final balR = 1.0 + effectiveBalance.clamp(-1.0, 0.0);

    canvas.save();
    canvas.translate(cx + panOffset, cy);
    canvas.rotate(rotRad);

    // Field fill (very subtle)
    final fieldFill = Paint()
      ..color = accent.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: spreadH * 2 * math.max(balL, balR),
      height: spreadV * 2,
    );
    canvas.drawOval(rect, fieldFill);

    // Field outline with subtle glow
    final fieldGlow = Paint()
      ..color = accent.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawOval(rect, fieldGlow);

    final fieldStroke = Paint()
      ..color = accent.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75;
    canvas.drawOval(rect, fieldStroke);

    canvas.restore();
  }

  // ─── TRAIL BUFFER (persistence effect) ──────────────────────────────

  void _drawTrail(Canvas canvas, double cx, double cy, double radius) {
    if (trail.isEmpty) return;

    final effectivePan = enablePanner ? pan : 0.0;
    final rotRad = enableRotation ? rotationDeg * math.pi / 180.0 : 0.0;
    final panOffset = effectivePan * radius * 0.4;

    canvas.save();
    canvas.translate(cx + panOffset, cy);
    canvas.rotate(rotRad);

    for (int i = 0; i < trail.length; i++) {
      final sample = trail[i];
      final age = i / math.max(trail.length, 1).toDouble(); // 0.0=newest, 1.0=oldest
      final alpha = (1.0 - age) * 0.5; // Fade from 0.5 to 0.0

      // Convert L/R peaks to X/Y in M/S space
      final sigX = (sample.peakR - sample.peakL) * radius * 0.5;
      final sigY = -(sample.peakL + sample.peakR) * 0.5 * radius * 0.5;

      final dotRadius = 1.5 + (1.0 - age) * 1.0; // Newer dots are larger

      final dotPaint = Paint()
        ..color = accent.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(sigX, sigY), dotRadius, dotPaint);
    }

    canvas.restore();
  }

  // ─── SIGNAL DOT (current position with glow) ───────────────────────

  void _drawSignalDot(Canvas canvas, double cx, double cy, double radius) {
    final hasPeak = peakL > 0.001 || peakR > 0.001;
    if (!hasPeak) return;

    final effectivePan = enablePanner ? pan : 0.0;
    final rotRad = enableRotation ? rotationDeg * math.pi / 180.0 : 0.0;
    final panOffset = effectivePan * radius * 0.4;

    canvas.save();
    canvas.translate(cx + panOffset, cy);
    canvas.rotate(rotRad);

    final sigX = (peakR - peakL) * radius * 0.5;
    final sigY = -(peakL + peakR) * 0.5 * radius * 0.5;

    // Outer glow (large, very subtle)
    final outerGlow = Paint()
      ..color = accent.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset(sigX, sigY), 8, outerGlow);

    // Middle glow
    final midGlow = Paint()
      ..color = accent.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(sigX, sigY), 4, midGlow);

    // Core dot
    final corePaint = Paint()
      ..color = accent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(sigX, sigY), 2.5, corePaint);

    // White highlight center
    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(sigX, sigY), 1.0, highlight);

    canvas.restore();
  }

  // ─── CORRELATION ARC (bottom of scope) ──────────────────────────────

  void _drawCorrelationArc(Canvas canvas, double cx, double cy, double radius) {
    // Draw a small arc indicator at the bottom showing overall correlation
    final corrNorm = (correlation + 1.0) / 2.0; // 0.0 → 1.0
    final corrColor = correlation < 0
        ? Color.lerp(FabFilterColors.red, FabFilterColors.yellow, corrNorm * 2)!
        : Color.lerp(FabFilterColors.yellow, FabFilterColors.green, (corrNorm - 0.5) * 2)!;

    // Arc from -90° to +90° (bottom semicircle)
    final arcRadius = radius + 6;
    final startAngle = math.pi * 0.6;  // ~108°
    final sweepAngle = math.pi * -0.2; // sweep based on corr position
    final corrAngle = startAngle + (math.pi * -0.2 * corrNorm * 5); // map to arc

    // Background arc track
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: arcRadius),
      math.pi * 0.6,
      math.pi * -0.2,
      false,
      trackPaint,
    );

    // Correlation indicator dot on the arc
    final indicatorAngle = math.pi * 0.6 + (math.pi * -0.2 * corrNorm);
    final indicatorX = cx + arcRadius * math.cos(indicatorAngle);
    final indicatorY = cy + arcRadius * math.sin(indicatorAngle);

    final indicatorPaint = Paint()
      ..color = corrColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(indicatorX, indicatorY), 2.5, indicatorPaint);

    // Glow on indicator
    final indicatorGlow = Paint()
      ..color = corrColor.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(Offset(indicatorX, indicatorY), 3.5, indicatorGlow);
  }

  // ─── PER-BAND CORRELATION ARCS (multiband mode) ─────────────────────

  void _drawBandCorrelationArc(Canvas canvas, double cx, double cy, double radius) {
    final bands = bandCorrelations!;
    final nBands = numBands!;
    final colors = bandColors ?? List.generate(6, (_) => accent);

    // Draw small colored ticks around the right side for each band's correlation
    final arcRadius = radius + 4;

    for (int b = 0; b < nBands && b < bands.length; b++) {
      final corr = bands[b].clamp(-1.0, 1.0);
      final corrNorm = (corr + 1.0) / 2.0;
      // Spread bands around right-bottom quadrant
      final baseAngle = math.pi * 0.15 + (b / nBands) * math.pi * 0.25;
      final color = b < colors.length ? colors[b] : accent;
      final isSelected = selectedBand == b;

      // Band tick
      final tickLen = isSelected ? 6.0 : 3.5;
      final tickWidth = isSelected ? 2.0 : 1.0;
      final innerR = arcRadius;
      final outerR = arcRadius + tickLen;

      final tickPaint = Paint()
        ..color = color.withValues(alpha: isSelected ? 0.9 : 0.5)
        ..strokeWidth = tickWidth
        ..strokeCap = StrokeCap.round;

      final x1 = cx + innerR * math.cos(baseAngle);
      final y1 = cy + innerR * math.sin(baseAngle);
      final x2 = cx + outerR * math.cos(baseAngle);
      final y2 = cy + outerR * math.sin(baseAngle);

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), tickPaint);

      // Show correlation value for selected band
      if (isSelected) {
        _drawText(
          canvas,
          corr.toStringAsFixed(2),
          Offset(x2 + 3, y2 - 4),
          color.withValues(alpha: 0.7),
          7,
        );
      }
    }
  }

  // ─── TEXT HELPER ────────────────────────────────────────────────────

  void _drawText(Canvas canvas, String text, Offset pos, Color color, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontFamily: 'JetBrains Mono',
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(_StereoFieldPainter old) {
    return peakL != old.peakL ||
        peakR != old.peakR ||
        correlation != old.correlation ||
        width != old.width ||
        pan != old.pan ||
        balance != old.balance ||
        rotationDeg != old.rotationDeg ||
        enableWidth != old.enableWidth ||
        enablePanner != old.enablePanner ||
        enableBalance != old.enableBalance ||
        enableRotation != old.enableRotation ||
        trail.length != old.trail.length ||
        bandCorrelations != old.bandCorrelations ||
        selectedBand != old.selectedBand;
  }
}
