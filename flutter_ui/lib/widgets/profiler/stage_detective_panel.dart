/// Stage Detective Panel
///
/// P1-10: Stage→Event Resolution Trace UI
///
/// Shows the complete resolution path for each stage trigger:
/// - Why did/didn't it play?
/// - Which fallbacks were tried?
/// - Which event was ultimately chosen?

import 'package:flutter/material.dart';
import '../../services/stage_resolution_tracer.dart';

class StageDetectivePanel extends StatefulWidget {
  const StageDetectivePanel({super.key});

  @override
  State<StageDetectivePanel> createState() => _StageDetectivePanelState();
}

class _StageDetectivePanelState extends State<StageDetectivePanel> {
  /// Selected trace for detail view
  ResolutionTrace? _selectedTrace;

  /// Filter: show only failed traces
  bool _showFailedOnly = false;

  /// Search query
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final tracer = StageResolutionTracer.instance;

    return Column(
      children: [
        // Header
        _buildHeader(tracer),
        const Divider(height: 1),

        // Stats
        _buildStats(tracer),
        const Divider(height: 1),

        // Filters
        _buildFilters(),
        const Divider(height: 1),

        // Trace list
        Expanded(
          child: Row(
            children: [
              // Left: Trace list
              Expanded(
                flex: 2,
                child: _buildTraceList(tracer),
              ),

              // Right: Detail view
              if (_selectedTrace != null) ...[
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 3,
                  child: _buildDetailView(_selectedTrace!),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(StageResolutionTracer tracer) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey[900],
      child: Row(
        children: [
          const Icon(Icons.search, size: 20, color: Colors.cyan),
          const SizedBox(width: 8),
          const Text(
            'Stage Detective',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Spacer(),

          // Enable/Disable
          Switch(
            value: tracer.enabled,
            onChanged: (value) {
              if (value) {
                tracer.enable();
              } else {
                tracer.disable();
              }
              setState(() {});
            },
            activeColor: Colors.green,
          ),
          const SizedBox(width: 8),
          Text(
            tracer.enabled ? 'Enabled' : 'Disabled',
            style: TextStyle(
              color: tracer.enabled ? Colors.green : Colors.grey,
              fontSize: 12,
            ),
          ),

          const SizedBox(width: 16),

          // Clear
          IconButton(
            icon: const Icon(Icons.clear_all, size: 20),
            onPressed: () {
              tracer.clear();
              setState(() {
                _selectedTrace = null;
              });
            },
            tooltip: 'Clear traces',
          ),

          // Export
          PopupMenuButton<String>(
            icon: const Icon(Icons.download, size: 20),
            tooltip: 'Export',
            onSelected: (value) {
              if (value == 'json') {
                final json = tracer.exportToJson();
              } else if (value == 'csv') {
                final csv = tracer.exportToCsv();
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

  Widget _buildStats(StageResolutionTracer tracer) {
    final failedCount = tracer.getFailedTraces().length;
    final successRate = tracer.completedTraceCount > 0
        ? ((tracer.completedTraceCount - failedCount) / tracer.completedTraceCount * 100)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey[850],
      child: Row(
        children: [
          _buildStatCard(
            'Total Traces',
            '${tracer.completedTraceCount}',
            Icons.assessment,
            Colors.blue,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            'Success Rate',
            '${successRate.toStringAsFixed(1)}%',
            Icons.check_circle,
            successRate >= 95 ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            'Failed',
            '$failedCount',
            Icons.cancel,
            failedCount > 0 ? Colors.red : Colors.green,
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

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.grey[850],
      child: Row(
        children: [
          // Search field
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search stages...',
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          const SizedBox(width: 12),

          // Show failed only toggle
          FilterChip(
            label: const Text('Failed Only'),
            selected: _showFailedOnly,
            onSelected: (value) {
              setState(() {
                _showFailedOnly = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTraceList(StageResolutionTracer tracer) {
    var traces = tracer.getRecentTraces(100);

    // Apply filters
    if (_showFailedOnly) {
      traces = traces.where((t) => !t.success).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      traces = traces.where((t) => t.originalStage.toLowerCase().contains(query)).toList();
    }

    if (traces.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_empty, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No traces yet',
              style: TextStyle(color: Colors.grey[500]),
            ),
            const SizedBox(height: 8),
            Text(
              'Enable tracing and trigger audio events',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: traces.length,
      itemBuilder: (context, index) {
        final trace = traces[index];
        final isSelected = _selectedTrace?.id == trace.id;
        return _buildTraceItem(trace, isSelected);
      },
    );
  }

  Widget _buildTraceItem(ResolutionTrace trace, bool isSelected) {
    final color = trace.success ? Colors.green : Colors.red;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedTrace = isSelected ? null : trace;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.1) : null,
          border: Border(
            left: BorderSide(color: color, width: 3),
            bottom: BorderSide(color: Colors.grey[800]!),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  trace.success ? Icons.check_circle : Icons.cancel,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trace.originalStage,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${trace.resolutionTimeMs?.toStringAsFixed(1) ?? "?"}ms',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              trace.summary,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailView(ResolutionTrace trace) {
    return Container(
      color: Colors.grey[900],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey[850],
            child: Row(
              children: [
                Icon(
                  trace.success ? Icons.check_circle : Icons.cancel,
                  size: 20,
                  color: trace.success ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trace.originalStage,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        trace.summary,
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${trace.resolutionTimeMs?.toStringAsFixed(2) ?? "?"}ms',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${trace.steps.length} steps',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Steps
          Expanded(
            child: ListView.builder(
              itemCount: trace.steps.length,
              itemBuilder: (context, index) {
                final step = trace.steps[index];
                return _buildStepItem(step, index + 1);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem(ResolutionStep step, int stepNumber) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: step.color, width: 3),
          bottom: BorderSide(color: Colors.grey[800]!),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step number
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: step.color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '$stepNumber',
                style: TextStyle(fontSize: 11, color: step.color, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Icon
          Icon(step.icon, size: 16, color: step.color),
          const SizedBox(width: 8),

          // Description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.description,
                  style: const TextStyle(fontSize: 13),
                ),
                if (step.data != null && step.data!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  ...step.data!.entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${entry.key}: ${entry.value}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500], fontFamily: 'monospace'),
                    ),
                  )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
