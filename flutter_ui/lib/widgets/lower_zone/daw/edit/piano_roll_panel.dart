/// DAW Piano Roll Panel (P0.1 Extracted)
///
/// MIDI note editor with:
/// - Full piano roll (128 notes)
/// - Velocity editor
/// - CC automation
/// - Toolbar (draw/select/erase)
///
/// Wrapper for PianoRollWidget (already exists).
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
/// Lines 1620-1716 (~97 LOC)
library;

import 'package:flutter/material.dart';
import '../../lower_zone_types.dart';
import '../../../midi/piano_roll_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PIANO ROLL PANEL
// ═══════════════════════════════════════════════════════════════════════════

class PianoRollPanel extends StatelessWidget {
  /// Currently selected track ID (for MIDI editing)
  final int? selectedTrackId;

  /// Current tempo (for grid quantization)
  final double tempo;

  /// Callback when notes are changed
  final void Function(String action, Map<String, dynamic> data)? onAction;

  const PianoRollPanel({
    super.key,
    this.selectedTrackId,
    this.tempo = 120.0,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedTrackId == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('PIANO ROLL', Icons.piano),
            const SizedBox(height: 24),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.piano,
                      size: 48,
                      color: LowerZoneColors.textMuted.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No MIDI Track Selected',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: LowerZoneColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Select a MIDI track to edit notes',
                      style: TextStyle(
                        fontSize: 10,
                        color: LowerZoneColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Full piano roll editor for selected MIDI track
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with track info
          Row(
            children: [
              const Icon(Icons.piano, size: 14, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 6),
              Text(
                'PIANO ROLL — Track $selectedTrackId',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.dawAccent,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              // Info: The piano roll widget has its own toolbar
              const Text(
                'Use toolbar in editor to draw/select/erase notes',
                style: TextStyle(
                  fontSize: 9,
                  color: LowerZoneColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Piano Roll Widget with integrated toolbar and velocity lane
          Expanded(
            child: PianoRollWidget(
              clipId: selectedTrackId!, // Use track ID as clip ID
              lengthBars: 4,
              bpm: tempo, // Use tempo from parameter
              onNotesChanged: () {
                onAction?.call('midi_notes_changed', {
                  'trackId': selectedTrackId,
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── UI Builders ───────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: LowerZoneColors.dawAccent),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.dawAccent,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
