/// Stage Timing Editor Widget (P12.1.15)
///
/// Visual timing adjustment for stage events.
/// Features:
/// - Delay adjustment per stage
/// - Grid snapping (off, 10ms, 50ms, 100ms, 250ms)
/// - Visual timeline representation
/// - Drag handles for precise timing
library;

import 'package:flutter/material.dart';

// =============================================================================
// STAGE TIMING MODEL
// =============================================================================

/// Stage timing configuration
class StageTiming {
  final String stageId;
  final String stageName;
  final double baseTimeMs;    // Base timing from engine
  final double delayMs;       // User-adjustable delay
  final double durationMs;    // Duration of stage audio
  final Color color;

  const StageTiming({
    required this.stageId,
    required this.stageName,
    required this.baseTimeMs,
    this.delayMs = 0,
    this.durationMs = 100,
    this.color = const Color(0xFF4A9EFF),
  });

  double get totalTimeMs => baseTimeMs + delayMs;

  StageTiming copyWith({
    String? stageId,
    String? stageName,
    double? baseTimeMs,
    double? delayMs,
    double? durationMs,
    Color? color,
  }) {
    return StageTiming(
      stageId: stageId ?? this.stageId,
      stageName: stageName ?? this.stageName,
      baseTimeMs: baseTimeMs ?? this.baseTimeMs,
      delayMs: delayMs ?? this.delayMs,
      durationMs: durationMs ?? this.durationMs,
      color: color ?? this.color,
    );
  }
}

/// Grid snap options
enum GridSnap {
  off(0),
  ms10(10),
  ms50(50),
  ms100(100),
  ms250(250);

  final double valueMs;
  const GridSnap(this.valueMs);

  String get label => switch (this) {
    GridSnap.off => 'Off',
    GridSnap.ms10 => '10ms',
    GridSnap.ms50 => '50ms',
    GridSnap.ms100 => '100ms',
    GridSnap.ms250 => '250ms',
  };
}

// =============================================================================
// STAGE TIMING EDITOR WIDGET
// =============================================================================

class StageTimingEditor extends StatefulWidget {
  final List<StageTiming> stages;
  final void Function(String stageId, double newDelayMs)? onDelayChanged;
  final String? selectedStageId;
  final void Function(String stageId)? onStageSelected;
  final double pixelsPerMs;
  final double timelineWidthMs;

  const StageTimingEditor({
    super.key,
    required this.stages,
    this.onDelayChanged,
    this.selectedStageId,
    this.onStageSelected,
    this.pixelsPerMs = 0.2,
    this.timelineWidthMs = 5000,
  });

  @override
  State<StageTimingEditor> createState() => _StageTimingEditorState();
}

class _StageTimingEditorState extends State<StageTimingEditor> {
  GridSnap _gridSnap = GridSnap.ms50;
  double _scrollOffset = 0;
  String? _draggingStageId;
  double _dragStartDelayMs = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        const Divider(height: 1),
        Expanded(child: _buildTimelineView()),
        const Divider(height: 1),
        _buildStageList(),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: const Color(0xFF1a1a20),
      child: Row(
        children: [
          const Icon(Icons.timer, size: 16, color: Color(0xFF40FF90)),
          const SizedBox(width: 8),
          const Text(
            'Stage Timing',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          // Grid snap selector
          const Text('Snap: ', style: TextStyle(fontSize: 10)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF242430),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButton<GridSnap>(
              value: _gridSnap,
              underline: const SizedBox(),
              isDense: true,
              style: const TextStyle(fontSize: 10, color: Colors.white),
              dropdownColor: const Color(0xFF242430),
              items: GridSnap.values.map((snap) => DropdownMenuItem(
                value: snap,
                child: Text(snap.label),
              )).toList(),
              onChanged: (value) {
                if (value != null) setState(() => _gridSnap = value);
              },
            ),
          ),
          const SizedBox(width: 8),
          // Reset all delays
          IconButton(
            icon: const Icon(Icons.restart_alt, size: 16),
            onPressed: _resetAllDelays,
            tooltip: 'Reset all delays',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = widget.timelineWidthMs * widget.pixelsPerMs;

        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              _scrollOffset = (_scrollOffset - details.delta.dx)
                  .clamp(0.0, totalWidth - constraints.maxWidth);
            });
          },
          child: ClipRect(
            child: CustomPaint(
              painter: _TimelinePainter(
                stages: widget.stages,
                pixelsPerMs: widget.pixelsPerMs,
                scrollOffset: _scrollOffset,
                gridSnap: _gridSnap,
                selectedStageId: widget.selectedStageId,
                viewWidth: constraints.maxWidth,
              ),
              child: Stack(
                children: widget.stages.map((stage) {
                  return _buildDraggableStage(stage, constraints.maxWidth);
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDraggableStage(StageTiming stage, double viewWidth) {
    final left = stage.totalTimeMs * widget.pixelsPerMs - _scrollOffset;
    final width = stage.durationMs * widget.pixelsPerMs;
    final isSelected = stage.stageId == widget.selectedStageId;

    // Skip if out of view
    if (left + width < 0 || left > viewWidth) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: left.clamp(0.0, viewWidth - 10),
      top: 10,
      child: GestureDetector(
        onTap: () => widget.onStageSelected?.call(stage.stageId),
        onHorizontalDragStart: (details) {
          setState(() {
            _draggingStageId = stage.stageId;
            _dragStartDelayMs = stage.delayMs;
          });
        },
        onHorizontalDragUpdate: (details) {
          if (_draggingStageId == stage.stageId) {
            final deltaPx = details.delta.dx;
            final deltaMs = deltaPx / widget.pixelsPerMs;
            var newDelay = _dragStartDelayMs + deltaMs;

            // Apply grid snapping
            if (_gridSnap != GridSnap.off) {
              newDelay = (newDelay / _gridSnap.valueMs).round() * _gridSnap.valueMs;
            }

            // Clamp to valid range
            newDelay = newDelay.clamp(-stage.baseTimeMs, widget.timelineWidthMs - stage.baseTimeMs);

            widget.onDelayChanged?.call(stage.stageId, newDelay);
          }
        },
        onHorizontalDragEnd: (_) {
          setState(() => _draggingStageId = null);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: width.clamp(20.0, 200.0),
          height: 24,
          decoration: BoxDecoration(
            color: stage.color.withValues(alpha: isSelected ? 0.9 : 0.7),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? Colors.white : stage.color,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: _draggingStageId == stage.stageId
                ? [BoxShadow(color: stage.color.withValues(alpha: 0.5), blurRadius: 8)]
                : null,
          ),
          child: Center(
            child: Text(
              stage.stageName,
              style: const TextStyle(fontSize: 9, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStageList() {
    return Container(
      height: 120,
      color: const Color(0xFF0a0a0c),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: widget.stages.length,
        itemBuilder: (context, index) {
          final stage = widget.stages[index];
          final isSelected = stage.stageId == widget.selectedStageId;

          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? stage.color.withValues(alpha: 0.15) : const Color(0xFF1a1a20),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? stage.color : const Color(0xFF333340),
              ),
            ),
            child: Row(
              children: [
                // Color indicator
                Container(
                  width: 3,
                  height: 20,
                  decoration: BoxDecoration(
                    color: stage.color,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                const SizedBox(width: 8),
                // Stage name
                Expanded(
                  child: Text(
                    stage.stageName,
                    style: const TextStyle(fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Base time
                Text(
                  '${stage.baseTimeMs.toInt()}ms',
                  style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                ),
                const SizedBox(width: 8),
                // Delay adjustment
                SizedBox(
                  width: 60,
                  child: Row(
                    children: [
                      Text(
                        stage.delayMs >= 0 ? '+' : '',
                        style: TextStyle(
                          fontSize: 9,
                          color: stage.delayMs >= 0 ? const Color(0xFF40FF90) : const Color(0xFFFF6B6B),
                        ),
                      ),
                      Text(
                        '${stage.delayMs.toInt()}ms',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: stage.delayMs >= 0 ? const Color(0xFF40FF90) : const Color(0xFFFF6B6B),
                        ),
                      ),
                    ],
                  ),
                ),
                // Reset button
                IconButton(
                  icon: const Icon(Icons.close, size: 12),
                  onPressed: () => widget.onDelayChanged?.call(stage.stageId, 0),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  tooltip: 'Reset delay',
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _resetAllDelays() {
    for (final stage in widget.stages) {
      widget.onDelayChanged?.call(stage.stageId, 0);
    }
  }
}

// =============================================================================
// TIMELINE PAINTER
// =============================================================================

class _TimelinePainter extends CustomPainter {
  final List<StageTiming> stages;
  final double pixelsPerMs;
  final double scrollOffset;
  final GridSnap gridSnap;
  final String? selectedStageId;
  final double viewWidth;

  _TimelinePainter({
    required this.stages,
    required this.pixelsPerMs,
    required this.scrollOffset,
    required this.gridSnap,
    required this.selectedStageId,
    required this.viewWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0a0a0c),
    );

    // Draw grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFF1a1a20)
      ..strokeWidth = 1;

    final majorGridPaint = Paint()
      ..color = const Color(0xFF242430)
      ..strokeWidth = 1;

    final textPaint = TextPainter(textDirection: TextDirection.ltr);

    // Calculate visible range
    final startMs = scrollOffset / pixelsPerMs;
    final endMs = (scrollOffset + viewWidth) / pixelsPerMs;

    // Draw time markers every 100ms, major every 500ms
    for (var ms = (startMs / 100).floor() * 100; ms <= endMs; ms += 100) {
      final x = ms * pixelsPerMs - scrollOffset;
      final isMajor = ms % 500 == 0;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        isMajor ? majorGridPaint : gridPaint,
      );

      // Draw time label for major lines
      if (isMajor) {
        textPaint.text = TextSpan(
          text: '${(ms / 1000).toStringAsFixed(1)}s',
          style: TextStyle(fontSize: 9, color: Colors.grey[600]),
        );
        textPaint.layout();
        textPaint.paint(canvas, Offset(x + 2, size.height - 14));
      }
    }

    // Draw snap grid if enabled
    if (gridSnap != GridSnap.off) {
      final snapPaint = Paint()
        ..color = const Color(0xFF4A9EFF).withValues(alpha: 0.1)
        ..strokeWidth = 1;

      for (var ms = (startMs / gridSnap.valueMs).floor() * gridSnap.valueMs;
           ms <= endMs;
           ms += gridSnap.valueMs) {
        final x = ms * pixelsPerMs - scrollOffset;
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height - 20),
          snapPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.scrollOffset != scrollOffset ||
           oldDelegate.gridSnap != gridSnap ||
           oldDelegate.stages != stages;
  }
}
