/// Tempo Track Widget
///
/// Professional tempo track with:
/// - Tempo changes visualization
/// - Time signature changes
/// - Tempo ramps (gradual/instant)
/// - Click points for tempo editing
/// - Visual tempo curve
/// - BPM display

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../theme/reelforge_theme.dart';

/// Tempo change point
class TempoPoint {
  final String id;
  final double time; // In seconds
  final double bpm;
  final TempoRampType rampType;
  final int timeSignatureNum;
  final int timeSignatureDenom;

  const TempoPoint({
    required this.id,
    required this.time,
    required this.bpm,
    this.rampType = TempoRampType.instant,
    this.timeSignatureNum = 4,
    this.timeSignatureDenom = 4,
  });

  TempoPoint copyWith({
    String? id,
    double? time,
    double? bpm,
    TempoRampType? rampType,
    int? timeSignatureNum,
    int? timeSignatureDenom,
  }) {
    return TempoPoint(
      id: id ?? this.id,
      time: time ?? this.time,
      bpm: bpm ?? this.bpm,
      rampType: rampType ?? this.rampType,
      timeSignatureNum: timeSignatureNum ?? this.timeSignatureNum,
      timeSignatureDenom: timeSignatureDenom ?? this.timeSignatureDenom,
    );
  }
}

/// Type of tempo ramp
enum TempoRampType {
  instant, // Jump to new tempo
  linear, // Linear ramp
  sCurve, // S-curve (smooth)
}

/// Tempo track widget
class TempoTrack extends StatefulWidget {
  final List<TempoPoint> tempoPoints;
  final double zoom;
  final double scrollOffset;
  final double height;
  final bool isExpanded;
  final ValueChanged<TempoPoint>? onTempoPointAdd;
  final void Function(String id, TempoPoint newPoint)? onTempoPointChange;
  final ValueChanged<String>? onTempoPointDelete;
  final VoidCallback? onToggleExpanded;
  final double playheadPosition;

  const TempoTrack({
    super.key,
    required this.tempoPoints,
    required this.zoom,
    required this.scrollOffset,
    this.height = 80,
    this.isExpanded = true,
    this.onTempoPointAdd,
    this.onTempoPointChange,
    this.onTempoPointDelete,
    this.onToggleExpanded,
    this.playheadPosition = 0,
  });

  @override
  State<TempoTrack> createState() => _TempoTrackState();
}

class _TempoTrackState extends State<TempoTrack> {
  String? _hoveredPointId;
  String? _draggingPointId;
  Offset? _lastDragPosition;

  double get _minBpm => 20;
  double get _maxBpm => 300;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        _buildHeader(),
        // Track content
        if (widget.isExpanded)
          Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgDeep,
              border: const Border(
                bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
              ),
            ),
            child: ClipRect(
              child: CustomPaint(
                painter: _TempoTrackPainter(
                  tempoPoints: widget.tempoPoints,
                  zoom: widget.zoom,
                  scrollOffset: widget.scrollOffset,
                  minBpm: _minBpm,
                  maxBpm: _maxBpm,
                  hoveredPointId: _hoveredPointId,
                  draggingPointId: _draggingPointId,
                  playheadPosition: widget.playheadPosition,
                ),
                child: GestureDetector(
                  onTapDown: _handleTap,
                  onDoubleTapDown: _handleDoubleTap,
                  child: MouseRegion(
                    onHover: _handleHover,
                    onExit: (_) => setState(() => _hoveredPointId = null),
                    child: Listener(
                      onPointerSignal: _handleScroll,
                      child: _buildPointHandles(),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader() {
    // Get current tempo at playhead
    final currentTempo = _getTempoAtTime(widget.playheadPosition);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        border: const Border(
          bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onToggleExpanded,
            child: Icon(
              widget.isExpanded ? Icons.expand_more : Icons.chevron_right,
              size: 18,
              color: Colors.white54,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.speed, size: 14, color: ReelForgeTheme.accentOrange),
          const SizedBox(width: 6),
          const Text(
            'Tempo',
            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          // Current BPM display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: ReelForgeTheme.accentOrange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${currentTempo.toStringAsFixed(1)} BPM',
              style: const TextStyle(
                color: ReelForgeTheme.accentOrange,
                fontSize: 11,
                fontFamily: 'JetBrains Mono',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Spacer(),
          Text(
            '${widget.tempoPoints.length} points',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildPointHandles() {
    return Stack(
      children: widget.tempoPoints.map((point) {
        final x = (point.time - widget.scrollOffset) * widget.zoom;
        if (x < -20 || x > MediaQuery.of(context).size.width + 20) {
          return const SizedBox.shrink();
        }

        final y = widget.height - ((point.bpm - _minBpm) / (_maxBpm - _minBpm)) * widget.height;
        final isHovered = _hoveredPointId == point.id;
        final isDragging = _draggingPointId == point.id;

        return Positioned(
          left: x - 6,
          top: y - 6,
          child: GestureDetector(
            onPanStart: (details) {
              setState(() => _draggingPointId = point.id);
              _lastDragPosition = details.globalPosition;
            },
            onPanUpdate: (details) {
              if (_draggingPointId == point.id) {
                final delta = details.globalPosition - _lastDragPosition!;
                _lastDragPosition = details.globalPosition;

                // Update tempo point
                final newTime = (point.time + delta.dx / widget.zoom).clamp(0.0, double.infinity);
                final bpmDelta = -delta.dy / widget.height * (_maxBpm - _minBpm);
                final newBpm = (point.bpm + bpmDelta).clamp(_minBpm, _maxBpm);

                widget.onTempoPointChange?.call(point.id, point.copyWith(
                  time: newTime,
                  bpm: newBpm,
                ));
              }
            },
            onPanEnd: (_) => setState(() => _draggingPointId = null),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isHovered || isDragging
                    ? ReelForgeTheme.accentOrange
                    : ReelForgeTheme.accentOrange.withValues(alpha: 0.8),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: isHovered || isDragging ? 2 : 1,
                ),
                boxShadow: isHovered || isDragging
                    ? [BoxShadow(color: ReelForgeTheme.accentOrange.withValues(alpha: 0.5), blurRadius: 8)]
                    : null,
              ),
              child: isDragging
                  ? const Icon(Icons.drag_indicator, size: 8, color: Colors.white)
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }

  void _handleTap(TapDownDetails details) {
    // Check if tapped on a point
    for (final point in widget.tempoPoints) {
      final x = (point.time - widget.scrollOffset) * widget.zoom;
      final y = widget.height - ((point.bpm - _minBpm) / (_maxBpm - _minBpm)) * widget.height;
      final distance = (Offset(x, y) - details.localPosition).distance;
      if (distance < 12) {
        // Show edit dialog
        _showEditDialog(point);
        return;
      }
    }
  }

  void _handleDoubleTap(TapDownDetails details) {
    // Add new tempo point
    final time = details.localPosition.dx / widget.zoom + widget.scrollOffset;
    final bpm = _maxBpm - (details.localPosition.dy / widget.height) * (_maxBpm - _minBpm);

    final newPoint = TempoPoint(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      time: time,
      bpm: bpm.clamp(_minBpm, _maxBpm),
    );
    widget.onTempoPointAdd?.call(newPoint);
  }

  void _handleHover(PointerHoverEvent event) {
    // Find hovered point
    String? hovered;
    for (final point in widget.tempoPoints) {
      final x = (point.time - widget.scrollOffset) * widget.zoom;
      final y = widget.height - ((point.bpm - _minBpm) / (_maxBpm - _minBpm)) * widget.height;
      final distance = (Offset(x, y) - event.localPosition).distance;
      if (distance < 12) {
        hovered = point.id;
        break;
      }
    }
    if (hovered != _hoveredPointId) {
      setState(() => _hoveredPointId = hovered);
    }
  }

  void _handleScroll(PointerSignalEvent event) {
    if (event is PointerScrollEvent && _hoveredPointId != null) {
      // Scroll to adjust BPM of hovered point
      final point = widget.tempoPoints.firstWhere((p) => p.id == _hoveredPointId);
      final bpmDelta = event.scrollDelta.dy > 0 ? -1.0 : 1.0;
      final newBpm = (point.bpm + bpmDelta).clamp(_minBpm, _maxBpm);
      widget.onTempoPointChange?.call(point.id, point.copyWith(bpm: newBpm));
    }
  }

  void _showEditDialog(TempoPoint point) {
    final bpmController = TextEditingController(text: point.bpm.toStringAsFixed(1));
    var selectedRampType = point.rampType;
    var tsNum = point.timeSignatureNum;
    var tsDenom = point.timeSignatureDenom;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: ReelForgeTheme.bgMid,
          title: const Text('Edit Tempo Point', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // BPM
              TextField(
                controller: bpmController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'BPM',
                  labelStyle: TextStyle(color: Colors.white54),
                  suffixText: 'BPM',
                ),
              ),
              const SizedBox(height: 16),
              // Ramp type
              const Text('Ramp Type', style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: TempoRampType.values.map((type) {
                  final isSelected = selectedRampType == type;
                  return ChoiceChip(
                    label: Text(_getRampTypeName(type)),
                    selected: isSelected,
                    onSelected: (_) => setDialogState(() => selectedRampType = type),
                    backgroundColor: ReelForgeTheme.bgDeep,
                    selectedColor: ReelForgeTheme.accentOrange,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 11,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              // Time signature
              const Text('Time Signature', style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  DropdownButton<int>(
                    value: tsNum,
                    dropdownColor: ReelForgeTheme.bgMid,
                    style: const TextStyle(color: Colors.white),
                    items: [2, 3, 4, 5, 6, 7, 8, 9, 12].map((n) {
                      return DropdownMenuItem(value: n, child: Text('$n'));
                    }).toList(),
                    onChanged: (v) => setDialogState(() => tsNum = v ?? 4),
                  ),
                  const Text(' / ', style: TextStyle(color: Colors.white, fontSize: 16)),
                  DropdownButton<int>(
                    value: tsDenom,
                    dropdownColor: ReelForgeTheme.bgMid,
                    style: const TextStyle(color: Colors.white),
                    items: [2, 4, 8, 16].map((n) {
                      return DropdownMenuItem(value: n, child: Text('$n'));
                    }).toList(),
                    onChanged: (v) => setDialogState(() => tsDenom = v ?? 4),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                widget.onTempoPointDelete?.call(point.id);
                Navigator.pop(ctx);
              },
              child: const Text('Delete', style: TextStyle(color: ReelForgeTheme.accentRed)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newBpm = double.tryParse(bpmController.text) ?? point.bpm;
                widget.onTempoPointChange?.call(point.id, point.copyWith(
                  bpm: newBpm.clamp(_minBpm, _maxBpm),
                  rampType: selectedRampType,
                  timeSignatureNum: tsNum,
                  timeSignatureDenom: tsDenom,
                ));
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: ReelForgeTheme.accentOrange),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  double _getTempoAtTime(double time) {
    if (widget.tempoPoints.isEmpty) return 120;
    final sorted = List<TempoPoint>.from(widget.tempoPoints)..sort((a, b) => a.time.compareTo(b.time));

    // Find surrounding points
    TempoPoint? before;
    TempoPoint? after;
    for (final p in sorted) {
      if (p.time <= time) {
        before = p;
      } else {
        after = p;
        break;
      }
    }

    if (before == null) return sorted.first.bpm;
    if (after == null) return before.bpm;

    // Interpolate based on ramp type
    final t = (time - before.time) / (after.time - before.time);
    switch (before.rampType) {
      case TempoRampType.instant:
        return before.bpm;
      case TempoRampType.linear:
        return before.bpm + (after.bpm - before.bpm) * t;
      case TempoRampType.sCurve:
        final smoothT = t * t * (3 - 2 * t);
        return before.bpm + (after.bpm - before.bpm) * smoothT;
    }
  }

  String _getRampTypeName(TempoRampType type) {
    switch (type) {
      case TempoRampType.instant:
        return 'Instant';
      case TempoRampType.linear:
        return 'Linear';
      case TempoRampType.sCurve:
        return 'S-Curve';
    }
  }
}

/// Painter for tempo track
class _TempoTrackPainter extends CustomPainter {
  final List<TempoPoint> tempoPoints;
  final double zoom;
  final double scrollOffset;
  final double minBpm;
  final double maxBpm;
  final String? hoveredPointId;
  final String? draggingPointId;
  final double playheadPosition;

  _TempoTrackPainter({
    required this.tempoPoints,
    required this.zoom,
    required this.scrollOffset,
    required this.minBpm,
    required this.maxBpm,
    this.hoveredPointId,
    this.draggingPointId,
    required this.playheadPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background grid
    _drawGrid(canvas, size);

    // Tempo curve
    _drawTempoCurve(canvas, size);

    // BPM labels on right side
    _drawBpmLabels(canvas, size);

    // Playhead position indicator
    _drawPlayhead(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    // Horizontal lines (BPM levels)
    for (var bpm = minBpm; bpm <= maxBpm; bpm += 20) {
      final y = size.height - ((bpm - minBpm) / (maxBpm - minBpm)) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawTempoCurve(Canvas canvas, Size size) {
    if (tempoPoints.isEmpty) return;

    final sorted = List<TempoPoint>.from(tempoPoints)..sort((a, b) => a.time.compareTo(b.time));

    // Draw tempo regions
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          ReelForgeTheme.accentOrange.withValues(alpha: 0.3),
          ReelForgeTheme.accentOrange.withValues(alpha: 0.05),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = ReelForgeTheme.accentOrange
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < sorted.length; i++) {
      final point = sorted[i];
      final x = (point.time - scrollOffset) * zoom;
      final y = size.height - ((point.bpm - minBpm) / (maxBpm - minBpm)) * size.height;

      if (i == 0) {
        // Draw from start
        final startY = size.height - ((point.bpm - minBpm) / (maxBpm - minBpm)) * size.height;
        final startX = -scrollOffset * zoom;
        path.moveTo(startX, startY);
        path.lineTo(x, y);
        fillPath.moveTo(startX, size.height);
        fillPath.lineTo(startX, startY);
        fillPath.lineTo(x, y);
      } else {
        final prevPoint = sorted[i - 1];
        final prevX = (prevPoint.time - scrollOffset) * zoom;
        final prevY = size.height - ((prevPoint.bpm - minBpm) / (maxBpm - minBpm)) * size.height;

        switch (prevPoint.rampType) {
          case TempoRampType.instant:
            path.lineTo(x, prevY);
            path.lineTo(x, y);
            fillPath.lineTo(x, prevY);
            fillPath.lineTo(x, y);
            break;
          case TempoRampType.linear:
            path.lineTo(x, y);
            fillPath.lineTo(x, y);
            break;
          case TempoRampType.sCurve:
            // S-curve with bezier
            final midX = (prevX + x) / 2;
            path.cubicTo(midX, prevY, midX, y, x, y);
            fillPath.cubicTo(midX, prevY, midX, y, x, y);
            break;
        }
      }
    }

    // Extend to end of visible area
    final lastPoint = sorted.last;
    final lastX = (lastPoint.time - scrollOffset) * zoom;
    final lastY = size.height - ((lastPoint.bpm - minBpm) / (maxBpm - minBpm)) * size.height;
    path.lineTo(size.width, lastY);
    fillPath.lineTo(size.width, lastY);
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  void _drawBpmLabels(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (var bpm = minBpm; bpm <= maxBpm; bpm += 40) {
      final y = size.height - ((bpm - minBpm) / (maxBpm - minBpm)) * size.height;

      textPainter.text = TextSpan(
        text: '${bpm.round()}',
        style: const TextStyle(
          color: Colors.white24,
          fontSize: 9,
          fontFamily: 'JetBrains Mono',
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(size.width - textPainter.width - 4, y - textPainter.height / 2));
    }
  }

  void _drawPlayhead(Canvas canvas, Size size) {
    final x = (playheadPosition - scrollOffset) * zoom;
    if (x < 0 || x > size.width) return;

    // Get tempo at playhead
    final bpm = _getTempoAtPlayhead();
    final y = size.height - ((bpm - minBpm) / (maxBpm - minBpm)) * size.height;

    // Draw vertical line
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);

    // Draw tempo indicator
    canvas.drawCircle(
      Offset(x, y),
      4,
      Paint()..color = Colors.white,
    );
  }

  double _getTempoAtPlayhead() {
    if (tempoPoints.isEmpty) return 120;
    final sorted = List<TempoPoint>.from(tempoPoints)..sort((a, b) => a.time.compareTo(b.time));

    TempoPoint? before;
    TempoPoint? after;
    for (final p in sorted) {
      if (p.time <= playheadPosition) {
        before = p;
      } else {
        after = p;
        break;
      }
    }

    if (before == null) return sorted.first.bpm;
    if (after == null) return before.bpm;

    final t = (playheadPosition - before.time) / (after.time - before.time);
    switch (before.rampType) {
      case TempoRampType.instant:
        return before.bpm;
      case TempoRampType.linear:
        return before.bpm + (after.bpm - before.bpm) * t;
      case TempoRampType.sCurve:
        final smoothT = t * t * (3 - 2 * t);
        return before.bpm + (after.bpm - before.bpm) * smoothT;
    }
  }

  @override
  bool shouldRepaint(_TempoTrackPainter oldDelegate) =>
      tempoPoints != oldDelegate.tempoPoints ||
      zoom != oldDelegate.zoom ||
      scrollOffset != oldDelegate.scrollOffset ||
      hoveredPointId != oldDelegate.hoveredPointId ||
      draggingPointId != oldDelegate.draggingPointId ||
      playheadPosition != oldDelegate.playheadPosition;
}
