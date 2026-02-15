/// DAW Compressor Panel (P0.1 Extracted)
///
/// FF-C compressor wrapper.
/// Displays FabFilterCompressorPanel for selected track.
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
library;

import 'package:flutter/material.dart';
import '../../../fabfilter/fabfilter_compressor_panel.dart';
import '../shared/panel_helpers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// COMPRESSOR PANEL
// ═══════════════════════════════════════════════════════════════════════════

class CompPanel extends StatelessWidget {
  final int? selectedTrackId;

  const CompPanel({super.key, this.selectedTrackId});

  @override
  Widget build(BuildContext context) {
    if (selectedTrackId == null) {
      return buildEmptyState(
        icon: Icons.compress,
        title: 'No Track Selected',
        subtitle: 'Select a track to open Compressor',
      );
    }

    return FabFilterCompressorPanel(trackId: selectedTrackId!);
  }
}
