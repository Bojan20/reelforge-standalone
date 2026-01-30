/// FPS Counter Widget (P4.22)
///
/// Displays real-time frame rate and performance metrics.
/// Toggle with Ctrl+Shift+F or from debug menu.
///
/// Features:
/// - Real-time FPS display (rolling average)
/// - Frame time histogram
/// - Min/Max/Avg statistics
/// - Jank detection (frames > 16.67ms)
/// - Memory usage display
///
/// Created: 2026-01-30

import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../theme/fluxforge_theme.dart';

/// Frame timing sample
class FrameSample {
  final int frameNumber;
  final Duration frameTime;
  final DateTime timestamp;

  const FrameSample({
    required this.frameNumber,
    required this.frameTime,
    required this.timestamp,
  });

  double get frameTimeMs => frameTime.inMicroseconds / 1000.0;
  bool get isJank => frameTimeMs > 16.67; // > 60fps target
  bool get isSevereJank => frameTimeMs > 33.33; // > 30fps
}

/// FPS statistics calculator
class FpsStats {
  final Queue<FrameSample> _samples = Queue();
  static const int _maxSamples = 120; // 2 seconds at 60fps
  int _frameCount = 0;
  int _jankCount = 0;

  void addSample(Duration frameTime) {
    final sample = FrameSample(
      frameNumber: _frameCount++,
      frameTime: frameTime,
      timestamp: DateTime.now(),
    );

    _samples.addLast(sample);
    if (sample.isJank) _jankCount++;

    while (_samples.length > _maxSamples) {
      final removed = _samples.removeFirst();
      if (removed.isJank) _jankCount--;
    }
  }

  double get currentFps {
    if (_samples.isEmpty) return 0;
    final totalMs = _samples.fold<double>(0, (sum, s) => sum + s.frameTimeMs);
    if (totalMs == 0) return 0;
    return (_samples.length / totalMs) * 1000;
  }

  double get avgFrameTimeMs {
    if (_samples.isEmpty) return 0;
    return _samples.fold<double>(0, (sum, s) => sum + s.frameTimeMs) /
        _samples.length;
  }

  double get minFrameTimeMs {
    if (_samples.isEmpty) return 0;
    return _samples.map((s) => s.frameTimeMs).reduce((a, b) => a < b ? a : b);
  }

  double get maxFrameTimeMs {
    if (_samples.isEmpty) return 0;
    return _samples.map((s) => s.frameTimeMs).reduce((a, b) => a > b ? a : b);
  }

  double get jankPercent {
    if (_samples.isEmpty) return 0;
    return (_jankCount / _samples.length) * 100;
  }

  List<double> get histogram {
    return _samples.map((s) => s.frameTimeMs).toList();
  }

  void reset() {
    _samples.clear();
    _jankCount = 0;
  }
}

/// Global FPS monitor singleton
class FpsMonitor {
  static final FpsMonitor _instance = FpsMonitor._();
  static FpsMonitor get instance => _instance;

  FpsMonitor._();

  final FpsStats stats = FpsStats();
  Ticker? _ticker;
  Duration _lastFrameTime = Duration.zero;
  bool _isRunning = false;
  final _controller = StreamController<FpsStats>.broadcast();

  Stream<FpsStats> get stream => _controller.stream;
  bool get isRunning => _isRunning;

  void start(TickerProvider vsync) {
    if (_isRunning) return;

    _ticker = vsync.createTicker(_onTick);
    _ticker!.start();
    _isRunning = true;
    _lastFrameTime = Duration.zero;
  }

  void _onTick(Duration elapsed) {
    if (_lastFrameTime != Duration.zero) {
      final frameTime = elapsed - _lastFrameTime;
      stats.addSample(frameTime);
      _controller.add(stats);
    }
    _lastFrameTime = elapsed;
  }

  void stop() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _isRunning = false;
    _lastFrameTime = Duration.zero;
  }

  void reset() {
    stats.reset();
    _lastFrameTime = Duration.zero;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}

/// FPS Counter Overlay Widget
class FpsCounter extends StatefulWidget {
  final bool showHistogram;
  final bool showStats;
  final bool compact;
  final Color? backgroundColor;

  const FpsCounter({
    super.key,
    this.showHistogram = true,
    this.showStats = true,
    this.compact = false,
    this.backgroundColor,
  });

  @override
  State<FpsCounter> createState() => _FpsCounterState();
}

class _FpsCounterState extends State<FpsCounter>
    with SingleTickerProviderStateMixin {
  late StreamSubscription<FpsStats> _subscription;
  FpsStats? _currentStats;

  @override
  void initState() {
    super.initState();
    FpsMonitor.instance.start(this);
    _subscription = FpsMonitor.instance.stream.listen((stats) {
      if (mounted) {
        setState(() => _currentStats = stats);
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    FpsMonitor.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _currentStats ?? FpsMonitor.instance.stats;
    final fps = stats.currentFps;
    final bgColor = widget.backgroundColor ?? FluxForgeTheme.bgDeep.withAlpha(220);

    if (widget.compact) {
      return _buildCompactCounter(fps, bgColor);
    }

    return Container(
      width: 200,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _getFpsColor(fps).withAlpha(100),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(fps),
          if (widget.showHistogram) ...[
            const SizedBox(height: 8),
            _buildHistogram(stats),
          ],
          if (widget.showStats) ...[
            const SizedBox(height: 8),
            _buildStats(stats),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactCounter(double fps, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.speed, size: 14, color: _getFpsColor(fps)),
          const SizedBox(width: 4),
          Text(
            '${fps.toStringAsFixed(1)} FPS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _getFpsColor(fps),
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(double fps) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.speed, size: 16, color: _getFpsColor(fps)),
            const SizedBox(width: 6),
            Text(
              'FPS',
              style: TextStyle(
                fontSize: 11,
                color: FluxForgeTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Text(
          fps.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: _getFpsColor(fps),
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildHistogram(FpsStats stats) {
    final histogram = stats.histogram;
    if (histogram.isEmpty) {
      return const SizedBox(height: 40);
    }

    return SizedBox(
      height: 40,
      child: CustomPaint(
        size: const Size(double.infinity, 40),
        painter: FrameHistogramPainter(
          values: histogram,
          targetMs: 16.67, // 60fps target
        ),
      ),
    );
  }

  Widget _buildStats(FpsStats stats) {
    return Column(
      children: [
        _buildStatRow('Avg', '${stats.avgFrameTimeMs.toStringAsFixed(2)} ms'),
        _buildStatRow('Min', '${stats.minFrameTimeMs.toStringAsFixed(2)} ms'),
        _buildStatRow('Max', '${stats.maxFrameTimeMs.toStringAsFixed(2)} ms'),
        _buildStatRow(
          'Jank',
          '${stats.jankPercent.toStringAsFixed(1)}%',
          valueColor: stats.jankPercent > 5
              ? FluxForgeTheme.accentOrange
              : FluxForgeTheme.accentGreen,
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              color: valueColor ?? FluxForgeTheme.textPrimary,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Color _getFpsColor(double fps) {
    if (fps >= 55) return FluxForgeTheme.accentGreen;
    if (fps >= 30) return FluxForgeTheme.accentOrange;
    return const Color(0xFFFF4060); // Red
  }
}

/// Histogram painter for frame times (public for reuse)
class FrameHistogramPainter extends CustomPainter {
  final List<double> values;
  final double targetMs;

  FrameHistogramPainter({
    required this.values,
    required this.targetMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final barWidth = size.width / values.length;
    final maxValue = values.reduce((a, b) => a > b ? a : b).clamp(targetMs, 50.0);

    // Draw target line (60fps = 16.67ms)
    final targetY = size.height - (targetMs / maxValue) * size.height;
    final targetPaint = Paint()
      ..color = FluxForgeTheme.accentGreen.withAlpha(100)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, targetY),
      Offset(size.width, targetY),
      targetPaint,
    );

    // Draw bars
    for (int i = 0; i < values.length; i++) {
      final value = values[i];
      final barHeight = (value / maxValue) * size.height;
      final x = i * barWidth;
      final y = size.height - barHeight;

      final color = value <= targetMs
          ? FluxForgeTheme.accentGreen
          : value <= 33.33
              ? FluxForgeTheme.accentOrange
              : const Color(0xFFFF4060);

      final paint = Paint()..color = color.withAlpha(180);
      canvas.drawRect(
        Rect.fromLTWH(x, y, barWidth - 1, barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(FrameHistogramPainter oldDelegate) {
    return values != oldDelegate.values;
  }
}

/// FPS Badge for status bars (minimal footprint)
class FpsBadge extends StatefulWidget {
  const FpsBadge({super.key});

  @override
  State<FpsBadge> createState() => _FpsBadgeState();
}

class _FpsBadgeState extends State<FpsBadge>
    with SingleTickerProviderStateMixin {
  late StreamSubscription<FpsStats> _subscription;
  double _currentFps = 0;

  @override
  void initState() {
    super.initState();
    FpsMonitor.instance.start(this);
    _subscription = FpsMonitor.instance.stream.listen((stats) {
      if (mounted) {
        setState(() => _currentFps = stats.currentFps);
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _currentFps >= 55
        ? FluxForgeTheme.accentGreen
        : _currentFps >= 30
            ? FluxForgeTheme.accentOrange
            : const Color(0xFFFF4060);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withAlpha(80), width: 1),
      ),
      child: Text(
        '${_currentFps.toStringAsFixed(0)} fps',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
