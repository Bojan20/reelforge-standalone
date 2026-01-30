/// Demo Mode Panel
///
/// UI controls for demo mode auto-play in SlotLab:
/// - Quick start/stop controls
/// - Sequence selector
/// - Statistics display
/// - Configuration settings
///
/// Created: 2026-01-30 (P4.17)

import 'package:flutter/material.dart';

import '../../services/demo_mode_service.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DEMO MODE BUTTON
// ═══════════════════════════════════════════════════════════════════════════

/// Compact demo mode toggle button
class DemoModeButton extends StatelessWidget {
  final VoidCallback? onTap;

  const DemoModeButton({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DemoModeService.instance,
      builder: (context, _) {
        final service = DemoModeService.instance;
        final isActive = service.isPlaying || service.isPaused;

        return Tooltip(
          message: isActive ? 'Stop Demo Mode' : 'Start Demo Mode',
          child: InkWell(
            onTap: () {
              if (isActive) {
                service.stop();
              } else {
                onTap?.call();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF40FF90).withAlpha(30) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isActive ? const Color(0xFF40FF90) : FluxForgeTheme.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isActive ? Icons.stop_circle : Icons.play_circle,
                    size: 16,
                    color: isActive ? const Color(0xFF40FF90) : Colors.white70,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'DEMO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isActive ? const Color(0xFF40FF90) : Colors.white70,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DEMO MODE STATUS BADGE
// ═══════════════════════════════════════════════════════════════════════════

/// Shows current demo mode status
class DemoModeStatusBadge extends StatelessWidget {
  const DemoModeStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DemoModeService.instance,
      builder: (context, _) {
        final service = DemoModeService.instance;
        if (service.state == DemoModeState.idle) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _getStateColor(service.state).withAlpha(50),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _getStateColor(service.state)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStateIcon(service.state),
              const SizedBox(width: 4),
              Text(
                _getStateLabel(service),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _getStateColor(service.state),
                ),
              ),
              if (service.currentSequence != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${service.currentStepIndex + 1}/${service.currentSequence!.totalSteps}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white54,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStateIcon(DemoModeState state) {
    switch (state) {
      case DemoModeState.playing:
        return Icon(Icons.play_arrow, size: 12, color: _getStateColor(state));
      case DemoModeState.paused:
        return Icon(Icons.pause, size: 12, color: _getStateColor(state));
      case DemoModeState.waiting:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _getStateColor(state),
          ),
        );
      case DemoModeState.idle:
        return const SizedBox.shrink();
    }
  }

  Color _getStateColor(DemoModeState state) {
    switch (state) {
      case DemoModeState.playing:
        return const Color(0xFF40FF90);
      case DemoModeState.paused:
        return const Color(0xFFFFD700);
      case DemoModeState.waiting:
        return const Color(0xFF4A9EFF);
      case DemoModeState.idle:
        return Colors.white54;
    }
  }

  String _getStateLabel(DemoModeService service) {
    if (service.currentSequence != null) {
      return service.currentSequence!.name;
    }
    return service.state.label;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DEMO MODE PANEL
// ═══════════════════════════════════════════════════════════════════════════

/// Full demo mode control panel
class DemoModePanel extends StatefulWidget {
  final VoidCallback? onClose;

  const DemoModePanel({
    super.key,
    this.onClose,
  });

  @override
  State<DemoModePanel> createState() => _DemoModePanelState();
}

class _DemoModePanelState extends State<DemoModePanel> {
  DemoSequence? _selectedSequence;

  @override
  void initState() {
    super.initState();
    final sequences = BuiltInDemoSequences.all();
    if (sequences.isNotEmpty) {
      _selectedSequence = sequences.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DemoModeService.instance,
      builder: (context, _) {
        final service = DemoModeService.instance;

        return Container(
          width: 320,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            border: Border.all(color: FluxForgeTheme.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              _buildHeader(),
              const SizedBox(height: 12),

              // Controls
              _buildControls(service),
              const SizedBox(height: 12),

              // Sequence selector
              _buildSequenceSelector(service),
              const SizedBox(height: 12),

              // Statistics
              _buildStatistics(service),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.play_circle, size: 16, color: Color(0xFF40FF90)),
        const SizedBox(width: 8),
        const Text(
          'DEMO MODE',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white70,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        if (widget.onClose != null)
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: widget.onClose,
            color: Colors.white54,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ],
    );
  }

  Widget _buildControls(DemoModeService service) {
    return Row(
      children: [
        // Start/Stop button
        Expanded(
          child: ElevatedButton.icon(
            icon: Icon(
              service.isPlaying || service.isPaused ? Icons.stop : Icons.play_arrow,
              size: 18,
            ),
            label: Text(
              service.isPlaying || service.isPaused ? 'STOP' : 'START',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              if (service.isPlaying || service.isPaused) {
                service.stop();
              } else if (_selectedSequence != null) {
                service.startSequence(_selectedSequence!);
              } else {
                service.startAutoSpin();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: service.isPlaying
                  ? const Color(0xFFFF4060)
                  : const Color(0xFF40FF90),
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Pause/Resume button
        IconButton(
          icon: Icon(
            service.isPaused ? Icons.play_arrow : Icons.pause,
            size: 20,
          ),
          onPressed: service.isPlaying || service.isPaused
              ? () {
                  if (service.isPaused) {
                    service.resume();
                  } else {
                    service.pause();
                  }
                }
              : null,
          style: IconButton.styleFrom(
            backgroundColor: FluxForgeTheme.bgMid,
          ),
        ),
      ],
    );
  }

  Widget _buildSequenceSelector(DemoModeService service) {
    final sequences = BuiltInDemoSequences.all();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SEQUENCE',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white38,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            border: Border.all(color: FluxForgeTheme.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<DemoSequence>(
              value: _selectedSequence,
              isExpanded: true,
              isDense: true,
              dropdownColor: FluxForgeTheme.bgSurface,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              items: [
                const DropdownMenuItem<DemoSequence>(
                  value: null,
                  child: Text('Random Auto-Spin'),
                ),
                ...sequences.map((seq) => DropdownMenuItem<DemoSequence>(
                      value: seq,
                      child: Text(seq.name),
                    )),
              ],
              onChanged: service.isPlaying
                  ? null
                  : (seq) => setState(() => _selectedSequence = seq),
            ),
          ),
        ),
        if (_selectedSequence != null) ...[
          const SizedBox(height: 4),
          Text(
            _selectedSequence!.description,
            style: const TextStyle(fontSize: 10, color: Colors.white38),
          ),
          Text(
            '${_selectedSequence!.totalSteps} steps • ~${_formatDuration(_selectedSequence!.estimatedDuration)}',
            style: const TextStyle(fontSize: 10, color: Colors.white24),
          ),
        ],
      ],
    );
  }

  Widget _buildStatistics(DemoModeService service) {
    final stats = service.statistics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'STATISTICS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white38,
                letterSpacing: 1.0,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: service.resetStatistics,
              child: const Text('Reset', style: TextStyle(fontSize: 10)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            children: [
              _buildStatRow('Spins', '${stats.totalSpins}'),
              _buildStatRow('Wins', '${stats.wins} (${stats.winRate.toStringAsFixed(1)}%)'),
              _buildStatRow('Big Wins', '${stats.bigWins}'),
              _buildStatRow('Total Bet', '\$${stats.totalBetAmount.toStringAsFixed(2)}'),
              _buildStatRow('Total Win', '\$${stats.totalWinAmount.toStringAsFixed(2)}'),
              _buildStatRow('RTP', '${stats.rtp.toStringAsFixed(2)}%'),
              _buildStatRow('Play Time', _formatDuration(stats.totalPlayTime)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.white54),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds}s';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    } else {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DEMO MODE QUICK MENU
// ═══════════════════════════════════════════════════════════════════════════

/// Quick popup menu for demo mode
class DemoModeQuickMenu extends StatelessWidget {
  const DemoModeQuickMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DemoModeService.instance,
      builder: (context, _) {
        final service = DemoModeService.instance;

        return PopupMenuButton<Object>(
          icon: Icon(
            service.isPlaying ? Icons.stop_circle : Icons.play_circle,
            size: 18,
            color: service.isPlaying ? const Color(0xFF40FF90) : Colors.white70,
          ),
          tooltip: 'Demo Mode',
          onSelected: (value) {
            if (value == 'stop') {
              service.stop();
            } else if (value == 'pause') {
              service.pause();
            } else if (value == 'resume') {
              service.resume();
            } else if (value == 'random') {
              service.startAutoSpin();
            } else if (value is DemoSequence) {
              service.startSequence(value);
            }
          },
          itemBuilder: (context) {
            final items = <PopupMenuEntry<Object>>[];

            if (service.isPlaying || service.isPaused) {
              // Currently running
              items.add(PopupMenuItem<Object>(
                value: 'stop',
                child: Row(
                  children: [
                    const Icon(Icons.stop, size: 16, color: Color(0xFFFF4060)),
                    const SizedBox(width: 8),
                    const Text('Stop Demo'),
                  ],
                ),
              ));
              if (service.isPlaying) {
                items.add(PopupMenuItem<Object>(
                  value: 'pause',
                  child: Row(
                    children: [
                      const Icon(Icons.pause, size: 16, color: Color(0xFFFFD700)),
                      const SizedBox(width: 8),
                      const Text('Pause'),
                    ],
                  ),
                ));
              } else {
                items.add(PopupMenuItem<Object>(
                  value: 'resume',
                  child: Row(
                    children: [
                      const Icon(Icons.play_arrow, size: 16, color: Color(0xFF40FF90)),
                      const SizedBox(width: 8),
                      const Text('Resume'),
                    ],
                  ),
                ));
              }
            } else {
              // Not running
              items.add(PopupMenuItem<Object>(
                value: 'random',
                child: Row(
                  children: [
                    const Icon(Icons.shuffle, size: 16, color: Color(0xFF4A9EFF)),
                    const SizedBox(width: 8),
                    const Text('Random Auto-Spin'),
                  ],
                ),
              ));
              items.add(const PopupMenuDivider());
              items.add(const PopupMenuItem<Object>(
                enabled: false,
                height: 24,
                child: Text(
                  'SEQUENCES',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white38,
                    letterSpacing: 1.0,
                  ),
                ),
              ));
              for (final seq in BuiltInDemoSequences.all()) {
                items.add(PopupMenuItem<Object>(
                  value: seq,
                  child: Text(seq.name),
                ));
              }
            }

            return items;
          },
        );
      },
    );
  }
}
