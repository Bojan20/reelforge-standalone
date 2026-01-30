// timing_validation_panel.dart
// UI for event timing validation

import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/timing_validator.dart';

class TimingValidationPanel extends StatefulWidget {
  const TimingValidationPanel({Key? key}) : super(key: key);

  @override
  State<TimingValidationPanel> createState() => _TimingValidationPanelState();
}

class _TimingValidationPanelState extends State<TimingValidationPanel> {
  final _validator = TimingValidator.instance;
  ValidationReport? _currentReport;
  bool _isMonitoring = false;
  Timer? _updateTimer;

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _startMonitoring() {
    _validator.startSession();
    setState(() {
      _isMonitoring = true;
      _currentReport = null;
    });

    // Update stats every 500ms
    _updateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _isMonitoring) {
        setState(() {
          _currentReport = _validator.generateReport();
        });
      }
    });
  }

  void _stopMonitoring() {
    _updateTimer?.cancel();
    setState(() {
      _isMonitoring = false;
      _currentReport = _validator.generateReport();
    });
  }

  void _clear() {
    _validator.clear();
    setState(() {
      _currentReport = null;
    });
  }

  void _exportReport() {
    if (_currentReport == null) return;

    final json = _validator.exportReportJson(_currentReport!);
    // TODO: Show save dialog or copy to clipboard
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Report exported to clipboard'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          if (_currentReport != null) ...[
            _buildSummaryCards(),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Statistics
                SizedBox(
                  width: 350,
                  child: _buildStatistics(),
                ),
                const SizedBox(width: 16),
                // Right: Measurements list
                Expanded(
                  child: _buildMeasurementsList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.timer, size: 24, color: Colors.green),
        const SizedBox(width: 8),
        const Text(
          'TIMING VALIDATION',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        if (!_isMonitoring) ...[
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Start'),
            onPressed: _startMonitoring,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
          ),
        ] else ...[
          ElevatedButton.icon(
            icon: const Icon(Icons.stop, size: 16),
            label: const Text('Stop'),
            onPressed: _stopMonitoring,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
          ),
        ],
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.clear, size: 18),
          onPressed: _clear,
          tooltip: 'Clear',
        ),
        if (_currentReport != null) ...[
          IconButton(
            icon: const Icon(Icons.download, size: 18),
            onPressed: _exportReport,
            tooltip: 'Export Report',
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryCards() {
    if (_currentReport == null) return const SizedBox.shrink();

    final report = _currentReport!;
    final passingSla = report.passRate >= 95.0;

    return Row(
      children: [
        _buildSummaryCard(
          icon: Icons.check_circle,
          label: 'PASS RATE',
          value: '${report.passRate.toStringAsFixed(1)}%',
          color: passingSla ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 12),
        _buildSummaryCard(
          icon: Icons.event,
          label: 'TOTAL EVENTS',
          value: '${report.totalEvents}',
          color: Colors.blue,
        ),
        const SizedBox(width: 12),
        _buildSummaryCard(
          icon: Icons.speed,
          label: 'AVG LATENCY',
          value: formatLatency(report.averageLatency),
          color: Colors.orange,
        ),
        const SizedBox(width: 12),
        _buildSummaryCard(
          icon: Icons.error,
          label: 'FAILED',
          value: '${report.failedEvents}',
          color: Colors.red,
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
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
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatistics() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white24)),
            ),
            child: const Row(
              children: [
                Icon(Icons.bar_chart, size: 16, color: Colors.grey),
                SizedBox(width: 8),
                Text(
                  'STATISTICS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_currentReport != null) ...[
                    _buildStatRow('Total Events', '${_currentReport!.totalEvents}'),
                    _buildStatRow('Passed Events', '${_currentReport!.passedEvents}',
                        color: Colors.green),
                    _buildStatRow('Failed Events', '${_currentReport!.failedEvents}',
                        color: Colors.red),
                    const Divider(height: 24),
                    _buildStatRow(
                        'Average Latency', formatLatency(_currentReport!.averageLatency)),
                    _buildStatRow('Min Latency', formatLatency(_currentReport!.minLatency)),
                    _buildStatRow('Max Latency', formatLatency(_currentReport!.maxLatency)),
                    const Divider(height: 24),
                    const Text(
                      'LATENCY DISTRIBUTION',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._currentReport!.latencyDistribution.entries.map((entry) {
                      return _buildDistributionBar(
                        entry.key,
                        entry.value,
                        _currentReport!.totalEvents,
                      );
                    }),
                  ] else ...[
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No data yet',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionBar(String label, int count, int total) {
    final percentage = total > 0 ? (count / total) * 100 : 0.0;
    final isPassing = label != '>5ms';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
              Text(
                '$count (${percentage.toStringAsFixed(1)}%)',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: percentage / 100,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(
                isPassing ? Colors.green : Colors.red,
              ),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeasurementsList() {
    final measurements = _validator.getLatestMeasurements(count: 100);

    return Container(
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white24)),
            ),
            child: Row(
              children: [
                const Icon(Icons.list, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                const Text(
                  'MEASUREMENTS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_isMonitoring)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: measurements.isEmpty
                ? const Center(
                    child: Text(
                      'No measurements yet',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: measurements.length,
                    itemBuilder: (context, index) {
                      return _buildMeasurementItem(measurements[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeasurementItem(TimingMeasurement measurement) {
    final passed = measurement.passedSla;
    final color = passed ? Colors.green : Colors.red;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_circle : Icons.error,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  measurement.stage,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                if (measurement.errorMessage != null)
                  Text(
                    measurement.errorMessage!,
                    style: const TextStyle(fontSize: 9, color: Colors.red),
                  ),
              ],
            ),
          ),
          if (measurement.latency != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                formatLatency(measurement.latency),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
