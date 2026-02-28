import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/energy_governance_provider.dart';

/// Energy Budget Bar — per-domain energy cap visualization.
/// Shows 5 horizontal bars (Dynamic, Transient, Spatial, Harmonic, Temporal)
/// with overall cap, SM factor, and voice budget.
class EnergyBudgetBar extends StatefulWidget {
  const EnergyBudgetBar({super.key});

  @override
  State<EnergyBudgetBar> createState() => _EnergyBudgetBarState();
}

class _EnergyBudgetBarState extends State<EnergyBudgetBar> {
  late final EnergyGovernanceProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<EnergyGovernanceProvider>();
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

  static const _domainColors = [
    Color(0xFF4FC3F7), // Dynamic — blue
    Color(0xFFFF7043), // Transient — orange
    Color(0xFF66BB6A), // Spatial — green
    Color(0xFFAB47BC), // Harmonic — purple
    Color(0xFFFFCA28), // Temporal — amber
  ];

  @override
  Widget build(BuildContext context) {
    final caps = _provider.domainCaps;
    final overall = _provider.overallCap;
    final sm = _provider.sessionMemorySM;
    final profile = _provider.activeProfile;
    final voiceMax = _provider.voiceBudgetMax;
    final voiceRatio = _provider.voiceBudgetRatio;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.bolt, size: 14, color: Color(0xFFFFCA28)),
              const SizedBox(width: 4),
              Text(
                'Energy Budget',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _chip(profile.displayName, const Color(0xFF4FC3F7)),
              const SizedBox(width: 4),
              _chip('SM ${sm.toStringAsFixed(2)}',
                  sm < 0.85 ? const Color(0xFFFF7043) : const Color(0xFF66BB6A)),
            ],
          ),
          const SizedBox(height: 6),
          // Domain bars
          for (int i = 0; i < 5; i++)
            _domainBar(EnergyDomain.values[i].displayName, caps[i], _domainColors[i]),
          const SizedBox(height: 4),
          // Overall + Voice budget
          Row(
            children: [
              Text(
                'Overall: ${(overall * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
              const Spacer(),
              Text(
                'Voices: $voiceMax (${(voiceRatio * 100).toStringAsFixed(0)}%)',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          // Session indicators
          if (_provider.featureStormActive || _provider.jackpotCompressionActive || _provider.lossStreak > 5)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (_provider.lossStreak > 5)
                    _indicator('Loss ×${_provider.lossStreak}', const Color(0xFFEF5350)),
                  if (_provider.featureStormActive)
                    _indicator('Feature Storm', const Color(0xFFFF9800)),
                  if (_provider.jackpotCompressionActive)
                    _indicator('JP Compress', const Color(0xFF7E57C2)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _domainBar(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 9,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(4),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              '${(value * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 9,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _indicator(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
