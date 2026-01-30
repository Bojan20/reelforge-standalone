/// Container Real-Time Metrics Panel
///
/// Displays live performance metrics for all active containers:
/// - Evaluation latency (avg, min, max, p50, p95, p99)
/// - Evaluation count
/// - Type-specific metrics (RTPC distribution, selection distribution, timing accuracy)
/// - Visual graphs and sparklines

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/container_metering_service.dart';
import '../../theme/fluxforge_theme.dart';
import 'dart:math' as math;

class ContainerMetricsPanel extends StatefulWidget {
  final int? selectedContainerId;

  const ContainerMetricsPanel({
    super.key,
    this.selectedContainerId,
  });

  @override
  State<ContainerMetricsPanel> createState() => _ContainerMetricsPanelState();
}

class _ContainerMetricsPanelState extends State<ContainerMetricsPanel> {
  bool _autoRefresh = true;
  ContainerType? _filterType;

  @override
  Widget build(BuildContext context) {
    final service = ContainerMeteringService.instance;
    final theme = Theme.of(context);

    return ChangeNotifierProvider.value(
      value: service,
      child: Consumer<ContainerMeteringService>(
        builder: (context, svc, _) {
          final containers = svc.trackedContainers;
          final summary = svc.getSummary();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, summary),
              const SizedBox(height: 8),
              _buildControls(context),
              const SizedBox(height: 8),
              Expanded(
                child: containers.isEmpty
                  ? _buildEmptyState(context)
                  : _buildMetricsList(context, containers),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Map<String, dynamic> summary) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Container Performance Metrics',
            style: theme.textTheme.titleMedium?.copyWith(
              color: FluxForgeTheme.accentBlue,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildSummaryChip('Containers', summary['total_containers'].toString(), Icons.view_module),
              const SizedBox(width: 12),
              _buildSummaryChip('Evaluations', summary['total_evaluations'].toString(), Icons.timeline),
              const SizedBox(width: 12),
              _buildSummaryChip(
                'Avg Latency',
                '${(summary['avg_latency_ms'] as double).toStringAsFixed(2)} ms',
                Icons.speed,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: FluxForgeTheme.accentCyan),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: FluxForgeTheme.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    return Row(
      children: [
        // Type filter
        DropdownButton<ContainerType?>(
          value: _filterType,
          hint: const Text('All Types'),
          items: [
            const DropdownMenuItem(value: null, child: Text('All Types')),
            const DropdownMenuItem(value: ContainerType.blend, child: Text('Blend')),
            const DropdownMenuItem(value: ContainerType.random, child: Text('Random')),
            const DropdownMenuItem(value: ContainerType.sequence, child: Text('Sequence')),
          ],
          onChanged: (val) => setState(() => _filterType = val),
        ),
        const SizedBox(width: 12),
        // Auto-refresh toggle
        Row(
          children: [
            Switch(
              value: _autoRefresh,
              onChanged: (val) => setState(() => _autoRefresh = val),
            ),
            const Text('Auto-refresh'),
          ],
        ),
        const Spacer(),
        // Clear button
        TextButton.icon(
          icon: const Icon(Icons.clear_all),
          label: const Text('Clear All'),
          onPressed: () {
            ContainerMeteringService.instance.clearAll();
          },
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.timer_off,
            size: 64,
            color: FluxForgeTheme.textSecondary.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No Container Metrics',
            style: TextStyle(
              fontSize: 16,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Trigger container evaluations to see metrics',
            style: TextStyle(
              fontSize: 12,
              color: FluxForgeTheme.textSecondary.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsList(BuildContext context, List<int> containers) {
    var filteredContainers = containers;

    if (_filterType != null) {
      filteredContainers = containers.where((id) {
        final stats = ContainerMeteringService.instance.getStats(id);
        return stats?.type == _filterType;
      }).toList();
    }

    return ListView.builder(
      itemCount: filteredContainers.length,
      itemBuilder: (context, index) {
        final containerId = filteredContainers[index];
        final stats = ContainerMeteringService.instance.getStats(containerId);

        if (stats == null) return const SizedBox();

        return _buildContainerCard(context, stats);
      },
    );
  }

  Widget _buildContainerCard(BuildContext context, ContainerMeteringStats stats) {
    final theme = Theme.of(context);
    final isSelected = widget.selectedContainerId == stats.containerId;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected ? FluxForgeTheme.accentBlue.withOpacity(0.1) : FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected ? FluxForgeTheme.accentBlue : FluxForgeTheme.borderSubtle,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              _buildTypeIcon(stats.type),
              const SizedBox(width: 8),
              Text(
                'Container ${stats.containerId}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: FluxForgeTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              _buildTypeBadge(stats.type),
              const Spacer(),
              Text(
                '${stats.evaluationCount} evals',
                style: TextStyle(
                  fontSize: 12,
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () {
                  ContainerMeteringService.instance.clearStats(stats.containerId);
                },
                tooltip: 'Clear Stats',
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Timing metrics
          _buildTimingMetrics(stats),
          const SizedBox(height: 12),
          // Sparkline
          _buildSparkline(stats),
          const SizedBox(height: 12),
          // Type-specific metrics
          _buildTypeSpecificMetrics(stats),
        ],
      ),
    );
  }

  Widget _buildTypeIcon(ContainerType type) {
    IconData icon;
    Color color;

    switch (type) {
      case ContainerType.blend:
        icon = Icons.blur_on;
        color = FluxForgeTheme.accentPurple;
        break;
      case ContainerType.random:
        icon = Icons.shuffle;
        color = FluxForgeTheme.accentOrange;
        break;
      case ContainerType.sequence:
        icon = Icons.view_timeline;
        color = FluxForgeTheme.accentCyan;
        break;
    }

    return Icon(icon, size: 20, color: color);
  }

  Widget _buildTypeBadge(ContainerType type) {
    String label;
    Color color;

    switch (type) {
      case ContainerType.blend:
        label = 'BLEND';
        color = FluxForgeTheme.accentPurple;
        break;
      case ContainerType.random:
        label = 'RANDOM';
        color = FluxForgeTheme.accentOrange;
        break;
      case ContainerType.sequence:
        label = 'SEQUENCE';
        color = FluxForgeTheme.accentCyan;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildTimingMetrics(ContainerMeteringStats stats) {
    return Row(
      children: [
        Expanded(child: _buildMetricChip('AVG', '${stats.avgEvaluationMs.toStringAsFixed(2)} ms')),
        const SizedBox(width: 8),
        Expanded(child: _buildMetricChip('MIN', '${stats.minEvaluationMs.toStringAsFixed(2)} ms')),
        const SizedBox(width: 8),
        Expanded(child: _buildMetricChip('MAX', '${stats.maxEvaluationMs.toStringAsFixed(2)} ms')),
      ],
    );
  }

  Widget _buildMetricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
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
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: FluxForgeTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSparkline(ContainerMeteringStats stats) {
    if (stats.recentEvaluations.isEmpty) {
      return const SizedBox();
    }

    return SizedBox(
      height: 40,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: stats.recentEvaluations,
          color: FluxForgeTheme.accentCyan,
        ),
        child: Container(),
      ),
    );
  }

  Widget _buildTypeSpecificMetrics(ContainerMeteringStats stats) {
    switch (stats.type) {
      case ContainerType.blend:
        return _buildBlendMetrics(stats);
      case ContainerType.random:
        return _buildRandomMetrics(stats);
      case ContainerType.sequence:
        return _buildSequenceMetrics(stats);
    }
  }

  Widget _buildBlendMetrics(ContainerMeteringStats stats) {
    final avgActive = stats.typeSpecificStats['avg_active_children'] as double?;
    if (avgActive == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Blend Metrics',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Avg Active Children: ${avgActive.toStringAsFixed(1)}',
          style: TextStyle(
            fontSize: 11,
            color: FluxForgeTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildRandomMetrics(ContainerMeteringStats stats) {
    final selectionCounts = stats.typeSpecificStats['selection_counts'] as Map<int, int>?;
    if (selectionCounts == null || selectionCounts.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Selection Distribution',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        ...selectionCounts.entries.take(3).map((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Text(
                  'Child ${e.key}: ',
                  style: TextStyle(fontSize: 11, color: FluxForgeTheme.textSecondary),
                ),
                Text(
                  '${e.value} times',
                  style: TextStyle(fontSize: 11, color: FluxForgeTheme.textPrimary),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSequenceMetrics(ContainerMeteringStats stats) {
    final loopCount = stats.typeSpecificStats['loop_count'] as int?;
    if (loopCount == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sequence Metrics',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Loop Completions: $loopCount',
          style: TextStyle(
            fontSize: 11,
            color: FluxForgeTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();

    final maxVal = values.reduce(math.max);
    final minVal = values.reduce(math.min);
    final range = maxVal - minVal;

    if (range == 0) return;

    final stepX = size.width / (values.length - 1);

    for (int i = 0; i < values.length; i++) {
      final x = i * stepX;
      final normalizedY = (values[i] - minVal) / range;
      final y = size.height - (normalizedY * size.height);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}
