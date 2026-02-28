import 'package:flutter/material.dart';

/// UCP-5: Fatigue/Stability Dashboard
///
/// Displays fatigue index, session drift, and peak duration metrics.
class FatigueStabilityDashboard extends StatelessWidget {
  const FatigueStabilityDashboard({super.key});

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
        _gauge('Fatigue', 0.0, 0.9, const Color(0xFFFFB74D)),
        const SizedBox(width: 6),
        _gauge('Drift', 0.0, 1.0, const Color(0xFF42A5F5)),
        const SizedBox(width: 6),
        _gauge('Peak', 0, 240, const Color(0xFFEF5350)),
      ],
    );
  }

  Widget _gauge(String label, num value, num max, Color color) {
    final ratio = max > 0 ? (value / max).clamp(0.0, 1.0).toDouble() : 0.0;
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
                value is double ? value.toStringAsFixed(1) : '$value',
                style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w600),
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
