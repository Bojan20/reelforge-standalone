// HELIX dock — A/B Split-Test panel (Sprint 15 Faza 4.C split #7).
//
// Dual-variant config (RTP + volatility sliders), spin count up to 1M,
// run simulation with progress, results table (6 metrics + diff),
// winner badge.
//
// Extracted from helix_screen.dart 2026-05-11.
//
// Content:
//   • _AbTestPanel(State) — root widget + simulation orchestrator

part of '../../helix_screen.dart';// ── 3.7 A/B Split Test Panel ────────────────────────────────────────────────

class _AbTestPanel extends StatefulWidget {
  const _AbTestPanel();
  @override
  State<_AbTestPanel> createState() => _AbTestPanelState();
}

class _AbTestPanelState extends State<_AbTestPanel> {
  // Variant config
  double _variantARtp = 96.0;
  double _variantBRtp = 94.0;
  double _variantAVolatility = 2.5;
  double _variantBVolatility = 3.0;
  int _spinCount = 100000;
  bool _isRunning = false;
  Map<String, dynamic>? _results;

  AbSimProvider? _abSim;

  void _onSimUpdate() {
    if (!mounted) return;
    final sim = _abSim;
    if (sim == null) return;
    if (!sim.isRunning) {
      setState(() {
        _results = sim.lastResult;
        _isRunning = false;
      });
      sim.removeListener(_onSimUpdate);
    } else {
      setState(() {}); // refresh progress
    }
  }

  @override
  void dispose() {
    _abSim?.removeListener(_onSimUpdate);
    super.dispose();
  }

  void _runSimulation() {
    final abSim = GetIt.instance<AbSimProvider>();
    _abSim = abSim;
    setState(() { _isRunning = true; _results = null; });

    final config = {
      'variants': [
        {'name': 'Variant A', 'rtp': _variantARtp / 100, 'volatility': _variantAVolatility},
        {'name': 'Variant B', 'rtp': _variantBRtp / 100, 'volatility': _variantBVolatility},
      ],
      'spinsPerVariant': _spinCount,
    };

    abSim.addListener(_onSimUpdate);
    abSim.startSimulation(config);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left: Config
        Flexible(
          flex: 3,
          child: _DockCard(
            accent: FluxForgeTheme.accentGreen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('A/B SPLIT TEST CONFIG', color: FluxForgeTheme.accentGreen),
                const SizedBox(height: 8),
                // Variant A
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('VARIANT A', style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                      color: FluxForgeTheme.accentBlue, fontWeight: FontWeight.w700)),
                    _SfxPresetSlider(label: 'RTP', value: _variantARtp, min: 85, max: 99, suffix: '%',
                      onChanged: (v) => setState(() => _variantARtp = v)),
                    _SfxPresetSlider(label: 'Volatility', value: _variantAVolatility, min: 1, max: 5, suffix: '',
                      onChanged: (v) => setState(() => _variantAVolatility = v)),
                  ]),
                ),
                // Variant B
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentGreen.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: FluxForgeTheme.accentGreen.withValues(alpha: 0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('VARIANT B', style: TextStyle(fontFamily: 'monospace', fontSize: 9,
                      color: FluxForgeTheme.accentGreen, fontWeight: FontWeight.w700)),
                    _SfxPresetSlider(label: 'RTP', value: _variantBRtp, min: 85, max: 99, suffix: '%',
                      onChanged: (v) => setState(() => _variantBRtp = v)),
                    _SfxPresetSlider(label: 'Volatility', value: _variantBVolatility, min: 1, max: 5, suffix: '',
                      onChanged: (v) => setState(() => _variantBVolatility = v)),
                  ]),
                ),
                // Spin count
                _SfxPresetSlider(label: 'Spins/Variant', value: _spinCount.toDouble(),
                  min: 10000, max: 1000000, suffix: '',
                  color: FluxForgeTheme.accentGreen, onChanged: (v) => setState(() => _spinCount = v.round())),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _isRunning ? null : _runSimulation,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _isRunning
                        ? FluxForgeTheme.textTertiary.withValues(alpha: 0.1)
                        : FluxForgeTheme.accentGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _isRunning
                        ? FluxForgeTheme.textTertiary : FluxForgeTheme.accentGreen.withValues(alpha: 0.5)),
                    ),
                    child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_isRunning)
                        const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: FluxForgeTheme.accentGreen))
                      else
                        const Icon(Icons.science_rounded, size: 14, color: FluxForgeTheme.accentGreen),
                      const SizedBox(width: 8),
                      Text(_isRunning ? 'SIMULATING...' : 'RUN A/B TEST',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
                          color: FluxForgeTheme.accentGreen, fontWeight: FontWeight.w600)),
                    ])),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Right: Results
        Expanded(
          flex: 3,
          child: _DockCard(
            accent: FluxForgeTheme.accentGreen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DockLabel('RESULTS', color: FluxForgeTheme.accentGreen),
                const SizedBox(height: 8),
                if (_isRunning) ...[
                  ListenableBuilder(
                    listenable: GetIt.instance<AbSimProvider>(),
                    builder: (_, _) {
                    final abSim = GetIt.instance<AbSimProvider>();
                    return Column(children: [
                      LinearProgressIndicator(
                        value: abSim.progress,
                        backgroundColor: FluxForgeTheme.bgSurface,
                        valueColor: const AlwaysStoppedAnimation(FluxForgeTheme.accentGreen),
                      ),
                      const SizedBox(height: 8),
                      Text('${(abSim.progress * 100).toStringAsFixed(1)}% complete',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textSecondary)),
                    ]);
                  }),
                ] else if (_results != null) ...[
                  Expanded(
                    child: _buildResultsTable(),
                  ),
                ] else ...[
                  Expanded(
                    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.science_outlined, size: 48, color: FluxForgeTheme.accentGreen.withValues(alpha: 0.2)),
                      const SizedBox(height: 12),
                      const Text('Configure variants and run simulation',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: FluxForgeTheme.textTertiary)),
                      const SizedBox(height: 6),
                      Text('Up to 1M spins per variant',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6))),
                    ])),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsTable() {
    final variants = _results?['variants'] as List? ?? [];
    if (variants.isEmpty) {
      return const Center(child: Text('No results', style: TextStyle(
        fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textTertiary)));
    }
    return ListView(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(children: [
            SizedBox(width: 100, child: Text('METRIC', style: TextStyle(fontFamily: 'monospace', fontSize: 9,
              color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600))),
            Expanded(child: Text('VARIANT A', style: TextStyle(fontFamily: 'monospace', fontSize: 9,
              color: FluxForgeTheme.accentBlue, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
            Expanded(child: Text('VARIANT B', style: TextStyle(fontFamily: 'monospace', fontSize: 9,
              color: FluxForgeTheme.accentGreen, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
            SizedBox(width: 80, child: Text('DIFF', style: TextStyle(fontFamily: 'monospace', fontSize: 9,
              color: FluxForgeTheme.textTertiary, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
          ]),
        ),
        const SizedBox(height: 4),
        // Metrics rows
        ..._buildMetricRows(variants),
        const SizedBox(height: 12),
        // Winner badge
        if (variants.length >= 2) _buildWinnerBadge(variants),
      ],
    );
  }

  List<Widget> _buildMetricRows(List variants) {
    final a = variants[0] as Map<String, dynamic>? ?? {};
    final b = variants.length > 1 ? variants[1] as Map<String, dynamic>? ?? {} : {};
    final metrics = [
      ('Actual RTP', a['actualRtp'] ?? _variantARtp, b['actualRtp'] ?? _variantBRtp, '%'),
      ('Avg Win', a['avgWin'] ?? 0.0, b['avgWin'] ?? 0.0, 'x'),
      ('Hit Rate', a['hitRate'] ?? 0.0, b['hitRate'] ?? 0.0, '%'),
      ('Max Win', a['maxWin'] ?? 0.0, b['maxWin'] ?? 0.0, 'x'),
      ('Std Dev', a['stdDev'] ?? 0.0, b['stdDev'] ?? 0.0, ''),
      ('Bankroll Half-life', a['halfLife'] ?? 0.0, b['halfLife'] ?? 0.0, ' spins'),
    ];
    return metrics.map((m) {
      final (label, aVal, bVal, suffix) = m;
      final aNum = (aVal is num) ? aVal.toDouble() : 0.0;
      final bNum = (bVal is num) ? bVal.toDouble() : 0.0;
      final diff = aNum - bNum;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        margin: const EdgeInsets.only(bottom: 2),
        child: Row(children: [
          SizedBox(width: 100, child: Text(label,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary))),
          Expanded(child: Text('${aNum.toStringAsFixed(2)}$suffix',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textPrimary),
            textAlign: TextAlign.center)),
          Expanded(child: Text('${bNum.toStringAsFixed(2)}$suffix',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: FluxForgeTheme.textPrimary),
            textAlign: TextAlign.center)),
          SizedBox(width: 80, child: Text(
            '${diff >= 0 ? "+" : ""}${diff.toStringAsFixed(2)}',
            style: TextStyle(fontFamily: 'monospace', fontSize: 9,
              color: diff.abs() < 0.1 ? FluxForgeTheme.textTertiary
                : diff > 0 ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentPink),
            textAlign: TextAlign.center)),
        ]),
      );
    }).toList();
  }

  Widget _buildWinnerBadge(List variants) {
    final aRtp = (variants[0] as Map?)?['actualRtp'] ?? _variantARtp;
    final bRtp = (variants[1] as Map?)?['actualRtp'] ?? _variantBRtp;
    final aNum = (aRtp is num) ? aRtp.toDouble() : 0.0;
    final bNum = (bRtp is num) ? bRtp.toDouble() : 0.0;
    final winner = aNum >= bNum ? 'A' : 'B';
    final winColor = winner == 'A' ? FluxForgeTheme.accentBlue : FluxForgeTheme.accentGreen;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: winColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: winColor.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.emoji_events_rounded, size: 18, color: winColor),
        const SizedBox(width: 8),
        Text('VARIANT $winner WINS',
          style: TextStyle(fontFamily: 'monospace', fontSize: 12,
            color: winColor, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text('(${(aNum - bNum).abs().toStringAsFixed(2)}% RTP difference)',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary)),
      ]),
    );
  }
}
