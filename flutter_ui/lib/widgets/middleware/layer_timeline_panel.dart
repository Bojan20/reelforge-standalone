/// Layer Timeline Panel — Comprehensive Audio Layer Visualization
///
/// P3.6: Layer timeline visualization.
///
/// Features:
/// - Timeline ruler with time markers
/// - Multi-track lane view for layers
/// - Waveform preview for each layer
/// - Playhead with position indicator
/// - Zoom and scroll controls
/// - Layer selection and editing
library;

import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// LAYER DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════════

/// Represents a single audio layer on the timeline
class TimelineLayer {
  final String id;
  final String name;
  final String? audioPath;
  final double startMs;
  final double durationMs;
  final double volume;
  final double pan;
  final bool muted;
  final bool soloed;
  final Color color;
  final List<double>? waveformData;

  const TimelineLayer({
    required this.id,
    required this.name,
    this.audioPath,
    required this.startMs,
    required this.durationMs,
    this.volume = 1.0,
    this.pan = 0.0,
    this.muted = false,
    this.soloed = false,
    this.color = const Color(0xFF4A9EFF),
    this.waveformData,
  });

  double get endMs => startMs + durationMs;

  TimelineLayer copyWith({
    String? id,
    String? name,
    String? audioPath,
    double? startMs,
    double? durationMs,
    double? volume,
    double? pan,
    bool? muted,
    bool? soloed,
    Color? color,
    List<double>? waveformData,
  }) {
    return TimelineLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      audioPath: audioPath ?? this.audioPath,
      startMs: startMs ?? this.startMs,
      durationMs: durationMs ?? this.durationMs,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      muted: muted ?? this.muted,
      soloed: soloed ?? this.soloed,
      color: color ?? this.color,
      waveformData: waveformData ?? this.waveformData,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LAYER TIMELINE PANEL
// ═══════════════════════════════════════════════════════════════════════════════

/// Comprehensive timeline visualization for audio layers
class LayerTimelinePanel extends StatefulWidget {
  final List<TimelineLayer> layers;
  final double totalDurationMs;
  final double playheadPositionMs;
  final bool isPlaying;
  final String? selectedLayerId;
  final void Function(String layerId)? onLayerSelected;
  final void Function(String layerId, double newStartMs)? onLayerMoved;
  final void Function(String layerId, double newDurationMs)? onLayerResized;
  final void Function(String layerId)? onLayerDeleted;
  final void Function(String layerId, bool muted)? onLayerMuteToggled;
  final void Function(String layerId, bool soloed)? onLayerSoloToggled;
  final void Function(double positionMs)? onPlayheadMoved;
  final VoidCallback? onPlay;
  final VoidCallback? onPause;
  final VoidCallback? onStop;

  const LayerTimelinePanel({
    super.key,
    required this.layers,
    required this.totalDurationMs,
    this.playheadPositionMs = 0,
    this.isPlaying = false,
    this.selectedLayerId,
    this.onLayerSelected,
    this.onLayerMoved,
    this.onLayerResized,
    this.onLayerDeleted,
    this.onLayerMuteToggled,
    this.onLayerSoloToggled,
    this.onPlayheadMoved,
    this.onPlay,
    this.onPause,
    this.onStop,
  });

  @override
  State<LayerTimelinePanel> createState() => _LayerTimelinePanelState();
}

class _LayerTimelinePanelState extends State<LayerTimelinePanel> {
  static const double kRulerHeight = 24.0;
  static const double kTrackHeight = 48.0;
  static const double kTrackHeaderWidth = 120.0;
  static const double kMinPixelsPerSecond = 20.0;
  static const double kMaxPixelsPerSecond = 500.0;

  double _pixelsPerSecond = 100.0;
  double _scrollOffsetX = 0.0;
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  // Drag state
  String? _draggingLayerId;
  double _dragStartX = 0;
  double _dragStartMs = 0;

  // Resize state
  String? _resizingLayerId;
  bool _resizingFromStart = false;
  double _resizeStartX = 0;
  double _resizeOriginalStartMs = 0;
  double _resizeOriginalDurationMs = 0;

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  void _handleZoom(double delta) {
    setState(() {
      _pixelsPerSecond = (_pixelsPerSecond * (1 + delta * 0.1))
          .clamp(kMinPixelsPerSecond, kMaxPixelsPerSecond);
    });
  }

  void _handlePlayheadSeek(double localX) {
    final positionMs = (_scrollOffsetX + localX) / _pixelsPerSecond * 1000;
    widget.onPlayheadMoved?.call(positionMs.clamp(0, widget.totalDurationMs));
  }

  double _msToPixels(double ms) => ms / 1000 * _pixelsPerSecond;
  double _pixelsToMs(double pixels) => pixels / _pixelsPerSecond * 1000;

  @override
  Widget build(BuildContext context) {
    final totalWidthMs = math.max(widget.totalDurationMs, 5000.0); // Min 5 seconds
    final contentWidth = _msToPixels(totalWidthMs);

    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          // Transport controls
          _buildTransportBar(),
          // Timeline content
          Expanded(
            child: Row(
              children: [
                // Track headers (fixed)
                SizedBox(
                  width: kTrackHeaderWidth,
                  child: Column(
                    children: [
                      // Ruler corner
                      Container(
                        height: kRulerHeight,
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.bgMid,
                          border: Border(
                            bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
                            right: BorderSide(color: FluxForgeTheme.borderSubtle),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'LAYERS',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: FluxForgeTheme.textSecondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      // Track headers
                      Expanded(
                        child: ListView.builder(
                          controller: _verticalScrollController,
                          itemCount: widget.layers.length,
                          itemBuilder: (context, index) => _buildTrackHeader(widget.layers[index]),
                        ),
                      ),
                    ],
                  ),
                ),
                // Timeline area (scrollable)
                Expanded(
                  child: GestureDetector(
                    onScaleUpdate: (details) {
                      if (details.scale != 1.0) {
                        _handleZoom(details.scale - 1.0);
                      }
                    },
                    child: Listener(
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) {
                          if (HardwareKeyboard.instance.isControlPressed) {
                            _handleZoom(-event.scrollDelta.dy / 100);
                          } else {
                            _horizontalScrollController.jumpTo(
                              (_horizontalScrollController.offset + event.scrollDelta.dx)
                                  .clamp(0, contentWidth),
                            );
                          }
                        }
                      },
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollUpdateNotification) {
                            setState(() => _scrollOffsetX = notification.metrics.pixels);
                          }
                          return false;
                        },
                        child: SingleChildScrollView(
                          controller: _horizontalScrollController,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: contentWidth,
                            child: Column(
                              children: [
                                // Ruler
                                _buildRuler(contentWidth),
                                // Tracks
                                Expanded(
                                  child: Stack(
                                    children: [
                                      // Grid lines
                                      _buildGridLines(contentWidth),
                                      // Layer tracks
                                      _buildLayerTracks(contentWidth),
                                      // Playhead
                                      _buildPlayhead(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
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

  Widget _buildTransportBar() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Transport buttons
          _buildTransportButton(
            icon: Icons.stop,
            tooltip: 'Stop',
            onTap: widget.onStop,
          ),
          const SizedBox(width: 4),
          _buildTransportButton(
            icon: widget.isPlaying ? Icons.pause : Icons.play_arrow,
            tooltip: widget.isPlaying ? 'Pause' : 'Play',
            onTap: widget.isPlaying ? widget.onPause : widget.onPlay,
            highlighted: widget.isPlaying,
          ),
          const SizedBox(width: 16),
          // Time display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FluxForgeTheme.borderSubtle),
            ),
            child: Text(
              _formatTime(widget.playheadPositionMs),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: FluxForgeTheme.accentGreen,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '/ ${_formatTime(widget.totalDurationMs)}',
            style: TextStyle(
              fontSize: 10,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          const Spacer(),
          // Zoom controls
          IconButton(
            icon: Icon(Icons.zoom_out, size: 18, color: FluxForgeTheme.textSecondary),
            onPressed: () => _handleZoom(-0.2),
            tooltip: 'Zoom Out',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          Container(
            width: 60,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Slider(
              value: _pixelsPerSecond,
              min: kMinPixelsPerSecond,
              max: kMaxPixelsPerSecond,
              onChanged: (v) => setState(() => _pixelsPerSecond = v),
            ),
          ),
          IconButton(
            icon: Icon(Icons.zoom_in, size: 18, color: FluxForgeTheme.textSecondary),
            onPressed: () => _handleZoom(0.2),
            tooltip: 'Zoom In',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          const SizedBox(width: 8),
          Text(
            '${_pixelsPerSecond.toInt()} px/s',
            style: TextStyle(
              fontSize: 9,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransportButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onTap,
    bool highlighted = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: highlighted
                ? FluxForgeTheme.accentGreen.withValues(alpha: 0.2)
                : FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: highlighted
                  ? FluxForgeTheme.accentGreen
                  : FluxForgeTheme.borderSubtle,
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: highlighted
                ? FluxForgeTheme.accentGreen
                : FluxForgeTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTrackHeader(TimelineLayer layer) {
    final isSelected = layer.id == widget.selectedLayerId;
    final hasSolo = widget.layers.any((l) => l.soloed);
    final effectiveMuted = layer.muted || (hasSolo && !layer.soloed);

    return GestureDetector(
      onTap: () => widget.onLayerSelected?.call(layer.id),
      child: Container(
        height: kTrackHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? layer.color.withValues(alpha: 0.1)
              : FluxForgeTheme.bgMid,
          border: Border(
            bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
            right: BorderSide(color: FluxForgeTheme.borderSubtle),
            left: isSelected
                ? BorderSide(color: layer.color, width: 2)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            // Layer name
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    layer.name,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: effectiveMuted
                          ? FluxForgeTheme.textSecondary
                          : FluxForgeTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${layer.durationMs.toStringAsFixed(0)}ms',
                    style: TextStyle(
                      fontSize: 8,
                      color: FluxForgeTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // Mute button
            _buildMiniButton(
              label: 'M',
              active: layer.muted,
              activeColor: FluxForgeTheme.accentOrange,
              onTap: () => widget.onLayerMuteToggled?.call(layer.id, !layer.muted),
            ),
            const SizedBox(width: 2),
            // Solo button
            _buildMiniButton(
              label: 'S',
              active: layer.soloed,
              activeColor: FluxForgeTheme.accentYellow,
              onTap: () => widget.onLayerSoloToggled?.call(layer.id, !layer.soloed),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniButton({
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.3) : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: active ? activeColor : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: active ? activeColor : FluxForgeTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRuler(double contentWidth) {
    return GestureDetector(
      onTapDown: (details) => _handlePlayheadSeek(details.localPosition.dx),
      onPanUpdate: (details) => _handlePlayheadSeek(details.localPosition.dx),
      child: Container(
        height: kRulerHeight,
        width: contentWidth,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          border: Border(
            bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
          ),
        ),
        child: CustomPaint(
          painter: _RulerPainter(
            pixelsPerSecond: _pixelsPerSecond,
            totalMs: widget.totalDurationMs,
          ),
        ),
      ),
    );
  }

  Widget _buildGridLines(double contentWidth) {
    return CustomPaint(
      size: Size(contentWidth, double.infinity),
      painter: _GridPainter(
        pixelsPerSecond: _pixelsPerSecond,
        trackCount: widget.layers.length,
        trackHeight: kTrackHeight,
      ),
    );
  }

  Widget _buildLayerTracks(double contentWidth) {
    return Column(
      children: widget.layers.map((layer) {
        return SizedBox(
          height: kTrackHeight,
          width: contentWidth,
          child: Stack(
            children: [
              // Layer block
              _buildLayerBlock(layer),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLayerBlock(TimelineLayer layer) {
    final left = _msToPixels(layer.startMs);
    final width = _msToPixels(layer.durationMs);
    final isSelected = layer.id == widget.selectedLayerId;
    final isDragging = layer.id == _draggingLayerId;
    final isResizing = layer.id == _resizingLayerId;
    final hasSolo = widget.layers.any((l) => l.soloed);
    final effectiveMuted = layer.muted || (hasSolo && !layer.soloed);

    return Positioned(
      left: left,
      top: 4,
      child: GestureDetector(
        onTap: () => widget.onLayerSelected?.call(layer.id),
        onPanStart: (details) {
          setState(() {
            _draggingLayerId = layer.id;
            _dragStartX = details.localPosition.dx;
            _dragStartMs = layer.startMs;
          });
        },
        onPanUpdate: (details) {
          if (_draggingLayerId == layer.id) {
            final deltaX = details.localPosition.dx - _dragStartX;
            final newStartMs = (_dragStartMs + _pixelsToMs(deltaX)).clamp(0.0, widget.totalDurationMs - layer.durationMs);
            widget.onLayerMoved?.call(layer.id, newStartMs);
          }
        },
        onPanEnd: (details) {
          setState(() => _draggingLayerId = null);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 50),
          width: width,
          height: kTrackHeight - 8,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: effectiveMuted
                  ? [Colors.grey.shade700, Colors.grey.shade800]
                  : [
                      layer.color.withValues(alpha: 0.8),
                      layer.color.withValues(alpha: 0.6),
                    ],
            ),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected
                  ? Colors.white
                  : isDragging || isResizing
                      ? FluxForgeTheme.accentCyan
                      : layer.color.withValues(alpha: 0.5),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isDragging
                ? [
                    BoxShadow(
                      color: layer.color.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              // Waveform
              if (layer.waveformData != null && layer.waveformData!.isNotEmpty)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: CustomPaint(
                      painter: _WaveformPainter(
                        data: layer.waveformData!,
                        color: effectiveMuted
                            ? Colors.grey.shade500
                            : Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              // Layer name
              Positioned(
                left: 4,
                top: 2,
                right: 4,
                child: Text(
                  layer.name,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: effectiveMuted
                        ? Colors.grey.shade400
                        : Colors.white,
                    shadows: const [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 2,
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Resize handles
              if (isSelected) ...[
                // Left handle
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onPanStart: (details) {
                      setState(() {
                        _resizingLayerId = layer.id;
                        _resizingFromStart = true;
                        _resizeStartX = details.localPosition.dx;
                        _resizeOriginalStartMs = layer.startMs;
                        _resizeOriginalDurationMs = layer.durationMs;
                      });
                    },
                    onPanUpdate: (details) {
                      if (_resizingLayerId == layer.id && _resizingFromStart) {
                        final deltaX = details.localPosition.dx - _resizeStartX;
                        final deltaMs = _pixelsToMs(deltaX);
                        final newStartMs = (_resizeOriginalStartMs + deltaMs).clamp(0.0, _resizeOriginalStartMs + _resizeOriginalDurationMs - 50.0);
                        final newDurationMs = _resizeOriginalDurationMs - (newStartMs - _resizeOriginalStartMs);
                        widget.onLayerMoved?.call(layer.id, newStartMs);
                        widget.onLayerResized?.call(layer.id, newDurationMs);
                      }
                    },
                    onPanEnd: (_) => setState(() => _resizingLayerId = null),
                    child: Container(
                      width: 8,
                      color: Colors.transparent,
                      child: Center(
                        child: Container(
                          width: 3,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Right handle
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onPanStart: (details) {
                      setState(() {
                        _resizingLayerId = layer.id;
                        _resizingFromStart = false;
                        _resizeStartX = details.localPosition.dx;
                        _resizeOriginalDurationMs = layer.durationMs;
                      });
                    },
                    onPanUpdate: (details) {
                      if (_resizingLayerId == layer.id && !_resizingFromStart) {
                        final deltaX = details.localPosition.dx - _resizeStartX;
                        final deltaMs = _pixelsToMs(deltaX);
                        final newDurationMs = (_resizeOriginalDurationMs + deltaMs).clamp(50.0, widget.totalDurationMs - layer.startMs);
                        widget.onLayerResized?.call(layer.id, newDurationMs);
                      }
                    },
                    onPanEnd: (_) => setState(() => _resizingLayerId = null),
                    child: Container(
                      width: 8,
                      color: Colors.transparent,
                      child: Center(
                        child: Container(
                          width: 3,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayhead() {
    final position = _msToPixels(widget.playheadPositionMs);

    return Positioned(
      left: position - 1,
      top: 0,
      bottom: 0,
      child: Container(
        width: 2,
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentRed,
          boxShadow: [
            BoxShadow(
              color: FluxForgeTheme.accentRed.withValues(alpha: 0.5),
              blurRadius: 4,
            ),
          ],
        ),
        child: Column(
          children: [
            // Playhead head
            Container(
              width: 8,
              height: 8,
              transform: Matrix4.translationValues(-3, 0, 0),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentRed,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(double ms) {
    final totalSeconds = ms / 1000;
    final minutes = (totalSeconds / 60).floor();
    final seconds = (totalSeconds % 60).floor();
    final milliseconds = ((ms % 1000) / 10).floor();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${milliseconds.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class _RulerPainter extends CustomPainter {
  final double pixelsPerSecond;
  final double totalMs;

  _RulerPainter({required this.pixelsPerSecond, required this.totalMs});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FluxForgeTheme.textSecondary
      ..strokeWidth = 1;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Determine tick interval based on zoom
    double majorTickMs;
    double minorTickMs;
    if (pixelsPerSecond >= 200) {
      majorTickMs = 100; // 100ms major ticks
      minorTickMs = 20;
    } else if (pixelsPerSecond >= 100) {
      majorTickMs = 500; // 500ms major ticks
      minorTickMs = 100;
    } else if (pixelsPerSecond >= 50) {
      majorTickMs = 1000; // 1s major ticks
      minorTickMs = 200;
    } else {
      majorTickMs = 5000; // 5s major ticks
      minorTickMs = 1000;
    }

    // Draw ticks
    for (double ms = 0; ms <= totalMs; ms += minorTickMs) {
      final x = ms / 1000 * pixelsPerSecond;
      final isMajor = (ms % majorTickMs).abs() < 0.001;

      canvas.drawLine(
        Offset(x, size.height - (isMajor ? 12 : 6)),
        Offset(x, size.height),
        paint..color = isMajor ? FluxForgeTheme.textSecondary : FluxForgeTheme.borderSubtle,
      );

      // Draw time label for major ticks
      if (isMajor) {
        final seconds = ms / 1000;
        String label;
        if (majorTickMs >= 1000) {
          label = '${seconds.toInt()}s';
        } else {
          label = '${ms.toInt()}ms';
        }

        textPainter.text = TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 8,
            color: FluxForgeTheme.textSecondary,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter oldDelegate) =>
      pixelsPerSecond != oldDelegate.pixelsPerSecond ||
      totalMs != oldDelegate.totalMs;
}

class _GridPainter extends CustomPainter {
  final double pixelsPerSecond;
  final int trackCount;
  final double trackHeight;

  _GridPainter({
    required this.pixelsPerSecond,
    required this.trackCount,
    required this.trackHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Vertical grid lines (time)
    double gridIntervalMs;
    if (pixelsPerSecond >= 200) {
      gridIntervalMs = 100;
    } else if (pixelsPerSecond >= 100) {
      gridIntervalMs = 500;
    } else if (pixelsPerSecond >= 50) {
      gridIntervalMs = 1000;
    } else {
      gridIntervalMs = 5000;
    }

    for (double ms = 0; ms < size.width / pixelsPerSecond * 1000; ms += gridIntervalMs) {
      final x = ms / 1000 * pixelsPerSecond;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Horizontal grid lines (tracks)
    for (int i = 0; i <= trackCount; i++) {
      final y = i * trackHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      pixelsPerSecond != oldDelegate.pixelsPerSecond ||
      trackCount != oldDelegate.trackCount;
}

class _WaveformPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _WaveformPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.fill;

    final path = Path();
    final centerY = size.height / 2;
    final step = size.width / data.length;

    path.moveTo(0, centerY);

    // Top half
    for (int i = 0; i < data.length; i++) {
      final x = i * step;
      final amplitude = data[i].clamp(0.0, 1.0);
      final y = centerY - (amplitude * centerY * 0.9);
      path.lineTo(x, y);
    }

    // Bottom half (mirror)
    for (int i = data.length - 1; i >= 0; i--) {
      final x = i * step;
      final amplitude = data[i].clamp(0.0, 1.0);
      final y = centerY + (amplitude * centerY * 0.9);
      path.lineTo(x, y);
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      data != oldDelegate.data || color != oldDelegate.color;
}
