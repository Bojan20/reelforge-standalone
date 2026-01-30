/// Loudness History Graph Widget
///
/// P2-18: Real-time LUFS history visualization with zoom/pan.
/// Shows integrated, short-term, and momentary loudness over time.

import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// LUFS history sample
class LufsHistorySample {
  final DateTime timestamp;
  final double integrated;  // LUFS integrated
  final double shortTerm;   // LUFS short-term (3s)
  final double momentary;   // LUFS momentary (400ms)
  final double truePeak;    // dBTP

  const LufsHistorySample({
    required this.timestamp,
    required this.integrated,
    required this.shortTerm,
    required this.momentary,
    required this.truePeak,
  });

  int get timestampMs => timestamp.millisecondsSinceEpoch;
}

/// Loudness history buffer
class LufsHistoryBuffer {
  final int maxSamples;
  final Queue<LufsHistorySample> _samples = Queue();

  LufsHistoryBuffer({this.maxSamples = 3600}); // 1 hour at 1 sample/sec

  /// Add a sample
  void add(LufsHistorySample sample) {
    _samples.add(sample);
    if (_samples.length > maxSamples) {
      _samples.removeFirst();
    }
  }

  /// Clear all samples
  void clear() {
    _samples.clear();
  }

  /// Get all samples
  List<LufsHistorySample> get samples => _samples.toList();

  /// Get sample count
  int get length => _samples.length;

  /// Get time range (first to last timestamp)
  Duration? get timeRange {
    if (_samples.length < 2) return null;
    return _samples.last.timestamp.difference(_samples.first.timestamp);
  }

  /// Get min/max for a metric
  (double min, double max) getRange(String metric) {
    if (_samples.isEmpty) return (0.0, 0.0);

    double min = double.infinity;
    double max = double.negativeInfinity;

    for (final sample in _samples) {
      final value = switch (metric) {
        'integrated' => sample.integrated,
        'shortTerm' => sample.shortTerm,
        'momentary' => sample.momentary,
        'truePeak' => sample.truePeak,
        _ => 0.0,
      };

      if (value < min) min = value;
      if (value > max) max = value;
    }

    return (min, max);
  }
}

/// Loudness History Graph Widget
class LoudnessHistoryGraph extends StatefulWidget {
  final LufsHistoryBuffer buffer;
  final double width;
  final double height;
  final Set<String> visibleMetrics; // 'integrated', 'shortTerm', 'momentary', 'truePeak'
  final Color backgroundColor;
  final bool showGrid;
  final bool showLegend;
  final double Function(double lufs)? targetLineValue; // e.g., -14 LUFS for streaming

  const LoudnessHistoryGraph({
    super.key,
    required this.buffer,
    this.width = 800,
    this.height = 200,
    this.visibleMetrics = const {'integrated', 'shortTerm', 'momentary'},
    this.backgroundColor = const Color(0xFF121216),
    this.showGrid = true,
    this.showLegend = true,
    this.targetLineValue,
  });

  @override
  State<LoudnessHistoryGraph> createState() => _LoudnessHistoryGraphState();
}

class _LoudnessHistoryGraphState extends State<LoudnessHistoryGraph> {
  // Zoom/pan state
  double _zoomLevel = 1.0;
  double _panOffset = 0.0;

  // Mouse hover state
  Offset? _hoverPosition;
  LufsHistorySample? _hoveredSample;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Stack(
        children: [
          // Graph canvas
          Positioned.fill(
            child: MouseRegion(
              onHover: _handleHover,
              onExit: (_) => setState(() {
                _hoverPosition = null;
                _hoveredSample = null;
              }),
              child: GestureDetector(
                onScaleUpdate: _handleScaleUpdate,
                child: CustomPaint(
                  painter: _LoudnessGraphPainter(
                    buffer: widget.buffer,
                    visibleMetrics: widget.visibleMetrics,
                    zoomLevel: _zoomLevel,
                    panOffset: _panOffset,
                    hoverPosition: _hoverPosition,
                    showGrid: widget.showGrid,
                    targetLineValue: widget.targetLineValue,
                  ),
                ),
              ),
            ),
          ),
          // Legend (top-right)
          if (widget.showLegend)
            Positioned(
              top: 8,
              right: 8,
              child: _buildLegend(),
            ),
          // Hover tooltip
          if (_hoveredSample != null && _hoverPosition != null)
            Positioned(
              left: _hoverPosition!.dx + 12,
              top: _hoverPosition!.dy - 60,
              child: _buildTooltip(_hoveredSample!),
            ),
          // Zoom controls (bottom-right)
          Positioned(
            bottom: 8,
            right: 8,
            child: _buildZoomControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.visibleMetrics.contains('integrated'))
            _legendItem('Integrated', const Color(0xFF4A9EFF)),
          if (widget.visibleMetrics.contains('shortTerm'))
            _legendItem('Short-term', const Color(0xFFFF9040)),
          if (widget.visibleMetrics.contains('momentary'))
            _legendItem('Momentary', const Color(0xFF40FF90)),
          if (widget.visibleMetrics.contains('truePeak'))
            _legendItem('True Peak', const Color(0xFFFF4060)),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 2,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTooltip(LufsHistorySample sample) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${sample.timestamp.hour.toString().padLeft(2, '0')}:'
            '${sample.timestamp.minute.toString().padLeft(2, '0')}:'
            '${sample.timestamp.second.toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 10, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          _tooltipRow('I', sample.integrated, const Color(0xFF4A9EFF)),
          _tooltipRow('S', sample.shortTerm, const Color(0xFFFF9040)),
          _tooltipRow('M', sample.momentary, const Color(0xFF40FF90)),
          _tooltipRow('TP', sample.truePeak, const Color(0xFFFF4060)),
        ],
      ),
    );
  }

  Widget _tooltipRow(String label, double value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(fontSize: 9, color: color),
        ),
        Text(
          '${value.toStringAsFixed(1)} LUFS',
          style: const TextStyle(fontSize: 9, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildZoomControls() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 16),
            onPressed: () => setState(() => _zoomLevel = (_zoomLevel / 1.5).clamp(0.1, 10.0)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: Colors.white70,
          ),
          Text(
            '${(_zoomLevel * 100).toInt()}%',
            style: const TextStyle(fontSize: 10, color: Colors.white70),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            onPressed: () => setState(() => _zoomLevel = (_zoomLevel * 1.5).clamp(0.1, 10.0)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: Colors.white70,
          ),
        ],
      ),
    );
  }

  void _handleHover(PointerHoverEvent event) {
    // Find closest sample to hover position
    // TODO: Implement sample lookup logic
    setState(() {
      _hoverPosition = event.localPosition;
    });
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _zoomLevel = (_zoomLevel * details.scale).clamp(0.1, 10.0);
      _panOffset += details.focalPointDelta.dx;
    });
  }
}

/// Custom painter for loudness graph
class _LoudnessGraphPainter extends CustomPainter {
  final LufsHistoryBuffer buffer;
  final Set<String> visibleMetrics;
  final double zoomLevel;
  final double panOffset;
  final Offset? hoverPosition;
  final bool showGrid;
  final double Function(double)? targetLineValue;

  _LoudnessGraphPainter({
    required this.buffer,
    required this.visibleMetrics,
    required this.zoomLevel,
    required this.panOffset,
    this.hoverPosition,
    required this.showGrid,
    this.targetLineValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (buffer.length < 2) {
      _drawEmptyState(canvas, size);
      return;
    }

    // Calculate value range (-60 to 0 LUFS typically)
    const minLufs = -60.0;
    const maxLufs = 0.0;
    final lufsRange = maxLufs - minLufs;

    // Draw grid
    if (showGrid) {
      _drawGrid(canvas, size, minLufs, maxLufs);
    }

    // Draw target line (e.g., -14 LUFS)
    if (targetLineValue != null) {
      _drawTargetLine(canvas, size, targetLineValue!(0), minLufs, lufsRange);
    }

    // Draw metrics
    if (visibleMetrics.contains('integrated')) {
      _drawMetric(canvas, size, 'integrated', const Color(0xFF4A9EFF), minLufs, lufsRange);
    }
    if (visibleMetrics.contains('shortTerm')) {
      _drawMetric(canvas, size, 'shortTerm', const Color(0xFFFF9040), minLufs, lufsRange);
    }
    if (visibleMetrics.contains('momentary')) {
      _drawMetric(canvas, size, 'momentary', const Color(0xFF40FF90), minLufs, lufsRange);
    }
    if (visibleMetrics.contains('truePeak')) {
      _drawMetric(canvas, size, 'truePeak', const Color(0xFFFF4060), minLufs, lufsRange);
    }

    // Draw hover line
    if (hoverPosition != null) {
      _drawHoverLine(canvas, size);
    }
  }

  void _drawEmptyState(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'No loudness data',
        style: TextStyle(color: Colors.white38, fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  void _drawGrid(Canvas canvas, Size size, double minLufs, double maxLufs) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    // Horizontal grid lines (every 6 dB)
    for (double lufs = minLufs; lufs <= maxLufs; lufs += 6.0) {
      final y = _lufsToY(lufs, size, minLufs, maxLufs - minLufs);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Vertical grid lines (every 10 seconds)
    // TODO: Calculate time-based grid
  }

  void _drawTargetLine(Canvas canvas, Size size, double targetLufs, double minLufs, double lufsRange) {
    final y = _lufsToY(targetLufs, size, minLufs, lufsRange);
    final paint = Paint()
      ..color = Colors.yellow.withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  void _drawMetric(Canvas canvas, Size size, String metric, Color color, double minLufs, double lufsRange) {
    final samples = buffer.samples;
    if (samples.isEmpty) return;

    final path = Path();
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < samples.length; i++) {
      final sample = samples[i];
      final value = switch (metric) {
        'integrated' => sample.integrated,
        'shortTerm' => sample.shortTerm,
        'momentary' => sample.momentary,
        'truePeak' => sample.truePeak,
        _ => 0.0,
      };

      final x = _indexToX(i, size);
      final y = _lufsToY(value, size, minLufs, lufsRange);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  void _drawHoverLine(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(hoverPosition!.dx, 0),
      Offset(hoverPosition!.dx, size.height),
      paint,
    );
  }

  double _indexToX(int index, Size size) {
    final totalSamples = buffer.length;
    return (index / math.max(1, totalSamples - 1)) * size.width * zoomLevel + panOffset;
  }

  double _lufsToY(double lufs, Size size, double minLufs, double lufsRange) {
    final normalized = (lufs - minLufs) / lufsRange;
    return size.height * (1.0 - normalized); // Invert Y (0 at top)
  }

  @override
  bool shouldRepaint(_LoudnessGraphPainter oldDelegate) {
    return oldDelegate.buffer != buffer ||
           oldDelegate.zoomLevel != zoomLevel ||
           oldDelegate.panOffset != panOffset ||
           oldDelegate.hoverPosition != hoverPosition;
  }
}
