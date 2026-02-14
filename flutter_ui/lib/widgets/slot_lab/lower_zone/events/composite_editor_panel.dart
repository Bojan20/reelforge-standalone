/// Composite Editor Panel
///
/// DAW-style timeline editor for composite event layers.
/// Features unified horizontal scroll for ruler + ALL waveform tracks.
///
/// Features:
/// - Event selection dropdown (self-contained)
/// - DAW-style waveform tracks with horizontal drag-to-move
/// - Time ruler synced with all waveform tracks (single scroll controller)
/// - Add/delete layers
/// - Mute/Solo/Preview per layer
/// - Zoom in/out
///
/// Task: SL-LZ-P0.3
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../models/slot_audio_events.dart';
import '../../../../models/timeline_models.dart' show parseWaveformFromJson;
import '../../../../providers/middleware_provider.dart';
import '../../../../services/audio_playback_service.dart';
import '../../../../src/rust/native_ffi.dart';
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
  // Waveform cache: layerId → waveform peaks (absolute 0-1 values)
  final Map<String, List<double>> _waveformCache = {};
  // Duration cache: layerId → seconds
  final Map<String, double> _durationCache = {};
  // Pixels per second for timeline scale
  double _pixelsPerSecond = 100.0;
  // Single scroll controller for ruler + ALL tracks (unified horizontal scroll)
  final ScrollController _timelineScrollController = ScrollController();
  // Drag state
  String? _draggingLayerId;
  // Self-contained event selection (used when widget.selectedEventId is null)
  String? _internalSelectedEventId;

  // Layout constants
  static const double _kLabelWidth = 70.0;
  static const double _kRulerHeight = 20.0;
  static const double _kTrackHeight = 56.0;

  String? get _effectiveEventId => widget.selectedEventId ?? _internalSelectedEventId;

  @override
  void dispose() {
    _timelineScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        final events = middleware.compositeEvents;

        if (events.isEmpty) {
          return _buildEmptyState(
            'No events',
            'Create events by assigning audio in the Audio Panel',
          );
        }

        // Auto-select first event if nothing selected
        final effectiveId = _effectiveEventId;
        final event = effectiveId != null
            ? events.where((e) => e.id == effectiveId).firstOrNull
            : null;

        // Load waveforms for layers
        if (event != null) {
          _ensureWaveforms(event);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Event selector bar
            _buildEventSelectorBar(events, event, middleware),
            // Content
            if (event == null)
              Expanded(
                child: _buildEmptyState(
                  'Select an event',
                  'Choose an event from the dropdown above',
                ),
              )
            else
              Expanded(
                child: _buildEventContent(event, middleware),
              ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT SELECTOR BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEventSelectorBar(
    List<SlotCompositeEvent> events,
    SlotCompositeEvent? selected,
    MiddlewareProvider middleware,
  ) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF14141A),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          Icon(Icons.audiotrack, size: 14, color: FluxForgeTheme.accentBlue),
          const SizedBox(width: 6),
          const Text('Event:', style: TextStyle(fontSize: 10, color: Colors.white54)),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selected?.id,
                isDense: true,
                isExpanded: true,
                dropdownColor: const Color(0xFF1A1A22),
                style: const TextStyle(fontSize: 11, color: Colors.white),
                hint: const Text('Select event...', style: TextStyle(fontSize: 11, color: Colors.white38)),
                items: events.map((e) {
                  final stageLabel = e.triggerStages.isNotEmpty ? e.triggerStages.first : '';
                  return DropdownMenuItem<String>(
                    value: e.id,
                    child: Text(
                      '${e.name}${stageLabel.isNotEmpty ? '  [$stageLabel]' : ''}  (${e.layers.length}L)',
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (id) {
                  setState(() {
                    _internalSelectedEventId = id;
                  });
                },
              ),
            ),
          ),
          if (selected != null) ...[
            const SizedBox(width: 4),
            Text(
              '${selected.layers.length} layers',
              style: const TextStyle(fontSize: 9, color: Colors.white38, fontFamily: 'monospace'),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEventContent(SlotCompositeEvent event, MiddlewareProvider middleware) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Action bar
        _buildActionBar(event, middleware),
        // Timeline area (takes remaining space)
        Expanded(
          child: _buildTimelineArea(event, middleware),
        ),
      ],
    );
  }

  Widget _buildActionBar(SlotCompositeEvent event, MiddlewareProvider middleware) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          // Add Layer
          _buildActionBtn(
            icon: Icons.add,
            label: 'Add Layer',
            color: FluxForgeTheme.accentGreen,
            onTap: () async {
              final audioPath = await AudioWaveformPickerDialog.show(
                context,
                title: 'Select Audio for Layer',
              );
              if (audioPath != null) {
                middleware.addLayerToEvent(event.id, audioPath: audioPath, name: 'Layer ${event.layers.length + 1}');
              }
            },
          ),
          const SizedBox(width: 8),
          // Edit Stages
          _buildActionBtn(
            icon: Icons.tag,
            label: 'Stages (${event.triggerStages.length})',
            color: FluxForgeTheme.accentOrange,
            onTap: () async {
              final newStages = await StageEditorDialog.show(context, event: event);
              if (newStages != null) {
                middleware.updateCompositeEvent(event.copyWith(triggerStages: newStages));
              }
            },
          ),
          const Spacer(),
          // Zoom controls
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => setState(() {
                _pixelsPerSecond = (_pixelsPerSecond * 0.8).clamp(30.0, 500.0);
              }),
              child: const Icon(Icons.zoom_out, size: 14, color: Colors.white38),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${_pixelsPerSecond.toInt()}px/s',
            style: const TextStyle(fontSize: 8, color: Colors.white24, fontFamily: 'monospace'),
          ),
          const SizedBox(width: 4),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => setState(() {
                _pixelsPerSecond = (_pixelsPerSecond * 1.25).clamp(30.0, 500.0);
              }),
              child: const Icon(Icons.zoom_in, size: 14, color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 9, color: color)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMELINE AREA — UNIFIED horizontal scroll for ruler + ALL tracks
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTimelineArea(SlotCompositeEvent event, MiddlewareProvider middleware) {
    if (event.layers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.layers_outlined, size: 32, color: Colors.white12),
            const SizedBox(height: 8),
            const Text('No layers', style: TextStyle(fontSize: 11, color: Colors.white24)),
            const SizedBox(height: 4),
            const Text('Click "Add Layer" to add audio', style: TextStyle(fontSize: 9, color: Colors.white12)),
          ],
        ),
      );
    }

    // Calculate total timeline duration
    double maxEndSeconds = 2.0;
    for (final layer in event.layers) {
      final offsetSec = layer.offsetMs / 1000.0;
      final dur = _durationCache[layer.id] ?? (layer.durationSeconds ?? 1.0);
      final endSec = offsetSec + dur;
      if (endSec > maxEndSeconds) maxEndSeconds = endSec;
    }
    maxEndSeconds += 0.5;

    final totalWidth = maxEndSeconds * _pixelsPerSecond;

    // Layout: fixed label column on left + unified scrollable area on right.
    // The scrollable area contains ruler (top) + waveform tracks (below).
    // ONE scroll controller = perfect sync between ruler and all tracks.
    return Container(
      color: const Color(0xFF0D0D12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Fixed label column (left) ──
          SizedBox(
            width: _kLabelWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Empty area above labels (aligned with ruler)
                Container(
                  height: _kRulerHeight,
                  color: const Color(0xFF14141A),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 4),
                  child: const Text('', style: TextStyle(fontSize: 7, color: Colors.white24)),
                ),
                // Track labels (vertically scrollable if many tracks)
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: event.layers.length,
                    itemBuilder: (context, index) {
                      return _buildTrackLabel(event, event.layers[index], index, middleware);
                    },
                  ),
                ),
              ],
            ),
          ),
          // Divider between labels and waveforms
          Container(width: 1, color: Colors.white.withValues(alpha: 0.08)),
          // ── Unified scrollable area (right) ──
          Expanded(
            child: SingleChildScrollView(
              controller: _timelineScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Time ruler
                    SizedBox(
                      height: _kRulerHeight,
                      width: totalWidth,
                      child: CustomPaint(
                        painter: _TimeRulerPainter(
                          pixelsPerSecond: _pixelsPerSecond,
                          maxSeconds: maxEndSeconds,
                        ),
                      ),
                    ),
                    // Waveform tracks (vertically scrollable if many)
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: event.layers.length,
                        itemBuilder: (context, index) {
                          return _buildWaveformTrackContent(
                            event, event.layers[index], index, middleware,
                            maxEndSeconds, totalWidth,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACK LABEL (fixed left column)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTrackLabel(
    SlotCompositeEvent event,
    SlotEventLayer layer,
    int index,
    MiddlewareProvider middleware,
  ) {
    final hasAudio = layer.audioPath.isNotEmpty;
    final trackColors = [
      FluxForgeTheme.accentBlue,
      FluxForgeTheme.accentGreen,
      FluxForgeTheme.accentOrange,
      FluxForgeTheme.accentCyan,
      const Color(0xFF9370DB),
      FluxForgeTheme.accentRed,
    ];
    final trackColor = layer.muted ? Colors.grey : trackColors[index % trackColors.length];

    return Container(
      height: _kTrackHeight,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF14141A),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: trackColor.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: trackColor),
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  layer.name,
                  style: const TextStyle(fontSize: 8, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mute
              _buildTrackBtn(
                'M',
                layer.muted ? FluxForgeTheme.accentRed : Colors.white24,
                () => middleware.updateEventLayer(event.id, layer.copyWith(muted: !layer.muted)),
              ),
              const SizedBox(width: 4),
              // Solo
              _buildTrackBtn(
                'S',
                layer.solo ? FluxForgeTheme.accentOrange : Colors.white24,
                () => middleware.updateEventLayer(event.id, layer.copyWith(solo: !layer.solo)),
              ),
              const SizedBox(width: 4),
              // Preview
              if (hasAudio)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      AudioPlaybackService.instance.stopSource(PlaybackSource.browser);
                      AudioPlaybackService.instance.previewFile(
                        layer.audioPath,
                        volume: layer.volume,
                        source: PlaybackSource.browser,
                      );
                    },
                    child: Icon(Icons.play_arrow, size: 12, color: FluxForgeTheme.accentGreen),
                  ),
                ),
              const Spacer(),
              // Delete
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    _waveformCache.remove(layer.id);
                    _durationCache.remove(layer.id);
                    middleware.removeLayerFromEvent(event.id, layer.id);
                  },
                  child: const Icon(Icons.close, size: 10, color: Colors.white24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WAVEFORM TRACK CONTENT (scrollable right area — NO individual scroll!)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildWaveformTrackContent(
    SlotCompositeEvent event,
    SlotEventLayer layer,
    int index,
    MiddlewareProvider middleware,
    double maxSeconds,
    double totalWidth,
  ) {
    final waveform = _waveformCache[layer.id];
    final duration = _durationCache[layer.id] ?? (layer.durationSeconds ?? 1.0);
    final offsetSec = layer.offsetMs / 1000.0;
    final waveformWidth = duration * _pixelsPerSecond;
    final offsetPixels = offsetSec * _pixelsPerSecond;
    final isDragging = _draggingLayerId == layer.id;
    final hasAudio = layer.audioPath.isNotEmpty;
    final fileName = hasAudio ? layer.audioPath.split('/').last : 'No audio';

    final trackColors = [
      FluxForgeTheme.accentBlue,
      FluxForgeTheme.accentGreen,
      FluxForgeTheme.accentOrange,
      FluxForgeTheme.accentCyan,
      const Color(0xFF9370DB),
      FluxForgeTheme.accentRed,
    ];
    final trackColor = layer.muted ? Colors.grey : trackColors[index % trackColors.length];

    return Container(
      height: _kTrackHeight,
      width: totalWidth,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Stack(
        children: [
          // Grid lines (every second)
          CustomPaint(
            size: Size(totalWidth, _kTrackHeight),
            painter: _GridLinePainter(pixelsPerSecond: _pixelsPerSecond, maxSeconds: maxSeconds),
          ),
          // Waveform block at offset position
          Positioned(
            left: offsetPixels,
            top: 3,
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                final deltaMs = (details.delta.dx / _pixelsPerSecond) * 1000.0;
                final newOffset = (layer.offsetMs + deltaMs).clamp(0.0, maxSeconds * 1000.0);
                middleware.updateEventLayer(event.id, layer.copyWith(offsetMs: newOffset));
              },
              onHorizontalDragStart: (_) {
                setState(() => _draggingLayerId = layer.id);
              },
              onHorizontalDragEnd: (_) {
                setState(() => _draggingLayerId = null);
              },
              child: MouseRegion(
                cursor: isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
                child: Container(
                  width: waveformWidth.clamp(10.0, totalWidth),
                  height: 50,
                  decoration: BoxDecoration(
                    color: trackColor.withValues(alpha: isDragging ? 0.25 : 0.15),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isDragging
                          ? trackColor.withValues(alpha: 0.8)
                          : trackColor.withValues(alpha: 0.4),
                      width: isDragging ? 1.5 : 1.0,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Stack(
                      children: [
                        // Waveform
                        if (waveform != null && waveform.isNotEmpty)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _WaveformPainter(
                                data: waveform,
                                color: trackColor,
                                isMuted: layer.muted,
                              ),
                            ),
                          )
                        else
                          Center(
                            child: Text(
                              hasAudio ? 'Loading...' : 'No audio',
                              style: const TextStyle(fontSize: 8, color: Colors.white24),
                            ),
                          ),
                        // File name label
                        Positioned(
                          left: 4,
                          top: 2,
                          child: Text(
                            fileName,
                            style: TextStyle(
                              fontSize: 8,
                              color: trackColor.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        // Offset + duration label
                        Positioned(
                          right: 4,
                          bottom: 2,
                          child: Text(
                            '${layer.offsetMs.toInt()}ms  ${duration.toStringAsFixed(1)}s',
                            style: const TextStyle(
                              fontSize: 7,
                              color: Colors.white38,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackBtn(String label, Color color, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          label,
          style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WAVEFORM LOADING
  // ═══════════════════════════════════════════════════════════════════════════

  void _ensureWaveforms(SlotCompositeEvent event) {
    for (final layer in event.layers) {
      if (layer.audioPath.isEmpty) continue;
      if (_waveformCache.containsKey(layer.id)) continue;

      // Use layer's own waveformData if available
      if (layer.waveformData != null && layer.waveformData!.isNotEmpty) {
        _waveformCache[layer.id] = layer.waveformData!;
        _ensureDuration(layer);
        continue;
      }

      // Generate via FFI
      try {
        final cacheKey = 'ce-${layer.id}';
        final json = NativeFFI.instance.generateWaveformFromFile(layer.audioPath, cacheKey);
        if (json != null) {
          final (left, right) = parseWaveformFromJson(json, maxSamples: 2048);
          if (left != null) {
            final waveform = <double>[];
            if (right != null && right.length == left.length) {
              for (int i = 0; i < left.length; i++) {
                waveform.add((left[i] + right[i]) / 2.0);
              }
            } else {
              waveform.addAll(left);
            }
            _waveformCache[layer.id] = waveform;
          }
        }
      } catch (_) {
        // FFI may not be available
      }

      _ensureDuration(layer);
    }
  }

  void _ensureDuration(SlotEventLayer layer) {
    if (_durationCache.containsKey(layer.id)) return;
    final dur = layer.durationSeconds;
    if (dur != null && dur > 0) {
      _durationCache[layer.id] = dur;
    } else {
      try {
        final d = NativeFFI.instance.getAudioFileDuration(layer.audioPath);
        if (d > 0) {
          _durationCache[layer.id] = d;
        }
      } catch (_) {
        // FFI may not be available
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EMPTY STATE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState(String title, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.edit_note, size: 48, color: Colors.white12),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 14, color: Colors.white38, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(message, style: const TextStyle(fontSize: 11, color: Colors.white24), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Waveform painter — renders absolute peak values (0-1) as mirrored waveform
class _WaveformPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final bool isMuted;

  const _WaveformPainter({
    required this.data,
    required this.color,
    this.isMuted = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final waveColor = isMuted ? Colors.grey.withValues(alpha: 0.4) : color.withValues(alpha: 0.7);
    final fillColor = isMuted ? Colors.grey.withValues(alpha: 0.15) : color.withValues(alpha: 0.2);

    final centerY = size.height / 2;
    final scaleY = size.height / 2 * 0.85;
    final samplesPerPixel = data.length / size.width;

    // Fill path (mirrored)
    final fillPath = Path();
    fillPath.moveTo(0, centerY);

    // Top half
    for (int x = 0; x < size.width.toInt(); x++) {
      final startSample = (x * samplesPerPixel).floor();
      final endSample = ((x + 1) * samplesPerPixel).floor().clamp(0, data.length);
      if (startSample >= data.length) break;

      double peak = 0.0;
      for (int i = startSample; i < endSample && i < data.length; i++) {
        final s = data[i].abs().clamp(0.0, 1.0);
        if (s > peak) peak = s;
      }

      fillPath.lineTo(x.toDouble(), centerY - peak * scaleY);
    }

    // Bottom half (mirror)
    for (int x = size.width.toInt() - 1; x >= 0; x--) {
      final startSample = (x * samplesPerPixel).floor();
      final endSample = ((x + 1) * samplesPerPixel).floor().clamp(0, data.length);
      if (startSample >= data.length) continue;

      double peak = 0.0;
      for (int i = startSample; i < endSample && i < data.length; i++) {
        final s = data[i].abs().clamp(0.0, 1.0);
        if (s > peak) peak = s;
      }

      fillPath.lineTo(x.toDouble(), centerY + peak * scaleY);
    }

    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = fillColor..style = PaintingStyle.fill);

    // Outline stroke
    final strokePaint = Paint()
      ..color = waveColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final strokePath = Path();
    for (int x = 0; x < size.width.toInt(); x++) {
      final startSample = (x * samplesPerPixel).floor();
      final endSample = ((x + 1) * samplesPerPixel).floor().clamp(0, data.length);
      if (startSample >= data.length) break;

      double peak = 0.0;
      for (int i = startSample; i < endSample && i < data.length; i++) {
        final s = data[i].abs().clamp(0.0, 1.0);
        if (s > peak) peak = s;
      }

      final y1 = centerY - peak * scaleY;
      final y2 = centerY + peak * scaleY;

      if (x == 0) strokePath.moveTo(x.toDouble(), y1);
      strokePath.lineTo(x.toDouble(), y1);
      strokePath.lineTo(x.toDouble(), y2);
    }

    canvas.drawPath(strokePath, strokePaint);

    // Center line
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()..color = waveColor.withValues(alpha: 0.15)..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.color != color ||
        oldDelegate.isMuted != isMuted;
  }
}

/// Time ruler painter
class _TimeRulerPainter extends CustomPainter {
  final double pixelsPerSecond;
  final double maxSeconds;

  const _TimeRulerPainter({
    required this.pixelsPerSecond,
    required this.maxSeconds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = 1.0;

    final textStyle = TextStyle(
      fontSize: 8,
      color: Colors.white38,
      fontFamily: 'monospace',
    );

    double tickInterval;
    if (pixelsPerSecond >= 200) {
      tickInterval = 0.1;
    } else if (pixelsPerSecond >= 80) {
      tickInterval = 0.25;
    } else {
      tickInterval = 0.5;
    }

    for (double t = 0; t <= maxSeconds; t += tickInterval) {
      final x = t * pixelsPerSecond;
      if (x > size.width) break;

      final isMajor = (t * 1000).round() % 1000 == 0;
      final tickHeight = isMajor ? 12.0 : 6.0;

      paint.color = Colors.white.withValues(alpha: isMajor ? 0.2 : 0.08);
      canvas.drawLine(
        Offset(x, size.height - tickHeight),
        Offset(x, size.height),
        paint,
      );

      if (isMajor) {
        final tp = TextPainter(
          text: TextSpan(text: '${t.toStringAsFixed(0)}s', style: textStyle),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, Offset(x + 2, 2));
      }
    }

    // Bottom border
    paint.color = Colors.white.withValues(alpha: 0.08);
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), paint);
  }

  @override
  bool shouldRepaint(_TimeRulerPainter oldDelegate) {
    return oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.maxSeconds != maxSeconds;
  }
}

/// Grid line painter for track backgrounds
class _GridLinePainter extends CustomPainter {
  final double pixelsPerSecond;
  final double maxSeconds;

  const _GridLinePainter({required this.pixelsPerSecond, required this.maxSeconds});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 0.5;

    for (double t = 0; t <= maxSeconds; t += 1.0) {
      final x = t * pixelsPerSecond;
      if (x > size.width) break;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridLinePainter oldDelegate) {
    return oldDelegate.pixelsPerSecond != pixelsPerSecond;
  }
}
