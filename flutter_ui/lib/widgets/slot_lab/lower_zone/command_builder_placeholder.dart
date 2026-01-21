/// Command Builder Placeholder — Auto Event Builder Panel
///
/// Placeholder widget for the Command Builder tab.
/// Will be replaced with full Auto Event Builder implementation.
library;

import 'package:flutter/material.dart';
import '../../../theme/fluxforge_theme.dart';

class CommandBuilderPlaceholder extends StatelessWidget {
  const CommandBuilderPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: FluxForgeTheme.accentOrange.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(
              Icons.build_outlined,
              size: 32,
              color: FluxForgeTheme.accentOrange.withValues(alpha: 0.6),
            ),
          ),

          const SizedBox(height: 16),

          // Title
          Text(
            'Auto Event Builder',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 8),

          // Description
          Text(
            'Drop audio assets onto slot elements\nto automatically create events',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 24),

          // Feature list
          _FeatureList(),
        ],
      ),
    );
  }
}

class _FeatureList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final features = [
      ('Drag & Drop', 'Drop audio onto mockup elements'),
      ('Smart Routing', 'Auto-assigns bus and parameters'),
      ('Quick Commit', 'One-click event creation'),
    ];

    return Column(
      children: features.map((f) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 14,
                color: FluxForgeTheme.accentGreen.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 8),
              Text(
                f.$1,
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '— ${f.$2}',
                style: TextStyle(
                  color: FluxForgeTheme.textMuted,
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
