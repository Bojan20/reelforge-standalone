/// DAW Saturation Panel
///
/// FF-SAT saturation wrapper.
/// Displays SaturationPanel for selected track.
library;

import 'package:flutter/material.dart';
import '../../../fabfilter/fabfilter_saturation_panel.dart';
import '../shared/panel_helpers.dart';

class SaturationPanelWrapper extends StatelessWidget {
  final int? selectedTrackId;

  const SaturationPanelWrapper({super.key, this.selectedTrackId});

  @override
  Widget build(BuildContext context) {
    if (selectedTrackId == null) {
      return buildEmptyState(
        icon: Icons.whatshot,
        title: 'No Track Selected',
        subtitle: 'Select a track to open Saturator',
      );
    }

    return FabFilterSaturationPanel(trackId: selectedTrackId!);
  }
}
