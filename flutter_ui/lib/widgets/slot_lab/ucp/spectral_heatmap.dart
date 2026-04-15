import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/aurexis_provider.dart';

/// UCP-4: Spectral Heatmap Zone
///
/// Displays 10 spectral role allocations derived from live AUREXIS parameters.
/// Each spectral band is driven by the corresponding AUREXIS psychoacoustic module.
class SpectralHeatmap extends StatefulWidget {
  const SpectralHeatmap({super.key});

  @override
  State<SpectralHeatmap> createState() => _SpectralHeatmapState();
}

class _SpectralHeatmapState extends State<SpectralHeatmap> {
  AurexisProvider? _provider;

  static const _roles = [
    'Sub Bass', 'Bass', 'Low Mid', 'Mid', 'Upper Mid',
    'Presence', 'Brilliance', 'Air', 'Effects', 'Spatial',
  ];

  static const _colors = [
    Color(0xFFE53935), Color(0xFFFF7043), Color(0xFFFFB74D), Color(0xFFFFF176), Color(0xFF66BB6A),
    Color(0xFF42A5F5), Color(0xFF5C6BC0), Color(0xFF7E57C2), Color(0xFFAB47BC), Color(0xFF78909C),
  ];

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

  /// Derive 10 spectral band values from live AUREXIS parameter map.
  ///
  /// Mappings:
  ///   Sub Bass   → subReinforcementDb  (+6dB boost = 1.0, −6dB cut = 0.0)
  ///   Bass       → harmonicExcitation  (0.5–2.0 range → 0.0–1.0)
  ///   Low Mid    → energyDensity       (direct 0.0–1.0)
  ///   Mid        → transientSharpness  (0.5–2.0 → 0.0–1.0)
  ///   Upper Mid  → 1 − transientSmoothing (inverse: less smoothing = more presence)
  ///   Presence   → attentionWeight     (direct 0.0–1.0)
  ///   Brilliance → hfAttenuationDb     (−12dB = 0.0, 0dB = 1.0)
  ///   Air        → stereoWidth / 2     (0.0–2.0 → 0.0–1.0)
  ///   Effects    → reverbSendBias      (direct 0.0–1.0)
  ///   Spatial    → zDepthOffset.abs()  (depth offset magnitude 0.0–1.0)
  List<double> get _spectralValues {
    final p = _provider?.parameters;
    if (p == null) return List.filled(10, 0.0);

    return [
      // Sub Bass — sub reinforcement: −6..+6 dB → 0..1
      ((p.subReinforcementDb + 6.0) / 12.0).clamp(0.0, 1.0),
      // Bass — harmonic excitation: 0.5..2.0 → 0..1
      ((p.harmonicExcitation - 0.5) / 1.5).clamp(0.0, 1.0),
      // Low Mid — energy density: direct
      p.energyDensity.clamp(0.0, 1.0),
      // Mid — transient sharpness: 0.5..2.0 → 0..1
      ((p.transientSharpness - 0.5) / 1.5).clamp(0.0, 1.0),
      // Upper Mid — inverse smoothing: less smooth = more upper mid
      (1.0 - p.transientSmoothing).clamp(0.0, 1.0),
      // Presence — attention weight: direct
      p.attentionWeight.clamp(0.0, 1.0),
      // Brilliance — HF attenuation inverted: −12dB=0, 0dB=1
      ((p.hfAttenuationDb + 12.0) / 12.0).clamp(0.0, 1.0),
      // Air — stereo width: 0..2 → 0..1
      (p.stereoWidth / 2.0).clamp(0.0, 1.0),
      // Effects — reverb send bias: direct
      p.reverbSendBias.clamp(0.0, 1.0),
      // Spatial — z-depth offset magnitude: direct
      p.zDepthOffset.abs().clamp(0.0, 1.0),
    ];
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
          _buildHeatmap(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.equalizer, size: 12, color: Color(0xFFAB47BC)),
        const SizedBox(width: 4),
        Text(
          'Spectral Allocation',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildHeatmap() {
    final values = _spectralValues;

    return Column(
      children: [
        for (int i = 0; i < _roles.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                Container(
                  width: 3, height: 8,
                  decoration: BoxDecoration(
                    color: _colors[i],
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(width: 3),
                SizedBox(
                  width: 54,
                  child: Text(
                    _roles[i],
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 7),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 3,
                    child: LinearProgressIndicator(
                      value: values[i],
                      backgroundColor: Colors.white.withOpacity(0.04),
                      valueColor: AlwaysStoppedAnimation(_colors[i].withOpacity(0.7)),
                    ),
                  ),
                ),
                SizedBox(
                  width: 18,
                  child: Text(
                    '${(values[i] * 100).toStringAsFixed(0)}',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: _colors[i].withOpacity(0.5), fontSize: 6),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
