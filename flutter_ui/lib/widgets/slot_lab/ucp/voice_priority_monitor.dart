import 'package:flutter/material.dart';

/// UCP-3: Voice/Priority Monitor Zone
///
/// Displays active voice count, priority scores, and survival status.
class VoicePriorityMonitor extends StatelessWidget {
  const VoicePriorityMonitor({super.key});

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
          _buildVoiceMetrics(),
          const SizedBox(height: 4),
          _buildPriorityList(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.graphic_eq, size: 12, color: Color(0xFF66BB6A)),
        const SizedBox(width: 4),
        Text(
          'Voice / Priority',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceMetrics() {
    return Row(
      children: [
        _metric('Active', '0', const Color(0xFF66BB6A)),
        const SizedBox(width: 8),
        _metric('Budget', '48', const Color(0xFF42A5F5)),
        const SizedBox(width: 8),
        _metric('Stolen', '0', const Color(0xFFEF5350)),
        const SizedBox(width: 8),
        _metric('Util', '0%', Colors.white.withOpacity(0.5)),
      ],
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 7)),
      ],
    );
  }

  Widget _buildPriorityList() {
    return Container(
      height: 20,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: Text(
          'Voice priority scores during playback',
          style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 8),
        ),
      ),
    );
  }
}
