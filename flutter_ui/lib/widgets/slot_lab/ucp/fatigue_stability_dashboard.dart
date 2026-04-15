import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/aurexis_provider.dart';

/// UCP-5: Fatigue/Stability Dashboard
///
/// Displays fatigue index, session drift, and peak session duration.
/// All values are live from [AurexisProvider] — zero hardcoding.
class FatigueStabilityDashboard extends StatefulWidget {
  const FatigueStabilityDashboard({super.key});

  @override
  State<FatigueStabilityDashboard> createState() => _FatigueStabilityDashboardState();
}

class _FatigueStabilityDashboardState extends State<FatigueStabilityDashboard> {
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

  /// Fatigue index 0.0–1.0 from AUREXIS psychoacoustic fatigue model
  double get _fatigue => _provider?.parameters.fatigueIndex ?? 0.0;

  /// Session pan drift — absolute displacement 0.0–1.0
  double get _drift => (_provider?.parameters.panDrift ?? 0.0).abs().clamp(0.0, 1.0);

  /// Peak session duration in minutes (max 240 min = 4h)
  double get _peakMinutes =>
      ((_provider?.parameters.sessionDurationS ?? 0.0) / 60.0).clamp(0.0, 240.0);

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
          _buildMetrics(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.monitor_heart, size: 12, color: Color(0xFFFFB74D)),
        const SizedBox(width: 4),
        Text(
          'Fatigue / Stability',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildMetrics() {
    return Row(
      children: [
        _gauge('Fatigue', _fatigue, 1.0, const Color(0xFFFFB74D)),
        const SizedBox(width: 6),
        _gauge('Drift', _drift, 1.0, const Color(0xFF42A5F5)),
        const SizedBox(width: 6),
        _gauge('Peak', _peakMinutes, 240.0, const Color(0xFFEF5350)),
      ],
    );
  }

  Widget _gauge(String label, double value, double max, Color color) {
    final ratio = max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;
    final displayText = label == 'Peak'
        ? '${value.toStringAsFixed(0)}m'
        : value.toStringAsFixed(2);

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 28, height: 28,
                child: CircularProgressIndicator(
                  value: ratio,
                  strokeWidth: 2.5,
                  backgroundColor: Colors.white.withOpacity(0.06),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Text(
                displayText,
                style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 7)),
        ],
      ),
    );
  }
}
