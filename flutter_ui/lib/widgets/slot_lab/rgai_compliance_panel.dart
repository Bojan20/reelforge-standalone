import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/slot_lab/ail_provider.dart';

/// RGAI™ Compliance Dashboard — powered by AIL (Authoring Intelligence Layer).
///
/// Reads REAL analysis data from AilProvider (Rust FFI §9):
/// - 10 analysis domains with risk scores
/// - AIL Score (0-100) with status level
/// - PBSE simulation pass/fail
/// - Ranked recommendations (critical/warning/info)
/// - Fatigue analysis, voice efficiency, spectral clarity
class RgaiCompliancePanel extends StatefulWidget {
  const RgaiCompliancePanel({super.key});

  @override
  State<RgaiCompliancePanel> createState() => _RgaiCompliancePanelState();
}

class _RgaiCompliancePanelState extends State<RgaiCompliancePanel>
    with SingleTickerProviderStateMixin {
  late final AilProvider _provider;
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<AilProvider>();
    _provider.addListener(_onUpdate);
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _provider.removeListener(_onUpdate);
    _tabCtrl.dispose();
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
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 6),
          _buildTabBar(),
          const SizedBox(height: 6),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _buildTabContent(),
            ),
          ),
          const SizedBox(height: 6),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final statusColor = _statusColor(_provider.status);
    return Row(
      children: [
        const Icon(Icons.shield, size: 14, color: Color(0xFF40C8FF)),
        const SizedBox(width: 4),
        Text(
          'AIL Compliance',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        // AIL Score badge
        if (_provider.hasResults)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              '${_provider.score.toStringAsFixed(0)} ${_provider.status.displayName}',
              style: TextStyle(
                color: statusColor,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (_provider.isRunning)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFFBB33).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'ANALYZING...',
              style: TextStyle(
                color: Color(0xFFFFBB33),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        const Spacer(),
        // PBSE badge
        if (_provider.pbsePassed != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: (_provider.pbsePassed! ? const Color(0xFF4CAF50) : const Color(0xFFFF5252))
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              'PBSE ${_provider.pbsePassed! ? "PASS" : "FAIL"}',
              style: TextStyle(
                color: _provider.pbsePassed! ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(4),
      ),
      child: TabBar(
        controller: _tabCtrl,
        labelColor: const Color(0xFF40C8FF),
        unselectedLabelColor: Colors.white54,
        indicatorColor: const Color(0xFF40C8FF),
        indicatorWeight: 2,
        labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        tabs: [
          const Tab(text: 'DOMAINS'),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('FINDINGS'),
                if (_provider.criticalCount > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5252),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_provider.criticalCount}',
                      style: const TextStyle(fontSize: 7, color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Tab(text: 'FATIGUE'),
          const Tab(text: 'VOICES'),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tabCtrl.index) {
      case 0:
        return _buildDomainsTab();
      case 1:
        return _buildFindingsTab();
      case 2:
        return _buildFatigueTab();
      case 3:
        return _buildVoicesTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TAB: DOMAINS (10 analysis domains with risk bars)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildDomainsTab() {
    if (!_provider.hasResults) {
      return _buildEmptyState('No analysis results.\nRun AIL analysis to see domain scores.', Icons.shield_outlined);
    }

    final domains = _provider.domainResults;
    return ListView.builder(
      itemCount: domains.length,
      itemBuilder: (context, index) {
        final d = domains[index];
        return _buildDomainCard(d);
      },
    );
  }

  Widget _buildDomainCard(AilDomainResult domain) {
    final riskColor = domain.risk > 0.7
        ? const Color(0xFFFF5252)
        : domain.risk > 0.4
            ? const Color(0xFFFFBB33)
            : const Color(0xFF4CAF50);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E36),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  domain.name,
                  style: const TextStyle(
                    color: Color(0xFF40C8FF),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${domain.score.toStringAsFixed(1)}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Score bar
          _buildProgressBar(domain.score / 100.0, const Color(0xFF40C8FF), 'Score'),
          const SizedBox(height: 2),
          // Risk bar
          _buildProgressBar(domain.risk, riskColor, 'Risk'),
        ],
      ),
    );
  }

  Widget _buildProgressBar(double value, Color color, String label) {
    return Row(
      children: [
        SizedBox(
          width: 35,
          child: Text(label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 8)),
        ),
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A4A),
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 28,
          child: Text(
            '${(value * 100).toStringAsFixed(0)}%',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 8),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TAB: FINDINGS (recommendations)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildFindingsTab() {
    final recs = _provider.recommendations;
    if (recs.isEmpty) {
      return _buildEmptyState('No findings.\nRun analysis to check for issues.', Icons.analytics_outlined);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary row
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF12121F),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              _buildCountBadge(_provider.criticalCount, 'CRITICAL', const Color(0xFFFF5252)),
              const SizedBox(width: 8),
              _buildCountBadge(_provider.warningCount, 'WARNING', const Color(0xFFFFBB33)),
              const SizedBox(width: 8),
              _buildCountBadge(_provider.infoCount, 'INFO', const Color(0xFF40C8FF)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // List
        Expanded(
          child: ListView.builder(
            itemCount: recs.length,
            itemBuilder: (context, index) => _buildRecommendationCard(recs[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildCountBadge(int count, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            '$count',
            style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 8)),
      ],
    );
  }

  Widget _buildRecommendationCard(AilRecommendation rec) {
    final levelColor = switch (rec.level) {
      AilRecommendationLevel.critical => const Color(0xFFFF5252),
      AilRecommendationLevel.warning => const Color(0xFFFFBB33),
      AilRecommendationLevel.info => const Color(0xFF40C8FF),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E36),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: levelColor.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: levelColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  rec.level.displayName,
                  style: TextStyle(color: levelColor, fontSize: 8, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  rec.title,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Impact: ${rec.impactScore.toStringAsFixed(1)}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 8),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            rec.description,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 9),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TAB: FATIGUE
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildFatigueTab() {
    final fatigue = _provider.fatigueResult;
    if (fatigue == null) {
      return _buildEmptyState('No fatigue analysis.\nRun AIL analysis first.', Icons.battery_alert_outlined);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Fatigue Analysis'),
          const SizedBox(height: 8),
          _buildStatCard('Fatigue Score', fatigue.fatigueScore, 1.0,
              fatigue.fatigueScore > 0.7 ? const Color(0xFFFF5252) : const Color(0xFF4CAF50)),
          _buildStatCard('Peak Frequency', fatigue.peakFrequency, 20000.0, const Color(0xFF40C8FF)),
          _buildStatCard('Harmonic Density', fatigue.harmonicDensity, 1.0, const Color(0xFF7C4DFF)),
          _buildStatCard('Temporal Density', fatigue.temporalDensity, 1.0, const Color(0xFFFFBB33)),
          _buildStatCard('Recovery Factor', fatigue.recoveryFactor, 1.0, const Color(0xFF4CAF50)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E36),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, size: 14, color: Color(0xFFFFBB33)),
                const SizedBox(width: 6),
                Text(
                  'Risk Level: ${fatigue.riskLevel}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Spectral clarity
          _buildSectionTitle('Spectral Analysis'),
          const SizedBox(height: 4),
          _buildStatCard('Spectral Clarity', _provider.spectralClarityScore, 100.0, const Color(0xFF40C8FF)),
          _buildStatCard('SCI Index', _provider.spectralSci, 1.0, const Color(0xFF7C4DFF)),
          _buildStatCard('Volatility Alignment', _provider.volatilityAlignmentScore, 100.0, const Color(0xFFFFBB33)),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, double value, double max, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 9)),
          ),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A4A),
                borderRadius: BorderRadius.circular(3),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: max > 0 ? (value / max).clamp(0.0, 1.0) : 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 40,
            child: Text(
              value.toStringAsFixed(2),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 9),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TAB: VOICES
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildVoicesTab() {
    final ve = _provider.voiceEfficiency;
    if (ve == null) {
      return _buildEmptyState('No voice efficiency data.\nRun AIL analysis first.', Icons.graphic_eq_outlined);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Voice Efficiency'),
          const SizedBox(height: 8),
          // Utilization gauge
          Center(
            child: SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(
                      value: ve.utilizationPct / 100.0,
                      strokeWidth: 8,
                      backgroundColor: const Color(0xFF2A2A4A),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        ve.utilizationPct > 90
                            ? const Color(0xFFFF5252)
                            : ve.utilizationPct > 70
                                ? const Color(0xFFFFBB33)
                                : const Color(0xFF4CAF50),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${ve.utilizationPct.toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Utilization',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildKeyValue('Avg Voices', ve.avgVoices.toStringAsFixed(1)),
          _buildKeyValue('Peak Voices', '${ve.peakVoices}'),
          _buildKeyValue('Budget Cap', '${ve.budgetCap}'),
          _buildKeyValue('Efficiency', ve.efficiencyScore.toStringAsFixed(2)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _provider.isRunning ? null : () => _provider.runAnalysis(),
            icon: const Icon(Icons.play_arrow, size: 14),
            label: Text(
              _provider.hasResults ? 'Re-analyze' : 'Run Analysis',
              style: const TextStyle(fontSize: 10),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF40C8FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
        ),
        if (_provider.hasResults) ...[
          const SizedBox(width: 6),
          SizedBox(
            width: 80,
            child: OutlinedButton(
              onPressed: () => _provider.reset(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white54,
                side: const BorderSide(color: Color(0xFF3A3A5C)),
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: const Text('Reset', style: TextStyle(fontSize: 10)),
            ),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.8),
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildKeyValue(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(key,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 9)),
          ),
        ],
      ),
    );
  }

  Color _statusColor(AilStatusLevel status) {
    return switch (status) {
      AilStatusLevel.excellent => const Color(0xFF4CAF50),
      AilStatusLevel.good => const Color(0xFF8BC34A),
      AilStatusLevel.fair => const Color(0xFFFFBB33),
      AilStatusLevel.poor => const Color(0xFFFF8A65),
      AilStatusLevel.critical => const Color(0xFFFF5252),
    };
  }
}
