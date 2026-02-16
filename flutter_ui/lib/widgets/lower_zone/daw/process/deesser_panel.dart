/// DAW De-Esser Panel
///
/// FF-E de-esser wrapper.
/// Displays FabFilterDeEsserPanel for selected track.
library;

import 'package:flutter/material.dart';
import '../../../fabfilter/fabfilter_deesser_panel.dart';

class DeEsserPanel extends StatelessWidget {
  final int? selectedTrackId;

  const DeEsserPanel({super.key, this.selectedTrackId});

  @override
  Widget build(BuildContext context) {
    return FabFilterDeEsserPanel(trackId: selectedTrackId ?? 0);
  }
}
