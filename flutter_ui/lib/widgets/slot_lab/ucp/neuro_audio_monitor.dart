import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/slot_lab/neuro_audio_provider.dart';

/// UCP-9: NeuroAudio™ Monitor — Player Behavioral Adaptation Dashboard
///
/// Displays the 8D emotional state vector, risk level, and audio adaptation
/// parameters in real-time. All values from [NeuroAudioProvider].
class NeuroAudioMonitor extends StatefulWidget {
  const NeuroAudioMonitor({super.key});

  @override
  State<NeuroAudioMonitor> createState() => _NeuroAudioMonitorState();
}

class _NeuroAudioMonitorState extends State<NeuroAudioMonitor> {
  NeuroAudioProvider? _provider;

  @override
  void initState() {
    super.initState();
    try {
      _provider = GetIt.instance<NeuroAudioProvider>();
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
    final p = _provider;
    if (p == null) {
      return const Center(
        child: Text('NeuroAudio not available', style: TextStyle(color: Colors.grey)),
      );
    }

    final out = p.output;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Header ──────────────────────────────────────────────────
        Row(
          children: [
            Icon(Icons.psychology, color: Color(out.riskLevel.colorValue), size: 16),
            const SizedBox(width: 6),
            const Text(
              'NeuroAudio',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            _riskBadge(out.riskLevel),
            const SizedBox(width: 8),
            _toggleButton(p),
          ],
        ),
        const SizedBox(height: 8),

        // ─── 8D State Vector ─────────────────────────────────────────
        _sectionLabel('Player State'),
        const SizedBox(height: 4),
        _bar('Arousal', out.arousal, const Color(0xFFFF6633)),
        _bar('Valence', (out.valence + 1.0) / 2.0, const Color(0xFF44CC44)),
        _bar('Engagement', out.engagement, const Color(0xFF4488CC)),
        _bar('Flow Depth', out.flowDepth, const Color(0xFF8866CC)),
        _bar('Frustration', out.frustration, const Color(0xFFCC3333)),
        _bar('Risk Tolerance', out.riskTolerance, const Color(0xFFDD8822)),
        _bar('Churn Predict', out.churnPrediction, const Color(0xFFAA4444)),
        _bar('Session Fatigue', out.sessionFatigue, const Color(0xFF666688)),

        const SizedBox(height: 10),

        // ─── Audio Adaptation ────────────────────────────────────────
        _sectionLabel('Audio Adaptation'),
        const SizedBox(height: 4),
        _modBar('Tempo', out.tempoModifier, 0.7, 1.3, const Color(0xFF44AACC)),
        _modBar('Reverb', out.reverbDepthModifier, 0.5, 2.0, const Color(0xFF6688BB)),
        _modBar('Compression', out.compressionModifier, 0.5, 2.0, const Color(0xFF88AA44)),
        _modBar('Win Magnitude', out.winSoundMagnitude, 0.3, 1.5, const Color(0xFFFFCC00)),
        _modBar('Near-Miss', out.nearMissTension, 0.0, 1.0, const Color(0xFFDD8822)),
        _modBar('Volume Scale', out.volumeEnvelopeScale, 0.5, 1.0, const Color(0xFF888888)),

        const SizedBox(height: 8),

        // ─── Stats ───────────────────────────────────────────────────
        Row(
          children: [
            _stat('Spins', '${p.totalSpins}'),
            _stat('Losses', '${p.consecutiveLosses}'),
            _stat('Session', '${p.sessionDurationMinutes.toStringAsFixed(1)}m'),
          ],
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      );

  Widget _bar(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: value.clamp(0.0, 1.0),
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              (value * 100).toStringAsFixed(0),
              textAlign: TextAlign.right,
              style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modBar(String label, double value, double min, double max, Color color) {
    final normalized = max > min ? (value - min) / (max - min) : 0.0;
    final neutral = max > min ? (1.0 - min) / (max - min) : 0.5;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 6,
              child: CustomPaint(
                painter: _ModBarPainter(
                  value: normalized.clamp(0.0, 1.0),
                  neutral: neutral.clamp(0.0, 1.0),
                  color: color,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '${value.toStringAsFixed(2)}x',
              textAlign: TextAlign.right,
              style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _riskBadge(PlayerRiskLevel level) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Color(level.colorValue).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Color(level.colorValue).withValues(alpha: 0.4)),
      ),
      child: Text(
        level.displayName,
        style: TextStyle(
          color: Color(level.colorValue),
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _toggleButton(NeuroAudioProvider provider) {
    return GestureDetector(
      onTap: () => provider.setEnabled(!provider.enabled),
      child: Icon(
        provider.enabled ? Icons.visibility : Icons.visibility_off,
        color: provider.enabled ? Colors.white54 : Colors.white24,
        size: 14,
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
        ],
      ),
    );
  }
}

/// Custom painter for modifier bar with neutral point indicator
class _ModBarPainter extends CustomPainter {
  final double value;
  final double neutral;
  final Color color;

  _ModBarPainter({required this.value, required this.neutral, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = Colors.white10;
    final barPaint = Paint()..color = color;
    final neutralPaint = Paint()..color = Colors.white30;
    final r = Radius.circular(size.height / 2);

    // Background
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), bgPaint);

    // Value bar (from neutral point)
    final neutralX = neutral * size.width;
    final valueX = value * size.width;
    final left = valueX < neutralX ? valueX : neutralX;
    final right = valueX < neutralX ? neutralX : valueX;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(left, 0, right, size.height), r),
      barPaint,
    );

    // Neutral marker
    canvas.drawRect(
      Rect.fromLTWH(neutralX - 0.5, 0, 1.0, size.height),
      neutralPaint,
    );
  }

  @override
  bool shouldRepaint(_ModBarPainter old) =>
      old.value != value || old.neutral != neutral || old.color != color;
}
