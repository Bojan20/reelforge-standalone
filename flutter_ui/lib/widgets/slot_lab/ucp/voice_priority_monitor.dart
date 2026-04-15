import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/subsystems/voice_pool_provider.dart';

/// UCP-3: Voice/Priority Monitor Zone
///
/// Displays active voice count, priority scores, and survival status.
/// All values are live from [VoicePoolProvider] — zero hardcoding.
class VoicePriorityMonitor extends StatefulWidget {
  const VoicePriorityMonitor({super.key});

  @override
  State<VoicePriorityMonitor> createState() => _VoicePriorityMonitorState();
}

class _VoicePriorityMonitorState extends State<VoicePriorityMonitor> {
  VoicePoolProvider? _provider;

  @override
  void initState() {
    super.initState();
    try {
      _provider = GetIt.instance<VoicePoolProvider>();
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
    final active = _provider?.engineActiveCount ?? 0;
    final budget = _provider?.engineMaxVoices ?? 48;
    final stolen = _provider?.stealCount ?? 0;
    final util = _provider != null
        ? _provider!.engineUtilization.clamp(0.0, 100.0)
        : 0.0;

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
          _buildVoiceMetrics(active, budget, stolen, util),
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

  Widget _buildVoiceMetrics(int active, int budget, int stolen, double util) {
    // Color-code active voices: green < 60%, amber 60-85%, red > 85%
    final activeColor = util > 85
        ? const Color(0xFFEF5350)
        : util > 60
            ? Colors.amber
            : const Color(0xFF66BB6A);

    return Row(
      children: [
        _metric('Active', '$active', activeColor),
        const SizedBox(width: 8),
        _metric('Budget', '$budget', const Color(0xFF42A5F5)),
        const SizedBox(width: 8),
        _metric('Stolen', '$stolen',
            stolen > 0 ? const Color(0xFFEF5350) : Colors.white.withOpacity(0.3)),
        const SizedBox(width: 8),
        _metric('Util', '${util.toStringAsFixed(0)}%',
            activeColor),
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
    if (_provider == null) {
      return _placeholderBox('Voice priority — no provider');
    }

    // Show per-bus voice breakdown
    final busData = <String, int>{
      'SFX': _provider!.sfxVoices,
      'Music': _provider!.musicVoices,
      'VO': _provider!.voiceVoices,
      'Amb': _provider!.ambienceVoices,
      'Aux': _provider!.auxVoices,
    };

    final hasActivity = busData.values.any((v) => v > 0);
    if (!hasActivity) {
      return _placeholderBox('Voice priority scores during playback');
    }

    return SizedBox(
      height: 20,
      child: Row(
        children: busData.entries
            .where((e) => e.value > 0)
            .map((e) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${e.key}:${e.value}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 8,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _placeholderBox(String text) {
    return Container(
      height: 20,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 8),
        ),
      ),
    );
  }
}
