import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/slot_lab/ail_provider.dart';

/// AIL Score Panel — shows AIL Score, domain scores, recommendations, fatigue/voice/spectral.
class AilScorePanel extends StatefulWidget {
  const AilScorePanel({super.key});

  @override
  State<AilScorePanel> createState() => _AilScorePanelState();
}

class _AilScorePanelState extends State<AilScorePanel> {
  late final AilProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<AilProvider>();
    _provider.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _provider.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 6),
          if (!_provider.hasResults)
            _buildEmptyState()
          else ...[
            _buildScoreCard(),
            const SizedBox(height: 6),
            _buildDomainList(),
            const SizedBox(height: 6),
            _buildMetricsRow(),
            const SizedBox(height: 6),
            _buildRecommendations(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.psychology, size: 14, color: Color(0xFFFFAB40)),
        const SizedBox(width: 4),
        Text(
          'AIL Advisory',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (_provider.isRunning)
          SizedBox(
            width: 12, height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation(Colors.white.withOpacity(0.5)),
            ),
          )
        else
          _buildRunButton(),
      ],
    );
  }

  Widget _buildRunButton() {
    return GestureDetector(
      onTap: () => _provider.runAnalysis(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFFAB40).withOpacity(0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: const Color(0xFFFFAB40).withOpacity(0.3), width: 0.5),
        ),
        child: const Text(
          'Analyze',
          style: TextStyle(color: Color(0xFFFFAB40), fontSize: 9, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'No analysis results. Click Analyze to start.',
        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
      ),
    );
  }

  Widget _buildScoreCard() {
    final color = _statusColor(_provider.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        children: [
          Text(
            '${_provider.score.toStringAsFixed(0)}',
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _provider.status.displayName,
                style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600),
              ),
              Text(
                '${_provider.simulationSpins} spins analyzed',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 8),
              ),
            ],
          ),
          const Spacer(),
          _chip(
            '${_provider.criticalCount}C ${_provider.warningCount}W ${_provider.infoCount}I',
            Colors.white.withOpacity(0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildDomainList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final dr in _provider.domainResults)
          _buildDomainRow(dr),
      ],
    );
  }

  Widget _buildDomainRow(AilDomainResult dr) {
    final color = _riskColor(dr.risk);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Container(
            width: 3, height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 110,
            child: Text(
              dr.name,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 9),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          Text(
            '${dr.score.toStringAsFixed(0)}',
            style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            height: 3,
            child: LinearProgressIndicator(
              value: (dr.score / 100.0).clamp(0.0, 1.0),
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsRow() {
    final fat = _provider.fatigueResult;
    final voice = _provider.voiceEfficiency;
    return Row(
      children: [
        if (fat != null) ...[
          _metricChip('Fatigue', fat.riskLevel, _fatigueColor(fat.riskLevel)),
          const SizedBox(width: 4),
        ],
        _metricChip('Spectral', '${_provider.spectralClarityScore.toStringAsFixed(0)}%',
            _riskColor(1.0 - _provider.spectralClarityScore / 100.0)),
        const SizedBox(width: 4),
        if (voice != null)
          _metricChip('Voice', '${voice.utilizationPct.toStringAsFixed(0)}%',
              voice.utilizationPct > 90 ? const Color(0xFFEF5350) : const Color(0xFF66BB6A)),
        const SizedBox(width: 4),
        _metricChip('Volatility', '${_provider.volatilityAlignmentScore.toStringAsFixed(0)}',
            _riskColor(1.0 - _provider.volatilityAlignmentScore / 100.0)),
      ],
    );
  }

  Widget _buildRecommendations() {
    if (_provider.recommendations.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recommendations',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        for (final rec in _provider.recommendations.take(5))
          _buildRecommendationRow(rec),
      ],
    );
  }

  Widget _buildRecommendationRow(AilRecommendation rec) {
    final color = _recLevelColor(rec.level);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              rec.title,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 9),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${rec.impactScore.toStringAsFixed(0)}',
            style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _metricChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w500),
      ),
    );
  }

  Color _statusColor(AilStatusLevel status) {
    switch (status) {
      case AilStatusLevel.excellent: return const Color(0xFF66BB6A);
      case AilStatusLevel.good: return const Color(0xFF4FC3F7);
      case AilStatusLevel.fair: return const Color(0xFFFFB74D);
      case AilStatusLevel.poor: return const Color(0xFFFF8A65);
      case AilStatusLevel.critical: return const Color(0xFFEF5350);
    }
  }

  Color _riskColor(double risk) {
    if (risk >= 0.7) return const Color(0xFFEF5350);
    if (risk >= 0.4) return const Color(0xFFFFB74D);
    if (risk >= 0.2) return const Color(0xFF4FC3F7);
    return const Color(0xFF66BB6A);
  }

  Color _fatigueColor(String riskLevel) {
    switch (riskLevel) {
      case 'CRITICAL': return const Color(0xFFEF5350);
      case 'HIGH': return const Color(0xFFFF8A65);
      case 'MODERATE': return const Color(0xFFFFB74D);
      default: return const Color(0xFF66BB6A);
    }
  }

  Color _recLevelColor(AilRecommendationLevel level) {
    switch (level) {
      case AilRecommendationLevel.critical: return const Color(0xFFEF5350);
      case AilRecommendationLevel.warning: return const Color(0xFFFFB74D);
      case AilRecommendationLevel.info: return const Color(0xFF4FC3F7);
    }
  }
}
