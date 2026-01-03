/// Clip Editor Widget
///
/// Lower zone component for detailed audio clip editing:
/// - Zoomable waveform display (LOD)
/// - Selection tool for range selection
/// - Fade in/out handles
/// - Clip info sidebar
/// - Audio processing tools

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/reelforge_theme.dart';

// ============ Types ============

/// Clip data for the editor
class ClipEditorClip {
  final String id;
  final String name;
  final double duration;
  final int sampleRate;
  final int channels;
  final int bitDepth;
  final Float32List? waveform;
  final double fadeIn;
  final double fadeOut;
  final double gain;
  final Color? color;

  const ClipEditorClip({
    required this.id,
    required this.name,
    required this.duration,
    this.sampleRate = 48000,
    this.channels = 2,
    this.bitDepth = 24,
    this.waveform,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.gain = 0,
    this.color,
  });
}

/// Selection range
class ClipEditorSelection {
  final double start;
  final double end;

  const ClipEditorSelection({required this.start, required this.end});

  double get length => end - start;

  bool get isValid => end > start;
}

/// Editor tool types
enum EditorTool { select, zoom, fade, cut }

// ============ Clip Editor Widget ============

class ClipEditor extends StatefulWidget {
  final ClipEditorClip? clip;
  final ClipEditorSelection? selection;
  final double zoom;
  final double scrollOffset;
  final ValueChanged<ClipEditorSelection?>? onSelectionChange;
  final ValueChanged<double>? onZoomChange;
  final ValueChanged<double>? onScrollChange;
  final void Function(String clipId, double fadeIn)? onFadeInChange;
  final void Function(String clipId, double fadeOut)? onFadeOutChange;
  final void Function(String clipId, double gain)? onGainChange;
  final void Function(String clipId)? onNormalize;
  final void Function(String clipId)? onReverse;
  final void Function(String clipId, ClipEditorSelection selection)? onTrimToSelection;

  const ClipEditor({
    super.key,
    this.clip,
    this.selection,
    this.zoom = 100,
    this.scrollOffset = 0,
    this.onSelectionChange,
    this.onZoomChange,
    this.onScrollChange,
    this.onFadeInChange,
    this.onFadeOutChange,
    this.onGainChange,
    this.onNormalize,
    this.onReverse,
    this.onTrimToSelection,
  });

  @override
  State<ClipEditor> createState() => _ClipEditorState();
}

class _ClipEditorState extends State<ClipEditor> {
  EditorTool _tool = EditorTool.select;
  bool _isDragging = false;
  double? _dragStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        border: const Border(
          top: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),
          // Content
          Expanded(
            child: widget.clip == null ? _buildEmptyState() : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: ReelForgeTheme.bgSurface,
        border: Border(
          bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          const Text('✏️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Text(
            widget.clip?.name ?? 'Clip Editor',
            style: ReelForgeTheme.h3,
          ),
          const Spacer(),
          _buildToolbar(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final hasSelection = widget.selection?.isValid ?? false;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tools
        _ToolButton(
          icon: '⬚',
          label: 'Selection',
          isActive: _tool == EditorTool.select,
          onTap: () => setState(() => _tool = EditorTool.select),
        ),
        _ToolButton(
          icon: '🔍',
          label: 'Zoom',
          isActive: _tool == EditorTool.zoom,
          onTap: () => setState(() => _tool = EditorTool.zoom),
        ),
        _ToolButton(
          icon: '⟋',
          label: 'Fade',
          isActive: _tool == EditorTool.fade,
          onTap: () => setState(() => _tool = EditorTool.fade),
        ),
        _ToolButton(
          icon: '✂',
          label: 'Cut',
          isActive: _tool == EditorTool.cut,
          onTap: () => setState(() => _tool = EditorTool.cut),
        ),
        const SizedBox(width: 8),
        Container(width: 1, height: 16, color: ReelForgeTheme.borderSubtle),
        const SizedBox(width: 8),
        // Actions
        _ToolButton(
          icon: '📊',
          label: 'Normalize',
          onTap: () {
            if (widget.clip != null) {
              widget.onNormalize?.call(widget.clip!.id);
            }
          },
        ),
        _ToolButton(
          icon: '⇆',
          label: 'Reverse',
          onTap: () {
            if (widget.clip != null) {
              widget.onReverse?.call(widget.clip!.id);
            }
          },
        ),
        _ToolButton(
          icon: '⊞',
          label: 'Trim to Selection',
          isEnabled: hasSelection,
          onTap: hasSelection
              ? () {
                  if (widget.clip != null && widget.selection != null) {
                    widget.onTrimToSelection?.call(widget.clip!.id, widget.selection!);
                  }
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎵', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text(
            'Select a clip to edit',
            style: ReelForgeTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Row(
      children: [
        // Waveform area
        Expanded(
          child: _buildWaveformArea(),
        ),
        // Info sidebar
        SizedBox(
          width: 180,
          child: _InfoSidebar(
            clip: widget.clip!,
            selection: widget.selection,
            onFadeInChange: (v) => widget.onFadeInChange?.call(widget.clip!.id, v),
            onFadeOutChange: (v) => widget.onFadeOutChange?.call(widget.clip!.id, v),
            onGainChange: (v) => widget.onGainChange?.call(widget.clip!.id, v),
          ),
        ),
      ],
    );
  }

  Widget _buildWaveformArea() {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _handleWheel(event);
        }
      },
      child: GestureDetector(
        onPanStart: _handlePanStart,
        onPanUpdate: _handlePanUpdate,
        onPanEnd: _handlePanEnd,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return CustomPaint(
              painter: _WaveformPainter(
                waveform: widget.clip!.waveform,
                zoom: widget.zoom,
                scrollOffset: widget.scrollOffset,
                duration: widget.clip!.duration,
                selection: widget.selection,
                fadeIn: widget.clip!.fadeIn,
                fadeOut: widget.clip!.fadeOut,
                color: widget.clip!.color ?? ReelForgeTheme.accentBlue,
                channels: widget.clip!.channels,
              ),
              size: Size(constraints.maxWidth, constraints.maxHeight),
            );
          },
        ),
      ),
    );
  }

  void _handleWheel(PointerScrollEvent event) {
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      // Zoom
      final delta = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
      final newZoom = (widget.zoom * delta).clamp(10.0, 500.0);
      widget.onZoomChange?.call(newZoom);
    } else {
      // Scroll
      final delta =
          event.scrollDelta.dx != 0 ? event.scrollDelta.dx : event.scrollDelta.dy;
      final newOffset = (widget.scrollOffset + delta / widget.zoom).clamp(0.0, double.infinity);
      widget.onScrollChange?.call(newOffset);
    }
  }

  void _handlePanStart(DragStartDetails details) {
    if (_tool != EditorTool.select || widget.clip == null) return;

    final time = widget.scrollOffset + details.localPosition.dx / widget.zoom;
    setState(() {
      _isDragging = true;
      _dragStart = time;
    });
    widget.onSelectionChange?.call(ClipEditorSelection(start: time, end: time));
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!_isDragging || _dragStart == null || widget.clip == null) return;

    final time = (widget.scrollOffset + details.localPosition.dx / widget.zoom)
        .clamp(0.0, widget.clip!.duration);

    widget.onSelectionChange?.call(ClipEditorSelection(
      start: math.min(_dragStart!, time),
      end: math.max(_dragStart!, time),
    ));
  }

  void _handlePanEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
      _dragStart = null;
    });
  }
}

// ============ Tool Button ============

class _ToolButton extends StatelessWidget {
  final String icon;
  final String label;
  final bool isActive;
  final bool isEnabled;
  final VoidCallback? onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    this.isEnabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: isEnabled ? onTap : null,
        child: Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isActive
                ? ReelForgeTheme.accentBlue.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              icon,
              style: TextStyle(
                fontSize: 14,
                color: isEnabled
                    ? (isActive ? ReelForgeTheme.accentBlue : ReelForgeTheme.textSecondary)
                    : ReelForgeTheme.textTertiary.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============ Info Sidebar ============

class _InfoSidebar extends StatelessWidget {
  final ClipEditorClip clip;
  final ClipEditorSelection? selection;
  final ValueChanged<double>? onFadeInChange;
  final ValueChanged<double>? onFadeOutChange;
  final ValueChanged<double>? onGainChange;

  const _InfoSidebar({
    required this.clip,
    this.selection,
    this.onFadeInChange,
    this.onFadeOutChange,
    this.onGainChange,
  });

  String _formatTime(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = seconds % 60;
    return '$mins:${secs.toStringAsFixed(3).padLeft(6, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Clip info
            _InfoRow(label: 'Duration', value: _formatTime(clip.duration)),
            _InfoRow(label: 'Sample Rate', value: '${clip.sampleRate ~/ 1000} kHz'),
            _InfoRow(label: 'Channels', value: clip.channels == 2 ? 'Stereo' : 'Mono'),
            _InfoRow(label: 'Bit Depth', value: '${clip.bitDepth}-bit'),

            // Selection info
            if (selection != null && selection!.isValid) ...[
              const Divider(height: 24),
              _InfoRow(
                label: 'Selection',
                value: '${_formatTime(selection!.start)} → ${_formatTime(selection!.end)}',
              ),
              _InfoRow(label: 'Length', value: _formatTime(selection!.length)),
            ],

            // Fades
            const Divider(height: 24),
            Text('Fade In', style: ReelForgeTheme.label),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: clip.fadeIn,
                min: 0,
                max: clip.duration / 2,
                onChanged: onFadeInChange,
              ),
            ),
            Text('${clip.fadeIn.toStringAsFixed(2)}s', style: ReelForgeTheme.monoSmall),

            const SizedBox(height: 12),
            Text('Fade Out', style: ReelForgeTheme.label),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: clip.fadeOut,
                min: 0,
                max: clip.duration / 2,
                onChanged: onFadeOutChange,
              ),
            ),
            Text('${clip.fadeOut.toStringAsFixed(2)}s', style: ReelForgeTheme.monoSmall),

            // Gain
            const SizedBox(height: 12),
            Text('Gain', style: ReelForgeTheme.label),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: clip.gain,
                min: -24,
                max: 12,
                onChanged: onGainChange,
              ),
            ),
            Text(
              '${clip.gain >= 0 ? '+' : ''}${clip.gain.toStringAsFixed(1)} dB',
              style: ReelForgeTheme.monoSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: ReelForgeTheme.label),
          Text(value, style: ReelForgeTheme.monoSmall),
        ],
      ),
    );
  }
}

// ============ Waveform Painter ============

class _WaveformPainter extends CustomPainter {
  final Float32List? waveform;
  final double zoom;
  final double scrollOffset;
  final double duration;
  final ClipEditorSelection? selection;
  final double fadeIn;
  final double fadeOut;
  final Color color;
  final int channels;

  _WaveformPainter({
    this.waveform,
    required this.zoom,
    required this.scrollOffset,
    required this.duration,
    this.selection,
    required this.fadeIn,
    required this.fadeOut,
    required this.color,
    required this.channels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = ReelForgeTheme.bgDeepest,
    );

    // Grid
    _drawGrid(canvas, size);

    // Center line
    final centerY = size.height / 2;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.1)
        ..strokeWidth = 1,
    );

    // Waveform
    if (waveform != null && waveform!.isNotEmpty) {
      _drawWaveform(canvas, size, centerY);
    }

    // Selection
    if (selection != null && selection!.isValid) {
      _drawSelection(canvas, size);
    }

    // Fades
    _drawFades(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;

    // Determine grid step based on zoom
    double gridStep = 1;
    if (zoom > 200) gridStep = 0.1;
    else if (zoom > 50) gridStep = 0.5;

    final endSecond = scrollOffset + size.width / zoom;

    for (double s = (scrollOffset / gridStep).floor() * gridStep;
        s <= endSecond;
        s += gridStep) {
      final x = (s - scrollOffset) * zoom;
      if (x >= 0 && x <= size.width) {
        gridPaint.color = Colors.white.withValues(
          alpha: s % 1 == 0 ? 0.15 : 0.05,
        );
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
    }
  }

  void _drawWaveform(Canvas canvas, Size size, double centerY) {
    final amplitude = size.height / 2 - 4;
    final samplesPerSecond = waveform!.length / duration;

    final rmsPaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    final peakPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    for (double x = 0; x < size.width; x++) {
      final time = scrollOffset + x / zoom;
      if (time < 0 || time > duration) continue;

      final sampleIndex = (time * samplesPerSecond).floor().clamp(0, waveform!.length - 1);
      final sample = waveform![sampleIndex].abs();

      // Apply fade envelope
      double envelope = 1;
      if (fadeIn > 0 && time < fadeIn) {
        envelope = time / fadeIn;
      } else if (fadeOut > 0 && time > duration - fadeOut) {
        envelope = (duration - time) / fadeOut;
      }

      final peak = sample * envelope;
      final rms = peak * 0.7; // Approximate RMS

      // Draw RMS (inner)
      final rmsHeight = rms * amplitude;
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x, centerY),
          width: 1,
          height: rmsHeight * 2,
        ),
        rmsPaint,
      );

      // Draw peak (outer)
      final peakHeight = peak * amplitude;
      if (peakHeight > rmsHeight) {
        canvas.drawRect(
          Rect.fromLTRB(x, centerY - peakHeight, x + 1, centerY - rmsHeight),
          peakPaint,
        );
        canvas.drawRect(
          Rect.fromLTRB(x, centerY + rmsHeight, x + 1, centerY + peakHeight),
          peakPaint,
        );
      }
    }
  }

  void _drawSelection(Canvas canvas, Size size) {
    final startX = (selection!.start - scrollOffset) * zoom;
    final endX = (selection!.end - scrollOffset) * zoom;

    if (endX > 0 && startX < size.width) {
      // Fill
      canvas.drawRect(
        Rect.fromLTRB(
          startX.clamp(0, size.width),
          0,
          endX.clamp(0, size.width),
          size.height,
        ),
        Paint()..color = ReelForgeTheme.accentCyan.withValues(alpha: 0.2),
      );

      // Borders
      final borderPaint = Paint()
        ..color = ReelForgeTheme.accentCyan
        ..strokeWidth = 2;

      if (startX >= 0 && startX <= size.width) {
        canvas.drawLine(Offset(startX, 0), Offset(startX, size.height), borderPaint);
      }
      if (endX >= 0 && endX <= size.width) {
        canvas.drawLine(Offset(endX, 0), Offset(endX, size.height), borderPaint);
      }
    }
  }

  void _drawFades(Canvas canvas, Size size) {
    // Fade in
    if (fadeIn > 0) {
      final fadeInWidth = (fadeIn - scrollOffset) * zoom;
      if (fadeInWidth > 0) {
        final gradient = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        );

        canvas.drawRect(
          Rect.fromLTWH(0, 0, fadeInWidth.clamp(0, size.width), size.height),
          Paint()..shader = gradient.createShader(
            Rect.fromLTWH(0, 0, fadeInWidth, size.height),
          ),
        );

        // Fade curve
        final path = Path();
        for (double x = 0; x <= fadeInWidth.clamp(0, size.width); x++) {
          final t = x / fadeInWidth;
          final y = size.height - (t * t * size.height);
          if (x == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }

        canvas.drawPath(
          path,
          Paint()
            ..color = ReelForgeTheme.accentCyan
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke,
        );
      }
    }

    // Fade out
    if (fadeOut > 0) {
      final fadeOutStart = (duration - fadeOut - scrollOffset) * zoom;
      final fadeOutEnd = (duration - scrollOffset) * zoom;

      if (fadeOutEnd > 0 && fadeOutStart < size.width) {
        final startX = fadeOutStart.clamp(0.0, size.width);
        final endX = fadeOutEnd.clamp(0.0, size.width);

        final gradient = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.7),
          ],
        );

        canvas.drawRect(
          Rect.fromLTRB(startX, 0, endX, size.height),
          Paint()..shader = gradient.createShader(
            Rect.fromLTRB(startX, 0, endX, size.height),
          ),
        );

        // Fade curve
        final path = Path();
        for (double x = startX; x <= endX; x++) {
          final t = (x - fadeOutStart) / (fadeOutEnd - fadeOutStart);
          final y = t * t * size.height;
          if (x == startX) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }

        canvas.drawPath(
          path,
          Paint()
            ..color = ReelForgeTheme.accentCyan
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      waveform != oldDelegate.waveform ||
      zoom != oldDelegate.zoom ||
      scrollOffset != oldDelegate.scrollOffset ||
      selection != oldDelegate.selection ||
      fadeIn != oldDelegate.fadeIn ||
      fadeOut != oldDelegate.fadeOut;
}
