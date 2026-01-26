/// DAW Sends Panel (P0.1 Extracted)
///
/// Visual routing matrix showing Track→Bus connections.
/// Wrapper for RoutingMatrixPanel widget.
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
/// Line 1300 (1 LOC wrapper)
library;

import 'package:flutter/material.dart';
import '../../../routing/routing_matrix_panel.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SENDS PANEL
// ═══════════════════════════════════════════════════════════════════════════

class SendsPanel extends StatelessWidget {
  const SendsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    // Wrapper for RoutingMatrixPanel (already exists)
    return const RoutingMatrixPanel();
  }
}
