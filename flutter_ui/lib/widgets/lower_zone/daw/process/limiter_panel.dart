/// DAW Limiter Panel (P0.1 Extracted)
///
/// Pro-L style limiter wrapper.
/// Displays FabFilterLimiterPanel for selected track.
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
library;

import 'package:flutter/material.dart';
import '../../../fabfilter/fabfilter_limiter_panel.dart';
import '../shared/panel_helpers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LIMITER PANEL
// ═══════════════════════════════════════════════════════════════════════════

class LimiterPanel extends StatelessWidget {
  final int? selectedTrackId;

  const LimiterPanel({super.key, this.selectedTrackId});

  @override
  Widget build(BuildContext context) {
    if (selectedTrackId == null) {
      return buildEmptyState(
        icon: Icons.policy,
        title: 'No Track Selected',
        subtitle: 'Select a track to open Limiter',
      );
    }

    return FabFilterLimiterPanel(trackId: selectedTrackId!);
  }
}
