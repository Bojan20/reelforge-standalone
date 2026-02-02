/// Timeline Layer Reorder Widget (P12.1.14)
///
/// Drag-drop layer reordering in the SlotLab timeline.
/// Features:
/// - Visual drag feedback
/// - Drop zone indicators
/// - Animated reorder
/// - Undo support via callback
library;

import 'package:flutter/material.dart';

// =============================================================================
// LAYER ITEM MODEL (simplified for reorder widget)
// =============================================================================

/// Represents a layer in the timeline for reordering purposes
class ReorderableLayer {
  final String id;
  final String name;
  final String? audioPath;
  final double offsetMs;
  final double durationMs;
  final Color color;
  final bool isMuted;

  const ReorderableLayer({
    required this.id,
    required this.name,
    this.audioPath,
    this.offsetMs = 0,
    this.durationMs = 1000,
    this.color = const Color(0xFF4A9EFF),
    this.isMuted = false,
  });

  ReorderableLayer copyWith({
    String? id,
    String? name,
    String? audioPath,
    double? offsetMs,
    double? durationMs,
    Color? color,
    bool? isMuted,
  }) {
    return ReorderableLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      audioPath: audioPath ?? this.audioPath,
      offsetMs: offsetMs ?? this.offsetMs,
      durationMs: durationMs ?? this.durationMs,
      color: color ?? this.color,
      isMuted: isMuted ?? this.isMuted,
    );
  }
}

// =============================================================================
// TIMELINE LAYER REORDER WIDGET
// =============================================================================

class TimelineLayerReorder extends StatefulWidget {
  final List<ReorderableLayer> layers;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final void Function(ReorderableLayer layer)? onLayerTap;
  final void Function(ReorderableLayer layer)? onLayerDoubleTap;
  final String? selectedLayerId;
  final double rowHeight;

  const TimelineLayerReorder({
    super.key,
    required this.layers,
    this.onReorder,
    this.onLayerTap,
    this.onLayerDoubleTap,
    this.selectedLayerId,
    this.rowHeight = 40,
  });

  @override
  State<TimelineLayerReorder> createState() => _TimelineLayerReorderState();
}

class _TimelineLayerReorderState extends State<TimelineLayerReorder> {
  int? _draggingIndex;
  int? _targetIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        const Divider(height: 1),
        Expanded(child: _buildLayerList()),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF1a1a20),
      child: Row(
        children: [
          const Icon(Icons.layers, size: 16, color: Color(0xFF4A9EFF)),
          const SizedBox(width: 8),
          const Text(
            'Layer Order',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            '${widget.layers.length} layers',
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerList() {
    if (widget.layers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.layers_clear, size: 32, color: Colors.grey[700]),
            const SizedBox(height: 8),
            Text(
              'No layers',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: widget.layers.length,
      itemBuilder: (context, index) {
        final layer = widget.layers[index];
        final isSelected = layer.id == widget.selectedLayerId;
        final isDragging = _draggingIndex == index;
        final isTarget = _targetIndex == index;

        return _buildDraggableLayerRow(layer, index, isSelected, isDragging, isTarget);
      },
    );
  }

  Widget _buildDraggableLayerRow(
    ReorderableLayer layer,
    int index,
    bool isSelected,
    bool isDragging,
    bool isTarget,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drop zone indicator above
        if (isTarget && _draggingIndex != null && _draggingIndex! > index)
          _buildDropIndicator(),

        // Draggable row
        LongPressDraggable<int>(
          data: index,
          onDragStarted: () => setState(() => _draggingIndex = index),
          onDragEnd: (_) => setState(() {
            _draggingIndex = null;
            _targetIndex = null;
          }),
          feedback: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 200,
              height: widget.rowHeight - 4,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: layer.color.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.drag_indicator, size: 14, color: Colors.white70),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      layer.name,
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _buildLayerRow(layer, index, isSelected, false),
          ),
          child: DragTarget<int>(
            onWillAcceptWithDetails: (details) {
              if (details.data != index) {
                setState(() => _targetIndex = index);
                return true;
              }
              return false;
            },
            onLeave: (_) => setState(() => _targetIndex = null),
            onAcceptWithDetails: (details) {
              final oldIndex = details.data;
              if (oldIndex != index) {
                widget.onReorder?.call(oldIndex, index);
              }
              setState(() => _targetIndex = null);
            },
            builder: (context, candidateData, rejectedData) {
              return _buildLayerRow(layer, index, isSelected, isTarget);
            },
          ),
        ),

        // Drop zone indicator below
        if (isTarget && _draggingIndex != null && _draggingIndex! < index)
          _buildDropIndicator(),
      ],
    );
  }

  Widget _buildLayerRow(ReorderableLayer layer, int index, bool isSelected, bool isTarget) {
    return GestureDetector(
      onTap: () => widget.onLayerTap?.call(layer),
      onDoubleTap: () => widget.onLayerDoubleTap?.call(layer),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: widget.rowHeight,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? layer.color.withValues(alpha: 0.2)
              : const Color(0xFF1a1a20),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isTarget
                ? const Color(0xFF4A9EFF)
                : isSelected
                    ? layer.color
                    : const Color(0xFF333340),
            width: isTarget ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Drag handle
            const Icon(Icons.drag_indicator, size: 16, color: Colors.grey),
            const SizedBox(width: 4),

            // Order number
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: layer.color.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Layer color indicator
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                color: layer.isMuted ? Colors.grey : layer.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),

            // Layer name
            Expanded(
              child: Text(
                layer.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: layer.isMuted ? Colors.grey : Colors.white,
                  decoration: layer.isMuted ? TextDecoration.lineThrough : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Duration badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF242430),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                _formatDuration(layer.durationMs),
                style: TextStyle(fontSize: 9, color: Colors.grey[500]),
              ),
            ),

            // Mute indicator
            if (layer.isMuted) ...[
              const SizedBox(width: 4),
              const Icon(Icons.volume_off, size: 12, color: Colors.grey),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDropIndicator() {
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF4A9EFF),
        borderRadius: BorderRadius.circular(1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A9EFF).withValues(alpha: 0.5),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }

  String _formatDuration(double ms) {
    final seconds = ms / 1000;
    if (seconds < 1) {
      return '${ms.toInt()}ms';
    } else if (seconds < 60) {
      return '${seconds.toStringAsFixed(1)}s';
    } else {
      final minutes = (seconds / 60).floor();
      final remainingSecs = (seconds % 60).toInt();
      return '$minutes:${remainingSecs.toString().padLeft(2, '0')}';
    }
  }
}
