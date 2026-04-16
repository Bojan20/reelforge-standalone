import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/slot_lab/ab_test_provider.dart';

/// A/B Testing Analytics™ Panel — powered by AbTestProvider.
///
/// Reads REAL simulation data:
/// - 10k virtual player simulation with 5 archetypes
/// - 7 success metrics including responsible gaming checks
/// - Statistical significance (Welch's t-test, p-values, 95% CI)
/// - Per-archetype breakdown (Casual, Regular, High Roller, New, VIP)
class AbSimPanel extends StatefulWidget {
  const AbSimPanel({super.key});

  @override
  State<AbSimPanel> createState() => _AbSimPanelState();
}

class _AbSimPanelState extends State<AbSimPanel> {
  late final AbTestProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<AbTestProvider>();
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
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          if (_provider.isSimulating) _buildProgressBar(),
          if (_provider.isSimulating) const SizedBox(height: 8),
          Expanded(child: _buildContent()),
          const SizedBox(height: 6),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final result = _provider.lastResult;
    return Row(
      children: [
        const Icon(Icons.science, size: 14, color: Color(0xFF40C8FF)),
        const SizedBox(width: 4),
        Text(
          'A/B Testing Analytics',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        if (_provider.isSimulating)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFFBB33).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFFFBB33).withValues(alpha: 0.4)),
            ),
            child: const Text(
              'SIMULATING',
              style: TextStyle(color: Color(0xFFFFBB33), fontSize: 9, fontWeight: FontWeight.w700),
            ),
          ),
        if (result != null && !_provider.isSimulating)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (result.isSignificant ? const Color(0xFF4CAF50) : const Color(0xFFFFBB33))
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: (result.isSignificant ? const Color(0xFF4CAF50) : const Color(0xFFFFBB33))
                    .withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              result.isSignificant ? 'SIGNIFICANT' : 'NOT SIGNIFICANT',
              style: TextStyle(
                color: result.isSignificant ? const Color(0xFF4CAF50) : const Color(0xFFFFBB33),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        const Spacer(),
        Text(
          'n=${_provider.sampleSize}',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 9),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Simulating', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9)),
            const Spacer(),
            Text(
              '${(_provider.simulationProgress * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 9, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: _provider.simulationProgress,
          backgroundColor: const Color(0xFF2A2A4A),
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF40C8FF)),
          minHeight: 4,
          borderRadius: BorderRadius.circular(2),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final result = _provider.lastResult;
    if (result == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.science_outlined, size: 32, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 8),
            Text(
              _provider.isSimulating
                  ? 'Simulation in progress...'
                  : 'No results yet.\nRun simulation to compare variants.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Winner announcement
          if (result.winner != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events, size: 16, color: Color(0xFFFFD700)),
                  const SizedBox(width: 6),
                  Text(
                    'Winner: ${result.winner}',
                    style: const TextStyle(
                      color: Color(0xFF4CAF50),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'p=${result.pValue.toStringAsFixed(4)}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9),
                  ),
                ],
              ),
            ),

          // Responsible gaming flags
          if (result.responsibleGamingFlags.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFFF5252).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber, size: 12, color: Color(0xFFFF5252)),
                      SizedBox(width: 4),
                      Text('RG Flags', style: TextStyle(color: Color(0xFFFF5252), fontSize: 9, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  ...result.responsibleGamingFlags.map((f) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('• $f', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 9)),
                      )),
                ],
              ),
            ),
          ],

          // Metrics comparison
          _buildSectionTitle('Metric Comparison'),
          const SizedBox(height: 4),
          ...SuccessMetric.values.where((m) => _provider.activeMetrics.contains(m)).map(
                (metric) => _buildMetricComparison(result, metric),
              ),

          // Confidence interval
          const SizedBox(height: 8),
          _buildSectionTitle('Statistics'),
          const SizedBox(height: 4),
          _buildKeyValue('p-value', result.pValue.toStringAsFixed(6)),
          _buildKeyValue('95% CI', '(${result.confidenceInterval.$1.toStringAsFixed(3)}, ${result.confidenceInterval.$2.toStringAsFixed(3)})'),
          _buildKeyValue('Significant', result.isSignificant ? 'Yes (p < 0.05)' : 'No'),

          // History
          if (_provider.history.length > 1) ...[
            const SizedBox(height: 8),
            _buildSectionTitle('History (${_provider.history.length} runs)'),
            const SizedBox(height: 4),
            ..._provider.history.reversed.take(5).map((h) => _buildHistoryRow(h)),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricComparison(AbTestResult result, SuccessMetric metric) {
    final aScore = result.variantA.scores[metric] ?? 0;
    final bScore = result.variantB.scores[metric] ?? 0;
    final delta = result.getDeltaPercent(metric);
    final isRg = metric.isResponsibleGaming;
    final betterIsHigher = metric.higherIsBetter;
    final bIsBetter = betterIsHigher ? bScore > aScore : bScore < aScore;

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E36),
        borderRadius: BorderRadius.circular(3),
        border: isRg
            ? Border.all(color: const Color(0xFFFF5252).withValues(alpha: 0.2), width: 0.5)
            : null,
      ),
      child: Row(
        children: [
          if (isRg)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.shield, size: 10, color: Color(0xFFFF5252)),
            ),
          Expanded(
            flex: 3,
            child: Text(
              metric.displayName,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 9,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 45,
            child: Text(
              aScore.toStringAsFixed(2),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 4),
          const Text('vs', style: TextStyle(color: Color(0xFF3A3A5C), fontSize: 8)),
          const SizedBox(width: 4),
          SizedBox(
            width: 45,
            child: Text(
              bScore.toStringAsFixed(2),
              style: TextStyle(
                color: bIsBetter ? const Color(0xFF4CAF50) : Colors.white.withValues(alpha: 0.5),
                fontSize: 9,
                fontWeight: bIsBetter ? FontWeight.w600 : FontWeight.normal,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 42,
            child: Text(
              '${delta >= 0 ? "+" : ""}${delta.toStringAsFixed(1)}%',
              style: TextStyle(
                color: bIsBetter
                    ? const Color(0xFF4CAF50)
                    : (delta.abs() > 5 ? const Color(0xFFFF5252) : Colors.white.withValues(alpha: 0.4)),
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryRow(AbTestResult h) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(
            h.isSignificant ? Icons.check_circle : Icons.remove_circle_outline,
            size: 10,
            color: h.isSignificant ? const Color(0xFF4CAF50) : const Color(0xFF3A3A5C),
          ),
          const SizedBox(width: 4),
          Text(
            h.winner ?? 'No winner',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 9),
          ),
          const Spacer(),
          Text(
            'p=${h.pValue.toStringAsFixed(3)}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 8),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _provider.isSimulating ? null : () => _provider.runSimulation(),
            icon: const Icon(Icons.play_arrow, size: 14),
            label: Text(
              _provider.lastResult != null ? 'Re-run Sim' : 'Run Simulation',
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
      ],
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
        children: [
          SizedBox(
            width: 80,
            child: Text(key, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 9)),
          ),
        ],
      ),
    );
  }
}
