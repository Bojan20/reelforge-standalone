/// DAW Saturation Panel
///
/// FF-SAT saturation wrapper.
/// Displays SaturationPanel for selected track.
library;

import 'package:flutter/material.dart';
import '../../../fabfilter/fabfilter_saturation_panel.dart';

class SaturationPanelWrapper extends StatelessWidget {
  final int? selectedTrackId;

  const SaturationPanelWrapper({super.key, this.selectedTrackId});

  @override
  Widget build(BuildContext context) {
    return FabFilterSaturationPanel(trackId: selectedTrackId ?? 0);
  }
}
