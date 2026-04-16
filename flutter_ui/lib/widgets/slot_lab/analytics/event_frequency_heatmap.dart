/// Event Frequency Heatmap Widget — T2.4
///
/// Visualizes batch simulation results as a heatmap:
///
/// ┌──────────────────────────────────────────────────────────────┐
/// │ AUDIO EVENT FREQUENCY HEATMAP (1M spins)                     │
/// ├──────────────────────────────────────────────────────────────┤
/// │  REEL_SPIN      ████████████████████████████████  1000/1000  │
/// │  WIN_1          ██████████████████░░░░░░░░░░░░░░  186/1000   │
/// │  NEAR_MISS      ████████████░░░░░░░░░░░░░░░░░░░░  120/1000   │
/// │                                                              │
/// │  🔴 Peak voices: 14/48 (29%)  ⚠️ Max dry spell: 47 spins    │
/// │  📊 Actual RTP: 96.48% (target: 96.50%)                     │
/// └──────────────────────────────────────────────────────────────┘
///
/// Used in SlotLab analytics panel after batch simulation completes.

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/batch_sim_service.dart';
import '../../../theme/fluxforge_theme.dart';

/// Heatmap widget — shows event frequencies from a BatchSimResult.
/// Self-contained: polls NativeFFI for task progress if a task is running.
class EventFrequencyHeatmap extends StatefulWidget {
  final BatchSimResult? result;
  final BatchSimTask? runningTask;
  final String? gameName;
  final VoidCallback? onRunSimulation;

  const EventFrequencyHeatmap({
    super.key,
    this.result,
    this.runningTask,
    this.gameName,
    this.onRunSimulation,
  });

  @override
  State<EventFrequencyHeatmap> createState() => _EventFrequencyHeatmapState();
}

class _EventFrequencyHeatmapState extends State<EventFrequencyHeatmap> {
  Timer? _pollTimer;
  double _progress = 0.0;
  BatchSimResult? _liveResult;

  @override
  void initState() {
    super.initState();
    _liveResult = widget.result;
    if (widget.runningTask != null) {
      _startPolling();
    }
  }

  @override
  void didUpdateWidget(EventFrequencyHeatmap old) {
    super.didUpdateWidget(old);
    if (widget.result != old.result) {
      _liveResult = widget.result;
    }
    if (widget.runningTask != old.runningTask) {
      if (widget.runningTask != null) {
        _startPolling();
      } else {
        _stopPolling();
      }
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final task = widget.runningTask;
      if (task == null) {
        _stopPolling();
        return;
      }
      final prog = task.progress;
      final result = task.consumeResult();
      setState(() {
        _progress = prog;
        if (result != null) {
          _liveResult = result;
        }
      });
      if (prog >= 1.0 || result != null) {
        _stopPolling();
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final result = _liveResult;
    final task = widget.runningTask;
    final isRunning = task != null && _progress < 1.0;

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(isRunning),
          if (isRunning) _buildProgressBar(),
          if (result != null) ...[
            _buildSummaryRow(result),
            const Divider(height: 1, color: Colors.white12),
            Expanded(child: _buildHeatmap(result)),
            const Divider(height: 1, color: Colors.white12),
            _buildFooter(result),
          ] else if (!isRunning)
            Expanded(child: _buildEmptyState()),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isRunning) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.bar_chart,
            size: 14,
            color: FluxForgeTheme.accentBlue.withOpacity(0.8),
          ),
          const SizedBox(width: 6),
          Text(
            'AUDIO EVENT FREQUENCY HEATMAP',
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              color: FluxForgeTheme.accentBlue.withOpacity(0.9),
              letterSpacing: 1.0,
            ),
          ),
          if (_liveResult != null) ...[
            const SizedBox(width: 6),
            Text(
              '(${_formatSpins(_liveResult!.spinCount)} spins)',
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'monospace',
                color: Colors.white38,
              ),
            ),
          ],
          const Spacer(),
          if (!isRunning && widget.onRunSimulation != null)
            _buildRunButton(),
        ],
      ),
    );
  }

  Widget _buildRunButton() {
    return InkWell(
      onTap: widget.onRunSimulation,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentGreen.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: FluxForgeTheme.accentGreen.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_arrow,
              size: 10,
              color: FluxForgeTheme.accentGreen,
            ),
            const SizedBox(width: 3),
            Text(
              'RUN SIM',
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: FluxForgeTheme.accentGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Simulating...',
                style: TextStyle(
                  fontSize: 9,
                  fontFamily: 'monospace',
                  color: FluxForgeTheme.accentOrange,
                ),
              ),
              const Spacer(),
              Text(
                '${(_progress * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 9,
                  fontFamily: 'monospace',
                  color: FluxForgeTheme.accentOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(
                FluxForgeTheme.accentOrange,
              ),
              minHeight: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(BatchSimResult result) {
    final voicePct = (result.voiceBudget.peakVoices /
            result.voiceBudget.voiceBudget.clamp(1, 999999) *
            100)
        .toStringAsFixed(0);
    final voiceColor = result.voiceBudget.peakVoices > result.voiceBudget.voiceBudget
        ? FluxForgeTheme.accentRed
        : result.voiceBudget.peakVoices > result.voiceBudget.voiceBudget * 0.75
            ? FluxForgeTheme.accentOrange
            : FluxForgeTheme.accentGreen;

    final dryColor = result.drySpellAnalysis.maxDrySpins > 100
        ? FluxForgeTheme.accentRed
        : result.drySpellAnalysis.maxDrySpins > 50
            ? FluxForgeTheme.accentOrange
            : Colors.white60;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          _summaryChip(
            Icons.headphones,
            'Peak: ${result.voiceBudget.peakVoices}/${result.voiceBudget.voiceBudget} ($voicePct%)',
            voiceColor,
          ),
          const SizedBox(width: 12),
          _summaryChip(
            Icons.warning_amber,
            'Max dry: ${result.drySpellAnalysis.maxDrySpins}',
            dryColor,
          ),
          const SizedBox(width: 12),
          _summaryChip(
            Icons.percent,
            'RTP: ${(result.actualRtp * 100).toStringAsFixed(2)}%',
            Colors.white70,
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontFamily: 'monospace',
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildHeatmap(BatchSimResult result) {
    // Sort events by frequency (highest first)
    final entries = result.eventFrequencyMap.entries.toList()
      ..sort((a, b) => b.value.avgPer1000Spins.compareTo(a.value.avgPer1000Spins));

    if (entries.isEmpty) {
      return const Center(
        child: Text(
          'No events recorded',
          style: TextStyle(color: Colors.white24, fontSize: 10),
        ),
      );
    }

    final maxFreq = entries.first.value.avgPer1000Spins.clamp(0.001, double.infinity);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: entries.length,
      itemBuilder: (ctx, idx) {
        final entry = entries[idx];
        return _buildEventRow(entry.key, entry.value, maxFreq);
      },
    );
  }

  Widget _buildEventRow(String eventName, EventFrequency freq, double maxFreq) {
    final fillFrac = (freq.avgPer1000Spins / maxFreq).clamp(0.0, 1.0);
    final barColor = _colorForEvent(eventName, fillFrac);
    final freqLabel = freq.avgPer1000Spins >= 100
        ? '${freq.avgPer1000Spins.toStringAsFixed(0)}/1000'
        : freq.avgPer1000Spins >= 1
            ? '${freq.avgPer1000Spins.toStringAsFixed(1)}/1000'
            : '${freq.avgPer1000Spins.toStringAsFixed(2)}/1000';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1.5),
      child: Row(
        children: [
          // Event name
          SizedBox(
            width: 130,
            child: Text(
              eventName,
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'monospace',
                color: Colors.white70,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Bar
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final totalWidth = constraints.maxWidth;
                final fillWidth = totalWidth * fillFrac;
                final emptyWidth = totalWidth - fillWidth;
                return Row(
                  children: [
                    if (fillWidth > 0)
                      Container(
                        width: fillWidth,
                        height: 8,
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    if (emptyWidth > 0)
                      Container(
                        width: emptyWidth,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          // Frequency label
          SizedBox(
            width: 72,
            child: Text(
              freqLabel,
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'monospace',
                color: Colors.white38,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BatchSimResult result) {
    final rtpDelta = result.rtpDelta;
    final rtpColor = rtpDelta.abs() < 0.005
        ? FluxForgeTheme.accentGreen
        : rtpDelta.abs() < 0.02
            ? FluxForgeTheme.accentOrange
            : FluxForgeTheme.accentRed;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.analytics, size: 10, color: Colors.white24),
          const SizedBox(width: 4),
          Text(
            'Actual RTP: ${(result.actualRtp * 100).toStringAsFixed(2)}%',
            style: TextStyle(
              fontSize: 9,
              fontFamily: 'monospace',
              color: rtpColor,
            ),
          ),
          if (result.targetRtp > 0) ...[
            Text(
              '  (target: ${result.targetRtp.toStringAsFixed(2)}%)',
              style: const TextStyle(
                fontSize: 9,
                fontFamily: 'monospace',
                color: Colors.white38,
              ),
            ),
          ],
          const Spacer(),
          Text(
            '${_formatDuration(result.simDurationMs)}',
            style: const TextStyle(
              fontSize: 9,
              fontFamily: 'monospace',
              color: Colors.white24,
            ),
          ),
          if (result.warnings.isNotEmpty) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: result.warnings.join('\n'),
              child: Icon(
                Icons.warning_amber,
                size: 11,
                color: FluxForgeTheme.accentOrange,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bar_chart,
            size: 32,
            color: Colors.white12,
          ),
          const SizedBox(height: 8),
          Text(
            'Run a batch simulation to see\naudio event frequency analysis',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              color: Colors.white24,
            ),
          ),
          if (widget.onRunSimulation != null) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: widget.onRunSimulation,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: FluxForgeTheme.accentGreen.withOpacity(0.3),
                  ),
                ),
                child: Text(
                  'RUN SIMULATION',
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: FluxForgeTheme.accentGreen,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────────

  Color _colorForEvent(String name, double fillFrac) {
    // Color coding by event category
    if (name.startsWith('WIN_5') || name.startsWith('JACKPOT')) {
      return FluxForgeTheme.accentYellow;
    } else if (name.startsWith('WIN_4') || name.startsWith('BIG_WIN')) {
      return FluxForgeTheme.accentOrange;
    } else if (name.startsWith('WIN_3')) {
      return FluxForgeTheme.accentOrange.withOpacity(0.7);
    } else if (name.startsWith('WIN_')) {
      return FluxForgeTheme.accentGreen.withOpacity(0.4 + fillFrac * 0.6);
    } else if (name.contains('TRIGGER') || name.contains('FREE_SPIN')) {
      return FluxForgeTheme.accentPurple.withOpacity(0.8);
    } else if (name.contains('NEAR_MISS') || name.contains('ANTICIPATION')) {
      return FluxForgeTheme.accentCyan.withOpacity(0.6);
    } else if (name.contains('REEL')) {
      return FluxForgeTheme.accentBlue.withOpacity(0.5);
    } else if (name.contains('DEAD') || name.contains('LOW')) {
      return Colors.white.withOpacity(0.15);
    }
    return FluxForgeTheme.accentBlue.withOpacity(0.4 + fillFrac * 0.4);
  }

  String _formatSpins(int spins) {
    if (spins >= 1_000_000) return '${(spins / 1_000_000).toStringAsFixed(1)}M';
    if (spins >= 1_000) return '${(spins / 1_000).toStringAsFixed(0)}K';
    return spins.toString();
  }

  String _formatDuration(int ms) {
    if (ms < 1000) return '${ms}ms';
    if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
    return '${(ms / 60000).toStringAsFixed(1)}m';
  }
}
