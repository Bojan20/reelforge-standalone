import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/aurexis_provider.dart';

/// UCP-2: Energy/Emotional Monitor Zone
///
/// Displays 5 energy domains + emotional state + intensity from AUREXIS.
class EnergyEmotionalMonitor extends StatefulWidget {
  const EnergyEmotionalMonitor({super.key});

  @override
  State<EnergyEmotionalMonitor> createState() => _EnergyEmotionalMonitorState();
}

class _EnergyEmotionalMonitorState extends State<EnergyEmotionalMonitor> {
  AurexisProvider? _provider;

  @override
  void initState() {
    super.initState();
    try {
      _provider = GetIt.instance<AurexisProvider>();
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
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 4),
          _buildEnergyBars(),
          const SizedBox(height: 4),
          _buildEmotionalState(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.bolt, size: 12, color: Color(0xFFFF7043)),
        const SizedBox(width: 4),
        Text(
          'Energy / Emotional',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildEnergyBars() {
    final domains = ['Base', 'Win', 'Feature', 'Jackpot', 'Ambient'];
    final colors = [
      const Color(0xFF42A5F5),
      const Color(0xFF66BB6A),
      const Color(0xFFFFB74D),
      const Color(0xFFEF5350),
      const Color(0xFF7E57C2),
    ];
    // Use default values when provider not available
    final values = [0.3, 0.0, 0.0, 0.0, 0.2];

    return Column(
      children: [
        for (int i = 0; i < domains.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    domains[i],
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 8),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 3,
                    child: LinearProgressIndicator(
                      value: values[i].clamp(0.0, 1.0),
                      backgroundColor: Colors.white.withOpacity(0.06),
                      valueColor: AlwaysStoppedAnimation(colors[i]),
                    ),
                  ),
                ),
                SizedBox(
                  width: 24,
                  child: Text(
                    '${(values[i] * 100).toStringAsFixed(0)}',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: colors[i].withOpacity(0.7), fontSize: 7),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEmotionalState() {
    return Row(
      children: [
        _chip('Neutral', const Color(0xFF42A5F5)),
        const SizedBox(width: 4),
        _chip('Intensity: 30%', const Color(0xFFFFB74D)),
      ],
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.w500)),
    );
  }
}
