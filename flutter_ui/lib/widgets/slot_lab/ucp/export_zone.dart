import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/slot_lab/drc_provider.dart';
import '../../../providers/slot_lab/ail_provider.dart';
import '../../../providers/slot_lab/sam_provider.dart';

/// UCP-8: Export Zone
///
/// Exports session data in multiple formats:
/// - Session Report (markdown summary)
/// - DRC Trace (JSON)
/// - DRC Report (JSON)
/// - SAM State (JSON)
class ExportZone extends StatelessWidget {
  const ExportZone({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 4),
          _buildExportButtons(context),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.download, size: 12, color: Color(0xFF4FC3F7)),
        const SizedBox(width: 4),
        Text(
          'Export',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildExportButtons(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 3,
      children: [
        _exportButton(context, 'DRC Trace', Icons.timeline, _exportDrcTrace),
        _exportButton(context, 'DRC Report', Icons.assessment, _exportDrcReport),
        _exportButton(context, 'AIL Report', Icons.psychology, _exportAilReport),
        _exportButton(context, 'SAM State', Icons.tune, _exportSamState),
        _exportButton(context, 'Manifest', Icons.lock, _exportManifest),
      ],
    );
  }

  Widget _exportButton(
    BuildContext context,
    String label,
    IconData icon,
    void Function(BuildContext) onTap,
  ) {
    return GestureDetector(
      onTap: () => onTap(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF4FC3F7).withOpacity(0.08),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: const Color(0xFF4FC3F7).withOpacity(0.2),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 9, color: const Color(0xFF4FC3F7).withOpacity(0.7)),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                color: const Color(0xFF4FC3F7).withOpacity(0.8),
                fontSize: 8,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _exportDrcTrace(BuildContext context) {
    try {
      final drc = GetIt.instance<DrcProvider>();
      final json = drc.getTraceJson();
      if (json != null && json.isNotEmpty) {
        _copyToClipboard(context, json, 'DRC Trace');
      } else {
        _showMessage(context, 'No DRC trace data available');
      }
    } catch (_) {
      _showMessage(context, 'DRC not available');
    }
  }

  void _exportDrcReport(BuildContext context) {
    try {
      final drc = GetIt.instance<DrcProvider>();
      final json = drc.getReportJson();
      if (json != null && json.isNotEmpty) {
        _copyToClipboard(context, json, 'DRC Report');
      } else {
        _showMessage(context, 'No DRC report available');
      }
    } catch (_) {
      _showMessage(context, 'DRC not available');
    }
  }

  void _exportAilReport(BuildContext context) {
    try {
      final ail = GetIt.instance<AilProvider>();
      if (!ail.hasResults) {
        _showMessage(context, 'No AIL results available');
        return;
      }
      final report = StringBuffer()
        ..writeln('# AIL Report')
        ..writeln()
        ..writeln('Score: ${ail.score.toStringAsFixed(1)}')
        ..writeln('Status: ${ail.status.displayName}')
        ..writeln('Critical: ${ail.criticalCount}')
        ..writeln('Warnings: ${ail.warningCount}')
        ..writeln('Info: ${ail.infoCount}')
        ..writeln()
        ..writeln('## Spectral')
        ..writeln('SCI: ${ail.spectralSci.toStringAsFixed(4)}')
        ..writeln('Clarity: ${ail.spectralClarityScore.toStringAsFixed(4)}')
        ..writeln()
        ..writeln('## Volatility')
        ..writeln('Alignment: ${ail.volatilityAlignmentScore.toStringAsFixed(4)}')
        ..writeln()
        ..writeln('## Domains');
      for (final d in ail.domainResults) {
        report.writeln('- ${d.name}: ${d.score.toStringAsFixed(1)} (risk: ${d.risk.toStringAsFixed(2)})');
      }
      report.writeln();
      report.writeln('## Recommendations');
      for (final r in ail.recommendations) {
        report.writeln('- [${r.level.name}] ${r.title} (impact: ${r.impactScore.toStringAsFixed(0)})');
      }
      _copyToClipboard(context, report.toString(), 'AIL Report');
    } catch (_) {
      _showMessage(context, 'AIL not available');
    }
  }

  void _exportSamState(BuildContext context) {
    try {
      final sam = GetIt.instance<SamProvider>();
      final json = sam.getStateJson();
      if (json != null && json.isNotEmpty) {
        _copyToClipboard(context, json, 'SAM State');
      } else {
        _showMessage(context, 'No SAM state available');
      }
    } catch (_) {
      _showMessage(context, 'SAM not available');
    }
  }

  void _exportManifest(BuildContext context) {
    try {
      final drc = GetIt.instance<DrcProvider>();
      final json = drc.getManifestJson();
      if (json != null && json.isNotEmpty) {
        _copyToClipboard(context, json, 'Manifest');
      } else {
        _showMessage(context, 'No manifest available');
      }
    } catch (_) {
      _showMessage(context, 'DRC not available');
    }
  }

  void _copyToClipboard(BuildContext context, String data, String label) {
    Clipboard.setData(ClipboardData(text: data));
    _showMessage(context, '$label copied to clipboard (${data.length} chars)');
  }

  void _showMessage(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 11)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2A2A4A),
      ),
    );
  }
}
