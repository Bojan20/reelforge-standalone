// OrbMixer Painter — CustomPainter for the radial audio mixer
//
// Renders 12 visual layers at 60fps:
//  0: Background gradient (dark radial)
//  1: Frequency heatmap (radial energy sectors)
//  2: Orbit ring (0dB reference circle)
//  3: Timeline scrub ring (playback position)
//  4: Ghost trails (fading position history)
//  5: Routing lines (dot → center, opacity = volume)
//  6: Magnetic snap lines (proximity groups)
//  7: Bus dots (position=volume/pan, size=peak, color=category)
//  8: Solo glow + peak pulse + mute dim
//  9: Master dot (center, color=overall peak)
// 10: Voice dots (Nivo 2) + Param ring (Nivo 3)
// 11: Labels (bus name, dB on hover)

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
    _paintFrequencyHeatmap(canvas, size, center); // Phase 5: under everything
    _paintOrbitRing(canvas, center, orbitRadius);
    _paintTimelineScrubRing(canvas, size, center); // Phase 5: outer ring
    _paintGhostTrails(canvas); // Phase 5: behind live dots
    _paintRoutingLines(canvas, center);
    _paintMagneticSnapLines(canvas); // Phase 5: between close dots
    _paintBusDots(canvas, size);
    _paintMasterDot(canvas, center);

    // Nivo 2: Voice dots when bus is expanded
    if (provider.isExpanded) {
      _paintVoiceDots(canvas);
    }

    // Nivo 3: Param ring when voice detail is open
    if (provider.isDetailOpen) {
      _paintParamRing(canvas);
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

  // ── Layer 7b: Param Ring (Nivo 3 — sound detail) ──

  void _paintParamRing(Canvas canvas) {
    final voice = provider.detailVoice;
    if (voice == null) return;

    final center = voice.position;
    const ringRadius = 28.0; // radius of arc ring around voice dot
    const trackWidth = 4.0;
    const activeTrackWidth = 6.0;

    final params = provider.detailParams;

    // Dim background behind ring
    final dimPaint = Paint()
      ..color = const Color(0xAA06060A)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16.0);
    canvas.drawCircle(center, ringRadius + 12, dimPaint);

    // Draw each arc slider
    for (final arc in OrbParamArc.values) {
      final isActive = provider.activeArcIndex == arc.index;
      final normalized = arc.toNormalized(params[arc.index]);

      // Track background (dark arc)
      final trackPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isActive ? activeTrackWidth : trackWidth
        ..strokeCap = StrokeCap.round
        ..color = arc.color.withValues(alpha: 0.15);

      final rect = Rect.fromCircle(center: center, radius: ringRadius);
      canvas.drawArc(rect, arc.startAngle, arc.sweepAngle, false, trackPaint);

      // Value fill (colored arc proportional to value)
      if (normalized > 0.01) {
        final fillPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isActive ? activeTrackWidth : trackWidth
          ..strokeCap = StrokeCap.round
          ..color = arc.color.withValues(alpha: isActive ? 0.9 : 0.6);

        final fillSweep = arc.sweepAngle * normalized;
        canvas.drawArc(rect, arc.startAngle, fillSweep, false, fillPaint);
      }

      // Thumb dot at current value position
      final thumbAngle = arc.startAngle + arc.sweepAngle * normalized;
      final thumbPos = Offset(
        center.dx + ringRadius * math.cos(thumbAngle),
        center.dy + ringRadius * math.sin(thumbAngle),
      );

      final thumbPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isActive ? Colors.white : arc.color;
      canvas.drawCircle(thumbPos, isActive ? 3.5 : 2.5, thumbPaint);

      // Label at midpoint of arc
      final midAngle = arc.startAngle + arc.sweepAngle * 0.5;
      final labelRadius = ringRadius + 10;
      final labelPos = Offset(
        center.dx + labelRadius * math.cos(midAngle),
        center.dy + labelRadius * math.sin(midAngle),
      );

      // Format value text
      final valueText = _formatArcValue(arc, params[arc.index]);
      final labelSpan = TextSpan(
        text: '${arc.label}\n$valueText',
        style: TextStyle(
          color: arc.color.withValues(alpha: isActive ? 0.9 : 0.5),
          fontSize: 6.0,
          fontFamily: 'SpaceGrotesk',
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          height: 1.2,
        ),
      );
      final tp = TextPainter(
        text: labelSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      tp.paint(canvas, labelPos - Offset(tp.width / 2, tp.height / 2));
    }

    // Center voice dot (highlighted)
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = voice.statusColor;
    canvas.drawCircle(center, voice.dotRadius + 1, dotPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.6);
    canvas.drawCircle(center, voice.dotRadius + 1, borderPaint);
  }

  String _formatArcValue(OrbParamArc arc, double value) {
    return switch (arc) {
      OrbParamArc.volume => value <= 0.001
          ? '-∞'
          : '${(20.0 * math.log(value) / math.ln10).toStringAsFixed(1)}',
      OrbParamArc.pan => value == 0
          ? 'C'
          : (value < 0
              ? 'L${(-value * 100).toInt()}'
              : 'R${(value * 100).toInt()}'),
      OrbParamArc.pitch => '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}st',
      OrbParamArc.hpf => value < 1000
          ? '${value.toInt()}Hz'
          : '${(value / 1000).toStringAsFixed(1)}k',
      OrbParamArc.lpf => value < 1000
          ? '${value.toInt()}Hz'
          : '${(value / 1000).toStringAsFixed(1)}k',
      OrbParamArc.send => '${(value * 100).toInt()}%',
    };
  }

  // ── Phase 5: Ghost Trails ──

  void _paintGhostTrails(Canvas canvas) {
    final trailCount = provider.trailSamples;
    if (trailCount < 3) return;

    for (final bus in provider.orbitBuses) {
      if (bus.muted) continue;

      final color = bus.id.color;
      // Draw trail dots, fading from newest to oldest
      // Sample every 4th position to avoid overdraw
      final maxDots = (trailCount / 4).floor().clamp(1, 30);
      for (int i = 0; i < maxDots; i++) {
        final age = i * 4;
        final pos = provider.getTrailAt(bus.id, age);
        if (pos == null || pos == Offset.zero) continue;

        // Skip if too close to current position (no visible trail)
        if ((pos - bus.position).distance < 1.5) continue;

        // Opacity: newest=0.25, oldest=0.0
        final t = i / maxDots;
        final alpha = (0.25 * (1.0 - t)).clamp(0.0, 0.25);
        if (alpha < 0.01) continue;

        // Radius: shrinks with age
        final radius = bus.dotRadius * (1.0 - t * 0.6);

        final trailPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: alpha);
        canvas.drawCircle(pos, radius.clamp(1.0, 12.0), trailPaint);
      }
    }
  }

  // ── Phase 5: Magnetic Snap Lines ──

  void _paintMagneticSnapLines(Canvas canvas) {
    final pairs = provider.magneticSnapPairs;
    if (pairs.isEmpty) return;

    for (final (busA, busB) in pairs) {
      final stateA = provider.getBus(busA);
      final stateB = provider.getBus(busB);
      if (stateA == null || stateB == null) continue;

      final distance = (stateA.position - stateB.position).distance;
      // Stronger line when closer (inverse distance)
      final strength = (1.0 - distance / 24.0).clamp(0.0, 1.0);

      // Blended color between the two buses
      final blendedColor = Color.lerp(busA.color, busB.color, 0.5)!;

      // Magnetic field line — dashed with glow
      final linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 + strength
        ..color = blendedColor.withValues(alpha: 0.15 + strength * 0.25)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, 2.0 + strength * 2.0);
      canvas.drawLine(stateA.position, stateB.position, linePaint);

      // Crisp inner line
      final innerPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = blendedColor.withValues(alpha: 0.1 + strength * 0.2);
      canvas.drawLine(stateA.position, stateB.position, innerPaint);

      // Snap indicator dots at midpoint
      final mid = (stateA.position + stateB.position) / 2;
      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = blendedColor.withValues(alpha: 0.3 + strength * 0.3);
      canvas.drawCircle(mid, 1.5 + strength, dotPaint);
    }
  }

  // ── Phase 5: Frequency Heatmap ──

  void _paintFrequencyHeatmap(Canvas canvas, Size size, Offset center) {
    final heatmap = provider.heatmapData;
    final sectors = heatmap.length; // 32
    final maxRadius = size.width * 0.48; // just inside the widget edge
    final minRadius = size.width * 0.08; // around the master dot

    const sectorAngle = 2 * math.pi / 32;

    for (int i = 0; i < sectors; i++) {
      final energy = heatmap[i];
      if (energy < 0.01) continue;

      final startAngle = -math.pi + i * sectorAngle;

      // Radial extent proportional to energy
      final outerRadius = minRadius + (maxRadius - minRadius) * energy;

      // Color: cool blue at low energy → warm orange at high
      final heatColor = Color.lerp(
        FluxForgeTheme.accentBlue.withValues(alpha: 0.04),
        FluxForgeTheme.accentOrange.withValues(alpha: 0.12),
        energy,
      )!;

      final sectorPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = heatColor;

      // Draw as arc wedge
      final path = ui.Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: outerRadius),
          startAngle,
          sectorAngle,
          false,
        )
        ..close();

      canvas.drawPath(path, sectorPaint);
    }
  }

  // ── Phase 5: Timeline Scrub Ring ──

  void _paintTimelineScrubRing(Canvas canvas, Size size, Offset center) {
    final progress = provider.playbackProgress;
    final isPlaying = provider.isPlaying;
    final radius = size.width / 2 - 3; // just inside the outer edge

    // Track background (always visible, very subtle)
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.white.withValues(alpha: 0.04);
    canvas.drawCircle(center, radius, trackPaint);

    if (progress < 0.001 && !isPlaying) return;

    // Progress arc (from top, clockwise)
    final sweepAngle = progress * 2 * math.pi;
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..color = isPlaying
          ? FluxForgeTheme.accentGreen.withValues(alpha: 0.35)
          : Colors.white.withValues(alpha: 0.15);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // start at top
      sweepAngle,
      false,
      progressPaint,
    );

    // Playhead dot
    final headAngle = -math.pi / 2 + sweepAngle;
    final headPos = Offset(
      center.dx + radius * math.cos(headAngle),
      center.dy + radius * math.sin(headAngle),
    );

    final headPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = isPlaying
          ? FluxForgeTheme.accentGreen
          : Colors.white.withValues(alpha: 0.4);
    canvas.drawCircle(headPos, isPlaying ? 3.0 : 2.0, headPaint);

    // Glow behind playhead when playing
    if (isPlaying) {
      final glowPaint = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
        ..color = FluxForgeTheme.accentGreen.withValues(alpha: 0.3);
      canvas.drawCircle(headPos, 5.0, glowPaint);
    }
  }

  // ── Layer 8: Labels (hover/expanded mode) ──

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
