// ═══════════════════════════════════════════════════════════════════════════════
// LATENCY HISTOGRAM PANEL — Visual latency distribution analysis
// ═══════════════════════════════════════════════════════════════════════════════
//
// P3.12: Histogram visualization of latency distribution for network connections.
// Shows distribution buckets, percentiles, and outlier detection.

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Latency histogram bucket
class LatencyBucket {
  final double minMs;
  final double maxMs;
  final int count;

  LatencyBucket({
    required this.minMs,
    required this.maxMs,
    required this.count,
  });

  String get label {
    if (maxMs == double.infinity) {
      return '>${minMs.toInt()}';
    }
    return '${minMs.toInt()}-${maxMs.toInt()}';
  }
}

/// Latency statistics
class LatencyStats {
  final double min;
  final double max;
  final double avg;
  final double median;
  final double p95;
  final double p99;
  final double stdDev;
  final int sampleCount;
  final int outlierCount;

  LatencyStats({
    required this.min,
    required this.max,
    required this.avg,
    required this.median,
    required this.p95,
    required this.p99,
    required this.stdDev,
    required this.sampleCount,
    required this.outlierCount,
  });

  factory LatencyStats.empty() {
    return LatencyStats(
      min: 0,
      max: 0,
      avg: 0,
      median: 0,
      p95: 0,
      p99: 0,
      stdDev: 0,
      sampleCount: 0,
      outlierCount: 0,
    );
  }

  factory LatencyStats.fromSamples(List<double> samples) {
    if (samples.isEmpty) return LatencyStats.empty();

    final sorted = List<double>.from(samples)..sort();
    final n = sorted.length;

    // Basic stats
    final min = sorted.first;
    final max = sorted.last;
    final sum = sorted.fold<double>(0, (s, v) => s + v);
    final avg = sum / n;

    // Median
    final median = n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;

    // Percentiles
    final p95Idx = (n * 0.95).floor().clamp(0, n - 1);
    final p99Idx = (n * 0.99).floor().clamp(0, n - 1);
    final p95 = sorted[p95Idx];
    final p99 = sorted[p99Idx];

    // Standard deviation
    final variance = sorted.fold<double>(0, (s, v) => s + math.pow(v - avg, 2)) / n;
    final stdDev = math.sqrt(variance);

    // Outliers (> 2 standard deviations from mean)
    final outlierThreshold = avg + 2 * stdDev;
    final outlierCount = sorted.where((v) => v > outlierThreshold).length;

    return LatencyStats(
      min: min,
      max: max,
      avg: avg,
      median: median,
      p95: p95,
      p99: p99,
      stdDev: stdDev,
      sampleCount: n,
      outlierCount: outlierCount,
    );
  }
}

/// Latency histogram data
class LatencyHistogram {
  static const List<double> defaultBucketBoundaries = [
    0, 5, 10, 20, 30, 50, 75, 100, 150, 200, 300, 500
  ];

  final List<LatencyBucket> buckets;
  final LatencyStats stats;
  final int maxBucketCount;

  LatencyHistogram({
    required this.buckets,
    required this.stats,
    required this.maxBucketCount,
  });

  factory LatencyHistogram.empty() {
    return LatencyHistogram(
      buckets: [],
      stats: LatencyStats.empty(),
      maxBucketCount: 0,
    );
  }

  factory LatencyHistogram.fromSamples(
    List<double> samples, {
    List<double>? boundaries,
  }) {
    if (samples.isEmpty) return LatencyHistogram.empty();

    final bounds = boundaries ?? defaultBucketBoundaries;
    final stats = LatencyStats.fromSamples(samples);

    // Create buckets
    final bucketCounts = List<int>.filled(bounds.length, 0);

    for (final sample in samples) {
      var bucketIdx = bounds.length - 1;
      for (var i = 0; i < bounds.length - 1; i++) {
        if (sample >= bounds[i] && sample < bounds[i + 1]) {
          bucketIdx = i;
          break;
        }
      }
      bucketCounts[bucketIdx]++;
    }

    final buckets = <LatencyBucket>[];
    for (var i = 0; i < bounds.length; i++) {
      if (bucketCounts[i] > 0) {
        buckets.add(LatencyBucket(
          minMs: bounds[i],
          maxMs: i < bounds.length - 1 ? bounds[i + 1] : double.infinity,
          count: bucketCounts[i],
        ));
      }
    }

    final maxBucketCount = bucketCounts.reduce(math.max);

    return LatencyHistogram(
      buckets: buckets,
      stats: stats,
      maxBucketCount: maxBucketCount,
    );
  }
}

/// Latency histogram panel widget
class LatencyHistogramPanel extends StatefulWidget {
  /// Raw latency samples in milliseconds
  final List<double> samples;

  /// Title for the panel
  final String title;

  /// Whether to show detailed stats
  final bool showStats;

  /// Whether to show percentile markers
  final bool showPercentiles;

  /// Compact mode (smaller height)
  final bool compact;

  const LatencyHistogramPanel({
    super.key,
    required this.samples,
    this.title = 'Latency Distribution',
    this.showStats = true,
    this.showPercentiles = true,
    this.compact = false,
  });

  @override
  State<LatencyHistogramPanel> createState() => _LatencyHistogramPanelState();
}

class _LatencyHistogramPanelState extends State<LatencyHistogramPanel> {
  late LatencyHistogram _histogram;
  int? _hoveredBucket;

  @override
  void initState() {
    super.initState();
    _updateHistogram();
  }

  @override
  void didUpdateWidget(LatencyHistogramPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.samples != widget.samples) {
      _updateHistogram();
    }
  }

  void _updateHistogram() {
    _histogram = LatencyHistogram.fromSamples(widget.samples);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return _buildCompactView();
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3a3a44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  if (widget.showStats) ...[
                    _buildStatsRow(),
                    const SizedBox(height: 12),
                  ],
                  Expanded(child: _buildHistogram()),
                  const SizedBox(height: 8),
                  _buildLegend(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactView() {
    return Container(
      height: 80,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3a3a44)),
      ),
      child: Row(
        children: [
          // Mini histogram
          Expanded(
            flex: 2,
            child: _buildMiniHistogram(),
          ),
          const SizedBox(width: 12),
          // Quick stats
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildQuickStat('Avg', _histogram.stats.avg),
                _buildQuickStat('P95', _histogram.stats.p95),
                _buildQuickStat('Max', _histogram.stats.max),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStat(String label, double value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 10,
          ),
        ),
        Text(
          '${value.toStringAsFixed(1)}ms',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF242430),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.bar_chart,
            color: Colors.white.withOpacity(0.7),
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            widget.title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            '${_histogram.stats.sampleCount} samples',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final stats = _histogram.stats;

    return Row(
      children: [
        Expanded(child: _buildStatCard('Min', stats.min, const Color(0xFF40ff90))),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard('Avg', stats.avg, const Color(0xFF4a9eff))),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard('Median', stats.median, const Color(0xFF40c8ff))),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard('P95', stats.p95, const Color(0xFFffff40))),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard('P99', stats.p99, const Color(0xFFff9040))),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard('Max', stats.max, const Color(0xFFff4040))),
      ],
    );
  }

  Widget _buildStatCard(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${value.toStringAsFixed(1)}ms',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistogram() {
    if (_histogram.buckets.isEmpty) {
      return Center(
        child: Text(
          'No data',
          style: TextStyle(color: Colors.white.withOpacity(0.3)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _HistogramPainter(
            histogram: _histogram,
            hoveredBucket: _hoveredBucket,
            showPercentiles: widget.showPercentiles,
          ),
          child: MouseRegion(
            onHover: (event) {
              final bucketIdx = _getBucketAtPosition(event.localPosition.dx, constraints.maxWidth);
              if (bucketIdx != _hoveredBucket) {
                setState(() => _hoveredBucket = bucketIdx);
              }
            },
            onExit: (_) {
              if (_hoveredBucket != null) {
                setState(() => _hoveredBucket = null);
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildMiniHistogram() {
    if (_histogram.buckets.isEmpty) {
      return const SizedBox();
    }

    return CustomPaint(
      size: const Size(double.infinity, 64),
      painter: _MiniHistogramPainter(histogram: _histogram),
    );
  }

  int? _getBucketAtPosition(double x, double width) {
    if (_histogram.buckets.isEmpty) return null;

    final bucketWidth = width / _histogram.buckets.length;
    final idx = (x / bucketWidth).floor();
    if (idx >= 0 && idx < _histogram.buckets.length) {
      return idx;
    }
    return null;
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLegendItem('Good (<20ms)', const Color(0xFF40ff90)),
        const SizedBox(width: 16),
        _buildLegendItem('Fair (20-50ms)', const Color(0xFFffff40)),
        const SizedBox(width: 16),
        _buildLegendItem('Slow (50-100ms)', const Color(0xFFff9040)),
        const SizedBox(width: 16),
        _buildLegendItem('Critical (>100ms)', const Color(0xFFff4040)),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

/// Custom painter for histogram bars
class _HistogramPainter extends CustomPainter {
  final LatencyHistogram histogram;
  final int? hoveredBucket;
  final bool showPercentiles;

  _HistogramPainter({
    required this.histogram,
    this.hoveredBucket,
    this.showPercentiles = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (histogram.buckets.isEmpty) return;

    final barWidth = size.width / histogram.buckets.length;
    final maxHeight = size.height - 30; // Reserve space for labels

    for (var i = 0; i < histogram.buckets.length; i++) {
      final bucket = histogram.buckets[i];
      final barHeight = (bucket.count / histogram.maxBucketCount) * maxHeight;
      final isHovered = i == hoveredBucket;

      // Bar color based on latency range
      Color barColor;
      if (bucket.maxMs <= 20) {
        barColor = const Color(0xFF40ff90);
      } else if (bucket.maxMs <= 50) {
        barColor = const Color(0xFFffff40);
      } else if (bucket.maxMs <= 100) {
        barColor = const Color(0xFFff9040);
      } else {
        barColor = const Color(0xFFff4040);
      }

      // Draw bar
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          i * barWidth + 2,
          maxHeight - barHeight,
          barWidth - 4,
          barHeight,
        ),
        const Radius.circular(2),
      );

      final paint = Paint()
        ..color = isHovered ? barColor : barColor.withOpacity(0.7)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(barRect, paint);

      // Draw border on hover
      if (isHovered) {
        final borderPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawRRect(barRect, borderPaint);

        // Draw tooltip
        _drawTooltip(canvas, size, i, bucket, barWidth, maxHeight - barHeight);
      }

      // Draw bucket label
      final labelPainter = TextPainter(
        text: TextSpan(
          text: bucket.label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 9,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      labelPainter.layout();
      labelPainter.paint(
        canvas,
        Offset(
          i * barWidth + (barWidth - labelPainter.width) / 2,
          maxHeight + 4,
        ),
      );
    }

    // Draw percentile markers
    if (showPercentiles) {
      _drawPercentileMarker(canvas, size, histogram.stats.p95, 'P95', const Color(0xFFffff40));
      _drawPercentileMarker(canvas, size, histogram.stats.p99, 'P99', const Color(0xFFff9040));
    }
  }

  void _drawTooltip(Canvas canvas, Size size, int idx, LatencyBucket bucket, double barWidth, double barTop) {
    final text = '${bucket.count} samples\n${bucket.label}ms';
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();

    final tooltipWidth = painter.width + 16;
    final tooltipHeight = painter.height + 8;
    var tooltipX = idx * barWidth + barWidth / 2 - tooltipWidth / 2;
    tooltipX = tooltipX.clamp(0.0, size.width - tooltipWidth);

    final tooltipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(tooltipX, barTop - tooltipHeight - 8, tooltipWidth, tooltipHeight),
      const Radius.circular(4),
    );

    canvas.drawRRect(
      tooltipRect,
      Paint()..color = const Color(0xFF242430),
    );
    canvas.drawRRect(
      tooltipRect,
      Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..style = PaintingStyle.stroke,
    );

    painter.paint(
      canvas,
      Offset(tooltipX + 8, barTop - tooltipHeight - 4),
    );
  }

  void _drawPercentileMarker(Canvas canvas, Size size, double value, String label, Color color) {
    // Find x position based on value
    double x = 0;
    for (var i = 0; i < histogram.buckets.length; i++) {
      final bucket = histogram.buckets[i];
      if (value >= bucket.minMs && (bucket.maxMs == double.infinity || value < bucket.maxMs)) {
        final bucketWidth = size.width / histogram.buckets.length;
        final progress = bucket.maxMs == double.infinity
            ? 0.5
            : (value - bucket.minMs) / (bucket.maxMs - bucket.minMs);
        x = i * bucketWidth + progress * bucketWidth;
        break;
      }
    }

    final maxHeight = size.height - 30;
    final paint = Paint()
      ..color = color.withOpacity(0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Draw dashed line
    const dashHeight = 4.0;
    const gapHeight = 3.0;
    var y = 0.0;
    while (y < maxHeight) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + dashHeight, maxHeight)),
        paint,
      );
      y += dashHeight + gapHeight;
    }

    // Draw label
    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    labelPainter.layout();
    labelPainter.paint(canvas, Offset(x - labelPainter.width / 2, maxHeight + 16));
  }

  @override
  bool shouldRepaint(_HistogramPainter oldDelegate) {
    return oldDelegate.histogram != histogram ||
        oldDelegate.hoveredBucket != hoveredBucket ||
        oldDelegate.showPercentiles != showPercentiles;
  }
}

/// Mini histogram painter for compact view
class _MiniHistogramPainter extends CustomPainter {
  final LatencyHistogram histogram;

  _MiniHistogramPainter({required this.histogram});

  @override
  void paint(Canvas canvas, Size size) {
    if (histogram.buckets.isEmpty) return;

    final barWidth = size.width / histogram.buckets.length;

    for (var i = 0; i < histogram.buckets.length; i++) {
      final bucket = histogram.buckets[i];
      final barHeight = (bucket.count / histogram.maxBucketCount) * size.height;

      Color barColor;
      if (bucket.maxMs <= 20) {
        barColor = const Color(0xFF40ff90);
      } else if (bucket.maxMs <= 50) {
        barColor = const Color(0xFFffff40);
      } else if (bucket.maxMs <= 100) {
        barColor = const Color(0xFFff9040);
      } else {
        barColor = const Color(0xFFff4040);
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * barWidth + 1,
            size.height - barHeight,
            barWidth - 2,
            barHeight,
          ),
          const Radius.circular(1),
        ),
        Paint()..color = barColor.withOpacity(0.7),
      );
    }
  }

  @override
  bool shouldRepaint(_MiniHistogramPainter oldDelegate) {
    return oldDelegate.histogram != histogram;
  }
}

/// Compact latency histogram badge for status bars
class LatencyHistogramBadge extends StatelessWidget {
  final List<double> samples;

  const LatencyHistogramBadge({
    super.key,
    required this.samples,
  });

  @override
  Widget build(BuildContext context) {
    final stats = LatencyStats.fromSamples(samples);

    return Tooltip(
      message: 'Avg: ${stats.avg.toStringAsFixed(1)}ms\nP95: ${stats.p95.toStringAsFixed(1)}ms\nMax: ${stats.max.toStringAsFixed(1)}ms',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: _getHealthColor(stats).withOpacity(0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _getHealthColor(stats).withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart, size: 12, color: _getHealthColor(stats)),
            const SizedBox(width: 4),
            Text(
              '${stats.avg.toStringAsFixed(0)}ms',
              style: TextStyle(
                color: _getHealthColor(stats),
                fontSize: 10,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getHealthColor(LatencyStats stats) {
    if (stats.p95 > 100) return const Color(0xFFff4040);
    if (stats.p95 > 50) return const Color(0xFFff9040);
    if (stats.avg > 20) return const Color(0xFFffff40);
    return const Color(0xFF40ff90);
  }
}
