/// Voice Pool Stats Panel
///
/// Displays real-time voice pool statistics from the audio engine:
/// - Active voice count / max voices
/// - Utilization percentage with visual meter
/// - Breakdown by source (DAW, SlotLab, Middleware, Browser)
/// - Breakdown by bus (SFX, Music, Voice, Ambience, Aux, Master)
/// - Health indicator (Healthy → Warning → Critical)
///
/// Uses FFI to query Rust engine's voice pool state.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// Compact voice pool stats badge for status bars
class VoicePoolStatsBadge extends StatefulWidget {
  final Duration refreshInterval;

  const VoicePoolStatsBadge({
    super.key,
    this.refreshInterval = const Duration(milliseconds: 500),
  });

  @override
  State<VoicePoolStatsBadge> createState() => _VoicePoolStatsBadgeState();
}

class _VoicePoolStatsBadgeState extends State<VoicePoolStatsBadge> {
  NativeVoicePoolStats _stats = NativeVoicePoolStats.empty();
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
      _stats = NativeFFI.instance.getVoicePoolStats();
    });
  }

  Color _getStatusColor() {
    switch (_stats.healthStatus) {
      case 'critical':
        return FluxForgeTheme.accentRed;
      case 'warning':
        return FluxForgeTheme.accentOrange;
      case 'elevated':
        return FluxForgeTheme.accentYellow;
      default:
        return FluxForgeTheme.accentGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();

    return Tooltip(
      message: 'Voices: ${_stats.activeCount}/${_stats.maxVoices} (${_stats.utilizationPercent.toStringAsFixed(0)}%)\n'
          'DAW: ${_stats.dawVoices}, SlotLab: ${_stats.slotLabVoices}, Middleware: ${_stats.middlewareVoices}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: statusColor.withValues(alpha: 0.5), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${_stats.activeCount}/${_stats.maxVoices}',
              style: FluxForgeTheme.dockMono(
                size: 10,
                color: Colors.white70,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'voices',
              style: FluxForgeTheme.dockSans(
                size: 10,
                color: Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full voice pool stats panel with detailed breakdown
class VoicePoolStatsPanel extends StatefulWidget {
  final Duration refreshInterval;
  final bool showSourceBreakdown;
  final bool showBusBreakdown;
  final bool compactMode;

  const VoicePoolStatsPanel({
    super.key,
    this.refreshInterval = const Duration(milliseconds: 250),
    this.showSourceBreakdown = true,
    this.showBusBreakdown = true,
    this.compactMode = false,
  });

  @override
  State<VoicePoolStatsPanel> createState() => _VoicePoolStatsPanelState();
}

class _VoicePoolStatsPanelState extends State<VoicePoolStatsPanel> {
  NativeVoicePoolStats _stats = NativeVoicePoolStats.empty();
  Timer? _refreshTimer;
  bool _isPaused = false;

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

  Color _getStatusColor() {
    switch (_stats.healthStatus) {
      case 'critical':
        return FluxForgeTheme.accentRed;
      case 'warning':
        return FluxForgeTheme.accentOrange;
      case 'elevated':
        return FluxForgeTheme.accentYellow;
      default:
        return FluxForgeTheme.accentGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();

    if (widget.compactMode) {
      return _buildCompactView(statusColor);
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
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.multitrack_audio, size: 16, color: statusColor),
              const SizedBox(width: 8),
              Text(
                'VOICE POOL',
                style: FluxForgeTheme.dockSans(
                  size: 10,
                  weight: FontWeight.bold,
                  letterSpacing: 1,
                  color: statusColor,
                ),
              ),
              const Spacer(),
              // Pause/Play toggle
              IconButton(
                icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 14),
                onPressed: () => setState(() => _isPaused = !_isPaused),
                splashRadius: 12,
                color: Colors.white38,
                tooltip: _isPaused ? 'Resume' : 'Pause',
              ),
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

          // Main utilization display
          _buildUtilizationMeter(statusColor),
          const SizedBox(height: 16),

          // Voice counts
          Row(
            children: [
              Expanded(
                child: _buildStatBox(
                  'Active',
                  '${_stats.activeCount}',
                  statusColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatBox(
                  'Max',
                  '${_stats.maxVoices}',
                  Colors.white54,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatBox(
                  'Looping',
                  '${_stats.loopingCount}',
                  FluxForgeTheme.accentCyan,
                ),
              ),
            ],
          ),

          // Source breakdown
          if (widget.showSourceBreakdown) ...[
            const SizedBox(height: 16),
            _buildSectionHeader('BY SOURCE'),
            const SizedBox(height: 8),
            _buildSourceBreakdown(),
          ],

          // Bus breakdown
          if (widget.showBusBreakdown) ...[
            const SizedBox(height: 16),
            _buildSectionHeader('BY BUS'),
            const SizedBox(height: 8),
            _buildBusBreakdown(),
          ],

          // Timestamp
          const SizedBox(height: 12),
          Text(
            'Updated: ${_formatTime(_stats.timestamp)}',
            style: FluxForgeTheme.dockSans(
              size: 9,
              color: Colors.white24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactView(Color statusColor) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Utilization circle
          SizedBox(
            width: 32,
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _stats.utilizationPercent / 100,
                  strokeWidth: 3,
                  backgroundColor: FluxForgeTheme.borderSubtle,
                  valueColor: AlwaysStoppedAnimation(statusColor),
                ),
                Text(
                  '${_stats.activeCount}',
                  style: FluxForgeTheme.dockMono(
                    size: 10,
                    weight: FontWeight.bold,
                    color: Colors.white70,
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
                '${_stats.utilizationPercent.toStringAsFixed(0)}%',
                style: FluxForgeTheme.dockMono(
                  size: 11,
                  weight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
              Text(
                '${_stats.activeCount}/${_stats.maxVoices} voices',
                style: FluxForgeTheme.dockSans(
                  size: 9,
                  color: Colors.white38,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUtilizationMeter(Color statusColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Utilization',
              style: FluxForgeTheme.dockSans(
                size: 10,
                color: Colors.white54,
              ),
            ),
            Text(
              '${_stats.utilizationPercent.toStringAsFixed(1)}%',
              style: FluxForgeTheme.dockMono(
                size: 14,
                weight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Progress bar with gradient
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth * (_stats.utilizationPercent / 100).clamp(0.0, 1.0);
              return Stack(
                children: [
                  // Threshold markers
                  Positioned(
                    left: constraints.maxWidth * 0.5,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 1,
                      color: Colors.white12,
                    ),
                  ),
                  Positioned(
                    left: constraints.maxWidth * 0.7,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 1,
                      color: FluxForgeTheme.accentOrange.withValues(alpha: 0.3),
                    ),
                  ),
                  Positioned(
                    left: constraints.maxWidth * 0.9,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 1,
                      color: FluxForgeTheme.accentRed.withValues(alpha: 0.3),
                    ),
                  ),
                  // Fill bar
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: width,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          statusColor.withValues(alpha: 0.7),
                          statusColor,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: FluxForgeTheme.dockMono(
              size: 12,
              weight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: FluxForgeTheme.dockSans(
              size: 9,
              color: Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 10,
          decoration: BoxDecoration(
            color: FluxForgeTheme.accentBlue,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: FluxForgeTheme.dockSans(
            size: 9,
            weight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Colors.white38,
          ),
        ),
      ],
    );
  }

  Widget _buildSourceBreakdown() {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        _buildSourceChip('DAW', _stats.dawVoices, FluxForgeTheme.accentBlue),
        _buildSourceChip('SlotLab', _stats.slotLabVoices, FluxForgeTheme.accentOrange),
        _buildSourceChip('Middleware', _stats.middlewareVoices, FluxForgeTheme.accentGreen),
        _buildSourceChip('Browser', _stats.browserVoices, Colors.purple),
      ],
    );
  }

  Widget _buildBusBreakdown() {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        _buildSourceChip('SFX', _stats.sfxVoices, Colors.amber),
        _buildSourceChip('Music', _stats.musicVoices, FluxForgeTheme.accentCyan),
        _buildSourceChip('Voice', _stats.voiceVoices, Colors.pink),
        _buildSourceChip('Ambience', _stats.ambienceVoices, Colors.teal),
        _buildSourceChip('Aux', _stats.auxVoices, Colors.indigo),
        _buildSourceChip('Master', _stats.masterVoices, Colors.white54),
      ],
    );
  }

  Widget _buildSourceChip(String label, int count, Color color) {
    final hasVoices = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: hasVoices ? color.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: hasVoices ? color.withValues(alpha: 0.5) : FluxForgeTheme.borderSubtle,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: FluxForgeTheme.dockSans(
              size: 9,
              color: hasVoices ? color : Colors.white38,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: FluxForgeTheme.dockMono(
              size: 9,
              weight: FontWeight.bold,
              color: hasVoices ? color : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${(time.millisecond ~/ 10).toString().padLeft(2, '0')}';
  }
}

/// Inline voice count for status bars
class VoicePoolInlineStats extends StatefulWidget {
  final Duration refreshInterval;

  const VoicePoolInlineStats({
    super.key,
    this.refreshInterval = const Duration(milliseconds: 500),
  });

  @override
  State<VoicePoolInlineStats> createState() => _VoicePoolInlineStatsState();
}

class _VoicePoolInlineStatsState extends State<VoicePoolInlineStats> {
  NativeVoicePoolStats _stats = NativeVoicePoolStats.empty();
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
      _stats = NativeFFI.instance.getVoicePoolStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (_stats.healthStatus) {
      'critical' => FluxForgeTheme.accentRed,
      'warning' => FluxForgeTheme.accentOrange,
      'elevated' => FluxForgeTheme.accentYellow,
      _ => FluxForgeTheme.accentGreen,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.multitrack_audio, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          '${_stats.activeCount}/${_stats.maxVoices}',
          style: FluxForgeTheme.dockMono(
            size: 10,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '(${_stats.utilizationPercent.toStringAsFixed(0)}%)',
          style: FluxForgeTheme.dockSans(
            size: 10,
            color: Colors.white38,
          ),
        ),
      ],
    );
  }
}
