/// DAW Limiter Panel (P0.1 Extracted)
///
/// FF-L limiter wrapper.
/// Displays FabFilterLimiterPanel for selected track.
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
library;

import 'package:flutter/material.dart';
import '../../../fabfilter/fabfilter_limiter_panel.dart';

class LimiterPanel extends StatelessWidget {
  final int? selectedTrackId;

  const LimiterPanel({super.key, this.selectedTrackId});

  @override
  Widget build(BuildContext context) {
    return FabFilterLimiterPanel(trackId: selectedTrackId ?? 0);
  }
}
