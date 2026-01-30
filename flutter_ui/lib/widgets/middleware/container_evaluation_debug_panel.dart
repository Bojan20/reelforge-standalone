/// Container Evaluation Debug Panel
///
/// Shows real-time container evaluation logs:
/// - Last 100 evaluations with details
/// - Filter by container type
/// - Export to JSON for QA
/// - Statistics overview
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/fluxforge_theme.dart';
import '../../services/container_evaluation_logger.dart';

/// Container Evaluation Debug Panel
class ContainerEvaluationDebugPanel extends StatefulWidget {
  final double maxHeight;

  const ContainerEvaluationDebugPanel({
    super.key,
    this.maxHeight = 500,
  });

  @override
  State<ContainerEvaluationDebugPanel> createState() => _ContainerEvaluationDebugPanelState();
}

class _ContainerEvaluationDebugPanelState extends State<ContainerEvaluationDebugPanel> {
  ContainerEvaluationType? _filterType;
  final _logger = ContainerEvaluationLogger.instance;

  @override
  void initState() {
    super.initState();
    _logger.addListener(_onLogsUpdated);
  }

  @override
  void dispose() {
    _logger.removeListener(_onLogsUpdated);
    super.dispose();
  }

  void _onLogsUpdated() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final stats = _logger.stats;
    final logs = _filterType == null
        ? _logger.logs
        : _logger.getLogsByType(_filterType!);

    return Container(
      height: widget.maxHeight,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: FluxForgeTheme.borderSubtle,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(stats),

          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),

          // Filter bar
          _buildFilterBar(),

          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),

          // Log list
          Expanded(
            child: logs.isEmpty ? _buildEmptyState() : _buildLogList(logs),
          ),

          // Footer
          _buildFooter(stats),
        ],
      ),
    );
  }

  Widget _buildHeader(ContainerEvaluationStats stats) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(
            Icons.analytics,
            size: 18,
            color: FluxForgeTheme.accentBlue,
          ),
          const SizedBox(width: 8),
          Text(
            'Container Evaluations',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),

          // Stats badges
          _buildStatBadge(
            stats.totalEvaluations.toString(),
            'Total',
            FluxForgeTheme.accentBlue,
          ),
          const SizedBox(width: 8),
          _buildStatBadge(
            stats.uniqueContainers.toString(),
            'Containers',
            FluxForgeTheme.accentOrange,
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(
            'Filter:',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),

          // All button
          _buildFilterChip(
            label: 'All',
            isActive: _filterType == null,
            onTap: () => setState(() => _filterType = null),
          ),
          const SizedBox(width: 4),

          // Blend button
          _buildFilterChip(
            label: 'Blend',
            isActive: _filterType == ContainerEvaluationType.blend,
            color: Colors.purple,
            onTap: () => setState(() => _filterType = ContainerEvaluationType.blend),
          ),
          const SizedBox(width: 4),

          // Random button
          _buildFilterChip(
            label: 'Random',
            isActive: _filterType == ContainerEvaluationType.random,
            color: Colors.amber,
            onTap: () => setState(() => _filterType = ContainerEvaluationType.random),
          ),
          const SizedBox(width: 4),

          // Sequence button
          _buildFilterChip(
            label: 'Sequence',
            isActive: _filterType == ContainerEvaluationType.sequence,
            color: Colors.teal,
            onTap: () => setState(() => _filterType = ContainerEvaluationType.sequence),
          ),

          const Spacer(),

          // Clear button
          IconButton(
            icon: Icon(Icons.clear_all, size: 16),
            color: FluxForgeTheme.textMuted,
            tooltip: 'Clear Logs',
            onPressed: () {
              _logger.clear();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isActive,
    Color? color,
    required VoidCallback onTap,
  }) {
    final chipColor = color ?? FluxForgeTheme.accentBlue;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? chipColor.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? chipColor : FluxForgeTheme.borderSubtle,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? chipColor : FluxForgeTheme.textMuted,
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 48,
            color: FluxForgeTheme.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'No evaluations yet',
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Container evaluations will appear here',
            style: TextStyle(
              color: FluxForgeTheme.textMuted.withValues(alpha: 0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(List<ContainerEvaluationLog> logs) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        return _buildLogItem(logs[index]);
      },
    );
  }

  Widget _buildLogItem(ContainerEvaluationLog log) {
    final typeColor = _getTypeColor(log.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: typeColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              // Type badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  log.type.name.toUpperCase(),
                  style: TextStyle(
                    color: typeColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Container name
              Expanded(
                child: Text(
                  log.containerName,
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // Timestamp
              Text(
                _formatTime(log.timestamp),
                style: TextStyle(
                  color: FluxForgeTheme.textMuted,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Summary
          Text(
            log.summary,
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Color _getTypeColor(ContainerEvaluationType type) {
    switch (type) {
      case ContainerEvaluationType.blend:
        return Colors.purple;
      case ContainerEvaluationType.random:
        return Colors.amber;
      case ContainerEvaluationType.sequence:
        return Colors.teal;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else {
      return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  Widget _buildFooter(ContainerEvaluationStats stats) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Stats text
          Expanded(
            child: Text(
              'B: ${stats.blendEvaluations} | R: ${stats.randomEvaluations} | S: ${stats.sequenceEvaluations}',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),

          // Export button
          TextButton.icon(
            icon: Icon(Icons.download, size: 14),
            label: Text('Export JSON'),
            style: TextButton.styleFrom(
              foregroundColor: FluxForgeTheme.accentBlue,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            onPressed: () {
              final json = _logger.exportToJson();
              Clipboard.setData(ClipboardData(text: json));

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Exported ${stats.totalEvaluations} logs to clipboard'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
