/// MIDI Clip Widget for Timeline
///
/// Displays MIDI clips in the timeline with:
/// - Piano roll-style note preview
/// - Velocity visualization
/// - Pitch range indicator
/// - Looped clip display
/// - Selection and drag handling

import 'package:flutter/material.dart';
import '../../providers/midi_provider.dart';

/// MIDI clip widget for timeline display
class MidiClipWidget extends StatefulWidget {
  final MidiClip clip;
  final double zoom; // pixels per second
  final double scrollOffset;
  final double trackHeight;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(double newStartTime)? onMove;
  final void Function(double newStartTime, double newDuration)? onResize;
  final VoidCallback? onResizeEnd;
  final void Function(Offset globalPosition, Offset localPosition)? onDragStart;
  final void Function(Offset globalPosition)? onDragUpdate;
  final void Function(Offset globalPosition)? onDragEnd;

  const MidiClipWidget({
    super.key,
    required this.clip,
    required this.zoom,
    required this.scrollOffset,
    required this.trackHeight,
    this.isSelected = false,
    this.onTap,
    this.onDoubleTap,
    this.onMove,
    this.onResize,
    this.onResizeEnd,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  @override
  State<MidiClipWidget> createState() => _MidiClipWidgetState();
}

class _MidiClipWidgetState extends State<MidiClipWidget> {
  bool _isHovered = false;
  bool _isDragging = false;
  bool _isResizingLeft = false;
  bool _isResizingRight = false;
  double _dragStartX = 0;
  double _initialStartTime = 0;
  double _initialDuration = 0;

  static const double _resizeHandleWidth = 8.0;
  static const double _minClipWidth = 20.0;

  @override
  Widget build(BuildContext context) {
    final x = (widget.clip.startTime - widget.scrollOffset) * widget.zoom;
    final width = widget.clip.duration * widget.zoom;

    // Skip rendering if not visible
    if (x + width < -100 || x > 3000) {
      return const SizedBox.shrink();
    }

    final clipHeight = widget.trackHeight - 4;

    return Positioned(
      left: x,
      top: 2,
      width: width.clamp(_minClipWidth, double.infinity),
      height: clipHeight,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: _getCursor(),
        child: GestureDetector(
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
          onPanStart: _handlePanStart,
          onPanUpdate: _handlePanUpdate,
          onPanEnd: _handlePanEnd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  widget.clip.color.withValues(alpha: 0.9),
                  widget.clip.color.withValues(alpha: 0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: widget.isSelected
                    ? Colors.white
                    : widget.clip.color.withValues(alpha: 0.8),
                width: widget.isSelected ? 2 : 1,
              ),
              boxShadow: widget.isSelected
                  ? [
                      BoxShadow(
                        color: widget.clip.color.withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [
                  // Note preview
                  if (widget.clip.notes.isNotEmpty)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _MidiNotePreviewPainter(
                          notes: widget.clip.notes,
                          clipDuration: widget.clip.duration,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ),

                  // Empty clip indicator
                  if (widget.clip.isEmpty)
                    Center(
                      child: Icon(
                        Icons.music_note_outlined,
                        color: Colors.white.withValues(alpha: 0.5),
                        size: clipHeight * 0.6,
                      ),
                    ),

                  // Clip name
                  Positioned(
                    left: 4,
                    top: 2,
                    right: 4,
                    child: Text(
                      widget.clip.name,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
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

                  // Note count badge
                  if (widget.clip.notes.isNotEmpty)
                    Positioned(
                      right: 4,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '${widget.clip.noteCount}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),

                  // Muted overlay
                  if (widget.clip.muted)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.volume_off,
                            color: Colors.white54,
                            size: 16,
                          ),
                        ),
                      ),
                    ),

                  // Loop indicator
                  if (widget.clip.isLooped)
                    Positioned(
                      left: 4,
                      bottom: 2,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.loop,
                            color: Colors.white70,
                            size: 10,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${widget.clip.loopCount}x',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Resize handles (visible on hover)
                  if (_isHovered && !widget.clip.locked) ...[
                    // Left resize handle
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: _resizeHandleWidth,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.3),
                              Colors.transparent,
                            ],
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(3),
                            bottomLeft: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    // Right resize handle
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: _resizeHandleWidth,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.white.withValues(alpha: 0.3),
                            ],
                          ),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(3),
                            bottomRight: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  MouseCursor _getCursor() {
    if (widget.clip.locked) return SystemMouseCursors.forbidden;
    if (_isResizingLeft || _isResizingRight) return SystemMouseCursors.resizeLeftRight;
    if (_isDragging) return SystemMouseCursors.grabbing;
    return SystemMouseCursors.grab;
  }

  void _handlePanStart(DragStartDetails details) {
    if (widget.clip.locked) return;

    final localX = details.localPosition.dx;
    final width = widget.clip.duration * widget.zoom;

    _dragStartX = details.globalPosition.dx;
    _initialStartTime = widget.clip.startTime;
    _initialDuration = widget.clip.duration;

    if (localX < _resizeHandleWidth) {
      _isResizingLeft = true;
    } else if (localX > width - _resizeHandleWidth) {
      _isResizingRight = true;
    } else {
      _isDragging = true;
      widget.onDragStart?.call(details.globalPosition, details.localPosition);
    }

    setState(() {});
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (widget.clip.locked) return;

    final deltaX = details.globalPosition.dx - _dragStartX;
    final deltaTime = deltaX / widget.zoom;

    if (_isResizingLeft) {
      final newStartTime = (_initialStartTime + deltaTime).clamp(0.0, double.infinity);
      final startDelta = newStartTime - _initialStartTime;
      final newDuration = (_initialDuration - startDelta).clamp(0.1, double.infinity);
      widget.onResize?.call(newStartTime, newDuration);
    } else if (_isResizingRight) {
      final newDuration = (_initialDuration + deltaTime).clamp(0.1, double.infinity);
      widget.onResize?.call(_initialStartTime, newDuration);
    } else if (_isDragging) {
      widget.onDragUpdate?.call(details.globalPosition);
      final newStartTime = (_initialStartTime + deltaTime).clamp(0.0, double.infinity);
      widget.onMove?.call(newStartTime);
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_isResizingLeft || _isResizingRight) {
      widget.onResizeEnd?.call();
    } else if (_isDragging) {
      widget.onDragEnd?.call(details.globalPosition);
    }

    setState(() {
      _isDragging = false;
      _isResizingLeft = false;
      _isResizingRight = false;
    });
  }
}

/// Painter for MIDI note preview in timeline clips
class _MidiNotePreviewPainter extends CustomPainter {
  final List<MidiNoteData> notes;
  final double clipDuration;
  final Color color;

  _MidiNotePreviewPainter({
    required this.notes,
    required this.clipDuration,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (notes.isEmpty || clipDuration <= 0) return;

    // Find pitch range
    int minPitch = 127, maxPitch = 0;
    for (final note in notes) {
      if (note.pitch < minPitch) minPitch = note.pitch;
      if (note.pitch > maxPitch) maxPitch = note.pitch;
    }

    // Add padding to pitch range
    final pitchRange = (maxPitch - minPitch + 1).clamp(12, 127);
    final pitchPadding = (pitchRange * 0.1).ceil();
    minPitch = (minPitch - pitchPadding).clamp(0, 127);
    maxPitch = (maxPitch + pitchPadding).clamp(0, 127);

    final pitchHeight = size.height / (maxPitch - minPitch + 1);
    final timeScale = size.width / clipDuration;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Draw notes
    for (final note in notes) {
      if (note.muted) continue;

      final x = note.startTime * timeScale;
      final width = (note.duration * timeScale).clamp(1.0, size.width - x);
      final y = (maxPitch - note.pitch) * pitchHeight;
      final height = pitchHeight.clamp(1.0, size.height);

      // Velocity affects opacity
      final velocityAlpha = 0.3 + (note.velocity * 0.7);
      paint.color = color.withValues(alpha: velocityAlpha);

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, width, height - 1),
        const Radius.circular(1),
      );

      canvas.drawRRect(rect, paint);
      canvas.drawRRect(rect, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MidiNotePreviewPainter oldDelegate) {
    return notes != oldDelegate.notes ||
        clipDuration != oldDelegate.clipDuration ||
        color != oldDelegate.color;
  }
}

/// Compact MIDI clip for arrangement view (smaller tracks)
class MidiClipCompact extends StatelessWidget {
  final MidiClip clip;
  final double zoom;
  final double scrollOffset;
  final double height;
  final bool isSelected;
  final VoidCallback? onTap;

  const MidiClipCompact({
    super.key,
    required this.clip,
    required this.zoom,
    required this.scrollOffset,
    this.height = 24,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final x = (clip.startTime - scrollOffset) * zoom;
    final width = clip.duration * zoom;

    if (x + width < 0 || x > 2000) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: x,
      top: 0,
      width: width.clamp(8, double.infinity),
      height: height,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: clip.color.withValues(alpha: clip.muted ? 0.3 : 0.8),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: isSelected ? Colors.white : clip.color,
              width: isSelected ? 1.5 : 0.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Center(
            child: Text(
              clip.name,
              style: TextStyle(
                color: Colors.white.withValues(alpha: clip.muted ? 0.5 : 0.9),
                fontSize: 9,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
