/// Clip Widget
///
/// Cubase-style clip with:
/// - Waveform display (LOD)
/// - Drag to move
/// - Edge resize (trim)
/// - Fade handles
/// - Gain handle
/// - Slip edit (Cmd+drag)
/// - Selection state

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/reelforge_theme.dart';
import '../../models/timeline_models.dart';

class ClipWidget extends StatefulWidget {
  final TimelineClip clip;
  final double zoom;
  final double scrollOffset;
  final double trackHeight;
  final ValueChanged<bool>? onSelect;
  final ValueChanged<double>? onMove;
  final ValueChanged<double>? onGainChange;
  final void Function(double fadeIn, double fadeOut)? onFadeChange;
  final void Function(double newStartTime, double newDuration, double? newOffset)?
      onResize;
  final ValueChanged<String>? onRename;
  final ValueChanged<double>? onSlipEdit;
  final bool snapEnabled;
  final double snapValue;
  final double tempo;
  final List<TimelineClip> allClips;

  const ClipWidget({
    super.key,
    required this.clip,
    required this.zoom,
    required this.scrollOffset,
    required this.trackHeight,
    this.onSelect,
    this.onMove,
    this.onGainChange,
    this.onFadeChange,
    this.onResize,
    this.onRename,
    this.onSlipEdit,
    this.snapEnabled = false,
    this.snapValue = 1,
    this.tempo = 120,
    this.allClips = const [],
  });

  @override
  State<ClipWidget> createState() => _ClipWidgetState();
}

class _ClipWidgetState extends State<ClipWidget> {
  bool _isDraggingGain = false;
  bool _isDraggingFadeIn = false;
  bool _isDraggingFadeOut = false;
  bool _isDraggingLeftEdge = false;
  bool _isDraggingRightEdge = false;
  bool _isDraggingMove = false;
  bool _isSlipEditing = false;
  bool _isEditing = false;

  late TextEditingController _nameController;
  late FocusNode _focusNode;

  // Drag start values
  double _dragStartTime = 0;
  double _dragStartDuration = 0;
  double _dragStartMouseX = 0;
  double _dragStartSourceOffset = 0;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.clip.name);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _gainDisplay {
    if (widget.clip.gain <= 0) return '-∞';
    final db = 20 * _log10(widget.clip.gain);
    return db <= -60 ? '-∞' : '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)}';
  }

  double _log10(double x) => x > 0 ? (math.log(x) / math.ln10) : double.negativeInfinity;

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _nameController.text = widget.clip.name;
    });
    _focusNode.requestFocus();
  }

  void _submitName() {
    final trimmed = _nameController.text.trim();
    if (trimmed.isNotEmpty && trimmed != widget.clip.name) {
      widget.onRename?.call(trimmed);
    }
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final x = (clip.startTime - widget.scrollOffset) * widget.zoom;
    final width = clip.duration * widget.zoom;

    // Skip if not visible
    if (x + width < 0 || x > 2000) return const SizedBox.shrink();

    final clipHeight = widget.trackHeight - 4;
    final clipColor = clip.color ?? const Color(0xFF3A6EA5);

    return Positioned(
      left: x,
      top: 2,
      width: width.clamp(4, double.infinity),
      height: clipHeight,
      child: GestureDetector(
        onTap: () => widget.onSelect?.call(false),
        onDoubleTap: _startEditing,
        onPanStart: (details) {
          // Check for modifier keys for slip edit
          if (HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed) {
            _dragStartSourceOffset = clip.sourceOffset;
            _dragStartMouseX = details.globalPosition.dx;
            setState(() => _isSlipEditing = true);
          } else {
            _dragStartTime = clip.startTime;
            _dragStartMouseX = details.globalPosition.dx;
            setState(() => _isDraggingMove = true);
          }
        },
        onPanUpdate: (details) {
          final deltaX = details.globalPosition.dx - _dragStartMouseX;
          final deltaTime = deltaX / widget.zoom;

          if (_isSlipEditing) {
            // Slip edit - offset changes inversely
            final newOffset = (_dragStartSourceOffset - deltaTime).clamp(0.0, double.infinity);
            widget.onSlipEdit?.call(newOffset);
          } else if (_isDraggingMove) {
            // Move clip
            double rawNewStartTime = _dragStartTime + deltaTime;
            final snappedTime = applySnap(
              rawNewStartTime,
              widget.snapEnabled,
              widget.snapValue,
              widget.tempo,
              widget.allClips,
            );
            widget.onMove?.call(snappedTime.clamp(0.0, double.infinity));
          }
        },
        onPanEnd: (_) {
          setState(() {
            _isDraggingMove = false;
            _isSlipEditing = false;
          });
        },
        child: Container(
          decoration: BoxDecoration(
            color: clipColor.withValues(
              alpha: clip.muted ? 0.3 : (clip.selected ? 0.9 : 0.7),
            ),
            borderRadius: BorderRadius.circular(4),
            border: clip.selected
                ? Border.all(color: Colors.white, width: 2)
                : null,
          ),
          child: Stack(
            children: [
              // Waveform
              if (clip.waveform != null && width > 20)
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Transform.scale(
                      scaleY: clip.gain,
                      child: _WaveformCanvas(
                        waveform: clip.waveform!,
                        sourceOffset: clip.sourceOffset,
                        duration: clip.duration,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),

              // Label
              if (width > 40)
                Positioned(
                  left: 4,
                  top: 2,
                  right: 4,
                  child: _isEditing
                      ? TextField(
                          controller: _nameController,
                          focusNode: _focusNode,
                          style: ReelForgeTheme.bodySmall.copyWith(
                            color: Colors.white,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _submitName(),
                          onEditingComplete: _submitName,
                        )
                      : Text(
                          clip.name,
                          style: ReelForgeTheme.bodySmall.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                ),

              // Gain handle
              if (width > 60)
                Positioned(
                  top: 2,
                  left: (width - 40) / 2,
                  child: GestureDetector(
                    onVerticalDragStart: (_) {
                      setState(() => _isDraggingGain = true);
                    },
                    onVerticalDragUpdate: (details) {
                      // Up = louder, down = quieter
                      final delta = -details.delta.dy / 50;
                      final newGain = (widget.clip.gain + delta).clamp(0.0, 2.0);
                      widget.onGainChange?.call(newGain);
                    },
                    onVerticalDragEnd: (_) {
                      setState(() => _isDraggingGain = false);
                    },
                    onDoubleTap: () => widget.onGainChange?.call(1), // Reset
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: _isDraggingGain
                            ? ReelForgeTheme.accentBlue
                            : Colors.black54,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        _gainDisplay,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                    ),
                  ),
                ),

              // Fade in handle
              _FadeHandle(
                width: (clip.fadeIn * widget.zoom).clamp(8.0, double.infinity),
                isLeft: true,
                isActive: _isDraggingFadeIn,
                onDragStart: () => setState(() => _isDraggingFadeIn = true),
                onDragUpdate: (localX) {
                  final newFadeIn =
                      (localX / widget.zoom).clamp(0.0, clip.duration * 0.5);
                  widget.onFadeChange?.call(newFadeIn, clip.fadeOut);
                },
                onDragEnd: () => setState(() => _isDraggingFadeIn = false),
              ),

              // Fade out handle
              _FadeHandle(
                width: (clip.fadeOut * widget.zoom).clamp(8.0, double.infinity),
                isLeft: false,
                isActive: _isDraggingFadeOut,
                onDragStart: () => setState(() => _isDraggingFadeOut = true),
                onDragUpdate: (localX) {
                  final distFromRight = width - localX;
                  final newFadeOut =
                      (distFromRight / widget.zoom).clamp(0.0, clip.duration * 0.5);
                  widget.onFadeChange?.call(clip.fadeIn, newFadeOut);
                },
                onDragEnd: () => setState(() => _isDraggingFadeOut = false),
              ),

              // Fade visualizations
              if (clip.fadeIn > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: clip.fadeIn * widget.zoom,
                  child: CustomPaint(
                    painter: _FadeOverlayPainter(isLeft: true),
                  ),
                ),
              if (clip.fadeOut > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: clip.fadeOut * widget.zoom,
                  child: CustomPaint(
                    painter: _FadeOverlayPainter(isLeft: false),
                  ),
                ),

              // Left edge resize handle
              _EdgeHandle(
                isLeft: true,
                isActive: _isDraggingLeftEdge,
                onDragStart: () {
                  _dragStartTime = clip.startTime;
                  _dragStartDuration = clip.duration;
                  _dragStartSourceOffset = clip.sourceOffset;
                  setState(() => _isDraggingLeftEdge = true);
                },
                onDragUpdate: (deltaX) {
                  final deltaTime = deltaX / widget.zoom;
                  double rawNewStartTime = _dragStartTime + deltaTime;
                  final snappedStartTime = applySnap(
                    rawNewStartTime,
                    widget.snapEnabled,
                    widget.snapValue,
                    widget.tempo,
                    widget.allClips,
                  );

                  double newStartTime = snappedStartTime;
                  double newOffset = _dragStartSourceOffset;

                  if (snappedStartTime < _dragStartTime) {
                    // Extending left
                    final extensionAmount = _dragStartTime - snappedStartTime;
                    final maxExtension = _dragStartSourceOffset;
                    final actualExtension =
                        extensionAmount.clamp(0.0, maxExtension);
                    newStartTime = _dragStartTime - actualExtension;
                    newOffset = _dragStartSourceOffset - actualExtension;
                  } else {
                    // Trimming right
                    final trimAmount = snappedStartTime - _dragStartTime;
                    final maxTrim = _dragStartDuration - 0.1;
                    final actualTrim = trimAmount.clamp(0.0, maxTrim);
                    newStartTime = _dragStartTime + actualTrim;
                    newOffset = _dragStartSourceOffset + actualTrim;

                    // Source duration constraint
                    if (clip.sourceDuration != null) {
                      final maxOffset = clip.sourceDuration! - 0.1;
                      if (newOffset > maxOffset) {
                        newOffset = maxOffset;
                        newStartTime =
                            _dragStartTime + (newOffset - _dragStartSourceOffset);
                      }
                    }
                  }

                  newStartTime = newStartTime.clamp(0.0, double.infinity);
                  newOffset = newOffset.clamp(0.0, double.infinity);

                  final newDuration =
                      _dragStartDuration - (newStartTime - _dragStartTime);

                  widget.onResize?.call(
                    newStartTime,
                    newDuration.clamp(0.1, double.infinity),
                    newOffset,
                  );
                },
                onDragEnd: () => setState(() => _isDraggingLeftEdge = false),
              ),

              // Right edge resize handle
              _EdgeHandle(
                isLeft: false,
                isActive: _isDraggingRightEdge,
                onDragStart: () {
                  _dragStartDuration = clip.duration;
                  _dragStartMouseX = 0;
                  setState(() => _isDraggingRightEdge = true);
                },
                onDragUpdate: (deltaX) {
                  final deltaTime = deltaX / widget.zoom;
                  final rawEndTime = clip.startTime + _dragStartDuration + deltaTime;
                  final snappedEndTime = applySnap(
                    rawEndTime,
                    widget.snapEnabled,
                    widget.snapValue,
                    widget.tempo,
                    widget.allClips,
                  );
                  double newDuration = (snappedEndTime - clip.startTime).clamp(0.1, double.infinity);

                  // Source duration constraint
                  if (clip.sourceDuration != null) {
                    final maxDuration = clip.sourceDuration! - clip.sourceOffset;
                    newDuration = newDuration.clamp(0.1, maxDuration);
                  }

                  widget.onResize?.call(clip.startTime, newDuration, null);
                },
                onDragEnd: () => setState(() => _isDraggingRightEdge = false),
              ),

              // Muted overlay
              if (clip.muted)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============ Waveform Canvas ============

class _WaveformCanvas extends StatelessWidget {
  final Float32List waveform;
  final double sourceOffset;
  final double duration;
  final Color color;

  const _WaveformCanvas({
    required this.waveform,
    required this.sourceOffset,
    required this.duration,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WaveformPainter(
        waveform: waveform,
        color: color,
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final Float32List waveform;
  final Color color;

  _WaveformPainter({
    required this.waveform,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty || size.width <= 0 || size.height <= 0) return;

    final centerY = size.height / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final samplesPerPixel = waveform.length / size.width;

    for (double x = 0; x < size.width; x++) {
      final sampleIndex = (x * samplesPerPixel).floor().clamp(0, waveform.length - 1);
      final sample = waveform[sampleIndex].abs();
      final barHeight = sample * centerY * 0.9;

      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x, centerY),
          width: 1,
          height: barHeight * 2,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      waveform != oldDelegate.waveform || color != oldDelegate.color;
}

// ============ Fade Overlay Painter ============

class _FadeOverlayPainter extends CustomPainter {
  final bool isLeft;

  _FadeOverlayPainter({required this.isLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final path = Path();
    if (isLeft) {
      path.moveTo(0, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.close();
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_FadeOverlayPainter oldDelegate) => isLeft != oldDelegate.isLeft;
}

// ============ Fade Handle ============

class _FadeHandle extends StatelessWidget {
  final double width;
  final bool isLeft;
  final bool isActive;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  const _FadeHandle({
    required this.width,
    required this.isLeft,
    required this.isActive,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0,
      width: width,
      height: 12,
      child: GestureDetector(
        onHorizontalDragStart: (_) => onDragStart(),
        onHorizontalDragUpdate: (details) => onDragUpdate(details.localPosition.dx),
        onHorizontalDragEnd: (_) => onDragEnd(),
        child: Container(
          decoration: BoxDecoration(
            color: isActive
                ? ReelForgeTheme.accentBlue.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.only(
              topLeft: isLeft ? const Radius.circular(4) : Radius.zero,
              topRight: isLeft ? Radius.zero : const Radius.circular(4),
            ),
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: isActive ? 0.8 : 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============ Edge Handle ============

class _EdgeHandle extends StatefulWidget {
  final bool isLeft;
  final bool isActive;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  const _EdgeHandle({
    required this.isLeft,
    required this.isActive,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  State<_EdgeHandle> createState() => _EdgeHandleState();
}

class _EdgeHandleState extends State<_EdgeHandle> {
  double _startX = 0;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.isLeft ? 0 : null,
      right: widget.isLeft ? null : 0,
      top: 0,
      bottom: 0,
      width: 8,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          onHorizontalDragStart: (details) {
            _startX = details.globalPosition.dx;
            widget.onDragStart();
          },
          onHorizontalDragUpdate: (details) {
            final deltaX = details.globalPosition.dx - _startX;
            widget.onDragUpdate(deltaX);
          },
          onHorizontalDragEnd: (_) => widget.onDragEnd(),
          child: Container(
            decoration: BoxDecoration(
              color: widget.isActive
                  ? ReelForgeTheme.accentBlue.withValues(alpha: 0.5)
                  : Colors.transparent,
              borderRadius: BorderRadius.only(
                topLeft: widget.isLeft ? const Radius.circular(4) : Radius.zero,
                bottomLeft: widget.isLeft ? const Radius.circular(4) : Radius.zero,
                topRight: widget.isLeft ? Radius.zero : const Radius.circular(4),
                bottomRight: widget.isLeft ? Radius.zero : const Radius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
