/// SlotLab INTEL Tab — MWUI Intelligence Views
///
/// Build, Flow, SimView, Diagnostic, Templates,
/// Export, Coverage, Inspector

import 'package:flutter/material.dart';
import '../../lower_zone/lower_zone_types.dart';
import '../middleware/mwui_build_view.dart';
import '../middleware/mwui_flow_view.dart';
import '../middleware/mwui_simulation_view.dart';
import '../middleware/mwui_diagnostic_view.dart';
import '../middleware/mwui_template_gallery.dart';
import '../middleware/mwui_export_panel.dart';
import '../middleware/mwui_coverage_viz.dart';
import '../middleware/mwui_inspector_panel.dart';

class SlotLabIntelTabContent extends StatelessWidget {
  final SlotLabIntelSubTab subTab;

  const SlotLabIntelTabContent({super.key, required this.subTab});

  @override
  Widget build(BuildContext context) {
    return switch (subTab) {
      SlotLabIntelSubTab.build => const MwuiBuildView(),
      SlotLabIntelSubTab.flow => const MwuiFlowView(),
      SlotLabIntelSubTab.sim => const MwuiSimulationView(),
      SlotLabIntelSubTab.diagnostic => const MwuiDiagnosticView(),
      SlotLabIntelSubTab.templates => const MwuiTemplateGallery(),
      SlotLabIntelSubTab.export => const MwuiExportPanel(),
      SlotLabIntelSubTab.coverage => const MwuiCoverageViz(),
      SlotLabIntelSubTab.inspector => const MwuiInspectorPanel(),
    };
  }
}
