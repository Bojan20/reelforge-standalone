import 'package:flutter/material.dart';

/// UCP-4: Spectral Heatmap Zone
///
/// Displays 10 spectral role allocations and masking visualization.
class SpectralHeatmap extends StatelessWidget {
  const SpectralHeatmap({super.key});

  static const _roles = [
    'Sub Bass', 'Bass', 'Low Mid', 'Mid', 'Upper Mid',
    'Presence', 'Brilliance', 'Air', 'Effects', 'Spatial',
  ];

  static const _colors = [
    Color(0xFFE53935), Color(0xFFFF7043), Color(0xFFFFB74D), Color(0xFFFFF176), Color(0xFF66BB6A),
    Color(0xFF42A5F5), Color(0xFF5C6BC0), Color(0xFF7E57C2), Color(0xFFAB47BC), Color(0xFF78909C),
  ];

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
                      value: 0.0,
                      backgroundColor: Colors.white.withOpacity(0.04),
                      valueColor: AlwaysStoppedAnimation(_colors[i].withOpacity(0.5)),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
