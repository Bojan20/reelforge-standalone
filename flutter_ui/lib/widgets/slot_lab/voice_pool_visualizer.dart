/// Voice Pool Visualizer Widget
///
/// Visual display of voice allocation status:
/// - 48 voice slots with active/free/stolen states
/// - Per-bus breakdown pie chart
/// - Stealing mode indicator
/// - Real-time updates via VoicePoolProvider
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';
import '../../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// VOICE STATE ENUM
// ═══════════════════════════════════════════════════════════════════════════

/// State of a single voice slot
enum VoiceSlotState {
  free(Colors.transparent, 'Free'),
  active(Color(0xFF40FF90), 'Active'),
  looping(Color(0xFF40C8FF), 'Looping'),
  stolen(Color(0xFFFF4040), 'Stolen'),
  virtual(Color(0xFFFFAA00), 'Virtual');

  final Color color;
  final String label;
  const VoiceSlotState(this.color, this.label);
}

/// Voice stealing mode
enum StealingMode {
  oldest('Oldest', Icons.history),
  quietest('Quietest', Icons.volume_down),
  lowestPriority('Low Priority', Icons.low_priority),
  none('None', Icons.block);

  final String label;
  final IconData icon;
  const StealingMode(this.label, this.icon);
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Voice pool visualizer with grid and breakdown
class VoicePoolVisualizer extends StatefulWidget {
  /// Maximum voices in pool
  final int maxVoices;

  /// Refresh interval
  final Duration refreshInterval;

  /// Show per-bus breakdown
  final bool showBusBreakdown;

  /// Compact mode (grid only)
  final bool compactMode;

  const VoicePoolVisualizer({
    super.key,
    this.maxVoices = 48,
    this.refreshInterval = const Duration(milliseconds: 250),
    this.showBusBreakdown = true,
    this.compactMode = false,
  });

  @override
  State<VoicePoolVisualizer> createState() => _VoicePoolVisualizerState();
}

class _VoicePoolVisualizerState extends State<VoicePoolVisualizer> {
  NativeVoicePoolStats _stats = NativeVoicePoolStats.empty();
  Timer? _refreshTimer;
  bool _isPaused = false;
  int _recentSteals = 0;
  DateTime? _lastStealTime;

  @override
  void initState() {
    super.initState();
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

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _stats = NativeFFI.instance.getVoicePoolStats();
    });
  }

  StealingMode _getCurrentStealingMode() {
    // Infer from stats or default to oldest
    return StealingMode.oldest;
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
          // Voice grid
          Expanded(
            flex: 2,
            child: _buildVoiceGrid(),
          ),
          const SizedBox(height: 12),
          // Stats bar
          _buildStatsBar(),
          if (widget.showBusBreakdown) ...[
            const SizedBox(height: 12),
            Expanded(
              child: _buildBusBreakdown(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final mode = _getCurrentStealingMode();
    final utilization = _stats.utilizationPercent;
    final statusColor = utilization > 90
        ? FluxForgeTheme.accentRed
        : utilization > 70
            ? FluxForgeTheme.accentOrange
            : FluxForgeTheme.accentGreen;

    return Row(
      children: [
        Icon(Icons.multitrack_audio, size: 16, color: statusColor),
        const SizedBox(width: 8),
        const Text(
          'VOICE POOL',
          style: TextStyle(
            color: FluxForgeTheme.accentBlue,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(width: 12),
        // Stealing mode badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(mode.icon, size: 10, color: Colors.white54),
              const SizedBox(width: 4),
              Text(
                mode.label,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // Utilization percentage
        Text(
          '${utilization.toStringAsFixed(0)}%',
          style: TextStyle(
            color: statusColor,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
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

  Widget _buildVoiceGrid() {
    final activeCount = _stats.activeCount;
    final loopingCount = _stats.loopingCount;
    final maxVoices = _stats.maxVoices > 0 ? _stats.maxVoices : widget.maxVoices;

    // Calculate columns based on width (8 columns default)
    const columns = 8;
    final rows = (maxVoices / columns).ceil();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          childAspectRatio: 1,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: maxVoices,
        itemBuilder: (context, index) {
          VoiceSlotState state;
          if (index < loopingCount) {
            state = VoiceSlotState.looping;
          } else if (index < activeCount) {
            state = VoiceSlotState.active;
          } else {
            state = VoiceSlotState.free;
          }
          return _VoiceSlot(index: index, state: state);
        },
      ),
    );
  }

  Widget _buildStatsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            label: 'Active',
            value: '${_stats.activeCount}',
            color: FluxForgeTheme.accentGreen,
          ),
          _StatItem(
            label: 'Looping',
            value: '${_stats.loopingCount}',
            color: FluxForgeTheme.accentCyan,
          ),
          _StatItem(
            label: 'Max',
            value: '${_stats.maxVoices}',
            color: Colors.white54,
          ),
          _StatItem(
            label: 'Free',
            value: '${_stats.maxVoices - _stats.activeCount}',
            color: Colors.white38,
          ),
        ],
      ),
    );
  }

  Widget _buildBusBreakdown() {
    final busData = [
      ('SFX', _stats.sfxVoices, const Color(0xFFFF9040)),
      ('Music', _stats.musicVoices, const Color(0xFF40C8FF)),
      ('Voice', _stats.voiceVoices, const Color(0xFFFF80B0)),
      ('Ambience', _stats.ambienceVoices, const Color(0xFF40FF90)),
      ('Aux', _stats.auxVoices, const Color(0xFFB080FF)),
      ('Master', _stats.masterVoices, const Color(0xFFFFD700)),
    ];

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
            'BY BUS',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: busData.map((item) {
                final (name, count, color) = item;
                return Expanded(
                  child: _BusBar(
                    name: name,
                    count: count,
                    color: color,
                    maxCount: _stats.maxVoices > 0 ? _stats.maxVoices : widget.maxVoices,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactView() {
    final utilization = _stats.utilizationPercent;
    final statusColor = utilization > 90
        ? FluxForgeTheme.accentRed
        : utilization > 70
            ? FluxForgeTheme.accentOrange
            : FluxForgeTheme.accentGreen;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Circular progress
          SizedBox(
            width: 32,
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: utilization / 100,
                  strokeWidth: 3,
                  backgroundColor: FluxForgeTheme.borderSubtle,
                  valueColor: AlwaysStoppedAnimation(statusColor),
                ),
                Text(
                  '${_stats.activeCount}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${utilization.toStringAsFixed(0)}% used',
                style: TextStyle(
                  color: statusColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${_stats.activeCount}/${_stats.maxVoices} voices',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _VoiceSlot extends StatelessWidget {
  final int index;
  final VoiceSlotState state;

  const _VoiceSlot({
    required this.index,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = state != VoiceSlotState.free;

    return Tooltip(
      message: 'Voice $index: ${state.label}',
      child: Container(
        decoration: BoxDecoration(
          color: isActive ? state.color.withValues(alpha: 0.8) : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isActive ? state.color : Colors.white12,
            width: 0.5,
          ),
        ),
        child: isActive
            ? Center(
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}

class _BusBar extends StatelessWidget {
  final String name;
  final int count;
  final Color color;
  final int maxCount;

  const _BusBar({
    required this.name,
    required this.count,
    required this.color,
    required this.maxCount,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxCount > 0 ? count / maxCount : 0.0;

    return Tooltip(
      message: '$name: $count voices',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeepest,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: ratio.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name[0],
              style: TextStyle(
                color: count > 0 ? color : Colors.white38,
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$count',
              style: TextStyle(
                color: count > 0 ? color : Colors.white38,
                fontSize: 8,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
