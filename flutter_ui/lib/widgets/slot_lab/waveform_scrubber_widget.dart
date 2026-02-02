/// Waveform Scrubber Widget — Interactive Waveform with Playhead & Scrubbing
///
/// P12.1.2: Interactive waveform display with:
/// - Drag to scrub audio playback position
/// - Zoom controls (fit, in, out)
/// - Loop region selection (drag handles)
/// - Real-time playhead tracking
/// - Waveform visualization with peaks
///
/// Usage:
/// ```dart
/// WaveformScrubberWidget(
///   audioPath: '/path/to/audio.wav',
///   waveform: waveformData,
///   duration: 10.5,
///   onSeek: (position) => print('Seek to: $position'),
///   onLoopRegionChanged: (start, end) => print('Loop: $start - $end'),
/// )
/// ```

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Callback for seek position changes (in seconds)
typedef OnSeekCallback = void Function(double positionSeconds);

/// Callback for loop region changes (start/end in seconds)
typedef OnLoopRegionCallback = void Function(double startSeconds, double endSeconds);

/// Zoom level presets
enum WaveformZoomLevel {
  fit,     // Fit entire waveform to view
  x2,      // 2x zoom
  x4,      // 4x zoom
  x8,      // 8x zoom
  x16,     // 16x zoom
}

/// Loop region data
class LoopRegion {
  final double startSeconds;
  final double endSeconds;
  final bool enabled;

  const LoopRegion({
    required this.startSeconds,
    required this.endSeconds,
    this.enabled = false,
  });

  LoopRegion copyWith({
    double? startSeconds,
    double? endSeconds,
    bool? enabled,
  }) {
    return LoopRegion(
      startSeconds: startSeconds ?? this.startSeconds,
      endSeconds: endSeconds ?? this.endSeconds,
      enabled: enabled ?? this.enabled,
    );
  }

  double get durationSeconds => endSeconds - startSeconds;

  bool isValid() => startSeconds >= 0 && endSeconds > startSeconds;

  @override
  String toString() => 'LoopRegion($startSeconds - $endSeconds, enabled: $enabled)';
}

/// Interactive waveform scrubber widget
class WaveformScrubberWidget extends StatefulWidget {
  /// Path to audio file (for display/reference)
  final String audioPath;

  /// Waveform peak data (normalized -1 to 1)
  final Float32List? waveform;

  /// Total duration in seconds
  final double duration;

  /// Current playhead position in seconds
  final double position;

  /// Whether audio is currently playing
  final bool isPlaying;

  /// Callback when user seeks to new position
  final OnSeekCallback? onSeek;

  /// Callback when loop region changes
  final OnLoopRegionCallback? onLoopRegionChanged;

  /// Callback when scrubbing starts
  final VoidCallback? onScrubStart;

  /// Callback when scrubbing ends
  final VoidCallback? onScrubEnd;

  /// Initial loop region (null = no loop)
  final LoopRegion? initialLoopRegion;

  /// Widget height
  final double height;

  /// Waveform color
  final Color waveformColor;

  /// Playhead color
  final Color playheadColor;

  /// Loop region color
  final Color loopRegionColor;

  /// Background color
  final Color backgroundColor;

  /// Whether to show time labels
  final bool showTimeLabels;

  /// Whether to show zoom controls
  final bool showZoomControls;

  /// Whether loop region is editable
  final bool loopEditable;

  const WaveformScrubberWidget({
    super.key,
    required this.audioPath,
    this.waveform,
    required this.duration,
    this.position = 0.0,
    this.isPlaying = false,
    this.onSeek,
    this.onLoopRegionChanged,
    this.onScrubStart,
    this.onScrubEnd,
    this.initialLoopRegion,
    this.height = 80,
    this.waveformColor = const Color(0xFF4A9EFF),
    this.playheadColor = const Color(0xFFFF9040),
    this.loopRegionColor = const Color(0xFF40FF90),
    this.backgroundColor = const Color(0xFF1A1A20),
    this.showTimeLabels = true,
    this.showZoomControls = true,
    this.loopEditable = true,
  });

  @override
  State<WaveformScrubberWidget> createState() => _WaveformScrubberWidgetState();
}

class _WaveformScrubberWidgetState extends State<WaveformScrubberWidget> {
  // Zoom/scroll state
  double _zoomLevel = 1.0;
  double _scrollOffset = 0.0; // In seconds

  // Loop region
  LoopRegion? _loopRegion;
  bool _isDraggingLoopStart = false;
  bool _isDraggingLoopEnd = false;

  // Scrubbing state
  bool _isScrubbing = false;
  double _scrubPosition = 0.0;

  // For keyboard shortcuts
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loopRegion = widget.initialLoopRegion;
    _scrubPosition = widget.position;
  }

  @override
  void didUpdateWidget(WaveformScrubberWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isScrubbing && widget.position != oldWidget.position) {
      _scrubPosition = widget.position;
    }
    if (widget.initialLoopRegion != oldWidget.initialLoopRegion) {
      _loopRegion = widget.initialLoopRegion;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// Visible duration based on zoom level
  double get _visibleDuration => widget.duration / _zoomLevel;

  /// Pixels per second based on current width and zoom
  double _pixelsPerSecond(double width) {
    return width * _zoomLevel / widget.duration;
  }

  /// Convert screen X position to time in seconds
  double _xToSeconds(double x, double width) {
    final pps = _pixelsPerSecond(width);
    return _scrollOffset + (x / pps);
  }

  /// Convert time in seconds to screen X position
  double _secondsToX(double seconds, double width) {
    final pps = _pixelsPerSecond(width);
    return (seconds - _scrollOffset) * pps;
  }

  void _handleZoom(WaveformZoomLevel level) {
    setState(() {
      switch (level) {
        case WaveformZoomLevel.fit:
          _zoomLevel = 1.0;
          _scrollOffset = 0.0;
        case WaveformZoomLevel.x2:
          _zoomLevel = 2.0;
        case WaveformZoomLevel.x4:
          _zoomLevel = 4.0;
        case WaveformZoomLevel.x8:
          _zoomLevel = 8.0;
        case WaveformZoomLevel.x16:
          _zoomLevel = 16.0;
      }
      // Center on current position when zooming
      _centerOnPosition(_scrubPosition);
    });
  }

  void _handleZoomIn() {
    setState(() {
      _zoomLevel = (_zoomLevel * 1.5).clamp(1.0, 32.0);
      _centerOnPosition(_scrubPosition);
    });
  }

  void _handleZoomOut() {
    setState(() {
      _zoomLevel = (_zoomLevel / 1.5).clamp(1.0, 32.0);
      _clampScrollOffset();
    });
  }

  void _centerOnPosition(double position) {
    final halfVisible = _visibleDuration / 2;
    _scrollOffset = (position - halfVisible).clamp(0.0, widget.duration - _visibleDuration);
  }

  void _clampScrollOffset() {
    final maxOffset = math.max(0.0, widget.duration - _visibleDuration);
    _scrollOffset = _scrollOffset.clamp(0.0, maxOffset);
  }

  void _handleScrubStart(double x, double width) {
    setState(() {
      _isScrubbing = true;
      _scrubPosition = _xToSeconds(x, width).clamp(0.0, widget.duration);
    });
    widget.onScrubStart?.call();
    widget.onSeek?.call(_scrubPosition);
  }

  void _handleScrubUpdate(double x, double width) {
    if (!_isScrubbing) return;
    setState(() {
      _scrubPosition = _xToSeconds(x, width).clamp(0.0, widget.duration);
    });
    widget.onSeek?.call(_scrubPosition);
  }

  void _handleScrubEnd() {
    setState(() {
      _isScrubbing = false;
    });
    widget.onScrubEnd?.call();
  }

  void _handleLoopStartDrag(double x, double width) {
    if (!widget.loopEditable || _loopRegion == null) return;
    final newStart = _xToSeconds(x, width).clamp(0.0, _loopRegion!.endSeconds - 0.1);
    setState(() {
      _loopRegion = _loopRegion!.copyWith(startSeconds: newStart);
    });
    widget.onLoopRegionChanged?.call(_loopRegion!.startSeconds, _loopRegion!.endSeconds);
  }

  void _handleLoopEndDrag(double x, double width) {
    if (!widget.loopEditable || _loopRegion == null) return;
    final newEnd = _xToSeconds(x, width).clamp(_loopRegion!.startSeconds + 0.1, widget.duration);
    setState(() {
      _loopRegion = _loopRegion!.copyWith(endSeconds: newEnd);
    });
    widget.onLoopRegionChanged?.call(_loopRegion!.startSeconds, _loopRegion!.endSeconds);
  }

  void _createLoopRegion(double x, double width) {
    if (!widget.loopEditable) return;
    final tapTime = _xToSeconds(x, width).clamp(0.0, widget.duration);
    // Create 2-second loop region centered on tap
    final halfDuration = 1.0;
    final start = (tapTime - halfDuration).clamp(0.0, widget.duration - 0.5);
    final end = (tapTime + halfDuration).clamp(0.5, widget.duration);
    setState(() {
      _loopRegion = LoopRegion(startSeconds: start, endSeconds: end, enabled: true);
    });
    widget.onLoopRegionChanged?.call(start, end);
  }

  void _clearLoopRegion() {
    setState(() {
      _loopRegion = null;
    });
    widget.onLoopRegionChanged?.call(0.0, 0.0);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    // Zoom shortcuts
    if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add) {
      _handleZoomIn();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus) {
      _handleZoomOut();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit0) {
      _handleZoom(WaveformZoomLevel.fit);
      return KeyEventResult.handled;
    }

    // Loop shortcuts
    if (key == LogicalKeyboardKey.keyL) {
      if (_loopRegion != null) {
        _clearLoopRegion();
      } else {
        // Create loop at current position
        _createLoopRegion(_secondsToX(_scrubPosition, 300), 300);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  String _formatTime(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    final ms = ((seconds % 1) * 100).floor();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Zoom controls (optional)
          if (widget.showZoomControls) _buildZoomControls(),

          // Main waveform area
          SizedBox(
            height: widget.height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  onTapDown: (details) {
                    _focusNode.requestFocus();
                    _handleScrubStart(details.localPosition.dx, width);
                    _handleScrubEnd();
                  },
                  onHorizontalDragStart: (details) {
                    // Check if dragging loop handles
                    if (_loopRegion != null && widget.loopEditable) {
                      final loopStartX = _secondsToX(_loopRegion!.startSeconds, width);
                      final loopEndX = _secondsToX(_loopRegion!.endSeconds, width);
                      final tapX = details.localPosition.dx;

                      if ((tapX - loopStartX).abs() < 10) {
                        _isDraggingLoopStart = true;
                        return;
                      }
                      if ((tapX - loopEndX).abs() < 10) {
                        _isDraggingLoopEnd = true;
                        return;
                      }
                    }
                    _handleScrubStart(details.localPosition.dx, width);
                  },
                  onHorizontalDragUpdate: (details) {
                    if (_isDraggingLoopStart) {
                      _handleLoopStartDrag(details.localPosition.dx, width);
                    } else if (_isDraggingLoopEnd) {
                      _handleLoopEndDrag(details.localPosition.dx, width);
                    } else {
                      _handleScrubUpdate(details.localPosition.dx, width);
                    }
                  },
                  onHorizontalDragEnd: (_) {
                    _isDraggingLoopStart = false;
                    _isDraggingLoopEnd = false;
                    _handleScrubEnd();
                  },
                  onDoubleTap: () {
                    // Double-tap to create/clear loop
                    if (_loopRegion != null) {
                      _clearLoopRegion();
                    }
                  },
                  child: CustomPaint(
                    size: Size(width, widget.height),
                    painter: _WaveformScrubberPainter(
                      waveform: widget.waveform,
                      duration: widget.duration,
                      position: _isScrubbing ? _scrubPosition : widget.position,
                      scrollOffset: _scrollOffset,
                      zoomLevel: _zoomLevel,
                      loopRegion: _loopRegion,
                      waveformColor: widget.waveformColor,
                      playheadColor: widget.playheadColor,
                      loopRegionColor: widget.loopRegionColor,
                      backgroundColor: widget.backgroundColor,
                      showTimeLabels: widget.showTimeLabels,
                    ),
                  ),
                );
              },
            ),
          ),

          // Time display
          if (widget.showTimeLabels)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatTime(_isScrubbing ? _scrubPosition : widget.position),
                    style: TextStyle(
                      color: widget.playheadColor,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (_loopRegion != null && _loopRegion!.enabled)
                    Text(
                      'Loop: ${_formatTime(_loopRegion!.startSeconds)} - ${_formatTime(_loopRegion!.endSeconds)}',
                      style: TextStyle(
                        color: widget.loopRegionColor,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  Text(
                    _formatTime(widget.duration),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildZoomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(
            icon: Icons.zoom_out,
            tooltip: 'Zoom Out (-)',
            onPressed: _handleZoomOut,
          ),
          const SizedBox(width: 4),
          _ZoomButton(
            icon: Icons.fit_screen,
            tooltip: 'Fit (0)',
            onPressed: () => _handleZoom(WaveformZoomLevel.fit),
          ),
          const SizedBox(width: 4),
          _ZoomButton(
            icon: Icons.zoom_in,
            tooltip: 'Zoom In (+)',
            onPressed: _handleZoomIn,
          ),
          const SizedBox(width: 12),
          Text(
            '${_zoomLevel.toStringAsFixed(1)}x',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 12),
          if (widget.loopEditable)
            _ZoomButton(
              icon: _loopRegion != null ? Icons.repeat_one : Icons.repeat,
              tooltip: _loopRegion != null ? 'Clear Loop (L)' : 'Create Loop (L)',
              onPressed: () {
                if (_loopRegion != null) {
                  _clearLoopRegion();
                } else {
                  _createLoopRegion(_secondsToX(_scrubPosition, 300), 300);
                }
              },
              color: _loopRegion != null ? widget.loopRegionColor : null,
            ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 18,
            color: color ?? Colors.white70,
          ),
        ),
      ),
    );
  }
}

/// Custom painter for waveform scrubber
class _WaveformScrubberPainter extends CustomPainter {
  final Float32List? waveform;
  final double duration;
  final double position;
  final double scrollOffset;
  final double zoomLevel;
  final LoopRegion? loopRegion;
  final Color waveformColor;
  final Color playheadColor;
  final Color loopRegionColor;
  final Color backgroundColor;
  final bool showTimeLabels;

  _WaveformScrubberPainter({
    required this.waveform,
    required this.duration,
    required this.position,
    required this.scrollOffset,
    required this.zoomLevel,
    required this.loopRegion,
    required this.waveformColor,
    required this.playheadColor,
    required this.loopRegionColor,
    required this.backgroundColor,
    required this.showTimeLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = backgroundColor,
    );

    // Calculate visible range
    final visibleDuration = duration / zoomLevel;
    final pixelsPerSecond = size.width / visibleDuration;

    // Draw loop region first (behind waveform)
    if (loopRegion != null && loopRegion!.enabled) {
      final loopStartX = (loopRegion!.startSeconds - scrollOffset) * pixelsPerSecond;
      final loopEndX = (loopRegion!.endSeconds - scrollOffset) * pixelsPerSecond;

      // Loop region background
      canvas.drawRect(
        Rect.fromLTRB(loopStartX, 0, loopEndX, size.height),
        Paint()..color = loopRegionColor.withOpacity(0.15),
      );

      // Loop handles
      final handlePaint = Paint()
        ..color = loopRegionColor
        ..strokeWidth = 2;
      canvas.drawLine(Offset(loopStartX, 0), Offset(loopStartX, size.height), handlePaint);
      canvas.drawLine(Offset(loopEndX, 0), Offset(loopEndX, size.height), handlePaint);

      // Loop handle triangles
      final trianglePath = Path();
      trianglePath.moveTo(loopStartX, 0);
      trianglePath.lineTo(loopStartX + 8, 0);
      trianglePath.lineTo(loopStartX, 8);
      trianglePath.close();
      canvas.drawPath(trianglePath, Paint()..color = loopRegionColor);

      final endTriangle = Path();
      endTriangle.moveTo(loopEndX, 0);
      endTriangle.lineTo(loopEndX - 8, 0);
      endTriangle.lineTo(loopEndX, 8);
      endTriangle.close();
      canvas.drawPath(endTriangle, Paint()..color = loopRegionColor);
    }

    // Draw waveform
    if (waveform != null && waveform!.isNotEmpty) {
      final waveformPaint = Paint()
        ..color = waveformColor
        ..style = PaintingStyle.fill;

      final centerY = size.height / 2;
      final amplitude = size.height * 0.4;

      // Calculate sample range to draw
      final samplesPerSecond = waveform!.length / duration;
      final startSample = (scrollOffset * samplesPerSecond).floor().clamp(0, waveform!.length - 1);
      final endSample = ((scrollOffset + visibleDuration) * samplesPerSecond).ceil().clamp(0, waveform!.length);

      // Draw as bars (downsampled for performance)
      final samplesPerPixel = (endSample - startSample) / size.width;
      final barWidth = math.max(1.0, 2.0 / zoomLevel);

      for (double x = 0; x < size.width; x += barWidth) {
        final sampleIndex = startSample + (x * samplesPerPixel).floor();
        if (sampleIndex >= 0 && sampleIndex < waveform!.length) {
          // Get max amplitude in this pixel range
          var maxAmp = 0.0;
          final rangeEnd = math.min(sampleIndex + samplesPerPixel.ceil(), waveform!.length);
          for (int i = sampleIndex; i < rangeEnd; i++) {
            final amp = waveform![i].abs();
            if (amp > maxAmp) maxAmp = amp;
          }

          final barHeight = maxAmp * amplitude;
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(x, centerY),
              width: barWidth * 0.8,
              height: barHeight * 2,
            ),
            waveformPaint,
          );
        }
      }
    } else {
      // No waveform - draw placeholder line
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        Paint()
          ..color = waveformColor.withOpacity(0.3)
          ..strokeWidth = 1,
      );
    }

    // Draw playhead
    final playheadX = (position - scrollOffset) * pixelsPerSecond;
    if (playheadX >= 0 && playheadX <= size.width) {
      // Playhead glow
      canvas.drawLine(
        Offset(playheadX, 0),
        Offset(playheadX, size.height),
        Paint()
          ..color = playheadColor.withOpacity(0.3)
          ..strokeWidth = 5,
      );
      // Playhead line
      canvas.drawLine(
        Offset(playheadX, 0),
        Offset(playheadX, size.height),
        Paint()
          ..color = playheadColor
          ..strokeWidth = 2,
      );
      // Playhead triangle
      final trianglePath = Path();
      trianglePath.moveTo(playheadX - 6, 0);
      trianglePath.lineTo(playheadX + 6, 0);
      trianglePath.lineTo(playheadX, 8);
      trianglePath.close();
      canvas.drawPath(trianglePath, Paint()..color = playheadColor);
    }

    // Draw time grid lines
    if (showTimeLabels) {
      final gridPaint = Paint()
        ..color = Colors.white.withOpacity(0.1)
        ..strokeWidth = 1;

      // Determine grid interval based on zoom
      final gridInterval = _getGridInterval(visibleDuration);
      final startTime = (scrollOffset / gridInterval).floor() * gridInterval;

      for (double t = startTime; t <= scrollOffset + visibleDuration; t += gridInterval) {
        final x = (t - scrollOffset) * pixelsPerSecond;
        if (x >= 0 && x <= size.width) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
        }
      }
    }
  }

  double _getGridInterval(double visibleDuration) {
    if (visibleDuration <= 2) return 0.25;    // 250ms grid
    if (visibleDuration <= 5) return 0.5;     // 500ms grid
    if (visibleDuration <= 15) return 1.0;    // 1s grid
    if (visibleDuration <= 60) return 5.0;    // 5s grid
    if (visibleDuration <= 300) return 30.0;  // 30s grid
    return 60.0;                               // 1min grid
  }

  @override
  bool shouldRepaint(_WaveformScrubberPainter oldDelegate) {
    return position != oldDelegate.position ||
        scrollOffset != oldDelegate.scrollOffset ||
        zoomLevel != oldDelegate.zoomLevel ||
        loopRegion != oldDelegate.loopRegion ||
        waveform != oldDelegate.waveform;
  }
}
