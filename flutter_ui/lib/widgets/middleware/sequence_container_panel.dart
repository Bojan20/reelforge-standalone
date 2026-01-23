/// FluxForge Studio Sequence Container Panel
///
/// Timed sequence of sounds with visual timeline.
/// Perfect for reel cascades, win celebrations, multi-step events.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/middleware_models.dart';
import '../../providers/middleware_provider.dart';
import '../../providers/subsystems/sequence_containers_provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../common/audio_waveform_picker_dialog.dart';
import 'container_ab_comparison_panel.dart';
import 'container_preset_library_panel.dart';
import 'container_visualization_widgets.dart';

/// Sequence Container Panel Widget
class SequenceContainerPanel extends StatefulWidget {
  const SequenceContainerPanel({super.key});

  @override
  State<SequenceContainerPanel> createState() => _SequenceContainerPanelState();
}

class _SequenceContainerPanelState extends State<SequenceContainerPanel> {
  int? _selectedContainerId;
  int? _selectedStepIndex;
  bool _showAddContainer = false;
  bool _isPlaying = false;
  int? _currentPlayingStepIndex;

  @override
  Widget build(BuildContext context) {
    return Selector<MiddlewareProvider, List<SequenceContainer>>(
      selector: (_, p) => p.sequenceContainers,
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
                    // Timeline view
                    Expanded(
                      child: _buildTimelineView(containers),
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
        Icon(Icons.queue_music, color: Colors.teal, size: 20),
        const SizedBox(width: 8),
        Text(
          'Sequence Containers',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        if (_selectedContainerId != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => ContainerABComparisonDialog.show(
                context,
                containerId: _selectedContainerId!,
                containerType: 'sequence',
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
        GestureDetector(
          onTap: () => ContainerPresetLibraryDialog.show(
            context,
            targetContainerId: _selectedContainerId,
            targetContainerType: 'sequence',
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
              color: Colors.teal.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.teal),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 14, color: Colors.teal),
                const SizedBox(width: 4),
                Text(
                  'New Sequence',
                  style: TextStyle(
                    color: Colors.teal,
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

  Widget _buildContainerList(List<SequenceContainer> containers) {
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
            Icon(Icons.queue_music, size: 32, color: FluxForgeTheme.textSecondary),
            const SizedBox(height: 8),
            Text(
              'No sequences',
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
          final totalDuration = _calculateTotalDuration(container);

          return GestureDetector(
            onTap: () => setState(() {
              _selectedContainerId = isSelected ? null : container.id;
              _selectedStepIndex = null;
            }),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.teal.withValues(alpha: 0.1)
                    : Colors.transparent,
                border: Border(
                  left: isSelected
                      ? BorderSide(color: Colors.teal, width: 3)
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
                        Icons.queue_music,
                        size: 14,
                        color: container.enabled ? Colors.teal : FluxForgeTheme.textSecondary,
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
                          context.read<MiddlewareProvider>().updateSequenceContainer(
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
                          color: _getEndBehaviorColor(container.endBehavior).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          container.endBehavior.displayName,
                          style: TextStyle(
                            color: _getEndBehaviorColor(container.endBehavior),
                            fontSize: 9,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${container.steps.length} steps',
                        style: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${totalDuration.toStringAsFixed(0)}ms',
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

  Color _getEndBehaviorColor(SequenceEndBehavior behavior) {
    switch (behavior) {
      case SequenceEndBehavior.stop:
        return Colors.red;
      case SequenceEndBehavior.loop:
        return Colors.green;
      case SequenceEndBehavior.holdLast:
        return Colors.orange;
      case SequenceEndBehavior.pingPong:
        return Colors.purple;
    }
  }

  double _calculateTotalDuration(SequenceContainer container) {
    double total = 0;
    for (final step in container.steps) {
      total += step.delayMs + step.durationMs;
    }
    return total / container.speed;
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

  Widget _buildTimelineView(List<SequenceContainer> containers) {
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
                'Select a sequence to view timeline',
                style: TextStyle(color: FluxForgeTheme.textSecondary),
              ),
            ],
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
        // Settings bar
        _buildSettingsBar(container),
        const SizedBox(height: 12),
        // Enhanced timeline visualization
        Expanded(
          child: SequenceTimelineVisualization(
            container: container,
            currentStepIndex: _currentPlayingStepIndex,
            selectedStepIndex: _selectedStepIndex,
            isPlaying: _isPlaying,
            onStepSelected: (index) => setState(() => _selectedStepIndex = index),
            onPlay: () => _startPreview(container),
            onStop: _stopPreview,
          ),
        ),
        // Step editor
        if (_selectedStepIndex != null) ...[
          const SizedBox(height: 12),
          _buildStepEditor(container),
        ],
      ],
    );
  }

  void _startPreview(SequenceContainer container) {
    if (container.steps.isEmpty) return;
    setState(() {
      _isPlaying = true;
      _currentPlayingStepIndex = 0;
    });
    _playNextStep(container, 0);
  }

  void _playNextStep(SequenceContainer container, int stepIndex) {
    if (!_isPlaying || stepIndex >= container.steps.length) {
      if (_isPlaying && container.endBehavior == SequenceEndBehavior.loop) {
        // Loop back to start
        setState(() => _currentPlayingStepIndex = 0);
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_isPlaying) _playNextStep(container, 0);
        });
      } else {
        _stopPreview();
      }
      return;
    }

    setState(() => _currentPlayingStepIndex = stepIndex);
    final step = container.steps[stepIndex];
    final durationMs = (step.durationMs / container.speed).round();

    Future.delayed(Duration(milliseconds: durationMs), () {
      if (_isPlaying) _playNextStep(container, stepIndex + 1);
    });
  }

  void _stopPreview() {
    setState(() {
      _isPlaying = false;
      _currentPlayingStepIndex = null;
    });
  }

  Widget _buildSettingsBar(SequenceContainer container) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Row(
        children: [
          // End behavior selector
          Text(
            'End:',
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
          ),
          const SizedBox(width: 8),
          ...SequenceEndBehavior.values.map((behavior) {
            final isActive = container.endBehavior == behavior;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: () {
                  context.read<MiddlewareProvider>().updateSequenceContainer(
                    container.copyWith(endBehavior: behavior),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? _getEndBehaviorColor(behavior).withValues(alpha: 0.2)
                        : FluxForgeTheme.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isActive
                          ? _getEndBehaviorColor(behavior)
                          : FluxForgeTheme.border,
                    ),
                  ),
                  child: Text(
                    behavior.displayName,
                    style: TextStyle(
                      color: isActive
                          ? _getEndBehaviorColor(behavior)
                          : FluxForgeTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          // Speed control
          Text(
            'Speed:',
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                activeTrackColor: Colors.teal,
                inactiveTrackColor: FluxForgeTheme.surface,
                thumbColor: Colors.teal,
              ),
              child: Slider(
                value: container.speed,
                min: 0.25,
                max: 4.0,
                onChanged: (v) {
                  context.read<MiddlewareProvider>().updateSequenceContainer(
                    container.copyWith(speed: v),
                  );
                },
              ),
            ),
          ),
          Text(
            '${container.speed.toStringAsFixed(2)}x',
            style: TextStyle(
              color: Colors.teal,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 16),
          // Add step button
          GestureDetector(
            onTap: () => _showAddStepDialog(container),
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
                    'Add Step',
                    style: TextStyle(color: Colors.green, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(SequenceContainer container) {
    if (container.steps.isEmpty) {
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
              Icon(Icons.timeline, size: 32, color: FluxForgeTheme.textSecondary),
              const SizedBox(height: 8),
              Text(
                'No steps in sequence',
                style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _showAddStepDialog(container),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Text(
                    'Add First Step',
                    style: TextStyle(color: Colors.green, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final totalDuration = _calculateTotalDuration(container);

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        children: [
          // Timeline ruler
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: CustomPaint(
              painter: _TimelineRulerPainter(
                totalDuration: totalDuration,
                color: FluxForgeTheme.textSecondary,
              ),
              size: Size.infinite,
            ),
          ),
          // Steps
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  double currentX = 0;
                  final width = constraints.maxWidth;

                  return Stack(
                    children: [
                      // Grid lines
                      CustomPaint(
                        painter: _TimelineGridPainter(
                          totalDuration: totalDuration,
                          color: FluxForgeTheme.border.withValues(alpha: 0.3),
                        ),
                        size: Size(width, constraints.maxHeight),
                      ),
                      // Step blocks
                      ...container.steps.asMap().entries.map((entry) {
                        final index = entry.key;
                        final step = entry.value;
                        final stepStart = currentX;
                        final delayWidth = (step.delayMs / totalDuration) * width;
                        final durationWidth = (step.durationMs / totalDuration) * width;

                        currentX += delayWidth + durationWidth;

                        final isSelected = _selectedStepIndex == index;

                        return Positioned(
                          left: stepStart + delayWidth,
                          top: 8,
                          bottom: 8,
                          width: durationWidth.clamp(40.0, double.infinity),
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _selectedStepIndex = isSelected ? null : index;
                            }),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.teal.withValues(alpha: 0.4)
                                    : Colors.teal.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isSelected ? Colors.teal : Colors.teal.withValues(alpha: 0.5),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    step.childName,
                                    style: TextStyle(
                                      color: FluxForgeTheme.textPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${step.durationMs.toStringAsFixed(0)}ms',
                                    style: TextStyle(
                                      color: FluxForgeTheme.textSecondary,
                                      fontSize: 9,
                                    ),
                                  ),
                                  if (step.loopCount > 1)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Text(
                                        'x${step.loopCount}',
                                        style: TextStyle(
                                          color: Colors.orange,
                                          fontSize: 8,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepEditor(SequenceContainer container) {
    if (_selectedStepIndex == null || _selectedStepIndex! >= container.steps.length) {
      return const SizedBox.shrink();
    }

    final step = container.steps[_selectedStepIndex!];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit, size: 14, color: Colors.teal),
              const SizedBox(width: 8),
              Text(
                'Edit Step ${_selectedStepIndex! + 1}: ${step.childName}',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  context.read<MiddlewareProvider>().removeSequenceStep(container.id, _selectedStepIndex!);
                  setState(() => _selectedStepIndex = null);
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
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _selectedStepIndex = null),
                child: Icon(Icons.close, size: 14, color: FluxForgeTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStepSlider(
                  label: 'Delay',
                  value: step.delayMs,
                  maxValue: 2000,
                  unit: 'ms',
                  color: Colors.orange,
                  onChanged: (v) {
                    final updated = step.copyWith(delayMs: v);
                    context.read<MiddlewareProvider>().updateSequenceStep(container.id, _selectedStepIndex!, updated);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStepSlider(
                  label: 'Duration',
                  value: step.durationMs,
                  maxValue: 5000,
                  unit: 'ms',
                  color: Colors.teal,
                  onChanged: (v) {
                    final updated = step.copyWith(durationMs: v);
                    context.read<MiddlewareProvider>().updateSequenceStep(container.id, _selectedStepIndex!, updated);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildStepSlider(
                  label: 'Fade In',
                  value: step.fadeInMs,
                  maxValue: 500,
                  unit: 'ms',
                  color: Colors.green,
                  onChanged: (v) {
                    final updated = step.copyWith(fadeInMs: v);
                    context.read<MiddlewareProvider>().updateSequenceStep(container.id, _selectedStepIndex!, updated);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStepSlider(
                  label: 'Fade Out',
                  value: step.fadeOutMs,
                  maxValue: 500,
                  unit: 'ms',
                  color: Colors.red,
                  onChanged: (v) {
                    final updated = step.copyWith(fadeOutMs: v);
                    context.read<MiddlewareProvider>().updateSequenceStep(container.id, _selectedStepIndex!, updated);
                  },
                ),
              ),
              const SizedBox(width: 16),
              // Loop count
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Loop Count',
                    style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: FluxForgeTheme.border),
                    ),
                    child: DropdownButton<int>(
                      value: step.loopCount,
                      underline: const SizedBox.shrink(),
                      dropdownColor: FluxForgeTheme.surfaceDark,
                      style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
                      items: List.generate(10, (i) => i + 1).map((count) {
                        return DropdownMenuItem(
                          value: count,
                          child: Text('$count'),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          final updated = step.copyWith(loopCount: v);
                          context.read<MiddlewareProvider>().updateSequenceStep(container.id, _selectedStepIndex!, updated);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Audio Path
          _buildAudioPathRow(context, container.id, step),
        ],
      ),
    );
  }

  Widget _buildAudioPathRow(BuildContext context, int containerId, SequenceStep step) {
    final seqProvider = context.read<SequenceContainersProvider>();
    final hasAudio = step.audioPath != null && step.audioPath!.isNotEmpty;
    final fileName = hasAudio ? step.audioPath!.split('/').last : 'No audio file';

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
              title: 'Select Audio for Sequence Step',
            );
            if (path != null) {
              seqProvider.updateStepAudioPath(containerId, step.index, path);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_open, size: 12, color: Colors.teal),
                const SizedBox(width: 4),
                Text(
                  'Browse',
                  style: TextStyle(color: Colors.teal, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
        if (hasAudio) ...[
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () {
              seqProvider.updateStepAudioPath(containerId, step.index, null);
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

  Widget _buildStepSlider({
    required String label,
    required double value,
    required double maxValue,
    required String unit,
    required Color color,
    required ValueChanged<double> onChanged,
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
              '${value.toStringAsFixed(0)} $unit',
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            activeTrackColor: color,
            inactiveTrackColor: FluxForgeTheme.surface,
            thumbColor: color,
          ),
          child: Slider(
            value: value / maxValue,
            onChanged: (v) => onChanged(v * maxValue),
          ),
        ),
      ],
    );
  }

  void _showAddStepDialog(SequenceContainer container) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.surfaceDark,
        title: Text(
          'Add Step',
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
                  borderSide: BorderSide(color: Colors.teal),
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
                context.read<MiddlewareProvider>().addSequenceStep(
                  container.id,
                  childId: container.steps.length,
                  childName: controller.text,
                  delayMs: 0.0,
                  durationMs: 500.0,
                );
                Navigator.pop(context);
              }
            },
            child: Text('Add', style: TextStyle(color: Colors.teal)),
          ),
        ],
      ),
    );
  }

  Widget _buildAddContainerDialog() {
    return _AddSequenceContainerDialog(
      onAdd: (name) {
        context.read<MiddlewareProvider>().addSequenceContainer(name: name);
        setState(() => _showAddContainer = false);
      },
      onCancel: () => setState(() => _showAddContainer = false),
    );
  }
}

class _AddSequenceContainerDialog extends StatefulWidget {
  final void Function(String name) onAdd;
  final VoidCallback onCancel;

  const _AddSequenceContainerDialog({
    required this.onAdd,
    required this.onCancel,
  });

  @override
  State<_AddSequenceContainerDialog> createState() => _AddSequenceContainerDialogState();
}

class _AddSequenceContainerDialogState extends State<_AddSequenceContainerDialog> {
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
        border: Border.all(color: Colors.teal),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'New Sequence Container',
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
              labelText: 'Sequence Name',
              labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: FluxForgeTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.teal),
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
                    color: Colors.teal,
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

/// Timeline ruler painter
class _TimelineRulerPainter extends CustomPainter {
  final double totalDuration;
  final Color color;

  _TimelineRulerPainter({
    required this.totalDuration,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    // Draw major ticks every 500ms
    final tickInterval = 500.0;
    final tickCount = (totalDuration / tickInterval).ceil();

    for (int i = 0; i <= tickCount; i++) {
      final time = i * tickInterval;
      final x = (time / totalDuration) * size.width;

      // Major tick
      canvas.drawLine(Offset(x, size.height - 8), Offset(x, size.height), paint);

      // Label
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${time.toStringAsFixed(0)}',
          style: TextStyle(color: color, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, 2));
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineRulerPainter oldDelegate) {
    return oldDelegate.totalDuration != totalDuration;
  }
}

/// Timeline grid painter
class _TimelineGridPainter extends CustomPainter {
  final double totalDuration;
  final Color color;

  _TimelineGridPainter({
    required this.totalDuration,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    // Draw vertical lines every 500ms
    final tickInterval = 500.0;
    final tickCount = (totalDuration / tickInterval).ceil();

    for (int i = 0; i <= tickCount; i++) {
      final time = i * tickInterval;
      final x = (time / totalDuration) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineGridPainter oldDelegate) {
    return oldDelegate.totalDuration != totalDuration;
  }
}
