/// DSP Attribution Panel
///
/// P1-11: DSP Load Attribution UI
///
/// Shows CPU usage by event/stage/bus with flame graph and bar chart.

import 'package:flutter/material.dart';
import '../../services/dsp_attribution_profiler.dart';

class DspAttributionPanel extends StatefulWidget {
  const DspAttributionPanel({super.key});

  @override
  State<DspAttributionPanel> createState() => _DspAttributionPanelState();
}

class _DspAttributionPanelState extends State<DspAttributionPanel> {
  /// Selected view mode
  int _viewMode = 0; // 0=Top Sources, 1=By Operation, 2=By Bus, 3=Flame Graph

  @override
  Widget build(BuildContext context) {
    final profiler = DspAttributionProfiler.instance;

    return Column(
      children: [
        // Header
        _buildHeader(profiler),
        const Divider(height: 1),

        // Stats summary
        _buildStatsSummary(profiler),
        const Divider(height: 1),

        // View mode tabs
        _buildViewModeTabs(),
        const Divider(height: 1),

        // Content
        Expanded(
          child: _buildViewContent(profiler),
        ),
      ],
    );
  }

  Widget _buildHeader(DspAttributionProfiler profiler) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey[900],
      child: Row(
        children: [
          const Icon(Icons.pie_chart, size: 20, color: Colors.purple),
          const SizedBox(width: 8),
          const Text(
            'DSP Attribution',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Spacer(),

          // Enable/Disable
          Switch(
            value: profiler.enabled,
            onChanged: (value) {
              if (value) {
                profiler.enable();
              } else {
                profiler.disable();
              }
              setState(() {});
            },
            activeColor: Colors.green,
          ),
          const SizedBox(width: 8),
          Text(
            profiler.enabled ? 'Enabled' : 'Disabled',
            style: TextStyle(
              color: profiler.enabled ? Colors.green : Colors.grey,
              fontSize: 12,
            ),
          ),

          const SizedBox(width: 16),

          // Clear
          IconButton(
            icon: const Icon(Icons.clear_all, size: 20),
            onPressed: () {
              profiler.clear();
              setState(() {});
            },
            tooltip: 'Clear statistics',
          ),

          // Export
          PopupMenuButton<String>(
            icon: const Icon(Icons.download, size: 20),
            tooltip: 'Export',
            onSelected: (value) {
              if (value == 'json') {
                final json = profiler.exportToJson();
                debugPrint('[DspAttribution] Exported JSON: $json');
              } else if (value == 'csv') {
                final csv = profiler.exportToCsv();
                debugPrint('[DspAttribution] Exported CSV:\n$csv');
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'json', child: Text('Export JSON')),
              const PopupMenuItem(value: 'csv', child: Text('Export CSV')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSummary(DspAttributionProfiler profiler) {
    final totalCpu = profiler.getTotalCpuLoad();
    final topSource = profiler.getTopSources(1);

    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey[850],
      child: Row(
        children: [
          _buildStatCard(
            'Total CPU',
            '${totalCpu.toStringAsFixed(1)}%',
            Icons.memory,
            totalCpu > 80 ? Colors.red : (totalCpu > 50 ? Colors.orange : Colors.green),
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            'Sources',
            '${profiler.sourceStats.length}',
            Icons.source,
            Colors.blue,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            'Top Consumer',
            topSource.isNotEmpty ? topSource.first.source : 'N/A',
            Icons.warning,
            Colors.orange,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            'Operations',
            '${profiler.totalAttributions}',
            Icons.analytics,
            Colors.cyan,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewModeTabs() {
    return Container(
      color: Colors.grey[850],
      child: Row(
        children: [
          _buildTab('Top Sources', 0),
          _buildTab('By Operation', 1),
          _buildTab('By Bus', 2),
          _buildTab('Flame Graph', 3),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = _viewMode == index;

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _viewMode = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? Colors.purple : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.purple : Colors.grey[400],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewContent(DspAttributionProfiler profiler) {
    switch (_viewMode) {
      case 0:
        return _buildTopSourcesView(profiler);
      case 1:
        return _buildByOperationView(profiler);
      case 2:
        return _buildByBusView(profiler);
      case 3:
        return _buildFlameGraphView(profiler);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTopSourcesView(DspAttributionProfiler profiler) {
    final topSources = profiler.getTopSources(50);

    if (topSources.isEmpty) {
      return _buildEmptyState('No DSP data yet');
    }

    // Calculate max for bar scaling
    final maxTime = topSources.first.totalProcessingTimeMs;

    return ListView.builder(
      itemCount: topSources.length,
      itemBuilder: (context, index) {
        final stats = topSources[index];
        return _buildSourceItem(stats, index + 1, maxTime);
      },
    );
  }

  Widget _buildSourceItem(SourceDspStats stats, int rank, double maxTime) {
    final barWidth = maxTime > 0 ? (stats.totalProcessingTimeMs / maxTime) : 0.0;
    final color = _getColorForRank(rank);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[800]!),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Rank
              SizedBox(
                width: 40,
                child: Text(
                  '#$rank',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // Source name
              Expanded(
                child: Text(
                  stats.source,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Total time
              Text(
                '${stats.totalProcessingTimeMs.toStringAsFixed(1)}ms',
                style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Bar chart
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              widthFactor: barWidth,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // Stats
          Row(
            children: [
              const SizedBox(width: 40),
              Text(
                'Ops: ${stats.operationCount}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              const SizedBox(width: 12),
              Text(
                'Avg: ${stats.avgProcessingTimeMs.toStringAsFixed(1)}ms',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              const SizedBox(width: 12),
              Text(
                'Peak: ${stats.peakProcessingTimeMs.toStringAsFixed(1)}ms',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              const Spacer(),
              if (stats.mostExpensiveOperation != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    stats.mostExpensiveOperation!.name,
                    style: TextStyle(fontSize: 10, color: color),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildByOperationView(DspAttributionProfiler profiler) {
    final cpuByOp = profiler.getCpuLoadByOperation();

    if (cpuByOp.isEmpty) {
      return _buildEmptyState('No operation data yet');
    }

    final entries = cpuByOp.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxValue = entries.first.value;

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _buildOperationItem(entry.key, entry.value, maxValue);
      },
    );
  }

  Widget _buildOperationItem(DspOperationType operation, double timeMs, double maxValue) {
    final barWidth = maxValue > 0 ? (timeMs / maxValue) : 0.0;
    final color = _getColorForOperation(operation);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[800]!),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_getIconForOperation(operation), size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  operation.name.toUpperCase(),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Text(
                '${timeMs.toStringAsFixed(1)}ms',
                style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              widthFactor: barWidth,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildByBusView(DspAttributionProfiler profiler) {
    final cpuByBus = profiler.getCpuLoadByBus();

    if (cpuByBus.isEmpty) {
      return _buildEmptyState('No bus data yet');
    }

    final entries = cpuByBus.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxValue = entries.first.value;

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _buildBusItem(entry.key, entry.value, maxValue);
      },
    );
  }

  Widget _buildBusItem(String busName, double timeMs, double maxValue) {
    final barWidth = maxValue > 0 ? (timeMs / maxValue) : 0.0;
    final color = _getColorForBus(busName);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[800]!),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.router, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  busName,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Text(
                '${timeMs.toStringAsFixed(1)}ms',
                style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              widthFactor: barWidth,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlameGraphView(DspAttributionProfiler profiler) {
    final topSources = profiler.getTopSources(20);

    if (topSources.isEmpty) {
      return _buildEmptyState('No data for flame graph');
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: CustomPaint(
        size: Size.infinite,
        painter: _FlameGraphPainter(topSources),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hourglass_empty, size: 48, color: Colors.grey[600]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),
          Text(
            'Enable profiling and trigger audio events',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Color _getColorForRank(int rank) {
    if (rank == 1) return Colors.red;
    if (rank <= 3) return Colors.orange;
    if (rank <= 10) return Colors.amber;
    return Colors.blue;
  }

  Color _getColorForOperation(DspOperationType operation) {
    switch (operation) {
      case DspOperationType.decode:
        return Colors.cyan;
      case DspOperationType.resample:
        return Colors.blue;
      case DspOperationType.mixing:
        return Colors.purple;
      case DspOperationType.eq:
        return Colors.green;
      case DspOperationType.dynamics:
        return Colors.orange;
      case DspOperationType.reverb:
        return Colors.teal;
      case DspOperationType.delay:
        return Colors.amber;
      case DspOperationType.effects:
        return Colors.pink;
      case DspOperationType.busSum:
        return Colors.indigo;
      case DspOperationType.metering:
        return Colors.grey;
    }
  }

  IconData _getIconForOperation(DspOperationType operation) {
    switch (operation) {
      case DspOperationType.decode:
        return Icons.music_note;
      case DspOperationType.resample:
        return Icons.transform;
      case DspOperationType.mixing:
        return Icons.tune;
      case DspOperationType.eq:
        return Icons.equalizer;
      case DspOperationType.dynamics:
        return Icons.compress;
      case DspOperationType.reverb:
        return Icons.waves;
      case DspOperationType.delay:
        return Icons.schedule;
      case DspOperationType.effects:
        return Icons.auto_fix_high;
      case DspOperationType.busSum:
        return Icons.merge;
      case DspOperationType.metering:
        return Icons.bar_chart;
    }
  }

  Color _getColorForBus(String busName) {
    if (busName.contains('master')) return Colors.red;
    if (busName.contains('music')) return Colors.purple;
    if (busName.contains('sfx')) return Colors.orange;
    if (busName.contains('voice')) return Colors.blue;
    if (busName.contains('ambience')) return Colors.teal;
    if (busName.contains('aux')) return Colors.amber;
    return Colors.grey;
  }
}

/// Flame graph painter
class _FlameGraphPainter extends CustomPainter {
  final List<SourceDspStats> sources;

  _FlameGraphPainter(this.sources);

  @override
  void paint(Canvas canvas, Size size) {
    if (sources.isEmpty) return;

    final totalTime = sources.fold<double>(0.0, (sum, s) => sum + s.totalProcessingTimeMs);
    if (totalTime == 0) return;

    double x = 0;
    final height = size.height;

    for (final stats in sources) {
      final width = (stats.totalProcessingTimeMs / totalTime) * size.width;

      // Draw rectangle
      final rect = Rect.fromLTWH(x, 0, width, height);
      final paint = Paint()
        ..color = _getColorForStats(stats)
        ..style = PaintingStyle.fill;

      canvas.drawRect(rect, paint);

      // Draw border
      final borderPaint = Paint()
        ..color = Colors.black.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRect(rect, borderPaint);

      // Draw label (if width > 50)
      if (width > 50) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: stats.source,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(maxWidth: width - 8);
        textPainter.paint(canvas, Offset(x + 4, (height - textPainter.height) / 2));
      }

      x += width;
    }
  }

  Color _getColorForStats(SourceDspStats stats) {
    final hue = (stats.source.hashCode % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.7, 0.5).toColor();
  }

  @override
  bool shouldRepaint(covariant _FlameGraphPainter oldDelegate) {
    return sources != oldDelegate.sources;
  }
}
