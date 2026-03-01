import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/slot_lab/sss_provider.dart';

/// SSS Panel — Scale & Stability Suite (MASTER_SPEC §16).
///
/// Multi-project isolation, config diff, auto regression, burn test.
class SssPanel extends StatefulWidget {
  const SssPanel({super.key});

  @override
  State<SssPanel> createState() => _SssPanelState();
}

class _SssPanelState extends State<SssPanel> with SingleTickerProviderStateMixin {
  late final SssProvider _provider;
  late final TabController _tabCtrl;
  final _projectNameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<SssProvider>();
    _provider.addListener(_onUpdate);
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _provider.removeListener(_onUpdate);
    _tabCtrl.dispose();
    _projectNameCtrl.dispose();
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
    return Row(
      children: [
        const Icon(Icons.shield_outlined, size: 14, color: Color(0xFF4CAF50)),
        const SizedBox(width: 4),
        Text(
          'Scale & Stability Suite',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (_provider.projects.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${_provider.projects.length} projects',
              style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 9, fontWeight: FontWeight.w500),
            ),
          ),
      ],
    );
  }

  Widget _buildTabBar() {
    return SizedBox(
      height: 24,
      child: TabBar(
        controller: _tabCtrl,
        onTap: (_) => setState(() {}),
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorColor: const Color(0xFF4CAF50),
        indicatorWeight: 2,
        labelPadding: const EdgeInsets.symmetric(horizontal: 10),
        labelColor: const Color(0xFF4CAF50),
        unselectedLabelColor: Colors.white54,
        labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'Projects'),
          Tab(text: 'Config Diff'),
          Tab(text: 'Regression'),
          Tab(text: 'Burn Test'),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    return switch (_tabCtrl.index) {
      0 => _buildProjectsTab(),
      1 => _buildDiffTab(),
      2 => _buildRegressionTab(),
      3 => _buildBurnTestTab(),
      _ => const SizedBox.shrink(),
    };
  }

  // ─── Projects Tab ───

  Widget _buildProjectsTab() {
    return Column(
      key: const ValueKey('projects'),
      children: [
        _buildCreateProjectRow(),
        const SizedBox(height: 6),
        if (_provider.activeProject != null) ...[
          _buildActiveProjectCard(),
          const SizedBox(height: 6),
        ],
        Expanded(child: _buildProjectList()),
      ],
    );
  }

  Widget _buildCreateProjectRow() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 24,
            child: TextField(
              controller: _projectNameCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 10),
              decoration: InputDecoration(
                hintText: 'New project name...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                filled: true,
                fillColor: const Color(0xFF2A2A3E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _buildActionButton(
          icon: Icons.add,
          label: 'Create',
          color: const Color(0xFF4CAF50),
          onTap: () {
            if (_projectNameCtrl.text.isNotEmpty) {
              _provider.createProject(_projectNameCtrl.text);
              _projectNameCtrl.clear();
            }
          },
        ),
      ],
    );
  }

  Widget _buildActiveProjectCard() {
    final p = _provider.activeProject!;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_open, size: 14, color: Color(0xFF4CAF50)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                Text(
                  'Hash: ${p.configHash.length > 12 ? p.configHash.substring(0, 12) : p.configHash}... ${p.certified ? "• Certified" : ""}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 8),
                ),
              ],
            ),
          ),
          if (p.certified)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text('CERTIFIED', style: TextStyle(color: Color(0xFF4CAF50), fontSize: 7, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  Widget _buildProjectList() {
    if (_provider.projects.isEmpty) {
      return Center(
        child: Text(
          'No isolated projects — create one above',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
        ),
      );
    }
    return ListView.builder(
      itemCount: _provider.projects.length,
      itemBuilder: (_, i) {
        final p = _provider.projects[i];
        final isActive = _provider.activeProject?.id == p.id;
        return Container(
          margin: const EdgeInsets.only(bottom: 2),
          child: ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -4),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: Icon(Icons.folder, size: 14, color: isActive ? const Color(0xFF4CAF50) : Colors.white30),
            title: Text(p.name, style: TextStyle(color: Colors.white.withValues(alpha: isActive ? 0.9 : 0.5), fontSize: 10)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isActive)
                  _miniButton('Switch', () => _provider.switchProject(p.id)),
                const SizedBox(width: 4),
                _miniButton('Remove', () => _provider.removeProject(p.id), color: const Color(0xFFF44336)),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Config Diff Tab ───

  Widget _buildDiffTab() {
    return Column(
      key: const ValueKey('diff'),
      children: [
        _buildActionButton(
          icon: Icons.compare_arrows,
          label: 'Run Sample Diff',
          color: const Color(0xFFFF9800),
          onTap: () {
            _provider.computeDiff(
              {'rtp': '96.0', 'volatility': 'low', 'max_bet': '100'},
              {'rtp': '94.5', 'volatility': 'high', 'max_bet': '100', 'turbo_mode': 'enabled'},
            );
          },
        ),
        const SizedBox(height: 6),
        if (_provider.regressionRequired)
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFF44336).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFF44336).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, size: 14, color: Color(0xFFF44336)),
                const SizedBox(width: 6),
                Text(
                  'Regression Required — High-risk changes detected',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Expanded(child: _buildDiffList()),
      ],
    );
  }

  Widget _buildDiffList() {
    if (_provider.lastDiff.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.difference, size: 32, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 8),
            Text(
              'Config Diff Engine',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
            ),
            Text(
              'Compare configurations with risk analysis',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 8),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _provider.lastDiff.length,
      itemBuilder: (_, i) {
        final d = _provider.lastDiff[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF252538),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Color(d.risk.color).withValues(alpha: 0.3), width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Color(d.risk.color).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  d.risk.label,
                  style: TextStyle(color: Color(d.risk.color), fontSize: 8, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.key, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500)),
                    Text(
                      '${d.diffType}: ${d.oldValue ?? "∅"} → ${d.newValue ?? "∅"}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 8),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Regression Tab ───

  Widget _buildRegressionTab() {
    return Column(
      key: const ValueKey('regression'),
      children: [
        Row(
          children: [
            _buildActionButton(
              icon: Icons.play_arrow,
              label: _provider.regressionRunning ? 'Running...' : 'Run Regression',
              color: const Color(0xFF2196F3),
              onTap: _provider.regressionRunning ? null : () {
                if (!_provider.regressionInitialized) _provider.initRegression();
                _provider.runRegression();
              },
            ),
            const Spacer(),
            if (_provider.regressionPassed != null)
              _buildStatusBadge(_provider.regressionPassed!, '${(_provider.regressionPassRate * 100).toStringAsFixed(0)}% pass'),
          ],
        ),
        const SizedBox(height: 6),
        if (_provider.regressionPassed != null) ...[
          _buildPassRateBar(),
          const SizedBox(height: 6),
        ],
        Expanded(child: _buildRegressionResultList()),
      ],
    );
  }

  Widget _buildPassRateBar() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: _provider.regressionPassRate,
            backgroundColor: const Color(0xFF2A2A3E),
            valueColor: AlwaysStoppedAnimation(
              _provider.regressionPassRate >= 1.0 ? const Color(0xFF4CAF50)
                  : _provider.regressionPassRate >= 0.8 ? const Color(0xFFFF9800)
                  : const Color(0xFFF44336),
            ),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${(_provider.regressionPassRate * 100).toStringAsFixed(1)}% — ${_provider.regressionResults.length} scenarios tested',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 8),
        ),
      ],
    );
  }

  Widget _buildRegressionResultList() {
    if (_provider.regressionResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.science, size: 32, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 8),
            Text(
              'Auto Regression Suite',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
            ),
            Text(
              '10 stress scenarios • deterministic verification',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 8),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _provider.regressionResults.length,
      itemBuilder: (_, i) {
        final r = _provider.regressionResults[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF252538),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                r.passed ? Icons.check_circle : Icons.cancel,
                size: 12,
                color: r.passed ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(r.scenario, style: const TextStyle(color: Colors.white, fontSize: 10)),
              ),
              if (r.deterministic)
                const Icon(Icons.fingerprint, size: 10, color: Color(0xFF4CAF50))
              else
                const Icon(Icons.fingerprint, size: 10, color: Color(0xFFF44336)),
              const SizedBox(width: 4),
              Text(
                r.hash.length > 8 ? r.hash.substring(0, 8) : r.hash,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 8, fontFamily: 'monospace'),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Burn Test Tab ───

  Widget _buildBurnTestTab() {
    return Column(
      key: const ValueKey('burn'),
      children: [
        Row(
          children: [
            _buildActionButton(
              icon: Icons.local_fire_department,
              label: _provider.burnTestRunning ? 'Running...' : 'Run Burn Test',
              color: const Color(0xFFFF5722),
              onTap: _provider.burnTestRunning ? null : () {
                if (!_provider.burnTestInitialized) _provider.initBurnTest();
                _provider.runBurnTest();
              },
            ),
            const Spacer(),
            if (_provider.burnTestPassed != null)
              _buildStatusBadge(_provider.burnTestPassed!, _provider.burnTestDeterministic == true ? 'Deterministic' : 'Non-deterministic'),
          ],
        ),
        const SizedBox(height: 6),
        if (_provider.burnTestPassed != null) ...[
          _buildBurnTestSummary(),
          const SizedBox(height: 6),
        ],
        Expanded(child: _buildDriftMetricsList()),
      ],
    );
  }

  Widget _buildBurnTestSummary() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF252538),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem('Spins', _provider.burnTestTotalSpins.toString(), const Color(0xFFFF5722)),
          _summaryItem('Duration', '${_provider.burnTestDurationMs}ms', const Color(0xFF2196F3)),
          _summaryItem(
            'Hash',
            _provider.burnTestHash.length > 8 ? _provider.burnTestHash.substring(0, 8) : _provider.burnTestHash,
            const Color(0xFF9C27B0),
          ),
          _summaryItem(
            'Deterministic',
            _provider.burnTestDeterministic == true ? 'YES' : 'NO',
            _provider.burnTestDeterministic == true ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 8)),
      ],
    );
  }

  Widget _buildDriftMetricsList() {
    if (_provider.burnTestMetrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department, size: 32, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 8),
            Text(
              '10,000-Spin Burn Test',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
            ),
            Text(
              'Energy drift • Harmonic creep • Spectral bias\nVoice trend • Fatigue accumulation',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 8),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final metrics = _provider.burnTestMetrics.values.toList();
    return ListView.builder(
      itemCount: metrics.length,
      itemBuilder: (_, i) => _buildDriftMetricCard(metrics[i]),
    );
  }

  Widget _buildDriftMetricCard(DriftMetric m) {
    final trendColor = switch (m.trend) {
      SssTrendDirection.stable => const Color(0xFF4CAF50),
      SssTrendDirection.rising => const Color(0xFFFF9800),
      SssTrendDirection.falling => const Color(0xFF2196F3),
      SssTrendDirection.oscillating => const Color(0xFFE040FB),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF252538),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: trendColor.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(m.name, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: trendColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(m.trend.label, style: TextStyle(color: trendColor, fontSize: 8, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _metricValue('Init', m.initialValue),
              _metricValue('Final', m.finalValue),
              _metricValue('Peak', m.peakValue),
              _metricValue('Min', m.minValue),
              _metricValue('Drift', m.driftPct, suffix: '%'),
            ],
          ),
          if (m.samples.isNotEmpty) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 24,
              child: CustomPaint(
                painter: _SparklinePainter(m.samples, trendColor),
                size: const Size(double.infinity, 24),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricValue(String label, double value, {String suffix = ''}) {
    return Column(
      children: [
        Text(
          '${value.toStringAsFixed(2)}$suffix',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 9, fontFamily: 'monospace'),
        ),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 7)),
      ],
    );
  }

  // ─── Shared Widgets ───

  Widget _buildStatusBadge(bool passed, String label) {
    final color = passed ? const Color(0xFF4CAF50) : const Color(0xFFF44336);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(passed ? Icons.check : Icons.close, size: 10, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: onTap != null ? 0.15 : 0.05),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color.withValues(alpha: onTap != null ? 1.0 : 0.3)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: onTap != null ? 0.9 : 0.3),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniButton(String label, VoidCallback onTap, {Color color = const Color(0xFF2196F3)}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 8)),
      ),
    );
  }
}

/// Simple sparkline painter for drift metric samples.
class _SparklinePainter extends CustomPainter {
  final List<double> samples;
  final Color color;

  _SparklinePainter(this.samples, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;

    final min = samples.reduce((a, b) => a < b ? a : b);
    final max = samples.reduce((a, b) => a > b ? a : b);
    final range = max - min;
    if (range < 1e-10) return;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < samples.length; i++) {
      final x = (i / (samples.length - 1)) * size.width;
      final y = size.height - ((samples[i] - min) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);

    // Fill under
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = color.withValues(alpha: 0.08));
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.color != color;
}
