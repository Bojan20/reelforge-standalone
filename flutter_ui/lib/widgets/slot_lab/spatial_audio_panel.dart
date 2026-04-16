import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/slot_lab/neuro_audio_provider.dart';

/// NeuroAudio™ Spatial Panel — 8D Emotional State Visualizer.
///
/// Reads REAL data from NeuroAudioProvider:
/// - 8D emotional state vector (arousal, valence, risk, engagement, churn, frustration, flow, fatigue)
/// - Audio adaptation parameters (tempo, reverb, compression, win magnitude, etc.)
/// - Player risk level classification
/// - Behavioral signal history (click velocity, pause, bet, win/loss, near-miss)
class SpatialAudioPanel extends StatefulWidget {
  const SpatialAudioPanel({super.key});

  @override
  State<SpatialAudioPanel> createState() => _SpatialAudioPanelState();
}

class _SpatialAudioPanelState extends State<SpatialAudioPanel> {
  late final NeuroAudioProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<NeuroAudioProvider>();
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          Expanded(child: _buildContent()),
          const SizedBox(height: 6),
          _buildRtpcBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final risk = _provider.riskLevel;
    final riskColor = Color(risk.colorValue);

    return Row(
      children: [
        const Icon(Icons.psychology, size: 14, color: Color(0xFF40C8FF)),
        const SizedBox(width: 4),
        Text(
          'NeuroAudio™',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        // Risk level badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: riskColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: riskColor.withValues(alpha: 0.4)),
          ),
          child: Text(
            risk.displayName,
            style: TextStyle(
              color: riskColor,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Spacer(),
        // Enable/disable toggle
        GestureDetector(
          onTap: () => _provider.setEnabled(!_provider.enabled),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (_provider.enabled ? const Color(0xFF4CAF50) : const Color(0xFF3A3A5C))
                  .withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              _provider.enabled ? 'ON' : 'OFF',
              style: TextStyle(
                color: _provider.enabled ? const Color(0xFF4CAF50) : Colors.white54,
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final o = _provider.output;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 8D Emotional State Vector
          _buildSectionTitle('8D Emotional State'),
          const SizedBox(height: 6),
          _buildStateBar('Arousal', o.arousal, 0.0, 1.0, _arousalColor(o.arousal)),
          _buildStateBar('Valence', o.valence, -1.0, 1.0, _valenceColor(o.valence)),
          _buildStateBar('Risk Tolerance', o.riskTolerance, 0.0, 1.0, _riskColor(o.riskTolerance)),
          _buildStateBar('Engagement', o.engagement, 0.0, 1.0, const Color(0xFF40C8FF)),
          _buildStateBar('Churn Predict', o.churnPrediction, 0.0, 1.0, _churnColor(o.churnPrediction)),
          _buildStateBar('Frustration', o.frustration, 0.0, 1.0, _frustrationColor(o.frustration)),
          _buildStateBar('Flow Depth', o.flowDepth, 0.0, 1.0, const Color(0xFF7C4DFF)),
          _buildStateBar('Session Fatigue', o.sessionFatigue, 0.0, 1.0, _fatigueColor(o.sessionFatigue)),

          const SizedBox(height: 10),

          // Audio adaptation parameters
          _buildSectionTitle('Audio Adaptation'),
          const SizedBox(height: 6),
          _buildParamRow('Tempo', o.tempoModifier, '${(o.tempoModifier * 100 - 100).toStringAsFixed(0)}%'),
          _buildParamRow('Reverb Depth', o.reverbDepthModifier, 'x${o.reverbDepthModifier.toStringAsFixed(2)}'),
          _buildParamRow('Compression', o.compressionModifier, 'x${o.compressionModifier.toStringAsFixed(2)}'),
          _buildParamRow('Win Magnitude', o.winSoundMagnitude, 'x${o.winSoundMagnitude.toStringAsFixed(2)}'),
          _buildParamRow('Near-miss Tension', o.nearMissTension, o.nearMissTension.toStringAsFixed(2)),
          _buildParamRow('Volume Envelope', o.volumeEnvelopeScale, 'x${o.volumeEnvelopeScale.toStringAsFixed(2)}'),

          const SizedBox(height: 10),

          // Session info
          _buildSectionTitle('Session'),
          const SizedBox(height: 4),
          _buildInfoRow('Total Spins', '${_provider.totalSpins}'),
          _buildInfoRow('Session Duration', '${_provider.sessionDurationMinutes.toStringAsFixed(1)} min'),
          _buildInfoRow('Consecutive Losses', '${_provider.consecutiveLosses}'),
          _buildInfoRow('RG Mode', _provider.responsibleGamingMode ? 'Active' : 'Disabled'),
        ],
      ),
    );
  }

  Widget _buildStateBar(String label, double value, double min, double max, Color color) {
    final normalized = max > min ? (value - min) / (max - min) : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 85,
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9),
            ),
          ),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A4A),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Stack(
                children: [
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: normalized.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 34,
            child: Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 8,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParamRow(String label, double value, String display) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9)),
          ),
          Expanded(
            child: Text(
              display,
              style: TextStyle(
                color: const Color(0xFF40C8FF).withValues(alpha: 0.8),
                fontSize: 9,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 9)),
          ),
          Text(value,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildRtpcBar() {
    final o = _provider.output;
    // Quick-glance RTPC status bar
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildMiniGauge('A', o.arousal, _arousalColor(o.arousal)),
          _buildMiniGauge('V', (o.valence + 1) / 2, _valenceColor(o.valence)),
          _buildMiniGauge('E', o.engagement, const Color(0xFF40C8FF)),
          _buildMiniGauge('F', o.flowDepth, const Color(0xFF7C4DFF)),
          _buildMiniGauge('R', o.riskTolerance, _riskColor(o.riskTolerance)),
          _buildMiniGauge('C', o.churnPrediction, _churnColor(o.churnPrediction)),
        ],
      ),
    );
  }

  Widget _buildMiniGauge(String label, double value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            value: value.clamp(0.0, 1.0),
            strokeWidth: 2.5,
            backgroundColor: const Color(0xFF2A2A4A),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 8, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.8),
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  // Color helpers
  Color _arousalColor(double v) =>
      v > 0.7 ? const Color(0xFFFF5252) : v > 0.4 ? const Color(0xFFFFBB33) : const Color(0xFF4CAF50);
  Color _valenceColor(double v) =>
      v > 0.3 ? const Color(0xFF4CAF50) : v < -0.3 ? const Color(0xFFFF5252) : const Color(0xFFFFBB33);
  Color _riskColor(double v) =>
      v > 0.7 ? const Color(0xFFFF5252) : v > 0.4 ? const Color(0xFFFFBB33) : const Color(0xFF4CAF50);
  Color _churnColor(double v) =>
      v > 0.6 ? const Color(0xFFFF5252) : v > 0.3 ? const Color(0xFFFFBB33) : const Color(0xFF4CAF50);
  Color _frustrationColor(double v) =>
      v > 0.6 ? const Color(0xFFFF5252) : v > 0.3 ? const Color(0xFFFFBB33) : const Color(0xFF4CAF50);
  Color _fatigueColor(double v) =>
      v > 0.7 ? const Color(0xFFFF5252) : v > 0.4 ? const Color(0xFFFFBB33) : const Color(0xFF4CAF50);
}
