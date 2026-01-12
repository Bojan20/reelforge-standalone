/// Comping Lane Widget
///
/// Renders a recording lane with takes for comping:
/// - Multi-take stacking visualization
/// - Active take highlighting
/// - Comp region selection
/// - Take drag & drop reordering

import 'package:flutter/material.dart';
import '../../models/comping_models.dart';
import '../../models/timeline_models.dart';
import '../../theme/fluxforge_theme.dart';
import 'lane_header.dart';

/// Single lane in comping view
class CompingLaneWidget extends StatelessWidget {
  final RecordingLane lane;
  final double pixelsPerSecond;
  final double scrollOffset;
  final double visibleWidth;
  final double trackHeaderWidth;
  final bool showHeader;
  final bool isExpanded;

  final VoidCallback? onActivate;
  final VoidCallback? onToggleMute;
  final VoidCallback? onToggleVisible;
  final VoidCallback? onDelete;
  final Function(Take)? onTakeTap;
  final Function(Take)? onTakeDoubleTap;
  final Function(Take, double)? onTakeMove;
  final Function(Take, TakeRating)? onTakeRatingChanged;
  final Function(double, double)? onCompRegionSelect;

  const CompingLaneWidget({
    super.key,
    required this.lane,
    required this.pixelsPerSecond,
    required this.scrollOffset,
    required this.visibleWidth,
    this.trackHeaderWidth = 100,
    this.showHeader = true,
    this.isExpanded = false,
    this.onActivate,
    this.onToggleMute,
    this.onToggleVisible,
    this.onDelete,
    this.onTakeTap,
    this.onTakeDoubleTap,
    this.onTakeMove,
    this.onTakeRatingChanged,
    this.onCompRegionSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: lane.height,
      child: Row(
        children: [
          // Lane header
          if (showHeader)
            isExpanded
                ? LaneHeaderExpanded(
                    lane: lane,
                    isActive: lane.isActive,
                    onActivate: onActivate,
                    onToggleMute: onToggleMute,
                    onToggleVisible: onToggleVisible,
                    onDelete: onDelete,
                  )
                : LaneHeader(
                    lane: lane,
                    isActive: lane.isActive,
                    onActivate: onActivate,
                    onToggleMute: onToggleMute,
                    onToggleVisible: onToggleVisible,
                    onDelete: onDelete,
                  ),

          // Lane content (takes)
          Expanded(
            child: _CompingLaneContent(
              lane: lane,
              pixelsPerSecond: pixelsPerSecond,
              scrollOffset: scrollOffset,
              visibleWidth: visibleWidth,
              onTakeTap: onTakeTap,
              onTakeDoubleTap: onTakeDoubleTap,
              onTakeMove: onTakeMove,
              onCompRegionSelect: onCompRegionSelect,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lane content (takes area)
class _CompingLaneContent extends StatefulWidget {
  final RecordingLane lane;
  final double pixelsPerSecond;
  final double scrollOffset;
  final double visibleWidth;
  final Function(Take)? onTakeTap;
  final Function(Take)? onTakeDoubleTap;
  final Function(Take, double)? onTakeMove;
  final Function(double, double)? onCompRegionSelect;

  const _CompingLaneContent({
    required this.lane,
    required this.pixelsPerSecond,
    required this.scrollOffset,
    required this.visibleWidth,
    this.onTakeTap,
    this.onTakeDoubleTap,
    this.onTakeMove,
    this.onCompRegionSelect,
  });

  @override
  State<_CompingLaneContent> createState() => _CompingLaneContentState();
}

class _CompingLaneContentState extends State<_CompingLaneContent> {
  // Selection state
  double? _selectionStart;
  double? _selectionEnd;
  bool _isSelecting = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Start comp region selection
      onHorizontalDragStart: (details) {
        final localX = details.localPosition.dx + widget.scrollOffset;
        final time = localX / widget.pixelsPerSecond;
        setState(() {
          _isSelecting = true;
          _selectionStart = time;
          _selectionEnd = time;
        });
      },
      onHorizontalDragUpdate: (details) {
        if (_isSelecting) {
          final localX = details.localPosition.dx + widget.scrollOffset;
          final time = localX / widget.pixelsPerSecond;
          setState(() {
            _selectionEnd = time;
          });
        }
      },
      onHorizontalDragEnd: (details) {
        if (_isSelecting && _selectionStart != null && _selectionEnd != null) {
          final start =
              _selectionStart! < _selectionEnd! ? _selectionStart! : _selectionEnd!;
          final end =
              _selectionStart! < _selectionEnd! ? _selectionEnd! : _selectionStart!;

          // Only create region if selection is significant
          if ((end - start) > 0.05) {
            widget.onCompRegionSelect?.call(start, end);
          }
        }
        setState(() {
          _isSelecting = false;
          _selectionStart = null;
          _selectionEnd = null;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: widget.lane.isActive
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.05)
              : FluxForgeTheme.bgMid,
          border: Border(
            bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Grid lines
            _buildGridLines(),

            // Takes
            ...widget.lane.takes.map((take) => _buildTake(take)),

            // Selection overlay
            if (_isSelecting && _selectionStart != null && _selectionEnd != null)
              _buildSelectionOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildGridLines() {
    return CustomPaint(
      size: Size(widget.visibleWidth, widget.lane.height),
      painter: _LaneGridPainter(
        pixelsPerSecond: widget.pixelsPerSecond,
        scrollOffset: widget.scrollOffset,
      ),
    );
  }

  Widget _buildTake(Take take) {
    final startX = take.startTime * widget.pixelsPerSecond - widget.scrollOffset;
    final width = take.duration * widget.pixelsPerSecond;

    // Skip if not visible
    if (startX + width < 0 || startX > widget.visibleWidth) {
      return const SizedBox.shrink();
    }

    final clip = take.toClip();
    final laneColor = widget.lane.color ?? getLaneColor(widget.lane.index);

    return Positioned(
      left: startX,
      top: 2,
      bottom: 2,
      width: width,
      child: GestureDetector(
        onTap: () => widget.onTakeTap?.call(take),
        onDoubleTap: () => widget.onTakeDoubleTap?.call(take),
        child: _TakeWidget(
          take: take,
          clip: clip,
          laneColor: laneColor,
          pixelsPerSecond: widget.pixelsPerSecond,
          isActive: widget.lane.isActive,
        ),
      ),
    );
  }

  Widget _buildSelectionOverlay() {
    final start = _selectionStart! < _selectionEnd! ? _selectionStart! : _selectionEnd!;
    final end = _selectionStart! < _selectionEnd! ? _selectionEnd! : _selectionStart!;

    final startX = start * widget.pixelsPerSecond - widget.scrollOffset;
    final endX = end * widget.pixelsPerSecond - widget.scrollOffset;

    return Positioned(
      left: startX.clamp(0, widget.visibleWidth),
      right: (widget.visibleWidth - endX).clamp(0, widget.visibleWidth),
      top: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3),
          border: Border.all(
            color: FluxForgeTheme.accentBlue,
            width: 1,
          ),
        ),
      ),
    );
  }
}

/// Take widget (similar to clip but with comping features)
class _TakeWidget extends StatelessWidget {
  final Take take;
  final TimelineClip clip;
  final Color laneColor;
  final double pixelsPerSecond;
  final bool isActive;

  const _TakeWidget({
    required this.take,
    required this.clip,
    required this.laneColor,
    required this.pixelsPerSecond,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: take.inComp
            ? laneColor.withValues(alpha: 0.4)
            : laneColor.withValues(alpha: isActive ? 0.3 : 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: take.inComp
              ? FluxForgeTheme.accentGreen
              : laneColor.withValues(alpha: isActive ? 1.0 : 0.5),
          width: take.inComp ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          // Waveform
          if (take.waveform != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: CustomPaint(
                  painter: _WaveformPainter(
                    waveform: take.waveform!,
                    color: laneColor.withValues(alpha: isActive ? 0.8 : 0.5),
                  ),
                ),
              ),
            ),

          // Take info overlay
          Positioned(
            left: 4,
            top: 2,
            right: 4,
            child: Row(
              children: [
                // Take name
                Expanded(
                  child: Text(
                    take.displayName,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: FluxForgeTheme.textPrimary,
                      shadows: [
                        Shadow(
                          blurRadius: 2,
                          color: Colors.black.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Rating indicator
                if (take.rating != TakeRating.none)
                  Icon(
                    take.ratingIcon,
                    size: 10,
                    color: take.ratingColor,
                  ),

                // In comp indicator
                if (take.inComp)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentGreen,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      'C',
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                        color: FluxForgeTheme.bgDeepest,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Muted overlay
          if (take.muted)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Center(
                  child: Icon(
                    Icons.volume_off,
                    size: 16,
                    color: FluxForgeTheme.textTertiary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Grid painter for lane
class _LaneGridPainter extends CustomPainter {
  final double pixelsPerSecond;
  final double scrollOffset;

  _LaneGridPainter({
    required this.pixelsPerSecond,
    required this.scrollOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Calculate grid interval
    double gridInterval = 1.0; // 1 second
    if (pixelsPerSecond < 10) {
      gridInterval = 10.0;
    } else if (pixelsPerSecond < 50) {
      gridInterval = 5.0;
    } else if (pixelsPerSecond > 200) {
      gridInterval = 0.5;
    }

    final startTime = (scrollOffset / pixelsPerSecond / gridInterval).floor() * gridInterval;
    final endTime = ((scrollOffset + size.width) / pixelsPerSecond / gridInterval).ceil() * gridInterval;

    for (double t = startTime; t <= endTime; t += gridInterval) {
      final x = t * pixelsPerSecond - scrollOffset;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LaneGridPainter oldDelegate) {
    return pixelsPerSecond != oldDelegate.pixelsPerSecond ||
        scrollOffset != oldDelegate.scrollOffset;
  }
}

/// Waveform painter
class _WaveformPainter extends CustomPainter {
  final List<double> waveform;
  final Color color;

  _WaveformPainter({
    required List<dynamic> waveform,
    required this.color,
  }) : waveform = waveform.map((e) => (e as num).toDouble()).toList();

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final centerY = size.height / 2;
    final samplesPerPixel = (waveform.length / size.width).ceil().clamp(1, waveform.length);

    path.moveTo(0, centerY);

    for (int x = 0; x < size.width; x++) {
      final sampleIdx = (x * samplesPerPixel).clamp(0, waveform.length - 1);
      final sample = waveform[sampleIdx].clamp(-1.0, 1.0);
      final y = centerY - (sample * centerY * 0.8);
      path.lineTo(x.toDouble(), y);
    }

    // Complete the path back
    for (int x = size.width.toInt() - 1; x >= 0; x--) {
      final sampleIdx = (x * samplesPerPixel).clamp(0, waveform.length - 1);
      final sample = waveform[sampleIdx].clamp(-1.0, 1.0);
      final y = centerY + (sample.abs() * centerY * 0.8);
      path.lineTo(x.toDouble(), y);
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return waveform != oldDelegate.waveform || color != oldDelegate.color;
  }
}

/// Full comping view for a track (shows all lanes)
class CompingView extends StatelessWidget {
  final CompState compState;
  final double pixelsPerSecond;
  final double scrollOffset;
  final double visibleWidth;
  final double trackHeaderWidth;

  final Function(int)? onActiveLaneChanged;
  final Function(String)? onLaneMuteToggle;
  final Function(String)? onLaneDelete;
  final Function(Take)? onTakeTap;
  final Function(Take)? onTakeDoubleTap;
  final Function(String, double, double)? onCompRegionCreated;

  const CompingView({
    super.key,
    required this.compState,
    required this.pixelsPerSecond,
    required this.scrollOffset,
    required this.visibleWidth,
    this.trackHeaderWidth = 100,
    this.onActiveLaneChanged,
    this.onLaneMuteToggle,
    this.onLaneDelete,
    this.onTakeTap,
    this.onTakeDoubleTap,
    this.onCompRegionCreated,
  });

  @override
  Widget build(BuildContext context) {
    if (compState.lanes.isEmpty) {
      return _buildEmptyState();
    }

    final visibleLanes = compState.lanesExpanded
        ? compState.lanes.where((l) => l.visible).toList()
        : [compState.lanes[compState.activeLaneIndex]];

    return Column(
      children: [
        // Lanes
        ...visibleLanes.asMap().entries.map((entry) {
          final index = entry.key;
          final lane = entry.value;

          return CompingLaneWidget(
            lane: lane,
            pixelsPerSecond: pixelsPerSecond,
            scrollOffset: scrollOffset,
            visibleWidth: visibleWidth,
            trackHeaderWidth: trackHeaderWidth,
            isExpanded: compState.lanesExpanded,
            onActivate: () => onActiveLaneChanged?.call(index),
            onToggleMute: () => onLaneMuteToggle?.call(lane.id),
            onDelete: () => onLaneDelete?.call(lane.id),
            onTakeTap: onTakeTap,
            onTakeDoubleTap: onTakeDoubleTap,
            onCompRegionSelect: (start, end) {
              // Find which take this selection is on
              final takes = lane.takes.where(
                (t) => t.startTime <= start && t.endTime >= end,
              );
              if (takes.isNotEmpty) {
                onCompRegionCreated?.call(takes.first.id, start, end);
              }
            },
          );
        }),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Center(
        child: Text(
          'No lanes - Record to create takes',
          style: FluxForgeTheme.label.copyWith(
            color: FluxForgeTheme.textTertiary,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
