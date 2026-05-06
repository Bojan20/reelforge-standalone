import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/slot_lab/rgai_provider.dart';
import '../../../models/aurexis_jurisdiction.dart';

/// UCP-11: RGAI™ Compliance Panel — Responsible Gaming Audio Intelligence
///
/// Displays RGAR report: compliance score, asset analysis, risk distribution,
/// regulatory flags, and auto-remediation suggestions.
class RgaiCompliancePanel extends StatefulWidget {
  const RgaiCompliancePanel({super.key});

  @override
  State<RgaiCompliancePanel> createState() => _RgaiCompliancePanelState();
}

class _RgaiCompliancePanelState extends State<RgaiCompliancePanel> {
  RgaiProvider? _provider;

  @override
  void initState() {
    super.initState();
    try {
      _provider = GetIt.instance<RgaiProvider>();
      _provider?.addListener(_onUpdate);
    } catch (_) {}
  }

  @override
  void dispose() {
    _provider?.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = _provider;
    if (p == null) {
      return const Center(
        child: Text('RGAI not available', style: TextStyle(color: Colors.grey)),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header ──────────────────────────────────────────────
          Row(
            children: [
              Icon(
                Icons.verified_user,
                color: p.isCompliant ? const Color(0xFF44CC44) : const Color(0xFFCC4444),
                size: 16,
              ),
              const SizedBox(width: 6),
              const Text(
                'RGAI',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              _jurisdictionChip(p),
              const SizedBox(width: 6),
              _safeModeToggle(p),
              const SizedBox(width: 6),
              // 3.4.5 — Manifest export button
              if (p.hasReport) _exportButton(p),
            ],
          ),
          const SizedBox(height: 8),

          if (!p.hasReport) ...[
            _buildEmpty(),
          ] else ...[
            _buildReport(p),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.shield_outlined, color: Colors.white24, size: 32),
            const SizedBox(height: 8),
            const Text(
              'No RGAR Analysis Yet',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'Assign audio assets to stages,\nthen run compliance analysis',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReport(RgaiProvider p) {
    final report = p.report!;
    final summary = report.summary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Compliance Score ─────────────────────────────────────
        _complianceScoreBar(summary),
        const SizedBox(height: 10),

        // ─── Risk Distribution ───────────────────────────────────
        _sectionLabel('RISK DISTRIBUTION'),
        const SizedBox(height: 4),
        ...AddictionRiskRating.values.where((r) => (summary.ratingDistribution[r] ?? 0) > 0).map(
              (rating) => _ratingRow(rating, summary.ratingDistribution[rating] ?? 0, summary.totalAssets),
            ),
        const SizedBox(height: 8),

        // ─── Key Metrics ─────────────────────────────────────────
        _sectionLabel('KEY METRICS'),
        const SizedBox(height: 4),
        _metricBar('Avg Arousal', summary.avgArousal, const Color(0xFFFF6633)),
        _metricBar('Max Near-Miss', summary.maxNearMissDeception, const Color(0xFFDD8822)),
        _metricBar('Max Loss-Disguise', summary.maxLossDisguise, const Color(0xFFCC4444)),
        const SizedBox(height: 8),

        // ─── Flagged Assets ──────────────────────────────────────
        if (summary.flaggedAssets > 0 || summary.prohibitedAssets > 0) ...[
          _sectionLabel('FLAGGED ASSETS (${summary.flaggedAssets + summary.prohibitedAssets})'),
          const SizedBox(height: 4),
          ...report.assets
              .where((a) => a.riskRating.requiresRemediation)
              .take(5)
              .map((a) => _flaggedAssetRow(a)),
          const SizedBox(height: 8),
        ],

        // ─── Stats ───────────────────────────────────────────────
        Row(
          children: [
            _stat('Assets', '${summary.totalAssets}'),
            _stat('Passed', '${summary.passedAssets}'),
            _stat('Flagged', '${summary.flaggedAssets}'),
            _stat('Score', '${summary.overallComplianceScore.toStringAsFixed(0)}%'),
          ],
        ),
      ],
    );
  }

  Widget _complianceScoreBar(RgarSummary summary) {
    final score = summary.overallComplianceScore;
    final color = score >= 90
        ? const Color(0xFF44CC44)
        : score >= 70
            ? const Color(0xFFDDAA22)
            : const Color(0xFFCC4444);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${score.toStringAsFixed(0)}%',
              style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Text(
              summary.isCompliant ? 'COMPLIANT' : 'NON-COMPLIANT',
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }

  Widget _jurisdictionChip(RgaiProvider p) {
    return PopupMenuButton<AurexisJurisdiction>(
      offset: const Offset(0, 20),
      color: const Color(0xFF2A2A3A),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(p.jurisdiction.code,
                style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.w500)),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, color: Colors.white38, size: 12),
          ],
        ),
      ),
      itemBuilder: (_) => AurexisJurisdiction.values
          .where((j) => j != AurexisJurisdiction.none)
          .map((j) => PopupMenuItem(
                value: j,
                child: Text(j.label, style: const TextStyle(fontSize: 11)),
              ))
          .toList(),
      onSelected: p.setJurisdiction,
    );
  }

  Widget _safeModeToggle(RgaiProvider p) {
    return GestureDetector(
      onTap: () => p.setSafeModeActive(!p.safeModeActive),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: p.safeModeActive ? const Color(0xFF44CC44).withValues(alpha: 0.2) : Colors.white10,
          borderRadius: BorderRadius.circular(4),
          border: p.safeModeActive
              ? Border.all(color: const Color(0xFF44CC44).withValues(alpha: 0.4))
              : null,
        ),
        child: Text(
          'SAFE',
          style: TextStyle(
            color: p.safeModeActive ? const Color(0xFF44CC44) : Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      );

  Widget _ratingRow(AddictionRiskRating rating, int count, int total) {
    final pct = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Color(rating.colorValue),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 70,
            child: Text(rating.displayName,
                style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ),
          Expanded(
            child: SizedBox(
              height: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation(Color(rating.colorValue)),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 24,
            child: Text('$count', textAlign: TextAlign.right,
                style: TextStyle(color: Color(rating.colorValue), fontSize: 9)),
          ),
        ],
      ),
    );
  }

  Widget _metricBar(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ),
          Expanded(
            child: SizedBox(
              height: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: value.clamp(0.0, 1.0),
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              (value * 100).toStringAsFixed(0),
              textAlign: TextAlign.right,
              style: TextStyle(color: color, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  // ── 3.4.2: Enhanced flagged asset row with inline violation tooltip + remediation ──
  Widget _flaggedAssetRow(RgarAssetAnalysis asset) {
    final ratingColor = Color(asset.riskRating.colorValue);
    // Build tooltip text: all flags + remediation suggestions
    final tooltipLines = <String>[];
    if (asset.flags.isNotEmpty) {
      tooltipLines.add('Violations:');
      for (final f in asset.flags) {
        tooltipLines.add('  • $f');
      }
    }
    if (asset.remediations.isNotEmpty) {
      tooltipLines.add('');
      tooltipLines.add('Remediation:');
      for (final r in asset.remediations) {
        tooltipLines.add('  ${r.parameter}: ${r.currentValue} → ${r.suggestedValue}');
        tooltipLines.add('  (${r.reason})');
      }
    }
    final tooltipText = tooltipLines.join('\n');

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: tooltipText.isNotEmpty ? tooltipText : asset.assetName,
        preferBelow: false,
        textStyle: const TextStyle(color: Colors.white70, fontSize: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(
              asset.riskRating == AddictionRiskRating.prohibited
                  ? Icons.dangerous
                  : Icons.warning_amber,
              color: ratingColor,
              size: 12,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(asset.assetName,
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                      overflow: TextOverflow.ellipsis),
                  if (asset.flags.isNotEmpty)
                    Text(
                      asset.flags.join(', '),
                      style: const TextStyle(color: Colors.white38, fontSize: 9),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                ],
              ),
            ),
            // Risk score
            Text(
              asset.compositeRisk.toStringAsFixed(2),
              style: TextStyle(color: ratingColor, fontSize: 9),
            ),
            // 3.4.2 one-click auto-fix: show if remediations available
            if (asset.remediations.isNotEmpty) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _showRemediationSheet(asset),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: ratingColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: ratingColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'FIX ▶',
                    style: TextStyle(color: ratingColor, fontSize: 8, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showRemediationSheet(RgarAssetAnalysis asset) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_fix_high, color: Color(asset.riskRating.colorValue), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Remediation — ${asset.assetName}',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${asset.flags.length} violation${asset.flags.length != 1 ? 's' : ''} · ${asset.remediations.length} suggestion${asset.remediations.length != 1 ? 's' : ''}',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
            const SizedBox(height: 12),
            // Violations list
            if (asset.flags.isNotEmpty) ...[
              const Text('VIOLATIONS', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
              const SizedBox(height: 4),
              ...asset.flags.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Color(0xFFCC4444), size: 11),
                      const SizedBox(width: 6),
                      Expanded(child: Text(f, style: const TextStyle(color: Colors.white70, fontSize: 10))),
                    ]),
                  )),
              const SizedBox(height: 10),
            ],
            // Remediation suggestions
            const Text('SUGGESTIONS', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            ...asset.remediations.map((r) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(r.parameter, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text(r.currentValue, style: const TextStyle(color: Colors.white38, fontSize: 9, decoration: TextDecoration.lineThrough)),
                        const Icon(Icons.arrow_forward, color: Colors.white24, size: 10),
                        Text(r.suggestedValue, style: const TextStyle(color: Color(0xFF44CC88), fontSize: 9, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 2),
                      Text(r.reason, style: const TextStyle(color: Colors.white54, fontSize: 9)),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CLOSE', style: TextStyle(color: Colors.white54, fontSize: 10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 3.4.5: Export compliance manifest ──
  Widget _exportButton(RgaiProvider p) {
    return GestureDetector(
      onTap: () => _exportManifest(p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.download, color: Colors.white38, size: 10),
            SizedBox(width: 2),
            Text('JSON', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  void _exportManifest(RgaiProvider p) {
    final json = p.exportJsonAudit();
    // Copy to clipboard + show confirmation snackbar
    Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E2A1E),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: Color(0xFF44CC44), width: 0.5),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('RGAR Manifest Copied',
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              '${p.jurisdiction.label} · ${json.length} chars · ${DateTime.now().toIso8601String().substring(0, 16)}',
              style: const TextStyle(color: Colors.white54, fontSize: 9),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: const Color(0xFF44CC44),
          onPressed: () => _showManifestDialog(json),
        ),
      ),
    );
  }

  void _showManifestDialog(String json) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12121E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('RGAR Manifest', style: TextStyle(color: Colors.white, fontSize: 13)),
        content: SizedBox(
          width: 480,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(
              json,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE', style: TextStyle(color: Colors.white38, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
          ],
        ),
      );
}
