import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/rgai_ffi_provider.dart';

/// RGAI™ Compliance Dashboard — Responsible Gaming Audio Intelligence.
///
/// Real-time compliance monitoring powered by rf-rgai Rust engine via FFI.
/// Shows jurisdiction status, metric violations, export gate, remediation.
class RgaiCompliancePanel extends StatefulWidget {
  const RgaiCompliancePanel({super.key});

  @override
  State<RgaiCompliancePanel> createState() => _RgaiCompliancePanelState();
}

class _RgaiCompliancePanelState extends State<RgaiCompliancePanel>
    with SingleTickerProviderStateMixin {
  late final RgaiFfiProvider _provider;
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<RgaiFfiProvider>();
    _provider.addListener(_onUpdate);
    _tabCtrl = TabController(length: 4, vsync: this);
    if (!_provider.initialized) {
      _provider.init();
    }
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
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final gateColor = _provider.exportApproved
        ? const Color(0xFF4CAF50)
        : (_provider.lastExportGate != null
            ? const Color(0xFFFF5252)
            : Colors.white.withValues(alpha: 0.5));

    return Row(
      children: [
        const Icon(Icons.shield, size: 14, color: Color(0xFF40C8FF)),
        const SizedBox(width: 4),
        Text(
          'RGAI™ Compliance',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: gateColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: gateColor.withValues(alpha: 0.4)),
          ),
          child: Text(
            _provider.exportApproved
                ? 'APPROVED'
                : (_provider.lastExportGate != null ? 'BLOCKED' : 'NOT CHECKED'),
            style: TextStyle(
              color: gateColor,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const Spacer(),
        _buildJurisdictionChips(),
      ],
    );
  }

  Widget _buildJurisdictionChips() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _provider.activeJurisdictions.map((code) {
        return Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A4A),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            code,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
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
        tabs: const [
          Tab(text: 'OVERVIEW'),
          Tab(text: 'METRICS'),
          Tab(text: 'EXPORT GATE'),
          Tab(text: 'REMEDIATION'),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tabCtrl.index) {
      case 0:
        return _buildOverviewTab();
      case 1:
        return _buildMetricsTab();
      case 2:
        return _buildExportGateTab();
      case 3:
        return _buildRemediationTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TAB: OVERVIEW
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildOverviewTab() {
    if (!_provider.initialized) {
      return _buildEmptyState('RGAI not initialized', Icons.shield_outlined);
    }

    final jurisdictions = _provider.availableJurisdictions;
    return ListView.builder(
      itemCount: jurisdictions.length,
      itemBuilder: (context, index) {
        final j = jurisdictions[index];
        return _buildJurisdictionCard(j);
      },
    );
  }

  Widget _buildJurisdictionCard(Map<String, dynamic> jurisdiction) {
    final code = jurisdiction['code'] as String? ?? '??';
    final label = jurisdiction['label'] as String? ?? code;
    final maxArousal = (jurisdiction['max_arousal'] as num?)?.toDouble() ?? 1.0;
    final maxNearMiss = (jurisdiction['max_near_miss_deception'] as num?)?.toDouble() ?? 1.0;
    final maxLossDisguise = (jurisdiction['max_loss_disguise'] as num?)?.toDouble() ?? 1.0;
    final maxTemporal = (jurisdiction['max_temporal_distortion'] as num?)?.toDouble() ?? 1.0;

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
              Text(code,
                  style: const TextStyle(
                    color: Color(0xFF40C8FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                  )),
            ],
          ),
          const SizedBox(height: 6),
          _buildMetricBar('Arousal', maxArousal, const Color(0xFFFF6B6B)),
          _buildMetricBar('Near-Miss', maxNearMiss, const Color(0xFFFFBB33)),
          _buildMetricBar('Loss-Disguise', maxLossDisguise, const Color(0xFFFF8A65)),
          _buildMetricBar('Temporal', maxTemporal, const Color(0xFF7C4DFF)),
        ],
      ),
    );
  }

  Widget _buildMetricBar(String label, double maxValue, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 9)),
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
                widthFactor: maxValue.clamp(0.0, 1.0),
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
            width: 30,
            child: Text(
              maxValue.toStringAsFixed(2),
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 8),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TAB: METRICS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildMetricsTab() {
    final analysis = _provider.lastAssetAnalysis;
    if (analysis == null) {
      return _buildEmptyState(
        'No asset analysis yet.\nSelect an asset to analyze.',
        Icons.analytics_outlined,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Asset Analysis Results'),
          const SizedBox(height: 4),
          ...analysis.entries.map((e) => _buildKeyValue(e.key, '${e.value}')),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TAB: EXPORT GATE
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildExportGateTab() {
    final gate = _provider.lastExportGate;
    if (gate == null) {
      return _buildEmptyState(
        'Export gate not checked.\nRun a session analysis first.',
        Icons.security_outlined,
      );
    }

    final decision = gate['decision'] as String? ?? 'Unknown';
    final isApproved = decision == 'Approved';
    final criticals = (gate['critical_count'] as int?) ?? 0;
    final majors = (gate['major_count'] as int?) ?? 0;
    final reasons = (gate['reasons'] as List?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isApproved ? const Color(0xFF4CAF50) : const Color(0xFFFF5252))
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: (isApproved ? const Color(0xFF4CAF50) : const Color(0xFFFF5252))
                    .withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  isApproved ? Icons.check_circle : Icons.cancel,
                  color: isApproved ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                  size: 32,
                ),
                const SizedBox(height: 4),
                Text(
                  decision,
                  style: TextStyle(
                    color: isApproved ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!isApproved)
                  Text(
                    '$criticals critical, $majors major violations',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6), fontSize: 10),
                  ),
              ],
            ),
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildSectionTitle('Blocking Reasons'),
            ...reasons.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(color: Color(0xFFFF5252), fontSize: 10)),
                      Expanded(
                          child: Text('$r',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 10))),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TAB: REMEDIATION
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildRemediationTab() {
    final plan = _provider.lastRemediation;
    if (plan == null) {
      return _buildEmptyState(
        'No remediation plan.\nAnalyze a non-compliant asset first.',
        Icons.build_outlined,
      );
    }

    final status = plan['status'] as String? ?? '';
    if (status == 'compliant') {
      return _buildEmptyState('Asset is compliant. No fixes needed.', Icons.check_circle_outline);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Remediation Plan'),
          const SizedBox(height: 4),
          ...plan.entries.map((e) => _buildKeyValue(e.key, '${e.value}')),
        ],
      ),
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
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              key,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}
