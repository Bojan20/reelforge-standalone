/// FluxForge Studio Random Container Panel
///
/// Weighted random sound selection with pitch/volume variation.
/// Multiple selection modes: Random, Shuffle, Round Robin.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/middleware_models.dart';
import '../../providers/middleware_provider.dart';
import '../../providers/subsystems/random_containers_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// Random Container Panel Widget
class RandomContainerPanel extends StatefulWidget {
  const RandomContainerPanel({super.key});

  @override
  State<RandomContainerPanel> createState() => _RandomContainerPanelState();
}

class _RandomContainerPanelState extends State<RandomContainerPanel> {
  int? _selectedContainerId;
  int? _selectedChildId;
  bool _showAddContainer = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, provider, _) {
        final containers = provider.randomContainers;

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
              _buildHeader(provider),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Container list
                    SizedBox(
                      width: 220,
                      child: _buildContainerList(containers, provider),
                    ),
                    const SizedBox(width: 16),
                    // Children and settings
                    Expanded(
                      child: _buildContainerEditor(provider),
                    ),
                  ],
                ),
              ),
              if (_showAddContainer)
                _buildAddContainerDialog(provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(MiddlewareProvider provider) {
    return Row(
      children: [
        Icon(Icons.shuffle, color: Colors.amber, size: 20),
        const SizedBox(width: 8),
        Text(
          'Random Containers',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() => _showAddContainer = true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.amber),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 14, color: Colors.amber),
                const SizedBox(width: 4),
                Text(
                  'New Container',
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
      ],
    );
  }

  Widget _buildContainerList(List<RandomContainer> containers, MiddlewareProvider provider) {
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
            Icon(Icons.shuffle, size: 32, color: FluxForgeTheme.textSecondary),
            const SizedBox(height: 8),
            Text(
              'No random containers',
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
                    ? Colors.amber.withValues(alpha: 0.1)
                    : Colors.transparent,
                border: Border(
                  left: isSelected
                      ? BorderSide(color: Colors.amber, width: 3)
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
                        Icons.shuffle,
                        size: 14,
                        color: container.enabled ? Colors.amber : FluxForgeTheme.textSecondary,
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
                      _buildMiniToggle(
                        value: container.enabled,
                        onChanged: (v) {
                          provider.updateRandomContainer(
                            container.copyWith(enabled: v),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getModeColor(container.mode).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          container.mode.displayName,
                          style: TextStyle(
                            color: _getModeColor(container.mode),
                            fontSize: 9,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${container.children.length} sounds',
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

  Color _getModeColor(RandomMode mode) {
    switch (mode) {
      case RandomMode.random:
        return Colors.amber;
      case RandomMode.shuffle:
        return Colors.purple;
      case RandomMode.shuffleWithHistory:
        return Colors.blue;
      case RandomMode.roundRobin:
        return Colors.green;
    }
  }

  Widget _buildMiniToggle({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 28,
        height: 16,
        decoration: BoxDecoration(
          color: value
              ? Colors.green.withValues(alpha: 0.3)
              : FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value ? Colors.green : FluxForgeTheme.border,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: value ? Colors.green : FluxForgeTheme.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContainerEditor(MiddlewareProvider provider) {
    if (_selectedContainerId == null) {
      return Container(
        decoration: BoxDecoration(
          color: FluxForgeTheme.surface.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.border),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app, size: 32, color: FluxForgeTheme.textSecondary),
              const SizedBox(height: 8),
              Text(
                'Select a container to edit',
                style: TextStyle(color: FluxForgeTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    final container = provider.randomContainers
        .where((c) => c.id == _selectedContainerId)
        .firstOrNull;

    if (container == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mode selector and global settings
        _buildContainerSettings(provider, container),
        const SizedBox(height: 16),
        // Children list with weights
        Expanded(
          child: _buildChildrenList(provider, container),
        ),
        // Selected child editor
        if (_selectedChildId != null) ...[
          const SizedBox(height: 12),
          _buildChildEditor(provider, container),
        ],
      ],
    );
  }

  Widget _buildContainerSettings(MiddlewareProvider provider, RandomContainer container) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode selector
          Row(
            children: [
              Text(
                'Selection Mode:',
                style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
              ),
              const SizedBox(width: 12),
              ...RandomMode.values.map((mode) {
                final isActive = container.mode == mode;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: GestureDetector(
                    onTap: () {
                      provider.updateRandomContainer(
                        container.copyWith(mode: mode),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive
                            ? _getModeColor(mode).withValues(alpha: 0.2)
                            : FluxForgeTheme.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isActive ? _getModeColor(mode) : FluxForgeTheme.border,
                        ),
                      ),
                      child: Text(
                        mode.displayName,
                        style: TextStyle(
                          color: isActive ? _getModeColor(mode) : FluxForgeTheme.textSecondary,
                          fontSize: 10,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 12),
          // Avoid repeat count (for shuffle modes)
          if (container.mode == RandomMode.shuffle ||
              container.mode == RandomMode.shuffleWithHistory)
            Row(
              children: [
                Text(
                  'Avoid Repeat:',
                  style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 60,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: FluxForgeTheme.border),
                    ),
                    child: DropdownButton<int>(
                      value: container.avoidRepeatCount,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      dropdownColor: FluxForgeTheme.surfaceDark,
                      style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
                      items: List.generate(6, (i) => i).map((count) {
                        return DropdownMenuItem(
                          value: count,
                          child: Text('$count'),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          provider.updateRandomContainer(
                            container.copyWith(avoidRepeatCount: v),
                          );
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'last sounds',
                  style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
                ),
              ],
            ),
          const SizedBox(height: 12),
          // Global variation
          Text(
            'Global Variation',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildVariationSlider(
                  label: 'Pitch',
                  minValue: container.globalPitchMin,
                  maxValue: container.globalPitchMax,
                  unit: 'st',
                  color: Colors.cyan,
                  onChanged: (min, max) {
                    provider.updateRandomContainer(
                      container.copyWith(
                        globalPitchMin: min,
                        globalPitchMax: max,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildVariationSlider(
                  label: 'Volume',
                  minValue: container.globalVolumeMin,
                  maxValue: container.globalVolumeMax,
                  unit: 'dB',
                  color: Colors.orange,
                  onChanged: (min, max) {
                    provider.updateRandomContainer(
                      container.copyWith(
                        globalVolumeMin: min,
                        globalVolumeMax: max,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVariationSlider({
    required String label,
    required double minValue,
    required double maxValue,
    required String unit,
    required Color color,
    required void Function(double min, double max) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10),
            ),
            Text(
              '${minValue.toStringAsFixed(1)} / +${maxValue.toStringAsFixed(1)} $unit',
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        RangeSlider(
          values: RangeValues(minValue / 12.0 + 0.5, maxValue / 12.0 + 0.5),
          min: 0,
          max: 1,
          onChanged: (values) {
            onChanged(
              (values.start - 0.5) * 12.0,
              (values.end - 0.5) * 12.0,
            );
          },
          activeColor: color,
          inactiveColor: FluxForgeTheme.surface,
        ),
      ],
    );
  }

  Widget _buildChildrenList(MiddlewareProvider provider, RandomContainer container) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                Expanded(flex: 3, child: _listHeader('Sound')),
                Expanded(flex: 2, child: _listHeader('Weight')),
                Expanded(flex: 2, child: _listHeader('Probability')),
                const SizedBox(width: 32),
              ],
            ),
          ),
          // Children
          Expanded(
            child: container.children.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.music_off, size: 24, color: FluxForgeTheme.textSecondary),
                        const SizedBox(height: 8),
                        Text(
                          'No sounds added',
                          style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => _showAddChildDialog(provider, container),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.green),
                            ),
                            child: Text(
                              'Add Sound',
                              style: TextStyle(color: Colors.green, fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: container.children.length,
                    itemBuilder: (context, index) {
                      final child = container.children[index];
                      final totalWeight = container.children.fold(0.0, (sum, c) => sum + c.weight);
                      final probability = totalWeight > 0 ? child.weight / totalWeight : 0.0;
                      final isSelected = _selectedChildId == child.id;

                      return GestureDetector(
                        onTap: () => setState(() {
                          _selectedChildId = isSelected ? null : child.id;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.amber.withValues(alpha: 0.1)
                                : Colors.transparent,
                            border: Border(
                              left: isSelected
                                  ? BorderSide(color: Colors.amber, width: 2)
                                  : BorderSide.none,
                              bottom: BorderSide(
                                color: FluxForgeTheme.border.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Name
                              Expanded(
                                flex: 3,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.music_note,
                                      size: 14,
                                      color: Colors.amber,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      child.name,
                                      style: TextStyle(
                                        color: FluxForgeTheme.textPrimary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Weight slider
                              Expanded(
                                flex: 2,
                                child: SliderTheme(
                                  data: SliderThemeData(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                    activeTrackColor: Colors.amber,
                                    inactiveTrackColor: FluxForgeTheme.surface,
                                    thumbColor: Colors.amber,
                                  ),
                                  child: Slider(
                                    value: child.weight / 10.0,
                                    onChanged: (v) {
                                      final updated = child.copyWith(weight: v * 10.0);
                                      provider.updateRandomChild(container.id, updated);
                                    },
                                  ),
                                ),
                              ),
                              // Probability bar
                              Expanded(
                                flex: 2,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: FluxForgeTheme.surface,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                        child: FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: probability,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.amber.withValues(alpha: 0.7),
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 36,
                                      child: Text(
                                        '${(probability * 100).toStringAsFixed(0)}%',
                                        style: TextStyle(
                                          color: Colors.amber,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Delete button
                              GestureDetector(
                                onTap: () {
                                  provider.removeRandomChild(container.id, child.id);
                                  if (_selectedChildId == child.id) {
                                    setState(() => _selectedChildId = null);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: FluxForgeTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // Add button
          if (container.children.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: FluxForgeTheme.border)),
              ),
              child: GestureDetector(
                onTap: () => _showAddChildDialog(provider, container),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 14, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      'Add Sound',
                      style: TextStyle(color: Colors.green, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _listHeader(String label) {
    return Text(
      label,
      style: TextStyle(
        color: FluxForgeTheme.textSecondary,
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildChildEditor(MiddlewareProvider provider, RandomContainer container) {
    final child = container.children.where((c) => c.id == _selectedChildId).firstOrNull;
    if (child == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 14, color: Colors.amber),
              const SizedBox(width: 8),
              Text(
                'Per-Sound Variation: ${child.name}',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _selectedChildId = null),
                child: Icon(Icons.close, size: 14, color: FluxForgeTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildVariationSlider(
                  label: 'Pitch Variation',
                  minValue: child.pitchMin,
                  maxValue: child.pitchMax,
                  unit: 'st',
                  color: Colors.cyan,
                  onChanged: (min, max) {
                    provider.updateRandomChild(
                      container.id,
                      child.copyWith(pitchMin: min, pitchMax: max),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildVariationSlider(
                  label: 'Volume Variation',
                  minValue: child.volumeMin,
                  maxValue: child.volumeMax,
                  unit: 'dB',
                  color: Colors.orange,
                  onChanged: (min, max) {
                    provider.updateRandomChild(
                      container.id,
                      child.copyWith(volumeMin: min, volumeMax: max),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Audio Path
          _buildAudioPathRow(context, container.id, child),
        ],
      ),
    );
  }

  Widget _buildAudioPathRow(BuildContext context, int containerId, RandomChild child) {
    final randomProvider = context.read<RandomContainersProvider>();
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
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['wav', 'mp3', 'ogg', 'flac', 'aiff'],
            );
            if (result != null && result.files.single.path != null) {
              randomProvider.updateChildAudioPath(containerId, child.id, result.files.single.path);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_open, size: 12, color: Colors.amber),
                const SizedBox(width: 4),
                Text(
                  'Browse',
                  style: TextStyle(color: Colors.amber, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
        if (hasAudio) ...[
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () {
              randomProvider.updateChildAudioPath(containerId, child.id, null);
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

  void _showAddChildDialog(MiddlewareProvider provider, RandomContainer container) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.surfaceDark,
        title: Text(
          'Add Sound',
          style: TextStyle(color: FluxForgeTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Sound Name',
                labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: FluxForgeTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.amber),
                ),
              ),
              style: TextStyle(color: FluxForgeTheme.textPrimary),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                provider.addRandomChild(
                  container.id,
                  name: controller.text,
                  weight: 1.0,
                );
                Navigator.pop(context);
              }
            },
            child: Text('Add', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  Widget _buildAddContainerDialog(MiddlewareProvider provider) {
    return _AddRandomContainerDialog(
      onAdd: (name) {
        provider.addRandomContainer(name: name);
        setState(() => _showAddContainer = false);
      },
      onCancel: () => setState(() => _showAddContainer = false),
    );
  }
}

class _AddRandomContainerDialog extends StatefulWidget {
  final void Function(String name) onAdd;
  final VoidCallback onCancel;

  const _AddRandomContainerDialog({
    required this.onAdd,
    required this.onCancel,
  });

  @override
  State<_AddRandomContainerDialog> createState() => _AddRandomContainerDialogState();
}

class _AddRandomContainerDialogState extends State<_AddRandomContainerDialog> {
  final _nameController = TextEditingController();

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
        border: Border.all(color: Colors.amber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'New Random Container',
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
                borderSide: BorderSide(color: Colors.amber),
              ),
            ),
            style: TextStyle(color: FluxForgeTheme.textPrimary),
            autofocus: true,
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
                    widget.onAdd(_nameController.text);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Create',
                    style: TextStyle(
                      color: Colors.black,
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
