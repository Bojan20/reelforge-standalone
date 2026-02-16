/// DAW Reverb Panel
///
/// FF-R reverb wrapper.
/// Displays FabFilterReverbPanel for selected track.
library;

import 'package:flutter/material.dart';
import '../../../fabfilter/fabfilter_reverb_panel.dart';

class ReverbPanel extends StatelessWidget {
  final int? selectedTrackId;

  const ReverbPanel({super.key, this.selectedTrackId});

  @override
  Widget build(BuildContext context) {
    return FabFilterReverbPanel(trackId: selectedTrackId ?? 0);
  }
}
