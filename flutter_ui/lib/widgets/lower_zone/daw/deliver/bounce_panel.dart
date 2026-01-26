/// DAW Bounce Panel (P0.1 Extracted)
///
/// Master bounce wrapper for DawBouncePanel.
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
library;

import 'package:flutter/material.dart';
import '../../export_panels.dart';

class BouncePanel extends StatelessWidget {
  const BouncePanel({super.key});

  @override
  Widget build(BuildContext context) => const DawBouncePanel();
}
