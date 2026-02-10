/// DraggableLayerWidget — Self-contained StatefulWidget for timeline layer drag
///
/// CRITICAL: This widget is ISOLATED from parent rebuilds.
/// setState() in this widget ONLY rebuilds THIS widget, not the parent.
/// This prevents GestureDetector death during drag operations.
///
/// Architecture (matches DAW ClipWidget):
/// - onPanStart: capture start values, local setState
/// - onPanUpdate: compute new position, local setState
/// - onPanEnd: call parent callback with final position
/// - Parent NEVER calls setState during drag

import 'package:flutter/material.dart';

/// Callback when layer drag starts
typedef LayerDragStartCallback = void Function(String layerId, String eventId, double startOffsetMs);

/// Callback when layer drag completes
typedef LayerDragEndCallback = void Function(String layerId, String eventId, double finalOffsetMs);

/// Callback to get fresh offset from provider
typedef GetFreshOffsetCallback = double Function(String layerId, String eventId);

/// Widget for a single draggable layer on the timeline
class DraggableLayerWidget extends StatefulWidget {
  final String layerId;
  final String eventId;
  final String regionId;
  final double initialOffsetMs;
  final double regionStart; // In seconds
  final double regionDuration; // In seconds
  final double layerDuration; // In seconds
  final double regionWidth; // In pixels
  final Color color;
  final bool muted;
  final String layerName;
  final List<double>? waveformData;
  final LayerDragStartCallback? onDragStart;
  final LayerDragEndCallback onDragEnd;
  final GetFreshOffsetCallback getFreshOffset;
  final VoidCallback? onDelete;

  const DraggableLayerWidget({
    super.key,
    required this.layerId,
    required this.eventId,
    required this.regionId,
    required this.initialOffsetMs,
    required this.regionStart,
    required this.regionDuration,
    required this.layerDuration,
    required this.regionWidth,
    required this.color,
    required this.muted,
    required this.layerName,
    this.waveformData,
    this.onDragStart,
    required this.onDragEnd,
    required this.getFreshOffset,
    this.onDelete,
  });

  @override
  State<DraggableLayerWidget> createState() => _DraggableLayerWidgetState();
}

class _DraggableLayerWidgetState extends State<DraggableLayerWidget> {
  // ═══════════════════════════════════════════════════════════════════════════
  // LOCAL DRAG STATE — isolated from parent, setState is safe here
  // ═══════════════════════════════════════════════════════════════════════════
  bool _isDragging = false;
  double _dragStartOffsetMs = 0;
  double _dragStartMouseX = 0;
  double _currentOffsetMs = 0;
  double _dragPixelsPerMs = 1.0;

  // Captured values at drag start (for stable visual during drag)
  double _capturedRegionDuration = 0;
  double _capturedLayerDuration = 0;
  double _capturedRegionStart = 0; // CRITICAL: region.start changes dynamically!

  @override
  void initState() {
    super.initState();
    _currentOffsetMs = widget.initialOffsetMs;
  }

  @override
  void didUpdateWidget(DraggableLayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // CRITICAL: Only update if NOT dragging AND the new value differs significantly
    // from our CURRENT value. This prevents:
    // 1. Overwriting during active drag
    // 2. Overwriting with stale data after drag completes (race condition)
    // 3. Small floating point differences causing jumps
    if (!_isDragging) {
      final delta = (widget.initialOffsetMs - _currentOffsetMs).abs();
      // Only update if provider value differs by more than 1ms from our local state
      // This means: external changes (from other UI) will update us,
      // but our own just-committed drag value won't be overwritten
      if (delta > 1.0) {
        _currentOffsetMs = widget.initialOffsetMs;
      } else {
      }
    }
  }

  double get _pixelsPerSecond {
    final duration = _isDragging ? _capturedRegionDuration : widget.regionDuration;
    return duration > 0 ? widget.regionWidth / duration : 100.0;
  }

  double get _layerWidth {
    final duration = _isDragging ? _capturedLayerDuration : widget.layerDuration;
    return (duration * _pixelsPerSecond).clamp(30.0, double.infinity);
  }

  double get _offsetPixels {
    // Use CAPTURED regionStart during drag to prevent jumps when region.start changes
    final regionStart = _isDragging ? _capturedRegionStart : widget.regionStart;
    final offsetSeconds = (_currentOffsetMs / 1000.0) - regionStart;
    return (offsetSeconds * _pixelsPerSecond).clamp(0.0, double.infinity);
  }

  double get _originalOffsetPixels {
    if (!_isDragging) return _offsetPixels;
    // Always use captured value for ghost position
    final offsetSeconds = (_dragStartOffsetMs / 1000.0) - _capturedRegionStart;
    return (offsetSeconds * _pixelsPerSecond).clamp(0.0, double.infinity);
  }

  String _formatTimeMs(int ms) {
    if (ms < 1000) return '${ms}ms';
    if (ms < 60000) return '${(ms / 1000).toStringAsFixed(2)}s';
    return '${ms ~/ 60000}m ${((ms % 60000) / 1000).toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: widget.regionWidth, maxWidth: widget.regionWidth),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          // Ghost outline at original position during drag
          if (_isDragging && (_offsetPixels - _originalOffsetPixels).abs() > 2)
            Positioned(
              left: _originalOffsetPixels,
              top: 2,
              bottom: 2,
              width: _layerWidth,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: widget.color.withAlpha(100), width: 1),
                ),
              ),
            ),

          // Time tooltip above layer during drag
          if (_isDragging)
            Positioned(
              left: _offsetPixels.clamp(0.0, double.infinity),
              top: -20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF242430),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF4a9eff), width: 1),
                ),
                child: Text(
                  _formatTimeMs(_currentOffsetMs.round()),
                  style: const TextStyle(color: Color(0xFF4a9eff), fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ),

          // The actual draggable layer
          Positioned(
            left: _offsetPixels,
            top: 2,
            bottom: 2,
            width: _layerWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              onPanCancel: _onPanCancel,
              child: MouseRegion(
                cursor: _isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
                child: Opacity(
                  opacity: _isDragging ? 0.85 : 1.0,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: _isDragging ? Colors.white : widget.color.withOpacity(0.6),
                        width: _isDragging ? 2 : 1,
                      ),
                      boxShadow: _isDragging ? [
                        BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 8, offset: const Offset(2, 2)),
                      ] : null,
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Stack(
                      children: [
                        // Background + waveform
                        Positioned.fill(
                          child: _buildContent(),
                        ),
                        // Delete button (only when not dragging)
                        if (!_isDragging && widget.onDelete != null)
                          Positioned(
                            right: 2,
                            top: 2,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: widget.onDelete,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Icon(Icons.close, size: 10, color: Colors.white),
                                ),
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

  Widget _buildContent() {
    final hasWaveform = widget.waveformData != null && widget.waveformData!.isNotEmpty;
    final color = widget.muted ? Colors.grey : widget.color;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withOpacity(0.4),
            color.withOpacity(0.25),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Waveform
          if (hasWaveform)
            Positioned.fill(
              child: CustomPaint(
                painter: _WaveformPainter(
                  data: widget.waveformData!,
                  color: color.withOpacity(0.6),
                ),
              ),
            ),
          // Layer name + debug offset display
          Positioned(
            left: 4,
            top: 2,
            right: 4,
            child: Text(
              '${widget.layerName} [${_currentOffsetMs.round()}ms]',
              style: TextStyle(
                color: widget.muted ? Colors.grey : Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAN HANDLERS — local setState is safe, only rebuilds THIS widget
  // ═══════════════════════════════════════════════════════════════════════════

  void _onPanStart(DragStartDetails details) {
    if (widget.layerId.isEmpty) return;

    // Get FRESH offset from provider via callback
    final freshOffsetMs = widget.getFreshOffset(widget.layerId, widget.eventId);

    setState(() {
      _isDragging = true;
      _dragStartOffsetMs = freshOffsetMs;
      _dragStartMouseX = details.globalPosition.dx;
      _currentOffsetMs = freshOffsetMs;
      _capturedRegionDuration = widget.regionDuration;
      _capturedLayerDuration = widget.layerDuration;
      _capturedRegionStart = widget.regionStart; // CRITICAL: Capture before it changes!
      _dragPixelsPerMs = widget.regionWidth / (widget.regionDuration * 1000);
    });


    // CRITICAL: Notify parent that drag started (so _dragController knows)
    // This prevents region.start from being updated during drag
    widget.onDragStart?.call(widget.layerId, widget.eventId, freshOffsetMs);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    final deltaX = details.globalPosition.dx - _dragStartMouseX;
    final deltaMs = deltaX / _dragPixelsPerMs;
    final newOffsetMs = (_dragStartOffsetMs + deltaMs).clamp(0.0, double.infinity);

    setState(() {
      _currentOffsetMs = newOffsetMs;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (!_isDragging) return;

    final finalOffsetMs = _currentOffsetMs;


    // CRITICAL FIX: Set local state to FINAL value and mark as not dragging
    // This ensures _currentOffsetMs survives the parent rebuild
    setState(() {
      _isDragging = false;
      // KEEP the final offset value - this is the source of truth until
      // didUpdateWidget receives the confirmed value from provider
      _currentOffsetMs = finalOffsetMs;
    });

    // CRITICAL: Defer callback to NEXT FRAME
    // This allows parent's setState/rebuild cycle to complete first.
    // When _onMiddlewareChanged triggers rebuild, this widget's state
    // already has the correct _currentOffsetMs, so didUpdateWidget
    // won't overwrite it with stale data.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onDragEnd(widget.layerId, widget.eventId, finalOffsetMs);
    });
  }

  void _onPanCancel() {
    if (!_isDragging) return;


    setState(() {
      _isDragging = false;
      _currentOffsetMs = _dragStartOffsetMs; // Revert to original
    });
  }
}

/// Simple waveform painter
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
      ..style = PaintingStyle.stroke;

    final path = Path();
    final width = size.width;
    final height = size.height;
    final centerY = height / 2;

    final step = data.length / width;
    for (int i = 0; i < width.toInt(); i++) {
      final dataIndex = (i * step).floor().clamp(0, data.length - 1);
      final value = data[dataIndex].clamp(-1.0, 1.0);
      final y = centerY - (value * centerY * 0.8);

      if (i == 0) {
        path.moveTo(i.toDouble(), y);
      } else {
        path.lineTo(i.toDouble(), y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      data != oldDelegate.data || color != oldDelegate.color;
}
