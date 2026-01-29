/// DAW EQ Panel (P0.1 Extracted)
///
/// 64-band parametric EQ wrapper.
/// Displays FabFilterEqPanel for selected track.
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
library;

import 'package:flutter/material.dart';
import '../../../fabfilter/fabfilter_eq_panel.dart';
import '../shared/panel_helpers.dart';

// ═══════════════════════════════════════════════════════════════════════════
// EQ PANEL
// ═══════════════════════════════════════════════════════════════════════════

class EqPanel extends StatelessWidget {
  final int? selectedTrackId;

  const EqPanel({super.key, this.selectedTrackId});

  @override
  Widget build(BuildContext context) {
    if (selectedTrackId == null) {
      return buildEmptyState(
        icon: Icons.equalizer,
        title: 'No Track Selected',
        subtitle: 'Select a track to open EQ',
      );
    }

    return FabFilterEqPanel(trackId: selectedTrackId!);
  }
}
