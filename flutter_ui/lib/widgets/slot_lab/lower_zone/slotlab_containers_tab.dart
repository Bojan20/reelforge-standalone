/// SlotLab CONTAINERS Tab — Blend, Random, Sequence + Advanced panels
///
/// Unified container tools from middleware into SlotLab lower zone.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../lower_zone/lower_zone_types.dart';
import '../../middleware/blend_container_panel.dart';
import '../../middleware/random_container_panel.dart';
import '../../middleware/sequence_container_panel.dart';
import '../../middleware/container_groups_panel.dart';
import '../../middleware/container_preset_browser.dart';
import '../../middleware/container_metrics_panel.dart';
import '../../middleware/intensity_crossfade_wizard.dart';
import '../../middleware/container_ab_comparison_panel.dart';
import '../../middleware/container_crossfade_preview_panel.dart';
import '../../../providers/middleware_provider.dart';
import '../../../models/middleware_models.dart';
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
      SlotLabContainersSubTab.abCompare => const _ContainerSelectorPanel(panelType: 'abCompare'),
      SlotLabContainersSubTab.crossfade => const _ContainerSelectorPanel(panelType: 'crossfade'),
      SlotLabContainersSubTab.groups => const ContainerGroupsPanel(),
      SlotLabContainersSubTab.presets => const ContainerPresetBrowser(),
      SlotLabContainersSubTab.metrics => const ContainerMetricsPanel(),
      SlotLabContainersSubTab.timeline => const _SequenceTimelinePanel(),
      SlotLabContainersSubTab.wizard => const IntensityCrossfadeWizard(),
    };
  }
}

/// Container selector that picks a container, then shows AB/Crossfade panel
class _ContainerSelectorPanel extends StatefulWidget {
  final String panelType; // 'abCompare' or 'crossfade'

  const _ContainerSelectorPanel({required this.panelType});

  @override
  State<_ContainerSelectorPanel> createState() => _ContainerSelectorPanelState();
}

class _ContainerSelectorPanelState extends State<_ContainerSelectorPanel> {
  int? _selectedId;
  String _selectedType = 'blend'; // blend, random, sequence

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MiddlewareProvider>();
    final blends = provider.blendContainers;
    final randoms = provider.randomContainers;
    final sequences = provider.sequenceContainers;

    // If a container is selected, show the panel
    if (_selectedId != null) {
      if (widget.panelType == 'abCompare') {
        return ContainerABComparisonPanel(
          containerId: _selectedId!,
          containerType: _selectedType,
          onClose: () => setState(() => _selectedId = null),
        );
      } else {
        return ContainerCrossfadePreviewPanel(
          containerId: _selectedId!,
          onClose: () => setState(() => _selectedId = null),
        );
      }
    }

    // Container selector
    final title = widget.panelType == 'abCompare' ? 'A/B COMPARISON' : 'CROSSFADE PREVIEW';
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              border: const Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
            ),
            child: Row(
              children: [
                Icon(
                  widget.panelType == 'abCompare' ? Icons.compare : Icons.swap_horiz,
                  size: 14,
                  color: FluxForgeTheme.accentPurple,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: FluxForgeTheme.dockSans(
                    size: 10,
                    weight: FontWeight.bold,
                    letterSpacing: 1,
                    color: FluxForgeTheme.accentPurple,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                if (blends.isNotEmpty) ...[
                  _buildSectionHeader('Blend'),
                  for (final b in blends)
                    _buildContainerRow(b.id, b.name, 'blend', FluxForgeTheme.accentPurple),
                ],
                if (randoms.isNotEmpty) ...[
                  _buildSectionHeader('Random'),
                  for (final r in randoms)
                    _buildContainerRow(r.id, r.name, 'random', FluxForgeTheme.accentOrange),
                ],
                if (sequences.isNotEmpty) ...[
                  _buildSectionHeader('Sequence'),
                  for (final s in sequences)
                    _buildContainerRow(s.id, s.name, 'sequence', FluxForgeTheme.accentCyan),
                ],
                if (blends.isEmpty && randoms.isEmpty && sequences.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No containers available',
                        style: FluxForgeTheme.dockSans(size: 10, color: FluxForgeTheme.textTertiary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        label.toUpperCase(),
        style: FluxForgeTheme.dockSans(
          size: 9,
          weight: FontWeight.bold,
          letterSpacing: 1,
          color: FluxForgeTheme.textTertiary,
        ),
      ),
    );
  }

  Widget _buildContainerRow(int id, String name, String type, Color color) {
    return GestureDetector(
      onTap: () => setState(() {
        _selectedId = id;
        _selectedType = type;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: FluxForgeTheme.dockSans(size: 10, color: FluxForgeTheme.textPrimary),
              ),
            ),
            Text(
              type.toUpperCase(),
              style: FluxForgeTheme.dockSans(size: 8, weight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Timeline view for sequence containers — shows steps as horizontal blocks
class _SequenceTimelinePanel extends StatefulWidget {
  const _SequenceTimelinePanel();

  @override
  State<_SequenceTimelinePanel> createState() => _SequenceTimelinePanelState();
}

class _SequenceTimelinePanelState extends State<_SequenceTimelinePanel> {
  int? _selectedContainerId;
  double _zoom = 1.0;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MiddlewareProvider>();
    final sequences = provider.sequenceContainers;

    if (sequences.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timeline, size: 28, color: FluxForgeTheme.textTertiary.withValues(alpha: 0.4)),
            const SizedBox(height: 8),
            Text(
              'No sequence containers',
              style: FluxForgeTheme.dockSans(size: 11, color: FluxForgeTheme.textTertiary),
            ),
            const SizedBox(height: 4),
            Text(
              'Create sequences in the Sequence tab',
              style: FluxForgeTheme.dockSans(size: 9, color: FluxForgeTheme.textTertiary),
            ),
          ],
        ),
      );
    }

    final selected = _selectedContainerId != null
        ? sequences.where((s) => s.id == _selectedContainerId).firstOrNull
        : sequences.first;

    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          // Header: container selector + zoom
          _buildHeader(sequences, selected),
          // Timeline
          Expanded(
            child: selected != null
                ? _buildTimeline(selected)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(List<SequenceContainer> sequences, SequenceContainer? selected) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: const Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timeline, size: 14, color: FluxForgeTheme.accentCyan),
          const SizedBox(width: 8),
          Text(
            'SEQUENCE TIMELINE',
            style: FluxForgeTheme.dockSans(
              size: 10,
              weight: FontWeight.bold,
              letterSpacing: 1,
              color: FluxForgeTheme.accentCyan,
            ),
          ),
          const SizedBox(width: 16),
          // Container selector
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: selected?.id ?? sequences.first.id,
              isDense: true,
              dropdownColor: FluxForgeTheme.bgMid,
              style: FluxForgeTheme.dockSans(size: 10, color: FluxForgeTheme.textPrimary),
              items: sequences.map((s) => DropdownMenuItem(
                value: s.id,
                child: Text(s.name, style: FluxForgeTheme.dockSans(size: 10)),
              )).toList(),
              onChanged: (id) => setState(() => _selectedContainerId = id),
            ),
          ),
          const Spacer(),
          // Zoom controls
          GestureDetector(
            onTap: () => setState(() => _zoom = (_zoom - 0.25).clamp(0.25, 4.0)),
            child: const Icon(Icons.zoom_out, size: 14, color: FluxForgeTheme.textSecondary),
          ),
          const SizedBox(width: 4),
          Text(
            '${(_zoom * 100).toInt()}%',
            style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textSecondary),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => setState(() => _zoom = (_zoom + 0.25).clamp(0.25, 4.0)),
            child: const Icon(Icons.zoom_in, size: 14, color: FluxForgeTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(SequenceContainer seq) {
    final steps = seq.steps;
    if (steps.isEmpty) {
      return Center(
        child: Text('No steps in sequence', style: FluxForgeTheme.dockSans(size: 10, color: FluxForgeTheme.textTertiary)),
      );
    }

    // Calculate total duration for proportional sizing
    final totalDuration = steps.fold<double>(0, (sum, s) => sum + (s.durationMs > 0 ? s.durationMs : 500));

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info bar
          Row(
            children: [
              _buildInfoBadge('Steps', '${steps.length}'),
              const SizedBox(width: 8),
              _buildInfoBadge('Total', '${totalDuration.toInt()} ms'),
              const SizedBox(width: 8),
              _buildInfoBadge('Speed', '${seq.speed}x'),
              const SizedBox(width: 8),
              _buildInfoBadge('End', seq.endBehavior.name),
            ],
          ),
          const SizedBox(height: 12),
          // Timeline blocks
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < steps.length; i++) ...[
                    _buildStepBlock(steps[i], i, totalDuration),
                    if (i < steps.length - 1)
                      Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        color: FluxForgeTheme.borderSubtle,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepBlock(SequenceStep step, int index, double totalDuration) {
    final fraction = (step.durationMs > 0 ? step.durationMs : 500) / totalDuration;
    final width = (fraction * 600 * _zoom).clamp(60.0, 400.0);

    final colors = [
      FluxForgeTheme.accentCyan,
      FluxForgeTheme.accentGreen,
      FluxForgeTheme.accentOrange,
      FluxForgeTheme.accentPurple,
      FluxForgeTheme.accentBlue,
      FluxForgeTheme.accentPink,
    ];
    final color = colors[index % colors.length];

    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: FluxForgeTheme.dockSans(
                      size: 9,
                      weight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  step.childName,
                  style: FluxForgeTheme.dockSans(
                    size: 10,
                    weight: FontWeight.w600,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            '${step.durationMs > 0 ? step.durationMs : 500} ms',
            style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBadge(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: FluxForgeTheme.dockSans(size: 9, color: FluxForgeTheme.textTertiary),
          ),
          Text(
            value,
            style: FluxForgeTheme.dockSans(
              size: 9,
              weight: FontWeight.bold,
              color: FluxForgeTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
