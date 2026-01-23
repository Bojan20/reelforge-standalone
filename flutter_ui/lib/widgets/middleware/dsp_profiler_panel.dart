// DSP Profiler Panel (P3.12)
//
// Real-time visualization of DSP performance:
// - CPU load meter with history graph
// - Per-stage breakdown (Input, Mixing, Effects, Metering, Output)
// - Peak/average statistics
// - Overload warnings

import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/advanced_middleware_models.dart';
import '../../theme/fluxforge_theme.dart';

class DspProfilerPanel extends StatefulWidget {
  const DspProfilerPanel({super.key});

  @override
  State<DspProfilerPanel> createState() => _DspProfilerPanelState();
}

class _DspProfilerPanelState extends State<DspProfilerPanel> {
  final DspProfiler _profiler = DspProfiler(maxSamples: 500);
  Timer? _updateTimer;
  bool _isRecording = true;
  bool _showStageBreakdown = true;

  @override
  void initState() {
    super.initState();
    _startUpdateTimer();
  }

  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted && _isRecording) {
        // Simulate DSP data (in production, this comes from FFI)
        _profiler.simulateSample(
          baseLoad: 12.0 + (_profiler.getStats().totalSamples % 100) * 0.05,
          variance: 8.0,
        );
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _profiler.getStats();
    final loadHistory = _profiler.getLoadHistory(count: 100);

    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          // Header
          _buildHeader(stats),

          // Main load meter
          _buildLoadMeter(stats),

          // Load graph
          Expanded(
            flex: 2,
            child: _buildLoadGraph(loadHistory),
          ),

          // Stage breakdown
          if (_showStageBreakdown)
            Expanded(
              flex: 1,
              child: _buildStageBreakdown(stats),
            ),

          // Statistics
          _buildStatistics(stats),

          // Controls
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildHeader(DspProfilerStats stats) {
    Color statusColor;
    String statusText;
    if (stats.avgLoadPercent > 90) {
      statusColor = FluxForgeTheme.accentRed;
      statusText = 'OVERLOAD';
    } else if (stats.avgLoadPercent > 70) {
      statusColor = FluxForgeTheme.accentOrange;
      statusText = 'WARNING';
    } else {
      statusColor = FluxForgeTheme.accentGreen;
      statusText = 'NORMAL';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.speed,
            color: FluxForgeTheme.accentCyan,
            size: 16,
          ),
          const SizedBox(width: 8),
          const Text(
            'DSP PROFILER',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          // Status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: statusColor.withValues(alpha: 0.5)),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Recording indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _isRecording
                  ? FluxForgeTheme.accentRed.withValues(alpha: 0.2)
                  : FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _isRecording
                        ? FluxForgeTheme.accentRed
                        : FluxForgeTheme.textSecondary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  _isRecording ? 'REC' : 'OFF',
                  style: TextStyle(
                    color: _isRecording
                        ? FluxForgeTheme.accentRed
                        : FluxForgeTheme.textSecondary,
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadMeter(DspProfilerStats stats) {
    final load = _profiler.currentLoad;
    Color meterColor;
    if (load > 90) {
      meterColor = FluxForgeTheme.accentRed;
    } else if (load > 70) {
      meterColor = FluxForgeTheme.accentOrange;
    } else if (load > 50) {
      meterColor = FluxForgeTheme.accentYellow;
    } else {
      meterColor = FluxForgeTheme.accentGreen;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Big load display
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                load.toStringAsFixed(1),
                style: TextStyle(
                  color: meterColor,
                  fontSize: 48,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '%',
                  style: TextStyle(
                    color: meterColor.withValues(alpha: 0.7),
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Horizontal bar meter
          Container(
            height: 20,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FluxForgeTheme.borderSubtle),
            ),
            child: Stack(
              children: [
                // Background gradient zones
                Row(
                  children: [
                    Expanded(
                      flex: 50,
                      child: Container(
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentGreen.withValues(alpha: 0.1),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(3),
                            bottomLeft: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 20,
                      child: Container(
                        color: FluxForgeTheme.accentYellow.withValues(alpha: 0.1),
                      ),
                    ),
                    Expanded(
                      flex: 20,
                      child: Container(
                        color: FluxForgeTheme.accentOrange.withValues(alpha: 0.1),
                      ),
                    ),
                    Expanded(
                      flex: 10,
                      child: Container(
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentRed.withValues(alpha: 0.1),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(3),
                            bottomRight: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Load bar
                FractionallySizedBox(
                  widthFactor: (load / 100).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          meterColor.withValues(alpha: 0.8),
                          meterColor,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                // Peak indicator
                Positioned(
                  left: (stats.peakLoadPercent / 100 * (context.size?.width ?? 300) - 2).clamp(0, double.infinity),
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2,
                    color: FluxForgeTheme.accentRed,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '0%',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 8,
                ),
              ),
              Text(
                'Peak: ${stats.peakLoadPercent.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: FluxForgeTheme.accentRed.withValues(alpha: 0.8),
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '100%',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadGraph(List<double> loadHistory) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'LOAD HISTORY',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                '${loadHistory.length} samples',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: CustomPaint(
              painter: _LoadGraphPainter(
                loadHistory: loadHistory,
                warningThreshold: 70,
                criticalThreshold: 90,
              ),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageBreakdown(DspProfilerStats stats) {
    final breakdown = _profiler.getCurrentStageBreakdown();
    final total = breakdown[DspStage.total] ?? 1.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STAGE BREAKDOWN',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: DspStage.values
                  .where((s) => s != DspStage.total)
                  .map((stage) {
                final time = breakdown[stage] ?? 0;
                final percent = total > 0 ? (time / total * 100) : 0.0;
                final color = _getStageColor(stage);

                return Expanded(
                  child: Column(
                    children: [
                      Text(
                        stage.shortName,
                        style: TextStyle(
                          color: color,
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Container(
                          width: 20,
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.bgDeep,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.bottomCenter,
                            heightFactor: (percent / 100).clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${percent.toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStageColor(DspStage stage) {
    switch (stage) {
      case DspStage.input:
        return FluxForgeTheme.accentBlue;
      case DspStage.mixing:
        return FluxForgeTheme.accentCyan;
      case DspStage.effects:
        return FluxForgeTheme.accentPurple;
      case DspStage.metering:
        return FluxForgeTheme.accentYellow;
      case DspStage.output:
        return FluxForgeTheme.accentGreen;
      case DspStage.total:
        return FluxForgeTheme.textPrimary;
    }
  }

  Widget _buildStatistics(DspProfilerStats stats) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          _buildStatItem('AVG', '${stats.avgLoadPercent.toStringAsFixed(1)}%', FluxForgeTheme.accentBlue),
          _buildStatItem('PEAK', '${stats.peakLoadPercent.toStringAsFixed(1)}%', FluxForgeTheme.accentOrange),
          _buildStatItem('MIN', '${stats.minLoadPercent.toStringAsFixed(1)}%', FluxForgeTheme.accentGreen),
          _buildStatItem('OVERLOADS', '${stats.overloadCount}',
            stats.overloadCount > 0 ? FluxForgeTheme.accentRed : FluxForgeTheme.accentGreen),
          _buildStatItem('AVG μs', '${stats.avgBlockTimeUs.toStringAsFixed(0)}', FluxForgeTheme.accentCyan),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 7,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          _buildControlButton(
            icon: _isRecording ? Icons.pause : Icons.play_arrow,
            label: _isRecording ? 'Pause' : 'Start',
            color: _isRecording ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentGreen,
            onTap: () => setState(() => _isRecording = !_isRecording),
          ),
          const SizedBox(width: 8),
          _buildControlButton(
            icon: Icons.delete_outline,
            label: 'Clear',
            onTap: () => setState(() => _profiler.clear()),
          ),
          const SizedBox(width: 8),
          _buildControlButton(
            icon: Icons.bar_chart,
            label: 'Stages',
            color: _showStageBreakdown ? FluxForgeTheme.accentBlue : null,
            onTap: () => setState(() => _showStageBreakdown = !_showStageBreakdown),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    Color? color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (color ?? FluxForgeTheme.textSecondary).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: (color ?? FluxForgeTheme.textSecondary).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 12,
              color: color ?? FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color ?? FluxForgeTheme.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for load history graph
class _LoadGraphPainter extends CustomPainter {
  final List<double> loadHistory;
  final double warningThreshold;
  final double criticalThreshold;

  _LoadGraphPainter({
    required this.loadHistory,
    this.warningThreshold = 70,
    this.criticalThreshold = 90,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (loadHistory.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Draw threshold lines
    final thresholdPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Warning threshold
    thresholdPaint.color = FluxForgeTheme.accentOrange.withValues(alpha: 0.3);
    final warningY = size.height * (1 - warningThreshold / 100);
    canvas.drawLine(
      Offset(0, warningY),
      Offset(size.width, warningY),
      thresholdPaint,
    );

    // Critical threshold
    thresholdPaint.color = FluxForgeTheme.accentRed.withValues(alpha: 0.3);
    final criticalY = size.height * (1 - criticalThreshold / 100);
    canvas.drawLine(
      Offset(0, criticalY),
      Offset(size.width, criticalY),
      thresholdPaint,
    );

    // Draw load line
    final path = Path();
    final xStep = size.width / (loadHistory.length - 1).clamp(1, double.infinity);

    for (var i = 0; i < loadHistory.length; i++) {
      final x = i * xStep;
      final y = size.height * (1 - loadHistory[i] / 100);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Gradient based on current value
    final currentLoad = loadHistory.last;
    if (currentLoad > criticalThreshold) {
      paint.color = FluxForgeTheme.accentRed;
    } else if (currentLoad > warningThreshold) {
      paint.color = FluxForgeTheme.accentOrange;
    } else {
      paint.color = FluxForgeTheme.accentGreen;
    }

    canvas.drawPath(path, paint);

    // Fill under the line
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = paint.color.withValues(alpha: 0.1);
    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _LoadGraphPainter oldDelegate) {
    return loadHistory != oldDelegate.loadHistory;
  }
}
