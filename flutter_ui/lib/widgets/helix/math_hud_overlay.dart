/// MathHudOverlay — SPRINT 1 SPEC-10.
///
/// Floating compact HUD on the HELIX Neural Canvas showing live math
/// metrics: target RTP, volatility, hit frequency, max win.
///
/// Always visible while the user works in FLOW / AUDIO / TIMELINE tabs —
/// the values that define the slot's character should not require a tab
/// switch to MATH to read.
///
/// Tap the HUD to collapse / expand.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/slot_lab_project_provider.dart';
import '../../services/gdd_import_service.dart';
import '../../theme/fluxforge_theme.dart';
import '../common/flux_tooltip.dart';

class MathHudOverlay extends StatefulWidget {
  const MathHudOverlay({super.key});

  @override
  State<MathHudOverlay> createState() => _MathHudOverlayState();
}

class _MathHudOverlayState extends State<MathHudOverlay> {
  bool _collapsed = false;

  // Volatility string → 0..10 numeric scale (industry common mapping).
  double _volatilityScore(String v) {
    switch (v.toLowerCase()) {
      case 'low': return 2.5;
      case 'medium': return 5.0;
      case 'high': return 7.5;
      case 'very_high':
      case 'extreme': return 9.0;
      default: return 5.0;
    }
  }

  // Hit frequency 0..1 → "1:N.N" string (slot vendor convention).
  String _formatHitFreq(double hitFreq) {
    if (hitFreq <= 0) return '1:∞';
    final ratio = 1.0 / hitFreq;
    return '1:${ratio.toStringAsFixed(1)}';
  }

  // Max multiplier from GDD win tiers — find the highest tier maxX.
  double _maxMultiplier(List<GddWinTier> tiers) {
    if (tiers.isEmpty) return 0.0;
    double max = 0.0;
    for (final t in tiers) {
      if (t.maxMultiplier > max) max = t.maxMultiplier;
    }
    return max;
  }

  // Color for a metric chip dot based on whether the value is "in target".
  Color _statusColor({
    required double value,
    required double target,
    double tolerancePct = 5.0,
  }) {
    if (target == 0.0) return FluxForgeTheme.brandGold;
    final deltaPct = ((value - target).abs() / target) * 100.0;
    if (deltaPct <= tolerancePct) return FluxForgeTheme.brandGold;
    if (deltaPct <= tolerancePct * 2) return FluxForgeTheme.accentOrange;
    return FluxForgeTheme.accentRed;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SlotLabProjectProvider>(
      builder: (context, provider, _) {
        final gdd = provider.importedGdd;
        final math = gdd?.math;

        // Defaults if no GDD imported yet
        final targetRtp = provider.targetRtp; // % (96.0 default)
        final liveRtp = provider.sessionStats.rtp; // % from session
        final volatilityStr = math?.volatility ?? 'medium';
        final volScore = _volatilityScore(volatilityStr);
        final hitFreq = math?.hitFrequency ?? 0.25;
        final maxX = _maxMultiplier(math?.winTiers ?? const []);

        // Use live RTP if any spins recorded, otherwise show target
        final hasSession = provider.sessionStats.totalSpins > 0;
        final rtpValue = hasSession ? liveRtp : targetRtp;
        final rtpColor = hasSession
            ? _statusColor(value: liveRtp, target: targetRtp, tolerancePct: 5.0)
            : FluxForgeTheme.brandGold;

        // The caller is responsible for positioning the HUD inside a Stack
        // (typically Positioned top-left of Neural Canvas).
        return GestureDetector(
            onTap: () => setState(() => _collapsed = !_collapsed),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: const Color(0xF20D0D12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: FluxForgeTheme.brandGold.withValues(alpha: 0.18),
                  width: 0.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: _collapsed
                    ? _buildCollapsed()
                    : _buildExpanded(
                        rtpValue: rtpValue,
                        rtpColor: rtpColor,
                        hasSession: hasSession,
                        targetRtp: targetRtp,
                        volScore: volScore,
                        volatilityStr: volatilityStr,
                        hitFreq: hitFreq,
                        maxX: maxX,
                      ),
              ),
            ),
          );
      },
    );
  }

  Widget _buildCollapsed() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.functions_rounded,
          size: 13,
          color: FluxForgeTheme.brandGoldBright.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 4),
        const Text(
          'MATH',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: FluxForgeTheme.brandGoldBright,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildExpanded({
    required double rtpValue,
    required Color rtpColor,
    required bool hasSession,
    required double targetRtp,
    required double volScore,
    required String volatilityStr,
    required double hitFreq,
    required double maxX,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chip(
          label: 'RTP',
          value: '${rtpValue.toStringAsFixed(1)}%',
          dot: rtpColor,
          tooltip: hasSession
              ? 'Live RTP from session — target ${targetRtp.toStringAsFixed(1)}%'
              : 'Target RTP from GDD math model',
        ),
        const SizedBox(width: 6),
        _chip(
          label: 'VOL',
          value: volScore.toStringAsFixed(1),
          dot: FluxForgeTheme.brandGold,
          tooltip: 'Volatility: ${volatilityStr.toUpperCase()} (${volScore.toStringAsFixed(1)}/10)',
        ),
        const SizedBox(width: 6),
        _chip(
          label: 'HIT',
          value: _formatHitFreq(hitFreq),
          dot: FluxForgeTheme.brandGold,
          tooltip: 'Hit frequency — ${(hitFreq * 100).toStringAsFixed(1)}% of spins win',
        ),
        const SizedBox(width: 6),
        _chip(
          label: 'MAX',
          value: maxX > 0 ? '${maxX.toStringAsFixed(0)}×' : '—',
          dot: FluxForgeTheme.brandGold,
          tooltip: maxX > 0
              ? 'Max win multiplier from highest GDD win tier'
              : 'No GDD win tiers defined yet',
        ),
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Icon(
            Icons.expand_less_rounded,
            size: 12,
            color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _chip({
    required String label,
    required String value,
    required Color dot,
    required String tooltip,
  }) {
    return FluxTooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF14141C),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: FluxForgeTheme.brandGoldDark.withValues(alpha: 0.35),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: FluxForgeTheme.textTertiary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              value,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: FluxForgeTheme.textPrimary,
                fontFamily: 'JetBrainsMono',
                height: 1.0,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 5, height: 5,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: dot.withValues(alpha: 0.6),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
