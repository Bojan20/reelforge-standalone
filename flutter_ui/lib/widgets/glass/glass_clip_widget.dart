/// Glass Clip Widget
///
/// Liquid Glass styled timeline clip with:
/// - Frosted glass background
/// - Glass waveform with glow effects
/// - Specular highlights and blur
/// - Theme-aware wrapper for Classic/Glass switching

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../providers/theme_mode_provider.dart';
import '../../models/timeline_models.dart';
import '../../models/middleware_models.dart' show FadeCurve;
import '../editors/clip_fx_editor.dart';
import '../../src/rust/native_ffi.dart';
import '../timeline/stretch_overlay.dart';
import '../timeline/clip_widget.dart';

// ==============================================================================
// THEME-AWARE WRAPPER
// ==============================================================================

/// Theme-aware clip widget that switches between Classic and Glass modes
class ThemeAwareClipWidget extends StatelessWidget {
  final TimelineClip clip;
  final double zoom;
  final double scrollOffset;
  final double trackHeight;
  final ValueChanged<bool>? onSelect;
  final ValueChanged<double>? onMove;
  final void Function(double newStartTime, double verticalDelta)? onCrossTrackDrag;
  final VoidCallback? onCrossTrackDragEnd;
  final void Function(Offset globalPosition, Offset localPosition)? onDragStart;
  final void Function(Offset globalPosition)? onDragUpdate;
  final void Function(Offset globalPosition)? onDragEnd;
  final ValueChanged<double>? onGainChange;
  final void Function(double fadeIn, double fadeOut)? onFadeChange;
  final void Function(double newStartTime, double newDuration, double? newOffset)? onResize;
  final VoidCallback? onResizeEnd;
  final ValueChanged<String>? onRename;
  final ValueChanged<double>? onSlipEdit;
  final VoidCallback? onOpenFxEditor;
  final VoidCallback? onOpenAudioEditor;
  final VoidCallback? onDelete;
  final VoidCallback? onDuplicate;
  final VoidCallback? onSplit;
  final VoidCallback? onMute;
  final ValueChanged<double>? onPlayheadMove;
  final bool snapEnabled;
  final double snapValue;
  final double tempo;
  final List<TimelineClip> allClips;

  const ThemeAwareClipWidget({
    super.key,
    required this.clip,
    required this.zoom,
    required this.scrollOffset,
    required this.trackHeight,
    this.onSelect,
    this.onMove,
    this.onCrossTrackDrag,
    this.onCrossTrackDragEnd,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onGainChange,
    this.onFadeChange,
    this.onResize,
    this.onResizeEnd,
    this.onRename,
    this.onSlipEdit,
    this.onOpenFxEditor,
    this.onOpenAudioEditor,
    this.onDelete,
    this.onDuplicate,
    this.onSplit,
    this.onMute,
    this.onPlayheadMove,
    this.snapEnabled = false,
    this.snapValue = 1,
    this.tempo = 120,
    this.allClips = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return GlassClipWidget(
        clip: clip,
        zoom: zoom,
        scrollOffset: scrollOffset,
        trackHeight: trackHeight,
        onSelect: onSelect,
        onMove: onMove,
        onCrossTrackDrag: onCrossTrackDrag,
        onCrossTrackDragEnd: onCrossTrackDragEnd,
        onDragStart: onDragStart,
        onDragUpdate: onDragUpdate,
        onDragEnd: onDragEnd,
        onGainChange: onGainChange,
        onFadeChange: onFadeChange,
        onResize: onResize,
        onResizeEnd: onResizeEnd,
        onRename: onRename,
        onSlipEdit: onSlipEdit,
        onOpenFxEditor: onOpenFxEditor,
        onOpenAudioEditor: onOpenAudioEditor,
        onDelete: onDelete,
        onDuplicate: onDuplicate,
        onSplit: onSplit,
        onMute: onMute,
        onPlayheadMove: onPlayheadMove,
        snapEnabled: snapEnabled,
        snapValue: snapValue,
        tempo: tempo,
        allClips: allClips,
      );
    }

    // Classic mode - use original ClipWidget with full functionality
    return ClipWidget(
      clip: clip,
      zoom: zoom,
      scrollOffset: scrollOffset,
      trackHeight: trackHeight,
      onSelect: onSelect,
      onMove: onMove,
      onCrossTrackDrag: onCrossTrackDrag,
      onCrossTrackDragEnd: onCrossTrackDragEnd,
      onDragStart: onDragStart,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      onGainChange: onGainChange,
      onFadeChange: onFadeChange,
      onResize: onResize,
      onResizeEnd: onResizeEnd,
      onRename: onRename,
      onSlipEdit: onSlipEdit,
      onOpenFxEditor: onOpenFxEditor,
      onOpenAudioEditor: onOpenAudioEditor,
      onDelete: onDelete,
      onDuplicate: onDuplicate,
      onSplit: onSplit,
      onMute: onMute,
      onPlayheadMove: onPlayheadMove,
      snapEnabled: snapEnabled,
      snapValue: snapValue,
      tempo: tempo,
      allClips: allClips,
    );
  }
}

// ==============================================================================
// GLASS CLIP WIDGET
// ==============================================================================

/// Glass-styled timeline clip with frosted glass effects
class GlassClipWidget extends StatefulWidget {
  final TimelineClip clip;
  final double zoom;
  final double scrollOffset;
  final double trackHeight;
  final ValueChanged<bool>? onSelect;
  final ValueChanged<double>? onMove;
  final void Function(double newStartTime, double verticalDelta)? onCrossTrackDrag;
  final VoidCallback? onCrossTrackDragEnd;
  final void Function(Offset globalPosition, Offset localPosition)? onDragStart;
  final void Function(Offset globalPosition)? onDragUpdate;
  final void Function(Offset globalPosition)? onDragEnd;
  final ValueChanged<double>? onGainChange;
  final void Function(double fadeIn, double fadeOut)? onFadeChange;
  final void Function(double newStartTime, double newDuration, double? newOffset)? onResize;
  final VoidCallback? onResizeEnd;
  final ValueChanged<String>? onRename;
  final ValueChanged<double>? onSlipEdit;
  final VoidCallback? onOpenFxEditor;
  final VoidCallback? onOpenAudioEditor;
  final VoidCallback? onDelete;
  final VoidCallback? onDuplicate;
  final VoidCallback? onSplit;
  final VoidCallback? onMute;
  final ValueChanged<double>? onPlayheadMove;
  final bool snapEnabled;
  final double snapValue;
  final double tempo;
  final List<TimelineClip> allClips;

  const GlassClipWidget({
    super.key,
    required this.clip,
    required this.zoom,
    required this.scrollOffset,
    required this.trackHeight,
    this.onSelect,
    this.onMove,
    this.onCrossTrackDrag,
    this.onCrossTrackDragEnd,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onGainChange,
    this.onFadeChange,
    this.onResize,
    this.onResizeEnd,
    this.onRename,
    this.onSlipEdit,
    this.onOpenFxEditor,
    this.onOpenAudioEditor,
    this.onDelete,
    this.onDuplicate,
    this.onSplit,
    this.onMute,
    this.onPlayheadMove,
    this.snapEnabled = false,
    this.snapValue = 1,
    this.tempo = 120,
    this.allClips = const [],
  });

  @override
  State<GlassClipWidget> createState() => _GlassClipWidgetState();
}

class _GlassClipWidgetState extends State<GlassClipWidget> {
  bool _isDraggingGain = false;
  bool _isDraggingFadeIn = false;
  bool _isDraggingFadeOut = false;
  bool _isDraggingLeftEdge = false;
  bool _isDraggingRightEdge = false;
  bool _isDraggingMove = false;
  bool _isSlipEditing = false;
  bool _isEditing = false;
  bool _isHovered = false;
  bool _isTrackpadPanActive = false;

  late TextEditingController _nameController;
  late FocusNode _focusNode;

  double _dragStartTime = 0;
  double _dragStartDuration = 0;
  double _dragStartMouseX = 0;
  double _dragStartMouseY = 0;
  double _dragStartSourceOffset = 0;
  Offset _lastDragPosition = Offset.zero;
  double _lastSnappedTime = 0;
  bool _isCrossTrackDrag = false;
  bool _wasCrossTrackDrag = false;

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
    if (widget.clip.gain <= 0) return '-inf';
    final db = 20 * _log10(widget.clip.gain);
    return db <= -60 ? '-inf' : '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)}';
  }

  double _log10(double x) => x > 0 ? (math.log(x) / math.ln10) : double.negativeInfinity;

  bool _hasTimeStretch(TimelineClip clip) {
    return clip.fxChain.slots.any((s) => s.type == ClipFxType.timeStretch && !s.bypass);
  }

  double _getStretchRatio(TimelineClip clip) {
    if (clip.sourceDuration != null && clip.sourceDuration! > 0) {
      return clip.duration / clip.sourceDuration!;
    }
    return 1.0;
  }

  void _startEditing() {
    if (widget.clip.sourceFile != null && widget.onOpenAudioEditor != null) {
      widget.onOpenAudioEditor!();
      return;
    }
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

  void _showContextMenu(BuildContext context, Offset position) {
    final clip = widget.clip;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: Colors.black.withValues(alpha: 0.85),
      items: [
        if (clip.sourceFile != null && widget.onOpenAudioEditor != null)
          PopupMenuItem(
            value: 'audio_editor',
            child: Row(
              children: [
                Icon(Icons.graphic_eq, size: 18, color: LiquidGlassTheme.accentCyan),
                const SizedBox(width: 8),
                Text('Edit Audio', style: TextStyle(color: LiquidGlassTheme.accentCyan)),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'rename',
          enabled: !clip.locked,
          child: Row(
            children: [
              Icon(Icons.edit, size: 18, color: clip.locked ? LiquidGlassTheme.textTertiary : LiquidGlassTheme.textPrimary),
              const SizedBox(width: 8),
              Text('Rename', style: TextStyle(color: clip.locked ? LiquidGlassTheme.textTertiary : LiquidGlassTheme.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'duplicate',
          enabled: !clip.locked,
          child: Row(
            children: [
              Icon(Icons.copy, size: 18, color: clip.locked ? LiquidGlassTheme.textTertiary : LiquidGlassTheme.textPrimary),
              const SizedBox(width: 8),
              Text('Duplicate', style: TextStyle(color: clip.locked ? LiquidGlassTheme.textTertiary : LiquidGlassTheme.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'split',
          enabled: !clip.locked,
          child: Row(
            children: [
              Icon(Icons.content_cut, size: 18, color: clip.locked ? LiquidGlassTheme.textTertiary : LiquidGlassTheme.textPrimary),
              const SizedBox(width: 8),
              Text('Split at Playhead', style: TextStyle(color: clip.locked ? LiquidGlassTheme.textTertiary : LiquidGlassTheme.textPrimary)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'mute',
          child: Row(
            children: [
              Icon(clip.muted ? Icons.volume_up : Icons.volume_off, size: 18, color: LiquidGlassTheme.textPrimary),
              const SizedBox(width: 8),
              Text(clip.muted ? 'Unmute' : 'Mute', style: TextStyle(color: LiquidGlassTheme.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'fx',
          child: Row(
            children: [
              Icon(Icons.auto_fix_high, size: 18, color: LiquidGlassTheme.textPrimary),
              const SizedBox(width: 8),
              Text('Clip FX...', style: TextStyle(color: LiquidGlassTheme.textPrimary)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          enabled: !clip.locked,
          child: Row(
            children: [
              Icon(Icons.delete, size: 18, color: clip.locked ? LiquidGlassTheme.textTertiary : LiquidGlassTheme.accentRed),
              const SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: clip.locked ? LiquidGlassTheme.textTertiary : LiquidGlassTheme.accentRed)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'audio_editor':
          widget.onOpenAudioEditor?.call();
          break;
        case 'rename':
          if (!clip.locked) _startEditing();
          break;
        case 'duplicate':
          if (!clip.locked) widget.onDuplicate?.call();
          break;
        case 'split':
          if (!clip.locked) widget.onSplit?.call();
          break;
        case 'mute':
          widget.onMute?.call();
          break;
        case 'fx':
          widget.onOpenFxEditor?.call();
          break;
        case 'delete':
          if (!clip.locked) widget.onDelete?.call();
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final x = (clip.startTime - widget.scrollOffset) * widget.zoom;
    final width = clip.duration * widget.zoom;

    if (x + width < 0 || x > 2000) return const SizedBox.shrink();

    final clipHeight = widget.trackHeight - 4;
    final clipColor = clip.color ?? LiquidGlassTheme.accentBlue;

    final minWidth = (0.05 * widget.zoom).clamp(2.0, 4.0);
    final clampedWidth = width.clamp(minWidth, double.infinity);

    return Positioned(
      left: x,
      top: 2,
      width: clampedWidth,
      height: clipHeight,
      child: Listener(
        onPointerPanZoomStart: (_) => _isTrackpadPanActive = true,
        onPointerPanZoomEnd: (_) => _isTrackpadPanActive = false,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTapDown: (details) {
              if (fadeHandleActiveGlobal) return;
              if (_isDraggingFadeIn || _isDraggingFadeOut) return;

              final clickX = details.localPosition.dx;
              final clickY = details.localPosition.dy;
              const fadeHandleZone = 20.0;
              if (clickY < fadeHandleZone) {
                if (clickX < fadeHandleZone || clickX > width - fadeHandleZone) {
                  return;
                }
              }
              widget.onSelect?.call(false);
            },
            onDoubleTap: _startEditing,
            onSecondaryTapDown: (details) {
              widget.onSelect?.call(false);
              _showContextMenu(context, details.globalPosition);
            },
            onPanStart: _handlePanStart,
            onPanUpdate: _handlePanUpdate,
            onPanEnd: _handlePanEnd,
            onPanCancel: _handlePanCancel,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(LiquidGlassTheme.radiusSmall),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: 8,
                  sigmaY: 8,
                ),
                child: AnimatedContainer(
                  duration: LiquidGlassTheme.animFast,
                  decoration: BoxDecoration(
                    // Glass gradient with clip color tint
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        clipColor.withValues(alpha: clip.selected ? 0.45 : 0.3),
                        clipColor.withValues(alpha: clip.selected ? 0.35 : 0.2),
                        clipColor.withValues(alpha: clip.selected ? 0.25 : 0.15),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(LiquidGlassTheme.radiusSmall),
                    border: Border.all(
                      color: clip.selected
                          ? clipColor
                          : _isHovered
                              ? clipColor.withValues(alpha: 0.7)
                              : clipColor.withValues(alpha: 0.4),
                      width: clip.selected ? 2 : 1,
                    ),
                    boxShadow: clip.selected
                        ? [
                            BoxShadow(
                              color: clipColor.withValues(alpha: 0.5),
                              blurRadius: 12,
                              spreadRadius: -2,
                            ),
                          ]
                        : null,
                  ),
                  child: Stack(
                    children: [
                      // Specular highlight
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.5),
                                Colors.white.withValues(alpha: 0.15),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Glass Waveform
                      if (clip.waveform != null && width > 20)
                        Positioned.fill(
                          child: _GlassClipWaveform(
                            clipId: clip.id,
                            waveform: clip.waveform!,
                            waveformRight: clip.waveformRight,
                            sourceOffset: clip.sourceOffset,
                            duration: clip.duration,
                            gain: clip.gain,
                            zoom: widget.zoom,
                            clipColor: clipColor,
                            trackHeight: widget.trackHeight,
                          ),
                        ),

                      // Label with glass styling
                      if (width > 40)
                        Positioned(
                          left: 4,
                          top: 2,
                          right: 4,
                          child: _isEditing
                              ? TextField(
                                  controller: _nameController,
                                  focusNode: _focusNode,
                                  style: const TextStyle(
                                    color: LiquidGlassTheme.textPrimary,
                                    fontSize: 11,
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
                                  style: TextStyle(
                                    color: LiquidGlassTheme.textPrimary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black.withValues(alpha: 0.7),
                                        blurRadius: 3,
                                      ),
                                    ],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),

                      // Glass gain handle
                      if (width > 60)
                        Positioned(
                          top: 2,
                          left: (width - 44) / 2,
                          child: _GlassGainHandle(
                            gain: widget.clip.gain,
                            gainDisplay: _gainDisplay,
                            isActive: _isDraggingGain,
                            locked: clip.locked,
                            onDragStart: () => setState(() => _isDraggingGain = true),
                            onDragUpdate: (delta) {
                              if (clip.locked) return;
                              final newGain = (widget.clip.gain + delta).clamp(0.0, 2.0);
                              widget.onGainChange?.call(newGain);
                            },
                            onDragEnd: () => setState(() => _isDraggingGain = false),
                            onReset: () {
                              if (!clip.locked) widget.onGainChange?.call(1);
                            },
                          ),
                        ),

                      // Glass fade visualizations
                      if (clip.fadeIn > 0)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: clip.fadeIn * widget.zoom,
                          child: CustomPaint(
                            painter: _GlassFadeOverlayPainter(
                              isLeft: true,
                              curve: clip.fadeInCurve,
                              clipColor: clipColor,
                            ),
                          ),
                        ),
                      if (clip.fadeOut > 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          width: clip.fadeOut * widget.zoom,
                          child: CustomPaint(
                            painter: _GlassFadeOverlayPainter(
                              isLeft: false,
                              curve: clip.fadeOutCurve,
                              clipColor: clipColor,
                            ),
                          ),
                        ),

                      // Glass fade handles
                      if (!clip.locked)
                        _GlassFadeHandle(
                          width: (clip.fadeIn * widget.zoom).clamp(20.0, double.infinity),
                          fadeTime: clip.fadeIn,
                          isLeft: true,
                          isActive: _isDraggingFadeIn,
                          curve: clip.fadeInCurve,
                          onDragStart: () => setState(() => _isDraggingFadeIn = true),
                          onDragUpdate: (deltaPixels) {
                            final deltaSeconds = deltaPixels / widget.zoom;
                            final newFadeIn = (clip.fadeIn + deltaSeconds)
                                .clamp(0.0, clip.duration * 0.5);
                            widget.onFadeChange?.call(newFadeIn, clip.fadeOut);
                          },
                          onDragEnd: () => setState(() => _isDraggingFadeIn = false),
                        ),

                      if (!clip.locked)
                        _GlassFadeHandle(
                          width: (clip.fadeOut * widget.zoom).clamp(20.0, double.infinity),
                          fadeTime: clip.fadeOut,
                          isLeft: false,
                          isActive: _isDraggingFadeOut,
                          curve: clip.fadeOutCurve,
                          onDragStart: () => setState(() => _isDraggingFadeOut = true),
                          onDragUpdate: (deltaPixels) {
                            final deltaSeconds = -deltaPixels / widget.zoom;
                            final newFadeOut = (clip.fadeOut + deltaSeconds)
                                .clamp(0.0, clip.duration * 0.5);
                            widget.onFadeChange?.call(clip.fadeIn, newFadeOut);
                          },
                          onDragEnd: () => setState(() => _isDraggingFadeOut = false),
                        ),

                      // Glass edge handles
                      if (!clip.locked)
                        _GlassEdgeHandle(
                          isLeft: true,
                          isActive: _isDraggingLeftEdge,
                          onDragStart: () {
                            _dragStartTime = clip.startTime;
                            _dragStartDuration = clip.duration;
                            _dragStartSourceOffset = clip.sourceOffset;
                            setState(() => _isDraggingLeftEdge = true);
                          },
                          onDragUpdate: (deltaX) => _handleLeftEdgeDrag(deltaX),
                          onDragEnd: () => setState(() => _isDraggingLeftEdge = false),
                        ),

                      if (!clip.locked)
                        _GlassEdgeHandle(
                          isLeft: false,
                          isActive: _isDraggingRightEdge,
                          onDragStart: () {
                            _dragStartDuration = clip.duration;
                            _dragStartMouseX = 0;
                            setState(() => _isDraggingRightEdge = true);
                          },
                          onDragUpdate: (deltaX) => _handleRightEdgeDrag(deltaX),
                          onDragEnd: () => setState(() => _isDraggingRightEdge = false),
                        ),

                      // FX badge
                      if (clip.hasFx && width > 50)
                        Positioned(
                          right: 4,
                          bottom: 2,
                          child: GestureDetector(
                            onTap: widget.onOpenFxEditor,
                            child: ClipFxBadge(
                              fxChain: clip.fxChain,
                              onTap: widget.onOpenFxEditor,
                            ),
                          ),
                        ),

                      // Time stretch badge
                      if (_hasTimeStretch(clip) && width > 70)
                        Positioned(
                          left: 4,
                          bottom: 2,
                          child: StretchIndicatorBadge(
                            stretchRatio: _getStretchRatio(clip),
                          ),
                        ),

                      // Muted overlay with glass effect
                      if (clip.muted)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(LiquidGlassTheme.radiusSmall),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.volume_off,
                                color: LiquidGlassTheme.textTertiary,
                                size: 16,
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
      ),
    );
  }

  void _handlePanStart(DragStartDetails details) {
    if (_isTrackpadPanActive) return;
    if (widget.clip.locked) return;
    if (_isDraggingFadeIn || _isDraggingFadeOut || fadeHandleActiveGlobal) return;

    if (HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed) {
      _dragStartSourceOffset = widget.clip.sourceOffset;
      _dragStartMouseX = details.globalPosition.dx;
      setState(() => _isSlipEditing = true);
    } else {
      _dragStartTime = widget.clip.startTime;
      _dragStartMouseX = details.globalPosition.dx;
      _dragStartMouseY = details.globalPosition.dy;
      _lastDragPosition = details.globalPosition;
      _wasCrossTrackDrag = false;
      setState(() => _isDraggingMove = true);

      if (widget.onDragStart != null) {
        widget.onDragStart!(details.globalPosition, details.localPosition);
      }
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_isDraggingFadeIn || _isDraggingFadeOut || fadeHandleActiveGlobal) return;

    final deltaX = details.globalPosition.dx - _dragStartMouseX;
    final deltaY = details.globalPosition.dy - _dragStartMouseY;
    final deltaTime = deltaX / widget.zoom;
    _lastDragPosition = details.globalPosition;

    if (_isSlipEditing) {
      final newOffset = (_dragStartSourceOffset - deltaTime).clamp(0.0, double.infinity);
      widget.onSlipEdit?.call(newOffset);
    } else if (_isDraggingMove) {
      double rawNewStartTime = _dragStartTime + deltaTime;
      final snappedTime = applySnap(
        rawNewStartTime,
        widget.snapEnabled,
        widget.snapValue,
        widget.tempo,
        widget.allClips,
      );
      _lastSnappedTime = snappedTime.clamp(0.0, double.infinity);

      widget.onDragUpdate?.call(details.globalPosition);

      _isCrossTrackDrag = deltaY.abs() > 20;
      if (_isCrossTrackDrag) {
        _wasCrossTrackDrag = true;
        widget.onCrossTrackDrag?.call(_lastSnappedTime, deltaY);
      }
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_isDraggingMove) {
      if (_isCrossTrackDrag || _wasCrossTrackDrag) {
        widget.onCrossTrackDragEnd?.call();
      }
      if (!_isCrossTrackDrag) {
        widget.onMove?.call(_lastSnappedTime);
      }
    }
    widget.onDragEnd?.call(details.globalPosition);
    setState(() {
      _isDraggingMove = false;
      _isSlipEditing = false;
      _isCrossTrackDrag = false;
      _wasCrossTrackDrag = false;
    });
  }

  void _handlePanCancel() {
    widget.onDragEnd?.call(_lastDragPosition);
    setState(() {
      _isDraggingMove = false;
      _isSlipEditing = false;
      _isCrossTrackDrag = false;
      _wasCrossTrackDrag = false;
    });
  }

  void _handleLeftEdgeDrag(double deltaX) {
    final clip = widget.clip;
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
      final extensionAmount = _dragStartTime - snappedStartTime;
      final maxExtension = _dragStartSourceOffset;
      final actualExtension = extensionAmount.clamp(0.0, maxExtension);
      newStartTime = _dragStartTime - actualExtension;
      newOffset = _dragStartSourceOffset - actualExtension;
    } else {
      final trimAmount = snappedStartTime - _dragStartTime;
      final maxTrim = _dragStartDuration - 0.1;
      final actualTrim = trimAmount.clamp(0.0, maxTrim);
      newStartTime = _dragStartTime + actualTrim;
      newOffset = _dragStartSourceOffset + actualTrim;

      if (clip.sourceDuration != null) {
        final maxOffset = clip.sourceDuration! - 0.1;
        if (newOffset > maxOffset) {
          newOffset = maxOffset;
          newStartTime = _dragStartTime + (newOffset - _dragStartSourceOffset);
        }
      }
    }

    newStartTime = newStartTime.clamp(0.0, double.infinity);
    newOffset = newOffset.clamp(0.0, double.infinity);

    final newDuration = _dragStartDuration - (newStartTime - _dragStartTime);

    widget.onResize?.call(
      newStartTime,
      newDuration.clamp(0.1, double.infinity),
      newOffset,
    );
  }

  void _handleRightEdgeDrag(double deltaX) {
    final clip = widget.clip;
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

    if (clip.sourceDuration != null) {
      final maxDuration = clip.sourceDuration! - clip.sourceOffset;
      newDuration = newDuration.clamp(0.1, maxDuration);
    }

    widget.onResize?.call(clip.startTime, newDuration, null);
  }
}

// ==============================================================================
// GLASS WAVEFORM
// ==============================================================================

class _GlassClipWaveform extends StatefulWidget {
  final String clipId;
  final Float32List waveform;
  final Float32List? waveformRight;
  final double sourceOffset;
  final double duration;
  final double gain;
  final double zoom;
  final Color clipColor;
  final double trackHeight;

  const _GlassClipWaveform({
    required this.clipId,
    required this.waveform,
    this.waveformRight,
    required this.sourceOffset,
    required this.duration,
    required this.gain,
    required this.zoom,
    required this.clipColor,
    required this.trackHeight,
  });

  @override
  State<_GlassClipWaveform> createState() => _GlassClipWaveformState();
}

class _GlassClipWaveformState extends State<_GlassClipWaveform> {
  static const int _fixedPixels = 1024;

  WaveformPixelData? _cachedData;
  int _cachedClipId = 0;
  double _cachedSourceOffset = -1;
  double _cachedDuration = -1;

  @override
  void initState() {
    super.initState();
    _loadCacheOnce();
  }

  @override
  void didUpdateWidget(_GlassClipWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clipChanged = widget.clipId != oldWidget.clipId;
    final offsetChanged = (widget.sourceOffset - oldWidget.sourceOffset).abs() > 0.01;
    final durationChanged = (widget.duration - oldWidget.duration).abs() > 0.01;

    if (clipChanged || offsetChanged || durationChanged) {
      _loadCacheOnce();
    }
  }

  void _loadCacheOnce() {
    final clipIdNum = int.tryParse(widget.clipId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (clipIdNum <= 0 || widget.duration <= 0) return;

    if (_cachedClipId == clipIdNum &&
        (_cachedSourceOffset - widget.sourceOffset).abs() < 0.01 &&
        (_cachedDuration - widget.duration).abs() < 0.01) {
      return;
    }

    final sampleRate = NativeFFI.instance.getWaveformSampleRate(clipIdNum);
    final totalSamples = NativeFFI.instance.getWaveformTotalSamples(clipIdNum);
    if (totalSamples <= 0) return;

    final startFrame = (widget.sourceOffset * sampleRate).round();
    final endFrame = ((widget.sourceOffset + widget.duration) * sampleRate).round();

    final data = NativeFFI.instance.queryWaveformPixels(
      clipIdNum, startFrame, endFrame, _fixedPixels,
    );

    if (data != null && !data.isEmpty) {
      _cachedData = data;
      _cachedClipId = clipIdNum;
      _cachedSourceOffset = widget.sourceOffset;
      _cachedDuration = widget.duration;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.waveform.isEmpty && _cachedData == null) {
      return const SizedBox.shrink();
    }

    if (_cachedData != null && !_cachedData!.isEmpty) {
      return RepaintBoundary(
        child: ClipRect(
          child: Transform.scale(
            scaleY: widget.gain,
            child: CustomPaint(
              size: Size.infinite,
              painter: _GlassWaveformPainter(
                mins: _cachedData!.mins,
                maxs: _cachedData!.maxs,
                rms: _cachedData!.rms,
                clipColor: widget.clipColor,
              ),
            ),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: ClipRect(
        child: Transform.scale(
          scaleY: widget.gain,
          child: CustomPaint(
            size: Size.infinite,
            painter: _GlassLegacyWaveformPainter(
              waveform: widget.waveform,
              sourceOffset: widget.sourceOffset,
              duration: widget.duration,
              clipColor: widget.clipColor,
            ),
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// GLASS WAVEFORM PAINTER
// ==============================================================================

class _GlassWaveformPainter extends CustomPainter {
  final Float32List mins;
  final Float32List maxs;
  final Float32List rms;
  final Color clipColor;

  _GlassWaveformPainter({
    required this.mins,
    required this.maxs,
    required this.rms,
    required this.clipColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (mins.isEmpty || size.width <= 0 || size.height <= 0) return;

    final centerY = size.height / 2;
    final amplitude = centerY * 0.92;
    final numSamples = mins.length;

    // Build waveform path
    final wavePath = Path();

    double sampleToX(int i) => numSamples > 1 ? (i / (numSamples - 1)) * size.width : size.width / 2;

    wavePath.moveTo(0, centerY - maxs[0] * amplitude);

    for (int i = 1; i < numSamples; i++) {
      wavePath.lineTo(sampleToX(i), centerY - maxs[i] * amplitude);
    }

    for (int i = numSamples - 1; i >= 0; i--) {
      wavePath.lineTo(sampleToX(i), centerY - mins[i] * amplitude);
    }

    wavePath.close();

    // Glass waveform gradient - lighter, more ethereal
    final gradient = ui.Gradient.linear(
      Offset(0, centerY - amplitude),
      Offset(0, centerY + amplitude),
      [
        Colors.white.withValues(alpha: 0.95),
        Colors.white.withValues(alpha: 0.7),
        Colors.white.withValues(alpha: 0.7),
        Colors.white.withValues(alpha: 0.95),
      ],
      [0.0, 0.45, 0.55, 1.0],
    );

    // Glow effect
    final glowPaint = Paint()
      ..shader = gradient
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 3)
      ..isAntiAlias = true;
    canvas.drawPath(wavePath, glowPaint);

    // Main fill
    canvas.drawPath(wavePath, Paint()
      ..shader = gradient
      ..style = PaintingStyle.fill
      ..isAntiAlias = true);

    // Subtle outline
    canvas.drawPath(wavePath, Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..isAntiAlias = true);

    // Zero line
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.1)
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(_GlassWaveformPainter oldDelegate) =>
      mins != oldDelegate.mins ||
      maxs != oldDelegate.maxs ||
      rms != oldDelegate.rms ||
      clipColor != oldDelegate.clipColor;
}

// ==============================================================================
// GLASS LEGACY WAVEFORM PAINTER (fallback)
// ==============================================================================

class _GlassLegacyWaveformPainter extends CustomPainter {
  final Float32List waveform;
  final double sourceOffset;
  final double duration;
  final Color clipColor;

  _GlassLegacyWaveformPainter({
    required this.waveform,
    required this.sourceOffset,
    required this.duration,
    required this.clipColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty || size.width <= 0 || size.height <= 0) return;

    final centerY = size.height / 2;
    final amplitude = centerY * 0.92;
    final samplesPerPixel = waveform.length / size.width;

    final peakPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1
      ..isAntiAlias = false;

    final rmsPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1
      ..isAntiAlias = false;

    for (double x = 0; x < size.width; x++) {
      final startIdx = (x * samplesPerPixel).floor().clamp(0, waveform.length - 1);
      final endIdx = ((x + 1) * samplesPerPixel).ceil().clamp(startIdx + 1, waveform.length);

      double minVal = waveform[startIdx];
      double maxVal = waveform[startIdx];
      double sumSq = 0;
      int count = 0;

      for (int i = startIdx; i < endIdx; i++) {
        final s = waveform[i];
        if (s < minVal) minVal = s;
        if (s > maxVal) maxVal = s;
        sumSq += s * s;
        count++;
      }

      final rmsVal = count > 0 ? math.sqrt(sumSq / count) : 0;

      final peakTop = centerY - maxVal * amplitude;
      final peakBottom = centerY - minVal * amplitude;
      canvas.drawLine(Offset(x, peakTop), Offset(x, peakBottom), peakPaint);

      final rmsTop = centerY - rmsVal * amplitude;
      final rmsBottom = centerY + rmsVal * amplitude;
      canvas.drawLine(Offset(x, rmsTop), Offset(x, rmsBottom), rmsPaint);
    }

    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.1)
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(_GlassLegacyWaveformPainter oldDelegate) =>
      waveform != oldDelegate.waveform || clipColor != oldDelegate.clipColor;
}

// ==============================================================================
// GLASS FADE OVERLAY PAINTER
// ==============================================================================

class _GlassFadeOverlayPainter extends CustomPainter {
  final bool isLeft;
  final FadeCurve curve;
  final Color clipColor;

  _GlassFadeOverlayPainter({
    required this.isLeft,
    required this.curve,
    required this.clipColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    final path = Path();
    const steps = 30;

    if (isLeft) {
      path.moveTo(0, 0);
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = t * size.width;
        final fadeGain = _evaluateCurve(t);
        final y = size.height * (1 - fadeGain);
        path.lineTo(x, y);
      }
      path.lineTo(size.width, 0);
      path.close();
    } else {
      path.moveTo(0, 0);
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = t * size.width;
        final fadeGain = _evaluateCurve(1 - t);
        final y = size.height * (1 - fadeGain);
        path.lineTo(x, y);
      }
      path.lineTo(size.width, 0);
      path.close();
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
  bool shouldRepaint(_GlassFadeOverlayPainter oldDelegate) =>
      isLeft != oldDelegate.isLeft ||
      curve != oldDelegate.curve ||
      clipColor != oldDelegate.clipColor;
}

// ==============================================================================
// GLASS FADE HANDLE
// ==============================================================================

class _GlassFadeHandle extends StatefulWidget {
  final double width;
  final double fadeTime;
  final bool isLeft;
  final bool isActive;
  final FadeCurve curve;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  const _GlassFadeHandle({
    required this.width,
    required this.fadeTime,
    required this.isLeft,
    required this.isActive,
    required this.curve,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  State<_GlassFadeHandle> createState() => _GlassFadeHandleState();
}

class _GlassFadeHandleState extends State<_GlassFadeHandle> {
  bool _isHovered = false;
  bool _isDragging = false;
  double _dragStartX = 0;
  double _accumulatedDelta = 0;

  @override
  Widget build(BuildContext context) {
    const handleSize = 16.0;

    return Positioned(
      left: widget.isLeft ? 0 : null,
      right: widget.isLeft ? null : 0,
      top: 0,
      bottom: 0,
      width: widget.width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Fade curve overlay
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GlassFadeCurvePainter(
                  isLeft: widget.isLeft,
                  isActive: widget.isActive || _isHovered,
                  curve: widget.curve,
                ),
              ),
            ),
          ),
          // Handle
          Positioned(
            left: widget.isLeft ? 2 : null,
            right: widget.isLeft ? null : 2,
            top: 2,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                fadeHandleActiveNotifier.value = true;
                _isDragging = true;
                _dragStartX = event.position.dx;
                _accumulatedDelta = 0;
                widget.onDragStart();
              },
              onPointerMove: (event) {
                if (_isDragging) {
                  final totalDelta = event.position.dx - _dragStartX;
                  final incrementalDelta = totalDelta - _accumulatedDelta;
                  _accumulatedDelta = totalDelta;
                  if (incrementalDelta.abs() > 0.5) {
                    widget.onDragUpdate(incrementalDelta);
                  }
                }
              },
              onPointerUp: (event) {
                fadeHandleActiveNotifier.value = false;
                if (_isDragging) {
                  _isDragging = false;
                  _accumulatedDelta = 0;
                  widget.onDragEnd();
                }
              },
              onPointerCancel: (event) {
                fadeHandleActiveNotifier.value = false;
                if (_isDragging) {
                  _isDragging = false;
                  _accumulatedDelta = 0;
                  widget.onDragEnd();
                }
              },
              child: MouseRegion(
                onEnter: (_) => setState(() => _isHovered = true),
                onExit: (_) => setState(() => _isHovered = false),
                cursor: SystemMouseCursors.resizeColumn,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: AnimatedContainer(
                      duration: LiquidGlassTheme.animFast,
                      width: handleSize,
                      height: handleSize,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: (widget.isActive || _isHovered)
                              ? [
                                  LiquidGlassTheme.accentCyan.withValues(alpha: 0.8),
                                  LiquidGlassTheme.accentCyan.withValues(alpha: 0.6),
                                ]
                              : [
                                  Colors.white.withValues(alpha: 0.7),
                                  Colors.white.withValues(alpha: 0.5),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: (widget.isActive || _isHovered)
                              ? LiquidGlassTheme.accentCyan
                              : Colors.white.withValues(alpha: 0.5),
                          width: 1,
                        ),
                        boxShadow: (widget.isActive || _isHovered)
                            ? [
                                BoxShadow(
                                  color: LiquidGlassTheme.accentCyan.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                  spreadRadius: -2,
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Icon(
                          widget.isLeft ? Icons.chevron_right : Icons.chevron_left,
                          size: 10,
                          color: (widget.isActive || _isHovered)
                              ? Colors.white
                              : LiquidGlassTheme.bgGradientEnd,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Fade time label
          if (widget.fadeTime > 0)
            Positioned(
              left: widget.isLeft ? 4 : null,
              right: widget.isLeft ? null : 4,
              bottom: 4,
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: (_isHovered || widget.isActive)
                              ? LiquidGlassTheme.accentCyan.withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        _formatFadeTime(),
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'JetBrains Mono',
                          color: (_isHovered || widget.isActive)
                              ? LiquidGlassTheme.accentCyan
                              : Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
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

  String _formatFadeTime() {
    final seconds = widget.fadeTime;
    if (seconds < 0.01) return '0ms';
    if (seconds < 1.0) return '${(seconds * 1000).round()}ms';
    if (seconds < 10.0) return '${seconds.toStringAsFixed(2)}s';
    return '${seconds.toStringAsFixed(1)}s';
  }
}

// ==============================================================================
// GLASS FADE CURVE PAINTER
// ==============================================================================

class _GlassFadeCurvePainter extends CustomPainter {
  final bool isLeft;
  final bool isActive;
  final FadeCurve curve;

  _GlassFadeCurvePainter({
    required this.isLeft,
    required this.isActive,
    required this.curve,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isActive
          ? LiquidGlassTheme.accentCyan.withValues(alpha: 0.2)
          : Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final path = Path();
    const steps = 30;

    if (isLeft) {
      path.moveTo(0, 0);
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = t * size.width;
        final fadeGain = _evaluateCurve(t);
        final y = size.height * (1 - fadeGain);
        path.lineTo(x, y);
      }
      path.lineTo(size.width, 0);
      path.close();
    } else {
      path.moveTo(0, 0);
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = t * size.width;
        final fadeGain = _evaluateCurve(1 - t);
        final y = size.height * (1 - fadeGain);
        path.lineTo(x, y);
      }
      path.lineTo(size.width, 0);
      path.close();
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
  bool shouldRepaint(_GlassFadeCurvePainter oldDelegate) =>
      isLeft != oldDelegate.isLeft ||
      isActive != oldDelegate.isActive ||
      curve != oldDelegate.curve;
}

// ==============================================================================
// GLASS EDGE HANDLE
// ==============================================================================

class _GlassEdgeHandle extends StatefulWidget {
  final bool isLeft;
  final bool isActive;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  const _GlassEdgeHandle({
    required this.isLeft,
    required this.isActive,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  State<_GlassEdgeHandle> createState() => _GlassEdgeHandleState();
}

class _GlassEdgeHandleState extends State<_GlassEdgeHandle> {
  double _startX = 0;
  bool _isHovered = false;

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
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
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
          child: AnimatedContainer(
            duration: LiquidGlassTheme.animFast,
            decoration: BoxDecoration(
              gradient: (widget.isActive || _isHovered)
                  ? LinearGradient(
                      begin: widget.isLeft ? Alignment.centerRight : Alignment.centerLeft,
                      end: widget.isLeft ? Alignment.centerLeft : Alignment.centerRight,
                      colors: [
                        LiquidGlassTheme.accentBlue.withValues(alpha: 0.6),
                        LiquidGlassTheme.accentBlue.withValues(alpha: 0.2),
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.only(
                topLeft: widget.isLeft ? const Radius.circular(6) : Radius.zero,
                bottomLeft: widget.isLeft ? const Radius.circular(6) : Radius.zero,
                topRight: widget.isLeft ? Radius.zero : const Radius.circular(6),
                bottomRight: widget.isLeft ? Radius.zero : const Radius.circular(6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// GLASS GAIN HANDLE
// ==============================================================================

class _GlassGainHandle extends StatelessWidget {
  final double gain;
  final String gainDisplay;
  final bool isActive;
  final bool locked;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;

  const _GlassGainHandle({
    required this.gain,
    required this.gainDisplay,
    required this.isActive,
    required this.locked,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart: (_) {
        if (!locked) onDragStart();
      },
      onVerticalDragUpdate: (details) {
        if (!locked) {
          final delta = -details.delta.dy / 50;
          onDragUpdate(delta);
        }
      },
      onVerticalDragEnd: (_) => onDragEnd(),
      onDoubleTap: () {
        if (!locked) onReset();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: AnimatedContainer(
            duration: LiquidGlassTheme.animFast,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isActive
                    ? [
                        LiquidGlassTheme.accentBlue.withValues(alpha: 0.7),
                        LiquidGlassTheme.accentBlue.withValues(alpha: 0.5),
                      ]
                    : [
                        Colors.black.withValues(alpha: 0.5),
                        Colors.black.withValues(alpha: 0.4),
                      ],
              ),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: isActive
                    ? LiquidGlassTheme.accentBlue
                    : Colors.white.withValues(alpha: 0.2),
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: LiquidGlassTheme.accentBlue.withValues(alpha: 0.4),
                        blurRadius: 6,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: Text(
              gainDisplay,
              style: TextStyle(
                fontSize: 9,
                color: LiquidGlassTheme.textPrimary,
                fontFamily: 'JetBrains Mono',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// NOTE: Classic mode uses the original ClipWidget from clip_widget.dart
// The ThemeAwareClipWidget delegates to ClipWidget when not in Glass mode
// ==============================================================================
