/// Event List Placeholder — Event Browser Panel
///
/// Placeholder widget for the Event List tab.
/// Will be replaced with full event browser implementation.
library;

import 'package:flutter/material.dart';
import '../../../theme/fluxforge_theme.dart';

class EventListPlaceholder extends StatelessWidget {
  const EventListPlaceholder({super.key});

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
              color: FluxForgeTheme.accentCyan.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: FluxForgeTheme.accentCyan.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(
              Icons.list_alt_outlined,
              size: 32,
              color: FluxForgeTheme.accentCyan.withValues(alpha: 0.6),
            ),
          ),

          const SizedBox(height: 16),

          // Title
          Text(
            'Event Browser',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 8),

          // Description
          Text(
            'Browse and manage all registered events\nwith search and filtering',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 24),

          // Mock event count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: FluxForgeTheme.borderSubtle,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.event_note,
                  size: 16,
                  color: FluxForgeTheme.textMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  '0 events registered',
                  style: TextStyle(
                    color: FluxForgeTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Hint
          Text(
            'Drop audio assets to create events',
            style: TextStyle(
              color: FluxForgeTheme.textMuted.withValues(alpha: 0.6),
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
