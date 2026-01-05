/// Clip Editor Widget
///
/// Lower zone component for detailed audio clip editing:
/// - Zoomable waveform display (LOD)
/// - Selection tool for range selection
/// - Draggable fade handles
/// - Clip info sidebar
/// - Audio processing tools
/// - Snap-to-grid editing

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
  final double sourceOffset;
  final double sourceDuration;

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
    this.sourceOffset = 0,
    this.sourceDuration = 0,
  });

  ClipEditorClip copyWith({
    String? id,
    String? name,
    double? duration,
    int? sampleRate,
    int? channels,
    int? bitDepth,
    Float32List? waveform,
    double? fadeIn,
    double? fadeOut,
    double? gain,
    Color? color,
    double? sourceOffset,
    double? sourceDuration,
  }) {
    return ClipEditorClip(
      id: id ?? this.id,
      name: name ?? this.name,
      duration: duration ?? this.duration,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      bitDepth: bitDepth ?? this.bitDepth,
      waveform: waveform ?? this.waveform,
      fadeIn: fadeIn ?? this.fadeIn,
      fadeOut: fadeOut ?? this.fadeOut,
      gain: gain ?? this.gain,
      color: color ?? this.color,
      sourceOffset: sourceOffset ?? this.sourceOffset,
      sourceDuration: sourceDuration ?? this.sourceDuration,
    );
  }
}

/// Selection range in seconds
class ClipEditorSelection {
  final double start;
  final double end;

  const ClipEditorSelection({required this.start, required this.end});

  double get length => end - start;
  bool get isValid => end > start;

  ClipEditorSelection copyWith({double? start, double? end}) {
    return ClipEditorSelection(
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }
}

/// Editor tool types
enum EditorTool {
  select,
  zoom,
  fade,
  cut,
  slip,
}

/// Fade handle being dragged
enum _FadeHandle { none, fadeIn, fadeOut }

// ============ Clip Editor Widget ============

class ClipEditor extends StatefulWidget {
  final ClipEditorClip? clip;
  final ClipEditorSelection? selection;
  final double zoom;
  final double scrollOffset;
  final double playheadPosition;
  final bool snapEnabled;
  final double snapValue;
  final ValueChanged<ClipEditorSelection?>? onSelectionChange;
  final ValueChanged<double>? onZoomChange;
  final ValueChanged<double>? onScrollChange;
  final void Function(String clipId, double fadeIn)? onFadeInChange;
  final void Function(String clipId, double fadeOut)? onFadeOutChange;
  final void Function(String clipId, double gain)? onGainChange;
  final void Function(String clipId)? onNormalize;
  final void Function(String clipId)? onReverse;
  final void Function(String clipId, ClipEditorSelection selection)? onTrimToSelection;
  final void Function(String clipId, double position)? onSplitAtPosition;
  final ValueChanged<double>? onPlayheadChange;

  const ClipEditor({
    super.key,
    this.clip,
    this.selection,
    this.zoom = 100,
    this.scrollOffset = 0,
    this.playheadPosition = 0,
    this.snapEnabled = true,
    this.snapValue = 0.1,
    this.onSelectionChange,
    this.onZoomChange,
    this.onScrollChange,
    this.onFadeInChange,
    this.onFadeOutChange,
    this.onGainChange,
    this.onNormalize,
    this.onReverse,
    this.onTrimToSelection,
    this.onSplitAtPosition,
    this.onPlayheadChange,
  });

  @override
  State<ClipEditor> createState() => _ClipEditorState();
}

class _ClipEditorState extends State<ClipEditor> {
  EditorTool _tool = EditorTool.select;
  bool _isDragging = false;
  double? _dragStart;
  _FadeHandle _draggingFade = _FadeHandle.none;
  double _hoverX = -1;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ReelForgeTheme.bgMid,
        border: Border(
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
          Icon(Icons.edit, size: 14, color: ReelForgeTheme.accentBlue),
          const SizedBox(width: 8),
          Text(
            widget.clip?.name ?? 'Clip Editor',
            style: ReelForgeTheme.h3,
          ),
          if (widget.clip != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: ReelForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                _formatTime(widget.clip!.duration),
                style: ReelForgeTheme.monoSmall,
              ),
            ),
          ],
          const Spacer(),
          _buildToolbar(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final hasSelection = widget.selection?.isValid ?? false;
    final hasClip = widget.clip != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tools
        _ToolButton(
          icon: Icons.select_all,
          label: 'Selection (1)',
          isActive: _tool == EditorTool.select,
          onTap: () => setState(() => _tool = EditorTool.select),
        ),
        _ToolButton(
          icon: Icons.zoom_in,
          label: 'Zoom (2)',
          isActive: _tool == EditorTool.zoom,
          onTap: () => setState(() => _tool = EditorTool.zoom),
        ),
        _ToolButton(
          icon: Icons.show_chart,
          label: 'Fade (3)',
          isActive: _tool == EditorTool.fade,
          onTap: () => setState(() => _tool = EditorTool.fade),
        ),
        _ToolButton(
          icon: Icons.content_cut,
          label: 'Cut (4)',
          isActive: _tool == EditorTool.cut,
          onTap: () => setState(() => _tool = EditorTool.cut),
        ),
        _ToolButton(
          icon: Icons.swap_horiz,
          label: 'Slip Edit (5)',
          isActive: _tool == EditorTool.slip,
          onTap: () => setState(() => _tool = EditorTool.slip),
        ),
        const SizedBox(width: 8),
        Container(width: 1, height: 16, color: ReelForgeTheme.borderSubtle),
        const SizedBox(width: 8),
        // Zoom controls
        _ToolButton(
          icon: Icons.zoom_out,
          label: 'Zoom Out',
          onTap: () => widget.onZoomChange?.call((widget.zoom * 0.8).clamp(10, 500)),
        ),
        Text('${widget.zoom.toInt()}%', style: ReelForgeTheme.monoSmall),
        _ToolButton(
          icon: Icons.zoom_in,
          label: 'Zoom In',
          onTap: () => widget.onZoomChange?.call((widget.zoom * 1.25).clamp(10, 500)),
        ),
        const SizedBox(width: 8),
        Container(width: 1, height: 16, color: ReelForgeTheme.borderSubtle),
        const SizedBox(width: 8),
        // Actions
        _ToolButton(
          icon: Icons.vertical_align_center,
          label: 'Normalize',
          isEnabled: hasClip,
          onTap: hasClip
              ? () => widget.onNormalize?.call(widget.clip!.id)
              : null,
        ),
        _ToolButton(
          icon: Icons.swap_horiz,
          label: 'Reverse',
          isEnabled: hasClip,
          onTap: hasClip
              ? () => widget.onReverse?.call(widget.clip!.id)
              : null,
        ),
        _ToolButton(
          icon: Icons.crop,
          label: 'Trim to Selection',
          isEnabled: hasSelection && hasClip,
          onTap: hasSelection && hasClip
              ? () => widget.onTrimToSelection?.call(widget.clip!.id, widget.selection!)
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
          Icon(
            Icons.graphic_eq,
            size: 48,
            color: ReelForgeTheme.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            'Select a clip to edit',
            style: ReelForgeTheme.body.copyWith(color: ReelForgeTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Double-click a clip on the timeline',
            style: ReelForgeTheme.bodySmall.copyWith(color: ReelForgeTheme.textTertiary),
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
          child: Column(
            children: [
              // Time ruler
              _buildTimeRuler(),
              // Waveform
              Expanded(child: _buildWaveformArea()),
              // Overview
              _buildOverview(),
            ],
          ),
        ),
        // Info sidebar
        SizedBox(
          width: 200,
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

  Widget _buildTimeRuler() {
    return Container(
      height: 24,
      decoration: const BoxDecoration(
        color: ReelForgeTheme.bgSurface,
        border: Border(
          bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            painter: _TimeRulerPainter(
              zoom: widget.zoom,
              scrollOffset: widget.scrollOffset,
              duration: widget.clip!.duration,
              width: constraints.maxWidth,
              snapEnabled: widget.snapEnabled,
              snapValue: widget.snapValue,
            ),
            size: Size(constraints.maxWidth, 24),
          );
        },
      ),
    );
  }

  Widget _buildWaveformArea() {
    return MouseRegion(
      onHover: (event) {
        setState(() => _hoverX = event.localPosition.dx);
      },
      onExit: (_) {
        setState(() => _hoverX = -1);
      },
      cursor: _getCursor(),
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            _handleWheel(event);
          }
        },
        child: GestureDetector(
          onTapDown: _handleTapDown,
          onPanStart: _handlePanStart,
          onPanUpdate: _handlePanUpdate,
          onPanEnd: _handlePanEnd,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  // Waveform canvas
                  CustomPaint(
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
                      hoverX: _hoverX,
                    ),
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                  ),
                  // Fade handles
                  _buildFadeHandles(constraints),
                  // Playhead
                  _buildPlayhead(constraints),
                  // Hover info
                  if (_hoverX >= 0 && _tool != EditorTool.fade)
                    _buildHoverInfo(constraints),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFadeHandles(BoxConstraints constraints) {
    final fadeInX = widget.clip!.fadeIn * widget.zoom;
    final fadeOutX = constraints.maxWidth - widget.clip!.fadeOut * widget.zoom;

    return Stack(
      children: [
        // Fade in handle
        if (fadeInX > 0 && fadeInX < constraints.maxWidth)
          Positioned(
            left: fadeInX - 8,
            top: 0,
            child: GestureDetector(
              onHorizontalDragStart: (_) {
                setState(() => _draggingFade = _FadeHandle.fadeIn);
              },
              onHorizontalDragUpdate: (details) {
                final newX = fadeInX + details.delta.dx;
                final newFadeIn = (newX / widget.zoom).clamp(0.0, widget.clip!.duration / 2);
                widget.onFadeInChange?.call(widget.clip!.id, _snapTime(newFadeIn));
              },
              onHorizontalDragEnd: (_) {
                setState(() => _draggingFade = _FadeHandle.none);
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(
                  width: 16,
                  height: 60,
                  decoration: BoxDecoration(
                    color: _draggingFade == _FadeHandle.fadeIn
                        ? ReelForgeTheme.accentCyan
                        : ReelForgeTheme.accentCyan.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                        color: ReelForgeTheme.accentCyan.withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        // Fade out handle
        if (fadeOutX > 0 && fadeOutX < constraints.maxWidth)
          Positioned(
            left: fadeOutX - 8,
            top: 0,
            child: GestureDetector(
              onHorizontalDragStart: (_) {
                setState(() => _draggingFade = _FadeHandle.fadeOut);
              },
              onHorizontalDragUpdate: (details) {
                final newX = fadeOutX + details.delta.dx;
                final widthFromEnd = constraints.maxWidth - newX;
                final newFadeOut = (widthFromEnd / widget.zoom).clamp(0.0, widget.clip!.duration / 2);
                widget.onFadeOutChange?.call(widget.clip!.id, _snapTime(newFadeOut));
              },
              onHorizontalDragEnd: (_) {
                setState(() => _draggingFade = _FadeHandle.none);
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(
                  width: 16,
                  height: 60,
                  decoration: BoxDecoration(
                    color: _draggingFade == _FadeHandle.fadeOut
                        ? ReelForgeTheme.accentCyan
                        : ReelForgeTheme.accentCyan.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                        color: ReelForgeTheme.accentCyan.withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.chevron_left,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlayhead(BoxConstraints constraints) {
    final playheadX = (widget.playheadPosition - widget.scrollOffset) * widget.zoom;
    if (playheadX < 0 || playheadX > constraints.maxWidth) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: playheadX - 1,
      top: 0,
      bottom: 0,
      child: Container(
        width: 2,
        color: ReelForgeTheme.accentRed,
      ),
    );
  }

  Widget _buildHoverInfo(BoxConstraints constraints) {
    final time = widget.scrollOffset + _hoverX / widget.zoom;
    if (time < 0 || time > widget.clip!.duration) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: _hoverX + 10,
      top: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgSurface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: ReelForgeTheme.borderSubtle),
        ),
        child: Text(
          _formatTime(time),
          style: ReelForgeTheme.monoSmall,
        ),
      ),
    );
  }

  Widget _buildOverview() {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: ReelForgeTheme.bgDeep,
        border: Border(
          top: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onTapDown: (details) {
              // Click to scroll to position
              final fraction = details.localPosition.dx / constraints.maxWidth;
              final time = fraction * widget.clip!.duration;
              widget.onScrollChange?.call(time.clamp(0, widget.clip!.duration - constraints.maxWidth / widget.zoom));
            },
            onHorizontalDragUpdate: (details) {
              final delta = details.delta.dx / constraints.maxWidth * widget.clip!.duration;
              final newOffset = (widget.scrollOffset + delta)
                  .clamp(0.0, widget.clip!.duration - constraints.maxWidth / widget.zoom);
              widget.onScrollChange?.call(newOffset);
            },
            child: CustomPaint(
              painter: _OverviewPainter(
                waveform: widget.clip!.waveform,
                duration: widget.clip!.duration,
                viewportStart: widget.scrollOffset,
                viewportEnd: widget.scrollOffset + constraints.maxWidth / widget.zoom,
                color: widget.clip!.color ?? ReelForgeTheme.accentBlue,
                selection: widget.selection,
              ),
              size: Size(constraints.maxWidth, 40),
            ),
          );
        },
      ),
    );
  }

  MouseCursor _getCursor() {
    switch (_tool) {
      case EditorTool.select:
        return SystemMouseCursors.text;
      case EditorTool.zoom:
        return SystemMouseCursors.zoomIn;
      case EditorTool.fade:
        return SystemMouseCursors.resizeColumn;
      case EditorTool.cut:
        return SystemMouseCursors.click;
      case EditorTool.slip:
        return SystemMouseCursors.resizeLeftRight;
    }
  }

  void _handleWheel(PointerScrollEvent event) {
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      // Zoom (centered on mouse position)
      final mouseTime = widget.scrollOffset + event.localPosition.dx / widget.zoom;
      final delta = event.scrollDelta.dy > 0 ? 0.85 : 1.18;
      final newZoom = (widget.zoom * delta).clamp(10.0, 500.0);

      // Adjust scroll to keep mouse position stable
      final newScrollOffset = mouseTime - event.localPosition.dx / newZoom;

      widget.onZoomChange?.call(newZoom);
      widget.onScrollChange?.call(newScrollOffset.clamp(0, widget.clip!.duration));
    } else if (HardwareKeyboard.instance.isShiftPressed) {
      // Horizontal scroll with shift
      final delta = event.scrollDelta.dy / widget.zoom;
      final newOffset = (widget.scrollOffset + delta).clamp(0.0, widget.clip!.duration);
      widget.onScrollChange?.call(newOffset);
    } else {
      // Normal scroll
      final delta = event.scrollDelta.dx != 0
          ? event.scrollDelta.dx
          : event.scrollDelta.dy;
      final newOffset = (widget.scrollOffset + delta / widget.zoom)
          .clamp(0.0, widget.clip!.duration);
      widget.onScrollChange?.call(newOffset);
    }
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.clip == null) return;

    final time = widget.scrollOffset + details.localPosition.dx / widget.zoom;

    switch (_tool) {
      case EditorTool.cut:
        widget.onSplitAtPosition?.call(widget.clip!.id, _snapTime(time));
        break;
      case EditorTool.zoom:
        // Zoom in on click, zoom out on alt+click
        if (HardwareKeyboard.instance.isAltPressed) {
          widget.onZoomChange?.call((widget.zoom * 0.7).clamp(10, 500));
        } else {
          widget.onZoomChange?.call((widget.zoom * 1.4).clamp(10, 500));
        }
        break;
      default:
        // Click to set playhead
        widget.onPlayheadChange?.call(_snapTime(time.clamp(0, widget.clip!.duration)));
        break;
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

  double _snapTime(double time) {
    if (!widget.snapEnabled || widget.snapValue <= 0) return time;
    return (time / widget.snapValue).round() * widget.snapValue;
  }

  String _formatTime(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = seconds % 60;
    return '$mins:${secs.toStringAsFixed(3).padLeft(6, '0')}';
  }
}

// ============ Tool Button ============

class _ToolButton extends StatelessWidget {
  final IconData icon;
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
            border: isActive
                ? Border.all(color: ReelForgeTheme.accentBlue.withValues(alpha: 0.4))
                : null,
          ),
          child: Center(
            child: Icon(
              icon,
              size: 16,
              color: isEnabled
                  ? (isActive ? ReelForgeTheme.accentBlue : ReelForgeTheme.textSecondary)
                  : ReelForgeTheme.textTertiary.withValues(alpha: 0.5),
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

  String _formatSamples(double seconds, int sampleRate) {
    return '${(seconds * sampleRate).round()} samples';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: ReelForgeTheme.bgDeep,
        border: Border(
          left: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section: Clip Info
            _SectionHeader(title: 'Clip Info'),
            const SizedBox(height: 8),
            _InfoRow(label: 'Duration', value: _formatTime(clip.duration)),
            _InfoRow(label: 'Sample Rate', value: '${clip.sampleRate ~/ 1000} kHz'),
            _InfoRow(label: 'Channels', value: clip.channels == 2 ? 'Stereo' : 'Mono'),
            _InfoRow(label: 'Bit Depth', value: '${clip.bitDepth}-bit'),
            _InfoRow(
              label: 'Samples',
              value: _formatSamples(clip.duration, clip.sampleRate),
            ),

            // Section: Selection
            if (selection != null && selection!.isValid) ...[
              const Divider(height: 24, color: ReelForgeTheme.borderSubtle),
              _SectionHeader(title: 'Selection'),
              const SizedBox(height: 8),
              _InfoRow(
                label: 'Start',
                value: _formatTime(selection!.start),
              ),
              _InfoRow(
                label: 'End',
                value: _formatTime(selection!.end),
              ),
              _InfoRow(
                label: 'Length',
                value: _formatTime(selection!.length),
              ),
              _InfoRow(
                label: 'Samples',
                value: _formatSamples(selection!.length, clip.sampleRate),
              ),
            ],

            // Section: Fades
            const Divider(height: 24, color: ReelForgeTheme.borderSubtle),
            _SectionHeader(title: 'Fades'),
            const SizedBox(height: 8),

            Text('Fade In', style: ReelForgeTheme.label),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: ReelForgeTheme.accentCyan,
                      inactiveTrackColor: ReelForgeTheme.borderSubtle,
                      thumbColor: ReelForgeTheme.accentCyan,
                    ),
                    child: Slider(
                      value: clip.fadeIn,
                      min: 0,
                      max: clip.duration / 2,
                      onChanged: onFadeInChange,
                    ),
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Text(
                    '${(clip.fadeIn * 1000).toStringAsFixed(0)}ms',
                    style: ReelForgeTheme.monoSmall,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            Text('Fade Out', style: ReelForgeTheme.label),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: ReelForgeTheme.accentCyan,
                      inactiveTrackColor: ReelForgeTheme.borderSubtle,
                      thumbColor: ReelForgeTheme.accentCyan,
                    ),
                    child: Slider(
                      value: clip.fadeOut,
                      min: 0,
                      max: clip.duration / 2,
                      onChanged: onFadeOutChange,
                    ),
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Text(
                    '${(clip.fadeOut * 1000).toStringAsFixed(0)}ms',
                    style: ReelForgeTheme.monoSmall,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),

            // Section: Gain
            const Divider(height: 24, color: ReelForgeTheme.borderSubtle),
            _SectionHeader(title: 'Gain'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: clip.gain >= 0
                          ? ReelForgeTheme.accentGreen
                          : ReelForgeTheme.accentRed,
                      inactiveTrackColor: ReelForgeTheme.borderSubtle,
                      thumbColor: clip.gain >= 0
                          ? ReelForgeTheme.accentGreen
                          : ReelForgeTheme.accentRed,
                    ),
                    child: Slider(
                      value: clip.gain,
                      min: -24,
                      max: 12,
                      onChanged: onGainChange,
                    ),
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    '${clip.gain >= 0 ? '+' : ''}${clip.gain.toStringAsFixed(1)} dB',
                    style: ReelForgeTheme.monoSmall.copyWith(
                      color: clip.gain >= 0
                          ? ReelForgeTheme.accentGreen
                          : ReelForgeTheme.accentRed,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: ReelForgeTheme.h3.copyWith(
        fontSize: 11,
        color: ReelForgeTheme.textSecondary,
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
      padding: const EdgeInsets.only(bottom: 6),
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

// ============ Time Ruler Painter ============

class _TimeRulerPainter extends CustomPainter {
  final double zoom;
  final double scrollOffset;
  final double duration;
  final double width;
  final bool snapEnabled;
  final double snapValue;

  _TimeRulerPainter({
    required this.zoom,
    required this.scrollOffset,
    required this.duration,
    required this.width,
    required this.snapEnabled,
    required this.snapValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = ReelForgeTheme.bgSurface,
    );

    // Determine tick spacing based on zoom
    double majorTickInterval = 1.0; // seconds
    if (zoom > 200) majorTickInterval = 0.1;
    else if (zoom > 100) majorTickInterval = 0.5;
    else if (zoom < 30) majorTickInterval = 5.0;
    else if (zoom < 15) majorTickInterval = 10.0;

    final minorTickInterval = majorTickInterval / 4;

    // Draw ticks
    final endTime = scrollOffset + width / zoom;
    final startTick = (scrollOffset / minorTickInterval).floor() * minorTickInterval;

    for (double t = startTick; t <= endTime && t <= duration; t += minorTickInterval) {
      final x = (t - scrollOffset) * zoom;
      if (x < 0 || x > width) continue;

      final isMajor = (t % majorTickInterval).abs() < 0.001 ||
          (majorTickInterval - (t % majorTickInterval)).abs() < 0.001;

      final tickHeight = isMajor ? 12.0 : 6.0;
      final tickColor = isMajor
          ? ReelForgeTheme.textSecondary
          : ReelForgeTheme.borderSubtle;

      canvas.drawLine(
        Offset(x, size.height - tickHeight),
        Offset(x, size.height),
        Paint()
          ..color = tickColor
          ..strokeWidth = 1,
      );

      // Label for major ticks
      if (isMajor) {
        final label = _formatRulerTime(t);
        textPainter.text = TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 10,
            color: ReelForgeTheme.textTertiary,
            fontFamily: 'monospace',
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, 2),
        );
      }
    }

    // Draw snap grid indicator if enabled
    if (snapEnabled && snapValue > 0) {
      final snapIndicator = '⊞ ${snapValue}s';
      textPainter.text = TextSpan(
        text: snapIndicator,
        style: TextStyle(
          fontSize: 9,
          color: ReelForgeTheme.accentBlue,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(width - textPainter.width - 4, 2),
      );
    }
  }

  String _formatRulerTime(double seconds) {
    if (seconds < 60) {
      return '${seconds.toStringAsFixed(seconds < 1 ? 2 : 1)}s';
    }
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).toStringAsFixed(0);
    return '$mins:${secs.padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(_TimeRulerPainter oldDelegate) =>
      zoom != oldDelegate.zoom ||
      scrollOffset != oldDelegate.scrollOffset ||
      snapEnabled != oldDelegate.snapEnabled ||
      snapValue != oldDelegate.snapValue;
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
  final double hoverX;

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
    required this.hoverX,
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

    // Selection
    if (selection != null && selection!.isValid) {
      _drawSelection(canvas, size);
    }

    // Center line (0 dB)
    final centerY = size.height / 2;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()
        ..color = ReelForgeTheme.borderSubtle.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );

    // Waveform
    if (waveform != null && waveform!.isNotEmpty) {
      _drawWaveform(canvas, size, centerY);
    } else {
      _drawDemoWaveform(canvas, size, centerY);
    }

    // Fades overlay
    _drawFades(canvas, size);

    // Hover line
    if (hoverX >= 0 && hoverX <= size.width) {
      canvas.drawLine(
        Offset(hoverX, 0),
        Offset(hoverX, size.height),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.3)
          ..strokeWidth = 1,
      );
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = ReelForgeTheme.borderSubtle.withValues(alpha: 0.15)
      ..strokeWidth = 1;

    // Vertical grid (time)
    double gridStep = 1;
    if (zoom > 200) gridStep = 0.1;
    else if (zoom > 50) gridStep = 0.5;

    final endSecond = scrollOffset + size.width / zoom;

    for (double s = (scrollOffset / gridStep).floor() * gridStep;
        s <= endSecond && s <= duration;
        s += gridStep) {
      final x = (s - scrollOffset) * zoom;
      if (x >= 0 && x <= size.width) {
        gridPaint.color = ReelForgeTheme.borderSubtle.withValues(
          alpha: s % 1 == 0 ? 0.25 : 0.1,
        );
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
    }

    // Horizontal grid (dB levels)
    final levels = [-6.0, -12.0, -18.0];
    for (final db in levels) {
      final y = size.height / 2 * (1 - math.pow(10, db / 20));
      canvas.drawLine(
        Offset(0, size.height / 2 - y),
        Offset(size.width, size.height / 2 - y),
        Paint()..color = ReelForgeTheme.borderSubtle.withValues(alpha: 0.1),
      );
      canvas.drawLine(
        Offset(0, size.height / 2 + y),
        Offset(size.width, size.height / 2 + y),
        Paint()..color = ReelForgeTheme.borderSubtle.withValues(alpha: 0.1),
      );
    }
  }

  void _drawWaveform(Canvas canvas, Size size, double centerY) {
    final amplitude = size.height / 2 - 4;
    final samplesPerSecond = waveform!.length / duration;

    final rmsPaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    final peakPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
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
      final rms = peak * 0.7;

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

  void _drawDemoWaveform(Canvas canvas, Size size, double centerY) {
    // Generate demo waveform on the fly
    final amplitude = size.height / 2 - 4;

    final rmsPaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    final peakPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    for (double x = 0; x < size.width; x++) {
      final time = scrollOffset + x / zoom;
      if (time < 0 || time > duration) continue;

      // Generate procedural waveform
      final t = time * 2 * math.pi;
      final sample = (math.sin(t * 2) * 0.3 +
              math.sin(t * 5) * 0.2 +
              math.sin(t * 11) * 0.15 +
              (math.Random((x * 1000).toInt()).nextDouble() - 0.5) * 0.2)
          .abs()
          .clamp(0.0, 1.0);

      // Apply fade envelope
      double envelope = 1;
      if (fadeIn > 0 && time < fadeIn) {
        envelope = time / fadeIn;
      } else if (fadeOut > 0 && time > duration - fadeOut) {
        envelope = (duration - time) / fadeOut;
      }

      final peak = sample * envelope;
      final rms = peak * 0.7;

      final rmsHeight = rms * amplitude;
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x, centerY),
          width: 1,
          height: rmsHeight * 2,
        ),
        rmsPaint,
      );

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
        Paint()..color = ReelForgeTheme.accentCyan.withValues(alpha: 0.15),
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
      final fadeInWidth = fadeIn * zoom;
      if (fadeInWidth > 0 && scrollOffset < fadeIn) {
        final startX = math.max(0.0, -scrollOffset * zoom);
        final endX = math.min(fadeInWidth, size.width);

        // Darken overlay
        final gradient = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.black.withValues(alpha: 0.5),
            Colors.transparent,
          ],
        );

        canvas.drawRect(
          Rect.fromLTRB(startX, 0, endX, size.height),
          Paint()
            ..shader = gradient.createShader(
              Rect.fromLTRB(startX, 0, endX, size.height),
            ),
        );

        // Fade curve
        final path = Path();
        for (double x = startX; x <= endX; x += 2) {
          final t = x / fadeInWidth;
          // S-curve (ease in-out)
          final curve = t * t * (3 - 2 * t);
          final y = size.height - (curve * size.height);
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
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      }
    }

    // Fade out
    if (fadeOut > 0) {
      final fadeOutStart = duration - fadeOut;
      final fadeOutStartX = (fadeOutStart - scrollOffset) * zoom;
      final fadeOutEndX = (duration - scrollOffset) * zoom;

      if (fadeOutEndX > 0 && fadeOutStartX < size.width) {
        final startX = fadeOutStartX.clamp(0.0, size.width);
        final endX = fadeOutEndX.clamp(0.0, size.width);

        // Darken overlay
        final gradient = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.5),
          ],
        );

        canvas.drawRect(
          Rect.fromLTRB(startX, 0, endX, size.height),
          Paint()
            ..shader = gradient.createShader(
              Rect.fromLTRB(startX, 0, endX, size.height),
            ),
        );

        // Fade curve
        final path = Path();
        final fadeWidth = endX - startX;
        for (double x = startX; x <= endX; x += 2) {
          final t = (x - startX) / fadeWidth;
          // S-curve (ease in-out)
          final curve = t * t * (3 - 2 * t);
          final y = curve * size.height;
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
            ..strokeWidth = 2
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
      fadeOut != oldDelegate.fadeOut ||
      hoverX != oldDelegate.hoverX;
}

// ============ Overview Painter ============

class _OverviewPainter extends CustomPainter {
  final Float32List? waveform;
  final double duration;
  final double viewportStart;
  final double viewportEnd;
  final Color color;
  final ClipEditorSelection? selection;

  _OverviewPainter({
    this.waveform,
    required this.duration,
    required this.viewportStart,
    required this.viewportEnd,
    required this.color,
    this.selection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = ReelForgeTheme.bgDeep,
    );

    // Draw mini waveform
    final centerY = size.height / 2;
    final amplitude = size.height / 2 - 2;

    if (waveform != null && waveform!.isNotEmpty) {
      for (double x = 0; x < size.width; x++) {
        final time = (x / size.width) * duration;
        final sampleIndex = (time * waveform!.length / duration)
            .floor()
            .clamp(0, waveform!.length - 1);
        final sample = waveform![sampleIndex].abs();
        final height = sample * amplitude;

        canvas.drawLine(
          Offset(x, centerY - height),
          Offset(x, centerY + height),
          Paint()
            ..color = color.withValues(alpha: 0.5)
            ..strokeWidth = 1,
        );
      }
    } else {
      // Demo waveform
      for (double x = 0; x < size.width; x++) {
        final t = (x / size.width) * duration * 2 * math.pi;
        final sample = (math.sin(t * 2) * 0.3 + math.sin(t * 5) * 0.2)
            .abs()
            .clamp(0.0, 1.0);
        final height = sample * amplitude;

        canvas.drawLine(
          Offset(x, centerY - height),
          Offset(x, centerY + height),
          Paint()
            ..color = color.withValues(alpha: 0.5)
            ..strokeWidth = 1,
        );
      }
    }

    // Selection highlight
    if (selection != null && selection!.isValid) {
      final startX = (selection!.start / duration) * size.width;
      final endX = (selection!.end / duration) * size.width;
      canvas.drawRect(
        Rect.fromLTRB(startX, 0, endX, size.height),
        Paint()..color = ReelForgeTheme.accentCyan.withValues(alpha: 0.2),
      );
    }

    // Viewport indicator
    final vpStartX = (viewportStart / duration) * size.width;
    final vpEndX = (viewportEnd / duration).clamp(0, 1) * size.width;

    // Darken outside viewport
    canvas.drawRect(
      Rect.fromLTRB(0, 0, vpStartX, size.height),
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );
    canvas.drawRect(
      Rect.fromLTRB(vpEndX, 0, size.width, size.height),
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );

    // Viewport border
    canvas.drawRect(
      Rect.fromLTRB(vpStartX, 0, vpEndX, size.height),
      Paint()
        ..color = ReelForgeTheme.accentBlue
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_OverviewPainter oldDelegate) =>
      viewportStart != oldDelegate.viewportStart ||
      viewportEnd != oldDelegate.viewportEnd ||
      selection != oldDelegate.selection;
}

// ============ Connected Clip Editor (uses Provider) ============

/// Widget that connects ClipEditor to the selected clip from timeline
class ConnectedClipEditor extends StatefulWidget {
  final String? selectedClipId;
  final String? clipName;
  final double? clipDuration;
  final Float32List? clipWaveform;
  final double fadeIn;
  final double fadeOut;
  final double gain;
  final Color? clipColor;
  final double playheadPosition;
  final bool snapEnabled;
  final double snapValue;
  final void Function(String clipId, double fadeIn)? onFadeInChange;
  final void Function(String clipId, double fadeOut)? onFadeOutChange;
  final void Function(String clipId, double gain)? onGainChange;
  final void Function(String clipId)? onNormalize;
  final void Function(String clipId)? onReverse;
  final void Function(String clipId, ClipEditorSelection selection)? onTrimToSelection;
  final void Function(String clipId, double position)? onSplitAtPosition;
  final ValueChanged<double>? onPlayheadChange;

  const ConnectedClipEditor({
    super.key,
    this.selectedClipId,
    this.clipName,
    this.clipDuration,
    this.clipWaveform,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.gain = 0,
    this.clipColor,
    this.playheadPosition = 0,
    this.snapEnabled = true,
    this.snapValue = 0.1,
    this.onFadeInChange,
    this.onFadeOutChange,
    this.onGainChange,
    this.onNormalize,
    this.onReverse,
    this.onTrimToSelection,
    this.onSplitAtPosition,
    this.onPlayheadChange,
  });

  @override
  State<ConnectedClipEditor> createState() => _ConnectedClipEditorState();
}

class _ConnectedClipEditorState extends State<ConnectedClipEditor> {
  double _zoom = 100;
  double _scrollOffset = 0;
  ClipEditorSelection? _selection;

  @override
  Widget build(BuildContext context) {
    final clip = widget.selectedClipId != null && widget.clipDuration != null
        ? ClipEditorClip(
            id: widget.selectedClipId!,
            name: widget.clipName ?? 'Untitled',
            duration: widget.clipDuration!,
            waveform: widget.clipWaveform,
            fadeIn: widget.fadeIn,
            fadeOut: widget.fadeOut,
            gain: widget.gain,
            color: widget.clipColor,
          )
        : null;

    return ClipEditor(
      clip: clip,
      selection: _selection,
      zoom: _zoom,
      scrollOffset: _scrollOffset,
      playheadPosition: widget.playheadPosition,
      snapEnabled: widget.snapEnabled,
      snapValue: widget.snapValue,
      onSelectionChange: (sel) => setState(() => _selection = sel),
      onZoomChange: (z) => setState(() => _zoom = z),
      onScrollChange: (o) => setState(() => _scrollOffset = o),
      onFadeInChange: widget.onFadeInChange,
      onFadeOutChange: widget.onFadeOutChange,
      onGainChange: widget.onGainChange,
      onNormalize: widget.onNormalize,
      onReverse: widget.onReverse,
      onTrimToSelection: widget.onTrimToSelection,
      onSplitAtPosition: widget.onSplitAtPosition,
      onPlayheadChange: widget.onPlayheadChange,
    );
  }
}
