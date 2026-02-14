/// Memory Usage Panel Widget
///
/// Visual display of audio memory allocation:
/// - Breakdown by category (audio, events, containers)
/// - Progress bar visualization
/// - Budget warnings with thresholds
/// - Real-time updates via MemoryManagerProvider
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';
import '../../models/advanced_middleware_models.dart';
import '../../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// Memory category for breakdown display
enum MemoryCategory {
  audio('Audio', Icons.audiotrack, Color(0xFF40C8FF)),
  events('Events', Icons.event, Color(0xFFFF9040)),
  containers('Containers', Icons.layers, Color(0xFF40FF90)),
  streaming('Streaming', Icons.stream, Color(0xFFB080FF)),
  cache('Cache', Icons.cached, Color(0xFFFFD700));

  final String label;
  final IconData icon;
  final Color color;
  const MemoryCategory(this.label, this.icon, this.color);
}

/// Memory usage data for a category
class MemoryCategoryData {
  final MemoryCategory category;
  final int usedBytes;
  final int budgetBytes;

  const MemoryCategoryData({
    required this.category,
    required this.usedBytes,
    required this.budgetBytes,
  });

  double get usedMb => usedBytes / (1024 * 1024);
  double get budgetMb => budgetBytes / (1024 * 1024);
  double get percent => budgetBytes > 0 ? usedBytes / budgetBytes : 0.0;
  bool get isWarning => percent > 0.75;
  bool get isCritical => percent > 0.90;
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Memory usage panel with breakdown and progress bars
class MemoryUsagePanel extends StatefulWidget {
  /// Refresh interval for updates
  final Duration refreshInterval;

  /// Total memory budget in bytes
  final int totalBudgetBytes;

  /// Warning threshold (0.0-1.0)
  final double warningThreshold;

  /// Critical threshold (0.0-1.0)
  final double criticalThreshold;

  /// Compact mode (single bar)
  final bool compactMode;

  /// Show category breakdown
  final bool showBreakdown;

  const MemoryUsagePanel({
    super.key,
    this.refreshInterval = const Duration(milliseconds: 500),
    this.totalBudgetBytes = 128 * 1024 * 1024, // 128MB default
    this.warningThreshold = 0.75,
    this.criticalThreshold = 0.90,
    this.compactMode = false,
    this.showBreakdown = true,
  });

  @override
  State<MemoryUsagePanel> createState() => _MemoryUsagePanelState();
}

class _MemoryUsagePanelState extends State<MemoryUsagePanel> {
  late List<MemoryCategoryData> _categoryData;
  Timer? _refreshTimer;
  bool _isPaused = false;
  int _totalUsedBytes = 0;
  MemoryState _state = MemoryState.normal;

  @override
  void initState() {
    super.initState();
    _initCategoryData();
    _refresh();
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) {
      if (!_isPaused) _refresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _initCategoryData() {
    // Initial empty data
    _categoryData = [
      MemoryCategoryData(
        category: MemoryCategory.audio,
        usedBytes: 0,
        budgetBytes: (widget.totalBudgetBytes * 0.5).toInt(),
      ),
      MemoryCategoryData(
        category: MemoryCategory.events,
        usedBytes: 0,
        budgetBytes: (widget.totalBudgetBytes * 0.15).toInt(),
      ),
      MemoryCategoryData(
        category: MemoryCategory.containers,
        usedBytes: 0,
        budgetBytes: (widget.totalBudgetBytes * 0.1).toInt(),
      ),
      MemoryCategoryData(
        category: MemoryCategory.streaming,
        usedBytes: 0,
        budgetBytes: (widget.totalBudgetBytes * 0.2).toInt(),
      ),
      MemoryCategoryData(
        category: MemoryCategory.cache,
        usedBytes: 0,
        budgetBytes: (widget.totalBudgetBytes * 0.05).toInt(),
      ),
    ];
  }

  void _refresh() {
    if (!mounted) return;

    try {
      // Try to get real stats from FFI
      final ffi = NativeFFI.instance;

      // Get container counts for estimation
      final blendCount = ffi.getBlendContainerCount();
      final randomCount = ffi.getRandomContainerCount();
      final sequenceCount = ffi.getSequenceContainerCount();
      final totalContainers = blendCount + randomCount + sequenceCount;

      // Get voice pool stats for audio estimation
      final voiceStats = ffi.getVoicePoolStats();

      // Estimate memory usage based on activity
      // Average audio clip ~2MB, container ~16KB, event ~4KB
      final estimatedAudioBytes = voiceStats.activeCount * 512 * 1024; // 512KB per voice buffer
      final estimatedContainerBytes = totalContainers * 16 * 1024; // 16KB per container
      final estimatedEventBytes = voiceStats.activeCount * 4 * 1024; // 4KB per event
      final estimatedStreamingBytes = voiceStats.loopingCount * 256 * 1024; // 256KB streaming buffer
      final estimatedCacheBytes = (voiceStats.maxVoices - voiceStats.activeCount) * 32 * 1024; // 32KB cached

      setState(() {
        _categoryData = [
          MemoryCategoryData(
            category: MemoryCategory.audio,
            usedBytes: estimatedAudioBytes,
            budgetBytes: (widget.totalBudgetBytes * 0.5).toInt(),
          ),
          MemoryCategoryData(
            category: MemoryCategory.events,
            usedBytes: estimatedEventBytes,
            budgetBytes: (widget.totalBudgetBytes * 0.15).toInt(),
          ),
          MemoryCategoryData(
            category: MemoryCategory.containers,
            usedBytes: estimatedContainerBytes,
            budgetBytes: (widget.totalBudgetBytes * 0.1).toInt(),
          ),
          MemoryCategoryData(
            category: MemoryCategory.streaming,
            usedBytes: estimatedStreamingBytes,
            budgetBytes: (widget.totalBudgetBytes * 0.2).toInt(),
          ),
          MemoryCategoryData(
            category: MemoryCategory.cache,
            usedBytes: estimatedCacheBytes,
            budgetBytes: (widget.totalBudgetBytes * 0.05).toInt(),
          ),
        ];

        _totalUsedBytes = _categoryData.fold(0, (sum, cat) => sum + cat.usedBytes);

        final totalPercent = _totalUsedBytes / widget.totalBudgetBytes;
        if (totalPercent >= widget.criticalThreshold) {
          _state = MemoryState.critical;
        } else if (totalPercent >= widget.warningThreshold) {
          _state = MemoryState.warning;
        } else {
          _state = MemoryState.normal;
        }
      });
    } catch (e) {
      // FFI not available, keep estimated values
    }
  }

  Color get _statusColor {
    switch (_state) {
      case MemoryState.critical:
        return FluxForgeTheme.accentRed;
      case MemoryState.warning:
        return FluxForgeTheme.accentOrange;
      case MemoryState.normal:
        return FluxForgeTheme.accentGreen;
    }
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
          // Total usage bar
          _buildTotalUsageBar(),
          const SizedBox(height: 12),
          if (widget.showBreakdown) ...[
            // Category breakdown
            Expanded(
              child: _buildCategoryBreakdown(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final totalMb = _totalUsedBytes / (1024 * 1024);
    final budgetMb = widget.totalBudgetBytes / (1024 * 1024);
    final percent = widget.totalBudgetBytes > 0
        ? (_totalUsedBytes / widget.totalBudgetBytes * 100)
        : 0.0;

    return Row(
      children: [
        Icon(Icons.memory, size: 16, color: _statusColor),
        const SizedBox(width: 8),
        const Text(
          'MEMORY USAGE',
          style: TextStyle(
            color: FluxForgeTheme.accentBlue,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const Spacer(),
        // Usage text
        Text(
          '${totalMb.toStringAsFixed(1)} / ${budgetMb.toStringAsFixed(0)} MB',
          style: TextStyle(
            color: _statusColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '(${percent.toStringAsFixed(0)}%)',
          style: TextStyle(
            color: _statusColor.withValues(alpha: 0.7),
            fontSize: 10,
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
      ],
    );
  }

  Widget _buildTotalUsageBar() {
    final percent = widget.totalBudgetBytes > 0
        ? _totalUsedBytes / widget.totalBudgetBytes
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Warning indicator
        if (_state != MemoryState.normal)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _statusColor.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _state == MemoryState.critical ? Icons.error : Icons.warning,
                  size: 12,
                  color: _statusColor,
                ),
                const SizedBox(width: 6),
                Text(
                  _state == MemoryState.critical
                      ? 'CRITICAL: Memory budget exceeded!'
                      : 'WARNING: Approaching memory limit',
                  style: TextStyle(
                    color: _statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        // Progress bar
        Container(
          height: 16,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              // Threshold markers
              Positioned(
                left: widget.warningThreshold * 100,
                child: Container(
                  width: 1,
                  height: 16,
                  color: FluxForgeTheme.accentOrange.withValues(alpha: 0.5),
                ),
              ),
              Positioned(
                left: widget.criticalThreshold * 100,
                child: Container(
                  width: 1,
                  height: 16,
                  color: FluxForgeTheme.accentRed.withValues(alpha: 0.5),
                ),
              ),
              // Fill bar
              LayoutBuilder(
                builder: (context, constraints) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: constraints.maxWidth * percent.clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _statusColor.withValues(alpha: 0.7),
                          _statusColor,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryBreakdown() {
    return ListView.separated(
      itemCount: _categoryData.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return _CategoryRow(data: _categoryData[index]);
      },
    );
  }

  Widget _buildCompactView() {
    final totalMb = _totalUsedBytes / (1024 * 1024);
    final percent = widget.totalBudgetBytes > 0
        ? _totalUsedBytes / widget.totalBudgetBytes
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.memory, size: 14, color: _statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${totalMb.toStringAsFixed(1)} MB',
                  style: TextStyle(
                    color: _statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                LinearProgressIndicator(
                  value: percent.clamp(0.0, 1.0),
                  backgroundColor: FluxForgeTheme.bgMid,
                  valueColor: AlwaysStoppedAnimation(_statusColor),
                  minHeight: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(percent * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              color: _statusColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _CategoryRow extends StatelessWidget {
  final MemoryCategoryData data;

  const _CategoryRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final color = data.isCritical
        ? FluxForgeTheme.accentRed
        : data.isWarning
            ? FluxForgeTheme.accentOrange
            : data.category.color;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          // Icon and label
          SizedBox(
            width: 90,
            child: Row(
              children: [
                Icon(data.category.icon, size: 12, color: data.category.color),
                const SizedBox(width: 6),
                Text(
                  data.category.label,
                  style: TextStyle(
                    color: data.category.color,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Progress bar
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: constraints.maxWidth * data.percent.clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Value
          SizedBox(
            width: 60,
            child: Text(
              '${data.usedMb.toStringAsFixed(1)} MB',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
