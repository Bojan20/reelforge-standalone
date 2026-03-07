/// SlotLab CONTAINERS Tab — Blend, Random, Sequence + Advanced panels
///
/// Unified container tools from middleware into SlotLab lower zone.

import 'package:flutter/material.dart';
import '../../lower_zone/lower_zone_types.dart';
import '../../middleware/blend_container_panel.dart';
import '../../middleware/random_container_panel.dart';
import '../../middleware/sequence_container_panel.dart';
import '../../middleware/container_groups_panel.dart';
import '../../middleware/container_preset_browser.dart';
import '../../middleware/container_metrics_panel.dart';
import '../../middleware/intensity_crossfade_wizard.dart';
import '../../../theme/fluxforge_theme.dart';

class SlotLabContainersTabContent extends StatelessWidget {
  final SlotLabContainersSubTab subTab;

  const SlotLabContainersTabContent({super.key, required this.subTab});

  @override
  Widget build(BuildContext context) {
    return switch (subTab) {
      SlotLabContainersSubTab.blend => const BlendContainerPanel(),
      SlotLabContainersSubTab.random => const RandomContainerPanel(),
      SlotLabContainersSubTab.sequence => const SequenceContainerPanel(),
      SlotLabContainersSubTab.abCompare => _buildContextRequired('A/B Comparison', 'Select a container to compare variants'),
      SlotLabContainersSubTab.crossfade => _buildContextRequired('Crossfade Preview', 'Select a container to preview crossfades'),
      SlotLabContainersSubTab.groups => const ContainerGroupsPanel(),
      SlotLabContainersSubTab.presets => const ContainerPresetBrowser(),
      SlotLabContainersSubTab.metrics => const ContainerMetricsPanel(),
      SlotLabContainersSubTab.timeline => _buildContextRequired('Timeline Zoom', 'Select a sequence container to view timeline'),
      SlotLabContainersSubTab.wizard => const IntensityCrossfadeWizard(),
    };
  }

  /// Placeholder for context-dependent panels that require a selected container
  static Widget _buildContextRequired(String title, String hint) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FluxForgeTheme.textTertiary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: FluxForgeTheme.textTertiary.withValues(alpha: 0.12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app, size: 28, color: FluxForgeTheme.textTertiary.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hint,
              style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
