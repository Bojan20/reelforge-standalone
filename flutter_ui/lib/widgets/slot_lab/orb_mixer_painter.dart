// OrbMixer Painter — CustomPainter for the radial audio mixer
//
// Renders 8 visual layers at 60fps:
//  0: Background gradient (dark radial)
//  1: Orbit ring (0dB reference circle)
//  2: Routing lines (dot → center, opacity = volume)
//  3: Bus dots (position=volume/pan, size=peak, color=category)
//  4: Solo glow (bloom shader on soloed dots)
//  5: Mute dim (50% opacity on muted dots)
//  6: Master dot (center, color=overall peak)
//  7: Labels (bus name, dB on hover)

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../providers/orb_mixer_provider.dart';
import '../../theme/fluxforge_theme.dart';

class OrbMixerPainter extends CustomPainter {
  final OrbMixerProvider provider;
  final bool showLabels;
  final OrbBusId? hoveredBus;

  OrbMixerPainter({
    required this.provider,
    this.showLabels = false,
    this.hoveredBus,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final orbitRadius = size.width * 0.35;

    _paintBackground(canvas, size, center);
    _paintOrbitRing(canvas, center, orbitRadius);
    _paintRoutingLines(canvas, center);
    _paintBusDots(canvas, size);
    _paintMasterDot(canvas, center);

    // Nivo 2: Voice dots when bus is expanded
    if (provider.isExpanded) {
      _paintVoiceDots(canvas);
    }

    if (showLabels || hoveredBus != null) {
      _paintLabels(canvas, size);
    }
  }

  // ── Layer 0: Background ──

  void _paintBackground(Canvas canvas, Size size, Offset center) {
    final bgPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        size.width / 2,
        [
          const Color(0xFF0A0A14), // deep center
          const Color(0xFF06060A), // FluxForge bg
        ],
        [0.0, 1.0],
      );
    canvas.drawCircle(center, size.width / 2, bgPaint);

    // Subtle outer ring glow
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = FluxForgeTheme.accentBlue.withValues(alpha: 0.08);
    canvas.drawCircle(center, size.width / 2 - 1, glowPaint);
  }

  // ── Layer 1: Orbit ring (0dB reference) ──

  void _paintOrbitRing(Canvas canvas, Offset center, double radius) {
    // Dashed orbit ring
    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white.withValues(alpha: 0.12);

    // Draw as dotted circle (12 segments)
    const segments = 24;
    const arcLength = 2 * math.pi / segments;
    for (int i = 0; i < segments; i += 2) {
      final startAngle = i * arcLength;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        arcLength,
        false,
        orbitPaint,
      );
    }

    // Inner ring (50% volume reference)
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.3
      ..color = Colors.white.withValues(alpha: 0.05);
    canvas.drawCircle(center, radius * 0.5, innerPaint);
  }

  // ── Layer 2: Routing lines (dot → center) ──

  void _paintRoutingLines(Canvas canvas, Offset center) {
    for (final bus in provider.orbitBuses) {
      if (bus.muted) continue;

      // Opacity proportional to volume (louder = more visible)
      final alpha = (bus.volume / 0.85).clamp(0.05, 0.35);
      final linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = bus.id.color.withValues(alpha: alpha);

      canvas.drawLine(center, bus.position, linePaint);
    }
  }

  // ── Layer 3-5: Bus dots ──

  void _paintBusDots(Canvas canvas, Size size) {
    for (final bus in provider.orbitBuses) {
      _paintSingleDot(canvas, bus, size);
    }
  }

  void _paintSingleDot(Canvas canvas, OrbBusState bus, Size size) {
    final pos = bus.position;
    final radius = bus.dotRadius;
    final color = bus.id.color;
    final isHovered = hoveredBus == bus.id;
    final isDragging = provider.draggingBus == bus.id;

    // Mute: dim
    final baseAlpha = bus.muted ? 0.35 : 1.0;

    // Solo glow (Layer 4)
    if (bus.solo) {
      final glowPaint = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0)
        ..color = color.withValues(alpha: 0.5 * baseAlpha);
      canvas.drawCircle(pos, radius + 6, glowPaint);
    }

    // Peak pulse glow
    if (bus.peak > 0.1 && !bus.muted) {
      final peakGlow = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
        ..color = color.withValues(alpha: (bus.peak * 0.3).clamp(0.0, 0.3));
      canvas.drawCircle(pos, radius + 3, peakGlow);
    }

    // Main dot fill
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: baseAlpha);

    // Gradient fill: brighter in center
    dotPaint.shader = ui.Gradient.radial(
      pos,
      radius,
      [
        Color.lerp(color, Colors.white, 0.3)!.withValues(alpha: baseAlpha),
        color.withValues(alpha: baseAlpha * 0.7),
      ],
      [0.0, 1.0],
    );
    canvas.drawCircle(pos, radius, dotPaint);

    // Border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isDragging ? 2.0 : (isHovered ? 1.5 : 0.8)
      ..color = color.withValues(
          alpha: isDragging ? 0.9 : (isHovered ? 0.7 : 0.4));
    canvas.drawCircle(pos, radius, borderPaint);

    // Hover ring
    if (isHovered && !isDragging) {
      final hoverPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.white.withValues(alpha: 0.3);
      canvas.drawCircle(pos, radius + 3, hoverPaint);
    }

    // Bus label (always visible for orbit dots in compact, below dot)
    _paintDotLabel(canvas, bus, size);
  }

  void _paintDotLabel(Canvas canvas, OrbBusState bus, Size size) {
    final textSpan = TextSpan(
      text: bus.id.label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: bus.muted ? 0.3 : 0.6),
        fontSize: 8.0,
        fontFamily: 'SpaceGrotesk',
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );
    final tp = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    // Position label below dot
    final labelPos = Offset(
      bus.position.dx - tp.width / 2,
      bus.position.dy + bus.dotRadius + 3,
    );

    // Clamp to widget bounds
    final clampedX = labelPos.dx.clamp(2.0, size.width - tp.width - 2);
    final clampedY = labelPos.dy.clamp(2.0, size.height - tp.height - 2);

    tp.paint(canvas, Offset(clampedX, clampedY));
  }

  // ── Layer 6: Master dot ──

  void _paintMasterDot(Canvas canvas, Offset center) {
    final master = provider.master;
    final radius = master.dotRadius;

    // Master peak color: green → yellow → red
    final peakColor = _peakToColor(master.peak);

    // Outer glow based on peak
    if (master.peak > 0.05) {
      final glowPaint = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0)
        ..color = peakColor.withValues(alpha: (master.peak * 0.25).clamp(0.0, 0.25));
      canvas.drawCircle(center, radius + 4, glowPaint);
    }

    // Master solo glow
    if (master.solo) {
      final soloGlow = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0)
        ..color = FluxForgeTheme.accentYellow.withValues(alpha: 0.4);
      canvas.drawCircle(center, radius + 8, soloGlow);
    }

    // Main dot with radial gradient
    final dotPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [
          Color.lerp(peakColor, Colors.white, 0.4)!,
          peakColor.withValues(alpha: 0.8),
          peakColor.withValues(alpha: 0.4),
        ],
        [0.0, 0.6, 1.0],
      );
    canvas.drawCircle(center, radius, dotPaint);

    // Mute dim overlay
    if (master.muted) {
      final mutePaint = Paint()
        ..color = const Color(0xFF06060A).withValues(alpha: 0.6);
      canvas.drawCircle(center, radius, mutePaint);
    }

    // Border ring
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: master.muted ? 0.15 : 0.35);
    canvas.drawCircle(center, radius, borderPaint);

    // "M" label
    final textSpan = TextSpan(
      text: 'M',
      style: TextStyle(
        color: Colors.white.withValues(alpha: master.muted ? 0.3 : 0.8),
        fontSize: 9.0,
        fontFamily: 'SpaceGrotesk',
        fontWeight: FontWeight.w700,
      ),
    );
    final tp = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  // ── Layer 6b: Voice dots (Nivo 2 — bus expand) ──

  void _paintVoiceDots(Canvas canvas) {
    final voices = provider.expandedVoices;
    if (voices.isEmpty) return;

    // Connecting lines from voice dots to parent bus dot
    final parentBus = provider.getBus(provider.expandedBus!);
    if (parentBus != null) {
      for (final voice in voices) {
        final linePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.4
          ..color = voice.statusColor.withValues(alpha: 0.2);
        canvas.drawLine(parentBus.position, voice.position, linePaint);
      }
    }

    // Draw each voice dot
    for (final voice in voices) {
      final pos = voice.position;
      final radius = voice.dotRadius;
      final color = voice.statusColor;

      // Peak glow
      if (voice.peak > 0.1) {
        final glowPaint = Paint()
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0)
          ..color = color.withValues(alpha: (voice.peak * 0.3).clamp(0.0, 0.3));
        canvas.drawCircle(pos, radius + 2, glowPaint);
      }

      // Main dot
      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..shader = ui.Gradient.radial(
          pos,
          radius,
          [
            Color.lerp(color, Colors.white, 0.25)!,
            color.withValues(alpha: 0.7),
          ],
          [0.0, 1.0],
        );
      canvas.drawCircle(pos, radius, dotPaint);

      // Border
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = color.withValues(alpha: 0.5);
      canvas.drawCircle(pos, radius, borderPaint);

      // Looping indicator (tiny ring)
      if (voice.isLooping) {
        final loopPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = FluxForgeTheme.accentCyan.withValues(alpha: 0.5);
        canvas.drawCircle(pos, radius + 2, loopPaint);
      }
    }
  }

  // ── Layer 7: Labels (hover/expanded mode) ──

  void _paintLabels(Canvas canvas, Size size) {
    if (!showLabels) return;

    for (final bus in provider.busStates.values) {
      if (bus.isMaster) continue;

      // dB value
      final db = _linearToDb(bus.volume);
      final dbText = db <= -60 ? '-∞' : '${db.toStringAsFixed(1)} dB';

      final textSpan = TextSpan(
        text: dbText,
        style: TextStyle(
          color: bus.id.color.withValues(alpha: 0.7),
          fontSize: 7.0,
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w400,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      // Above the dot
      final labelPos = Offset(
        bus.position.dx - tp.width / 2,
        bus.position.dy - bus.dotRadius - tp.height - 2,
      );
      final clampedX = labelPos.dx.clamp(2.0, size.width - tp.width - 2);
      final clampedY = labelPos.dy.clamp(2.0, size.height - tp.height - 2);
      tp.paint(canvas, Offset(clampedX, clampedY));
    }
  }

  // ── Helpers ──

  /// Peak level to color (green → yellow → orange → red)
  Color _peakToColor(double peak) {
    if (peak < 0.3) return FluxForgeTheme.accentGreen;
    if (peak < 0.6) {
      // Green → Yellow
      final t = (peak - 0.3) / 0.3;
      return Color.lerp(FluxForgeTheme.accentGreen,
          FluxForgeTheme.accentYellow, t)!;
    }
    if (peak < 0.85) {
      // Yellow → Orange
      final t = (peak - 0.6) / 0.25;
      return Color.lerp(FluxForgeTheme.accentYellow,
          FluxForgeTheme.accentOrange, t)!;
    }
    // Orange → Red
    final t = ((peak - 0.85) / 0.15).clamp(0.0, 1.0);
    return Color.lerp(FluxForgeTheme.accentOrange,
        FluxForgeTheme.accentRed, t)!;
  }

  /// Linear gain to dB
  double _linearToDb(double linear) {
    if (linear <= 0.0001) return -60.0;
    return 20.0 * math.log(linear) / math.ln10;
  }

  @override
  bool shouldRepaint(OrbMixerPainter oldDelegate) {
    // Always repaint — real-time meter animation
    return true;
  }
}
