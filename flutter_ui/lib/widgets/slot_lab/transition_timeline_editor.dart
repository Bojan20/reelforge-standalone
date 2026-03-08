/// Transition Timeline Editor — Visual keyframe editor for scene transitions
///
/// 6-track CustomPaint timeline showing per-phase timing, delays, and intensity.
/// Drag handles to adjust phase durations and stagger delays in real-time.
///
/// Tracks:
///   1. FADE    — Background blackout phase
///   2. BURST   — Ray expansion behind plaque
///   3. PLAQUE  — Main plaque entrance animation
///   4. GLOW    — Pulsing glow halo (continuous)
///   5. SHIMMER — Diagonal sweep highlight (continuous)
///   6. AUDIO   — Per-phase audio stage triggers
library;

import 'package:flutter/material.dart';
import '../../models/game_flow_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TRACK DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════════

enum _TimelineTrack {
  fade('FADE', Color(0xFF4A9EFF), 350, 0),
  burst('BURST', Color(0xFFFF6D00), 750, 150),
  plaque('PLAQUE', Color(0xFFE040FB), 700, 250),
  glow('GLOW', Color(0xFF00E5FF), 1600, 800),
  shimmer('SHIMMER', Color(0xFFFFD700), 2000, 1200),
  audio('AUDIO', Color(0xFF66BB6A), 0, 0);

  final String label;
  final Color color;
  final int defaultDurationMs;
  final int defaultDelayMs;

  const _TimelineTrack(this.label, this.color, this.defaultDurationMs, this.defaultDelayMs);
}

// ═══════════════════════════════════════════════════════════════════════════
// TIMELINE EDITOR WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class TransitionTimelineEditor extends StatefulWidget {
  final SceneTransitionConfig config;
  final ValueChanged<SceneTransitionConfig> onChanged;
  final double totalDurationMs;

  const TransitionTimelineEditor({
    super.key,
    required this.config,
    required this.onChanged,
    this.totalDurationMs = 5000,
  });

  @override
  State<TransitionTimelineEditor> createState() => _TransitionTimelineEditorState();
}

class _TransitionTimelineEditorState extends State<TransitionTimelineEditor> {
  static const double _trackHeight = 22.0;
  static const double _labelWidth = 52.0;
  static const double _handleWidth = 8.0;
  static const double _topPadding = 20.0; // ruler area

  _DragTarget? _activeDrag;
  double _dragStartX = 0;
  int _dragStartValue = 0;

  double get _totalMs => widget.totalDurationMs;

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK DATA EXTRACTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Duration scale factor (same as overlay)
  double get _dScale => widget.config.durationMs.clamp(500, 30000) / 3000.0;

  int _getDelay(_TimelineTrack track) {
    final cfg = widget.config;
    return switch (track) {
      _TimelineTrack.fade => 0,
      _TimelineTrack.burst => cfg.burstDelayMs ?? (_dScale * 150).round(),
      _TimelineTrack.plaque => cfg.plaqueDelayMs ?? (_dScale * 250).round(),
      _TimelineTrack.glow => cfg.glowDelayMs ?? (_dScale * 800).round(),
      _TimelineTrack.shimmer => cfg.shimmerDelayMs ?? (_dScale * 1200).round(),
      _TimelineTrack.audio => 0,
    };
  }

  int _getDuration(_TimelineTrack track) {
    final cfg = widget.config;
    final s = _dScale;
    return switch (track) {
      _TimelineTrack.fade => cfg.fadePhaseMs ?? (s * 350).round(),
      _TimelineTrack.burst => cfg.burstPhaseMs ?? (s * 750).round(),
      _TimelineTrack.plaque => cfg.plaquePhaseMs ?? (s * 700).round(),
      _TimelineTrack.glow => cfg.glowPhaseMs ?? (s * 1600).round().clamp(800, 4000),
      _TimelineTrack.shimmer => cfg.shimmerPhaseMs ?? (s * 2000).round().clamp(1000, 5000),
      _TimelineTrack.audio => 200, // fixed visual marker width
    };
  }

  bool _isEnabled(_TimelineTrack track) {
    return switch (track) {
      _TimelineTrack.burst => widget.config.showBurst,
      _TimelineTrack.glow => widget.config.showGlow,
      _TimelineTrack.shimmer => widget.config.showShimmer,
      _ => true,
    };
  }

  double _getIntensity(_TimelineTrack track) {
    return switch (track) {
      _TimelineTrack.burst => widget.config.burstIntensity,
      _TimelineTrack.glow => widget.config.glowIntensity,
      _TimelineTrack.shimmer => widget.config.shimmerIntensity,
      _ => 1.0,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LAYOUT
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final tracks = _TimelineTrack.values;
    final totalHeight = _topPadding + tracks.length * (_trackHeight + 2) + 8;

    return SizedBox(
      height: totalHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final timelineWidth = constraints.maxWidth - _labelWidth - 8;
          return Listener(
            onPointerDown: (e) => _onPointerDown(e, timelineWidth),
            onPointerMove: (e) => _onPointerMove(e, timelineWidth),
            onPointerUp: (_) => _onPointerUp(),
            child: CustomPaint(
              size: Size(constraints.maxWidth, totalHeight),
              painter: _TimelineEditorPainter(
                tracks: tracks,
                getDelay: _getDelay,
                getDuration: _getDuration,
                isEnabled: _isEnabled,
                getIntensity: _getIntensity,
                totalMs: _totalMs,
                labelWidth: _labelWidth,
                trackHeight: _trackHeight,
                topPadding: _topPadding,
                activeDrag: _activeDrag,
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DRAG INTERACTION
  // ═══════════════════════════════════════════════════════════════════════════

  void _onPointerDown(PointerDownEvent event, double timelineWidth) {
    final localX = event.localPosition.dx - _labelWidth;
    final localY = event.localPosition.dy - _topPadding;
    if (localX < 0 || localY < 0) return;

    final trackIndex = localY ~/ (_trackHeight + 2);
    final tracks = _TimelineTrack.values;
    if (trackIndex >= tracks.length) return;

    final track = tracks[trackIndex];
    if (track == _TimelineTrack.audio) return; // audio track not draggable

    final msPerPx = _totalMs / timelineWidth;
    final delay = _getDelay(track);
    final duration = _getDuration(track);

    final delayPx = delay / msPerPx;
    final endPx = (delay + duration) / msPerPx;

    // Check if near start handle (delay), end handle (duration), or bar (move both)
    if ((localX - delayPx).abs() < _handleWidth) {
      _activeDrag = _DragTarget(track, _DragPart.start);
      _dragStartX = event.localPosition.dx;
      _dragStartValue = delay;
      setState(() {});
    } else if ((localX - endPx).abs() < _handleWidth) {
      _activeDrag = _DragTarget(track, _DragPart.end);
      _dragStartX = event.localPosition.dx;
      _dragStartValue = duration;
      setState(() {});
    } else if (localX > delayPx && localX < endPx) {
      _activeDrag = _DragTarget(track, _DragPart.bar);
      _dragStartX = event.localPosition.dx;
      _dragStartValue = delay;
      setState(() {});
    }
  }

  void _onPointerMove(PointerMoveEvent event, double timelineWidth) {
    if (_activeDrag == null) return;

    final msPerPx = _totalMs / timelineWidth;
    final deltaPx = event.localPosition.dx - _dragStartX;
    final deltaMs = (deltaPx * msPerPx).round();

    final track = _activeDrag!.track;
    final part = _activeDrag!.part;

    switch (part) {
      case _DragPart.start:
        // Move delay (start position)
        final newDelay = (_dragStartValue + deltaMs).clamp(0, _totalMs.toInt() - 100);
        _updateDelay(track, newDelay);

      case _DragPart.end:
        // Resize duration
        final newDuration = (_dragStartValue + deltaMs).clamp(50, _totalMs.toInt());
        _updateDuration(track, newDuration);

      case _DragPart.bar:
        // Move entire bar (delay only)
        final newDelay = (_dragStartValue + deltaMs).clamp(0, _totalMs.toInt() - 100);
        _updateDelay(track, newDelay);
    }
  }

  void _onPointerUp() {
    if (_activeDrag != null) {
      _activeDrag = null;
      setState(() {});
    }
  }

  void _updateDelay(_TimelineTrack track, int delayMs) {
    final cfg = widget.config;
    final updated = switch (track) {
      _TimelineTrack.burst => cfg.copyWith(burstDelayMs: delayMs),
      _TimelineTrack.plaque => cfg.copyWith(plaqueDelayMs: delayMs),
      _TimelineTrack.glow => cfg.copyWith(glowDelayMs: delayMs),
      _TimelineTrack.shimmer => cfg.copyWith(shimmerDelayMs: delayMs),
      _ => cfg,
    };
    widget.onChanged(updated);
  }

  void _updateDuration(_TimelineTrack track, int durationMs) {
    final cfg = widget.config;
    final updated = switch (track) {
      _TimelineTrack.fade => cfg.copyWith(fadePhaseMs: durationMs),
      _TimelineTrack.burst => cfg.copyWith(burstPhaseMs: durationMs),
      _TimelineTrack.plaque => cfg.copyWith(plaquePhaseMs: durationMs),
      _TimelineTrack.glow => cfg.copyWith(glowPhaseMs: durationMs),
      _TimelineTrack.shimmer => cfg.copyWith(shimmerPhaseMs: durationMs),
      _ => cfg,
    };
    widget.onChanged(updated);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DRAG TARGET
// ═══════════════════════════════════════════════════════════════════════════

enum _DragPart { start, end, bar }

class _DragTarget {
  final _TimelineTrack track;
  final _DragPart part;
  const _DragTarget(this.track, this.part);
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTER — 6-track timeline with ruler, bars, and handles
// ═══════════════════════════════════════════════════════════════════════════

class _TimelineEditorPainter extends CustomPainter {
  final List<_TimelineTrack> tracks;
  final int Function(_TimelineTrack) getDelay;
  final int Function(_TimelineTrack) getDuration;
  final bool Function(_TimelineTrack) isEnabled;
  final double Function(_TimelineTrack) getIntensity;
  final double totalMs;
  final double labelWidth;
  final double trackHeight;
  final double topPadding;
  final _DragTarget? activeDrag;

  _TimelineEditorPainter({
    required this.tracks,
    required this.getDelay,
    required this.getDuration,
    required this.isEnabled,
    required this.getIntensity,
    required this.totalMs,
    required this.labelWidth,
    required this.trackHeight,
    required this.topPadding,
    required this.activeDrag,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final timelineWidth = size.width - labelWidth - 8;
    final msPerPx = totalMs / timelineWidth;

    _drawRuler(canvas, size, timelineWidth, msPerPx);
    _drawTracks(canvas, size, timelineWidth, msPerPx);
  }

  void _drawRuler(Canvas canvas, Size size, double timelineWidth, double msPerPx) {
    final paint = Paint()
      ..color = const Color(0xFF303038)
      ..strokeWidth = 0.5;

    // Draw time markers every 500ms
    final intervalMs = totalMs > 8000 ? 1000 : 500;
    for (var ms = 0; ms <= totalMs; ms += intervalMs) {
      final x = labelWidth + (ms / totalMs) * timelineWidth;
      final isMajor = ms % 1000 == 0;

      canvas.drawLine(
        Offset(x, isMajor ? 2 : 8),
        Offset(x, topPadding - 2),
        paint..color = isMajor ? const Color(0xFF505060) : const Color(0xFF303038),
      );

      if (isMajor) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${(ms / 1000).toStringAsFixed(ms % 1000 == 0 ? 0 : 1)}s',
            style: const TextStyle(color: Color(0xFF606068), fontSize: 8),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, 1));
      }
    }

    // Baseline
    canvas.drawLine(
      Offset(labelWidth, topPadding - 1),
      Offset(size.width - 4, topPadding - 1),
      paint..color = const Color(0xFF2A2A38),
    );
  }

  void _drawTracks(Canvas canvas, Size size, double timelineWidth, double msPerPx) {
    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final y = topPadding + i * (trackHeight + 2);
      final enabled = isEnabled(track);
      final intensity = getIntensity(track);
      final isDragging = activeDrag?.track == track;

      // Track background
      final bgPaint = Paint()
        ..color = isDragging
            ? const Color(0xFF1A1A28)
            : const Color(0xFF12121A);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, y, size.width, trackHeight),
          const Radius.circular(2),
        ),
        bgPaint,
      );

      // Track label
      final labelTp = TextPainter(
        text: TextSpan(
          text: track.label,
          style: TextStyle(
            color: enabled ? track.color.withOpacity(0.8) : const Color(0xFF404048),
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelTp.paint(canvas, Offset(4, y + (trackHeight - labelTp.height) / 2));

      if (track == _TimelineTrack.audio) {
        // Audio track: draw marker triangles at burst and plaque audio positions
        _drawAudioMarkers(canvas, timelineWidth, y);
        continue;
      }

      final delay = getDelay(track);
      final duration = getDuration(track);
      final startX = labelWidth + (delay / totalMs) * timelineWidth;
      final barWidth = (duration / totalMs) * timelineWidth;
      final endX = startX + barWidth;

      if (!enabled) {
        // Disabled track: dashed outline
        final dashPaint = Paint()
          ..color = const Color(0xFF303038)
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(startX, y + 2, barWidth, trackHeight - 4),
            const Radius.circular(2),
          ),
          dashPaint,
        );
        continue;
      }

      // Duration bar
      final barPaint = Paint()
        ..color = track.color.withOpacity(0.25 * intensity)
        ..style = PaintingStyle.fill;
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(startX, y + 2, barWidth, trackHeight - 4),
        const Radius.circular(2),
      );
      canvas.drawRRect(barRect, barPaint);

      // Bar border
      canvas.drawRRect(
        barRect,
        Paint()
          ..color = track.color.withOpacity(isDragging ? 0.8 : 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isDragging ? 1.5 : 0.5,
      );

      // Intensity fill (proportional to intensity)
      if (intensity < 1.0) {
        final fillWidth = barWidth * intensity;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(startX, y + 2, fillWidth, trackHeight - 4),
            const Radius.circular(2),
          ),
          Paint()..color = track.color.withOpacity(0.15),
        );
      }

      // Start handle
      _drawHandle(canvas, startX, y, trackHeight, track.color, isDragging && activeDrag?.part == _DragPart.start);

      // End handle
      _drawHandle(canvas, endX, y, trackHeight, track.color, isDragging && activeDrag?.part == _DragPart.end);

      // Duration label inside bar
      if (barWidth > 30) {
        final durTp = TextPainter(
          text: TextSpan(
            text: '${duration}ms',
            style: TextStyle(
              color: track.color.withOpacity(0.6),
              fontSize: 7,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        durTp.paint(canvas, Offset(
          startX + (barWidth - durTp.width) / 2,
          y + (trackHeight - durTp.height) / 2,
        ));
      }
    }
  }

  void _drawHandle(Canvas canvas, double x, double y, double height, Color color, bool active) {
    final paint = Paint()
      ..color = active ? color : color.withOpacity(0.6)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 2, y + 3, 4, height - 6),
        const Radius.circular(1),
      ),
      paint,
    );
  }

  void _drawAudioMarkers(Canvas canvas, double timelineWidth, double y) {
    // Draw triangular markers at audio trigger points
    final markerPaint = Paint()
      ..color = const Color(0xFF66BB6A).withOpacity(0.6)
      ..style = PaintingStyle.fill;

    // Markers correspond to burst and plaque audio delays
    final burstDelay = getDelay(_TimelineTrack.burst);
    final plaqueDelay = getDelay(_TimelineTrack.plaque);

    for (final ms in [burstDelay, plaqueDelay]) {
      final x = labelWidth + (ms / totalMs) * timelineWidth;
      final path = Path()
        ..moveTo(x, y + 4)
        ..lineTo(x + 5, y + trackHeight / 2)
        ..lineTo(x, y + trackHeight - 4)
        ..close();
      canvas.drawPath(path, markerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineEditorPainter oldDelegate) => true;
}
