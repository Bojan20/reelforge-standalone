/// FluxForge Studio Blend Container Panel
///
/// RTPC-based crossfade between sounds.
/// Smooth transitions controlled by game parameters.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/middleware_models.dart';
import '../../providers/middleware_provider.dart';
import '../../providers/subsystems/blend_containers_provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../common/audio_waveform_picker_dialog.dart';
import 'container_ab_comparison_panel.dart';
import 'container_crossfade_preview_panel.dart';
import 'container_preset_library_panel.dart';
import 'container_visualization_widgets.dart';

/// Blend Container Panel Widget
class BlendContainerPanel extends StatefulWidget {
  const BlendContainerPanel({super.key});

  @override
  State<BlendContainerPanel> createState() => _BlendContainerPanelState();
}

class _BlendContainerPanelState extends State<BlendContainerPanel> {
  int? _selectedContainerId;
  int? _selectedChildId;
  bool _showAddContainer = false;
  double _rtpcPreviewValue = 0.5; // For RTPC slider preview

  @override
  Widget build(BuildContext context) {
    return Selector<MiddlewareProvider, List<BlendContainer>>(
      selector: (_, p) => p.blendContainers,
      builder: (context, containers, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FluxForgeTheme.surfaceDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Container list
                    SizedBox(
                      width: 200,
                      child: _buildContainerList(containers),
                    ),
                    const SizedBox(width: 16),
                    // Blend visualization
                    Expanded(
                      child: _buildBlendVisualization(containers),
                    ),
                  ],
                ),
              ),
              if (_showAddContainer)
                _buildAddContainerDialog(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.blur_linear, color: Colors.purple, size: 20),
        const SizedBox(width: 8),
        Text(
          'Blend Containers',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        if (_selectedContainerId != null) ...[
          // Crossfade preview button
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => ContainerCrossfadePreviewDialog.show(
                context,
                containerId: _selectedContainerId!,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.graphic_eq, size: 14, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      'Preview',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // A/B comparison button
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => ContainerABComparisonDialog.show(
                context,
                containerId: _selectedContainerId!,
                containerType: 'blend',
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.cyan.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.cyan),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.compare, size: 14, color: Colors.cyan),
                    const SizedBox(width: 4),
                    Text(
                      'A/B',
                      style: TextStyle(
                        color: Colors.cyan,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        GestureDetector(
          onTap: () => ContainerPresetLibraryDialog.show(
            context,
            targetContainerId: _selectedContainerId,
            targetContainerType: 'blend',
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.amber),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.library_music, size: 14, color: Colors.amber),
                const SizedBox(width: 4),
                Text(
                  'Presets',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => setState(() => _showAddContainer = true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.purple),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 14, color: Colors.purple),
                const SizedBox(width: 4),
                Text(
                  'New Container',
                  style: TextStyle(
                    color: Colors.purple,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContainerList(List<BlendContainer> containers) {
    if (containers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FluxForgeTheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.blur_off, size: 32, color: FluxForgeTheme.textSecondary),
            const SizedBox(height: 8),
            Text(
              'No blend containers',
              style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: containers.length,
        itemBuilder: (context, index) {
          final container = containers[index];
          final isSelected = _selectedContainerId == container.id;

          return GestureDetector(
            onTap: () => setState(() {
              _selectedContainerId = isSelected ? null : container.id;
              _selectedChildId = null;
            }),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.purple.withValues(alpha: 0.1)
                    : Colors.transparent,
                border: Border(
                  left: isSelected
                      ? BorderSide(color: Colors.purple, width: 3)
                      : BorderSide.none,
                  bottom: BorderSide(
                    color: FluxForgeTheme.border.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.blur_linear,
                        size: 14,
                        color: container.enabled ? Colors.purple : FluxForgeTheme.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          container.name,
                          style: TextStyle(
                            color: FluxForgeTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          context.read<MiddlewareProvider>().updateBlendContainer(
                            container.copyWith(enabled: !container.enabled),
                          );
                        },
                        child: Container(
                          width: 28,
                          height: 16,
                          decoration: BoxDecoration(
                            color: container.enabled
                                ? Colors.green.withValues(alpha: 0.3)
                                : FluxForgeTheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: container.enabled ? Colors.green : FluxForgeTheme.border,
                            ),
                          ),
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 150),
                            alignment: container.enabled
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              width: 12,
                              height: 12,
                              margin: const EdgeInsets.all(1),
                              decoration: BoxDecoration(
                                color: container.enabled
                                    ? Colors.green
                                    : FluxForgeTheme.textSecondary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'RTPC: ${container.rtpcId}',
                          style: TextStyle(
                            color: FluxForgeTheme.accentBlue,
                            fontSize: 9,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${container.children.length} children',
                        style: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBlendVisualization(List<BlendContainer> containers) {
    if (_selectedContainerId == null) {
      return Container(
        decoration: BoxDecoration(
          color: FluxForgeTheme.surface.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.border),
        ),
        child: Center(
          child: Text(
            'Select a blend container to visualize',
            style: TextStyle(color: FluxForgeTheme.textSecondary),
          ),
        ),
      );
    }

    final container = containers
        .where((c) => c.id == _selectedContainerId)
        .firstOrNull;

    if (container == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Curve type selector
        Row(
          children: [
            Text(
              'Crossfade Curve:',
              style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
            ),
            const SizedBox(width: 8),
            ...CrossfadeCurve.values.map((curve) {
              final isActive = container.crossfadeCurve == curve;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () {
                    context.read<MiddlewareProvider>().updateBlendContainer(
                      container.copyWith(crossfadeCurve: curve),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.purple.withValues(alpha: 0.2)
                          : FluxForgeTheme.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isActive ? Colors.purple : FluxForgeTheme.border,
                      ),
                    ),
                    child: Text(
                      curve.displayName,
                      style: TextStyle(
                        color: isActive ? Colors.purple : FluxForgeTheme.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              );
            }),
            const Spacer(),
            GestureDetector(
              onTap: () => _showAddChildDialog(container),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 12, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      'Add Child',
                      style: TextStyle(color: Colors.green, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // RTPC Preview Slider
        BlendRtpcSlider(
          container: container,
          value: _rtpcPreviewValue,
          onChanged: (v) => setState(() => _rtpcPreviewValue = v),
          onPreview: () {
            // TODO: Preview blend at current RTPC value
          },
        ),
        const SizedBox(height: 12),
        // Visualization
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: FluxForgeTheme.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FluxForgeTheme.border),
            ),
            child: CustomPaint(
              painter: _BlendCurvePainter(
                children: container.children,
                crossfadeCurve: container.crossfadeCurve,
                selectedChildId: _selectedChildId,
                currentRtpcValue: _rtpcPreviewValue,
              ),
              child: Stack(
                children: [
                  // Child labels
                  ...container.children.map((child) {
                    return Positioned(
                      left: (child.rtpcStart + child.rtpcEnd) / 2 * 0.9 * MediaQuery.of(context).size.width * 0.4,
                      bottom: 8,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _selectedChildId = _selectedChildId == child.id ? null : child.id;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _selectedChildId == child.id
                                ? Colors.purple.withValues(alpha: 0.3)
                                : FluxForgeTheme.surface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _selectedChildId == child.id
                                  ? Colors.purple
                                  : FluxForgeTheme.border,
                            ),
                          ),
                          child: Text(
                            child.name,
                            style: TextStyle(
                              color: _selectedChildId == child.id
                                  ? Colors.purple
                                  : FluxForgeTheme.textSecondary,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
        // Child editor
        if (_selectedChildId != null) ...[
          const SizedBox(height: 12),
          _buildChildEditor(container),
        ],
      ],
    );
  }

  Widget _buildChildEditor(BlendContainer container) {
    final child = container.children.where((c) => c.id == _selectedChildId).firstOrNull;
    if (child == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Edit: ${child.name}',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  context.read<MiddlewareProvider>().removeBlendChild(container.id, child.id);
                  setState(() => _selectedChildId = null);
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.delete, size: 14, color: Colors.red),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // RTPC Range
          Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  'RTPC Range',
                  style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
                ),
              ),
              Expanded(
                child: RangeSlider(
                  values: RangeValues(child.rtpcStart, child.rtpcEnd),
                  min: 0,
                  max: 1,
                  onChanged: (values) {
                    final updatedChild = child.copyWith(
                      rtpcStart: values.start,
                      rtpcEnd: values.end,
                    );
                    context.read<MiddlewareProvider>().updateBlendChild(container.id, updatedChild);
                  },
                  activeColor: Colors.purple,
                  inactiveColor: FluxForgeTheme.surface,
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  '${child.rtpcStart.toStringAsFixed(2)} - ${child.rtpcEnd.toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.purple,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Crossfade width
          _buildSliderRow(
            label: 'Crossfade Width',
            value: child.crossfadeWidth.toStringAsFixed(2),
            sliderValue: child.crossfadeWidth,
            color: Colors.purple,
            onChanged: (v) {
              final updatedChild = child.copyWith(crossfadeWidth: v);
              context.read<MiddlewareProvider>().updateBlendChild(container.id, updatedChild);
            },
          ),
          const SizedBox(height: 8),
          // Audio Path
          _buildAudioPathRow(context, container.id, child),
        ],
      ),
    );
  }

  Widget _buildAudioPathRow(BuildContext context, int containerId, BlendChild child) {
    final blendProvider = context.read<BlendContainersProvider>();
    final hasAudio = child.audioPath != null && child.audioPath!.isNotEmpty;
    final fileName = hasAudio ? child.audioPath!.split('/').last : 'No audio file';

    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            'Audio File',
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.backgroundDeep,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: hasAudio ? Colors.green.withValues(alpha: 0.5) : FluxForgeTheme.surface,
              ),
            ),
            child: Text(
              fileName,
              style: TextStyle(
                color: hasAudio ? Colors.green : FluxForgeTheme.textSecondary,
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () async {
            final path = await AudioWaveformPickerDialog.show(
              context,
              title: 'Select Audio for Blend Child',
            );
            if (path != null) {
              blendProvider.updateChildAudioPath(containerId, child.id, path);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_open, size: 12, color: Colors.purple),
                const SizedBox(width: 4),
                Text(
                  'Browse',
                  style: TextStyle(color: Colors.purple, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
        if (hasAudio) ...[
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () {
              blendProvider.updateChildAudioPath(containerId, child.id, null);
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(Icons.close, size: 12, color: Colors.red),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSliderRow({
    required String label,
    required String value,
    required double sliderValue,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: color,
              inactiveTrackColor: FluxForgeTheme.surface,
              thumbColor: color,
            ),
            child: Slider(
              value: sliderValue.clamp(0.0, 1.0),
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  void _showAddChildDialog(BlendContainer container) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.surfaceDark,
        title: Text(
          'Add Blend Child',
          style: TextStyle(color: FluxForgeTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: FluxForgeTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.purple),
                ),
              ),
              style: TextStyle(color: FluxForgeTheme.textPrimary),
              onSubmitted: (name) {
                if (name.isNotEmpty) {
                  context.read<MiddlewareProvider>().addBlendChild(
                    container.id,
                    name: name,
                    rtpcStart: 0.0,
                    rtpcEnd: 0.5,
                  );
                  Navigator.pop(context);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _buildAddContainerDialog() {
    return _AddBlendContainerDialog(
      onAdd: (name, rtpcId) {
        context.read<MiddlewareProvider>().addBlendContainer(name: name, rtpcId: rtpcId);
        setState(() => _showAddContainer = false);
      },
      onCancel: () => setState(() => _showAddContainer = false),
    );
  }
}

class _AddBlendContainerDialog extends StatefulWidget {
  final void Function(String name, int rtpcId) onAdd;
  final VoidCallback onCancel;

  const _AddBlendContainerDialog({
    required this.onAdd,
    required this.onCancel,
  });

  @override
  State<_AddBlendContainerDialog> createState() => _AddBlendContainerDialogState();
}

class _AddBlendContainerDialogState extends State<_AddBlendContainerDialog> {
  final _nameController = TextEditingController();
  int _rtpcId = 1;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purple),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'New Blend Container',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Container Name',
              labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: FluxForgeTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.purple),
              ),
            ),
            style: TextStyle(color: FluxForgeTheme.textPrimary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'RTPC ID:',
                style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: FluxForgeTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.purple),
                    ),
                  ),
                  style: TextStyle(color: FluxForgeTheme.textPrimary),
                  onChanged: (v) => _rtpcId = int.tryParse(v) ?? 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: widget.onCancel,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FluxForgeTheme.border),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  if (_nameController.text.isNotEmpty) {
                    widget.onAdd(_nameController.text, _rtpcId);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.purple,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Create',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Custom painter for blend curve visualization
class _BlendCurvePainter extends CustomPainter {
  final List<BlendChild> children;
  final CrossfadeCurve crossfadeCurve;
  final int? selectedChildId;
  final double? currentRtpcValue;

  _BlendCurvePainter({
    required this.children,
    required this.crossfadeCurve,
    this.selectedChildId,
    this.currentRtpcValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (children.isEmpty) return;

    final colors = [
      Colors.purple,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.pink,
      Colors.cyan,
    ];

    // Draw grid
    final gridPaint = Paint()
      ..color = FluxForgeTheme.border.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    for (int i = 0; i <= 10; i++) {
      final x = size.width * i / 10;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw each child's curve
    for (int i = 0; i < children.length; i++) {
      final child = children[i];
      final color = colors[i % colors.length];
      final isSelected = child.id == selectedChildId;

      final paint = Paint()
        ..color = color.withValues(alpha: isSelected ? 0.8 : 0.5)
        ..strokeWidth = isSelected ? 3 : 2
        ..style = PaintingStyle.stroke;

      final fillPaint = Paint()
        ..color = color.withValues(alpha: isSelected ? 0.2 : 0.1)
        ..style = PaintingStyle.fill;

      final path = Path();
      final fillPath = Path();

      final startX = child.rtpcStart * size.width;
      final endX = child.rtpcEnd * size.width;
      final fadeWidth = child.crossfadeWidth * size.width;

      // Build curve path
      fillPath.moveTo(startX, size.height);

      // Fade in
      if (startX > 0) {
        path.moveTo(startX - fadeWidth, size.height);
        fillPath.lineTo(startX - fadeWidth, size.height);

        for (double t = 0; t <= 1; t += 0.05) {
          final x = startX - fadeWidth + fadeWidth * t;
          final y = size.height - size.height * _applyCurve(t);
          if (t == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
          fillPath.lineTo(x, y);
        }
      } else {
        path.moveTo(0, 0);
        fillPath.lineTo(0, 0);
      }

      // Full volume section
      path.lineTo(endX, 0);
      fillPath.lineTo(endX, 0);

      // Fade out
      if (endX < size.width) {
        for (double t = 0; t <= 1; t += 0.05) {
          final x = endX + fadeWidth * t;
          final y = size.height * _applyCurve(t);
          path.lineTo(x, y);
          fillPath.lineTo(x, y);
        }
      }

      fillPath.lineTo(endX + fadeWidth, size.height);
      fillPath.close();

      canvas.drawPath(fillPath, fillPaint);
      canvas.drawPath(path, paint);
    }

    // Draw current RTPC position indicator
    if (currentRtpcValue != null) {
      final indicatorX = currentRtpcValue! * size.width;
      final indicatorPaint = Paint()
        ..color = Colors.purple
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(indicatorX, 0),
        Offset(indicatorX, size.height),
        indicatorPaint,
      );
      // Draw diamond at bottom
      final diamondPath = Path()
        ..moveTo(indicatorX, size.height - 8)
        ..lineTo(indicatorX - 6, size.height)
        ..lineTo(indicatorX, size.height + 8)
        ..lineTo(indicatorX + 6, size.height)
        ..close();
      canvas.drawPath(diamondPath, Paint()..color = Colors.purple);
    }

    // Draw RTPC axis label
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'RTPC Value →',
        style: TextStyle(
          color: FluxForgeTheme.textSecondary,
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - textPainter.width - 8, size.height - 16));
  }

  double _applyCurve(double t) {
    switch (crossfadeCurve) {
      case CrossfadeCurve.linear:
        return t;
      case CrossfadeCurve.equalPower:
        return t * t * (3 - 2 * t);
      case CrossfadeCurve.sCurve:
        return t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t);
      case CrossfadeCurve.sinCos:
        return 0.5 - 0.5 * (t * 3.14159).cos();
    }
  }

  @override
  bool shouldRepaint(covariant _BlendCurvePainter oldDelegate) {
    return oldDelegate.children != children ||
        oldDelegate.crossfadeCurve != crossfadeCurve ||
        oldDelegate.selectedChildId != selectedChildId ||
        oldDelegate.currentRtpcValue != currentRtpcValue;
  }
}

extension on double {
  double cos() => Math.cos(this);
}

class Math {
  static double cos(double x) {
    // Simple cosine approximation
    x = x % (2 * 3.14159);
    return 1 - (x * x / 2) + (x * x * x * x / 24);
  }
}
