/// Container Storage Metrics Widget
///
/// Displays real-time container storage statistics from Rust engine:
/// - Blend container count
/// - Random container count
/// - Sequence container count
/// - Total container count
/// - Memory estimate (approximate)
///
/// Used in Middleware panel footer or debug overlay.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// Container storage metrics model
class ContainerMetrics {
  final int blendCount;
  final int randomCount;
  final int sequenceCount;
  final int totalCount;
  final DateTime timestamp;

  const ContainerMetrics({
    required this.blendCount,
    required this.randomCount,
    required this.sequenceCount,
    required this.totalCount,
    required this.timestamp,
  });

  factory ContainerMetrics.empty() => ContainerMetrics(
        blendCount: 0,
        randomCount: 0,
        sequenceCount: 0,
        totalCount: 0,
        timestamp: DateTime.now(),
      );

  factory ContainerMetrics.fromFFI(NativeFFI ffi) {
    final blend = ffi.getBlendContainerCount();
    final random = ffi.getRandomContainerCount();
    final sequence = ffi.getSequenceContainerCount();
    return ContainerMetrics(
      blendCount: blend,
      randomCount: random,
      sequenceCount: sequence,
      totalCount: blend + random + sequence,
      timestamp: DateTime.now(),
    );
  }

  /// Estimated memory usage (rough approximation)
  /// Blend: ~200 bytes base + 50 bytes per child
  /// Random: ~150 bytes base + 40 bytes per child
  /// Sequence: ~250 bytes base + 60 bytes per step
  int get estimatedMemoryBytes {
    // Conservative estimates (base only, children unknown)
    return (blendCount * 200) + (randomCount * 150) + (sequenceCount * 250);
  }

  String get estimatedMemoryFormatted {
    final bytes = estimatedMemoryBytes;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

/// Compact metrics badge for status bars
class ContainerMetricsBadge extends StatefulWidget {
  final Duration refreshInterval;

  const ContainerMetricsBadge({
    super.key,
    this.refreshInterval = const Duration(seconds: 2),
  });

  @override
  State<ContainerMetricsBadge> createState() => _ContainerMetricsBadgeState();
}

class _ContainerMetricsBadgeState extends State<ContainerMetricsBadge> {
  ContainerMetrics _metrics = ContainerMetrics.empty();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _metrics = ContainerMetrics.fromFFI(NativeFFI.instance);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Blend: ${_metrics.blendCount}, Random: ${_metrics.randomCount}, Sequence: ${_metrics.sequenceCount}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storage,
              size: 12,
              color: _metrics.totalCount > 0
                  ? FluxForgeTheme.accentGreen
                  : Colors.white38,
            ),
            const SizedBox(width: 4),
            Text(
              '${_metrics.totalCount} containers',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Detailed metrics panel with breakdown
class ContainerStorageMetricsPanel extends StatefulWidget {
  final Duration refreshInterval;
  final bool showMemoryEstimate;

  const ContainerStorageMetricsPanel({
    super.key,
    this.refreshInterval = const Duration(seconds: 1),
    this.showMemoryEstimate = true,
  });

  @override
  State<ContainerStorageMetricsPanel> createState() =>
      _ContainerStorageMetricsPanelState();
}

class _ContainerStorageMetricsPanelState
    extends State<ContainerStorageMetricsPanel> {
  ContainerMetrics _metrics = ContainerMetrics.empty();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _metrics = ContainerMetrics.fromFFI(NativeFFI.instance);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.storage, size: 16, color: FluxForgeTheme.accentBlue),
              const SizedBox(width: 8),
              Text(
                'CONTAINER STORAGE',
                style: TextStyle(
                  color: FluxForgeTheme.accentBlue,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 14),
                onPressed: _refresh,
                splashRadius: 12,
                color: Colors.white38,
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Container counts
          _buildCountRow('Blend', _metrics.blendCount, Colors.purple),
          const SizedBox(height: 6),
          _buildCountRow('Random', _metrics.randomCount, Colors.amber),
          const SizedBox(height: 6),
          _buildCountRow('Sequence', _metrics.sequenceCount, Colors.teal),
          const SizedBox(height: 10),

          // Divider
          Container(height: 1, color: FluxForgeTheme.borderSubtle),
          const SizedBox(height: 10),

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${_metrics.totalCount}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),

          // Memory estimate
          if (widget.showMemoryEstimate) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Est. Memory',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                  ),
                ),
                Text(
                  _metrics.estimatedMemoryFormatted,
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],

          // Last updated
          const SizedBox(height: 8),
          Text(
            'Updated: ${_formatTime(_metrics.timestamp)}',
            style: TextStyle(
              color: Colors.white24,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountRow(String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: color, width: 1),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
            ),
          ),
        ),
        Text(
          '$count',
          style: TextStyle(
            color: count > 0 ? color : Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}

/// Inline metrics row for panel footers
class ContainerMetricsRow extends StatefulWidget {
  final Duration refreshInterval;

  const ContainerMetricsRow({
    super.key,
    this.refreshInterval = const Duration(seconds: 2),
  });

  @override
  State<ContainerMetricsRow> createState() => _ContainerMetricsRowState();
}

class _ContainerMetricsRowState extends State<ContainerMetricsRow> {
  ContainerMetrics _metrics = ContainerMetrics.empty();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _metrics = ContainerMetrics.fromFFI(NativeFFI.instance);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildChip('B', _metrics.blendCount, Colors.purple),
        const SizedBox(width: 4),
        _buildChip('R', _metrics.randomCount, Colors.amber),
        const SizedBox(width: 4),
        _buildChip('S', _metrics.sequenceCount, Colors.teal),
        const SizedBox(width: 8),
        Text(
          '= ${_metrics.totalCount}',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: count > 0 ? color.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: count > 0 ? color : FluxForgeTheme.borderSubtle,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: count > 0 ? color : Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 2),
          Text(
            '$count',
            style: TextStyle(
              color: count > 0 ? color : Colors.white38,
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
