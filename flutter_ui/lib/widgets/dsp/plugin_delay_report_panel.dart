/// Plugin Delay Compensation Report Panel
///
/// Summary panel showing PDC (Plugin Delay Compensation) contributions
/// per plugin across all tracks. Helps identify latency-heavy plugins.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/mixer_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// PDC entry for a single plugin
class PdcEntry {
  final String trackName;
  final String trackId;
  final String pluginName;
  final int slotIndex;
  final int pdcSamples;
  final double pdcMs;

  const PdcEntry({
    required this.trackName,
    required this.trackId,
    required this.pluginName,
    required this.slotIndex,
    required this.pdcSamples,
    required this.pdcMs,
  });
}

/// Plugin Delay Report Panel
///
/// Shows a summary of PDC contributions across the project.
class PluginDelayReportPanel extends StatelessWidget {
  final double sampleRate;

  const PluginDelayReportPanel({
    super.key,
    this.sampleRate = 48000.0,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<MixerProvider>(
      builder: (context, mixer, _) {
        final entries = _collectPdcEntries(mixer);
        final totalPdc = entries.fold<int>(0, (sum, e) => sum + e.pdcSamples);
        final totalMs = _samplesToMs(totalPdc);

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
              // Header
              _buildHeader(context, entries, totalPdc, totalMs),
              const SizedBox(height: 12),

              // Content
              if (entries.isEmpty)
                _buildEmptyState()
              else
                Expanded(
                  child: _buildEntryList(entries),
                ),

              // Footer with total
              if (entries.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildFooter(totalPdc, totalMs),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    List<PdcEntry> entries,
    int totalPdc,
    double totalMs,
  ) {
    return Row(
      children: [
        const Icon(
          Icons.timer_outlined,
          size: 16,
          color: FluxForgeTheme.accentOrange,
        ),
        const SizedBox(width: 8),
        const Text(
          'PLUGIN DELAY COMPENSATION',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        // Export button
        Tooltip(
          message: 'Copy report to clipboard',
          child: InkWell(
            onTap: () => _copyReport(context, entries, totalPdc, totalMs),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: const Icon(
                Icons.content_copy,
                size: 14,
                color: FluxForgeTheme.textTertiary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return const Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 32,
              color: FluxForgeTheme.accentGreen,
            ),
            SizedBox(height: 8),
            Text(
              'No plugin delay detected',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'All plugins have zero latency',
              style: TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryList(List<PdcEntry> entries) {
    // Sort by PDC samples (highest first)
    final sorted = List<PdcEntry>.from(entries)
      ..sort((a, b) => b.pdcSamples.compareTo(a.pdcSamples));

    return ListView.separated(
      itemCount: sorted.length,
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        color: FluxForgeTheme.borderSubtle,
      ),
      itemBuilder: (context, index) {
        final entry = sorted[index];
        return _buildEntryRow(entry, index);
      },
    );
  }

  Widget _buildEntryRow(PdcEntry entry, int index) {
    // Color code by severity
    final Color severityColor;
    if (entry.pdcMs > 10) {
      severityColor = FluxForgeTheme.accentRed;
    } else if (entry.pdcMs > 5) {
      severityColor = FluxForgeTheme.accentOrange;
    } else {
      severityColor = FluxForgeTheme.accentGreen;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Rank indicator
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: severityColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: severityColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Plugin info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.pluginName,
                  style: const TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${entry.trackName} • Slot ${entry.slotIndex + 1}',
                  style: const TextStyle(
                    color: FluxForgeTheme.textTertiary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),

          // PDC values
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.pdcSamples} smp',
                style: TextStyle(
                  color: severityColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                '${entry.pdcMs.toStringAsFixed(2)} ms',
                style: const TextStyle(
                  color: FluxForgeTheme.textTertiary,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(int totalPdc, double totalMs) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Text(
            'TOTAL ACCUMULATED PDC',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Text(
            '$totalPdc samples',
            style: const TextStyle(
              color: FluxForgeTheme.accentOrange,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '(${totalMs.toStringAsFixed(2)} ms)',
            style: const TextStyle(
              color: FluxForgeTheme.textTertiary,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  List<PdcEntry> _collectPdcEntries(MixerProvider mixer) {
    final entries = <PdcEntry>[];

    for (final channel in mixer.channels) {
      for (int i = 0; i < channel.inserts.length; i++) {
        final insert = channel.inserts[i];
        if (insert.isEmpty) continue;

        // Get PDC from insert (if available)
        final pdcSamples = insert.pdcSamples;
        if (pdcSamples <= 0) continue;

        entries.add(PdcEntry(
          trackName: channel.name,
          trackId: channel.id,
          pluginName: insert.name,
          slotIndex: i,
          pdcSamples: pdcSamples,
          pdcMs: _samplesToMs(pdcSamples),
        ));
      }
    }

    return entries;
  }

  double _samplesToMs(int samples) {
    return (samples / sampleRate) * 1000.0;
  }

  void _copyReport(
    BuildContext context,
    List<PdcEntry> entries,
    int totalPdc,
    double totalMs,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('Plugin Delay Compensation Report');
    buffer.writeln('================================');
    buffer.writeln('Sample Rate: ${sampleRate.toInt()} Hz');
    buffer.writeln('');

    if (entries.isEmpty) {
      buffer.writeln('No plugins with latency detected.');
    } else {
      // Sort by PDC
      final sorted = List<PdcEntry>.from(entries)
        ..sort((a, b) => b.pdcSamples.compareTo(a.pdcSamples));

      buffer.writeln('Plugins with Latency:');
      buffer.writeln('');

      for (int i = 0; i < sorted.length; i++) {
        final entry = sorted[i];
        buffer.writeln(
            '${i + 1}. ${entry.pluginName} (${entry.trackName}, Slot ${entry.slotIndex + 1})');
        buffer.writeln(
            '   ${entry.pdcSamples} samples (${entry.pdcMs.toStringAsFixed(2)} ms)');
      }

      buffer.writeln('');
      buffer.writeln('Total Accumulated PDC: $totalPdc samples (${totalMs.toStringAsFixed(2)} ms)');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PDC report copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
