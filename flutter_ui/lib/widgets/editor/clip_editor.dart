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
import '../../models/middleware_models.dart'; // For FadeCurve enum

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
  final FadeCurve fadeInCurve;
  final FadeCurve fadeOutCurve;
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
    this.fadeInCurve = FadeCurve.linear,
    this.fadeOutCurve = FadeCurve.linear,
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
    FadeCurve? fadeInCurve,
    FadeCurve? fadeOutCurve,
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
      fadeInCurve: fadeInCurve ?? this.fadeInCurve,
      fadeOutCurve: fadeOutCurve ?? this.fadeOutCurve,
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
  final void Function(String clipId, FadeCurve curve)? onFadeInCurveChange;
  final void Function(String clipId, FadeCurve curve)? onFadeOutCurveChange;
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
    this.onFadeInCurveChange,
    this.onFadeOutCurveChange,
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
  final FocusNode _focusNode = FocusNode();
  double _containerWidth = 0;

  @override
  void initState() {
    super.initState();
    // Request focus when clip is loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.clip != null && mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(ClipEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Request focus when a new clip is selected
    if (widget.clip != null && oldWidget.clip?.id != widget.clip?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.clip != null,
      onKeyEvent: (node, event) {
        _handleKeyEvent(event);
        // Consume zoom and fade keys
        final isZoomKey = event.logicalKey == LogicalKeyboardKey.keyG ||
            event.logicalKey == LogicalKeyboardKey.keyH;
        final isFadeKey = event.logicalKey == LogicalKeyboardKey.bracketLeft ||
            event.logicalKey == LogicalKeyboardKey.bracketRight;
        final isToolKey = event.logicalKey == LogicalKeyboardKey.digit1 ||
            event.logicalKey == LogicalKeyboardKey.digit2 ||
            event.logicalKey == LogicalKeyboardKey.digit3 ||
            event.logicalKey == LogicalKeyboardKey.digit4 ||
            event.logicalKey == LogicalKeyboardKey.digit5;
        if (isZoomKey || isFadeKey || isToolKey) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _focusNode.requestFocus(),
        child: Container(
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
        ),
      ),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    // No clip = no keyboard handling (except tool shortcuts)
    final clip = widget.clip;

    // G/H zoom and [ ] fade - allow repeat (hold key for continuous adjustment)
    final isZoomKey = event.logicalKey == LogicalKeyboardKey.keyG ||
        event.logicalKey == LogicalKeyboardKey.keyH;
    final isFadeKey = event.logicalKey == LogicalKeyboardKey.bracketLeft ||
        event.logicalKey == LogicalKeyboardKey.bracketRight;

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    // Only allow repeat for zoom and fade keys
    if (event is KeyRepeatEvent && !isZoomKey && !isFadeKey) return;

    debugPrint('[ClipEditor] Key: ${event.logicalKey.keyLabel}');

    // G - zoom out (center-screen anchor)
    if (event.logicalKey == LogicalKeyboardKey.keyG && clip != null) {
      final centerX = _containerWidth / 2;
      final centerTime = widget.scrollOffset + centerX / widget.zoom;
      final newZoom = (widget.zoom * 0.92).clamp(5.0, 500.0);
      final newScrollOffset = centerTime - centerX / newZoom;
      widget.onZoomChange?.call(newZoom);
      widget.onScrollChange?.call(newScrollOffset.clamp(0.0,
          (clip.duration - _containerWidth / newZoom).clamp(0.0, double.infinity)));
    }

    // H - zoom in (center-screen anchor)
    if (event.logicalKey == LogicalKeyboardKey.keyH && clip != null) {
      final centerX = _containerWidth / 2;
      final centerTime = widget.scrollOffset + centerX / widget.zoom;
      final newZoom = (widget.zoom * 1.08).clamp(5.0, 500.0);
      final newScrollOffset = centerTime - centerX / newZoom;
      widget.onZoomChange?.call(newZoom);
      widget.onScrollChange?.call(newScrollOffset.clamp(0.0,
          (clip.duration - _containerWidth / newZoom).clamp(0.0, double.infinity)));
    }

    // [ and ] keys - fade nudge
    if (clip != null) {
      final fadeNudgeAmount = HardwareKeyboard.instance.isShiftPressed
          ? 0.01  // 10ms fine control
          : 0.05; // 50ms normal

      // [ key - decrease fade in OR increase fade out
      if (event.logicalKey == LogicalKeyboardKey.bracketLeft) {
        if (HardwareKeyboard.instance.isAltPressed) {
          // Alt+[ = increase fade out
          final newFadeOut = (clip.fadeOut + fadeNudgeAmount)
              .clamp(0.0, clip.duration * 0.5);
          widget.onFadeOutChange?.call(clip.id, newFadeOut);
        } else {
          // [ = decrease fade in
          final newFadeIn = (clip.fadeIn - fadeNudgeAmount)
              .clamp(0.0, clip.duration * 0.5);
          widget.onFadeInChange?.call(clip.id, newFadeIn);
        }
      }

      // ] key - increase fade in OR decrease fade out
      if (event.logicalKey == LogicalKeyboardKey.bracketRight) {
        if (HardwareKeyboard.instance.isAltPressed) {
          // Alt+] = decrease fade out
          final newFadeOut = (clip.fadeOut - fadeNudgeAmount)
              .clamp(0.0, clip.duration * 0.5);
          widget.onFadeOutChange?.call(clip.id, newFadeOut);
        } else {
          // ] = increase fade in
          final newFadeIn = (clip.fadeIn + fadeNudgeAmount)
              .clamp(0.0, clip.duration * 0.5);
          widget.onFadeInChange?.call(clip.id, newFadeIn);
        }
      }
    }

    // Tool shortcuts (work without clip)
    if (event.logicalKey == LogicalKeyboardKey.digit1) {
      setState(() => _tool = EditorTool.select);
    }
    if (event.logicalKey == LogicalKeyboardKey.digit2) {
      setState(() => _tool = EditorTool.zoom);
    }
    if (event.logicalKey == LogicalKeyboardKey.digit3) {
      setState(() => _tool = EditorTool.fade);
    }
    if (event.logicalKey == LogicalKeyboardKey.digit4) {
      setState(() => _tool = EditorTool.cut);
    }
    if (event.logicalKey == LogicalKeyboardKey.digit5) {
      setState(() => _tool = EditorTool.slip);
    }
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
          onTap: () => widget.onZoomChange?.call((widget.zoom * 0.8).clamp(1, 500)),
        ),
        Text('${widget.zoom.toInt()}%', style: ReelForgeTheme.monoSmall),
        _ToolButton(
          icon: Icons.zoom_in,
          label: 'Zoom In',
          onTap: () => widget.onZoomChange?.call((widget.zoom * 1.25).clamp(1, 500)),
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
            onFadeInCurveChange: (curve) {
              if (curve != null) {
                widget.onFadeInCurveChange?.call(widget.clip!.id, curve);
              }
            },
            onFadeOutCurveChange: (curve) {
              if (curve != null) {
                widget.onFadeOutCurveChange?.call(widget.clip!.id, curve);
              }
            },
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
              // Store container width for keyboard zoom
              _containerWidth = constraints.maxWidth;

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
    final fadeInTime = widget.clip!.fadeIn;
    final fadeOutTime = widget.clip!.fadeOut;
    final duration = widget.clip!.duration;
    final maxW = constraints.maxWidth;
    final maxH = constraints.maxHeight;

    // Safety check
    if (maxW <= 0 || maxH <= 0 || duration <= 0) {
      return const SizedBox.shrink();
    }

    // Calculate fade region widths in pixels
    final fadeInWidth = fadeInTime * widget.zoom;
    final fadeOutWidth = fadeOutTime * widget.zoom;

    // Calculate visible clip boundaries
    final clipStartX = (0 - widget.scrollOffset) * widget.zoom;
    final clipEndX = (duration - widget.scrollOffset) * widget.zoom;

    const handleSize = 20.0;

    return Stack(
      children: [
        // ===== FADE IN REGION (left side) =====
        // Triangular overlay for fade in
        if (fadeInTime > 0 && fadeInWidth > 0 && clipStartX < maxW)
          Positioned(
            left: clipStartX.clamp(0.0, maxW).toDouble(),
            top: 0,
            bottom: 0,
            width: fadeInWidth.clamp(1.0, maxW).toDouble(),
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FadeOverlayPainter(isLeft: true),
              ),
            ),
          ),

        // Fade In handle/arrow - positioned at TOP LEFT corner
        if (clipStartX > -handleSize && clipStartX < maxW && maxW > handleSize)
          Positioned(
            left: clipStartX.clamp(0.0, maxW - handleSize).toDouble(),
            top: 2,
            child: _EditorFadeArrow(
              isLeft: true,
              isActive: _draggingFade == _FadeHandle.fadeIn,
              hasFade: fadeInTime > 0,
              onDragStart: () => setState(() => _draggingFade = _FadeHandle.fadeIn),
              onDragUpdate: (delta) {
                final timeDelta = delta / widget.zoom;
                final newFadeIn = (fadeInTime + timeDelta).clamp(0.0, duration / 2);
                widget.onFadeInChange?.call(widget.clip!.id, _snapTime(newFadeIn));
              },
              onDragEnd: () => setState(() => _draggingFade = _FadeHandle.none),
            ),
          ),

        // ===== FADE OUT REGION (right side) =====
        // Triangular overlay for fade out
        if (fadeOutTime > 0 && fadeOutWidth > 0 && clipEndX > 0)
          Positioned(
            left: (clipEndX - fadeOutWidth).clamp(0.0, maxW).toDouble(),
            top: 0,
            bottom: 0,
            width: fadeOutWidth.clamp(1.0, maxW).toDouble(),
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FadeOverlayPainter(isLeft: false),
              ),
            ),
          ),

        // Fade Out handle/arrow - positioned at TOP RIGHT corner
        if (clipEndX > 0 && clipEndX < maxW + handleSize && maxW > handleSize)
          Positioned(
            left: (clipEndX - handleSize).clamp(0.0, maxW - handleSize).toDouble(),
            top: 2,
            child: _EditorFadeArrow(
              isLeft: false,
              isActive: _draggingFade == _FadeHandle.fadeOut,
              hasFade: fadeOutTime > 0,
              onDragStart: () => setState(() => _draggingFade = _FadeHandle.fadeOut),
              onDragUpdate: (delta) {
                // Negative because dragging left increases fade
                final timeDelta = -delta / widget.zoom;
                final newFadeOut = (fadeOutTime + timeDelta).clamp(0.0, duration / 2);
                widget.onFadeOutChange?.call(widget.clip!.id, _snapTime(newFadeOut));
              },
              onDragEnd: () => setState(() => _draggingFade = _FadeHandle.none),
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
          // Safety: max scroll can't be negative
          final maxScroll = (widget.clip!.duration - constraints.maxWidth / widget.zoom).clamp(0.0, double.infinity);

          return GestureDetector(
            onTapDown: (details) {
              // Click to scroll to position
              final fraction = details.localPosition.dx / constraints.maxWidth;
              final time = fraction * widget.clip!.duration;
              widget.onScrollChange?.call(time.clamp(0.0, maxScroll));
            },
            onHorizontalDragUpdate: (details) {
              final delta = details.delta.dx / constraints.maxWidth * widget.clip!.duration;
              final newOffset = (widget.scrollOffset + delta).clamp(0.0, maxScroll);
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
    // ══════════════════════════════════════════════════════════════════
    // DAW-STANDARD SCROLL/ZOOM (matching Timeline behavior)
    // ══════════════════════════════════════════════════════════════════
    final clip = widget.clip;
    if (clip == null) return;

    final isZoomModifier = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShiftHeld = HardwareKeyboard.instance.isShiftPressed;

    if (isZoomModifier) {
      // ════════════════════════════════════════════════════════════════
      // ZOOM TO CURSOR
      // ════════════════════════════════════════════════════════════════
      final mouseX = event.localPosition.dx;

      // Simple zoom factor based on scroll direction
      final zoomIn = event.scrollDelta.dy < 0;
      final zoomFactor = zoomIn ? 1.15 : 0.87;
      final newZoom = (widget.zoom * zoomFactor).clamp(5.0, 500.0);

      if (_containerWidth > 0) {
        final mouseTime = widget.scrollOffset + mouseX / widget.zoom;
        final newScrollOffset = mouseTime - mouseX / newZoom;

        widget.onZoomChange?.call(newZoom);
        widget.onScrollChange?.call(newScrollOffset.clamp(
            0.0, (clip.duration - _containerWidth / newZoom).clamp(0.0, double.infinity)));
      } else {
        widget.onZoomChange?.call(newZoom);
      }
    } else {
      // ════════════════════════════════════════════════════════════════
      // HORIZONTAL SCROLL
      // ════════════════════════════════════════════════════════════════
      final rawDelta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
          ? event.scrollDelta.dx
          : event.scrollDelta.dy;

      final speedMultiplier = isShiftHeld ? 3.0 : 1.0;
      final scrollSeconds = (rawDelta / widget.zoom) * speedMultiplier;

      final maxOffset = (clip.duration - _containerWidth / widget.zoom)
          .clamp(0.0, double.infinity);
      final newOffset = (widget.scrollOffset + scrollSeconds).clamp(0.0, maxOffset);

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
          widget.onZoomChange?.call((widget.zoom * 0.7).clamp(1, 500));
        } else {
          widget.onZoomChange?.call((widget.zoom * 1.4).clamp(1, 500));
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
  final ValueChanged<FadeCurve?>? onFadeInCurveChange;
  final ValueChanged<FadeCurve?>? onFadeOutCurveChange;
  final ValueChanged<double>? onGainChange;

  const _InfoSidebar({
    required this.clip,
    this.selection,
    this.onFadeInChange,
    this.onFadeOutChange,
    this.onFadeInCurveChange,
    this.onFadeOutCurveChange,
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
            _FadeControl(
              value: clip.fadeIn,
              maxValue: clip.duration / 2,
              onChanged: onFadeInChange,
            ),

            const SizedBox(height: 6),
            // Fade In Curve selector
            _CurveSelector(
              label: 'Curve',
              value: clip.fadeInCurve,
              onChanged: onFadeInCurveChange,
            ),

            const SizedBox(height: 12),
            Text('Fade Out', style: ReelForgeTheme.label),
            const SizedBox(height: 4),
            _FadeControl(
              value: clip.fadeOut,
              maxValue: clip.duration / 2,
              onChanged: onFadeOutChange,
            ),

            const SizedBox(height: 6),
            // Fade Out Curve selector
            _CurveSelector(
              label: 'Curve',
              value: clip.fadeOutCurve,
              onChanged: onFadeOutCurveChange,
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

    // Calculate samples per pixel for LOD decision
    final visibleDuration = size.width / zoom;
    final samplesPerPixel = (visibleDuration * samplesPerSecond) / size.width;

    // LOD: Choose rendering method based on zoom level (Cubase-style)
    if (samplesPerPixel < 4) {
      _drawDetailedWaveform(canvas, size, centerY, amplitude, samplesPerSecond);
    } else if (samplesPerPixel < 50) {
      _drawMinMaxWaveform(canvas, size, centerY, amplitude, samplesPerSecond);
    } else {
      _drawOverviewWaveform(canvas, size, centerY, amplitude, samplesPerSecond);
    }
  }

  /// HIGH ZOOM: Sample-accurate rendering with interpolation and transients
  void _drawDetailedWaveform(Canvas canvas, Size size, double centerY, double amplitude, double samplesPerSecond) {
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final path = Path();
    bool pathStarted = false;

    for (double x = 0; x < size.width; x++) {
      final time = scrollOffset + x / zoom;
      if (time < 0 || time > duration) continue;

      final sampleIndex = (time * samplesPerSecond).floor().clamp(0, waveform!.length - 1);
      final nextIndex = ((scrollOffset + (x + 1) / zoom) * samplesPerSecond).floor().clamp(0, waveform!.length - 1);

      final sample = waveform![sampleIndex];
      final t = (time * samplesPerSecond) - sampleIndex.floor();
      final interpolated = nextIndex < waveform!.length
          ? sample * (1 - t) + waveform![nextIndex] * t
          : sample;

      // Apply fade envelope
      double envelope = 1;
      if (fadeIn > 0 && time < fadeIn) {
        envelope = time / fadeIn;
      } else if (fadeOut > 0 && time > duration - fadeOut) {
        envelope = (duration - time) / fadeOut;
      }

      final y = centerY - interpolated * amplitude * envelope;

      if (!pathStarted) {
        path.moveTo(x, y);
        pathStarted = true;
      } else {
        path.lineTo(x, y);
      }
    }

    // Draw filled area
    if (pathStarted) {
      final fillPath = Path()..addPath(path, Offset.zero);
      for (double x = size.width - 1; x >= 0; x--) {
        final time = scrollOffset + x / zoom;
        if (time < 0 || time > duration) continue;
        final sampleIndex = (time * samplesPerSecond).floor().clamp(0, waveform!.length - 1);
        double envelope = 1;
        if (fadeIn > 0 && time < fadeIn) envelope = time / fadeIn;
        else if (fadeOut > 0 && time > duration - fadeOut) envelope = (duration - time) / fadeOut;
        fillPath.lineTo(x, centerY + waveform![sampleIndex].abs() * amplitude * envelope);
      }
      fillPath.close();
      canvas.drawPath(fillPath, fillPaint);
      canvas.drawPath(path, linePaint);
    }

    // Draw transient markers
    _drawTransientMarkers(canvas, size, centerY, samplesPerSecond);
  }

  /// Draw transient markers at sudden amplitude changes
  void _drawTransientMarkers(Canvas canvas, Size size, double centerY, double samplesPerSecond) {
    final transientPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1;

    double prevSample = 0;
    double prevSlope = 0;
    const slopeThreshold = 0.25;

    for (double x = 1; x < size.width; x++) {
      final time = scrollOffset + x / zoom;
      if (time < 0 || time > duration) continue;

      final sampleIndex = (time * samplesPerSecond).floor().clamp(0, waveform!.length - 1);
      final sample = waveform![sampleIndex];
      final slope = (sample - prevSample).abs();

      if (slope > slopeThreshold && slope > prevSlope * 1.8) {
        canvas.drawLine(
          Offset(x, centerY - 4),
          Offset(x, centerY + 4),
          transientPaint,
        );
      }

      prevSample = sample;
      prevSlope = slope;
    }
  }

  /// MEDIUM ZOOM: True min/max envelope - accurate peak display
  void _drawMinMaxWaveform(Canvas canvas, Size size, double centerY, double amplitude, double samplesPerSecond) {
    final peakPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    final rmsPaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    // Collect data for path-based rendering (smoother than rectangles)
    final minValues = <double>[];
    final maxValues = <double>[];
    final rmsValues = <double>[];
    final envelopes = <double>[];

    for (double x = 0; x < size.width; x++) {
      final timeStart = scrollOffset + x / zoom;
      final timeEnd = scrollOffset + (x + 1) / zoom;
      if (timeEnd < 0 || timeStart > duration) {
        minValues.add(0);
        maxValues.add(0);
        rmsValues.add(0);
        envelopes.add(0);
        continue;
      }

      final startSample = (timeStart * samplesPerSecond).floor().clamp(0, waveform!.length - 1);
      final endSample = (timeEnd * samplesPerSecond).ceil().clamp(startSample + 1, waveform!.length);

      double minVal = waveform![startSample];
      double maxVal = waveform![startSample];
      double sumSq = 0;
      int count = 0;

      for (int i = startSample; i < endSample && i < waveform!.length; i++) {
        final s = waveform![i];
        if (s < minVal) minVal = s;
        if (s > maxVal) maxVal = s;
        sumSq += s * s;
        count++;
      }

      // Apply fade envelope
      final midTime = (timeStart + timeEnd) / 2;
      double envelope = 1;
      if (fadeIn > 0 && midTime < fadeIn) {
        envelope = midTime / fadeIn;
      } else if (fadeOut > 0 && midTime > duration - fadeOut) {
        envelope = (duration - midTime) / fadeOut;
      }

      minValues.add(minVal);
      maxValues.add(maxVal);
      rmsValues.add(count > 0 ? math.sqrt(sumSq / count) : 0);
      envelopes.add(envelope);
    }

    // Draw peak envelope as path (true min/max)
    final peakPath = Path();
    for (int i = 0; i < maxValues.length; i++) {
      final y = centerY - maxValues[i] * amplitude * envelopes[i];
      if (i == 0) {
        peakPath.moveTo(i.toDouble(), y);
      } else {
        peakPath.lineTo(i.toDouble(), y);
      }
    }
    for (int i = minValues.length - 1; i >= 0; i--) {
      final y = centerY - minValues[i] * amplitude * envelopes[i];
      peakPath.lineTo(i.toDouble(), y);
    }
    peakPath.close();
    canvas.drawPath(peakPath, peakPaint);

    // Draw RMS envelope
    final rmsPath = Path();
    for (int i = 0; i < rmsValues.length; i++) {
      final y = centerY - rmsValues[i] * amplitude * envelopes[i];
      if (i == 0) {
        rmsPath.moveTo(i.toDouble(), y);
      } else {
        rmsPath.lineTo(i.toDouble(), y);
      }
    }
    for (int i = rmsValues.length - 1; i >= 0; i--) {
      final y = centerY + rmsValues[i] * amplitude * envelopes[i];
      rmsPath.lineTo(i.toDouble(), y);
    }
    rmsPath.close();
    canvas.drawPath(rmsPath, rmsPaint);

    // Zero line
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()..color = Colors.white.withValues(alpha: 0.08)..strokeWidth = 0.5,
    );
  }

  /// LOW ZOOM: RMS overview waveform
  void _drawOverviewWaveform(Canvas canvas, Size size, double centerY, double amplitude, double samplesPerSecond) {
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
  final FadeCurve fadeInCurve;
  final FadeCurve fadeOutCurve;
  final double gain;
  final Color? clipColor;
  final double playheadPosition;
  final bool snapEnabled;
  final double snapValue;
  final void Function(String clipId, double fadeIn)? onFadeInChange;
  final void Function(String clipId, double fadeOut)? onFadeOutChange;
  final void Function(String clipId, FadeCurve curve)? onFadeInCurveChange;
  final void Function(String clipId, FadeCurve curve)? onFadeOutCurveChange;
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
    this.fadeInCurve = FadeCurve.linear,
    this.fadeOutCurve = FadeCurve.linear,
    this.gain = 0,
    this.clipColor,
    this.playheadPosition = 0,
    this.snapEnabled = true,
    this.snapValue = 0.1,
    this.onFadeInChange,
    this.onFadeOutChange,
    this.onFadeInCurveChange,
    this.onFadeOutCurveChange,
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
            fadeInCurve: widget.fadeInCurve,
            fadeOutCurve: widget.fadeOutCurve,
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
      onFadeInCurveChange: widget.onFadeInCurveChange,
      onFadeOutCurveChange: widget.onFadeOutCurveChange,
      onGainChange: widget.onGainChange,
      onNormalize: widget.onNormalize,
      onReverse: widget.onReverse,
      onTrimToSelection: widget.onTrimToSelection,
      onSplitAtPosition: widget.onSplitAtPosition,
      onPlayheadChange: widget.onPlayheadChange,
    );
  }
}

// ============ Fade Control Widget (Slider + Arrows + Value) ============

class _FadeControl extends StatelessWidget {
  final double value;
  final double maxValue;
  final ValueChanged<double>? onChanged;

  const _FadeControl({
    required this.value,
    required this.maxValue,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const nudgeAmount = 0.01; // 10ms
    const nudgeAmountLarge = 0.05; // 50ms

    return Row(
      children: [
        // Decrease button
        _ArrowButton(
          icon: Icons.remove,
          onTap: onChanged != null
              ? () => onChanged!((value - nudgeAmount).clamp(0.0, maxValue))
              : null,
          onLongPress: onChanged != null
              ? () => onChanged!((value - nudgeAmountLarge).clamp(0.0, maxValue))
              : null,
        ),
        // Slider
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: ReelForgeTheme.accentCyan,
              inactiveTrackColor: ReelForgeTheme.borderSubtle,
              thumbColor: ReelForgeTheme.accentCyan,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value.clamp(0.0, maxValue),
              min: 0,
              max: maxValue > 0 ? maxValue : 1.0,
              onChanged: onChanged,
            ),
          ),
        ),
        // Increase button
        _ArrowButton(
          icon: Icons.add,
          onTap: onChanged != null
              ? () => onChanged!((value + nudgeAmount).clamp(0.0, maxValue))
              : null,
          onLongPress: onChanged != null
              ? () => onChanged!((value + nudgeAmountLarge).clamp(0.0, maxValue))
              : null,
        ),
        const SizedBox(width: 4),
        // Value display
        SizedBox(
          width: 48,
          child: Text(
            '${(value * 1000).toStringAsFixed(0)}ms',
            style: ReelForgeTheme.monoSmall,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// ============ Arrow Button Widget ============

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _ArrowButton({
    required this.icon,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: ReelForgeTheme.borderSubtle),
        ),
        child: Icon(
          icon,
          size: 14,
          color: onTap != null
              ? ReelForgeTheme.textSecondary
              : ReelForgeTheme.textTertiary,
        ),
      ),
    );
  }
}

// ============ Curve Selector Widget ============

class _CurveSelector extends StatelessWidget {
  final String label;
  final FadeCurve value;
  final ValueChanged<FadeCurve?>? onChanged;

  const _CurveSelector({
    required this.label,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: ReelForgeTheme.bodySmall.copyWith(color: ReelForgeTheme.textSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: ReelForgeTheme.borderSubtle),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<FadeCurve>(
                value: value,
                isDense: true,
                dropdownColor: ReelForgeTheme.bgDeep,
                style: ReelForgeTheme.monoSmall.copyWith(color: ReelForgeTheme.textPrimary),
                icon: const Icon(Icons.arrow_drop_down, size: 16, color: ReelForgeTheme.textSecondary),
                items: FadeCurve.values.map((curve) {
                  return DropdownMenuItem<FadeCurve>(
                    value: curve,
                    child: Row(
                      children: [
                        // Mini curve preview icon
                        SizedBox(
                          width: 24,
                          height: 16,
                          child: CustomPaint(
                            painter: _CurvePreviewPainter(curve),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(curve.displayName),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============ Curve Preview Painter ============

class _CurvePreviewPainter extends CustomPainter {
  final FadeCurve curve;

  _CurvePreviewPainter(this.curve);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ReelForgeTheme.accentCyan
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    const steps = 20;

    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = t * size.width;
      final y = size.height * (1 - _evaluateCurve(t));

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  double _evaluateCurve(double t) {
    switch (curve) {
      case FadeCurve.linear:
        return t;
      case FadeCurve.exp1:
        return t * t;
      case FadeCurve.exp3:
        return t * t * t;
      case FadeCurve.log1:
        return math.sqrt(t);
      case FadeCurve.log3:
        return math.pow(t, 1 / 3).toDouble();
      case FadeCurve.sCurve:
        return t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t);
      case FadeCurve.invSCurve:
        return t < 0.5 ? 0.5 * math.sqrt(2 * t) : 0.5 + 0.5 * math.sqrt(2 * t - 1);
      case FadeCurve.sine:
        return math.sin(t * math.pi / 2);
    }
  }

  @override
  bool shouldRepaint(_CurvePreviewPainter oldDelegate) => oldDelegate.curve != curve;
}

// ============ Editor Fade Arrow Widget ============

/// Draggable arrow for fade in/out on waveform edges
class _EditorFadeArrow extends StatefulWidget {
  final bool isLeft;
  final bool isActive;
  final bool hasFade;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  const _EditorFadeArrow({
    required this.isLeft,
    required this.isActive,
    required this.hasFade,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  State<_EditorFadeArrow> createState() => _EditorFadeArrowState();
}

class _EditorFadeArrowState extends State<_EditorFadeArrow> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    const size = 20.0;
    final isActive = widget.isActive || _isHovered || _isDragging;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (details) {
          setState(() => _isDragging = true);
          widget.onDragStart();
        },
        onHorizontalDragUpdate: (details) {
          // Smooth: send delta directly, no threshold
          widget.onDragUpdate(details.delta.dx);
        },
        onHorizontalDragEnd: (details) {
          setState(() => _isDragging = false);
          widget.onDragEnd();
        },
        onHorizontalDragCancel: () {
          setState(() => _isDragging = false);
          widget.onDragEnd();
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isActive
                ? ReelForgeTheme.accentCyan
                : widget.hasFade
                    ? Colors.white.withValues(alpha: 0.9)
                    : Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(3),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: ReelForgeTheme.accentCyan.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Icon(
              widget.isLeft ? Icons.chevron_right : Icons.chevron_left,
              size: 14,
              color: isActive ? Colors.white : ReelForgeTheme.bgDeepest,
            ),
          ),
        ),
      ),
    );
  }
}

// ============ Fade Overlay Painter ============

/// Paints triangular fade overlay on waveform
class _FadeOverlayPainter extends CustomPainter {
  final bool isLeft;

  _FadeOverlayPainter({required this.isLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ReelForgeTheme.accentCyan.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final path = Path();

    if (isLeft) {
      // Fade in: triangle from top-left to bottom-right
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(0, size.height);
      path.close();
    } else {
      // Fade out: triangle from top-right to bottom-left
      path.moveTo(size.width, 0);
      path.lineTo(0, 0);
      path.lineTo(size.width, size.height);
      path.close();
    }

    canvas.drawPath(path, paint);

    // Draw edge line
    final linePaint = Paint()
      ..color = ReelForgeTheme.accentCyan.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    if (isLeft) {
      canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), linePaint);
    } else {
      canvas.drawLine(Offset(0, 0), Offset(size.width, size.height), linePaint);
    }
  }

  @override
  bool shouldRepaint(_FadeOverlayPainter oldDelegate) => oldDelegate.isLeft != isLeft;
}
