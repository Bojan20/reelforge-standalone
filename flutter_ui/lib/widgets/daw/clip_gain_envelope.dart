/// Clip Gain Envelope (P2-DAW-7)
///
/// Visual gain envelope editor for timeline clips:
/// - Draggable breakpoints
/// - dB display
/// - Linear/curved interpolation
///
/// Created: 2026-02-02
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../lower_zone/lower_zone_types.dart';

/// Single breakpoint in gain envelope
class GainEnvelopePoint {
  final double time;   // 0-1 normalized position within clip
  final double gain;   // Linear gain (0-2, 1 = unity)

  const GainEnvelopePoint({required this.time, required this.gain});

  double get dB {
    if (gain <= 0.001) return -60.0;
    return 20.0 * math.log(gain) / math.ln10;
  }

  GainEnvelopePoint copyWith({double? time, double? gain}) {
    return GainEnvelopePoint(
      time: time ?? this.time,
      gain: gain ?? this.gain,
    );
  }

  Map<String, dynamic> toJson() => {'time': time, 'gain': gain};

  factory GainEnvelopePoint.fromJson(Map<String, dynamic> json) {
    return GainEnvelopePoint(
      time: (json['time'] as num).toDouble(),
      gain: (json['gain'] as num).toDouble(),
    );
  }
}

/// Gain envelope for a clip
class ClipGainEnvelope {
  final List<GainEnvelopePoint> points;

  const ClipGainEnvelope({this.points = const []});

  /// Get gain at normalized time (0-1)
  double gainAt(double t) {
    if (points.isEmpty) return 1.0;
    if (points.length == 1) return points.first.gain;

    // Find surrounding points
    final sorted = List<GainEnvelopePoint>.from(points)
      ..sort((a, b) => a.time.compareTo(b.time));

    if (t <= sorted.first.time) return sorted.first.gain;
    if (t >= sorted.last.time) return sorted.last.gain;

    for (int i = 0; i < sorted.length - 1; i++) {
      if (t >= sorted[i].time && t <= sorted[i + 1].time) {
        final range = sorted[i + 1].time - sorted[i].time;
        if (range <= 0) return sorted[i].gain;
        final ratio = (t - sorted[i].time) / range;
        return sorted[i].gain + (sorted[i + 1].gain - sorted[i].gain) * ratio;
      }
    }
    return 1.0;
  }

  ClipGainEnvelope addPoint(GainEnvelopePoint point) {
    return ClipGainEnvelope(points: [...points, point]);
  }

  ClipGainEnvelope updatePoint(int index, GainEnvelopePoint point) {
    final newPoints = List<GainEnvelopePoint>.from(points);
    if (index >= 0 && index < newPoints.length) {
      newPoints[index] = point;
    }
    return ClipGainEnvelope(points: newPoints);
  }

  ClipGainEnvelope removePoint(int index) {
    final newPoints = List<GainEnvelopePoint>.from(points);
    if (index >= 0 && index < newPoints.length) {
      newPoints.removeAt(index);
    }
    return ClipGainEnvelope(points: newPoints);
  }

  Map<String, dynamic> toJson() => {
    'points': points.map((p) => p.toJson()).toList(),
  };

  factory ClipGainEnvelope.fromJson(Map<String, dynamic> json) {
    final pointsList = (json['points'] as List<dynamic>?)
        ?.map((p) => GainEnvelopePoint.fromJson(p as Map<String, dynamic>))
        .toList() ?? [];
    return ClipGainEnvelope(points: pointsList);
  }
}

/// Visual gain envelope editor widget
class ClipGainEnvelopeEditor extends StatefulWidget {
  final ClipGainEnvelope envelope;
  final double width;
  final double height;
  final void Function(ClipGainEnvelope)? onEnvelopeChanged;

  const ClipGainEnvelopeEditor({
    super.key,
    required this.envelope,
    this.width = 300,
    this.height = 100,
    this.onEnvelopeChanged,
  });

  @override
  State<ClipGainEnvelopeEditor> createState() => _ClipGainEnvelopeEditorState();
}

class _ClipGainEnvelopeEditorState extends State<ClipGainEnvelopeEditor> {
  int? _draggingIndex;
  GainEnvelopePoint? _hoverPoint;

  void _handleTapDown(TapDownDetails details) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(details.globalPosition);
    final t = (local.dx / widget.width).clamp(0.0, 1.0);
    final gain = (1.0 - local.dy / widget.height) * 2.0; // 0-2 range

    // Add new point
    final newEnvelope = widget.envelope.addPoint(
      GainEnvelopePoint(time: t, gain: gain.clamp(0.0, 2.0)),
    );
    widget.onEnvelopeChanged?.call(newEnvelope);
  }

  void _handleDragStart(int index, DragStartDetails details) {
    setState(() => _draggingIndex = index);
  }

  void _handleDragUpdate(int index, DragUpdateDetails details) {
    if (_draggingIndex != index) return;

    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(details.globalPosition);
    final t = (local.dx / widget.width).clamp(0.0, 1.0);
    final gain = ((1.0 - local.dy / widget.height) * 2.0).clamp(0.0, 2.0);

    final newEnvelope = widget.envelope.updatePoint(
      index,
      GainEnvelopePoint(time: t, gain: gain),
    );
    widget.onEnvelopeChanged?.call(newEnvelope);
  }

  void _handleDragEnd(int index, DragEndDetails details) {
    setState(() => _draggingIndex = null);
  }

  void _handleDoubleTap(int index) {
    // Remove point on double-tap
    final newEnvelope = widget.envelope.removePoint(index);
    widget.onEnvelopeChanged?.call(newEnvelope);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: LowerZoneColors.bgDeep,
          border: Border.all(color: LowerZoneColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: CustomPaint(
          painter: _GainEnvelopePainter(
            envelope: widget.envelope,
            draggingIndex: _draggingIndex,
          ),
          child: Stack(
            children: [
              // Unity line label
              Positioned(
                left: 4,
                top: widget.height / 2 - 8,
                child: const Text('0dB', style: TextStyle(fontSize: 9, color: LowerZoneColors.textMuted)),
              ),
              // Draggable points
              ...widget.envelope.points.asMap().entries.map((entry) {
                final index = entry.key;
                final point = entry.value;
                final x = point.time * widget.width;
                final y = (1.0 - point.gain / 2.0) * widget.height;

                return Positioned(
                  left: x - 6,
                  top: y - 6,
                  child: GestureDetector(
                    onPanStart: (d) => _handleDragStart(index, d),
                    onPanUpdate: (d) => _handleDragUpdate(index, d),
                    onPanEnd: (d) => _handleDragEnd(index, d),
                    onDoubleTap: () => _handleDoubleTap(index),
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _hoverPoint = point),
                      onExit: (_) => setState(() => _hoverPoint = null),
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _draggingIndex == index
                              ? LowerZoneColors.dawAccent
                              : point.gain > 1.0
                                  ? const Color(0xFFFF9040)
                                  : LowerZoneColors.dawAccent.withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              // Hover tooltip
              if (_hoverPoint != null)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: LowerZoneColors.bgMid,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${_hoverPoint!.dB.toStringAsFixed(1)} dB',
                      style: TextStyle(
                        fontSize: 10,
                        color: _hoverPoint!.gain > 1.0 ? const Color(0xFFFF9040) : LowerZoneColors.textPrimary,
                        fontFamily: 'monospace',
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

class _GainEnvelopePainter extends CustomPainter {
  final ClipGainEnvelope envelope;
  final int? draggingIndex;

  _GainEnvelopePainter({required this.envelope, this.draggingIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Unity line (0dB)
    final unityY = size.height / 2;
    canvas.drawLine(
      Offset(0, unityY),
      Offset(size.width, unityY),
      Paint()
        ..color = LowerZoneColors.textMuted.withValues(alpha: 0.3)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );

    // Grid lines
    final gridPaint = Paint()
      ..color = LowerZoneColors.border.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (envelope.points.isEmpty) return;

    // Draw envelope curve
    final sorted = List<GainEnvelopePoint>.from(envelope.points)
      ..sort((a, b) => a.time.compareTo(b.time));

    final path = Path();
    for (int i = 0; i < sorted.length; i++) {
      final point = sorted[i];
      final x = point.time * size.width;
      final y = (1.0 - point.gain / 2.0) * size.height;

      if (i == 0) {
        // Line from start
        path.moveTo(0, y);
        path.lineTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    // Line to end
    path.lineTo(size.width, (1.0 - sorted.last.gain / 2.0) * size.height);

    // Gradient based on gain
    paint.color = LowerZoneColors.dawAccent;
    canvas.drawPath(path, paint);

    // Fill under curve
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..color = LowerZoneColors.dawAccent.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_GainEnvelopePainter oldDelegate) {
    return envelope != oldDelegate.envelope || draggingIndex != oldDelegate.draggingIndex;
  }
}
