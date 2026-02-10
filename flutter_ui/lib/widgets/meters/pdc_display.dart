/// PDC Display Widget - Plugin Delay Compensation Status
///
/// Shows:
/// - Total system latency (samples + ms)
/// - Per-track latency breakdown
/// - Master bus latency
/// - PDC enable status

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';
import '../../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PDC INFO WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Compact PDC indicator for transport bar
class PdcIndicator extends StatelessWidget {
  final int totalLatencySamples;
  final double totalLatencyMs;
  final bool isEnabled;
  final VoidCallback? onTap;

  const PdcIndicator({
    super.key,
    required this.totalLatencySamples,
    required this.totalLatencyMs,
    this.isEnabled = true,
    this.onTap,
  });

  /// Create from FFI data
  factory PdcIndicator.fromEngine({VoidCallback? onTap}) {
    try {
      final ffi = NativeFFI.instance;
      if (ffi.isLoaded) {
        return PdcIndicator(
          totalLatencySamples: ffi.pdcGetTotalLatencySamples(),
          totalLatencyMs: ffi.pdcGetTotalLatencyMs(),
          isEnabled: ffi.pdcIsEnabled(),
          onTap: onTap,
        );
      }
    } catch (_) { /* ignored */ }
    return PdcIndicator(
      totalLatencySamples: 0,
      totalLatencyMs: 0,
      isEnabled: true,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only show if there's actual latency
    if (totalLatencySamples == 0) {
      return const SizedBox.shrink();
    }

    final hasHighLatency = totalLatencyMs > 10; // >10ms is noticeable
    final color = hasHighLatency
        ? FluxForgeTheme.warningOrange
        : isEnabled
            ? FluxForgeTheme.accentGreen
            : FluxForgeTheme.textTertiary;

    return Tooltip(
      message: 'Plugin Delay Compensation\n'
          '$totalLatencySamples samples (${totalLatencyMs.toStringAsFixed(2)}ms)\n'
          'Click for details',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timer_outlined, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                '${totalLatencyMs.toStringAsFixed(1)}ms',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PDC DETAIL PANEL
// ═══════════════════════════════════════════════════════════════════════════════

/// Full PDC status panel for lower zone
class PdcDetailPanel extends StatefulWidget {
  final List<int> trackIds;
  final double sampleRate;

  const PdcDetailPanel({
    super.key,
    required this.trackIds,
    this.sampleRate = 48000,
  });

  @override
  State<PdcDetailPanel> createState() => _PdcDetailPanelState();
}

class _PdcDetailPanelState extends State<PdcDetailPanel> {
  int _totalLatency = 0;
  double _totalLatencyMs = 0;
  int _masterLatency = 0;
  Map<int, int> _trackLatencies = {};
  bool _isEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadPdcData();
  }

  void _loadPdcData() {
    try {
      final ffi = NativeFFI.instance;
      if (ffi.isLoaded) {
        setState(() {
          _totalLatency = ffi.pdcGetTotalLatencySamples();
          _totalLatencyMs = ffi.pdcGetTotalLatencyMs();
          _masterLatency = ffi.pdcGetMasterLatency();
          _isEnabled = ffi.pdcIsEnabled();
          _trackLatencies = {
            for (final id in widget.trackIds)
              id: ffi.pdcGetTrackLatency(id),
          };
        });
      }
    } catch (_) { /* ignored */ }
  }

  String _samplesToMs(int samples) {
    final ms = (samples / widget.sampleRate) * 1000;
    return '${ms.toStringAsFixed(2)}ms';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeepest,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.timer_outlined,
                color: _isEnabled
                    ? FluxForgeTheme.accentBlue
                    : FluxForgeTheme.textTertiary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Plugin Delay Compensation',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _isEnabled
                      ? FluxForgeTheme.accentGreen.withValues(alpha: 0.2)
                      : FluxForgeTheme.textTertiary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _isEnabled ? 'ENABLED' : 'DISABLED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _isEnabled
                        ? FluxForgeTheme.accentGreen
                        : FluxForgeTheme.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: _loadPdcData,
                tooltip: 'Refresh',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Total latency card
          _LatencyCard(
            title: 'Total System Latency',
            samples: _totalLatency,
            ms: _totalLatencyMs,
            isHighlighted: true,
          ),

          const SizedBox(height: 12),

          // Master latency
          _LatencyRow(
            label: 'Master Bus',
            samples: _masterLatency,
            msString: _samplesToMs(_masterLatency),
            color: FluxForgeTheme.warningOrange,
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // Track latencies header
          Text(
            'Track Insert Latencies',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textSecondary,
            ),
          ),

          const SizedBox(height: 8),

          // Track latency list
          Expanded(
            child: ListView.builder(
              itemCount: _trackLatencies.length,
              itemBuilder: (context, index) {
                final entry = _trackLatencies.entries.elementAt(index);
                return _LatencyRow(
                  label: 'Track ${entry.key}',
                  samples: entry.value,
                  msString: _samplesToMs(entry.value),
                  color: FluxForgeTheme.accentBlue,
                );
              },
            ),
          ),

          // Footer info
          const SizedBox(height: 8),
          Text(
            'Sample Rate: ${widget.sampleRate.toInt()} Hz',
            style: TextStyle(
              fontSize: 10,
              color: FluxForgeTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _LatencyCard extends StatelessWidget {
  final String title;
  final int samples;
  final double ms;
  final bool isHighlighted;

  const _LatencyCard({
    required this.title,
    required this.samples,
    required this.ms,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasLatency = samples > 0;
    final isHigh = ms > 10; // >10ms

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isHighlighted
            ? (isHigh
                ? FluxForgeTheme.warningOrange.withValues(alpha: 0.15)
                : FluxForgeTheme.accentBlue.withValues(alpha: 0.15))
            : FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHighlighted
              ? (isHigh
                  ? FluxForgeTheme.warningOrange.withValues(alpha: 0.5)
                  : FluxForgeTheme.accentBlue.withValues(alpha: 0.5))
              : FluxForgeTheme.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasLatency ? '${ms.toStringAsFixed(2)} ms' : '0 ms',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isHigh
                        ? FluxForgeTheme.warningOrange
                        : FluxForgeTheme.textPrimary,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$samples',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: FluxForgeTheme.textSecondary,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
              Text(
                'samples',
                style: TextStyle(
                  fontSize: 9,
                  color: FluxForgeTheme.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LatencyRow extends StatelessWidget {
  final String label;
  final int samples;
  final String msString;
  final Color color;

  const _LatencyRow({
    required this.label,
    required this.samples,
    required this.msString,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final hasLatency = samples > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: hasLatency ? color : FluxForgeTheme.textTertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: FluxForgeTheme.textPrimary,
              ),
            ),
          ),
          Text(
            hasLatency ? msString : '-',
            style: TextStyle(
              fontSize: 11,
              color: hasLatency
                  ? FluxForgeTheme.textSecondary
                  : FluxForgeTheme.textTertiary,
              fontFamily: 'JetBrains Mono',
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            child: Text(
              hasLatency ? '$samples' : '-',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                color: hasLatency
                    ? FluxForgeTheme.textTertiary
                    : FluxForgeTheme.textTertiary,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
