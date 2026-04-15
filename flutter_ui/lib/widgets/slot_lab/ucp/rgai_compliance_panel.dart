import 'package:flutter/material.dart';
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

  Widget _flaggedAssetRow(RgarAssetAnalysis asset) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            asset.riskRating == AddictionRiskRating.prohibited
                ? Icons.dangerous
                : Icons.warning_amber,
            color: Color(asset.riskRating.colorValue),
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
                  Text(asset.flags.first,
                      style: const TextStyle(color: Colors.white38, fontSize: 9),
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Text(
            asset.compositeRisk.toStringAsFixed(2),
            style: TextStyle(color: Color(asset.riskRating.colorValue), fontSize: 9),
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
