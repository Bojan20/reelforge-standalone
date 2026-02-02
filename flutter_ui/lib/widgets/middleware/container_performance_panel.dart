/// Container Performance Panel Widget
///
/// Displays real-time container evaluation metrics:
/// - Blend/Random/Sequence benchmark times
/// - Performance graph over time
/// - Per-container breakdown
/// - Uses ContainerMeteringService for data
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';
import '../../services/container_metering_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Container performance monitoring panel
class ContainerPerformancePanel extends StatefulWidget {
  /// Refresh interval
  final Duration refreshInterval;

  /// Show per-container details
  final bool showDetails;

  /// Show performance graph
  final bool showGraph;

  /// Compact mode (summary only)
  final bool compactMode;

  /// Maximum history points for graph
  final int maxHistoryPoints;

  const ContainerPerformancePanel({
    super.key,
    this.refreshInterval = const Duration(milliseconds: 250),
    this.showDetails = true,
    this.showGraph = true,
    this.compactMode = false,
    this.maxHistoryPoints = 100,
  });

  @override
  State<ContainerPerformancePanel> createState() => _ContainerPerformancePanelState();
}

class _ContainerPerformancePanelState extends State<ContainerPerformancePanel> {
  final ContainerMeteringService _service = ContainerMeteringService.instance;
  StreamSubscription<ContainerEvaluationMetrics>? _subscription;

  final List<_PerformanceSnapshot> _history = [];
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _subscription = _service.metricsStream.listen(_onMetrics);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _onMetrics(ContainerEvaluationMetrics metrics) {
    if (_isPaused || !mounted) return;

    setState(() {
      _history.add(_PerformanceSnapshot(
        timestamp: DateTime.now(),
        type: metrics.type,
        evaluationTimeMs: metrics.evaluationTimeMs,
      ));

      // Trim history
      while (_history.length > widget.maxHistoryPoints) {
        _history.removeAt(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compactMode) {
      return _buildCompactView();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          // Summary cards
          _buildSummaryCards(),
          const SizedBox(height: 12),
          if (widget.showGraph) ...[
            // Performance graph
            Expanded(
              flex: 2,
              child: _buildPerformanceGraph(),
            ),
            const SizedBox(height: 12),
          ],
          if (widget.showDetails) ...[
            // Container details
            Expanded(
              child: _buildContainerDetails(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final summary = _service.getSummary();
    final avgLatency = summary['avg_latency_ms'] as double? ?? 0.0;

    return Row(
      children: [
        const Icon(Icons.speed, size: 16, color: FluxForgeTheme.accentBlue),
        const SizedBox(width: 8),
        const Text(
          'CONTAINER PERFORMANCE',
          style: TextStyle(
            color: FluxForgeTheme.accentBlue,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const Spacer(),
        // Average latency badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _getLatencyColor(avgLatency).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Avg: ${avgLatency.toStringAsFixed(2)}ms',
            style: TextStyle(
              color: _getLatencyColor(avgLatency),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 14),
          onPressed: () => setState(() => _isPaused = !_isPaused),
          splashRadius: 12,
          color: Colors.white38,
          tooltip: _isPaused ? 'Resume' : 'Pause',
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 14),
          onPressed: () {
            _service.clearAll();
            setState(() => _history.clear());
          },
          splashRadius: 12,
          color: Colors.white38,
          tooltip: 'Clear',
        ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    final summary = _service.getSummary();
    final byType = summary['by_type'] as Map<String, dynamic>? ?? {};

    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            label: 'Blend',
            count: byType['blend'] as int? ?? 0,
            color: const Color(0xFF9370DB),
            icon: Icons.tune,
            latency: _getAverageLatencyForType(ContainerType.blend),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            label: 'Random',
            count: byType['random'] as int? ?? 0,
            color: const Color(0xFFFFAA00),
            icon: Icons.shuffle,
            latency: _getAverageLatencyForType(ContainerType.random),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            label: 'Sequence',
            count: byType['sequence'] as int? ?? 0,
            color: const Color(0xFF40C8FF),
            icon: Icons.playlist_play,
            latency: _getAverageLatencyForType(ContainerType.sequence),
          ),
        ),
      ],
    );
  }

  double _getAverageLatencyForType(ContainerType type) {
    final snapshots = _history.where((s) => s.type == type).toList();
    if (snapshots.isEmpty) return 0.0;
    return snapshots.fold<double>(0, (sum, s) => sum + s.evaluationTimeMs) / snapshots.length;
  }

  Widget _buildPerformanceGraph() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'LATENCY HISTORY',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              _buildLegendChip('Blend', const Color(0xFF9370DB)),
              const SizedBox(width: 8),
              _buildLegendChip('Random', const Color(0xFFFFAA00)),
              const SizedBox(width: 8),
              _buildLegendChip('Sequence', const Color(0xFF40C8FF)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: CustomPaint(
              painter: _PerformanceGraphPainter(
                history: _history,
                maxPoints: widget.maxHistoryPoints,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendChip(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildContainerDetails() {
    final containers = _service.trackedContainers;

    if (containers.isEmpty) {
      return Center(
        child: Text(
          'No containers tracked',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 11,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CONTAINER DETAILS',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: containers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final containerId = containers[index];
                final stats = _service.getStats(containerId);
                if (stats == null) return const SizedBox.shrink();
                return _ContainerDetailRow(stats: stats);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactView() {
    final summary = _service.getSummary();
    final avgLatency = summary['avg_latency_ms'] as double? ?? 0.0;
    final totalEvaluations = summary['total_evaluations'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(Icons.speed, size: 14, color: _getLatencyColor(avgLatency)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Avg: ${avgLatency.toStringAsFixed(2)}ms',
                  style: TextStyle(
                    color: _getLatencyColor(avgLatency),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '$totalEvaluations evals',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          // Mini sparkline
          SizedBox(
            width: 60,
            height: 24,
            child: CustomPaint(
              painter: _MiniSparklinePainter(
                values: _history.map((s) => s.evaluationTimeMs).toList(),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  Color _getLatencyColor(double ms) {
    if (ms > 1.0) return FluxForgeTheme.accentRed;
    if (ms > 0.5) return FluxForgeTheme.accentOrange;
    return FluxForgeTheme.accentGreen;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════

class _PerformanceSnapshot {
  final DateTime timestamp;
  final ContainerType type;
  final double evaluationTimeMs;

  const _PerformanceSnapshot({
    required this.timestamp,
    required this.type,
    required this.evaluationTimeMs,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _SummaryCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  final double latency;

  const _SummaryCard({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
    required this.latency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: count > 0 ? color.withValues(alpha: 0.3) : Colors.transparent,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$count',
                style: TextStyle(
                  color: count > 0 ? color : Colors.white38,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text(
                'Avg:',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 8,
                ),
              ),
              const Spacer(),
              Text(
                count > 0 ? '${latency.toStringAsFixed(2)}ms' : '-',
                style: TextStyle(
                  color: count > 0 ? Colors.white70 : Colors.white38,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContainerDetailRow extends StatelessWidget {
  final ContainerMeteringStats stats;

  const _ContainerDetailRow({required this.stats});

  Color get _typeColor {
    switch (stats.type) {
      case ContainerType.blend:
        return const Color(0xFF9370DB);
      case ContainerType.random:
        return const Color(0xFFFFAA00);
      case ContainerType.sequence:
        return const Color(0xFF40C8FF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          // Type indicator
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: _typeColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          // ID
          Text(
            '#${stats.containerId}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          // Type label
          Text(
            stats.type.name.toUpperCase(),
            style: TextStyle(
              color: _typeColor,
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Stats
          _StatChip('Avg', stats.avgEvaluationMs),
          const SizedBox(width: 8),
          _StatChip('P95', stats.p95Latency),
          const SizedBox(width: 8),
          _StatChip('Max', stats.maxEvaluationMs),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final double value;

  const _StatChip(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 7,
          ),
        ),
        Text(
          '${value.toStringAsFixed(2)}ms',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 9,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════

class _PerformanceGraphPainter extends CustomPainter {
  final List<_PerformanceSnapshot> history;
  final int maxPoints;

  _PerformanceGraphPainter({
    required this.history,
    required this.maxPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) {
      // Draw "No data" text
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'No data',
          style: TextStyle(color: Colors.white24, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );
      return;
    }

    // Draw grid
    _drawGrid(canvas, size);

    // Draw data for each type
    _drawTypeData(canvas, size, ContainerType.blend, const Color(0xFF9370DB));
    _drawTypeData(canvas, size, ContainerType.random, const Color(0xFFFFAA00));
    _drawTypeData(canvas, size, ContainerType.sequence, const Color(0xFF40C8FF));
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;

    // Horizontal lines (at 0.5ms, 1ms)
    for (final ms in [0.25, 0.5, 0.75, 1.0]) {
      final y = size.height * (1 - ms / 1.5);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Target line at 0.5ms (good performance)
    final targetY = size.height * (1 - 0.5 / 1.5);
    canvas.drawLine(
      Offset(0, targetY),
      Offset(size.width, targetY),
      Paint()
        ..color = FluxForgeTheme.accentGreen.withValues(alpha: 0.3)
        ..strokeWidth = 1,
    );
  }

  void _drawTypeData(Canvas canvas, Size size, ContainerType type, Color color) {
    final typeHistory = history.where((s) => s.type == type).toList();
    if (typeHistory.isEmpty) return;

    final path = Path();
    var started = false;

    for (var i = 0; i < typeHistory.length; i++) {
      final x = i / (typeHistory.length - 1).clamp(1, double.infinity) * size.width;
      final y = size.height * (1 - typeHistory[i].evaluationTimeMs / 1.5).clamp(0.0, 1.0);

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Draw dots at each point
    for (var i = 0; i < typeHistory.length; i++) {
      final x = i / (typeHistory.length - 1).clamp(1, double.infinity) * size.width;
      final y = size.height * (1 - typeHistory[i].evaluationTimeMs / 1.5).clamp(0.0, 1.0);

      canvas.drawCircle(
        Offset(x, y),
        2,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_PerformanceGraphPainter oldDelegate) {
    return history.length != oldDelegate.history.length;
  }
}

class _MiniSparklinePainter extends CustomPainter {
  final List<double> values;

  _MiniSparklinePainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final path = Path();
    final maxValue = values.reduce((a, b) => a > b ? a : b).clamp(0.1, double.infinity);

    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1).clamp(1, double.infinity) * size.width;
      final y = size.height * (1 - values[i] / maxValue).clamp(0.0, 1.0);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = FluxForgeTheme.accentBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_MiniSparklinePainter oldDelegate) {
    return values.length != oldDelegate.values.length;
  }
}
