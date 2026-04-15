import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/slot_lab/ab_test_provider.dart';

/// UCP-13: A/B Testing Analytics Panel — Data-driven audio decisions
///
/// Displays A/B test configuration, runs simulation, shows results with
/// statistical significance, per-archetype breakdown, and responsible gaming flags.
class AbTestPanel extends StatefulWidget {
  const AbTestPanel({super.key});

  @override
  State<AbTestPanel> createState() => _AbTestPanelState();
}

class _AbTestPanelState extends State<AbTestPanel> {
  AbTestProvider? _provider;

  @override
  void initState() {
    super.initState();
    try {
      _provider = GetIt.instance<AbTestProvider>();
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
        child: Text('A/B Test not available', style: TextStyle(color: Colors.grey)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Left: Config ──────────────────────────────────────
          SizedBox(
            width: 240,
            child: _buildConfigPanel(p),
          ),
          const SizedBox(width: 8),
          // ─── Center: Results ───────────────────────────────────
          Expanded(
            flex: 3,
            child: _buildResultsPanel(p),
          ),
          const SizedBox(width: 8),
          // ─── Right: Variant comparison ─────────────────────────
          SizedBox(
            width: 200,
            child: _buildVariantComparison(p),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIG PANEL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildConfigPanel(AbTestProvider p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header + Run
        Row(
          children: [
            const Icon(Icons.science, color: Color(0xFF8866CC), size: 14),
            const SizedBox(width: 6),
            const Text('A/B Test Config',
                style: TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            GestureDetector(
              onTap: p.isSimulating ? null : () => p.runSimulation(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: p.isSimulating
                      ? const Color(0xFF2A2A4E)
                      : const Color(0xFF44CC44).withAlpha(30),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                      color: p.isSimulating
                          ? const Color(0xFF3A3A5C)
                          : const Color(0xFF44CC44).withAlpha(80),
                      width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      p.isSimulating ? Icons.hourglass_top : Icons.play_arrow,
                      size: 11,
                      color: const Color(0xFF44CC44),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      p.isSimulating ? 'Running...' : 'Run',
                      style: const TextStyle(
                          color: Color(0xFF44CC44), fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Sample size
        _configRow('Sample Size', '${p.sampleSize}'),
        const SizedBox(height: 4),

        // Population mix
        const Text('Population Mix',
            style: TextStyle(
                color: Color(0xFF888888),
                fontSize: 9,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final arch in PlayerArchetype.values)
                  _buildArchetypeRow(p, arch),
                const SizedBox(height: 8),
                // Active metrics
                const Text('Success Metrics',
                    style: TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 9,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                for (final m in SuccessMetric.values)
                  _buildMetricToggle(p, m),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _configRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF888888), fontSize: 9)),
        Text(value,
            style: const TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 9,
                fontFamily: 'monospace')),
      ],
    );
  }

  Widget _buildArchetypeRow(AbTestProvider p, PlayerArchetype arch) {
    final weight = p.populationMix[arch] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(arch.displayName,
                style: const TextStyle(color: Color(0xFF999999), fontSize: 9)),
          ),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D1A),
                borderRadius: BorderRadius.circular(3),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: weight,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF8866CC),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 30,
            child: Text('${(weight * 100).toStringAsFixed(0)}%',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 8,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricToggle(AbTestProvider p, SuccessMetric m) {
    final active = p.activeMetrics.contains(m);
    return GestureDetector(
      onTap: () => p.toggleMetric(m),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 1),
        child: Row(
          children: [
            Icon(
              active ? Icons.check_box : Icons.check_box_outline_blank,
              size: 11,
              color: active
                  ? (m.isResponsibleGaming
                      ? const Color(0xFFCC8844)
                      : const Color(0xFF44AACC))
                  : const Color(0xFF555577),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(m.displayName,
                  style: TextStyle(
                      color: active
                          ? const Color(0xFFCCCCCC)
                          : const Color(0xFF666677),
                      fontSize: 9)),
            ),
            if (m.isResponsibleGaming)
              const Text('RG',
                  style: TextStyle(
                      color: Color(0xFFCC8844),
                      fontSize: 7,
                      fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESULTS PANEL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildResultsPanel(AbTestProvider p) {
    final result = p.lastResult;
    if (result == null) {
      return const Center(
        child: Text(
          'Configure variants and click Run to start A/B simulation.\n'
          'Default: 10,000 simulated player sessions per variant.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF555577), fontSize: 10),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Winner banner
        _buildWinnerBanner(result),
        const SizedBox(height: 6),

        // Metric comparison table
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats header
                Row(
                  children: [
                    const SizedBox(width: 120),
                    SizedBox(
                        width: 70,
                        child: Text(result.variantA.variantName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Color(0xFF4488CC),
                                fontSize: 9,
                                fontWeight: FontWeight.w600))),
                    SizedBox(
                        width: 70,
                        child: Text(result.variantB.variantName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Color(0xFFCC8844),
                                fontSize: 9,
                                fontWeight: FontWeight.w600))),
                    const SizedBox(width: 70,
                        child: Text('Delta',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Color(0xFF888888),
                                fontSize: 9,
                                fontWeight: FontWeight.w600))),
                  ],
                ),
                const SizedBox(height: 4),

                for (final m in p.activeMetrics) _buildMetricRow(result, m),

                const SizedBox(height: 8),

                // Responsible Gaming Flags
                if (result.responsibleGamingFlags.isNotEmpty) ...[
                  const Text('Responsible Gaming Flags',
                      style: TextStyle(
                          color: Color(0xFFCC4444),
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  for (final flag in result.responsibleGamingFlags)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(flag,
                          style: const TextStyle(
                              color: Color(0xFFCC8844), fontSize: 9)),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWinnerBanner(AbTestResult result) {
    final isSignificant = result.isSignificant;
    final winner = result.winner;
    final hasRgFlags = result.responsibleGamingFlags.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isSignificant
            ? (hasRgFlags
                ? const Color(0xFF332200)
                : const Color(0xFF003322))
            : const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: isSignificant
                ? (hasRgFlags
                    ? const Color(0xFFCC8844).withAlpha(60)
                    : const Color(0xFF44CC44).withAlpha(60))
                : const Color(0xFF3A3A5C),
            width: 0.5),
      ),
      child: Row(
        children: [
          Icon(
            isSignificant
                ? (hasRgFlags ? Icons.warning_amber : Icons.emoji_events)
                : Icons.info_outline,
            size: 16,
            color: isSignificant
                ? (hasRgFlags
                    ? const Color(0xFFCC8844)
                    : const Color(0xFF44CC44))
                : const Color(0xFF888888),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSignificant
                      ? (winner != null
                          ? '$winner wins (p=${result.pValue.toStringAsFixed(4)})'
                          : 'Significant but no clear winner')
                      : 'Not statistically significant (p=${result.pValue.toStringAsFixed(4)})',
                  style: TextStyle(
                      color: isSignificant
                          ? const Color(0xFFEEEEEE)
                          : const Color(0xFF999999),
                      fontSize: 10,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  '95% CI: [${result.confidenceInterval.$1.toStringAsFixed(4)}, '
                  '${result.confidenceInterval.$2.toStringAsFixed(4)}] | '
                  'n=${result.variantA.sampleSize} per variant',
                  style: const TextStyle(
                      color: Color(0xFF888888), fontSize: 8),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(AbTestResult result, SuccessMetric metric) {
    final a = result.variantA.scores[metric] ?? 0;
    final b = result.variantB.scores[metric] ?? 0;
    final delta = result.getDeltaPercent(metric);
    final isBetter = metric.higherIsBetter ? delta > 0 : delta < 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Row(
              children: [
                if (metric.isResponsibleGaming)
                  const Padding(
                    padding: EdgeInsets.only(right: 3),
                    child: Icon(Icons.shield, size: 9, color: Color(0xFFCC8844)),
                  ),
                Expanded(
                  child: Text(metric.displayName,
                      style: TextStyle(
                          color: metric.isResponsibleGaming
                              ? const Color(0xFFCC8844)
                              : const Color(0xFFCCCCCC),
                          fontSize: 9)),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 70,
            child: _buildMetricBar(a, const Color(0xFF4488CC)),
          ),
          SizedBox(
            width: 70,
            child: _buildMetricBar(b, const Color(0xFFCC8844)),
          ),
          SizedBox(
            width: 70,
            child: Text(
              '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: isBetter
                      ? const Color(0xFF44CC44)
                      : const Color(0xFFCC4444),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBar(double value, Color color) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D1A),
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0, 1),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 3),
        SizedBox(
          width: 22,
          child: Text(
            (value * 100).toStringAsFixed(0),
            style: TextStyle(
                color: color, fontSize: 8, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VARIANT COMPARISON — radar-style characteristics
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildVariantComparison(AbTestProvider p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.compare_arrows, color: Color(0xFF888888), size: 14),
            SizedBox(width: 6),
            Text('Variants',
                style: TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),

        // Variant A
        _buildVariantCard(p.variantA, const Color(0xFF4488CC)),
        const SizedBox(height: 6),

        // Variant B
        _buildVariantCard(p.variantB, const Color(0xFFCC8844)),

        const Spacer(),

        // History
        if (p.history.isNotEmpty) ...[
          const Text('Test History',
              style: TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 9,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          SizedBox(
            height: 80,
            child: ListView.builder(
              itemCount: p.history.length,
              itemBuilder: (context, i) {
                final r = p.history[i];
                final ago = DateTime.now().difference(r.timestamp);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Icon(
                        r.isSignificant
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 9,
                        color: r.isSignificant
                            ? const Color(0xFF44CC44)
                            : const Color(0xFF555577),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          r.winner ?? 'No winner',
                          style: const TextStyle(
                              color: Color(0xFF999999), fontSize: 8),
                        ),
                      ),
                      Text(
                        ago.inMinutes < 1 ? 'now' : '${ago.inMinutes}m',
                        style: const TextStyle(
                            color: Color(0xFF555577), fontSize: 8),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVariantCard(AudioVariant variant, Color color) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(40), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(variant.name,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
          if (variant.description.isNotEmpty)
            Text(variant.description,
                style: const TextStyle(
                    color: Color(0xFF888888), fontSize: 8)),
          const SizedBox(height: 4),
          for (final entry in variant.characteristics.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(entry.key,
                        style: const TextStyle(
                            color: Color(0xFF888888), fontSize: 8)),
                  ),
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D0D1A),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: entry.value,
                        child: Container(
                          decoration: BoxDecoration(
                            color: color.withAlpha(150),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
