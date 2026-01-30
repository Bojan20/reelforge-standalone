/// Latency Profiler Panel
///
/// P1-08: End-to-End Latency Measurement UI
///
/// Visual breakdown of Dart→FFI→Engine→Audio latency chain.
/// Target validation: < 5ms total latency.

import 'package:flutter/material.dart';
import '../../services/latency_profiler.dart';

class LatencyProfilerPanel extends StatefulWidget {
  const LatencyProfilerPanel({super.key});

  @override
  State<LatencyProfilerPanel> createState() => _LatencyProfilerPanelState();
}

class _LatencyProfilerPanelState extends State<LatencyProfilerPanel> {
  /// Selected measurement for detail view
  LatencyMeasurement? _selectedMeasurement;

  @override
  Widget build(BuildContext context) {
    final profiler = LatencyProfiler.instance;
    final stats = profiler.getStats();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with controls
        _buildHeader(profiler, stats),
        const Divider(height: 1),

        // Statistics panel
        _buildStatsPanel(stats),
        const Divider(height: 1),

        // Measurement list
        Expanded(
          child: _buildMeasurementList(profiler),
        ),

        // Detail panel (if measurement selected)
        if (_selectedMeasurement != null) ...[
          const Divider(height: 1),
          _buildDetailPanel(_selectedMeasurement!),
        ],
      ],
    );
  }

  Widget _buildHeader(LatencyProfiler profiler, LatencyStats stats) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey[900],
      child: Row(
        children: [
          // Title
          const Icon(Icons.speed, size: 20, color: Colors.blue),
          const SizedBox(width: 8),
          const Text(
            'Latency Profiler',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Spacer(),

          // Enable/Disable toggle
          Switch(
            value: profiler.enabled,
            onChanged: (value) {
              if (value) {
                profiler.enable();
              } else {
                profiler.disable();
              }
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

          // Clear button
          IconButton(
            icon: const Icon(Icons.clear_all, size: 20),
            onPressed: profiler.clear,
            tooltip: 'Clear measurements',
          ),

          // Export button
          IconButton(
            icon: const Icon(Icons.download, size: 20),
            onPressed: () {
              // TODO: Export to file
              final json = profiler.exportToJson();
              debugPrint('[LatencyProfiler] Exported: $json');
            },
            tooltip: 'Export to JSON',
          ),
        ],
      ),
    );
  }

  Widget _buildStatsPanel(LatencyStats stats) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey[850],
      child: Row(
        children: [
          // Total measurements
          _buildStatCard(
            'Total',
            '${stats.completeMeasurements}',
            Icons.assessment,
            Colors.blue,
          ),
          const SizedBox(width: 12),

          // Average latency
          _buildStatCard(
            'Avg Latency',
            '${stats.avgTotalLatencyMs.toStringAsFixed(2)}ms',
            Icons.timer,
            stats.avgTotalLatencyMs < 5.0 ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 12),

          // Min latency
          _buildStatCard(
            'Min',
            '${stats.minTotalLatencyMs.toStringAsFixed(2)}ms',
            Icons.arrow_downward,
            Colors.green,
          ),
          const SizedBox(width: 12),

          // Max latency
          _buildStatCard(
            'Max',
            '${stats.maxTotalLatencyMs.toStringAsFixed(2)}ms',
            Icons.arrow_upward,
            stats.maxTotalLatencyMs < 5.0 ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 12),

          // Meets target percentage
          _buildStatCard(
            'Meets Target (<5ms)',
            '${stats.meetsTargetPercent.toStringAsFixed(1)}%',
            Icons.check_circle,
            stats.meetsTargetPercent >= 95.0 ? Colors.green : Colors.orange,
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
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeasurementList(LatencyProfiler profiler) {
    final measurements = profiler.getRecentMeasurements(100);

    if (measurements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_empty, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No measurements yet',
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

    return ListView.builder(
      itemCount: measurements.length,
      itemBuilder: (context, index) {
        final measurement = measurements[index];
        final isSelected = _selectedMeasurement?.id == measurement.id;

        return _buildMeasurementItem(measurement, isSelected);
      },
    );
  }

  Widget _buildMeasurementItem(LatencyMeasurement measurement, bool isSelected) {
    final totalMs = measurement.totalLatencyMs ?? 0.0;
    final meetsTarget = measurement.meetsTarget;
    final color = meetsTarget ? Colors.green : Colors.orange;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedMeasurement = isSelected ? null : measurement;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.1) : null,
          border: Border(
            left: BorderSide(
              color: color,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            // Status icon
            Icon(
              meetsTarget ? Icons.check_circle : Icons.warning,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 8),

            // Source name
            Expanded(
              flex: 3,
              child: Text(
                measurement.source,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Total latency
            Expanded(
              flex: 2,
              child: Text(
                '${totalMs.toStringAsFixed(2)}ms',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),

            // Breakdown (compact)
            Expanded(
              flex: 3,
              child: _buildLatencyBreakdownBar(measurement),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLatencyBreakdownBar(LatencyMeasurement measurement) {
    final totalUs = measurement.totalLatencyUs ?? 1;
    if (totalUs == 0) return const SizedBox.shrink();

    final dartToFfi = measurement.dartToFfiUs ?? 0;
    final ffiToEngine = measurement.ffiToEngineUs ?? 0;
    final engineToScheduled = measurement.engineToScheduledUs ?? 0;
    final scheduledToOutput = measurement.scheduledToOutputUs ?? 0;

    final dartPct = dartToFfi / totalUs;
    final ffiPct = ffiToEngine / totalUs;
    final enginePct = engineToScheduled / totalUs;
    final scheduledPct = scheduledToOutput / totalUs;

    return Row(
      children: [
        if (dartPct > 0)
          Flexible(
            flex: (dartPct * 100).toInt(),
            child: Container(
              height: 12,
              color: Colors.blue,
              margin: const EdgeInsets.only(right: 1),
            ),
          ),
        if (ffiPct > 0)
          Flexible(
            flex: (ffiPct * 100).toInt(),
            child: Container(
              height: 12,
              color: Colors.purple,
              margin: const EdgeInsets.only(right: 1),
            ),
          ),
        if (enginePct > 0)
          Flexible(
            flex: (enginePct * 100).toInt(),
            child: Container(
              height: 12,
              color: Colors.orange,
              margin: const EdgeInsets.only(right: 1),
            ),
          ),
        if (scheduledPct > 0)
          Flexible(
            flex: (scheduledPct * 100).toInt(),
            child: Container(
              height: 12,
              color: Colors.cyan,
            ),
          ),
      ],
    );
  }

  Widget _buildDetailPanel(LatencyMeasurement measurement) {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(12),
      color: Colors.grey[850],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.info_outline, size: 18, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                'Measurement Details: ${measurement.source}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  setState(() {
                    _selectedMeasurement = null;
                  });
                },
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Breakdown table
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left column: Timestamps
                Expanded(
                  child: _buildTimestampColumn(measurement),
                ),

                const VerticalDivider(width: 1),

                // Right column: Latency breakdown
                Expanded(
                  child: _buildLatencyColumn(measurement),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimestampColumn(LatencyMeasurement measurement) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Timestamps',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildTimestampRow('Dart Trigger', measurement.dartTriggerUs),
        if (measurement.ffiReturnUs != null)
          _buildTimestampRow('FFI Return', measurement.ffiReturnUs!),
        if (measurement.engineProcessedUs != null)
          _buildTimestampRow('Engine Processed', measurement.engineProcessedUs!),
        if (measurement.audioScheduledUs != null)
          _buildTimestampRow('Audio Scheduled', measurement.audioScheduledUs!),
        if (measurement.audioOutputUs != null)
          _buildTimestampRow('Audio Output', measurement.audioOutputUs!),
      ],
    );
  }

  Widget _buildTimestampRow(String label, int timestampUs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          ),
          Text(
            '${timestampUs}µs',
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildLatencyColumn(LatencyMeasurement measurement) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Latency Breakdown',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (measurement.dartToFfiUs != null)
          _buildLatencyRow('Dart → FFI', measurement.dartToFfiUs!, Colors.blue),
        if (measurement.ffiToEngineUs != null)
          _buildLatencyRow('FFI → Engine', measurement.ffiToEngineUs!, Colors.purple),
        if (measurement.engineToScheduledUs != null)
          _buildLatencyRow('Engine → Scheduled', measurement.engineToScheduledUs!, Colors.orange),
        if (measurement.scheduledToOutputUs != null)
          _buildLatencyRow('Buffer Latency', measurement.scheduledToOutputUs!, Colors.cyan),
        const Divider(height: 16),
        if (measurement.totalLatencyUs != null)
          _buildLatencyRow(
            'TOTAL',
            measurement.totalLatencyUs!,
            measurement.meetsTarget ? Colors.green : Colors.red,
            bold: true,
          ),
      ],
    );
  }

  Widget _buildLatencyRow(String label, int latencyUs, Color color, {bool bold = false}) {
    final latencyMs = latencyUs / 1000.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[400],
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            '${latencyUs}µs',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '(${latencyMs.toStringAsFixed(2)}ms)',
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
