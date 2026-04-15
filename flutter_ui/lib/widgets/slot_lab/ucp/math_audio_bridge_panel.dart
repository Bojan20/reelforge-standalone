import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/slot_lab/math_audio_bridge_provider.dart';

/// UCP-10: MathAudio Bridge™ Panel — Math Model → Audio Map Dashboard
///
/// Displays imported math model, generated audio event map,
/// tier distribution, simulation results, and dry spell analysis.
class MathAudioBridgePanel extends StatefulWidget {
  const MathAudioBridgePanel({super.key});

  @override
  State<MathAudioBridgePanel> createState() => _MathAudioBridgePanelState();
}

class _MathAudioBridgePanelState extends State<MathAudioBridgePanel> {
  MathAudioBridgeProvider? _provider;

  @override
  void initState() {
    super.initState();
    try {
      _provider = GetIt.instance<MathAudioBridgeProvider>();
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
        child: Text('MathAudio Bridge not available', style: TextStyle(color: Colors.grey)),
      );
    }

    if (p.isProcessing) {
      return _buildProcessing(p);
    }

    if (p.error != null) {
      return _buildError(p);
    }

    if (!p.hasAudioMap) {
      return _buildEmpty();
    }

    return _buildResults(p);
  }

  Widget _buildProcessing(MathAudioBridgeProvider p) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.analytics, color: Colors.blue, size: 24),
        const SizedBox(height: 8),
        const Text('Generating Audio Map...', style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 8),
        SizedBox(
          width: 200,
          child: LinearProgressIndicator(
            value: p.progress,
            backgroundColor: Colors.white10,
            valueColor: const AlwaysStoppedAnimation(Colors.blue),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${(p.progress * 100).toStringAsFixed(0)}%',
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildError(MathAudioBridgeProvider p) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 24),
        const SizedBox(height: 8),
        Text(p.error!, style: const TextStyle(color: Colors.red, fontSize: 11)),
        const SizedBox(height: 8),
        TextButton(
          onPressed: p.reset,
          child: const Text('Reset', style: TextStyle(fontSize: 11)),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.upload_file, color: Colors.white38, size: 32),
        const SizedBox(height: 8),
        const Text(
          'Import PAR / CSV / GDD',
          style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          'Drop a math model file to auto-generate\na complete audio event map',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildResults(MathAudioBridgeProvider p) {
    final map = p.audioMap!;
    final model = p.model!;
    final sim = map.simulation;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header ──────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.auto_fix_high, color: Color(0xFF44AACC), size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  map.gameName,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _chip('${map.activeEvents} events'),
            ],
          ),
          const SizedBox(height: 8),

          // ─── Math Model Summary ──────────────────────────────────
          _sectionLabel('MATH MODEL'),
          const SizedBox(height: 4),
          Row(
            children: [
              _stat('RTP', '${model.targetRtp.toStringAsFixed(2)}%'),
              _stat('Hit Rate', '${(model.hitRate * 100).toStringAsFixed(1)}%'),
              _stat('Vol', model.volatilityIndex.toStringAsFixed(2)),
              _stat('Symbols', '${model.symbols.length}'),
            ],
          ),
          const SizedBox(height: 8),

          // ─── Tier Distribution ───────────────────────────────────
          _sectionLabel('AUDIO TIER DISTRIBUTION'),
          const SizedBox(height: 4),
          ...AudioTier.values.where((t) => (map.tierDistribution[t] ?? 0) > 0).map(
                (tier) => _tierRow(tier, map.tierDistribution[tier] ?? 0, map.totalEvents),
              ),
          const SizedBox(height: 8),

          // ─── Auto Tiers ──────────────────────────────────────────
          _sectionLabel('AUTO-CALIBRATED WIN TIERS'),
          const SizedBox(height: 4),
          ...map.autoTiers.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text(t.displayLabel,
                          style: const TextStyle(color: Colors.white70, fontSize: 10)),
                    ),
                    Expanded(
                      child: Text(
                        '${t.fromMultiplier.toStringAsFixed(1)}x – ${t.toMultiplier.toStringAsFixed(1)}x',
                        style: const TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                    ),
                    Text(
                      '${t.rollupDurationMs}ms',
                      style: const TextStyle(color: Colors.white38, fontSize: 9),
                    ),
                  ],
                ),
              )),

          // ─── Simulation Results ──────────────────────────────────
          if (sim != null) ...[
            const SizedBox(height: 8),
            _sectionLabel('SIMULATION (${_formatSpinCount(sim.totalSpins)} spins)'),
            const SizedBox(height: 4),
            Row(
              children: [
                _stat('RTP', '${sim.measuredRtp.toStringAsFixed(2)}%'),
                _stat('Hit', '${(sim.measuredHitRate * 100).toStringAsFixed(1)}%'),
                _stat('Peak V', '${sim.peakSimultaneousVoices}'),
                _stat('Dry', '${sim.drySpells.length}'),
              ],
            ),
            if (sim.voiceBudgetExceeded > 0) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.orange, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    'Voice budget exceeded ${sim.voiceBudgetExceeded}x',
                    style: const TextStyle(color: Colors.orange, fontSize: 10),
                  ),
                ],
              ),
            ],
            if (sim.drySpells.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Longest dry spell: ${sim.drySpells.map((d) => d.durationSpins).reduce(math.max)} spins',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              'Computed in ${sim.simulationDuration.inMilliseconds}ms',
              style: const TextStyle(color: Colors.white24, fontSize: 9),
            ),
          ],

          const SizedBox(height: 8),

          // ─── Top Events ──────────────────────────────────────────
          _sectionLabel('TOP EVENTS BY AUDIO WEIGHT'),
          const SizedBox(height: 4),
          ...map.events
              .where((e) => e.tier != AudioTier.silent)
              .take(8)
              .map((e) => _eventRow(e)),
        ],
      ),
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

  Widget _stat(String label, String value) => Expanded(
        child: Column(
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
          ],
        ),
      );

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 9)),
      );

  Widget _tierRow(AudioTier tier, int count, int total) {
    final pct = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Color(tier.colorValue),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 60,
            child: Text(tier.displayName,
                style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ),
          Expanded(
            child: SizedBox(
              height: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation(Color(tier.colorValue)),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: TextStyle(color: Color(tier.colorValue), fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventRow(AudioEventMapping event) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Color(event.tier.colorValue),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              event.displayName,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              event.suggestedStage,
              style: const TextStyle(color: Colors.white38, fontSize: 9),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              '${event.frequency.toStringAsFixed(0)}/k',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white54, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSpinCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(0)}K';
    return '$count';
  }
}
