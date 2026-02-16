/// DAW Delay Panel
///
/// FF-DLY delay wrapper.
/// Displays FabFilterDelayPanel for selected track.
library;

import 'package:flutter/material.dart';
import '../../../fabfilter/fabfilter_delay_panel.dart';

class DelayPanel extends StatelessWidget {
  final int? selectedTrackId;

  const DelayPanel({super.key, this.selectedTrackId});

  @override
  Widget build(BuildContext context) {
    return FabFilterDelayPanel(trackId: selectedTrackId ?? 0);
  }
}
