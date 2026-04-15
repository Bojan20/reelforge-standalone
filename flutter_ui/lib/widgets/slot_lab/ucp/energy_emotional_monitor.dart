import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/aurexis_provider.dart';

/// UCP-2: Energy/Emotional Monitor Zone
///
/// Displays 5 energy domains + emotional state + intensity from AUREXIS.
/// All values are live from [AurexisProvider] — zero hardcoding.
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

  // ═══ AUREXIS → Energy domain mappings ═══

  /// Base energy: core audio density from AUREXIS engine
  double get _baseEnergy => _provider?.parameters.energyDensity ?? 0.3;

  /// Win energy: win multiplier normalized 0–20x → 0–1
  double get _winEnergy =>
      ((_provider?.winMultiplier ?? 0.0).clamp(0.0, 20.0) / 20.0);

  /// Feature energy: escalation above neutral (1.0 = neutral, 4.0 = max)
  double get _featureEnergy =>
      ((_provider?.parameters.escalationMultiplier ?? 1.0) - 1.0).clamp(0.0, 3.0) / 3.0;

  /// Jackpot energy: proximity to jackpot trigger 0–1
  double get _jackpotEnergy => _provider?.jackpotProximity ?? 0.0;

  /// Ambient energy: reverb/spatial depth 0–1
  double get _ambientEnergy =>
      (_provider?.parameters.reverbSendBias ?? 0.2).clamp(0.0, 1.0);

  List<double> get _energyValues => [
    _baseEnergy,
    _winEnergy,
    _featureEnergy,
    _jackpotEnergy,
    _ambientEnergy,
  ];

  // ═══ Emotional state derivation ═══

  String get _emotionalState {
    final p = _provider?.parameters;
    final fatigue = p?.fatigueIndex ?? 0.0;
    final jackpot = _provider?.jackpotProximity ?? 0.0;
    final win = _provider?.winMultiplier ?? 0.0;
    final escalation = p?.escalationMultiplier ?? 1.0;

    if (fatigue > 0.75) return 'Fatigued';
    if (win > 10.0) return 'Euphoric';
    if (jackpot > 0.8) return 'Excited';
    if (escalation > 2.5) return 'Hyped';
    if (fatigue > 0.45) return 'Tired';
    if (win > 2.0 || jackpot > 0.4) return 'Engaged';
    return 'Neutral';
  }

  Color get _stateColor {
    switch (_emotionalState) {
      case 'Euphoric': return const Color(0xFFFFD700);
      case 'Excited':  return const Color(0xFFEF5350);
      case 'Hyped':    return const Color(0xFFFF7043);
      case 'Engaged':  return const Color(0xFF66BB6A);
      case 'Tired':    return const Color(0xFF90A4AE);
      case 'Fatigued': return const Color(0xFFB0BEC5);
      default:         return const Color(0xFF42A5F5);
    }
  }

  /// Intensity: escalation above 1.0 mapped to 0–100%
  int get _intensityPct {
    final esc = _provider?.parameters.escalationMultiplier ?? 1.0;
    return ((esc - 1.0).clamp(0.0, 3.0) / 3.0 * 100).round();
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
    const domains = ['Base', 'Win', 'Feature', 'Jackpot', 'Ambient'];
    const colors = [
      Color(0xFF42A5F5),
      Color(0xFF66BB6A),
      Color(0xFFFFB74D),
      Color(0xFFEF5350),
      Color(0xFF7E57C2),
    ];
    final values = _energyValues;

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
        _chip(_emotionalState, _stateColor),
        const SizedBox(width: 4),
        _chip('Intensity: $_intensityPct%', const Color(0xFFFFB74D)),
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
