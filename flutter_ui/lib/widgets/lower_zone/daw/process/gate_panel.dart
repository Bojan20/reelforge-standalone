/// DAW Gate Panel
///
/// FF-G gate wrapper.
/// Displays FabFilterGatePanel for selected track.
library;

import 'package:flutter/material.dart';
import '../../../fabfilter/fabfilter_gate_panel.dart';

class GatePanel extends StatelessWidget {
  final int? selectedTrackId;

  const GatePanel({super.key, this.selectedTrackId});

  @override
  Widget build(BuildContext context) {
    return FabFilterGatePanel(trackId: selectedTrackId ?? 0);
  }
}
