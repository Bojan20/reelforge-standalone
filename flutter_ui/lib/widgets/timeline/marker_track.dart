// Marker Track Widget
//
// Professional marker track with:
// - Position markers (Cubase-style)
// - Cycle/loop regions
// - Arrangement regions (verse, chorus, etc.)
// - Color coding
// - Marker labels
// - Snap to markers
// - Export marker list

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../theme/fluxforge_theme.dart';

/// Marker type
enum MarkerType {
  position, // Single point marker
  cycle,    // Loop region
  arrangement, // Arrangement section (verse, chorus, etc.)
}

/// Arrangement section type
enum ArrangementSection {
  intro,
  verse,
  preChorus,
  chorus,
  bridge,
  outro,
  solo,
  breakdown,
  buildup,
  drop,
  custom,
}

extension ArrangementSectionExt on ArrangementSection {
  String get label {
    switch (this) {
      case ArrangementSection.intro: return 'Intro';
      case ArrangementSection.verse: return 'Verse';
      case ArrangementSection.preChorus: return 'Pre-Chorus';
      case ArrangementSection.chorus: return 'Chorus';
      case ArrangementSection.bridge: return 'Bridge';
      case ArrangementSection.outro: return 'Outro';
      case ArrangementSection.solo: return 'Solo';
      case ArrangementSection.breakdown: return 'Breakdown';
      case ArrangementSection.buildup: return 'Buildup';
      case ArrangementSection.drop: return 'Drop';
      case ArrangementSection.custom: return 'Custom';
    }
  }

  Color get color {
    switch (this) {
      case ArrangementSection.intro: return const Color(0xFF9C27B0);
      case ArrangementSection.verse: return const Color(0xFF2196F3);
      case ArrangementSection.preChorus: return const Color(0xFF00BCD4);
      case ArrangementSection.chorus: return const Color(0xFF4CAF50);
      case ArrangementSection.bridge: return const Color(0xFFFF9800);
      case ArrangementSection.outro: return const Color(0xFF795548);
      case ArrangementSection.solo: return const Color(0xFFE91E63);
      case ArrangementSection.breakdown: return const Color(0xFF607D8B);
      case ArrangementSection.buildup: return const Color(0xFFFFEB3B);
      case ArrangementSection.drop: return const Color(0xFFF44336);
      case ArrangementSection.custom: return const Color(0xFF9E9E9E);
    }
  }
}

/// Marker data
class TimelineMarker {
  final String id;
  final MarkerType type;
  final double startTime; // seconds
  final double? endTime; // seconds (for regions)
  final String name;
  final Color color;
  final ArrangementSection? section;
  final String? description;
  final bool isLocked;

  TimelineMarker({
    required this.id,
    required this.type,
    required this.startTime,
    this.endTime,
    required this.name,
    required this.color,
    this.section,
    this.description,
    this.isLocked = false,
  });

  double get duration => (endTime ?? startTime) - startTime;

  TimelineMarker copyWith({
    String? id,
    MarkerType? type,
    double? startTime,
    double? endTime,
    String? name,
    Color? color,
    ArrangementSection? section,
    String? description,
    bool? isLocked,
  }) {
    return TimelineMarker(
      id: id ?? this.id,
      type: type ?? this.type,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      name: name ?? this.name,
      color: color ?? this.color,
      section: section ?? this.section,
      description: description ?? this.description,
      isLocked: isLocked ?? this.isLocked,
    );
  }
}

/// Marker Track Widget
class MarkerTrack extends StatefulWidget {
  final List<TimelineMarker> markers;
  final double zoom; // pixels per second
  final double scrollOffset;
  final double height;
  final double? cycleStart;
  final double? cycleEnd;
  final ValueChanged<TimelineMarker>? onMarkerTap;
  final ValueChanged<TimelineMarker>? onMarkerDoubleTap;
  final void Function(TimelineMarker marker, double newTime)? onMarkerMoved;
  final void Function(TimelineMarker marker, double newEnd)? onRegionResized;
  final void Function(double time, MarkerType type)? onAddMarker;
  final ValueChanged<TimelineMarker>? onDeleteMarker;

  const MarkerTrack({
    super.key,
    required this.markers,
    required this.zoom,
    required this.scrollOffset,
    this.height = 48,
    this.cycleStart,
    this.cycleEnd,
    this.onMarkerTap,
    this.onMarkerDoubleTap,
    this.onMarkerMoved,
    this.onRegionResized,
    this.onAddMarker,
    this.onDeleteMarker,
  });

  @override
  State<MarkerTrack> createState() => _MarkerTrackState();
}

class _MarkerTrackState extends State<MarkerTrack> {
  TimelineMarker? _hoveredMarker;
  TimelineMarker? _draggingMarker;
  bool _isDraggingEnd = false;
  double _dragStartX = 0;
  double _dragStartTime = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: const Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Header
          Container(
            width: 180,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              border: Border(
                right: BorderSide(color: FluxForgeTheme.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.bookmark, size: 16, color: FluxForgeTheme.accentOrange),
                const SizedBox(width: 8),
                const Text(
                  'Markers',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                PopupMenuButton<MarkerType>(
                  icon: const Icon(Icons.add, size: 14, color: Colors.white54),
                  tooltip: 'Add Marker',
                  color: FluxForgeTheme.bgMid,
                  onSelected: (type) => widget.onAddMarker?.call(0, type),
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: MarkerType.position,
                      child: Row(
                        children: [
                          Icon(Icons.place, size: 14, color: FluxForgeTheme.accentBlue),
                          SizedBox(width: 8),
                          Text('Position Marker', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: MarkerType.cycle,
                      child: Row(
                        children: [
                          Icon(Icons.loop, size: 14, color: FluxForgeTheme.accentGreen),
                          SizedBox(width: 8),
                          Text('Cycle Region', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: MarkerType.arrangement,
                      child: Row(
                        children: [
                          Icon(Icons.view_column, size: 14, color: FluxForgeTheme.accentOrange),
                          SizedBox(width: 8),
                          Text('Arrangement', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Markers area
          Expanded(
            child: ClipRect(
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    // Could implement horizontal scroll
                  }
                },
                child: GestureDetector(
                  onDoubleTapDown: (details) {
                    final time = (details.localPosition.dx + widget.scrollOffset) / widget.zoom;
                    widget.onAddMarker?.call(time, MarkerType.position);
                  },
                  child: CustomPaint(
                    painter: _MarkerTrackPainter(
                      markers: widget.markers,
                      zoom: widget.zoom,
                      scrollOffset: widget.scrollOffset,
                      cycleStart: widget.cycleStart,
                      cycleEnd: widget.cycleEnd,
                      hoveredMarker: _hoveredMarker,
                      height: widget.height,
                    ),
                    child: MouseRegion(
                      onHover: (event) => _handleHover(event.localPosition),
                      onExit: (_) => setState(() => _hoveredMarker = null),
                      child: GestureDetector(
                        onTapDown: (details) => _handleTap(details.localPosition),
                        onDoubleTapDown: (details) => _handleDoubleTap(details.localPosition),
                        onPanStart: (details) => _handleDragStart(details.localPosition),
                        onPanUpdate: (details) => _handleDragUpdate(details.localPosition),
                        onPanEnd: (_) => _handleDragEnd(),
                        child: Container(color: Colors.transparent),
                      ),
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

  TimelineMarker? _hitTest(Offset position) {
    final time = (position.dx + widget.scrollOffset) / widget.zoom;

    // Check regions first (they're larger)
    for (final marker in widget.markers.where((m) => m.type != MarkerType.position)) {
      if (time >= marker.startTime && time <= (marker.endTime ?? marker.startTime)) {
        return marker;
      }
    }

    // Check position markers
    for (final marker in widget.markers.where((m) => m.type == MarkerType.position)) {
      final markerX = marker.startTime * widget.zoom - widget.scrollOffset;
      if ((position.dx - markerX).abs() < 10) {
        return marker;
      }
    }

    return null;
  }

  void _handleHover(Offset position) {
    final marker = _hitTest(position);
    if (marker != _hoveredMarker) {
      setState(() => _hoveredMarker = marker);
    }
  }

  void _handleTap(Offset position) {
    final marker = _hitTest(position);
    if (marker != null) {
      widget.onMarkerTap?.call(marker);
    }
  }

  void _handleDoubleTap(Offset position) {
    final marker = _hitTest(position);
    if (marker != null) {
      widget.onMarkerDoubleTap?.call(marker);
    }
  }

  void _handleDragStart(Offset position) {
    final marker = _hitTest(position);
    if (marker != null && !marker.isLocked) {
      _draggingMarker = marker;
      _dragStartX = position.dx;
      _dragStartTime = marker.startTime;

      // Check if dragging end handle
      if (marker.endTime != null) {
        final endX = marker.endTime! * widget.zoom - widget.scrollOffset;
        _isDraggingEnd = (position.dx - endX).abs() < 10;
      }
    }
  }

  void _handleDragUpdate(Offset position) {
    if (_draggingMarker == null) return;

    final deltaX = position.dx - _dragStartX;
    final deltaTime = deltaX / widget.zoom;

    if (_isDraggingEnd && _draggingMarker!.endTime != null) {
      final newEnd = (_draggingMarker!.endTime! + deltaTime).clamp(
        _draggingMarker!.startTime + 0.1,
        double.infinity,
      );
      widget.onRegionResized?.call(_draggingMarker!, newEnd);
    } else {
      final newTime = (_dragStartTime + deltaTime).clamp(0.0, double.infinity);
      widget.onMarkerMoved?.call(_draggingMarker!, newTime);
    }

    _dragStartX = position.dx;
    if (!_isDraggingEnd) {
      _dragStartTime = _draggingMarker!.startTime;
    }
  }

  void _handleDragEnd() {
    _draggingMarker = null;
    _isDraggingEnd = false;
  }
}

class _MarkerTrackPainter extends CustomPainter {
  final List<TimelineMarker> markers;
  final double zoom;
  final double scrollOffset;
  final double? cycleStart;
  final double? cycleEnd;
  final TimelineMarker? hoveredMarker;
  final double height;

  _MarkerTrackPainter({
    required this.markers,
    required this.zoom,
    required this.scrollOffset,
    this.cycleStart,
    this.cycleEnd,
    this.hoveredMarker,
    required this.height,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw cycle region if active
    if (cycleStart != null && cycleEnd != null) {
      final startX = cycleStart! * zoom - scrollOffset;
      final endX = cycleEnd! * zoom - scrollOffset;

      final cyclePaint = Paint()
        ..color = FluxForgeTheme.accentGreen.withValues(alpha: 0.15);
      canvas.drawRect(Rect.fromLTRB(startX, 0, endX, size.height), cyclePaint);

      final cycleBorderPaint = Paint()
        ..color = FluxForgeTheme.accentGreen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawLine(Offset(startX, 0), Offset(startX, size.height), cycleBorderPaint);
      canvas.drawLine(Offset(endX, 0), Offset(endX, size.height), cycleBorderPaint);
    }

    // Draw arrangement regions first (background)
    for (final marker in markers.where((m) => m.type == MarkerType.arrangement)) {
      _drawArrangementRegion(canvas, size, marker);
    }

    // Draw cycle regions
    for (final marker in markers.where((m) => m.type == MarkerType.cycle)) {
      _drawCycleRegion(canvas, size, marker);
    }

    // Draw position markers last (on top)
    for (final marker in markers.where((m) => m.type == MarkerType.position)) {
      _drawPositionMarker(canvas, size, marker);
    }
  }

  void _drawPositionMarker(Canvas canvas, Size size, TimelineMarker marker) {
    final x = marker.startTime * zoom - scrollOffset;
    if (x < -20 || x > size.width + 20) return;

    final isHovered = hoveredMarker?.id == marker.id;
    final color = marker.color;

    // Draw flag
    final flagPath = Path()
      ..moveTo(x, 0)
      ..lineTo(x + 12, 6)
      ..lineTo(x, 12)
      ..close();

    final flagPaint = Paint()..color = color;
    canvas.drawPath(flagPath, flagPaint);

    // Draw line
    final linePaint = Paint()
      ..color = color.withValues(alpha: isHovered ? 1.0 : 0.7)
      ..strokeWidth = isHovered ? 2 : 1;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

    // Draw label
    if (marker.name.isNotEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: marker.name,
          style: TextStyle(
            color: Colors.white.withValues(alpha: isHovered ? 1.0 : 0.8),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, Offset(x + 4, 14));
    }
  }

  void _drawCycleRegion(Canvas canvas, Size size, TimelineMarker marker) {
    final startX = marker.startTime * zoom - scrollOffset;
    final endX = (marker.endTime ?? marker.startTime) * zoom - scrollOffset;
    if (endX < 0 || startX > size.width) return;

    final isHovered = hoveredMarker?.id == marker.id;
    final color = marker.color;

    // Draw region
    final regionPaint = Paint()
      ..color = color.withValues(alpha: isHovered ? 0.25 : 0.15);
    canvas.drawRect(
      Rect.fromLTRB(startX, size.height * 0.3, endX, size.height * 0.7),
      regionPaint,
    );

    // Draw borders
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = isHovered ? 2 : 1;
    canvas.drawRect(
      Rect.fromLTRB(startX, size.height * 0.3, endX, size.height * 0.7),
      borderPaint,
    );

    // Draw handles
    if (isHovered) {
      final handlePaint = Paint()..color = color;
      canvas.drawCircle(Offset(startX, size.height * 0.5), 4, handlePaint);
      canvas.drawCircle(Offset(endX, size.height * 0.5), 4, handlePaint);
    }

    // Draw label
    if (marker.name.isNotEmpty && endX - startX > 30) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: marker.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final textX = startX + 4;
      if (textX + textPainter.width < endX - 4) {
        textPainter.paint(canvas, Offset(textX, size.height * 0.35));
      }
    }
  }

  void _drawArrangementRegion(Canvas canvas, Size size, TimelineMarker marker) {
    final startX = marker.startTime * zoom - scrollOffset;
    final endX = (marker.endTime ?? marker.startTime) * zoom - scrollOffset;
    if (endX < 0 || startX > size.width) return;

    final isHovered = hoveredMarker?.id == marker.id;
    final color = marker.section?.color ?? marker.color;

    // Draw full-height region
    final regionPaint = Paint()
      ..color = color.withValues(alpha: isHovered ? 0.2 : 0.1);
    canvas.drawRect(Rect.fromLTRB(startX, 0, endX, size.height), regionPaint);

    // Draw top bar
    final barPaint = Paint()..color = color;
    canvas.drawRect(Rect.fromLTRB(startX, 0, endX, 4), barPaint);

    // Draw borders
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(Offset(startX, 0), Offset(startX, size.height), borderPaint);
    canvas.drawLine(Offset(endX, 0), Offset(endX, size.height), borderPaint);

    // Draw label
    final label = marker.section?.label ?? marker.name;
    if (label.isNotEmpty && endX - startX > 40) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: label.toUpperCase(),
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final textX = startX + (endX - startX - textPainter.width) / 2;
      textPainter.paint(canvas, Offset(textX, size.height / 2 - 5));
    }
  }

  @override
  bool shouldRepaint(covariant _MarkerTrackPainter oldDelegate) {
    return markers != oldDelegate.markers ||
        zoom != oldDelegate.zoom ||
        scrollOffset != oldDelegate.scrollOffset ||
        cycleStart != oldDelegate.cycleStart ||
        cycleEnd != oldDelegate.cycleEnd ||
        hoveredMarker != oldDelegate.hoveredMarker;
  }
}
