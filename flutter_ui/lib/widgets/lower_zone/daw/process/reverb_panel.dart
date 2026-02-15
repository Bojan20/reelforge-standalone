/// DAW Reverb Panel
///
/// Pro-R style reverb wrapper.
/// Displays FabFilterReverbPanel for selected track.
library;

import 'package:flutter/material.dart';
import '../../../fabfilter/fabfilter_reverb_panel.dart';
import '../shared/panel_helpers.dart';

class ReverbPanel extends StatelessWidget {
  final int? selectedTrackId;

  const ReverbPanel({super.key, this.selectedTrackId});

  @override
  Widget build(BuildContext context) {
    if (selectedTrackId == null) {
      return buildEmptyState(
        icon: Icons.waves,
        title: 'No Track Selected',
        subtitle: 'Select a track to open Reverb',
      );
    }

    return FabFilterReverbPanel(trackId: selectedTrackId!);
  }
}
