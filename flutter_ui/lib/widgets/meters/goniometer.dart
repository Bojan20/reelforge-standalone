// Goniometer / Lissajous Display Widget
//
// Professional stereo phase visualization showing:
// - L/R correlation as Lissajous figure
// - Phase relationship between channels
// - Stereo width visualization
// - Peak hold traces
// - Grid with +45/-45 degree lines

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Goniometer configuration
class GoniometerConfig {
  final Color traceColor;
  final Color peakColor;
  final Color gridColor;
  final Color backgroundColor;
  final double lineWidth;
  final double fadeRate;
  final int historyLength;
  final bool showGrid;
  final bool showLabels;
  final bool showPeakHold;

  const GoniometerConfig({
    this.traceColor = const Color(0xFF4AFFFF),
    this.peakColor = const Color(0xFFFF6B4A),
    this.gridColor = const Color(0xFF2A2A35),
    this.backgroundColor = const Color(0xFF0A0A0E),
    this.lineWidth = 1.5,
    this.fadeRate = 0.95,
    this.historyLength = 512,
    this.showGrid = true,
    this.showLabels = true,
    this.showPeakHold = true,
  });
}

/// Ring buffer for history frames — O(1) insert/remove, zero allocations at steady state
class _RingBuffer<T> {
  final List<T?> _buffer;
  int _head = 0;
  int _count = 0;

  _RingBuffer(int capacity) : _buffer = List<T?>.filled(capacity, null);

  int get length => _count;
  int get capacity => _buffer.length;
  bool get isEmpty => _count == 0;

  void pushFront(T item) {
    _head = (_head - 1) % _buffer.length;
    _buffer[_head] = item;
    if (_count < _buffer.length) _count++;
  }

  T operator [](int index) {
    assert(index >= 0 && index < _count);
    return _buffer[(_head + index) % _buffer.length] as T;
  }

  void clear() {
    for (int i = 0; i < _buffer.length; i++) {
      _buffer[i] = null;
    }
    _head = 0;
    _count = 0;
  }
}

/// Goniometer Widget
class Goniometer extends StatefulWidget {
  final Float64List? leftData;
  final Float64List? rightData;
  final GoniometerConfig config;
  final double? size;

  const Goniometer({
    super.key,
    this.leftData,
    this.rightData,
    this.config = const GoniometerConfig(),
    this.size,
  });

  @override
  State<Goniometer> createState() => _GoniometerState();
}

class _GoniometerState extends State<Goniometer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Ring buffer for history — capacity = historyLength / 64
  late _RingBuffer<Float64List> _history;

  // Pre-allocated point buffer (x,y interleaved pairs)
  Float64List _pointBuffer = Float64List(0);

  // Peak hold positions
  double _maxX = 0;
  double _minX = 0;
  double _maxY = 0;
  double _minY = 0;

  @override
  void initState() {
    super.initState();
    _history = _RingBuffer<Float64List>(widget.config.historyLength ~/ 64);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateDisplay);
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateDisplay() {
    if (widget.leftData == null || widget.rightData == null) return;

    final left = widget.leftData!;
    final right = widget.rightData!;
    final len = math.min(left.length, right.length);

    if (len == 0) return;

    // Ensure point buffer capacity (x,y pairs → len*2)
    if (_pointBuffer.length < len * 2) {
      _pointBuffer = Float64List(len * 2);
    }

    // Convert L/R to M/S (rotated 45 degrees) into pre-allocated buffer
    for (int i = 0; i < len; i++) {
      final l = left[i];
      final r = right[i];
      final x = (l - r) / 2; // Side (width)
      final y = (l + r) / 2; // Mid (center)

      _pointBuffer[i * 2] = x;
      _pointBuffer[i * 2 + 1] = y;

      // Update peak hold
      if (x > _maxX) _maxX = x;
      if (x < _minX) _minX = x;
      if (y > _maxY) _maxY = y;
      if (y < _minY) _minY = y;
    }

    // Store a typed snapshot for this frame (compact: only the used portion)
    final snapshot = Float64List(len * 2);
    snapshot.setRange(0, len * 2, _pointBuffer);
    _history.pushFront(snapshot);

    // Decay peak hold
    _maxX *= 0.999;
    _minX *= 0.999;
    _maxY *= 0.999;
    _minY *= 0.999;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = widget.size ?? math.min(constraints.maxWidth, constraints.maxHeight);

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: widget.config.backgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: widget.config.gridColor),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size(size, size),
                painter: _GoniometerPainter(
                  history: _history,
                  maxX: _maxX,
                  minX: _minX,
                  maxY: _maxY,
                  minY: _minY,
                  config: widget.config,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GoniometerPainter extends CustomPainter {
  final _RingBuffer<Float64List> history;
  final double maxX, minX, maxY, minY;
  final GoniometerConfig config;

  // Pre-allocated paint objects — reused across frames
  final Paint _tracePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  final Paint _peakPaint = Paint()
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;

  final Paint _gridPaint = Paint()..strokeWidth = 1;

  // Reusable path — reset per history entry instead of re-allocating
  final Path _tracePath = Path();

  // Cached label TextPainters — created once, never re-allocated
  final Map<String, TextPainter> _labelCache = {};

  _GoniometerPainter({
    required this.history,
    required this.maxX,
    required this.minX,
    required this.maxY,
    required this.minY,
    required this.config,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final scale = size.width / 2.5;

    // Draw grid
    if (config.showGrid) {
      _drawGrid(canvas, size, centerX, centerY, scale);
    }

    // Draw traces with fade effect — single Paint reused, Path reset per entry
    _tracePaint.strokeWidth = config.lineWidth;

    for (int h = 0; h < history.length; h++) {
      final alpha = ((1.0 - h / history.length) * 255 * config.fadeRate).toInt();
      _tracePaint.color = config.traceColor.withAlpha(alpha);

      final points = history[h];
      final pointCount = points.length ~/ 2;
      if (pointCount == 0) continue;

      _tracePath.reset();
      for (int i = 0; i < pointCount; i++) {
        final x = centerX + points[i * 2] * scale;
        final y = centerY - points[i * 2 + 1] * scale;

        if (i == 0) {
          _tracePath.moveTo(x, y);
        } else {
          _tracePath.lineTo(x, y);
        }
      }

      canvas.drawPath(_tracePath, _tracePaint);
    }

    // Draw peak hold box
    if (config.showPeakHold) {
      _peakPaint.color = config.peakColor.withAlpha(128);

      final peakRect = Rect.fromLTRB(
        centerX + minX * scale,
        centerY - maxY * scale,
        centerX + maxX * scale,
        centerY - minY * scale,
      );

      canvas.drawRect(peakRect, _peakPaint);
    }

    // Draw labels
    if (config.showLabels) {
      _drawLabels(canvas, size);
    }
  }

  void _drawGrid(Canvas canvas, Size size, double centerX, double centerY, double scale) {
    _gridPaint.color = config.gridColor;

    final center = Offset(centerX, centerY);

    // Circle guides
    for (double r = 0.25; r <= 1.0; r += 0.25) {
      canvas.drawCircle(center, r * scale, _gridPaint);
    }

    // Cross lines (0 and 90 degrees - L/R and M/S axes)
    canvas.drawLine(
      Offset(centerX - scale, centerY),
      Offset(centerX + scale, centerY),
      _gridPaint,
    );
    canvas.drawLine(
      Offset(centerX, centerY - scale),
      Offset(centerX, centerY + scale),
      _gridPaint,
    );

    // Diagonal lines (+45 and -45 degrees - L and R)
    final diag = scale * 0.707; // cos(45)
    _gridPaint.color = config.gridColor.withAlpha(77);
    canvas.drawLine(
      Offset(centerX - diag, centerY - diag),
      Offset(centerX + diag, centerY + diag),
      _gridPaint,
    );
    canvas.drawLine(
      Offset(centerX + diag, centerY - diag),
      Offset(centerX - diag, centerY + diag),
      _gridPaint,
    );
  }

  void _drawLabels(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      color: config.gridColor.withAlpha(200),
      fontSize: 10,
      fontWeight: FontWeight.bold,
    );

    _drawCachedText(canvas, 'L', Offset(8, 8), textStyle);
    _drawCachedText(canvas, 'R', Offset(size.width - 16, 8), textStyle);
    _drawCachedText(canvas, 'M', Offset(size.width / 2 - 4, 4), textStyle);
    _drawCachedText(canvas, 'S', Offset(size.width - 14, size.height / 2 - 6), textStyle);
    _drawCachedText(canvas, '+', Offset(size.width / 2 - 4, size.height / 2 - size.height / 3), textStyle);
    _drawCachedText(canvas, '-', Offset(size.width / 2 - 4, size.height / 2 + size.height / 3 - 12), textStyle);
  }

  TextPainter _drawCachedText(Canvas canvas, String text, Offset position, TextStyle style) {
    final tp = _labelCache.putIfAbsent(text, () {
      return TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
    });
    tp.paint(canvas, position);
    return tp;
  }

  @override
  bool shouldRepaint(covariant _GoniometerPainter oldDelegate) {
    return true; // Always repaint — 60fps animation
  }
}
