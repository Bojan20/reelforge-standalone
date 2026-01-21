/// Meters Placeholder — Audio Bus Meters Panel
///
/// Placeholder widget for the Meters tab.
/// Will be replaced with live bus meter visualization.
library;

import 'package:flutter/material.dart';
import '../../../theme/fluxforge_theme.dart';

class MetersPlaceholder extends StatelessWidget {
  const MetersPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          // Left: Info
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon + Title
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.equalizer,
                        size: 22,
                        color: FluxForgeTheme.accentGreen.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bus Meters',
                          style: TextStyle(
                            color: FluxForgeTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Real-time audio levels',
                          style: TextStyle(
                            color: FluxForgeTheme.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Bus list
                _BusList(),
              ],
            ),
          ),

          // Right: Mock meters
          Expanded(
            flex: 3,
            child: _MockMeters(),
          ),
        ],
      ),
    );
  }
}

class _BusList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final buses = [
      ('SFX', Icons.volume_up, FluxForgeTheme.accentBlue),
      ('Music', Icons.music_note, FluxForgeTheme.accentOrange),
      ('Voice', Icons.mic, FluxForgeTheme.accentGreen),
      ('Ambience', Icons.waves, FluxForgeTheme.accentCyan),
      ('Master', Icons.speaker, FluxForgeTheme.textPrimary),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: buses.map((b) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: b.$3.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                b.$2,
                size: 12,
                color: b.$3.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              Text(
                b.$1,
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _MockMeters extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: FluxForgeTheme.borderSubtle,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _MockMeter(label: 'SFX', level: 0.0, color: FluxForgeTheme.accentBlue),
          _MockMeter(label: 'MUS', level: 0.0, color: FluxForgeTheme.accentOrange),
          _MockMeter(label: 'VO', level: 0.0, color: FluxForgeTheme.accentGreen),
          _MockMeter(label: 'AMB', level: 0.0, color: FluxForgeTheme.accentCyan),
          const SizedBox(width: 8),
          Container(width: 1, height: 100, color: FluxForgeTheme.borderSubtle),
          const SizedBox(width: 8),
          _MockMeter(label: 'L', level: 0.0, color: FluxForgeTheme.textPrimary, isWide: true),
          _MockMeter(label: 'R', level: 0.0, color: FluxForgeTheme.textPrimary, isWide: true),
        ],
      ),
    );
  }
}

class _MockMeter extends StatelessWidget {
  final String label;
  final double level;
  final Color color;
  final bool isWide;

  const _MockMeter({
    required this.label,
    required this.level,
    required this.color,
    this.isWide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Meter bar
        Container(
          width: isWide ? 16 : 10,
          height: 80,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: color.withValues(alpha: 0.2),
            ),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              height: 80 * level,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    color.withValues(alpha: 0.8),
                    color.withValues(alpha: 0.4),
                  ],
                ),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),

        const SizedBox(height: 6),

        // Label
        Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
