// SlotLab Lower Zone — Custom Painters
//
// Extracted from slotlab_lower_zone_widget.dart via `part of` to reduce
// monolith LOC. All `_` private classes remain library-private and accessible
// within the slotlab_lower_zone_widget library scope.
//
// Classes:
//   _TimelinePainter         — simple grid/block timeline preview
//   KeyboardShortcutsOverlay — static helper + dialog
//   _KeyboardShortcutsDialog — keyboard shortcuts UI
//   _FadeCurvePainter        — fade in/out curve visualization
//   _TlRulerPainter          — time ruler for timeline tracks
//   _TlWaveformPainter       — waveform miniature painter
//   _TlGridPainter           — timeline grid lines
//   _SpatialFieldPainter     — 2D pan/spatial field painter
//
// Part of: ../slotlab_lower_zone_widget.dart

part of '../slotlab_lower_zone_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════

class _TimelinePainter extends CustomPainter {
  final Color color;
  _TimelinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = LowerZoneColors.border.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Draw vertical grid lines
    for (int i = 0; i < 10; i++) {
      final x = size.width * i / 10;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Draw stage blocks
    final stages = [
      (0.0, 0.05, 'SPIN'),
      (0.1, 0.3, 'REEL'),
      (0.35, 0.1, 'STOP'),
      (0.5, 0.15, 'EVAL'),
      (0.7, 0.25, 'WIN'),
    ];

    for (int i = 0; i < stages.length; i++) {
      final start = stages[i].$1;
      final duration = stages[i].$2;
      final y = 20.0 + i * 25.0;

      final rect = Rect.fromLTWH(
        start * size.width,
        y,
        duration * size.width,
        18,
      );

      final paint = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Note: _EqCurvePainter and _ReverbDecayPainter removed — replaced by FabFilter widgets

// ═══════════════════════════════════════════════════════════════════════════
// P0.3: KEYBOARD SHORTCUTS OVERLAY
// ═══════════════════════════════════════════════════════════════════════════

/// Shows keyboard shortcuts overlay dialog for SlotLab Lower Zone
class KeyboardShortcutsOverlay {
  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => const _KeyboardShortcutsDialog(),
    );
  }
}

class _KeyboardShortcutsDialog extends StatelessWidget {
  const _KeyboardShortcutsDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: LowerZoneColors.bgDeep,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: LowerZoneColors.border),
      ),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(20),
        child: Column(
          // mainAxisSize removed — fills Flexible parent
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.keyboard, color: LowerZoneColors.textPrimary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Keyboard Shortcuts',
                  style: FluxForgeTheme.dockSans(
                    color: LowerZoneColors.textPrimary,
                    size: 16,
                    weight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: LowerZoneColors.textSecondary,
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: LowerZoneColors.border, height: 1),
            const SizedBox(height: 16),

            // Super Tabs section
            _buildSection('Super Tabs', [
              ('1', 'STAGES tab'),
              ('2', 'EVENTS tab'),
              ('3', 'MIX tab'),
              ('4', 'DSP tab'),
              ('5', 'BAKE tab'),
            ]),
            const SizedBox(height: 16),

            // Sub Tabs section
            _buildSection('Sub Tabs (within STAGES)', [
              ('Q', 'Trace sub-tab'),
              ('W', 'Timeline sub-tab'),
              ('E', 'Symbols sub-tab'),
              ('R', 'Timing sub-tab'),
            ]),
            const SizedBox(height: 16),

            // General section
            _buildSection('General', [
              ('`', 'Toggle expand/collapse'),
              ('Esc', 'Close/collapse'),
              ('?', 'Show this help'),
            ]),
            const SizedBox(height: 16),

            // Slot Preview section
            _buildSection('Slot Preview', [
              ('Space', 'Spin / Stop'),
              ('1-7', 'Force outcomes (debug)'),
              ('T', 'Toggle turbo mode'),
            ]),

            const SizedBox(height: 20),
            // Footer hint
            Center(
              child: Text(
                'Press Esc or click outside to close',
                style: FluxForgeTheme.dockSans(
                  color: LowerZoneColors.textMuted,
                  size: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<(String, String)> shortcuts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: FluxForgeTheme.dockSans(
            color: LowerZoneColors.textSecondary,
            size: 12,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ...shortcuts.map((s) => _buildShortcutRow(s.$1, s.$2)),
      ],
    );
  }

  Widget _buildShortcutRow(String key, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: LowerZoneColors.border),
            ),
            child: Text(
              key,
              textAlign: TextAlign.center,
              style: FluxForgeTheme.dockMono(
                color: LowerZoneColors.textPrimary,
                size: 12,
                weight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            description,
            style: FluxForgeTheme.dockSans(
              color: LowerZoneColors.textSecondary,
              size: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// P2.8: FADE CURVE PAINTER
// =============================================================================

/// Custom painter for visualizing fade in/out curves on layer items
class _FadeCurvePainter extends CustomPainter {
  final double fadeInMs;
  final double fadeOutMs;
  final CrossfadeCurve fadeInCurve;
  final CrossfadeCurve fadeOutCurve;
  final Color color;

  _FadeCurvePainter({
    required this.fadeInMs,
    required this.fadeOutMs,
    required this.fadeInCurve,
    required this.fadeOutCurve,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Background line at y = height (bottom, representing 0 volume)
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.1)
        ..strokeWidth = 0.5,
    );

    // Calculate fade regions as percentage of total width
    // Assume total duration is ~2000ms for visualization purposes
    const totalDurationMs = 2000.0;
    final fadeInWidth = (fadeInMs / totalDurationMs).clamp(0.0, 0.4) * size.width;
    final fadeOutWidth = (fadeOutMs / totalDurationMs).clamp(0.0, 0.4) * size.width;

    final path = Path();

    // Start from bottom-left (0 volume at start)
    path.moveTo(0, size.height);

    // Fade In curve (rise from bottom to top = 0 to 1 volume)
    if (fadeInMs > 0 && fadeInWidth > 2) {
      const steps = 20;
      for (int i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = fadeInWidth * t;
        final y = size.height - (size.height * _applyCurve(t, fadeInCurve));
        path.lineTo(x, y);
      }
    } else {
      // No fade in - instant rise to top
      path.lineTo(0, 0);
    }

    // Sustain section (flat at top = full volume)
    final sustainStartX = fadeInWidth > 0 ? fadeInWidth : 0.0;
    final sustainEndX = size.width - (fadeOutWidth > 0 ? fadeOutWidth : 0.0);
    path.lineTo(sustainStartX, 0);
    path.lineTo(sustainEndX, 0);

    // Fade Out curve (descend from top to bottom = 1 to 0 volume)
    if (fadeOutMs > 0 && fadeOutWidth > 2) {
      const steps = 20;
      for (int i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = sustainEndX + (fadeOutWidth * t);
        final y = size.height * _applyCurve(t, fadeOutCurve);
        path.lineTo(x, y);
      }
    } else {
      // No fade out - instant drop to bottom
      path.lineTo(size.width, 0);
    }

    // Close path at bottom-right
    path.lineTo(size.width, size.height);
    path.close();

    // Draw filled area
    canvas.drawPath(path, paint);

    // Draw outline
    canvas.drawPath(path, linePaint);
  }

  /// Apply curve transformation to normalized value (0-1)
  double _applyCurve(double t, CrossfadeCurve curve) {
    switch (curve) {
      case CrossfadeCurve.linear:
        return t;
      case CrossfadeCurve.log3:
      case CrossfadeCurve.equalPower:
        return math.sin(t * math.pi / 2);
      case CrossfadeCurve.log1:
        return math.log(1 + t * (math.e - 1));
      case CrossfadeCurve.sCurve:
        return (1 - math.cos(t * math.pi)) / 2;
      case CrossfadeCurve.invSCurve:
        return t < 0.5 ? 4 * t * t * t : 1 - 4 * (1 - t) * (1 - t) * (1 - t);
      case CrossfadeCurve.sine:
      case CrossfadeCurve.sinCos:
        return 0.5 - 0.5 * math.cos(t * math.pi);
      case CrossfadeCurve.exp1:
        return (math.exp(t) - 1) / (math.e - 1);
      case CrossfadeCurve.exp3:
        return (math.exp(3 * t) - 1) / (math.exp(3) - 1);
    }
  }

  @override
  bool shouldRepaint(_FadeCurvePainter oldDelegate) {
    return oldDelegate.fadeInMs != fadeInMs ||
        oldDelegate.fadeOutMs != fadeOutMs ||
        oldDelegate.fadeInCurve != fadeInCurve ||
        oldDelegate.fadeOutCurve != fadeOutCurve ||
        oldDelegate.color != color;
  }
}

/// Time ruler painter for timeline
class _TlRulerPainter extends CustomPainter {
  final double pixelsPerSecond;
  final double maxSeconds;

  const _TlRulerPainter({required this.pixelsPerSecond, required this.maxSeconds});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 1.0;
    final textStyle = TextStyle(fontSize: 8, color: Colors.white38, fontFamily: 'monospace');

    double tickInterval;
    if (pixelsPerSecond >= 200) {
      tickInterval = 0.1;
    } else if (pixelsPerSecond >= 80) {
      tickInterval = 0.25;
    } else {
      tickInterval = 0.5;
    }

    for (double t = 0; t <= maxSeconds; t += tickInterval) {
      final x = t * pixelsPerSecond;
      if (x > size.width) break;

      final isMajor = (t * 1000).round() % 1000 == 0;
      final tickHeight = isMajor ? 12.0 : 6.0;

      paint.color = Colors.white.withValues(alpha: isMajor ? 0.2 : 0.08);
      canvas.drawLine(Offset(x, size.height - tickHeight), Offset(x, size.height), paint);

      if (isMajor) {
        final tp = TextPainter(
          text: TextSpan(text: '${t.toStringAsFixed(0)}s', style: textStyle),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, Offset(x + 2, 2));
      }
    }

    // Bottom border
    paint.color = Colors.white.withValues(alpha: 0.08);
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), paint);
  }

  @override
  bool shouldRepaint(_TlRulerPainter oldDelegate) =>
      oldDelegate.pixelsPerSecond != pixelsPerSecond || oldDelegate.maxSeconds != maxSeconds;
}

/// Waveform painter — renders absolute peak values (0-1) as mirrored waveform
class _TlWaveformPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final bool isMuted;

  // Pre-allocated paints (zero allocation in paint())
  late final Paint _fillPaint;
  late final Paint _strokePaint;
  late final Paint _centerPaint;

  _TlWaveformPainter({required this.data, required this.color, this.isMuted = false}) {
    final waveColor = isMuted ? FluxForgeTheme.textTertiary.withValues(alpha: 0.4) : color.withValues(alpha: 0.7);
    _fillPaint = Paint()
      ..color = (isMuted ? FluxForgeTheme.textTertiary.withValues(alpha: 0.15) : color.withValues(alpha: 0.2))
      ..style = PaintingStyle.fill;
    _strokePaint = Paint()
      ..color = waveColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    _centerPaint = Paint()
      ..color = waveColor.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final centerY = size.height / 2;
    final scaleY = size.height / 2 * 0.85;
    final w = size.width.toInt();
    final samplesPerPixel = data.length / size.width;
    final len = data.length;

    // Pre-compute peaks ONCE (not 3x)
    final peaks = Float32List(w);
    for (int x = 0; x < w; x++) {
      final start = (x * samplesPerPixel).floor();
      final end = ((x + 1) * samplesPerPixel).floor().clamp(0, len);
      if (start >= len) break;
      double peak = 0.0;
      for (int i = start; i < end && i < len; i++) {
        final s = data[i].abs();
        if (s > peak) peak = s > 1.0 ? 1.0 : s;
      }
      peaks[x] = peak;
    }

    // Fill path (mirrored waveform)
    final fillPath = Path();
    fillPath.moveTo(0, centerY);
    for (int x = 0; x < w; x++) {
      fillPath.lineTo(x.toDouble(), centerY - peaks[x] * scaleY);
    }
    for (int x = w - 1; x >= 0; x--) {
      fillPath.lineTo(x.toDouble(), centerY + peaks[x] * scaleY);
    }
    fillPath.close();
    canvas.drawPath(fillPath, _fillPaint);

    // Stroke path (vertical bars)
    final strokePath = Path();
    for (int x = 0; x < w; x++) {
      final y1 = centerY - peaks[x] * scaleY;
      final y2 = centerY + peaks[x] * scaleY;
      if (x == 0) strokePath.moveTo(0, y1);
      strokePath.lineTo(x.toDouble(), y1);
      strokePath.lineTo(x.toDouble(), y2);
    }
    canvas.drawPath(strokePath, _strokePaint);

    // Center line
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), _centerPaint);
  }

  @override
  bool shouldRepaint(_TlWaveformPainter oldDelegate) =>
      !identical(oldDelegate.data, data) || oldDelegate.color != color || oldDelegate.isMuted != isMuted;
}

/// Grid line painter for track backgrounds
class _TlGridPainter extends CustomPainter {
  final double pixelsPerSecond;
  final double maxSeconds;

  const _TlGridPainter({required this.pixelsPerSecond, required this.maxSeconds});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 0.5;

    for (double t = 0; t <= maxSeconds; t += 1.0) {
      final x = t * pixelsPerSecond;
      if (x > size.width) break;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_TlGridPainter oldDelegate) =>
      oldDelegate.pixelsPerSecond != pixelsPerSecond;
}

/// 2D spatial field painter — shows event positions based on pan value
class _SpatialFieldPainter extends CustomPainter {
  final List<SlotCompositeEvent> events;
  _SpatialFieldPainter({required this.events});

  static const _busColors = [
    Color(0x88FFFFFF), Color(0xFF50FF98), Color(0xFF40C8FF),
    Color(0xFFFFD054), Color(0xFFB080FF), Color(0xFFFF9850),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (size.width < size.height ? size.width : size.height) / 2 - 16;

    final ringPaint = Paint()..color = Colors.white.withValues(alpha: 0.06)..style = PaintingStyle.stroke..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(Offset(cx, cy), radius * i / 3, ringPaint);
    }
    final crossPaint = Paint()..color = Colors.white.withValues(alpha: 0.04)..strokeWidth = 1;
    canvas.drawLine(Offset(cx, cy - radius), Offset(cx, cy + radius), crossPaint);
    canvas.drawLine(Offset(cx - radius, cy), Offset(cx + radius, cy), crossPaint);
    canvas.drawCircle(Offset(cx, cy), 4, Paint()..color = Colors.white.withValues(alpha: 0.3));

    for (int i = 0; i < events.length; i++) {
      final mainLayer = events[i].layers.where((l) => l.audioPath.isNotEmpty).firstOrNull;
      if (mainLayer == null) continue;
      final busId = mainLayer.busId ?? 2;
      final color = busId < _busColors.length ? _busColors[busId] : Colors.white54;
      final x = cx + mainLayer.pan * radius * 0.85;
      final y = cy - radius * 0.3 + (i % 5) * radius * 0.15;
      canvas.drawCircle(Offset(x, y), 10, Paint()..color = color.withValues(alpha: 0.15)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = color);
      final tp = TextPainter(
        text: TextSpan(text: events[i].name.length > 12 ? '${events[i].name.substring(0, 10)}..' : events[i].name,
          style: TextStyle(fontSize: 8, color: color.withValues(alpha: 0.8))),
        textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y + 8));
    }
    final lp = TextPainter(text: TextSpan(text: 'L', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.2), fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr)..layout();
    lp.paint(canvas, Offset(4, cy - lp.height / 2));
    final rp = TextPainter(text: TextSpan(text: 'R', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.2), fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr)..layout();
    rp.paint(canvas, Offset(size.width - rp.width - 4, cy - rp.height / 2));
  }

  @override
  bool shouldRepaint(_SpatialFieldPainter old) => old.events.length != events.length;
}
