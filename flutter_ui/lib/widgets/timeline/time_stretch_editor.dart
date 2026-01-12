/// Time Stretch Editor Widget
///
/// Professional Ableton/Logic Pro style time stretch editing:
/// - Warp markers on timeline (double-click to create)
/// - Interactive stretch handles
/// - Real-time preview during drag
/// - Visual stretch regions
/// - BPM detection integration
/// - Quantize to grid

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TIME STRETCH EDITOR STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// State for time stretch editing on a clip
class TimeStretchEditState {
  /// Clip being edited
  final String clipId;

  /// Original clip duration
  final double originalDuration;

  /// Current stretched duration
  double stretchedDuration;

  /// Overall stretch ratio
  double get stretchRatio => stretchedDuration / originalDuration;

  /// Warp markers (user-placed)
  List<WarpMarkerData> warpMarkers;

  /// Auto-detected transient markers
  List<TransientMarkerData> transientMarkers;

  /// Stretch regions between markers
  List<StretchRegionData> stretchRegions;

  /// Detected BPM (if analyzed)
  double? detectedBpm;

  /// BPM confidence (0-1)
  double? bpmConfidence;

  /// Is in edit mode
  bool isEditing;

  /// Currently selected marker index
  int? selectedMarkerIndex;

  /// Currently dragged marker index
  int? draggedMarkerIndex;

  /// Preview stretch ratio (during drag)
  double? previewRatio;

  TimeStretchEditState({
    required this.clipId,
    required this.originalDuration,
    double? stretchedDuration,
    this.warpMarkers = const [],
    this.transientMarkers = const [],
    this.stretchRegions = const [],
    this.detectedBpm,
    this.bpmConfidence,
    this.isEditing = false,
    this.selectedMarkerIndex,
    this.draggedMarkerIndex,
    this.previewRatio,
  }) : stretchedDuration = stretchedDuration ?? originalDuration;

  TimeStretchEditState copyWith({
    double? stretchedDuration,
    List<WarpMarkerData>? warpMarkers,
    List<TransientMarkerData>? transientMarkers,
    List<StretchRegionData>? stretchRegions,
    double? detectedBpm,
    double? bpmConfidence,
    bool? isEditing,
    int? selectedMarkerIndex,
    int? draggedMarkerIndex,
    double? previewRatio,
  }) {
    return TimeStretchEditState(
      clipId: clipId,
      originalDuration: originalDuration,
      stretchedDuration: stretchedDuration ?? this.stretchedDuration,
      warpMarkers: warpMarkers ?? this.warpMarkers,
      transientMarkers: transientMarkers ?? this.transientMarkers,
      stretchRegions: stretchRegions ?? this.stretchRegions,
      detectedBpm: detectedBpm ?? this.detectedBpm,
      bpmConfidence: bpmConfidence ?? this.bpmConfidence,
      isEditing: isEditing ?? this.isEditing,
      selectedMarkerIndex: selectedMarkerIndex,
      draggedMarkerIndex: draggedMarkerIndex,
      previewRatio: previewRatio,
    );
  }
}

/// Warp marker data
class WarpMarkerData {
  /// Original time position (before stretch)
  final double originalTime;

  /// Warped time position (after stretch)
  double warpedTime;

  /// Is this marker locked (anchor)
  final bool locked;

  /// User label
  String? label;

  WarpMarkerData({
    required this.originalTime,
    required this.warpedTime,
    this.locked = false,
    this.label,
  });

  double get stretchFactor => warpedTime / originalTime;

  WarpMarkerData copyWith({
    double? warpedTime,
    bool? locked,
    String? label,
  }) {
    return WarpMarkerData(
      originalTime: originalTime,
      warpedTime: warpedTime ?? this.warpedTime,
      locked: locked ?? this.locked,
      label: label ?? this.label,
    );
  }
}

/// Transient marker (auto-detected)
class TransientMarkerData {
  /// Time position
  final double time;

  /// Detection confidence (0-1)
  final double confidence;

  /// Transient strength
  final double strength;

  const TransientMarkerData({
    required this.time,
    required this.confidence,
    this.strength = 1.0,
  });
}

/// Stretch region between two markers
class StretchRegionData {
  /// Start time (original)
  final double startOriginal;

  /// End time (original)
  final double endOriginal;

  /// Start time (warped)
  final double startWarped;

  /// End time (warped)
  final double endWarped;

  const StretchRegionData({
    required this.startOriginal,
    required this.endOriginal,
    required this.startWarped,
    required this.endWarped,
  });

  double get ratio => (endWarped - startWarped) / (endOriginal - startOriginal);
  bool get isCompressed => ratio < 0.99;
  bool get isExpanded => ratio > 1.01;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TIME STRETCH EDITOR WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Time stretch editor overlay for timeline clips
class TimeStretchEditor extends StatefulWidget {
  /// Edit state
  final TimeStretchEditState state;

  /// Clip width in pixels
  final double clipWidth;

  /// Clip height in pixels
  final double clipHeight;

  /// Zoom (pixels per second)
  final double zoom;

  /// Project tempo (for grid)
  final double tempo;

  /// Snap enabled
  final bool snapEnabled;

  /// Grid value in beats
  final double gridValue;

  /// Called when warp marker is added
  final ValueChanged<WarpMarkerData>? onMarkerAdded;

  /// Called when warp marker is moved
  final void Function(int index, double newWarpedTime)? onMarkerMoved;

  /// Called when warp marker is deleted
  final ValueChanged<int>? onMarkerDeleted;

  /// Called when overall stretch ratio changes
  final ValueChanged<double>? onStretchRatioChanged;

  /// Called when edit mode changes
  final ValueChanged<bool>? onEditModeChanged;

  /// Called to request BPM analysis
  final VoidCallback? onAnalyzeBpm;

  /// Called to quantize to grid
  final VoidCallback? onQuantizeToGrid;

  /// Called for real-time preview start
  final ValueChanged<double>? onPreviewStart;

  /// Called for real-time preview update
  final ValueChanged<double>? onPreviewUpdate;

  /// Called for real-time preview end
  final VoidCallback? onPreviewEnd;

  const TimeStretchEditor({
    super.key,
    required this.state,
    required this.clipWidth,
    required this.clipHeight,
    required this.zoom,
    this.tempo = 120,
    this.snapEnabled = false,
    this.gridValue = 0.25,
    this.onMarkerAdded,
    this.onMarkerMoved,
    this.onMarkerDeleted,
    this.onStretchRatioChanged,
    this.onEditModeChanged,
    this.onAnalyzeBpm,
    this.onQuantizeToGrid,
    this.onPreviewStart,
    this.onPreviewUpdate,
    this.onPreviewEnd,
  });

  @override
  State<TimeStretchEditor> createState() => _TimeStretchEditorState();
}

class _TimeStretchEditorState extends State<TimeStretchEditor>
    with SingleTickerProviderStateMixin {

  int? _hoveredMarkerIndex;
  bool _isDraggingEdge = false;
  bool _isDraggingMarker = false;
  double _dragStartX = 0;
  double _dragStartTime = 0;

  // Animation for highlight effects
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  double _timeToX(double time) => time * widget.zoom;
  double _xToTime(double x) => x / widget.zoom;

  double _snapTime(double time) {
    if (!widget.snapEnabled) return time;

    // Snap to grid
    final beatDuration = 60.0 / widget.tempo;
    final gridDuration = beatDuration * widget.gridValue;
    return (time / gridDuration).round() * gridDuration;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.state.isEditing) {
      // Non-editing mode: just show stretch indicator if stretched
      if ((widget.state.stretchRatio - 1.0).abs() < 0.01) {
        return const SizedBox.shrink();
      }
      return _buildCompactStretchIndicator();
    }

    return SizedBox(
      width: widget.clipWidth,
      height: widget.clipHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background stretch regions
          _buildStretchRegions(),

          // Transient markers (subtle)
          ..._buildTransientMarkers(),

          // Warp markers (interactive)
          ..._buildWarpMarkers(),

          // Edge stretch handles
          _buildLeftEdgeHandle(),
          _buildRightEdgeHandle(),

          // Toolbar (top)
          _buildToolbar(),

          // BPM indicator (if detected)
          if (widget.state.detectedBpm != null)
            _buildBpmIndicator(),

          // Overall ratio badge
          _buildRatioBadge(),

          // Double-click to add marker detection
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTapDown: (details) {
                final time = _xToTime(details.localPosition.dx);
                final snappedTime = _snapTime(time);
                _addWarpMarker(snappedTime);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactStretchIndicator() {
    final ratio = widget.state.stretchRatio;
    final isCompressed = ratio < 1.0;
    final color = isCompressed ? FluxForgeTheme.accentCyan : FluxForgeTheme.accentOrange;
    final text = '${(ratio * 100).toStringAsFixed(0)}%';

    return Positioned(
      right: 4,
      top: 4,
      child: GestureDetector(
        onTap: () => widget.onEditModeChanged?.call(true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isCompressed ? Icons.compress : Icons.expand,
                size: 12,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStretchRegions() {
    return Positioned.fill(
      child: CustomPaint(
        painter: _StretchRegionsPainter(
          regions: widget.state.stretchRegions,
          duration: widget.state.stretchedDuration,
          zoom: widget.zoom,
        ),
      ),
    );
  }

  List<Widget> _buildTransientMarkers() {
    return widget.state.transientMarkers.map((marker) {
      final x = _timeToX(marker.time);
      if (x < 0 || x > widget.clipWidth) return const SizedBox.shrink();

      final opacity = 0.2 + marker.confidence * 0.3;

      return Positioned(
        left: x - 1,
        top: 0,
        bottom: 0,
        width: 2,
        child: Container(
          color: FluxForgeTheme.textTertiary.withOpacity(opacity),
        ),
      );
    }).toList();
  }

  List<Widget> _buildWarpMarkers() {
    final markers = <Widget>[];

    for (int i = 0; i < widget.state.warpMarkers.length; i++) {
      final marker = widget.state.warpMarkers[i];
      final x = _timeToX(marker.warpedTime);
      if (x < -10 || x > widget.clipWidth + 10) continue;

      final isHovered = _hoveredMarkerIndex == i;
      final isSelected = widget.state.selectedMarkerIndex == i;
      final isDragging = widget.state.draggedMarkerIndex == i;

      markers.add(
        Positioned(
          left: x - 8,
          top: 0,
          bottom: 0,
          width: 16,
          child: _WarpMarkerWidget(
            marker: marker,
            index: i,
            isHovered: isHovered,
            isSelected: isSelected,
            isDragging: isDragging,
            height: widget.clipHeight,
            onHover: (hovering) {
              setState(() => _hoveredMarkerIndex = hovering ? i : null);
            },
            onDragStart: () => _startMarkerDrag(i),
            onDragUpdate: (dx) => _updateMarkerDrag(i, dx),
            onDragEnd: () => _endMarkerDrag(i),
            onDelete: () => widget.onMarkerDeleted?.call(i),
            onToggleLock: () {
              // Toggle lock state
            },
          ),
        ),
      );
    }

    return markers;
  }

  Widget _buildLeftEdgeHandle() {
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: 12,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          onHorizontalDragStart: (details) {
            _isDraggingEdge = true;
            _dragStartX = details.globalPosition.dx;
            _dragStartTime = widget.state.stretchedDuration;
            widget.onPreviewStart?.call(widget.state.stretchRatio);
          },
          onHorizontalDragUpdate: (details) {
            // Left edge: compress when dragging right, expand when dragging left
            final dx = details.globalPosition.dx - _dragStartX;
            final deltaTime = -_xToTime(dx);
            final newDuration = (_dragStartTime + deltaTime).clamp(
              widget.state.originalDuration * 0.25,
              widget.state.originalDuration * 4.0,
            );
            final newRatio = newDuration / widget.state.originalDuration;
            widget.onPreviewUpdate?.call(newRatio);
          },
          onHorizontalDragEnd: (details) {
            _isDraggingEdge = false;
            widget.onPreviewEnd?.call();
            // Apply final ratio
            final dx = details.velocity.pixelsPerSecond.dx;
            final deltaTime = -_xToTime(dx * 0.1);
            final newDuration = (_dragStartTime + deltaTime).clamp(
              widget.state.originalDuration * 0.25,
              widget.state.originalDuration * 4.0,
            );
            final newRatio = newDuration / widget.state.originalDuration;
            widget.onStretchRatioChanged?.call(newRatio);
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  FluxForgeTheme.accentOrange.withOpacity(0.3),
                  Colors.transparent,
                ],
              ),
            ),
            child: Center(
              child: Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentOrange,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRightEdgeHandle() {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: 12,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          onHorizontalDragStart: (details) {
            _isDraggingEdge = true;
            _dragStartX = details.globalPosition.dx;
            _dragStartTime = widget.state.stretchedDuration;
            widget.onPreviewStart?.call(widget.state.stretchRatio);
          },
          onHorizontalDragUpdate: (details) {
            final dx = details.globalPosition.dx - _dragStartX;
            final deltaTime = _xToTime(dx);
            final newDuration = (_dragStartTime + deltaTime).clamp(
              widget.state.originalDuration * 0.25,
              widget.state.originalDuration * 4.0,
            );
            final newRatio = newDuration / widget.state.originalDuration;
            widget.onPreviewUpdate?.call(newRatio);
          },
          onHorizontalDragEnd: (details) {
            _isDraggingEdge = false;
            widget.onPreviewEnd?.call();
            final dx = details.velocity.pixelsPerSecond.dx;
            final deltaTime = _xToTime(dx * 0.1);
            final newDuration = (_dragStartTime + deltaTime).clamp(
              widget.state.originalDuration * 0.25,
              widget.state.originalDuration * 4.0,
            );
            final newRatio = newDuration / widget.state.originalDuration;
            widget.onStretchRatioChanged?.call(newRatio);
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  FluxForgeTheme.accentOrange.withOpacity(0.3),
                ],
              ),
            ),
            child: Center(
              child: Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentOrange,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Positioned(
      left: 14,
      top: 2,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest.withOpacity(0.9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Analyze BPM
            _ToolbarButton(
              icon: Icons.graphic_eq,
              tooltip: 'Analyze BPM',
              onPressed: widget.onAnalyzeBpm,
            ),
            const SizedBox(width: 4),
            // Quantize
            _ToolbarButton(
              icon: Icons.grid_on,
              tooltip: 'Quantize to Grid',
              onPressed: widget.onQuantizeToGrid,
            ),
            const SizedBox(width: 4),
            // Exit edit mode
            _ToolbarButton(
              icon: Icons.check,
              tooltip: 'Done',
              color: FluxForgeTheme.accentGreen,
              onPressed: () => widget.onEditModeChanged?.call(false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBpmIndicator() {
    final bpm = widget.state.detectedBpm!;
    final confidence = widget.state.bpmConfidence ?? 0.0;
    final color = confidence > 0.7
        ? FluxForgeTheme.accentGreen
        : (confidence > 0.4 ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentRed);

    return Positioned(
      left: 14,
      bottom: 2,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.speed, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              '${bpm.toStringAsFixed(1)} BPM',
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatioBadge() {
    final ratio = widget.state.previewRatio ?? widget.state.stretchRatio;
    final isCompressed = ratio < 1.0;
    final color = isCompressed ? FluxForgeTheme.accentCyan : FluxForgeTheme.accentOrange;
    final text = '${(ratio * 100).toStringAsFixed(0)}%';

    return Positioned(
      right: 14,
      bottom: 2,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final opacity = widget.state.draggedMarkerIndex != null || _isDraggingEdge
              ? 0.5 + _pulseController.value * 0.5
              : 1.0;
          return Opacity(opacity: opacity, child: child);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.3),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ),
      ),
    );
  }

  void _addWarpMarker(double time) {
    final marker = WarpMarkerData(
      originalTime: time,
      warpedTime: time,
    );
    widget.onMarkerAdded?.call(marker);
  }

  void _startMarkerDrag(int index) {
    _isDraggingMarker = true;
    final marker = widget.state.warpMarkers[index];
    _dragStartTime = marker.warpedTime;
    widget.onPreviewStart?.call(widget.state.stretchRatio);
  }

  void _updateMarkerDrag(int index, double dx) {
    final deltaTime = _xToTime(dx);
    var newTime = _dragStartTime + deltaTime;
    newTime = _snapTime(newTime);

    // Constrain to clip bounds and neighboring markers
    final markers = widget.state.warpMarkers;
    final minTime = index > 0 ? markers[index - 1].warpedTime + 0.01 : 0.0;
    final maxTime = index < markers.length - 1
        ? markers[index + 1].warpedTime - 0.01
        : widget.state.stretchedDuration;
    newTime = newTime.clamp(minTime, maxTime);

    widget.onMarkerMoved?.call(index, newTime);
  }

  void _endMarkerDrag(int index) {
    _isDraggingMarker = false;
    widget.onPreviewEnd?.call();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(2),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            icon,
            size: 14,
            color: color ?? FluxForgeTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _WarpMarkerWidget extends StatelessWidget {
  final WarpMarkerData marker;
  final int index;
  final bool isHovered;
  final bool isSelected;
  final bool isDragging;
  final double height;
  final ValueChanged<bool> onHover;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleLock;

  const _WarpMarkerWidget({
    required this.marker,
    required this.index,
    required this.isHovered,
    required this.isSelected,
    required this.isDragging,
    required this.height,
    required this.onHover,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.onDelete,
    this.onToggleLock,
  });

  @override
  Widget build(BuildContext context) {
    final color = marker.locked
        ? FluxForgeTheme.accentRed
        : FluxForgeTheme.accentOrange;
    final opacity = isHovered || isSelected || isDragging ? 1.0 : 0.7;

    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      cursor: marker.locked ? SystemMouseCursors.forbidden : SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onPanStart: marker.locked ? null : (d) => onDragStart(),
        onPanUpdate: marker.locked ? null : (d) => onDragUpdate(d.delta.dx),
        onPanEnd: marker.locked ? null : (d) => onDragEnd(),
        onSecondaryTap: () {
          // Show context menu
          _showContextMenu(context);
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Vertical line
            Positioned(
              left: 7,
              top: 12,
              bottom: 0,
              width: 2,
              child: Container(
                color: color.withOpacity(opacity * 0.8),
              ),
            ),
            // Diamond handle at top
            Positioned(
              top: 2,
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: isHovered || isDragging ? 10 : 8,
                  height: isHovered || isDragging ? 10 : 8,
                  decoration: BoxDecoration(
                    color: color.withOpacity(opacity),
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                  ),
                ),
              ),
            ),
            // Lock icon for anchors
            if (marker.locked)
              Positioned(
                top: 2,
                child: Icon(
                  Icons.lock,
                  size: 8,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy,
        offset.dx + 1,
        offset.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'lock',
          child: Row(
            children: [
              Icon(marker.locked ? Icons.lock_open : Icons.lock, size: 16),
              const SizedBox(width: 8),
              Text(marker.locked ? 'Unlock' : 'Lock'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 16, color: FluxForgeTheme.accentRed),
              const SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: FluxForgeTheme.accentRed)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'lock') {
        onToggleLock?.call();
      } else if (value == 'delete') {
        onDelete?.call();
      }
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class _StretchRegionsPainter extends CustomPainter {
  final List<StretchRegionData> regions;
  final double duration;
  final double zoom;

  _StretchRegionsPainter({
    required this.regions,
    required this.duration,
    required this.zoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final region in regions) {
      if ((region.ratio - 1.0).abs() < 0.01) continue;

      final startX = region.startWarped * zoom;
      final endX = region.endWarped * zoom;
      final width = endX - startX;

      if (width < 1 || startX > size.width || endX < 0) continue;

      // Color based on stretch/compress
      final color = region.isCompressed
          ? FluxForgeTheme.accentCyan
          : FluxForgeTheme.accentOrange;

      final intensity = (region.ratio - 1.0).abs().clamp(0.0, 1.0);

      final paint = Paint()
        ..color = color.withOpacity(0.1 + intensity * 0.2)
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromLTWH(startX, 0, width, size.height),
        paint,
      );

      // Draw ratio label for significant regions
      if (width > 30) {
        final text = '${(region.ratio * 100).toStringAsFixed(0)}%';
        final textPainter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              fontFamily: 'JetBrains Mono',
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();

        final textX = startX + (width - textPainter.width) / 2;
        final textY = (size.height - textPainter.height) / 2;

        // Background
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(textX - 3, textY - 1, textPainter.width + 6, textPainter.height + 2),
            const Radius.circular(2),
          ),
          Paint()..color = FluxForgeTheme.bgDeepest.withOpacity(0.8),
        );

        textPainter.paint(canvas, Offset(textX, textY));
      }
    }
  }

  @override
  bool shouldRepaint(_StretchRegionsPainter oldDelegate) =>
      regions != oldDelegate.regions ||
      duration != oldDelegate.duration ||
      zoom != oldDelegate.zoom;
}
