/// FluxForge Studio Container Timeline Zoom
///
/// P2-MW-2: Zoom and pan for sequence container timelines
/// - Zoom in/out with mouse wheel
/// - Pan with drag
/// - Visual step editing with drag handles
/// - Snap to grid
library;

import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../models/middleware_models.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TIMELINE ZOOM CONTROLLER
// ═══════════════════════════════════════════════════════════════════════════════

/// Controller for timeline zoom and pan state
class TimelineZoomController extends ChangeNotifier {
  double _zoom = 1.0;
  double _panOffset = 0.0;
  int? _snapGridMs;

  /// Current zoom level (1.0 = 100%)
  double get zoom => _zoom;

  /// Current pan offset in milliseconds
  double get panOffset => _panOffset;

  /// Snap grid interval in ms (null = no snap)
  int? get snapGridMs => _snapGridMs;

  /// Set zoom level (clamped 0.1 to 10.0)
  void setZoom(double value) {
    _zoom = value.clamp(0.1, 10.0);
    notifyListeners();
  }

  /// Zoom in by factor
  void zoomIn([double factor = 1.2]) {
    setZoom(_zoom * factor);
  }

  /// Zoom out by factor
  void zoomOut([double factor = 1.2]) {
    setZoom(_zoom / factor);
  }

  /// Reset to default zoom
  void resetZoom() {
    _zoom = 1.0;
    _panOffset = 0.0;
    notifyListeners();
  }

  /// Set pan offset
  void setPanOffset(double value) {
    _panOffset = math.max(0.0, value);
    notifyListeners();
  }

  /// Pan by delta
  void pan(double deltaMs) {
    setPanOffset(_panOffset + deltaMs);
  }

  /// Set snap grid
  void setSnapGrid(int? ms) {
    _snapGridMs = ms;
    notifyListeners();
  }

  /// Snap value to grid
  double snapToGrid(double value) {
    if (_snapGridMs == null || _snapGridMs! <= 0) return value;
    return (value / _snapGridMs!).round() * _snapGridMs!.toDouble();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Zoomable and pannable sequence timeline
class ContainerTimelineZoom extends StatefulWidget {
  final SequenceContainer container;
  final TimelineZoomController? controller;
  final Function(int stepIndex, double newDelayMs)? onStepDelayChanged;
  final Function(int stepIndex, double newDurationMs)? onStepDurationChanged;
  final int? selectedStepIndex;
  final Function(int? stepIndex)? onStepSelected;

  const ContainerTimelineZoom({
    super.key,
    required this.container,
    this.controller,
    this.onStepDelayChanged,
    this.onStepDurationChanged,
    this.selectedStepIndex,
    this.onStepSelected,
  });

  @override
  State<ContainerTimelineZoom> createState() => _ContainerTimelineZoomState();
}

class _ContainerTimelineZoomState extends State<ContainerTimelineZoom> {
  late TimelineZoomController _controller;
  bool _ownsController = false;
  int? _draggingStepIndex;
  _DragHandle? _dragHandle;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TimelineZoomController();
      _ownsController = true;
    }
    _controller.addListener(_rebuild);
  }

  @override
  void dispose() {
    _controller.removeListener(_rebuild);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  double get _totalDurationMs {
    double max = 0;
    for (final step in widget.container.steps) {
      final end = step.delayMs + step.durationMs;
      if (end > max) max = end;
    }
    return max > 0 ? max + 200 : 1000; // Add padding
  }

  double _msToPixels(double ms, double width) {
    return (ms - _controller.panOffset) * _controller.zoom * (width / 1000);
  }

  double _pixelsToMs(double pixels, double width) {
    return (pixels / (width / 1000) / _controller.zoom) + _controller.panOffset;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildToolbar(),
          Expanded(child: _buildTimeline()),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surfaceDark,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.border)),
      ),
      child: Row(
        children: [
          // Zoom controls
          _buildToolbarButton(Icons.zoom_out, () => _controller.zoomOut()),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${(_controller.zoom * 100).toInt()}%',
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _buildToolbarButton(Icons.zoom_in, () => _controller.zoomIn()),
          const SizedBox(width: 8),
          _buildToolbarButton(Icons.fit_screen, () => _controller.resetZoom()),
          const Spacer(),
          // Snap grid
          Text('Snap:', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10)),
          const SizedBox(width: 6),
          _buildSnapDropdown(),
          const SizedBox(width: 8),
          // Duration display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.teal.withValues(alpha: 0.5)),
            ),
            child: Text(
              '${_totalDurationMs.toStringAsFixed(0)}ms',
              style: const TextStyle(
                color: Colors.teal,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.border),
        ),
        child: Icon(icon, size: 14, color: FluxForgeTheme.textSecondary),
      ),
    );
  }

  Widget _buildSnapDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _controller.snapGridMs,
          isDense: true,
          dropdownColor: FluxForgeTheme.surfaceDark,
          style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 10),
          icon: Icon(Icons.arrow_drop_down,
              size: 14, color: FluxForgeTheme.textSecondary),
          items: const [
            DropdownMenuItem(value: null, child: Text('Off')),
            DropdownMenuItem(value: 10, child: Text('10ms')),
            DropdownMenuItem(value: 25, child: Text('25ms')),
            DropdownMenuItem(value: 50, child: Text('50ms')),
            DropdownMenuItem(value: 100, child: Text('100ms')),
          ],
          onChanged: (v) => _controller.setSnapGrid(v),
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              // Zoom with scroll wheel
              if (event.scrollDelta.dy < 0) {
                _controller.zoomIn(1.1);
              } else {
                _controller.zoomOut(1.1);
              }
            }
          },
          child: GestureDetector(
            onPanUpdate: (details) {
              // Pan with drag (when not dragging a step)
              if (_draggingStepIndex == null) {
                _controller.pan(-_pixelsToMs(details.delta.dx, width) +
                    _controller.panOffset);
              }
            },
            child: CustomPaint(
              size: Size(width, height),
              painter: _TimelinePainter(
                container: widget.container,
                controller: _controller,
                selectedStepIndex: widget.selectedStepIndex,
                draggingStepIndex: _draggingStepIndex,
              ),
              child: Stack(
                children: [
                  // Step drag handles
                  ...widget.container.steps.asMap().entries.map(
                        (entry) => _buildStepHandles(entry.key, entry.value, width, height),
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStepHandles(int index, SequenceStep step, double width, double height) {
    final startX = _msToPixels(step.delayMs, width);
    final endX = _msToPixels(step.delayMs + step.durationMs, width);
    final trackHeight = 40.0;
    final trackY = 40.0 + index * (trackHeight + 8);

    if (startX > width || endX < 0) return const SizedBox.shrink();

    return Stack(
      children: [
        // Main block (tap to select)
        Positioned(
          left: startX.clamp(0.0, width - 10),
          top: trackY,
          width: (endX - startX).clamp(10.0, width),
          height: trackHeight,
          child: GestureDetector(
            onTap: () => widget.onStepSelected?.call(index),
            child: Container(color: Colors.transparent),
          ),
        ),
        // Left handle (delay)
        Positioned(
          left: startX - 4,
          top: trackY,
          width: 8,
          height: trackHeight,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              onPanStart: (_) {
                setState(() {
                  _draggingStepIndex = index;
                  _dragHandle = _DragHandle.start;
                });
              },
              onPanUpdate: (details) {
                if (_dragHandle == _DragHandle.start) {
                  final newDelay = _controller.snapToGrid(
                    _pixelsToMs(startX + details.delta.dx, width),
                  );
                  widget.onStepDelayChanged?.call(index, math.max(0, newDelay));
                }
              },
              onPanEnd: (_) {
                setState(() {
                  _draggingStepIndex = null;
                  _dragHandle = null;
                });
              },
              child: Container(color: Colors.transparent),
            ),
          ),
        ),
        // Right handle (duration)
        Positioned(
          left: endX - 4,
          top: trackY,
          width: 8,
          height: trackHeight,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              onPanStart: (_) {
                setState(() {
                  _draggingStepIndex = index;
                  _dragHandle = _DragHandle.end;
                });
              },
              onPanUpdate: (details) {
                if (_dragHandle == _DragHandle.end) {
                  final newEnd = _controller.snapToGrid(
                    _pixelsToMs(endX + details.delta.dx, width),
                  );
                  final newDuration = newEnd - step.delayMs;
                  widget.onStepDurationChanged?.call(index, math.max(10, newDuration));
                }
              },
              onPanEnd: (_) {
                setState(() {
                  _draggingStepIndex = null;
                  _dragHandle = null;
                });
              },
              child: Container(color: Colors.transparent),
            ),
          ),
        ),
      ],
    );
  }
}

enum _DragHandle { start, end }

// ═══════════════════════════════════════════════════════════════════════════════
// PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _TimelinePainter extends CustomPainter {
  final SequenceContainer container;
  final TimelineZoomController controller;
  final int? selectedStepIndex;
  final int? draggingStepIndex;

  _TimelinePainter({
    required this.container,
    required this.controller,
    this.selectedStepIndex,
    this.draggingStepIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawSteps(canvas, size);
    _drawTimeRuler(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FluxForgeTheme.border.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Determine grid interval based on zoom
    int gridIntervalMs = 100;
    if (controller.zoom > 2) gridIntervalMs = 50;
    if (controller.zoom > 5) gridIntervalMs = 25;
    if (controller.zoom < 0.5) gridIntervalMs = 200;
    if (controller.zoom < 0.25) gridIntervalMs = 500;

    // Draw vertical grid lines
    for (double ms = 0; ms < 10000; ms += gridIntervalMs) {
      final x = _msToPixels(ms, size.width);
      if (x < 0) continue;
      if (x > size.width) break;
      canvas.drawLine(Offset(x, 30), Offset(x, size.height), paint);
    }
  }

  void _drawTimeRuler(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = FluxForgeTheme.surfaceDark;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 30), bgPaint);

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Determine label interval
    int labelIntervalMs = 200;
    if (controller.zoom > 2) labelIntervalMs = 100;
    if (controller.zoom < 0.5) labelIntervalMs = 500;

    for (double ms = 0; ms < 10000; ms += labelIntervalMs) {
      final x = _msToPixels(ms, size.width);
      if (x < 0) continue;
      if (x > size.width) break;

      textPainter.text = TextSpan(
        text: '${ms.toInt()}ms',
        style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 9),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, 8));

      // Tick mark
      final tickPaint = Paint()
        ..color = FluxForgeTheme.textSecondary
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, 24), Offset(x, 30), tickPaint);
    }
  }

  void _drawSteps(Canvas canvas, Size size) {
    final trackHeight = 40.0;
    final trackY = 40.0;

    for (int i = 0; i < container.steps.length; i++) {
      final step = container.steps[i];
      final startX = _msToPixels(step.delayMs, size.width);
      final endX = _msToPixels(step.delayMs + step.durationMs, size.width);
      final y = trackY + i * (trackHeight + 8);

      // Skip if off-screen
      if (endX < 0 || startX > size.width) continue;

      final isSelected = selectedStepIndex == i;
      final isDragging = draggingStepIndex == i;

      // Step background
      final color = Colors.teal;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          startX.clamp(0.0, size.width),
          y,
          endX.clamp(0.0, size.width),
          y + trackHeight,
        ),
        const Radius.circular(4),
      );

      final fillPaint = Paint()
        ..color = color.withValues(alpha: isSelected ? 0.5 : 0.3);
      canvas.drawRRect(rect, fillPaint);

      final borderPaint = Paint()
        ..color = isSelected || isDragging ? color : color.withValues(alpha: 0.5)
        ..strokeWidth = isSelected ? 2 : 1
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(rect, borderPaint);

      // Step label
      if (endX - startX > 40) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: step.childName,
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(maxWidth: endX - startX - 8);
        textPainter.paint(canvas, Offset(startX + 4, y + 6));

        // Duration
        final durationPainter = TextPainter(
          text: TextSpan(
            text: '${step.durationMs.toInt()}ms',
            style: TextStyle(color: color, fontSize: 9),
          ),
          textDirection: TextDirection.ltr,
        );
        durationPainter.layout();
        durationPainter.paint(canvas, Offset(startX + 4, y + trackHeight - 14));
      }

      // Resize handles
      if (isSelected) {
        final handlePaint = Paint()..color = color;
        canvas.drawCircle(Offset(startX, y + trackHeight / 2), 4, handlePaint);
        canvas.drawCircle(Offset(endX, y + trackHeight / 2), 4, handlePaint);
      }
    }
  }

  double _msToPixels(double ms, double width) {
    return (ms - controller.panOffset) * controller.zoom * (width / 1000);
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.container != container ||
        oldDelegate.controller.zoom != controller.zoom ||
        oldDelegate.controller.panOffset != controller.panOffset ||
        oldDelegate.selectedStepIndex != selectedStepIndex ||
        oldDelegate.draggingStepIndex != draggingStepIndex;
  }
}
