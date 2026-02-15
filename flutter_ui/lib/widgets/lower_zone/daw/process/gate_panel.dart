/// DAW Gate Panel
///
/// FF-G gate wrapper.
/// Displays FabFilterGatePanel for selected track.
library;

import 'package:flutter/material.dart';
import '../../../fabfilter/fabfilter_gate_panel.dart';
import '../shared/panel_helpers.dart';

class GatePanel extends StatelessWidget {
  final int? selectedTrackId;

  const GatePanel({super.key, this.selectedTrackId});

  @override
  Widget build(BuildContext context) {
    if (selectedTrackId == null) {
      return buildEmptyState(
        icon: Icons.door_front_door,
        title: 'No Track Selected',
        subtitle: 'Select a track to open Gate',
      );
    }

    return FabFilterGatePanel(trackId: selectedTrackId!);
  }
}
