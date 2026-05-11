// HELIX dock — MATH panel (Sprint 15 Faza 4.C split #9).
//
// RTP verification + paytable analysis + recalc + win distribution
// histogram + run-sim button.
//
// Extracted from helix_screen.dart 2026-05-11.
//
// Content:
//   • _MathPanel(State)        — root widget + math metrics display
//   • _WinDistributionPainter  — histogram CustomPainter
//   • _RunSimButton(State)     — async sim trigger button

part of '../../helix_screen.dart';// ── MATH Panel ───────────────────────────────────────────────────────────────

class _MathPanel extends StatefulWidget {
  const _MathPanel();

  @override
  State<_MathPanel> createState() => _MathPanelState();
}

class _MathPanelState extends State<_MathPanel> {
  double _targetRtp = 96.0; // M1
  double _volatilitySlider = 5.0; // M2
  double _maxWinCap = 5000.0; // M4
  double _hitFreqTarget = 30.0; // M5
  double _bonusFreqTarget = 2.0; // M6

  @override
  Widget build(BuildContext context) {
    // Reactivity: rebuild when SlotLabProject or NeuroAudio change
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.instance<SlotLabProjectProvider>(),
        GetIt.instance<NeuroAudioProvider>(),
      ]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final proj = GetIt.instance<SlotLabProjectProvider>();
    final neuro = GetIt.instance<NeuroAudioProvider>();
    final stats = proj.sessionStats;
    final wins = proj.recentWins;
    final rtp = stats.rtp.isNaN || stats.rtp.isInfinite ? 0.0 : stats.rtp;

    // Volatility from NeuroAudio risk tolerance (real Rust FFI data)
    final volIdx = (neuro.output.riskTolerance * 10).clamp(0.0, 10.0);
    final volLabel = volIdx > 7 ? 'HIGH' : volIdx > 4 ? 'MED' : 'LOW';

    // Hit frequency from actual session data
    final hitRate = stats.totalSpins > 0 ? wins.length / stats.totalSpins : 0.0;
    final hitFreqStr = hitRate > 0 ? '1:${(1 / hitRate).toStringAsFixed(1)}' : '—';

    // Max win multiplier from actual wins
    final avgBet = stats.totalSpins > 0 ? stats.totalBet / stats.totalSpins : 1.0;
    final maxWinAmt = wins.isEmpty ? 0.0 : wins.map((w) => w.amount).reduce(math.max);
    final maxWinMult = avgBet > 0 ? maxWinAmt / avgBet : 0.0;

    // Bonus frequency from feature wins
    final bonusWins = wins.where((w) => w.tier.toUpperCase().contains('BONUS') || w.tier.toUpperCase().contains('FREE')).length;
    final bonusFreq = stats.totalSpins > 0 && bonusWins > 0
        ? '1:${(stats.totalSpins / bonusWins).toStringAsFixed(0)}' : '—';
    final bonusFill = stats.totalSpins > 0 ? (bonusWins / stats.totalSpins).clamp(0.0, 1.0) : 0.0;

    // RTP diff from target (M1)
    final rtpDiff = rtp > 0 ? rtp - _targetRtp : 0.0;
    final rtpDiffStr = rtpDiff >= 0 ? '+${rtpDiff.toStringAsFixed(1)}' : rtpDiff.toStringAsFixed(1);

    // RTP status color: green if within ±2% of target, orange ±5%, red beyond
    final rtpColor = rtp <= 0 ? FluxForgeTheme.textTertiary
        : rtpDiff.abs() <= 2.0 ? FluxForgeTheme.accentGreen
        : rtpDiff.abs() <= 5.0 ? FluxForgeTheme.accentOrange
        : FluxForgeTheme.accentPink;
    // Fill bar: show deviation magnitude (0=perfect, 1=max deviation)
    final rtpFill = rtp > 0 ? (1.0 - (rtpDiff.abs() / 20.0)).clamp(0.0, 1.0) : 0.0;

    // Win tier distribution from actual session wins
    const tierColors = [
      Color(0xFF4D9FFF), // WIN 1
      Color(0xFF5CFF9D), // WIN 2
      Color(0xFFFFE033), // WIN 3
      Color(0xFFFF9900), // WIN 4
      Color(0xFFFF3366), // WIN 5
    ];
    final tierCounts = <int, int>{};
    for (final w in wins) {
      final t = w.tier.toUpperCase();
      final idx = t.contains('5') ? 5 : t.contains('4') ? 4 : t.contains('3') ? 3
                : t.contains('2') ? 2 : t.contains('BONUS') || t.contains('FREE') ? 5 : 1;
      tierCounts[idx] = (tierCounts[idx] ?? 0) + 1;
    }
    final maxTierCount = tierCounts.values.fold(0, math.max);

    final cards = [
      ('RTP',       rtp > 0 ? '${rtp.toStringAsFixed(1)}%' : '—', 'Target: ${_targetRtp.toStringAsFixed(1)}% ($rtpDiffStr)', rtpFill, rtpColor),
      ('VOLATILITY',volLabel,  'Target: ${_volatilitySlider.toStringAsFixed(0)} / 10', volIdx / 10, FluxForgeTheme.accentOrange),
      ('HIT FREQ',  hitFreqStr,'Target: ${_hitFreqTarget.toStringAsFixed(0)}%', hitRate.clamp(0.0, 1.0), FluxForgeTheme.accentBlue),
      ('MAX WIN',   maxWinMult > 0 ? '${maxWinMult.toStringAsFixed(0)}×' : '—', 'Cap: ${_maxWinCap.toStringAsFixed(0)}×', (maxWinMult / _maxWinCap).clamp(0.0, 1.0), FluxForgeTheme.accentYellow),
      ('SPINS',     '${stats.totalSpins}', 'Total recorded', stats.totalSpins > 0 ? 1.0 : 0.0, FluxForgeTheme.accentPurple),
      ('BONUS FREQ',bonusFreq, 'Target: 1:${(100 / _bonusFreqTarget).toStringAsFixed(0)}', bonusFill, FluxForgeTheme.accentCyan),
    ];

    return Column(
      children: [
        // ── Stats grid 2×3 ──────────────────────────────────────────────
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: _MathCard(
                        label: cards[i].$1, value: cards[i].$2, sub: cards[i].$3,
                        fill: cards[i].$4, color: cards[i].$5,
                      )),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 3; i < 6; i++) ...[
                      if (i > 3) const SizedBox(width: 8),
                      Expanded(child: _MathCard(
                        label: cards[i].$1, value: cards[i].$2, sub: cards[i].$3,
                        fill: cards[i].$4, color: cards[i].$5,
                      )),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // ── Win Distribution Histogram ───────────────────────────────────
        Expanded(
          flex: 2,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Histogram card
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A14),
                    border: Border.all(color: const Color(0xFF1E2030)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('WIN DISTRIBUTION', style: FluxForgeTheme.dockMono(
                        size: 8,
                        color: FluxForgeTheme.textTertiary, letterSpacing: 1.0)),
                      const Spacer(),
                      Text('${wins.length} wins', style: FluxForgeTheme.dockMono(
                        size: 8, color: FluxForgeTheme.textTertiary)),
                    ]),
                    const SizedBox(height: 6),
                    Expanded(
                      child: wins.isEmpty
                        ? Center(child: Text('Run sim to populate',
                            style: FluxForgeTheme.dockSans(size: 8, color: FluxForgeTheme.textTertiary)))
                        : CustomPaint(
                            painter: _WinDistributionPainter(
                              tierCounts: tierCounts,
                              maxCount: maxTierCount,
                              tierColors: tierColors,
                            ),
                            child: const SizedBox.expand(),
                          ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              // Sliders column
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    Expanded(
                      child: Row(children: [
                        Expanded(child: _MathSlider(
                          label: 'TARGET RTP', value: _targetRtp,
                          min: 85, max: 99, suffix: '%',
                          color: FluxForgeTheme.accentGreen,
                          onChanged: (v) => setState(() => _targetRtp = v),
                        )),
                        const SizedBox(width: 6),
                        Expanded(child: _MathSlider(
                          label: 'VOLATILITY', value: _volatilitySlider,
                          min: 1, max: 10, suffix: '',
                          color: FluxForgeTheme.accentOrange,
                          onChanged: (v) => setState(() => _volatilitySlider = v),
                        )),
                        const SizedBox(width: 6),
                        Expanded(child: _MathSlider(
                          label: 'MAX WIN ×', value: _maxWinCap,
                          min: 100, max: 25000, suffix: '×',
                          color: FluxForgeTheme.accentYellow,
                          onChanged: (v) => setState(() => _maxWinCap = v),
                        )),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Row(children: [
                        Expanded(child: _MathSlider(
                          label: 'HIT FREQ', value: _hitFreqTarget,
                          min: 10, max: 60, suffix: '%',
                          color: FluxForgeTheme.accentBlue,
                          onChanged: (v) => setState(() => _hitFreqTarget = v),
                        )),
                        const SizedBox(width: 6),
                        Expanded(child: _MathSlider(
                          label: 'BONUS FREQ', value: _bonusFreqTarget,
                          min: 0.5, max: 10, suffix: '%',
                          color: FluxForgeTheme.accentCyan,
                          onChanged: (v) => setState(() => _bonusFreqTarget = v),
                        )),
                        const SizedBox(width: 6),
                        Expanded(child: _RunSimButton(
                          targetRtp: _targetRtp,
                          hitFreq: _hitFreqTarget,
                          maxWinCap: _maxWinCap,
                        )),
                      ]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Win Distribution CustomPainter ───────────────────────────────────────────

class _WinDistributionPainter extends CustomPainter {
  final Map<int, int> tierCounts;
  final int maxCount;
  final List<Color> tierColors;

  const _WinDistributionPainter({
    required this.tierCounts, required this.maxCount, required this.tierColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (maxCount == 0) return;
    const tiers = [1, 2, 3, 4, 5];
    final barW = (size.width - (tiers.length - 1) * 4) / tiers.length;
    const labelH = 14.0;
    final chartH = size.height - labelH;

    for (int i = 0; i < tiers.length; i++) {
      final tier = tiers[i];
      final count = tierCounts[tier] ?? 0;
      final fill = count > 0 ? count / maxCount : 0.0;
      final color = tierColors[i];
      final x = i * (barW + 4);
      final barH = chartH * fill;
      final y = chartH - barH;

      if (barH > 0) {
        // Gradient bar
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, barH), const Radius.circular(3));
        final paint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [color, color.withValues(alpha: 0.4)]).createShader(
              Rect.fromLTWH(x, y, barW, barH));
        canvas.drawRRect(rect, paint);

        // Count text
        if (barH > 14) {
          final tp = TextPainter(
            text: TextSpan(text: '$count',
              style: FluxForgeTheme.dockMono(size: 7, color: color)),
            textDirection: TextDirection.ltr)..layout();
          tp.paint(canvas, Offset(x + (barW - tp.width) / 2, y + 3));
        }
      }

      // Tier label below
      final label = 'W$tier';
      final tp = TextPainter(
        text: TextSpan(text: label,
          style: FluxForgeTheme.dockMono(size: 7,
            color: color.withValues(alpha: count > 0 ? 0.9 : 0.3))),
        textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(x + (barW - tp.width) / 2, chartH + 3));
    }
  }

  @override
  bool shouldRepaint(_WinDistributionPainter old) =>
    old.tierCounts != tierCounts || old.maxCount != maxCount;
}

class _RunSimButton extends StatefulWidget {
  final double targetRtp;
  final double hitFreq;
  final double maxWinCap;
  const _RunSimButton({
    this.targetRtp = 96.0,
    this.hitFreq = 30.0,
    this.maxWinCap = 5000.0,
  });
  @override
  State<_RunSimButton> createState() => _RunSimButtonState();
}

class _RunSimButtonState extends State<_RunSimButton> {
  bool _running = false;

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    silentRun('mathSim.runSimulation', () {
      final proj = GetIt.instance<SlotLabProjectProvider>();
      final rng = math.Random();
      // Use slider values: hit frequency as probability, RTP controls avg win size
      final hitProb = (widget.hitFreq / 100.0).clamp(0.05, 0.80);
      final avgWinMult = (widget.targetRtp / 100.0) / hitProb; // avg win × bet to reach target RTP
      final capMult = (widget.maxWinCap / 1000.0).clamp(2.0, 50.0);
      for (int i = 0; i < 1000; i++) {
        final isWin = rng.nextDouble() < hitProb;
        final win = isWin ? (rng.nextDouble() * avgWinMult * 2.0).clamp(0.01, capMult) : 0.0;
        proj.recordSpinResult(betAmount: 1.0, winAmount: win,
          tier: win > avgWinMult * 1.5 ? 'WIN 3' : win > 0 ? 'WIN 1' : null);
      }
    });
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: _run,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _running
          ? FluxForgeTheme.accentGreen.withValues(alpha: 0.08)
          : FluxForgeTheme.accentGreen.withValues(alpha: 0.04),
        border: Border.all(
          color: _running
            ? FluxForgeTheme.accentGreen.withValues(alpha: 0.5)
            : FluxForgeTheme.accentGreen.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (_running) ...[
          SizedBox(
            width: 10, height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: FluxForgeTheme.accentGreen,
            ),
          ),
          const SizedBox(width: 8),
          Text('Simulating 1000 spins...', style: FluxForgeTheme.dockMono(
            size: 10,
            color: FluxForgeTheme.accentGreen)),
        ] else ...[
          Icon(Icons.play_circle_rounded, size: 14, color: FluxForgeTheme.accentGreen),
          const SizedBox(width: 6),
          Text('Run Simulation (1000 spins)', style: FluxForgeTheme.dockMono(
            size: 10,
            color: FluxForgeTheme.accentGreen)),
        ],
      ]),
    ),
  );
}
