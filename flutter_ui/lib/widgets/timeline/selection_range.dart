/// Selection Range Widget
///
/// Cubase/Pro Tools style time selection with:
/// - Rubber-band selection
/// - Resize handles at edges
/// - Selection info tooltip
/// - Snap to grid
/// - Multi-clip selection support

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// Selection range data
class TimeSelection {
  final double start;
  final double end;

  const TimeSelection({required this.start, required this.end});

  double get duration => end - start;
  bool get isValid => end > start && duration > 0.001;

  TimeSelection copyWith({double? start, double? end}) {
    return TimeSelection(
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }

  /// Normalize selection (ensure start < end)
  TimeSelection normalized() {
    if (start <= end) return this;
    return TimeSelection(start: end, end: start);
  }

  @override
  String toString() => 'TimeSelection($start - $end)';
}

/// Selection overlay widget
class SelectionRangeOverlay extends StatefulWidget {
  /// Current selection (can be null if no selection)
  final TimeSelection? selection;

  /// Zoom level (pixels per second)
  final double zoom;

  /// Scroll offset
  final double scrollOffset;

  /// Total duration
  final double totalDuration;

  /// Height of the overlay
  final double height;

  /// Called when selection changes
  final ValueChanged<TimeSelection?>? onSelectionChange;

  /// Called when selection is completed (mouse up)
  final ValueChanged<TimeSelection?>? onSelectionComplete;

  /// Snap enabled
  final bool snapEnabled;

  /// Snap value
  final double snapValue;

  /// Tempo for beat snapping
  final double tempo;

  const SelectionRangeOverlay({
    super.key,
    this.selection,
    required this.zoom,
    required this.scrollOffset,
    required this.totalDuration,
    required this.height,
    this.onSelectionChange,
    this.onSelectionComplete,
    this.snapEnabled = true,
    this.snapValue = 1.0,
    this.tempo = 120.0,
  });

  @override
  State<SelectionRangeOverlay> createState() => _SelectionRangeOverlayState();
}

class _SelectionRangeOverlayState extends State<SelectionRangeOverlay> {
  bool _isCreatingSelection = false;
  bool _isDraggingStart = false;
  bool _isDraggingEnd = false;
  bool _isDraggingMiddle = false;
  double _dragStartTime = 0;
  double _dragStartX = 0;
  TimeSelection? _dragStartSelection;

  double _xToTime(double x) {
    return widget.scrollOffset + x / widget.zoom;
  }

  double _timeToX(double time) {
    return (time - widget.scrollOffset) * widget.zoom;
  }

  double _snapTime(double time) {
    if (!widget.snapEnabled || widget.snapValue <= 0) return time;
    return snapToGrid(time, widget.snapValue, widget.tempo);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: _handleTapDown,
          child: Stack(
            children: [
              // Selection rectangle
              if (widget.selection != null && widget.selection!.isValid)
                _buildSelectionRect(constraints.maxWidth),

              // Invisible handles for creating new selection
              // (Alt+drag to create selection)
            ],
          ),
        );
      },
    );
  }

  Widget _buildSelectionRect(double containerWidth) {
    final selection = widget.selection!;
    final startX = _timeToX(selection.start);
    final endX = _timeToX(selection.end);

    // Clip to visible area
    final visibleStartX = startX.clamp(0.0, containerWidth);
    final visibleEndX = endX.clamp(0.0, containerWidth);

    if (visibleEndX <= visibleStartX) return const SizedBox.shrink();

    return Positioned(
      left: visibleStartX,
      top: 0,
      width: visibleEndX - visibleStartX,
      height: widget.height,
      child: GestureDetector(
        onHorizontalDragStart: _handleMiddleDragStart,
        onHorizontalDragUpdate: _handleMiddleDragUpdate,
        onHorizontalDragEnd: _handleMiddleDragEnd,
        child: Stack(
          children: [
            // Selection fill
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentBlue.withValues(alpha: 0.15),
                  border: Border.all(
                    color: FluxForgeTheme.accentBlue.withValues(alpha: 0.6),
                    width: 1,
                  ),
                ),
              ),
            ),

            // Left edge handle
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 6,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  onHorizontalDragStart: (d) => _handleEdgeDragStart(d, true),
                  onHorizontalDragUpdate: (d) => _handleEdgeDragUpdate(d, true),
                  onHorizontalDragEnd: _handleEdgeDragEnd,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _isDraggingStart
                          ? FluxForgeTheme.accentBlue
                          : FluxForgeTheme.accentBlue.withValues(alpha: 0.6),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(2),
                        bottomLeft: Radius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Right edge handle
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 6,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  onHorizontalDragStart: (d) => _handleEdgeDragStart(d, false),
                  onHorizontalDragUpdate: (d) => _handleEdgeDragUpdate(d, false),
                  onHorizontalDragEnd: _handleEdgeDragEnd,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _isDraggingEnd
                          ? FluxForgeTheme.accentBlue
                          : FluxForgeTheme.accentBlue.withValues(alpha: 0.6),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(2),
                        bottomRight: Radius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Duration label (centered)
            if (endX - startX > 60)
              Positioned(
                left: 0,
                right: 0,
                top: 2,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgDeepest.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      _formatDuration(selection.duration),
                      style: FluxForgeTheme.monoSmall.copyWith(
                        fontSize: 9,
                        color: FluxForgeTheme.accentBlue,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _handleTapDown(TapDownDetails details) {
    // Clear selection on tap (unless clicking on selection)
    if (widget.selection != null) {
      final time = _xToTime(details.localPosition.dx);
      if (time < widget.selection!.start || time > widget.selection!.end) {
        widget.onSelectionChange?.call(null);
        widget.onSelectionComplete?.call(null);
      }
    }
  }

  void _handleEdgeDragStart(DragStartDetails details, bool isStart) {
    setState(() {
      _isDraggingStart = isStart;
      _isDraggingEnd = !isStart;
      _dragStartSelection = widget.selection;
    });
  }

  void _handleEdgeDragUpdate(DragUpdateDetails details, bool isStart) {
    if (_dragStartSelection == null) return;

    final parentBox = context.findRenderObject() as RenderBox?;
    if (parentBox == null) return;

    final localPos = parentBox.globalToLocal(details.globalPosition);
    final time = _snapTime(_xToTime(localPos.dx).clamp(0, widget.totalDuration));

    TimeSelection newSelection;
    if (isStart) {
      newSelection = TimeSelection(
        start: time,
        end: _dragStartSelection!.end,
      ).normalized();
    } else {
      newSelection = TimeSelection(
        start: _dragStartSelection!.start,
        end: time,
      ).normalized();
    }

    widget.onSelectionChange?.call(newSelection);
  }

  void _handleEdgeDragEnd(DragEndDetails details) {
    setState(() {
      _isDraggingStart = false;
      _isDraggingEnd = false;
      _dragStartSelection = null;
    });
    widget.onSelectionComplete?.call(widget.selection);
  }

  void _handleMiddleDragStart(DragStartDetails details) {
    setState(() {
      _isDraggingMiddle = true;
      _dragStartX = details.localPosition.dx;
      _dragStartSelection = widget.selection;
    });
  }

  void _handleMiddleDragUpdate(DragUpdateDetails details) {
    if (_dragStartSelection == null || !_isDraggingMiddle) return;

    final deltaX = details.localPosition.dx - _dragStartX;
    final deltaTime = deltaX / widget.zoom;

    var newStart = _dragStartSelection!.start + deltaTime;
    var newEnd = _dragStartSelection!.end + deltaTime;

    // Clamp to valid range
    if (newStart < 0) {
      newEnd -= newStart;
      newStart = 0;
    }
    if (newEnd > widget.totalDuration) {
      newStart -= (newEnd - widget.totalDuration);
      newEnd = widget.totalDuration;
    }

    widget.onSelectionChange?.call(TimeSelection(start: newStart, end: newEnd));
  }

  void _handleMiddleDragEnd(DragEndDetails details) {
    setState(() {
      _isDraggingMiddle = false;
      _dragStartSelection = null;
    });
    widget.onSelectionComplete?.call(widget.selection);
  }

  String _formatDuration(double seconds) {
    if (seconds < 1) {
      return '${(seconds * 1000).round()} ms';
    } else if (seconds < 60) {
      return '${seconds.toStringAsFixed(2)} s';
    } else {
      final mins = (seconds / 60).floor();
      final secs = seconds % 60;
      return '${mins}:${secs.toStringAsFixed(1).padLeft(4, '0')}';
    }
  }
}

/// Helper function to snap to grid
double snapToGrid(double time, double snapValue, double tempo) {
  if (snapValue <= 0) return time;

  final beatsPerSecond = tempo / 60;
  final beatDuration = 1 / beatsPerSecond;
  final snapDuration = beatDuration * snapValue;

  return (time / snapDuration).round() * snapDuration;
}

/// Selection range model extension
extension TimeSelectionExtension on TimeSelection? {
  bool get isNotEmpty => this != null && this!.isValid;
}
