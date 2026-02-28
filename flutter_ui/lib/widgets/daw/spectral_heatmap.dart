import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/spectral_allocation_provider.dart';

/// Spectral Heatmap — 10-band density visualization for SAMCL.
/// Shows density bars for each spectral role with SCI indicator.
class SpectralHeatmap extends StatefulWidget {
  const SpectralHeatmap({super.key});

  @override
  State<SpectralHeatmap> createState() => _SpectralHeatmapState();
}

class _SpectralHeatmapState extends State<SpectralHeatmap> {
  late final SpectralAllocationProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<SpectralAllocationProvider>();
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

  static const _roleColors = [
    Color(0xFFE91E63), // SubEnergy — pink
    Color(0xFFFF5722), // LowBody — deep orange
    Color(0xFFFF9800), // LowMidBody — orange
    Color(0xFFFFEB3B), // MidCore — yellow
    Color(0xFF4CAF50), // HighTransient — green
    Color(0xFF00BCD4), // AirLayer — cyan
    Color(0xFF2196F3), // FullSpectrum — blue
    Color(0xFF9C27B0), // NoiseImpact — purple
    Color(0xFFCDDC39), // MelodicTopline — lime
    Color(0xFF607D8B), // BackgroundPad — blue-grey
  ];

  @override
  Widget build(BuildContext context) {
    final densities = _provider.bandDensity;
    final sci = _provider.sciAdv;
    final collisions = _provider.collisionCount;
    final carve = _provider.aggressiveCarve;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.equalizer, size: 14, color: Color(0xFF4FC3F7)),
              const SizedBox(width: 4),
              Text(
                'Spectral Map',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _chip(
                'SCI ${sci.toStringAsFixed(2)}',
                sci > 0.85
                    ? const Color(0xFFEF5350)
                    : sci > 0.5
                        ? const Color(0xFFFF9800)
                        : const Color(0xFF66BB6A),
              ),
              if (carve) ...[
                const SizedBox(width: 4),
                _chip('CARVE', const Color(0xFFEF5350)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // Band density bars
          for (int i = 0; i < 10; i++)
            _bandBar(
              SpectralRole.values[i].displayName,
              densities[i],
              _roleColors[i],
            ),
          const SizedBox(height: 4),
          // Summary
          Row(
            children: [
              Text(
                'Collisions: $collisions',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
              const Spacer(),
              Text(
                'Shifts: ${_provider.slotShifts}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Voices: ${_provider.voiceCount}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bandBar(String label, int density, Color color) {
    final maxDensity = 8; // reasonable max for visualization
    final ratio = (density / maxDensity).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 9,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(4),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: ratio,
                child: Container(
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 20,
            child: Text(
              '$density',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 9,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w500),
      ),
    );
  }
}
