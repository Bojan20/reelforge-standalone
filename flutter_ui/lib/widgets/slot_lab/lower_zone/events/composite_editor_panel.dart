/// Composite Editor Panel
///
/// Comprehensive event editor for Lower Zone EVENTS > Composite Editor sub-tab.
///
/// Features:
/// - Event properties (name, category, color, priority, maxInstances)
/// - Layer list with interactive controls (volume, pan, delay sliders)
/// - Trigger stages editor (add/remove stages)
/// - Add/delete layers
/// - Preview playback per layer
/// - Real-time sync with MiddlewareProvider
///
/// Task: SL-LZ-P0.3
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../models/slot_audio_events.dart';
import '../../../../providers/middleware_provider.dart';
import '../../../../services/audio_playback_service.dart';
import '../../../../theme/fluxforge_theme.dart';
import '../../../common/audio_waveform_picker_dialog.dart';
import '../../stage_editor_dialog.dart';

/// Composite Editor Panel
class CompositeEditorPanel extends StatefulWidget {
  final String? selectedEventId;

  const CompositeEditorPanel({
    super.key,
    this.selectedEventId,
  });

  @override
  State<CompositeEditorPanel> createState() => _CompositeEditorPanelState();
}

class _CompositeEditorPanelState extends State<CompositeEditorPanel> {
  // Track expanded layers for property controls
  Set<String> _expandedLayerIds = {};

  @override
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        if (widget.selectedEventId == null) {
          return _buildEmptyState(
            'No event selected',
            'Select an event from the Event List tab to edit its properties',
          );
        }

        final event = middleware.compositeEvents.where(
          (e) => e.id == widget.selectedEventId,
        ).firstOrNull;

        if (event == null) {
          return _buildEmptyState(
            'Event not found',
            'The selected event may have been deleted',
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildEventPropertiesSection(event, middleware),
              const SizedBox(height: 16),
              Divider(color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 16),
              _buildLayersSection(event, middleware),
              const SizedBox(height: 16),
              Divider(color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 16),
              _buildTriggerStagesSection(event, middleware),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String title, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.edit_note, size: 64, color: Colors.white12),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white38,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white24,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEventPropertiesSection(SlotCompositeEvent event, MiddlewareProvider middleware) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('EVENT PROPERTIES'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF16161C),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            children: [
              // Event name
              _buildPropertyField(
                label: 'Name',
                child: TextField(
                  controller: TextEditingController(text: event.name),
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF0D0D10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onSubmitted: (value) {
                    middleware.updateCompositeEvent(
                      event.copyWith(name: value.trim()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // Category
              _buildPropertyField(
                label: 'Category',
                child: TextField(
                  controller: TextEditingController(text: event.category),
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF0D0D10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    hintText: 'spin, win, feature, ui...',
                    hintStyle: TextStyle(color: Colors.white24, fontSize: 11),
                  ),
                  onSubmitted: (value) {
                    middleware.updateCompositeEvent(
                      event.copyWith(category: value.trim()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // Master volume
              _buildPropertyField(
                label: 'Master Volume',
                child: Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: event.masterVolume,
                        min: 0.0,
                        max: 2.0,
                        divisions: 40,
                        label: '${(event.masterVolume * 100).toInt()}%',
                        onChanged: (v) {
                          middleware.updateCompositeEvent(
                            event.copyWith(masterVolume: v),
                          );
                        },
                        activeColor: FluxForgeTheme.accentBlue,
                      ),
                    ),
                    SizedBox(
                      width: 50,
                      child: Text(
                        '${(event.masterVolume * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                          fontFamily: 'monospace',
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLayersSection(SlotCompositeEvent event, MiddlewareProvider middleware) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSectionHeader('LAYERS (${event.layers.length})'),
            const Spacer(),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Layer', style: TextStyle(fontSize: 11)),
              onPressed: () async {
                final audioPath = await AudioWaveformPickerDialog.show(
                  context,
                  title: 'Select Audio for Layer',
                );
                if (audioPath != null) {
                  final newLayer = SlotEventLayer(
                    id: 'layer_${DateTime.now().millisecondsSinceEpoch}',
                    name: 'Layer ${event.layers.length + 1}',
                    audioPath: audioPath,
                    volume: 1.0,
                    pan: 0.0,
                    offsetMs: 0.0,
                    muted: false,
                    solo: false,
                  );
                  middleware.addLayerToEvent(event.id, audioPath: audioPath, name: newLayer.name);
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: FluxForgeTheme.accentGreen,
                side: BorderSide(color: FluxForgeTheme.accentGreen.withOpacity(0.3)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Layers list
        if (event.layers.isEmpty)
          Container(
            height: 100,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF16161C),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.layers_outlined, size: 32, color: Colors.white12),
                const SizedBox(height: 8),
                Text(
                  'No layers yet',
                  style: TextStyle(fontSize: 12, color: Colors.white24),
                ),
                const SizedBox(height: 4),
                Text(
                  'Click "Add Layer" to add audio',
                  style: TextStyle(fontSize: 10, color: Colors.white12, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          )
        else
          ...event.layers.asMap().entries.map((entry) {
            final index = entry.key;
            final layer = entry.value;
            return _buildLayerItem(event, layer, index, middleware);
          }),
      ],
    );
  }

  Widget _buildLayerItem(
    SlotCompositeEvent event,
    SlotEventLayer layer,
    int index,
    MiddlewareProvider middleware,
  ) {
    final hasAudio = layer.audioPath.isNotEmpty;
    final fileName = hasAudio ? layer.audioPath.split('/').last : 'No audio';
    final isExpanded = _expandedLayerIds.contains(layer.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedLayerIds.remove(layer.id);
                } else {
                  _expandedLayerIds.add(layer.id);
                }
              });
            },
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  // Expand icon
                  Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: Colors.white38,
                  ),
                  const SizedBox(width: 8),
                  // Layer index
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentBlue.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: FluxForgeTheme.accentBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Name + filename
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          layer.name,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          fileName,
                          style: TextStyle(
                            fontSize: 9,
                            color: hasAudio ? Colors.white38 : Colors.white24,
                            fontStyle: hasAudio ? FontStyle.normal : FontStyle.italic,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Mute
                  IconButton(
                    icon: Icon(
                      layer.muted ? Icons.volume_off : Icons.volume_up,
                      size: 16,
                      color: layer.muted ? Colors.red : Colors.white54,
                    ),
                    onPressed: () {
                      middleware.updateEventLayer(
                        event.id,
                        layer.copyWith(muted: !layer.muted),
                      );
                    },
                    tooltip: layer.muted ? 'Unmute' : 'Mute',
                  ),
                  // Delete
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 16, color: Colors.white38),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: const Color(0xFF1A1A22),
                          title: const Text('Delete Layer', style: TextStyle(color: Colors.white)),
                          content: Text(
                            'Delete "${layer.name}"?',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          actions: [
                            TextButton(
                              child: const Text('Cancel'),
                              onPressed: () => Navigator.pop(context, false),
                            ),
                            TextButton(
                              child: Text('Delete', style: TextStyle(color: FluxForgeTheme.accentRed)),
                              onPressed: () => Navigator.pop(context, true),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        middleware.removeLayerFromEvent(event.id, layer.id);
                      }
                    },
                    tooltip: 'Delete layer',
                  ),
                ],
              ),
            ),
          ),

          // Property controls (expandable)
          if (isExpanded)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.05)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Volume slider
                  _buildSlider(
                    label: 'Volume',
                    value: layer.volume,
                    min: 0.0,
                    max: 2.0,
                    divisions: 40,
                    valueDisplay: '${(layer.volume * 100).toInt()}%',
                    onChanged: (v) {
                      middleware.updateEventLayer(event.id, layer.copyWith(volume: v));
                    },
                  ),
                  const SizedBox(height: 10),

                  // Pan slider
                  _buildSlider(
                    label: 'Pan',
                    value: layer.pan,
                    min: -1.0,
                    max: 1.0,
                    divisions: 20,
                    valueDisplay: layer.pan == 0
                        ? 'C'
                        : layer.pan < 0
                            ? 'L${(-layer.pan * 100).toInt()}'
                            : 'R${(layer.pan * 100).toInt()}',
                    onChanged: (v) {
                      middleware.updateEventLayer(event.id, layer.copyWith(pan: v));
                    },
                  ),
                  const SizedBox(height: 10),

                  // Delay slider
                  _buildSlider(
                    label: 'Delay',
                    value: layer.offsetMs,
                    min: 0.0,
                    max: 2000.0,
                    divisions: 200,
                    valueDisplay: '${layer.offsetMs.toInt()}ms',
                    onChanged: (v) {
                      middleware.updateEventLayer(event.id, layer.copyWith(offsetMs: v));
                    },
                  ),

                  // Preview button
                  if (hasAudio) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text('Preview', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          AudioPlaybackService.instance.previewFile(
                            layer.audioPath,
                            volume: layer.volume,
                            source: PlaybackSource.browser,
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: FluxForgeTheme.accentGreen,
                          side: BorderSide(color: FluxForgeTheme.accentGreen.withOpacity(0.3)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTriggerStagesSection(SlotCompositeEvent event, MiddlewareProvider middleware) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSectionHeader('TRIGGER STAGES (${event.triggerStages.length})'),
            const Spacer(),
            OutlinedButton.icon(
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Edit Stages', style: TextStyle(fontSize: 11)),
              onPressed: () async {
                final newStages = await StageEditorDialog.show(
                  context,
                  event: event,
                );
                if (newStages != null) {
                  middleware.updateCompositeEvent(
                    event.copyWith(triggerStages: newStages),
                  );
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: FluxForgeTheme.accentOrange,
                side: BorderSide(color: FluxForgeTheme.accentOrange.withOpacity(0.3)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Stages list
        if (event.triggerStages.isEmpty)
          Container(
            height: 80,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF16161C),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.tag, size: 28, color: Colors.white12),
                const SizedBox(height: 8),
                Text(
                  'No trigger stages',
                  style: TextStyle(fontSize: 11, color: Colors.white24),
                ),
              ],
            ),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: event.triggerStages.map((stage) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentGreen.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: FluxForgeTheme.accentGreen.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tag, size: 12, color: FluxForgeTheme.accentGreen),
                    const SizedBox(width: 4),
                    Text(
                      stage,
                      style: TextStyle(
                        fontSize: 10,
                        color: FluxForgeTheme.accentGreen,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Colors.white54,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildPropertyField({required String label, required Widget child}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.white54),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueDisplay,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.white54),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: valueDisplay,
              onChanged: onChanged,
              activeColor: FluxForgeTheme.accentBlue,
              inactiveColor: Colors.white.withOpacity(0.1),
            ),
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            valueDisplay,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white70,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
