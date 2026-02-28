import 'package:flutter/material.dart';
import '../aurexis_theme.dart';

/// Win escalation parameter stack visualizer.
///
/// Shows the 5 escalation parameters (width, harmonics, reverb, sub, transient)
/// as horizontal bars with current values and saturation indicators.
class WinEscalationViz extends StatelessWidget {
  final double stereoWidth;
  final double harmonicExcitation;
  final double reverbTailExtensionMs;
  final double subReinforcementDb;
  final double transientSharpness;
  final double escalationMultiplier;
  final double height;

  const WinEscalationViz({
    super.key,
    this.stereoWidth = 1.0,
    this.harmonicExcitation = 1.0,
    this.reverbTailExtensionMs = 0.0,
    this.subReinforcementDb = 0.0,
    this.transientSharpness = 1.0,
    this.escalationMultiplier = 1.0,
    this.height = 100,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = escalationMultiplier > 1.01;

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text('Win Escalation', style: AurexisTextStyles.paramLabel),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isActive
                      ? AurexisColors.dynamics.withValues(alpha: 0.15)
                      : AurexisColors.bgSlider,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  isActive ? '${escalationMultiplier.toStringAsFixed(1)}x' : 'IDLE',
                  style: AurexisTextStyles.badge.copyWith(
                    color: isActive ? AurexisColors.dynamics : AurexisColors.textLabel,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Parameter bars
          _buildEscBar('Width', stereoWidth, 0.5, 2.0, '${stereoWidth.toStringAsFixed(2)}x'),
          _buildEscBar('Harmonics', harmonicExcitation, 0.5, 2.0, '${harmonicExcitation.toStringAsFixed(2)}x'),
          _buildEscBar('Reverb', reverbTailExtensionMs, 0, 2000, '+${reverbTailExtensionMs.toStringAsFixed(0)}ms'),
          _buildEscBar('Sub', subReinforcementDb, 0, 12, '+${subReinforcementDb.toStringAsFixed(1)}dB'),
          _buildEscBar('Transient', transientSharpness, 0.5, 2.0, '${transientSharpness.toStringAsFixed(2)}x'),
        ],
      ),
    );
  }

  Widget _buildEscBar(String label, double value, double min, double max, String display) {
    final normalized = max > min ? ((value - min) / (max - min)).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: SizedBox(
        height: 14,
        child: Row(
          children: [
            SizedBox(
              width: 55,
              child: Text(label, style: AurexisTextStyles.badge.copyWith(color: AurexisColors.textLabel)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(1),
                child: SizedBox(
                  height: 4,
                  child: Stack(
                    children: [
                      Container(color: AurexisColors.bgSlider),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: normalized,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AurexisColors.dynamics.withValues(alpha: 0.5),
                                AurexisColors.dynamics,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 45,
              child: Text(
                display,
                style: AurexisTextStyles.badge.copyWith(
                  color: normalized > 0.5 ? AurexisColors.dynamics : AurexisColors.textLabel,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
