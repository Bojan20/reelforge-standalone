// HELIX dock — INTEL panel (Sprint 15 Faza 4.C split #11).
//
// AI co-pilot + RGAI compliance + neuro audio state + engagement
// score + retention metrics + mini stats grid.
//
// Extracted from helix_screen.dart 2026-05-11.
//
// Content:
//   • _IntelPanel(State) — root widget + intel/co-pilot orchestrator

part of '../../helix_screen.dart';// ── INTEL Panel ──────────────────────────────────────────────────────────────

class _IntelPanel extends StatefulWidget {
  const _IntelPanel();
  @override
  State<_IntelPanel> createState() => _IntelPanelState();
}

class _IntelPanelState extends State<_IntelPanel> {
  String? _selectedArchetype;

  @override
  Widget build(BuildContext context) {
    // Reactivity: rebuild when RgaiProvider or NeuroAudioProvider change
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.instance<RgaiProvider>(),
        GetIt.instance<NeuroAudioProvider>(),
      ]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final rgai = GetIt.instance<RgaiProvider>();
    final neuro = GetIt.instance<NeuroAudioProvider>();
    final out = neuro.output;
    final report = rgai.report;
    final summary = report?.summary;

    // Build copilot suggestions from real RGAI remediations
    final allRemediations = <RemediationSuggestion>[];
    for (final asset in report?.assets ?? <RgarAssetAnalysis>[]) {
      allRemediations.addAll(asset.remediations);
    }

    // Build copilot text from real data
    String copilotText;
    if (allRemediations.isNotEmpty) {
      final top = allRemediations.first;
      copilotText = 'Suggest: ${top.parameter} ${top.currentValue} → ${top.suggestedValue}\n'
          '${top.reason}';
    } else if (neuro.responsibleGamingMode) {
      copilotText = 'RG mode active. Audio intensity reduced.\n'
          'Monitoring player risk level: ${neuro.riskLevel.name}.';
    } else if (out.frustration > 0.6) {
      copilotText = 'High frustration detected (${(out.frustration * 100).toStringAsFixed(0)}%).\n'
          'Suggest: Increase reverb depth, reduce tempo.';
    } else if (out.engagement > 0.7) {
      copilotText = 'Player in flow state (${(out.flowDepth * 100).toStringAsFixed(0)}% depth).\n'
          'Audio adaptation: maintaining current balance.';
    } else {
      copilotText = 'Session active. ${neuro.totalSpins} spins tracked.\n'
          'All parameters within normal range.';
    }

    final stimPass = summary?.isCompliant ?? true;
    final riskRating = summary?.overallRiskRating;
    final nearMissOk = (summary?.maxNearMissDeception ?? 0) < 0.5;

    // Real engagement score
    final score = (out.engagement * 10).clamp(0.0, 10.0);

    // Real mini metrics from NeuroAudioProvider
    final retention = ((1.0 - out.churnPrediction) * 100).toStringAsFixed(0);
    final dwell = '${neuro.sessionDurationMinutes.toStringAsFixed(1)}m';
    final fatigueIdx = out.sessionFatigue.toStringAsFixed(2);
    final losses = '${neuro.consecutiveLosses}';

    return Row(
      children: [
        // Left: AI Copilot + RGAI
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: _DockCard(
                  accent: FluxForgeTheme.accentPurple,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(width: 6, height: 6,
                          decoration: BoxDecoration(
                            color: neuro.responsibleGamingMode
                              ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentGreen,
                            shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        _DockLabel('AI COPILOT', color: FluxForgeTheme.accentPurple),
                        const Spacer(),
                        if (allRemediations.isNotEmpty)
                          Text('${allRemediations.length} suggestions', style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.accentYellow)),
                      ]),
                      const SizedBox(height: 4),
                      Text(copilotText,
                        style: const TextStyle(fontSize: 10, height: 1.4,
                          color: FluxForgeTheme.textSecondary)),
                      const SizedBox(height: 3),
                      // Apply top suggestion button
                      if (allRemediations.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            // Apply: set RTPC via middleware using suggested value
                            // Map parameter name → RTPC index (matches NeuroAudioProvider 8D dims)
                            silentRun('copilot.applyRtpcSuggestion', () {
                              final top = allRemediations.first;
                              final v = double.tryParse(top.suggestedValue) ?? 0.5;
                              final mw = GetIt.instance<MiddlewareProvider>();
                              final param = top.parameter.toLowerCase();
                              final rtpcIdx = param.contains('arousal') ? 0
                                : param.contains('valence') ? 1
                                : param.contains('engagement') ? 2
                                : param.contains('risk') ? 3
                                : param.contains('frustration') ? 4
                                : param.contains('flow') ? 5
                                : param.contains('churn') ? 6
                                : param.contains('fatigue') ? 7
                                : param.contains('reverb') ? 5
                                : param.contains('volume') ? 0
                                : param.contains('tempo') ? 3
                                : param.contains('compress') ? 2
                                : 0;
                              mw.setRtpc(rtpcIdx, v.clamp(0.0, 1.0), interpolationMs: 500);
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.accentPurple.withValues(alpha: 0.1),
                              border: Border.all(color: FluxForgeTheme.accentPurple.withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.auto_fix_high_rounded, size: 10,
                                color: FluxForgeTheme.accentPurple),
                              const SizedBox(width: 5),
                              const Text('Apply suggestion', style: TextStyle(
                                fontFamily: 'monospace', fontSize: 9,
                                color: FluxForgeTheme.accentPurple)),
                            ]),
                          ),
                        ),
                      const SizedBox(height: 3),
                      // I2: CoPilot chat input
                      const _CoPilotChatWidget(),
                      const SizedBox(height: 3),
                      // I3: Archetype selector
                      Row(children: [
                        _DockLabel('ARCHETYPE', color: FluxForgeTheme.accentPurple),
                        const Spacer(),
                        ...['Casual', 'Regular', 'Whale', 'Frustrated'].map((a) {
                          final isActive = _selectedArchetype == a;
                          const c = FluxForgeTheme.accentCyan;
                          return Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: GestureDetector(
                              onTap: () {
                                setState(() => _selectedArchetype = a);
                                // Archetype simulation: adjust neuro signals
                                switch (a) {
                                  case 'Casual':
                                    neuro.recordBetSize(0.2);
                                    neuro.recordClickVelocity(3000);
                                  case 'Whale':
                                    neuro.recordBetSize(0.9);
                                    neuro.recordClickVelocity(800);
                                  case 'Frustrated':
                                    neuro.recordBetSize(0.7);
                                    neuro.recordSpinResult(0);
                                    neuro.recordSpinResult(0);
                                  default:
                                    neuro.recordBetSize(0.5);
                                    neuro.recordClickVelocity(1500);
                                }
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isActive ? c.withValues(alpha: 0.18) : c.withValues(alpha: 0.05),
                                  border: Border.all(
                                    color: isActive ? c.withValues(alpha: 0.6) : c.withValues(alpha: 0.25)),
                                  borderRadius: BorderRadius.circular(4)),
                                child: Text(a, style: TextStyle(
                                  fontFamily: 'monospace', fontSize: 8,
                                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                  color: isActive ? c : c.withValues(alpha: 0.7))),
                              ),
                            ),
                          );
                        }),
                      ]),
                      const Spacer(),
                      // I4: Simulate Session button
                      Row(children: [
                        GestureDetector(
                          onTap: () {
                            // Run 200 spin neuro simulation
                            final rng = math.Random();
                            for (int i = 0; i < 200; i++) {
                              neuro.recordClickVelocity(500 + rng.nextDouble() * 3000);
                              neuro.recordPauseDuration(200 + rng.nextDouble() * 2000);
                              neuro.recordBetSize(rng.nextDouble());
                              final winMult = rng.nextDouble() < 0.25 ? rng.nextDouble() * 10 : 0.0;
                              neuro.recordSpinResult(winMult);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.accentCyan.withValues(alpha: 0.06),
                              border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(5)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.play_circle_outlined, size: 10, color: FluxForgeTheme.accentCyan),
                              SizedBox(width: 4),
                              Text('Simulate 200 spins', style: TextStyle(
                                fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.accentCyan)),
                            ]),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(neuro.responsibleGamingMode ? '⚠ RG MODE' : '✓ RG stable',
                          style: TextStyle(fontSize: 9,
                            color: neuro.responsibleGamingMode
                              ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentGreen)),
                      ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _DockCard(
                  accent: FluxForgeTheme.accentPurple,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        _DockLabel('RGAI COMPLIANCE', color: FluxForgeTheme.accentPurple),
                        const Spacer(),
                        // I5: Run Analysis button
                        GestureDetector(
                          onTap: () {
                            silentRun('rgai.analyzeBatch', () {
                              final mw = GetIt.instance<MiddlewareProvider>();
                              final ces = mw.compositeEvents;
                              if (ces.isNotEmpty) {
                                rgai.analyzeBatch(
                                  gameName: GetIt.instance<SlotLabProjectProvider>().projectName,
                                  assets: ces.map((e) => (
                                    id: e.id,
                                    name: e.name,
                                    stage: e.triggerStages.isNotEmpty ? e.triggerStages.first : 'base',
                                    volumeDb: -6.0 + (e.masterVolume * 6),
                                    durationS: 1.5,
                                    tempo: 1.0,
                                    spectralHz: 2000.0,
                                    isWin: e.category.contains('win'),
                                    isNearMiss: e.category.contains('near'),
                                    isLoss: e.category.contains('loss'),
                                    betMult: 1.0,
                                  )).toList(),
                                );
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.accentPurple.withValues(alpha: 0.08),
                              border: Border.all(color: FluxForgeTheme.accentPurple.withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(4)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.shield_rounded, size: 9,
                                color: rgai.isAnalyzing ? FluxForgeTheme.accentYellow : FluxForgeTheme.accentPurple),
                              const SizedBox(width: 4),
                              Text(rgai.isAnalyzing ? 'Analyzing...' : 'Run Analysis',
                                style: TextStyle(fontFamily: 'monospace', fontSize: 8,
                                  color: rgai.isAnalyzing ? FluxForgeTheme.accentYellow : FluxForgeTheme.accentPurple)),
                            ]),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (summary != null)
                          Text('${summary.passedAssets}/${summary.totalAssets}', style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textTertiary)),
                      ]),
                      const SizedBox(height: 8),
                      _IntelRow('Stimulation index',
                        stimPass ? 'PASS' : 'FAIL',
                        stimPass ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed),
                      _IntelRow('Near-miss exposure',
                        nearMissOk ? 'OK' : 'WARN',
                        nearMissOk ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentYellow),
                      _IntelRow('Risk level',
                        neuro.riskLevel.name.toUpperCase(),
                        neuro.riskLevel == PlayerRiskLevel.low ? FluxForgeTheme.accentGreen
                          : neuro.riskLevel == PlayerRiskLevel.high ? FluxForgeTheme.accentRed
                          : FluxForgeTheme.accentYellow),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Right: Engagement score — real NeuroAudio data
        Flexible(
          flex: 2,
          child: _DockCard(
            accent: FluxForgeTheme.accentPurple,
            child: Column(
              children: [
                _DockLabel('ENGAGEMENT SCORE', color: FluxForgeTheme.accentPurple),
                const Spacer(),
                Text(score.toStringAsFixed(1),
                  style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 40,
                    color: FluxForgeTheme.accentBlue, fontWeight: FontWeight.w300)),
                Text('/ 10.0 — ${_engagementLabel(score)}',
                  style: const TextStyle(
                    fontSize: 9, color: FluxForgeTheme.textTertiary,
                    letterSpacing: 0.05)),
                const Spacer(),
                // 4 real mini metrics from NeuroAudioProvider — 2×2 Row layout
                Row(children: [
                  Expanded(child: _MiniMetric('$retention%', 'Retention', FluxForgeTheme.accentBlue)),
                  const SizedBox(width: 4),
                  Expanded(child: _MiniMetric(dwell, 'Session', FluxForgeTheme.accentPurple)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: _MiniMetric(losses, 'Loss streak', FluxForgeTheme.accentOrange)),
                  const SizedBox(width: 4),
                  Expanded(child: _MiniMetric(fatigueIdx, 'Fatigue idx', FluxForgeTheme.accentGreen)),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _engagementLabel(double s) {
    if (s >= 8) return 'HIGH ENGAGEMENT';
    if (s >= 5) return 'MODERATE';
    return 'LOW';
  }
}
