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
import 'package:provider/provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../models/timeline_models.dart';
import '../../models/middleware_models.dart' show FadeCurve;
import '../../providers/editor_mode_provider.dart';
import '../../providers/smart_tool_provider.dart';
import '../editors/clip_fx_editor.dart';
import '../../src/rust/native_ffi.dart';

import 'stretch_overlay.dart';

/// ValueNotifier to coordinate fade handle interactions across clip widgets
/// Replaces the anti-pattern of a mutable global boolean
/// When true, other clip widgets should ignore drag events to prevent conflicts
final ValueNotifier<bool> fadeHandleActiveNotifier = ValueNotifier<bool>(false);

/// Convenience getter for cleaner code
bool get fadeHandleActiveGlobal => fadeHandleActiveNotifier.value;

/// Convenience setter that notifies listeners
set fadeHandleActiveGlobal(bool value) => fadeHandleActiveNotifier.value = value;

class ClipWidget extends StatefulWidget {
  final TimelineClip clip;
  final double zoom;
  final double scrollOffset;
  final double trackHeight;
  final ValueChanged<bool>? onSelect;
  final ValueChanged<double>? onMove;
  /// Called continuously during drag with the current snapped position
  /// (for real-time Channel Tab update — UI only, no FFI)
  final ValueChanged<double>? onDragLivePosition;
  /// Called during vertical drag with Y delta to indicate cross-track intent
  final void Function(double newStartTime, double verticalDelta)? onCrossTrackDrag;
  /// Called when cross-track drag ends
  final VoidCallback? onCrossTrackDragEnd;
  /// Smooth drag callbacks (Cubase-style ghost preview)
  final void Function(Offset globalPosition, Offset localPosition)? onDragStart;
  final void Function(Offset globalPosition)? onDragUpdate;
  final void Function(Offset globalPosition)? onDragEnd;
  final ValueChanged<double>? onGainChange;
  final void Function(double fadeIn, double fadeOut)? onFadeChange;
  final void Function(double newStartTime, double newDuration, double? newOffset)?
      onResize;
  /// Called when resize drag ends - for final FFI commit
  final VoidCallback? onResizeEnd;
  final ValueChanged<String>? onRename;
  final ValueChanged<double>? onSlipEdit;
  final VoidCallback? onOpenFxEditor;
  final VoidCallback? onOpenAudioEditor;
  /// Context menu callbacks
  final VoidCallback? onDelete;
  final VoidCallback? onDuplicate;
  /// Alt+drag: duplicate clip at new position (Cubase/Logic style)
  /// Threshold-based: small movement (<8px total) = split, large = duplicate
  final ValueChanged<double>? onDuplicateToPosition;
  final VoidCallback? onSplit;
  final VoidCallback? onMute;
  /// Called when Glue tool clicks this clip (glue with next adjacent)
  final VoidCallback? onGlue;
  /// Called when clip audio is reversed (toggle)
  final VoidCallback? onReverse;
  /// Called when loop handle is toggled (Logic Pro X style)
  final VoidCallback? onLoopToggle;
  /// Called when loop duration changes via drag (extends clip duration for looped content)
  final ValueChanged<double>? onLoopDurationChange;
  /// Called when time stretch drag changes clip duration (Logic Pro X Flex Time)
  /// Parameters: (newDuration, stretchRatio) — ratio = newDuration / originalDuration
  final void Function(double newDuration, double stretchRatio)? onTimeStretch;
  /// Called when time stretch drag ends — for FFI commit
  final VoidCallback? onTimeStretchEnd;
  /// Called when split at specific position (Cubase Alt+click)
  final ValueChanged<double>? onSplitAtPosition;
  /// Called when clip is moved in Shuffle mode — clips should push neighbors
  final ValueChanged<double>? onShuffleMove;
  final ValueChanged<double>? onPlayheadMove;
  /// Warp marker moved (markerId, newTimelinePos in seconds relative to clip)
  final void Function(int markerId, double newTimelinePos)? onWarpMarkerMove;
  /// Warp marker drag ended (markerId, originalPos, finalPos) — for undo recording
  final void Function(int markerId, double originalPos, double finalPos)? onWarpMarkerMoveEnd;
  /// Double-click at position to create warp marker (timelinePos in seconds relative to clip)
  final ValueChanged<double>? onWarpMarkerCreate;
  /// Right-click → pitch preset on warp marker (markerId, semitones)
  final void Function(int markerId, double semitones)? onWarpMarkerPitchChanged;
  /// Quantize warp markers to grid (gridInterval seconds, strength 0-1)
  final void Function(double gridInterval, double strength)? onWarpQuantize;
  /// Create warp markers from detected transients then quantize to grid
  final VoidCallback? onWarpToTempo;
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
    this.onDragLivePosition,
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
    this.onDuplicateToPosition,
    this.onSplit,
    this.onMute,
    this.onGlue,
    this.onReverse,
    this.onLoopToggle,
    this.onLoopDurationChange,
    this.onTimeStretch,
    this.onTimeStretchEnd,
    this.onSplitAtPosition,
    this.onShuffleMove,
    this.onPlayheadMove,
    this.onWarpMarkerMove,
    this.onWarpMarkerMoveEnd,
    this.onWarpMarkerCreate,
    this.onWarpMarkerPitchChanged,
    this.onWarpQuantize,
    this.onWarpToTempo,
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
  bool _isDraggingVolumeHandle = false; // Cubase volume handle (top-center)
  bool _isDraggingTimeStretch = false; // Logic Pro X Flex Time stretch
  bool _isDraggingLoopHandle = false; // Loop handle drag (extends clip duration)
  // Alt+drag duplicate: true when Alt is held during drag
  bool _isDuplicateDrag = false;
  // Click time at onPanStart (for split when tiny movement with Alt)
  double _duplicateDragClickTime = 0;
  // Total drag distance for click vs drag disambiguation (>8px = real drag)
  double _totalDragDistance = 0;
  double _loopDragStartDuration = 0; // Duration at drag start
  bool _timeStretchFromLeft = false; // Which edge initiated the stretch
  double _timeStretchOrigDuration = 0; // Original duration at drag start
  bool _isEditing = false;
  int? _draggingWarpMarkerId; // Currently dragged warp marker (for overlay guide)

  // Smart Tool — last hit test result for cursor + drag routing
  SmartToolHitResult? _smartToolHitResult;
  // Hover position for split tool scissors tracking
  double? _hoverLocalX;

  // Trackpad two-finger gesture detection
  // Two-finger pan on trackpad should scroll, not drag clips
  // Only three-finger drag (equivalent to click+drag) should move clips
  bool _isTrackpadPanActive = false;

  // Double-tap detection
  DateTime? _lastTapTime;
  static const _doubleTapThreshold = Duration(milliseconds: 300);

  late TextEditingController _nameController;
  late FocusNode _focusNode;

  // Drag start values
  double _dragStartTime = 0;
  double _dragStartDuration = 0;
  double _dragStartMouseX = 0;
  double _dragStartMouseY = 0;
  double _dragStartSourceOffset = 0;
  Offset _lastDragPosition = Offset.zero;
  double _lastSnappedTime = 0;
  bool _isCrossTrackDrag = false;
  bool _wasCrossTrackDrag = false; // Track if cross-track drag was ever triggered

  // Modifier keys captured at pointer down (reliable, not stale)
  bool _pointerDownCtrl = false;
  bool _pointerDownAlt = false;
  bool _pointerDownShift = false;

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

  /// Check if clip has time stretch applied
  bool _hasTimeStretch(TimelineClip clip) {
    // Check stretchRatio field first (from Flex Time drag)
    if (clip.stretchRatio != 1.0) return true;
    // Fallback: check FX chain for time stretch slot
    return clip.fxChain.slots.any((s) => s.type == ClipFxType.timeStretch && !s.bypass);
  }

  /// Get time stretch ratio from clip
  double _getStretchRatio(TimelineClip clip) {
    // Use stretchRatio field first (from Flex Time drag)
    if (clip.stretchRatio != 1.0) return clip.stretchRatio;
    // Fallback: calculate from duration vs source duration
    if (clip.sourceDuration != null && clip.sourceDuration! > 0) {
      return clip.duration / clip.sourceDuration!;
    }
    return 1.0;
  }

  void _startEditing() {
    // If double-click on audio clip with source file, open audio editor
    if (widget.clip.sourceFile != null && widget.onOpenAudioEditor != null) {
      widget.onOpenAudioEditor!();
      return;
    }

    // Otherwise, rename editing (for MIDI clips or clips without source)
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

  /// Show context menu on right-click
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
      items: [
        // Audio Editor (only for audio clips with source file)
        if (clip.sourceFile != null && widget.onOpenAudioEditor != null)
          PopupMenuItem(
            value: 'audio_editor',
            child: Row(
              children: [
                Icon(Icons.graphic_eq, size: 18, color: FluxForgeTheme.accentBlue),
                const SizedBox(width: 8),
                Text('Edit Audio', style: TextStyle(color: FluxForgeTheme.accentBlue)),
                const Spacer(),
                Text('Double-Click', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10)),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'rename',
          enabled: !clip.locked,
          child: Row(
            children: [
              Icon(Icons.edit, size: 18, color: clip.locked ? FluxForgeTheme.textTertiary : null),
              const SizedBox(width: 8),
              Text('Rename', style: clip.locked ? TextStyle(color: FluxForgeTheme.textTertiary) : null),
              const Spacer(),
              Text('F2', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'duplicate',
          enabled: !clip.locked,
          child: Row(
            children: [
              Icon(Icons.copy, size: 18, color: clip.locked ? FluxForgeTheme.textTertiary : null),
              const SizedBox(width: 8),
              Text('Duplicate', style: clip.locked ? TextStyle(color: FluxForgeTheme.textTertiary) : null),
              const Spacer(),
              Text('⌘D', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'split',
          enabled: !clip.locked,
          child: Row(
            children: [
              Icon(Icons.content_cut, size: 18, color: clip.locked ? FluxForgeTheme.textTertiary : null),
              const SizedBox(width: 8),
              Text('Split at Playhead', style: clip.locked ? TextStyle(color: FluxForgeTheme.textTertiary) : null),
              const Spacer(),
              Text('S', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'mute',
          child: Row(
            children: [
              Icon(clip.muted ? Icons.volume_up : Icons.volume_off, size: 18),
              const SizedBox(width: 8),
              Text(clip.muted ? 'Unmute' : 'Mute'),
              const Spacer(),
              Text('M', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'reverse',
          enabled: !clip.locked,
          child: Row(
            children: [
              Icon(Icons.swap_horiz, size: 18,
                color: clip.reversed ? FluxForgeTheme.accentCyan : null),
              const SizedBox(width: 8),
              Text(clip.reversed ? 'Unreverse' : 'Reverse',
                style: clip.reversed ? TextStyle(color: FluxForgeTheme.accentCyan) : null),
              const Spacer(),
              Text('R', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'fx',
          child: Row(
            children: [
              const Icon(Icons.auto_fix_high, size: 18),
              const SizedBox(width: 8),
              const Text('Clip FX...'),
            ],
          ),
        ),
        // ═══ Warp / Quantize (Phase 5) ═══
        if (clip.warpEnabled) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'warp_quantize',
            enabled: clip.warpMarkers.isNotEmpty && !clip.locked,
            child: Row(
              children: [
                Icon(Icons.grid_on, size: 18,
                  color: clip.warpMarkers.isNotEmpty && !clip.locked
                      ? FluxForgeTheme.accentGreen : FluxForgeTheme.textTertiary),
                const SizedBox(width: 8),
                const Text('Quantize Warp Markers'),
                const Spacer(),
                Text('Q', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 12)),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'warp_to_tempo',
            enabled: !clip.locked,
            child: Row(
              children: [
                Icon(Icons.music_note, size: 18,
                  color: !clip.locked ? FluxForgeTheme.accentOrange : FluxForgeTheme.textTertiary),
                const SizedBox(width: 8),
                const Text('Warp to Tempo'),
              ],
            ),
          ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          enabled: !clip.locked,
          child: Row(
            children: [
              Icon(Icons.delete, size: 18, color: clip.locked ? FluxForgeTheme.textTertiary : FluxForgeTheme.accentRed),
              const SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: clip.locked ? FluxForgeTheme.textTertiary : FluxForgeTheme.accentRed)),
              const Spacer(),
              Text('⌫', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 12)),
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
        case 'reverse':
          if (!clip.locked) widget.onReverse?.call();
          break;
        case 'fx':
          widget.onOpenFxEditor?.call();
          break;
        case 'warp_quantize':
          if (!clip.locked && clip.warpMarkers.isNotEmpty) {
            // Quantize to beat grid: gridInterval = 60/tempo * snapValue
            final beatDuration = 60.0 / widget.tempo;
            final gridInterval = beatDuration * widget.snapValue;
            widget.onWarpQuantize?.call(gridInterval, 1.0);
          }
          break;
        case 'warp_to_tempo':
          if (!clip.locked) widget.onWarpToTempo?.call();
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

    // Safety: if gain handle won't render (width <= 60) but drag is active, force reset
    if (_isDraggingGain && width <= 60) {
      _isDraggingGain = false;
    }

    // Skip if not visible
    // Cull clips outside visible viewport — use large fallback (context.size not available during build)
    const viewportWidth = 4096.0;
    if (x + width < 0 || x > viewportWidth + 200) {
      if (_isDraggingGain) _isDraggingGain = false;
      return const SizedBox.shrink();
    }

    final clipHeight = widget.trackHeight - 4;
    // Use clip's color (synced with track color) or fallback to default track blue
    final clipColor = clip.color ?? FluxForgeTheme.trackBlue;

    // PERFORMANCE FIX: Minimum width must scale with zoom to maintain proportionality
    // At very low zoom, clips can legitimately be < 4px wide
    // Use 2px as absolute minimum (for selection), but scale with zoom
    final minWidth = (0.05 * widget.zoom).clamp(2.0, 4.0); // 50ms minimum visibility
    final clampedWidth = width.clamp(minWidth, double.infinity);

    return Positioned(
      left: x,
      top: 2,
      width: clampedWidth,
      height: clipHeight,
      // Dim original clip during move drag (ghost shows the preview)
      child: Opacity(
        opacity: _isDraggingMove ? 0.35 : 1.0,
      // Smart Tool — dynamic cursor based on hover position
      child: Consumer<SmartToolProvider>(
        builder: (context, smartTool, child) {
          final smartEnabled = smartTool.enabled;
          final activeTool = smartTool.activeTool;
          // Explicit tool mode: use tool-specific cursor over clips
          final bool isExplicitTool = activeTool != TimelineEditTool.smart &&
              activeTool != TimelineEditTool.objectSelect;
          return MouseRegion(
            cursor: isExplicitTool
                ? smartTool.activeToolCursor
                : (smartEnabled && _smartToolHitResult != null
                    ? _smartToolHitResult!.cursor
                    : MouseCursor.defer),
            onHover: (event) {
                    final localPos = event.localPosition;
                    // Smart tool hit test for zone detection
                    if (smartEnabled && !isExplicitTool) {
                      final clipBounds = Rect.fromLTWH(0, 0, clampedWidth, clipHeight);
                      final result = smartTool.hitTest(
                        position: localPos,
                        clipBounds: clipBounds,
                        clipId: clip.id,
                      );
                      if (_smartToolHitResult?.mode != result.mode) {
                        setState(() => _smartToolHitResult = result);
                      }
                    }
                    // Track hover X for split tool scissors
                    if (isExplicitTool && activeTool == TimelineEditTool.split) {
                      setState(() => _hoverLocalX = localPos.dx);
                    }
                  },
            onExit: (_) {
                    if (_smartToolHitResult != null || _hoverLocalX != null) {
                      setState(() {
                        _smartToolHitResult = null;
                        _hoverLocalX = null;
                      });
                    }
                  },
      // Listener detects trackpad two-finger pan (scroll gesture)
      // to prevent it from being interpreted as clip drag
      child: Listener(
        onPointerDown: (event) {
          // Capture modifier keys IMMEDIATELY at pointer down (reliable)
          // HardwareKeyboard can have stale state by the time onPanStart fires
          _pointerDownCtrl = HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;
          _pointerDownAlt = HardwareKeyboard.instance.isAltPressed;
          _pointerDownShift = HardwareKeyboard.instance.isShiftPressed;
        },
        onPointerPanZoomStart: (_) {
          // Two-finger trackpad gesture started - this is scroll, not drag
          _isTrackpadPanActive = true;
        },
        onPointerPanZoomEnd: (_) {
          // Two-finger trackpad gesture ended
          _isTrackpadPanActive = false;
        },
        child: GestureDetector(
          onTapDown: (details) {
            if (fadeHandleActiveGlobal) return;
            if (_isDraggingFadeIn || _isDraggingFadeOut) return;

            final clickX = details.localPosition.dx;
            final clickY = details.localPosition.dy;
            // Ignore fade handle zones (top 20px corners)
            const fadeHandleZone = 20.0;
            if (clickY < fadeHandleZone) {
              if (clickX < fadeHandleZone || clickX > width - fadeHandleZone) {
                return;
              }
            }

            // ═══ Cubase-style tool dispatch on clip click ═══
            if (isExplicitTool) {
              switch (activeTool) {
                case TimelineEditTool.split:
                  // Split at exact click position (Cubase scissors behavior)
                  // Snap to grid when snap is enabled
                  if (!clip.locked) {
                    var clickTime = clip.startTime + clickX / widget.zoom;
                    if (widget.snapEnabled) {
                      clickTime = applySnap(clickTime, true, widget.snapValue, widget.tempo, widget.allClips);
                    }
                    if (widget.onSplitAtPosition != null) {
                      widget.onSplitAtPosition!(clickTime);
                    } else {
                      widget.onPlayheadMove?.call(clickTime);
                      widget.onSplit?.call();
                    }
                  }
                  return;
                case TimelineEditTool.erase:
                  // Delete clip on click
                  if (!clip.locked) {
                    widget.onDelete?.call();
                  }
                  return;
                case TimelineEditTool.mute:
                  // Toggle mute on click
                  widget.onMute?.call();
                  return;
                case TimelineEditTool.glue:
                  // Glue tool click: select this clip + glue with next adjacent
                  widget.onSelect?.call(_pointerDownShift);
                  widget.onGlue?.call();
                  return;
                case TimelineEditTool.zoom:
                  // Zoom tool on clip: zoom in centered at click
                  // Alt+click = zoom out (handled in Timeline)
                  return;
                case TimelineEditTool.play:
                  // Play tool: move playhead to click position
                  // clickX is widget-local, so absolute time = clip.startTime + clickX/zoom
                  final clickTime = clip.startTime + clickX / widget.zoom;
                  widget.onPlayheadMove?.call(clickTime);
                  return;
                default:
                  break; // smart, objectSelect, rangeSelect, draw — fall through to select
              }
            }

            // Default: select clip
            widget.onSelect?.call(_pointerDownShift);
          },
          onDoubleTap: _startEditing,
          onSecondaryTapDown: (details) {
            // Select clip on right-click before showing menu
            widget.onSelect?.call(_pointerDownShift);
            _showContextMenu(context, details.globalPosition);
          },
          onPanStart: (details) {
            // IGNORE if trackpad two-finger pan is active (that's scroll, not drag)
            // Only three-finger drag (equivalent to click+drag) should move clips
            if (_isTrackpadPanActive) return;

            // IGNORE if clip is locked
            if (clip.locked) return;

            // IGNORE if fade handle or gain handle is being dragged
            if (_isDraggingFadeIn || _isDraggingFadeOut || fadeHandleActiveGlobal || _isDraggingGain) {
              return;
            }

            // IGNORE drag for click-only tools (split, erase, mute, glue, play)
            if (isExplicitTool && (
              activeTool == TimelineEditTool.split ||
              activeTool == TimelineEditTool.erase ||
              activeTool == TimelineEditTool.mute ||
              activeTool == TimelineEditTool.glue ||
              activeTool == TimelineEditTool.play
            )) {
              return;
            }

            // Smart Tool routing — when enabled, use hit test to determine operation
            if (smartEnabled && _smartToolHitResult != null) {
              final mode = _smartToolHitResult!.mode;

              // Modifier-based overrides (Cubase + Pro Tools)
              // Use captured modifiers from onPointerDown (reliable, not stale)
              final isAlt = _pointerDownAlt;
              final isShift = _pointerDownShift;

              // Alt+drag in Move zone = Duplicate clip (Cubase/Logic style)
              // Threshold-based: < 8px total movement → treated as click → split
              // > 8px movement → true drag → duplicate at new position
              // Alt+click split is handled via onTap; onPanStart fires even for clicks
              if (mode == SmartToolMode.select && isAlt && !isShift) {
                if (!clip.locked) {
                  _dragStartTime = clip.startTime;
                  _dragStartMouseX = details.globalPosition.dx;
                  _dragStartMouseY = details.globalPosition.dy;
                  _lastDragPosition = details.globalPosition;
                  _wasCrossTrackDrag = false;
                  _isDuplicateDrag = true;
                  _totalDragDistance = 0.0;
                  var clickTime = clip.startTime + details.localPosition.dx / widget.zoom;
                  if (widget.snapEnabled) {
                    clickTime = applySnap(clickTime, true, widget.snapValue, widget.tempo, widget.allClips);
                  }
                  _duplicateDragClickTime = clickTime;
                  setState(() => _isDraggingMove = true);
                  widget.onDragStart?.call(details.globalPosition, details.localPosition);
                }
                return;
              }

              // Alt+Shift in Move zone = Slip content (Cubase)
              if (mode == SmartToolMode.select && isAlt && isShift) {
                _dragStartSourceOffset = clip.sourceOffset;
                _dragStartMouseX = details.globalPosition.dx;
                setState(() => _isSlipEditing = true);
                return;
              }

              switch (mode) {
                case SmartToolMode.trimLeft:
                  _dragStartTime = clip.startTime;
                  _dragStartDuration = clip.duration;
                  _dragStartSourceOffset = clip.sourceOffset;
                  _dragStartMouseX = details.globalPosition.dx;
                  setState(() => _isDraggingLeftEdge = true);
                  return;
                case SmartToolMode.trimRight:
                  _dragStartDuration = clip.duration;
                  _dragStartMouseX = details.globalPosition.dx;
                  setState(() => _isDraggingRightEdge = true);
                  return;
                case SmartToolMode.fadeIn:
                  setState(() => _isDraggingFadeIn = true);
                  fadeHandleActiveGlobal = true;
                  return;
                case SmartToolMode.fadeOut:
                  setState(() => _isDraggingFadeOut = true);
                  fadeHandleActiveGlobal = true;
                  return;
                case SmartToolMode.volumeHandle:
                  // Volume handle — vertical drag for clip gain (Cubase)
                  _dragStartMouseY = details.globalPosition.dy;
                  setState(() => _isDraggingVolumeHandle = true);
                  return;
                case SmartToolMode.timeStretch:
                  // Time stretch — Logic Pro X Flex Time style
                  _dragStartDuration = clip.duration;
                  _dragStartMouseX = details.globalPosition.dx;
                  _timeStretchOrigDuration = clip.duration;
                  _timeStretchFromLeft = _smartToolHitResult!.localPosition.dx < ((_smartToolHitResult!.clipBounds?.width ?? 100) / 2);
                  setState(() => _isDraggingTimeStretch = true);
                  return;
                case SmartToolMode.loopHandle:
                  // Loop handle drag — enable loop and extend duration (Logic Pro X)
                  if (!clip.loopEnabled) {
                    widget.onLoopToggle?.call();
                  }
                  _loopDragStartDuration = clip.duration;
                  _dragStartMouseX = details.globalPosition.dx;
                  setState(() => _isDraggingLoopHandle = true);
                  return;
                case SmartToolMode.rangeSelectBody:
                  // Range select in upper body — fall through to range logic
                  // Ctrl+click = Scrub (Pro Tools)
                  if (_pointerDownCtrl) {
                    // Scrub at click position (localPosition is widget-relative)
                    final clickTime = clip.startTime + details.localPosition.dx / widget.zoom;
                    widget.onPlayheadMove?.call(clickTime);
                    return;
                  }
                  // Otherwise start range selection in clip
                  break;
                case SmartToolMode.slipContent:
                  _dragStartSourceOffset = clip.sourceOffset;
                  _dragStartMouseX = details.globalPosition.dx;
                  setState(() => _isSlipEditing = true);
                  return;
                case SmartToolMode.select:
                  // Move mode — fall through to normal move logic below
                  break;
                default:
                  break;
              }
            }

            // Edit Mode: Slip mode forces slip edit (no modifier needed)
            final editMode = smartTool.activeEditMode;
            final isSlipMode = editMode == TimelineEditMode.slip;
            // Check for modifier keys for slip edit (captured at pointer down)
            if (isSlipMode || _pointerDownCtrl) {
              _dragStartSourceOffset = clip.sourceOffset;
              _dragStartMouseX = details.globalPosition.dx;
              setState(() => _isSlipEditing = true);
            } else if (_pointerDownAlt && !_pointerDownShift && !clip.locked) {
              // Alt+drag (non-smart-tool) = Duplicate clip (Cubase/Logic style)
              // Smart-tool Alt is handled above in SmartToolMode.select block
              _dragStartTime = clip.startTime;
              _dragStartMouseX = details.globalPosition.dx;
              _dragStartMouseY = details.globalPosition.dy;
              _lastDragPosition = details.globalPosition;
              _wasCrossTrackDrag = false;
              _isDuplicateDrag = true;
              _totalDragDistance = 0.0;
              var clickTime = clip.startTime + details.localPosition.dx / widget.zoom;
              if (widget.snapEnabled) {
                clickTime = applySnap(clickTime, true, widget.snapValue, widget.tempo, widget.allClips);
              }
              _duplicateDragClickTime = clickTime;
              setState(() => _isDraggingMove = true);
              widget.onDragStart?.call(details.globalPosition, details.localPosition);
            } else {
              _dragStartTime = clip.startTime;
              _dragStartMouseX = details.globalPosition.dx;
              _dragStartMouseY = details.globalPosition.dy;
              _lastDragPosition = details.globalPosition;
              _wasCrossTrackDrag = false; // Reset at start of drag
              setState(() => _isDraggingMove = true);

              // Start smooth drag with ghost preview (Cubase-style)
              if (widget.onDragStart != null) {
                widget.onDragStart!(details.globalPosition, details.localPosition);
              }
            }
          },
        onPanUpdate: (details) {
          // Alt+drag duplicate: accumulate distance for click/drag disambiguation
          if (_isDuplicateDrag) _totalDragDistance += details.delta.distance;

          // Smart Tool — handle trim drags via pan gesture
          if (_isDraggingLeftEdge && smartEnabled) {
            double rawNewStartTime = _dragStartTime + (details.globalPosition.dx - _dragStartMouseX) / widget.zoom;
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
            widget.onResize?.call(newStartTime, newDuration.clamp(0.1, double.infinity), newOffset);
            return;
          }

          if (_isDraggingRightEdge && smartEnabled) {
            final deltaTime = (details.globalPosition.dx - _dragStartMouseX) / widget.zoom;
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
            return;
          }

          if ((_isDraggingFadeIn || _isDraggingFadeOut) && smartEnabled) {
            final deltaPixels = details.delta.dx;
            if (_isDraggingFadeIn) {
              final deltaSeconds = deltaPixels / widget.zoom;
              final newFadeIn = (clip.fadeIn + deltaSeconds).clamp(0.0, clip.duration * 0.5);
              widget.onFadeChange?.call(newFadeIn, clip.fadeOut);
            } else {
              final deltaSeconds = -deltaPixels / widget.zoom;
              final newFadeOut = (clip.fadeOut + deltaSeconds).clamp(0.0, clip.duration * 0.5);
              widget.onFadeChange?.call(clip.fadeIn, newFadeOut);
            }
            return;
          }

          // Volume handle drag — Cubase-style vertical gain adjustment
          if (_isDraggingVolumeHandle && smartEnabled) {
            final deltaY = details.globalPosition.dy - _dragStartMouseY;
            // Upward = boost, downward = cut — 200px for full range (-inf to +6dB)
            // Sensitivity: ~0.15dB per pixel
            final gainDelta = -deltaY / 200.0 * 2.0; // ±2.0 gain range over 200px
            final newGain = (clip.gain + gainDelta).clamp(0.0, 4.0);
            _dragStartMouseY = details.globalPosition.dy; // Incremental
            widget.onGainChange?.call(newGain);
            return;
          }

          // Loop handle drag — extend clip duration for looped content
          if (_isDraggingLoopHandle && smartEnabled) {
            final deltaPx = details.globalPosition.dx - _dragStartMouseX;
            final deltaSecs = deltaPx / widget.zoom;
            // Minimum duration = source duration (can't shrink below original)
            final sourceDur = clip.sourceDuration ?? clip.duration;
            final newDuration = (_loopDragStartDuration + deltaSecs).clamp(sourceDur, sourceDur * 100);
            widget.onLoopDurationChange?.call(newDuration);
            return;
          }

          // Time stretch drag — Logic Pro X Flex Time style
          if (_isDraggingTimeStretch && smartEnabled) {
            final deltaTime = (details.globalPosition.dx - _dragStartMouseX) / widget.zoom;
            double newDuration;
            if (_timeStretchFromLeft) {
              // Dragging left edge left = expand, right = compress
              newDuration = (_dragStartDuration - deltaTime).clamp(0.1, _dragStartDuration * 4.0);
            } else {
              // Dragging right edge right = expand, left = compress
              newDuration = (_dragStartDuration + deltaTime).clamp(0.1, _dragStartDuration * 4.0);
            }
            final stretchRatio = newDuration / _timeStretchOrigDuration;
            widget.onTimeStretch?.call(newDuration, stretchRatio);
            return;
          }

          // Gain handle drag — direct gain adjustment from label widget
          if (_isDraggingGain) {
            return; // Handled by Listener on gain handle widget
          }

          // IGNORE if fade handle is being dragged (non-smart-tool path)
          if (_isDraggingFadeIn || _isDraggingFadeOut || fadeHandleActiveGlobal) {
            return;
          }

          final deltaX = details.globalPosition.dx - _dragStartMouseX;
          final deltaY = details.globalPosition.dy - _dragStartMouseY;
          final deltaTime = deltaX / widget.zoom;
          _lastDragPosition = details.globalPosition;

          if (_isSlipEditing) {
            // Slip edit - offset changes inversely
            final newOffset = (_dragStartSourceOffset - deltaTime).clamp(0.0, double.infinity);
            widget.onSlipEdit?.call(newOffset);
          } else if (_isDraggingMove) {
            // Cubase-style drag - only show ghost, don't move original until drop
            double rawNewStartTime = _dragStartTime + deltaTime;

            // Edit Mode determines snapping behavior:
            // - Grid: Force snap even if snap toggle is off
            // - Spot: Snap to absolute timecode (1-second grid)
            // - Shuffle: Normal snap, push logic handled on drop
            // - Slip: Won't reach here (handled above as _isSlipEditing)
            final editMode = smartTool.activeEditMode;
            final bool forceSnap = editMode == TimelineEditMode.grid;
            final bool isSpotMode = editMode == TimelineEditMode.spot;

            double snappedTime;
            if (isSpotMode) {
              // Spot mode: snap to absolute 1-second grid (frame-level precision)
              snappedTime = (rawNewStartTime * 10).roundToDouble() / 10; // 0.1s grid
            } else {
              snappedTime = applySnap(
                rawNewStartTime,
                widget.snapEnabled || forceSnap,
                widget.snapValue,
                widget.tempo,
                widget.allClips,
              );
            }
            _lastSnappedTime = snappedTime.clamp(0.0, double.infinity);

            // Live position update for Channel Tab (UI-only, no FFI)
            widget.onDragLivePosition?.call(_lastSnappedTime);

            // Update ghost position (visual feedback)
            widget.onDragUpdate?.call(details.globalPosition);

            // Cross-track drag (vertical movement)
            final wasCrossTrack = _isCrossTrackDrag;
            _isCrossTrackDrag = deltaY.abs() > 20;
            if (_isCrossTrackDrag) {
              _wasCrossTrackDrag = true; // Remember if ever crossed track threshold
              widget.onCrossTrackDrag?.call(_lastSnappedTime, deltaY);
            } else if (wasCrossTrack && !_isCrossTrackDrag) {
              // Clip returned to source track zone — reset cross-track with delta 0
              widget.onCrossTrackDrag?.call(_lastSnappedTime, 0);
            }
            // Note: original clip position is NOT updated during drag
            // It will be updated on drop via onPanEnd
          }
        },
        onPanEnd: (details) {
          // Smart Tool trim/fade end — commit resize
          if ((_isDraggingLeftEdge || _isDraggingRightEdge) && smartEnabled) {
            widget.onResizeEnd?.call();
          }
          // Smart Tool fade end — release global flag
          if ((_isDraggingFadeIn || _isDraggingFadeOut) && smartEnabled) {
            fadeHandleActiveGlobal = false;
          }
          // Smart Tool time stretch end — commit stretch
          if (_isDraggingTimeStretch && smartEnabled) {
            widget.onTimeStretchEnd?.call();
          }
          // Smart Tool loop handle end — loop drag complete
          if (_isDraggingLoopHandle && smartEnabled) {
            // Duration already updated via onLoopDurationChange during drag
          }

          if (_isDraggingMove) {
            // Use _wasCrossTrackDrag to ensure cleanup even if user moved back
            if (_isCrossTrackDrag || _wasCrossTrackDrag) {
              // Cross-track drag - let timeline handle the move
              widget.onCrossTrackDragEnd?.call();
            }
            // Always call onMove for same-track or if cross-track resulted in same track
            if (!_isCrossTrackDrag) {
              if (_isDuplicateDrag) {
                // Alt+drag: threshold-based disambiguation
                // > 8px total movement = true drag → duplicate at new position (Cubase Alt+drag)
                // ≤ 8px = click → split at original click position (Cubase Alt+click)
                if (_totalDragDistance > 8.0) {
                  widget.onDuplicateToPosition?.call(_lastSnappedTime);
                } else {
                  // Tiny movement = Alt+click → split at cursor
                  if (widget.onSplitAtPosition != null) {
                    widget.onSplitAtPosition!(_duplicateDragClickTime);
                  } else {
                    widget.onSplit?.call();
                  }
                }
              } else {
                // Shuffle mode: use shuffle callback to push adjacent clips
                final editMode = smartTool.activeEditMode;
                if (editMode == TimelineEditMode.shuffle && widget.onShuffleMove != null) {
                  widget.onShuffleMove!(_lastSnappedTime);
                } else {
                  widget.onMove?.call(_lastSnappedTime);
                }
              }
            }
          }
          // ALWAYS call onDragEnd to clear ghost in timeline - no conditions
          widget.onDragEnd?.call(details.globalPosition);
          // Clear local state
          setState(() {
            _isDraggingMove = false;
            _isDuplicateDrag = false;
            _totalDragDistance = 0;
            _isSlipEditing = false;
            _isCrossTrackDrag = false;
            _wasCrossTrackDrag = false;
            _isDraggingLeftEdge = false;
            _isDraggingRightEdge = false;
            _isDraggingFadeIn = false;
            _isDraggingFadeOut = false;
            _isDraggingVolumeHandle = false;
            _isDraggingTimeStretch = false;
            _isDraggingLoopHandle = false;
            _isDraggingGain = false;
          });
        },
        onPanCancel: () {
          // Smart Tool fade cancel — release global flag
          if (_isDraggingFadeIn || _isDraggingFadeOut) {
            fadeHandleActiveGlobal = false;
          }
          // ALWAYS call onDragEnd to clear ghost - no conditions
          widget.onDragEnd?.call(_lastDragPosition);
          setState(() {
            _isDraggingMove = false;
            _isDuplicateDrag = false;
            _totalDragDistance = 0;
            _isSlipEditing = false;
            _isCrossTrackDrag = false;
            _wasCrossTrackDrag = false;
            _isDraggingLeftEdge = false;
            _isDraggingRightEdge = false;
            _isDraggingFadeIn = false;
            _isDraggingFadeOut = false;
            _isDraggingVolumeHandle = false;
            _isDraggingTimeStretch = false;
            _isDraggingLoopHandle = false;
            _isDraggingGain = false;
          });
        },
        child: Container(
          decoration: BoxDecoration(
            // Logic Pro style: BLUE background with WHITE waveform
            color: clipColor,
            borderRadius: BorderRadius.circular(4),
            border: clip.selected
                ? Border.all(color: Colors.white, width: 2)
                : Border.all(color: clipColor.withValues(alpha: 0.7), width: 1),
          ),
          child: Stack(
            children: [
              // Ultimate Waveform Display (best-in-class DAW waveform)
              // NO padding - waveform fills entire clip from edge to edge
              if (clip.waveform != null && width > 20)
                Positioned.fill(
                  child: _UltimateClipWaveform(
                    clipId: clip.id,
                    waveform: clip.waveform!,
                    waveformRight: clip.waveformRight,
                    sourceOffset: clip.sourceOffset,
                    duration: clip.duration,
                    gain: clip.gain,
                    zoom: widget.zoom,
                    clipColor: clipColor,
                    trackHeight: widget.trackHeight,
                    channels: clip.channels,
                    reversed: clip.reversed,
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
                          style: FluxForgeTheme.bodySmall.copyWith(
                            color: FluxForgeTheme.textPrimary,
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
                          style: FluxForgeTheme.bodySmall.copyWith(
                            color: FluxForgeTheme.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                ),

              // Reversed badge indicator
              if (clip.reversed && width > 30)
                Positioned(
                  right: 4,
                  top: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentCyan.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swap_horiz, size: 10, color: Colors.white),
                        SizedBox(width: 2),
                        Text('R', style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        )),
                      ],
                    ),
                  ),
                ),

              // Gain handle — uses Listener to bypass gesture arena (parent pan can't steal it)
              if (width > 60)
                Positioned(
                  top: 2,
                  left: (width - 40) / 2,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) {
                      if (clip.locked) return;
                      setState(() => _isDraggingGain = true);
                      _dragStartMouseY = event.position.dy;
                    },
                    onPointerMove: (event) {
                      if (!_isDraggingGain || clip.locked) return;
                      final deltaY = event.position.dy - _dragStartMouseY;
                      // Sensitivity: ~0.15dB per pixel, range 0.0-4.0
                      final gainDelta = -deltaY / 200.0 * 2.0;
                      final newGain = (widget.clip.gain + gainDelta).clamp(0.0, 4.0);
                      _dragStartMouseY = event.position.dy;
                      widget.onGainChange?.call(newGain);
                    },
                    onPointerUp: (event) {
                      setState(() => _isDraggingGain = false);
                    },
                    onPointerCancel: (event) {
                      setState(() => _isDraggingGain = false);
                    },
                    child: GestureDetector(
                      onDoubleTap: () {
                        if (clip.locked) return;
                        widget.onGainChange?.call(1.0); // Reset to 0dB
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: _isDraggingGain
                              ? FluxForgeTheme.accentBlue
                              : FluxForgeTheme.bgVoid.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          _gainDisplay,
                          style: TextStyle(
                            fontSize: 9,
                            color: FluxForgeTheme.textPrimary,
                            fontFamily: 'JetBrains Mono',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Fade visualizations (BEFORE handles so they are behind)
              if (clip.fadeIn > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: clip.fadeIn * widget.zoom,
                  child: CustomPaint(
                    painter: _FadeOverlayPainter(
                      isLeft: true,
                      curve: clip.fadeInCurve,
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
                    painter: _FadeOverlayPainter(
                      isLeft: false,
                      curve: clip.fadeOutCurve,
                    ),
                  ),
                ),

              // P3.3: Gain envelope visualization
              // Shows a horizontal line indicating clip gain level (when != unity)
              if (clip.gain != 1.0 && width > 30)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GainEnvelopePainter(
                      gain: clip.gain,
                      clipColor: clipColor,
                    ),
                  ),
                ),

              // Smart Tool: Volume handle indicator (Cubase-style, top-center)
              // Small diamond marker visible when smart tool is enabled and clip is wide enough
              if (!clip.locked && width > 60 && smartEnabled)
                Positioned(
                  left: width / 2 - 5,
                  top: 0,
                  child: _VolumeHandleIndicator(
                    isActive: _isDraggingVolumeHandle,
                    gain: clip.gain,
                  ),
                ),

              // Loop boundary markers (dashed lines at each loop point)
              if (clip.loopEnabled && clip.sourceDuration != null && clip.sourceDuration! > 0 && width > 40)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LoopBoundaryPainter(
                      sourceDuration: clip.sourceDuration!,
                      clipDuration: clip.duration,
                      zoom: widget.zoom,
                      isDragging: _isDraggingLoopHandle,
                    ),
                  ),
                ),

              // Loop indicator (Logic Pro X style, bottom-right) — visible whenever loopEnabled
              if (clip.loopEnabled && width > 60)
                Positioned(
                  right: 6,
                  bottom: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (clip.loopCount > 0)
                        Text(
                          '${clip.loopCount}\u00D7',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.cyan.withValues(alpha: 0.8),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      Icon(
                        Icons.loop,
                        size: 12,
                        color: _isDraggingLoopHandle
                            ? Colors.cyanAccent
                            : Colors.cyan.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),

              // Fade in handle (ON TOP of edge handle) - hidden when locked
              if (!clip.locked)
              _FadeHandle(
                width: (clip.fadeIn * widget.zoom).clamp(20.0, double.infinity),
                fadeTime: clip.fadeIn,
                isLeft: true,
                isActive: _isDraggingFadeIn,
                curve: clip.fadeInCurve,
                onDragStart: () => setState(() => _isDraggingFadeIn = true),
                onDragUpdate: (deltaPixels) {
                  // Convert delta pixels to seconds
                  final deltaSeconds = deltaPixels / widget.zoom;
                  final newFadeIn = (clip.fadeIn + deltaSeconds)
                      .clamp(0.0, clip.duration * 0.5);
                  widget.onFadeChange?.call(newFadeIn, clip.fadeOut);
                },
                onDragEnd: () => setState(() => _isDraggingFadeIn = false),
              ),

              // Fade out handle - hidden when locked
              if (!clip.locked)
              _FadeHandle(
                width: (clip.fadeOut * widget.zoom).clamp(20.0, double.infinity),
                fadeTime: clip.fadeOut,
                isLeft: false,
                isActive: _isDraggingFadeOut,
                curve: clip.fadeOutCurve,
                onDragStart: () => setState(() => _isDraggingFadeOut = true),
                onDragUpdate: (deltaPixels) {
                  // Convert delta pixels to seconds (negative delta = increase fade out)
                  final deltaSeconds = -deltaPixels / widget.zoom;
                  final newFadeOut = (clip.fadeOut + deltaSeconds)
                      .clamp(0.0, clip.duration * 0.5);
                  widget.onFadeChange?.call(clip.fadeIn, newFadeOut);
                },
                onDragEnd: () => setState(() => _isDraggingFadeOut = false),
              ),

              // Left edge resize handle (ON TOP - always accessible)
              if (!clip.locked)
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
                onDragEnd: () {
                  setState(() => _isDraggingLeftEdge = false);
                  widget.onResizeEnd?.call();
                },
              ),

              // Right edge resize handle (ON TOP - always accessible)
              if (!clip.locked)
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
                onDragEnd: () {
                  setState(() => _isDraggingRightEdge = false);
                  widget.onResizeEnd?.call();
                },
              ),

              // FX badge (bottom-right corner)
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

              // Time stretch badge (bottom-left, next to FX)
              if (_hasTimeStretch(clip) && width > 70)
                Positioned(
                  left: 4,
                  bottom: 2,
                  child: StretchIndicatorBadge(
                    stretchRatio: _getStretchRatio(clip),
                  ),
                ),

              // ═══ Warp markers + transient display (Phase 4 enhanced) ═══
              if (clip.warpEnabled && width > 30) ...[
                // Visual overlay: stretch regions, transient markers, warp lines
                Positioned.fill(
                  child: CustomPaint(
                    painter: _WarpOverlayPainter(
                      markers: clip.warpMarkers,
                      transients: clip.warpTransients,
                      clipDuration: clip.duration,
                      draggingMarkerId: _draggingWarpMarkerId,
                    ),
                  ),
                ),
                // Interactive drag handles for each unlocked marker
                for (final marker in clip.warpMarkers)
                  if (!marker.locked && clip.duration > 0)
                    Positioned(
                      left: (marker.timelinePos / clip.duration * width) - 6,
                      top: 0,
                      width: 12,
                      height: math.max(16, widget.trackHeight * 0.4),
                      child: _WarpMarkerDragHandle(
                        markerId: marker.id,
                        initialTimelinePos: marker.timelinePos,
                        pitchSemitones: marker.pitchSemitones,
                        clipDuration: clip.duration,
                        zoom: widget.zoom,
                        snapEnabled: widget.snapEnabled,
                        snapValue: widget.snapValue,
                        tempo: widget.tempo,
                        onMove: widget.onWarpMarkerMove,
                        onMoveEnd: widget.onWarpMarkerMoveEnd,
                        onPitchChanged: widget.onWarpMarkerPitchChanged,
                        onDragStateChanged: (id) {
                          setState(() => _draggingWarpMarkerId = id);
                        },
                      ),
                    ),
                // Double-tap on warp zone (top 20px) creates new marker
                Positioned(
                  left: 0, right: 0, top: 0, height: 20,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTapDown: (details) {
                      final timeSec = details.localPosition.dx / widget.zoom;
                      widget.onWarpMarkerCreate?.call(timeSec.clamp(0.0, clip.duration));
                    },
                  ),
                ),
              ],

              // ═══ Tool-specific visual overlays ═══
              // Erase tool: red danger tint on hover
              if (isExplicitTool && activeTool == TimelineEditTool.erase)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: FluxForgeTheme.accentRed.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.delete_forever, color: Colors.red, size: 20),
                    ),
                  ),
                ),
              // Mute tool: mute icon overlay
              if (isExplicitTool && activeTool == TimelineEditTool.mute)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        clip.muted ? Icons.volume_up : Icons.volume_off,
                        color: Colors.orange,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              // Split tool: scissors + cut line following mouse
              if (isExplicitTool && activeTool == TimelineEditTool.split && !clip.locked && _hoverLocalX != null)
                Positioned(
                  left: _hoverLocalX! - 0.5,
                  top: 0,
                  bottom: 0,
                  width: 1,
                  child: Container(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.8)),
                ),
              if (isExplicitTool && activeTool == TimelineEditTool.split && !clip.locked && _hoverLocalX != null)
                Positioned(
                  left: _hoverLocalX! - 9,
                  top: 2,
                  child: Icon(Icons.content_cut, color: Colors.white.withValues(alpha: 0.9), size: 16),
                ),
              // Glue tool: link icon
              if (isExplicitTool && activeTool == TimelineEditTool.glue)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.link, color: Colors.green, size: 18),
                    ),
                  ),
                ),

              // ═══ Smart Tool Zone Overlay (Logic Pro X style) ═══
              // Shows active zone indicator on hover when smart tool is enabled
              if (smartEnabled && !isExplicitTool && _smartToolHitResult != null && !clip.locked)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _SmartToolZoneOverlay(
                      mode: _smartToolHitResult!.mode,
                      clipWidth: clampedWidth,
                      clipHeight: clipHeight,
                      zones: smartTool.zones,
                    ),
                  ),
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
      ), // Close GestureDetector
      ), // Close Listener
      ); // Close MouseRegion
        }, // Close Consumer builder
      ), // Close Consumer
      ), // Close Opacity
    );
  }
}

// ============ Ultimate Clip Waveform ============
/// Advanced waveform widget for clips - best of all DAWs
/// Uses Cubase-style caching: only query FFI when zoom level changes significantly

class _UltimateClipWaveform extends StatefulWidget {
  final String clipId;
  final Float32List waveform;
  final Float32List? waveformRight;
  final double sourceOffset;
  final double duration;
  final double gain;
  final double zoom;
  final Color clipColor;
  final double trackHeight;
  final int channels;
  final bool reversed;

  const _UltimateClipWaveform({
    required this.clipId,
    required this.waveform,
    this.waveformRight,
    required this.sourceOffset,
    required this.duration,
    required this.gain,
    required this.zoom,
    required this.clipColor,
    required this.trackHeight,
    this.channels = 2,
    this.reversed = false,
  });

  @override
  State<_UltimateClipWaveform> createState() => _UltimateClipWaveformState();
}

class _UltimateClipWaveformState extends State<_UltimateClipWaveform> {
  // ═══════════════════════════════════════════════════════════════════════════
  // PIXEL-PERFECT RESOLUTION: Query exactly as many data points as screen pixels
  // - Re-query only when pixel count changes significantly (>20% difference)
  // - Combined L+R computed in _loadCacheOnce(), not in build()
  // - Zero allocations during build/paint cycle
  // ═══════════════════════════════════════════════════════════════════════════

  // Stereo data cache (L/R channels)
  StereoWaveformPixelData? _cachedStereoData;
  int _cachedClipId = 0;
  double _cachedSourceOffset = -1;
  double _cachedDuration = -1;
  int _cachedPixelCount = 0; // Track pixel count we cached at

  // Waveform generation tracking - invalidates cache when switching back to DAW
  // This prevents stale waveform rendering after SlotLab/Middleware usage
  int _cachedWaveformGeneration = -1;

  // PRE-COMPUTED combined L+R (avoids allocation in build())
  Float32List? _combinedMins;
  Float32List? _combinedMaxs;
  Float32List? _combinedRms;

  @override
  void initState() {
    super.initState();
    // initState: can't call setState, but first build() will read _cachedStereoData directly
    _loadCacheOnce();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check if waveform generation changed (mode switch from SlotLab back to DAW)
    final currentGeneration = context.read<EditorModeProvider>().waveformGeneration;
    if (_cachedWaveformGeneration != currentGeneration && _cachedWaveformGeneration != -1) {
      if (_loadCacheOnce() && mounted) setState(() {});
    }
  }

  @override
  void didUpdateWidget(_UltimateClipWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clipChanged = widget.clipId != oldWidget.clipId;
    final offsetChanged = (widget.sourceOffset - oldWidget.sourceOffset).abs() > 0.01;
    final durationChanged = (widget.duration - oldWidget.duration).abs() > 0.01;

    // Reload on clip content change — setState ensures repaint with new data
    if (clipChanged || offsetChanged || durationChanged) {
      if (_loadCacheOnce() && mounted) setState(() {});
      return;
    }

    // Reload when screen pixel count changes significantly (>20% diff = zoom changed)
    final screenPixels = (widget.zoom * widget.duration).round().clamp(64, 16384);
    if (_cachedPixelCount > 0) {
      final ratio = screenPixels / _cachedPixelCount;
      if (ratio > 1.2 || ratio < 0.8) {
        if (_loadCacheOnce() && mounted) setState(() {});
      }
    }
  }

  /// Returns true if cache was actually updated (triggers setState in callers)
  bool _loadCacheOnce() {
    final clipIdNum = int.tryParse(widget.clipId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (clipIdNum <= 0 || widget.duration <= 0) return false;

    // Pixel-perfect: query exactly as many data points as screen pixels
    final screenPixels = (widget.zoom * widget.duration).round().clamp(64, 16384);

    // Check waveform generation to detect mode switch invalidation
    final currentGeneration = context.read<EditorModeProvider>().waveformGeneration;
    final generationChanged = _cachedWaveformGeneration != currentGeneration;

    // Skip if already cached for this clip AND pixel count is close enough
    if (!generationChanged &&
        _cachedClipId == clipIdNum &&
        (_cachedSourceOffset - widget.sourceOffset).abs() < 0.01 &&
        (_cachedDuration - widget.duration).abs() < 0.01) {
      // Only skip if pixel count hasn't changed significantly
      if (_cachedPixelCount > 0) {
        final ratio = screenPixels / _cachedPixelCount;
        if (ratio <= 1.2 && ratio >= 0.8) return false;
      }
    }

    _cachedWaveformGeneration = currentGeneration;

    final sampleRate = NativeFFI.instance.getWaveformSampleRate(clipIdNum);
    final totalSamples = NativeFFI.instance.getWaveformTotalSamples(clipIdNum);
    if (totalSamples <= 0) return false;

    final startFrame = (widget.sourceOffset * sampleRate).round();
    final endFrame = ((widget.sourceOffset + widget.duration) * sampleRate).round();

    // Pixel-perfect resolution — 1 data point per screen pixel
    final stereoData = NativeFFI.instance.queryWaveformPixelsStereo(
      clipIdNum, startFrame, endFrame, screenPixels,
    );

    if (stereoData != null && !stereoData.isEmpty) {
      _cachedStereoData = stereoData;
      _cachedClipId = clipIdNum;
      _cachedSourceOffset = widget.sourceOffset;
      _cachedDuration = widget.duration;
      _cachedPixelCount = screenPixels;

      // ═══════════════════════════════════════════════════════════════════════
      // PRE-COMPUTE combined L+R here — NOT in build()!
      // This eliminates Float32List allocation during rendering
      // ═══════════════════════════════════════════════════════════════════════
      final len = stereoData.left.mins.length;
      _combinedMins = Float32List(len);
      _combinedMaxs = Float32List(len);
      _combinedRms = Float32List(len);

      for (int i = 0; i < len; i++) {
        _combinedMins![i] = math.min(stereoData.left.mins[i], stereoData.right.mins[i]);
        _combinedMaxs![i] = math.max(stereoData.left.maxs[i], stereoData.right.maxs[i]);
        _combinedRms![i] = (stereoData.left.rms[i] + stereoData.right.rms[i]) * 0.5;
      }
      return true; // Cache updated — caller should setState
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Watch EditorModeProvider.waveformGeneration to trigger rebuild on mode switch
    // This ensures waveforms refresh when returning to DAW from SlotLab
    final currentGeneration = context.watch<EditorModeProvider>().waveformGeneration;
    if (_cachedWaveformGeneration != currentGeneration && _cachedWaveformGeneration != -1) {
      // Schedule reload after build completes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadCacheOnce();
          setState(() {}); // Force repaint with new data
        }
      });
    }

    if (widget.waveform.isEmpty && _cachedStereoData == null) {
      return const SizedBox.shrink();
    }

    const waveColor = Color(0xFFFFFFFF);

    // Wrap waveform in horizontal flip when reversed (GPU transform, zero cost)
    Widget wrapReversed(Widget child) {
      if (!widget.reversed) return child;
      return Transform.flip(flipX: true, child: child);
    }

    // Cached stereo path - GPU scales fixed-resolution waveform
    if (_cachedStereoData != null && !_cachedStereoData!.isEmpty) {
      // For stereo (2 channels) AND expanded track (> 100px), show split L/R display
      // Default track height (100px) shows combined mono-style waveform
      // Only when user manually expands track taller than default → stereo split
      final showStereoSplit = widget.channels >= 2 && widget.trackHeight > 100;

      if (showStereoSplit) {
        return RepaintBoundary(
          key: ValueKey('stereo_split_${widget.reversed}'),
          child: ClipRect(
            child: wrapReversed(CustomPaint(
              size: Size.infinite,
              painter: _StereoWaveformPainter(
                leftMins: _cachedStereoData!.left.mins,
                leftMaxs: _cachedStereoData!.left.maxs,
                leftRms: _cachedStereoData!.left.rms,
                rightMins: _cachedStereoData!.right.mins,
                rightMaxs: _cachedStereoData!.right.maxs,
                rightRms: _cachedStereoData!.right.rms,
                color: waveColor,
                gain: widget.gain,
              ),
            )),
          ),
        );
      }

      // Default: Combined L+R display (pre-computed, zero allocation)
      if (_combinedMins != null) {
        return RepaintBoundary(
          key: ValueKey('combined_mono_${widget.reversed}'),
          child: ClipRect(
            child: wrapReversed(CustomPaint(
              size: Size.infinite,
              painter: _CubaseWaveformPainter(
                mins: _combinedMins!,
                maxs: _combinedMaxs!,
                rms: _combinedRms!,
                color: waveColor,
                gain: widget.gain,
              ),
            )),
          ),
        );
      }
    }

    // Fallback - simple legacy waveform
    return RepaintBoundary(
      child: ClipRect(
        child: wrapReversed(CustomPaint(
          size: Size.infinite,
          painter: _WaveformPainter(
            waveform: widget.waveform,
            sourceOffset: widget.sourceOffset,
            duration: widget.duration,
            color: waveColor,
            gain: widget.gain,
          ),
        )),
      ),
    );
  }
}

// ============ Cubase Style Waveform Painter (Timeline) ============
// TRUE Cubase style based on research:
// - Filled waveform with gradient shading
// - Thin dark outline around peaks (amplitude marker)
// - Min/Max vertical lines per pixel column
// - Uses Path for GPU-accelerated rendering (no per-pixel draw calls)
//
// ═══════════════════════════════════════════════════════════════════════════
// GPU OPTIMIZATION: Path objects are cached and only rebuilt when size changes
// Paint objects are pre-allocated in constructor — zero allocations in paint()
// ═══════════════════════════════════════════════════════════════════════════

class _CubaseWaveformPainter extends CustomPainter {
  final Float32List mins;
  final Float32List maxs;
  final Float32List rms;
  final Color color;
  final double gain;

  // Cached Path objects — rebuilt on size, gain, or data change
  Path? _cachedWavePath;
  Path? _cachedRmsPath;
  Size? _cachedSize;
  double? _cachedGain;
  int _cachedDataLen = -1;

  // Pre-allocated Paint objects (zero allocation in paint())
  late final Paint _rmsFillPaint;
  late final Paint _peakFillPaint;
  late final Paint _peakStrokePaint;
  late final Paint _centerLinePaint;

  _CubaseWaveformPainter({
    required this.mins,
    required this.maxs,
    required this.rms,
    required this.color,
    this.gain = 1.0,
  }) {
    // Initialize paints ONCE in constructor
    _rmsFillPaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    _peakFillPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    _peakStrokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    _centerLinePaint = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (mins.isEmpty || size.width <= 0 || size.height <= 0) return;

    // Rebuild paths when size, gain, or data resolution changes
    if (_cachedWavePath == null || _cachedSize != size || _cachedGain != gain || _cachedDataLen != mins.length) {
      _rebuildPaths(size);
      _cachedSize = size;
      _cachedGain = gain;
      _cachedDataLen = mins.length;
    }

    final centerY = size.height / 2;

    // 1. Draw RMS body FIRST (smaller, darker) - the "mass" of sound
    if (_cachedRmsPath != null) {
      canvas.drawPath(_cachedRmsPath!, _rmsFillPaint);
    }

    // 2. Draw PEAK fill - lighter, shows transient extent above RMS
    canvas.drawPath(_cachedWavePath!, _peakFillPaint);

    // 3. Draw SHARP peak outline - bright, crisp transient spikes
    canvas.drawPath(_cachedWavePath!, _peakStrokePaint);

    // 4. Center line (zero crossing) - very subtle
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), _centerLinePaint);
  }

  /// Build and cache Path objects — called only when size or gain changes
  void _rebuildPaths(Size size) {
    final centerY = size.height / 2;
    // Pro Tools/Logic Pro X style: gain scales amplitude within channel lane
    // Clamp to prevent waveform exceeding channel bounds
    final amplitude = centerY * 0.7 * gain.clamp(0.0, 4.0);
    final numSamples = mins.length;

    // Helper to map sample index to X coordinate (fills entire width)
    double sampleToX(int i) => numSamples > 1 ? (i / (numSamples - 1)) * size.width : size.width / 2;

    // Build waveform envelope path
    _cachedWavePath = Path();
    _cachedWavePath!.moveTo(0, centerY - maxs[0] * amplitude);

    for (int i = 1; i < numSamples; i++) {
      _cachedWavePath!.lineTo(sampleToX(i), centerY - maxs[i] * amplitude);
    }

    for (int i = numSamples - 1; i >= 0; i--) {
      _cachedWavePath!.lineTo(sampleToX(i), centerY - mins[i] * amplitude);
    }
    _cachedWavePath!.close();

    // Build RMS path (smaller body)
    if (rms.isNotEmpty) {
      const rmsScale = 0.45;
      _cachedRmsPath = Path();
      _cachedRmsPath!.moveTo(0, centerY - rms[0] * amplitude * rmsScale);

      for (int i = 1; i < numSamples; i++) {
        _cachedRmsPath!.lineTo(sampleToX(i), centerY - rms[i] * amplitude * rmsScale);
      }

      for (int i = numSamples - 1; i >= 0; i--) {
        _cachedRmsPath!.lineTo(sampleToX(i), centerY + rms[i] * amplitude * rmsScale);
      }
      _cachedRmsPath!.close();
    }
  }

  @override
  bool shouldRepaint(_CubaseWaveformPainter oldDelegate) =>
      mins != oldDelegate.mins ||
      maxs != oldDelegate.maxs ||
      rms != oldDelegate.rms ||
      color != oldDelegate.color ||
      gain != oldDelegate.gain;
}

// ============ Stereo Waveform Painter (L/R split) ============
// Shows LEFT channel in top half, RIGHT channel in bottom half
// Pro Tools / Cubase stereo display style
//
// ═══════════════════════════════════════════════════════════════════════════
// GPU OPTIMIZATION: All 4 Path objects (L/R wave + L/R rms) cached
// Paint objects pre-allocated — zero allocations in paint()
// ═══════════════════════════════════════════════════════════════════════════

class _StereoWaveformPainter extends CustomPainter {
  final Float32List leftMins;
  final Float32List leftMaxs;
  final Float32List leftRms;
  final Float32List rightMins;
  final Float32List rightMaxs;
  final Float32List rightRms;
  final Color color;
  final double gain;

  // Cached Path objects — rebuilt on size, gain, or data change
  Path? _leftWavePath;
  Path? _leftRmsPath;
  Path? _rightWavePath;
  Path? _rightRmsPath;
  Size? _cachedSize;
  double? _cachedGain;
  int _cachedDataLen = -1;

  // Pre-allocated Paint objects (zero allocation in paint())
  late final Paint _rmsFillPaint;
  late final Paint _peakFillPaint;
  late final Paint _peakStrokePaint;
  late final Paint _centerLinePaint;
  late final Paint _separatorPaint;
  late final Paint _labelBgPaint;

  // Pre-built TextPainters for L/R labels (zero allocation in paint())
  late final TextPainter _leftLabelPainter;
  late final TextPainter _rightLabelPainter;

  _StereoWaveformPainter({
    required this.leftMins,
    required this.leftMaxs,
    required this.leftRms,
    required this.rightMins,
    required this.rightMaxs,
    required this.rightRms,
    required this.color,
    this.gain = 1.0,
  }) {
    // Initialize paints ONCE in constructor
    _rmsFillPaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    _peakFillPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    _peakStrokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    _centerLinePaint = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;

    _separatorPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = 1.0;

    _labelBgPaint = Paint()
      ..color = const Color(0x40000000);

    // Pre-build L/R label painters
    _leftLabelPainter = TextPainter(
      text: TextSpan(
        text: 'L',
        style: TextStyle(
          color: color.withValues(alpha: 0.5),
          fontSize: 8,
          fontFamily: 'JetBrains Mono',
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    _rightLabelPainter = TextPainter(
      text: TextSpan(
        text: 'R',
        style: TextStyle(
          color: color.withValues(alpha: 0.5),
          fontSize: 8,
          fontFamily: 'JetBrains Mono',
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (leftMins.isEmpty || size.width <= 0 || size.height <= 0) return;

    // Rebuild paths when size, gain, or data resolution changes
    if (_leftWavePath == null || _cachedSize != size || _cachedGain != gain || _cachedDataLen != leftMins.length) {
      _rebuildAllPaths(size);
      _cachedSize = size;
      _cachedGain = gain;
      _cachedDataLen = leftMins.length;
    }

    final leftCenterY = size.height * 0.25;
    final rightCenterY = size.height * 0.75;
    final midY = size.height / 2;

    // Draw LEFT channel (top half)
    if (_leftRmsPath != null) canvas.drawPath(_leftRmsPath!, _rmsFillPaint);
    canvas.drawPath(_leftWavePath!, _peakFillPaint);
    canvas.drawPath(_leftWavePath!, _peakStrokePaint);
    canvas.drawLine(Offset(0, leftCenterY), Offset(size.width, leftCenterY), _centerLinePaint);

    // Separator line between L/R — dashed style via short segments
    for (double x = 0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, midY), Offset(x + 3, midY), _separatorPaint);
    }

    // Draw RIGHT channel (bottom half)
    if (_rightRmsPath != null) canvas.drawPath(_rightRmsPath!, _rmsFillPaint);
    canvas.drawPath(_rightWavePath!, _peakFillPaint);
    canvas.drawPath(_rightWavePath!, _peakStrokePaint);
    canvas.drawLine(Offset(0, rightCenterY), Offset(size.width, rightCenterY), _centerLinePaint);

    // L/R channel labels (Logic Pro style — small labels at left edge)
    if (size.height > 50) {
      // L label — top channel
      final lX = 2.0;
      final lY = leftCenterY - _leftLabelPainter.height / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(lX - 1, lY - 1, _leftLabelPainter.width + 2, _leftLabelPainter.height + 2),
          const Radius.circular(1),
        ),
        _labelBgPaint,
      );
      _leftLabelPainter.paint(canvas, Offset(lX, lY));

      // R label — bottom channel
      final rY = rightCenterY - _rightLabelPainter.height / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(lX - 1, rY - 1, _rightLabelPainter.width + 2, _rightLabelPainter.height + 2),
          const Radius.circular(1),
        ),
        _labelBgPaint,
      );
      _rightLabelPainter.paint(canvas, Offset(lX, rY));
    }
  }

  /// Build and cache all 4 Path objects — called only when size or gain changes
  void _rebuildAllPaths(Size size) {
    final numSamples = leftMins.length;
    final leftCenterY = size.height * 0.25;
    final rightCenterY = size.height * 0.75;
    final channelHeight = size.height * 0.45;
    // Pro Tools/Logic Pro X style: gain scales amplitude within each channel lane
    final amplitude = (channelHeight / 2) * gain.clamp(0.0, 4.0);

    double sampleToX(int i) => numSamples > 1 ? (i / (numSamples - 1)) * size.width : size.width / 2;

    // Build LEFT channel paths
    _leftWavePath = _buildWavePath(leftMins, leftMaxs, leftCenterY, amplitude, numSamples, sampleToX);
    _leftRmsPath = leftRms.isNotEmpty ? _buildRmsPath(leftRms, leftCenterY, amplitude, numSamples, sampleToX) : null;

    // Build RIGHT channel paths
    _rightWavePath = _buildWavePath(rightMins, rightMaxs, rightCenterY, amplitude, numSamples, sampleToX);
    _rightRmsPath = rightRms.isNotEmpty ? _buildRmsPath(rightRms, rightCenterY, amplitude, numSamples, sampleToX) : null;
  }

  Path _buildWavePath(Float32List mins, Float32List maxs, double centerY, double amplitude, int numSamples, double Function(int) sampleToX) {
    final path = Path();
    path.moveTo(0, centerY - maxs[0] * amplitude);

    for (int i = 1; i < numSamples; i++) {
      path.lineTo(sampleToX(i), centerY - maxs[i] * amplitude);
    }

    for (int i = numSamples - 1; i >= 0; i--) {
      path.lineTo(sampleToX(i), centerY - mins[i] * amplitude);
    }
    path.close();
    return path;
  }

  Path _buildRmsPath(Float32List rms, double centerY, double amplitude, int numSamples, double Function(int) sampleToX) {
    const rmsScale = 0.45;
    final path = Path();
    path.moveTo(0, centerY - rms[0] * amplitude * rmsScale);

    for (int i = 1; i < numSamples; i++) {
      path.lineTo(sampleToX(i), centerY - rms[i] * amplitude * rmsScale);
    }

    for (int i = numSamples - 1; i >= 0; i--) {
      path.lineTo(sampleToX(i), centerY + rms[i] * amplitude * rmsScale);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(_StereoWaveformPainter oldDelegate) =>
      leftMins != oldDelegate.leftMins ||
      leftMaxs != oldDelegate.leftMaxs ||
      leftRms != oldDelegate.leftRms ||
      rightMins != oldDelegate.rightMins ||
      rightMaxs != oldDelegate.rightMaxs ||
      rightRms != oldDelegate.rightRms ||
      color != oldDelegate.color ||
      gain != oldDelegate.gain;
}

// ============ Legacy Waveform Canvas (fallback) ============

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
        sourceOffset: sourceOffset,
        duration: duration,
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final Float32List waveform;
  final Color color;
  final double sourceOffset;
  final double duration;
  final double gain;

  // PERFORMANCE: Pre-allocated Paint objects to avoid allocations in paint()
  late final Paint _peakPaint;
  late final Paint _rmsPaint;
  late final Paint _linePaint;
  late final Paint _glowPaint;
  late final Paint _fillPaint;
  late final Paint _zeroLinePaint;

  _WaveformPainter({
    required this.waveform,
    required this.color,
    required this.sourceOffset,
    required this.duration,
    this.gain = 1.0,
  }) {
    // Initialize paints once in constructor
    // Cubase style: peaks are LIGHTER (transient extent), RMS is SOLID (body)
    _peakPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..strokeWidth = 1
      ..isAntiAlias = false;

    _rmsPaint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..isAntiAlias = false;

    _linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    _glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
      ..isAntiAlias = true;

    _fillPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    _zeroLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 0.5;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty || size.width <= 0 || size.height <= 0) return;

    final centerY = size.height / 2;
    // FULL HEIGHT for maximum waveform visibility (Logic Pro style)
    // Gain scales amplitude within channel lane (Pro Tools/Logic Pro X behavior)
    final amplitude = centerY * 0.98 * gain.clamp(0.0, 4.0);
    final samplesPerPixel = waveform.length / size.width;

    // 4-Level LOD System (Professional DAW standard)
    // ULTRA (<1 spp): Sub-sample Catmull-Rom interpolation
    // SAMPLE (1-10 spp): Catmull-Rom curves through samples
    // DETAIL (10-100 spp): Smooth bezier envelope
    // OVERVIEW (>100 spp): Min/Max + RMS

    if (samplesPerPixel < 1) {
      _drawUltraZoomWaveform(canvas, size, centerY, amplitude, samplesPerPixel);
    } else if (samplesPerPixel < 10) {
      _drawDetailedWaveform(canvas, size, centerY, amplitude, samplesPerPixel);
    } else if (samplesPerPixel < 100) {
      _drawMinMaxWaveform(canvas, size, centerY, amplitude, samplesPerPixel);
    } else {
      _drawOverviewWaveform(canvas, size, centerY, amplitude, samplesPerPixel);
    }
  }

  /// ULTRA ZOOM: Sub-sample Catmull-Rom interpolation (oscilloscope view)
  void _drawUltraZoomWaveform(Canvas canvas, Size size, double centerY, double amplitude, double samplesPerPixel) {
    final path = Path();
    bool started = false;

    for (double x = 0; x < size.width; x++) {
      final exactSample = x * samplesPerPixel;
      final sampleIdx = exactSample.floor();

      if (sampleIdx < 1 || sampleIdx >= waveform.length - 2) continue;

      // Get 4 samples for Catmull-Rom
      final p0 = waveform[sampleIdx - 1];
      final p1 = waveform[sampleIdx];
      final p2 = waveform[sampleIdx + 1];
      final p3 = waveform[(sampleIdx + 2).clamp(0, waveform.length - 1)];

      final t = exactSample - sampleIdx;
      final interpolated = _catmullRom(p0, p1, p2, p3, t);
      final y = centerY - interpolated * amplitude;

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    // PERFORMANCE: Use pre-allocated paints
    canvas.drawPath(path, _glowPaint);
    canvas.drawPath(path, _linePaint);
  }

  /// HIGH ZOOM: Sample-accurate waveform with sinc interpolation appearance
  void _drawDetailedWaveform(Canvas canvas, Size size, double centerY, double amplitude, double samplesPerPixel) {
    // PERFORMANCE: Use pre-allocated paints
    // Reuse _fillPaint and _linePaint

    final topPath = Path();
    final bottomPath = Path();
    bool started = false;

    for (double x = 0; x < size.width; x++) {
      final exactSample = x * samplesPerPixel;
      final sampleIndex = exactSample.floor().clamp(0, waveform.length - 1);
      final nextIndex = (sampleIndex + 1).clamp(0, waveform.length - 1);

      // Cubic interpolation for smoother curves
      final t = exactSample - sampleIndex.floor();
      final s0 = waveform[(sampleIndex - 1).clamp(0, waveform.length - 1)];
      final s1 = waveform[sampleIndex];
      final s2 = waveform[nextIndex];
      final s3 = waveform[(nextIndex + 1).clamp(0, waveform.length - 1)];

      // Catmull-Rom spline interpolation
      final sample = _catmullRom(s0, s1, s2, s3, t);

      final yTop = centerY - sample * amplitude;
      final yBottom = centerY + sample * amplitude;

      if (!started) {
        topPath.moveTo(x, yTop);
        bottomPath.moveTo(x, yBottom);
        started = true;
      } else {
        topPath.lineTo(x, yTop);
        bottomPath.lineTo(x, yBottom);
      }
    }

    // Draw filled waveform area
    final fillPath = Path()..addPath(topPath, Offset.zero);
    // Connect to bottom path in reverse
    for (double x = size.width - 1; x >= 0; x--) {
      final exactSample = x * samplesPerPixel;
      final sampleIndex = exactSample.floor().clamp(0, waveform.length - 1);
      final sample = waveform[sampleIndex];
      fillPath.lineTo(x, centerY + sample * amplitude);
    }
    fillPath.close();

    canvas.drawPath(fillPath, _fillPaint);
    canvas.drawPath(topPath, _linePaint);
    canvas.drawPath(bottomPath, _linePaint);

    // Zero line (subtle) - use pre-allocated paint
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), _zeroLinePaint);
  }

  /// Catmull-Rom spline interpolation for smooth waveform
  double _catmullRom(double p0, double p1, double p2, double p3, double t) {
    final t2 = t * t;
    final t3 = t2 * t;
    return 0.5 * ((2 * p1) +
        (-p0 + p2) * t +
        (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
        (-p0 + 3 * p1 - 3 * p2 + p3) * t3);
  }

  /// MEDIUM ZOOM: True min/max envelope - the standard DAW waveform view
  /// NO SMOOTHING - shows EXACT peaks and transients as they are in the audio
  /// Pro Tools / Cubase style: sharp transients, true dynamics
  void _drawMinMaxWaveform(Canvas canvas, Size size, double centerY, double amplitude, double samplesPerPixel) {
    // PERFORMANCE: Use pre-allocated paints (_peakPaint, _rmsPaint)

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

      final rms = count > 0 ? math.sqrt(sumSq / count) : 0;

      // Peak line (full extent) - shows transients
      final peakTop = centerY - maxVal * amplitude;
      final peakBottom = centerY - minVal * amplitude;
      canvas.drawLine(Offset(x, peakTop), Offset(x, peakBottom), _peakPaint);

      // RMS line (inner, solid) - shows perceived loudness
      final rmsTop = centerY - rms * amplitude;
      final rmsBottom = centerY + rms * amplitude;
      canvas.drawLine(Offset(x, rmsTop), Offset(x, rmsBottom), _rmsPaint);
    }

    // Zero line - use pre-allocated paint
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), _zeroLinePaint);
  }

  /// LOW ZOOM: True min/max vertical lines - shows REAL dynamics
  /// NO SMOOTHING - every pixel shows actual peak range
  void _drawOverviewWaveform(Canvas canvas, Size size, double centerY, double amplitude, double samplesPerPixel) {
    // PERFORMANCE: Use pre-allocated paints (_peakPaint, _rmsPaint)

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

      final rms = count > 0 ? math.sqrt(sumSq / count) : 0;

      // Peak line - TRUE min/max (shows transients)
      final peakTop = centerY - maxVal * amplitude;
      final peakBottom = centerY - minVal * amplitude;
      canvas.drawLine(Offset(x, peakTop), Offset(x, peakBottom), _peakPaint);

      // RMS line (solid inner)
      final rmsTop = centerY - rms * amplitude;
      final rmsBottom = centerY + rms * amplitude;
      canvas.drawLine(Offset(x, rmsTop), Offset(x, rmsBottom), _rmsPaint);
    }

    // Zero line - use pre-allocated paint
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), _zeroLinePaint);
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      waveform != oldDelegate.waveform || color != oldDelegate.color || gain != oldDelegate.gain;
}

// ============ Fade Overlay Painter ============

class _FadeOverlayPainter extends CustomPainter {
  final bool isLeft;
  final FadeCurve curve;

  _FadeOverlayPainter({required this.isLeft, required this.curve});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final path = Path();
    const steps = 30;

    if (isLeft) {
      // Fade IN: dark at left (silence) fading to clear at right (full volume)
      // Fill area ABOVE the curve (the faded/quiet part)
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
      // Fade OUT: clear at left (full volume) fading to dark at right (silence)
      // Fill area ABOVE the curve (the faded/quiet part)
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
  bool shouldRepaint(_FadeOverlayPainter oldDelegate) =>
      isLeft != oldDelegate.isLeft || curve != oldDelegate.curve;
}

// ============ Loop Boundary Painter ============

/// Draws dashed vertical lines at each loop boundary point within a looped clip
class _LoopBoundaryPainter extends CustomPainter {
  final double sourceDuration;
  final double clipDuration;
  final double zoom;
  final bool isDragging;

  _LoopBoundaryPainter({
    required this.sourceDuration,
    required this.clipDuration,
    required this.zoom,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (sourceDuration <= 0 || clipDuration <= sourceDuration) return;

    final loopPixelWidth = sourceDuration * zoom;
    if (loopPixelWidth < 4) return; // Too small to draw

    final paint = Paint()
      ..color = isDragging
          ? Colors.cyan.withValues(alpha: 0.6)
          : Colors.cyan.withValues(alpha: 0.35)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw dashed vertical lines at each loop boundary
    var x = loopPixelWidth;
    while (x < size.width) {
      // Dashed line
      var y = 0.0;
      while (y < size.height) {
        final dashEnd = (y + 4).clamp(0.0, size.height);
        canvas.drawLine(Offset(x, y), Offset(x, dashEnd), paint);
        y += 7; // 4px dash + 3px gap
      }
      x += loopPixelWidth;
    }

    // Subtle overlay on looped region (past first source duration)
    if (isDragging) {
      final overlayPaint = Paint()
        ..color = Colors.cyan.withValues(alpha: 0.06)
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTRB(loopPixelWidth, 0, size.width, size.height),
        overlayPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_LoopBoundaryPainter oldDelegate) =>
      oldDelegate.sourceDuration != sourceDuration ||
      oldDelegate.clipDuration != clipDuration ||
      oldDelegate.zoom != zoom ||
      oldDelegate.isDragging != isDragging;
}

// ============ P3.3: Gain Envelope Painter ============

/// Draws a visual gain envelope line on clips
/// Shows gain level as a horizontal line (unity = center, boost = higher, cut = lower)
class _GainEnvelopePainter extends CustomPainter {
  final double gain;
  final Color clipColor;

  _GainEnvelopePainter({
    required this.gain,
    required this.clipColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Convert gain (0-2) to Y position
    // gain 1.0 = center, gain 2.0 = top, gain 0.0 = bottom
    // Using logarithmic scale for better visualization
    final centerY = size.height / 2;

    // Calculate Y offset based on gain
    // gain > 1: line moves up (boost)
    // gain < 1: line moves down (cut)
    // Max travel is half the height
    double yOffset;
    if (gain >= 1.0) {
      // Boost: 1.0->2.0 maps to 0->-centerY*0.8
      yOffset = -((gain - 1.0) / 1.0) * centerY * 0.8;
    } else {
      // Cut: 0.0->1.0 maps to centerY*0.8->0
      yOffset = ((1.0 - gain) / 1.0) * centerY * 0.8;
    }

    final lineY = centerY + yOffset;

    // Draw the gain line
    final linePaint = Paint()
      ..color = gain > 1.0
          ? Colors.orange.withOpacity(0.8)  // Boost = orange
          : Colors.cyan.withOpacity(0.8)    // Cut = cyan
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Draw dashed line
    const dashWidth = 6.0;
    const dashGap = 4.0;
    double x = 4.0;
    while (x < size.width - 4) {
      canvas.drawLine(
        Offset(x, lineY),
        Offset((x + dashWidth).clamp(0, size.width - 4), lineY),
        linePaint,
      );
      x += dashWidth + dashGap;
    }

    // Draw small indicator at edges
    final indicatorPaint = Paint()
      ..color = linePaint.color
      ..style = PaintingStyle.fill;

    // Left indicator triangle
    final leftTriangle = Path()
      ..moveTo(2, lineY)
      ..lineTo(8, lineY - 4)
      ..lineTo(8, lineY + 4)
      ..close();
    canvas.drawPath(leftTriangle, indicatorPaint);

    // Right indicator triangle
    final rightTriangle = Path()
      ..moveTo(size.width - 2, lineY)
      ..lineTo(size.width - 8, lineY - 4)
      ..lineTo(size.width - 8, lineY + 4)
      ..close();
    canvas.drawPath(rightTriangle, indicatorPaint);

    // Draw gain value label at center
    final textPainter = TextPainter(
      text: TextSpan(
        text: _formatGainDb(gain),
        style: TextStyle(
          color: linePaint.color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          fontFamily: 'JetBrains Mono',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Background for text readability
    final textBgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, lineY),
        width: textPainter.width + 8,
        height: textPainter.height + 4,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      textBgRect,
      Paint()..color = Colors.black.withOpacity(0.6),
    );

    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        lineY - textPainter.height / 2,
      ),
    );
  }

  String _formatGainDb(double gain) {
    if (gain <= 0) return '-∞';
    final db = 20 * math.log(gain) / math.ln10;
    if (db > 0) return '+${db.toStringAsFixed(1)}dB';
    return '${db.toStringAsFixed(1)}dB';
  }

  @override
  bool shouldRepaint(_GainEnvelopePainter oldDelegate) =>
      gain != oldDelegate.gain || clipColor != oldDelegate.clipColor;
}

// ============ Fade Handle (Logic Pro + Cubase Style) ============

class _FadeHandle extends StatefulWidget {
  final double width;
  final double fadeTime;
  final bool isLeft;
  final bool isActive;
  final FadeCurve curve;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate; // Now receives delta, not absolute position
  final VoidCallback onDragEnd;

  const _FadeHandle({
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
  State<_FadeHandle> createState() => _FadeHandleState();
}

class _FadeHandleState extends State<_FadeHandle> {
  bool _isHovered = false;
  bool _isDragging = false;
  double _dragStartX = 0;
  double _accumulatedDelta = 0; // Track total movement for stable updates

  @override
  Widget build(BuildContext context) {
    // Handle size for drag interaction — Pro DAW standard: 20px for visibility
    const handleSize = 20.0;
    final isActive = widget.isActive || _isHovered || _isDragging;

    // Handle position: at the END of fade zone, moves with fade
    // Left fade: handle at right edge of fade zone
    // Right fade: handle at left edge of fade zone
    final handleOffset = widget.width - handleSize - 2;

    return Positioned(
      left: widget.isLeft ? 0 : null,
      right: widget.isLeft ? null : 0,
      top: 0,
      bottom: 0,
      width: widget.width,
      // Stack with translucent behavior - only handle catches clicks
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Curved fade overlay (visual only, doesn't block clicks)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FadeTrianglePainter(
                  isLeft: widget.isLeft,
                  isActive: isActive,
                  curve: widget.curve,
                ),
              ),
            ),
          ),
          // Drag handle - ONLY this catches clicks
          // Position at END of fade zone (moves with fade width)
          Positioned(
            left: widget.isLeft ? handleOffset.clamp(2.0, double.infinity) : null,
            right: widget.isLeft ? null : handleOffset.clamp(2.0, double.infinity),
            top: 2,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                fadeHandleActiveGlobal = true;
                setState(() => _isDragging = true);
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
                fadeHandleActiveGlobal = false;
                if (_isDragging) {
                  setState(() => _isDragging = false);
                  _accumulatedDelta = 0;
                  widget.onDragEnd();
                }
              },
              onPointerCancel: (event) {
                fadeHandleActiveGlobal = false;
                if (_isDragging) {
                  setState(() => _isDragging = false);
                  _accumulatedDelta = 0;
                  widget.onDragEnd();
                }
              },
              child: MouseRegion(
                onEnter: (_) => setState(() => _isHovered = true),
                onExit: (_) => setState(() => _isHovered = false),
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(
                  width: handleSize,
                  height: handleSize,
                  decoration: BoxDecoration(
                    color: isActive
                        ? FluxForgeTheme.accentCyan
                        : Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isActive
                          ? FluxForgeTheme.accentCyan
                          : FluxForgeTheme.textSecondary,
                      width: 1.5,
                    ),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: FluxForgeTheme.accentCyan.withValues(alpha: 0.5),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                  ),
                  child: Center(
                    child: Icon(
                      widget.isLeft ? Icons.chevron_right : Icons.chevron_left,
                      size: 14,
                      color: isActive
                          ? Colors.white
                          : FluxForgeTheme.bgDeepest,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Fade time label - only show when fade > 0
          if (widget.fadeTime > 0)
            Positioned(
              left: widget.isLeft ? 4 : null,
              right: widget.isLeft ? null : 4,
              bottom: 4,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeepest.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: (_isHovered || widget.isActive)
                          ? FluxForgeTheme.accentBlue
                          : FluxForgeTheme.borderSubtle,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    _formatFadeTime(widget.width),
                    style: TextStyle(
                      fontSize: 9,
                      fontFamily: 'JetBrains Mono',
                      color: (_isHovered || widget.isActive)
                          ? FluxForgeTheme.accentBlue
                          : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatFadeTime(double width) {
    final seconds = widget.fadeTime;
    if (seconds < 0.01) return '0ms';
    if (seconds < 1.0) return '${(seconds * 1000).round()}ms';
    if (seconds < 10.0) return '${seconds.toStringAsFixed(2)}s';
    return '${seconds.toStringAsFixed(1)}s';
  }
}

/// Curved fade overlay painter (Logic Pro style)
class _FadeTrianglePainter extends CustomPainter {
  final bool isLeft;
  final bool isActive;
  final FadeCurve curve;

  _FadeTrianglePainter({
    required this.isLeft,
    required this.isActive,
    required this.curve,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isActive
          ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
          : FluxForgeTheme.textSecondary.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final path = Path();
    const steps = 30;

    if (isLeft) {
      // Fade in: fill area ABOVE the curve (the faded/quiet part)
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
      // Fade out: fill area ABOVE the curve (the faded/quiet part)
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
  bool shouldRepaint(_FadeTrianglePainter oldDelegate) =>
      isLeft != oldDelegate.isLeft ||
      isActive != oldDelegate.isActive ||
      curve != oldDelegate.curve;
}

/// Fade curve line painter — draws the actual fade curve with dashed style for S-curves
class _FadeCurveLinePainter extends CustomPainter {
  final bool isLeft;
  final bool isActive;
  final FadeCurve curve;

  _FadeCurveLinePainter({
    required this.isLeft,
    required this.isActive,
    required this.curve,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final isSCurve = curve == FadeCurve.sCurve || curve == FadeCurve.invSCurve;

    final paint = Paint()
      ..color = isActive
          ? FluxForgeTheme.accentCyan
          : FluxForgeTheme.textPrimary.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isActive ? 2.5 : 1.5
      ..strokeCap = StrokeCap.round;

    final path = Path();
    const steps = 40;

    if (isLeft) {
      path.moveTo(0, size.height);
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = t * size.width;
        final fadeGain = _evaluateCurve(t);
        final y = size.height * (1 - fadeGain);
        path.lineTo(x, y);
      }
    } else {
      path.moveTo(0, 0);
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = t * size.width;
        final fadeGain = _evaluateCurve(1 - t);
        final y = size.height * (1 - fadeGain);
        path.lineTo(x, y);
      }
    }

    // For S-curves, draw dashed line
    if (isSCurve) {
      _drawDashedPath(canvas, path, paint, 5.0, 3.0);
    } else {
      canvas.drawPath(path, paint);
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint, double dashLen, double gapLen) {
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0.0;
      while (distance < metric.length) {
        final dashEnd = (distance + dashLen).clamp(0.0, metric.length);
        final dashPath = metric.extractPath(distance, dashEnd);
        canvas.drawPath(dashPath, paint);
        distance += dashLen + gapLen;
      }
    }
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
  bool shouldRepaint(_FadeCurveLinePainter oldDelegate) =>
      isLeft != oldDelegate.isLeft ||
      isActive != oldDelegate.isActive ||
      curve != oldDelegate.curve;
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
                  ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
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

// ============ Volume Handle Indicator (Cubase-style) ============

/// Small diamond indicator at top-center of clip for gain adjustment.
/// Cubase shows a diamond that can be dragged vertically to change clip gain.
class _VolumeHandleIndicator extends StatelessWidget {
  final bool isActive;
  final double gain;

  const _VolumeHandleIndicator({
    required this.isActive,
    required this.gain,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? FluxForgeTheme.accentOrange
        : FluxForgeTheme.textSecondary.withValues(alpha: 0.5);

    return SizedBox(
      width: 10,
      height: 10,
      child: CustomPaint(
        painter: _DiamondPainter(color: color, isActive: isActive),
      ),
    );
  }
}

class _DiamondPainter extends CustomPainter {
  final Color color;
  final bool isActive;

  _DiamondPainter({required this.color, required this.isActive});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = isActive ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(0, size.height / 2)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_DiamondPainter oldDelegate) =>
      color != oldDelegate.color || isActive != oldDelegate.isActive;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SMART TOOL ZONE OVERLAY — Logic Pro X style visual feedback
// Shows which zone is active on hover with subtle highlight indicators
// ═══════════════════════════════════════════════════════════════════════════════

class _SmartToolZoneOverlay extends StatelessWidget {
  final SmartToolMode mode;
  final double clipWidth;
  final double clipHeight;
  final SmartToolZones zones;

  const _SmartToolZoneOverlay({
    required this.mode,
    required this.clipWidth,
    required this.clipHeight,
    required this.zones,
  });

  @override
  Widget build(BuildContext context) {
    if (mode == SmartToolMode.none) return const SizedBox.shrink();

    return CustomPaint(
      painter: _SmartToolZonePainter(
        mode: mode,
        clipWidth: clipWidth,
        clipHeight: clipHeight,
        zones: zones,
      ),
    );
  }
}

class _SmartToolZonePainter extends CustomPainter {
  final SmartToolMode mode;
  final double clipWidth;
  final double clipHeight;
  final SmartToolZones zones;

  _SmartToolZonePainter({
    required this.mode,
    required this.clipWidth,
    required this.clipHeight,
    required this.zones,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Zone dimensions
    final topH = (h * zones.topRowPercent).clamp(zones.minZoneRowPixels, h * 0.35);
    final botH = (h * zones.bottomRowPercent).clamp(zones.minZoneRowPixels, h * 0.35);
    final botTop = h - botH;
    final trimW = (w * zones.trimZonePercent).clamp(zones.minTrimZonePixels, w * 0.25);
    final fadeW = (w * zones.fadeCornerPercent).clamp(zones.minTrimZonePixels, w * 0.30);
    final bodyMidY = topH + (botTop - topH) * zones.bodyMidpoint;

    switch (mode) {
      case SmartToolMode.trimLeft:
        _paintTrimZone(canvas, Rect.fromLTWH(0, 0, trimW, h), true);
        break;
      case SmartToolMode.trimRight:
        _paintTrimZone(canvas, Rect.fromLTWH(w - trimW, 0, trimW, h), false);
        break;
      case SmartToolMode.fadeIn:
        _paintFadeZone(canvas, Rect.fromLTWH(0, 0, fadeW, topH), true);
        break;
      case SmartToolMode.fadeOut:
        _paintFadeZone(canvas, Rect.fromLTWH(w - fadeW, 0, fadeW, topH), false);
        break;
      case SmartToolMode.volumeHandle:
        _paintVolumeZone(canvas, Rect.fromLTWH(fadeW, 0, w - fadeW * 2, topH));
        break;
      case SmartToolMode.rangeSelectBody:
        _paintRangeZone(canvas, Rect.fromLTWH(trimW, topH, w - trimW * 2, bodyMidY - topH));
        break;
      case SmartToolMode.select:
        _paintMoveZone(canvas, Rect.fromLTWH(trimW, bodyMidY, w - trimW * 2, botTop - bodyMidY));
        break;
      case SmartToolMode.loopHandle:
        final loopW = (w * zones.loopZonePercent).clamp(zones.minTrimZonePixels, w * 0.20);
        _paintLoopZone(canvas, Rect.fromLTWH(w - trimW - loopW, botTop, loopW, botH));
        break;
      case SmartToolMode.timeStretch:
        _paintTimeStretchZone(canvas, size, trimW, topH, botTop);
        break;
      case SmartToolMode.crossfade:
        _paintCrossfadeZone(canvas, size, trimW, botTop, botH);
        break;
      case SmartToolMode.slipContent:
        _paintSlipZone(canvas, size);
        break;
      default:
        break;
    }

    // Always draw the body midpoint line when smart tool is active (subtle)
    if (mode != SmartToolMode.none && h > 30) {
      _paintMidpointLine(canvas, w, bodyMidY, trimW);
    }
  }

  /// Trim zone — vertical highlight strip on clip edge
  void _paintTrimZone(Canvas canvas, Rect rect, bool isLeft) {
    // Subtle edge highlight
    final edgePaint = Paint()
      ..color = const Color(0xFF4a9eff).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, edgePaint);

    // Bright edge line (3px)
    final linePaint = Paint()
      ..color = const Color(0xFF4a9eff).withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    final lineRect = isLeft
        ? Rect.fromLTWH(rect.left, rect.top, 3, rect.height)
        : Rect.fromLTWH(rect.right - 3, rect.top, 3, rect.height);
    canvas.drawRect(lineRect, linePaint);

    // Trim arrows (◀▶) — small triangles
    final arrowPaint = Paint()
      ..color = const Color(0xFF4a9eff).withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    final cx = isLeft ? rect.left + rect.width * 0.5 : rect.right - rect.width * 0.5;
    final cy = rect.top + rect.height * 0.5;
    final arrowPath = Path();
    if (isLeft) {
      arrowPath.moveTo(cx + 3, cy - 5);
      arrowPath.lineTo(cx - 3, cy);
      arrowPath.lineTo(cx + 3, cy + 5);
    } else {
      arrowPath.moveTo(cx - 3, cy - 5);
      arrowPath.lineTo(cx + 3, cy);
      arrowPath.lineTo(cx - 3, cy + 5);
    }
    arrowPath.close();
    canvas.drawPath(arrowPath, arrowPaint);
  }

  /// Fade zone — triangular highlight in corner
  void _paintFadeZone(Canvas canvas, Rect rect, bool isLeft) {
    final fadePaint = Paint()
      ..color = const Color(0xFFFF9F43).withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    final path = Path();
    if (isLeft) {
      path.moveTo(rect.left, rect.top);
      path.lineTo(rect.right, rect.top);
      path.lineTo(rect.left, rect.bottom);
    } else {
      path.moveTo(rect.right, rect.top);
      path.lineTo(rect.left, rect.top);
      path.lineTo(rect.right, rect.bottom);
    }
    path.close();
    canvas.drawPath(path, fadePaint);

    // Corner dot
    final dotPaint = Paint()
      ..color = const Color(0xFFFF9F43).withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    final dotCenter = isLeft
        ? Offset(rect.left + 6, rect.top + 6)
        : Offset(rect.right - 6, rect.top + 6);
    canvas.drawCircle(dotCenter, 3, dotPaint);
  }

  /// Volume zone — horizontal highlight strip across top center
  void _paintVolumeZone(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = const Color(0xFF40ff90).withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, paint);

    // Horizontal line at center of top zone
    final linePaint = Paint()
      ..color = const Color(0xFF40ff90).withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final cy = rect.top + rect.height * 0.5;
    canvas.drawLine(
      Offset(rect.left + 8, cy),
      Offset(rect.right - 8, cy),
      linePaint,
    );
  }

  /// Range select zone — subtle I-beam tint in upper body
  void _paintRangeZone(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = const Color(0xFF4a9eff).withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, paint);
  }

  /// Move zone — subtle hand/grab tint in lower body
  void _paintMoveZone(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, paint);
  }

  /// Loop handle zone — small badge area bottom-right
  void _paintLoopZone(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = const Color(0xFF00BCD4).withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
    canvas.drawRRect(rRect, paint);

    // Loop circle icon
    final iconPaint = Paint()
      ..color = const Color(0xFF00BCD4).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    canvas.drawCircle(Offset(cx, cy), 5, iconPaint);
    // Arrow on circle
    final arrowPaint = Paint()
      ..color = const Color(0xFF00BCD4).withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    final arrowPath = Path()
      ..moveTo(cx + 3, cy - 6)
      ..lineTo(cx + 7, cy - 3)
      ..lineTo(cx + 1, cy - 3)
      ..close();
    canvas.drawPath(arrowPath, arrowPaint);
  }

  /// Time stretch zone — double-arrow indicators on body edges
  void _paintTimeStretchZone(Canvas canvas, Size size, double trimW, double topH, double botTop) {
    final stretchPaint = Paint()
      ..color = const Color(0xFFFF6B6B).withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    // Left edge body
    canvas.drawRect(Rect.fromLTWH(0, topH, trimW, botTop - topH), stretchPaint);
    // Right edge body
    canvas.drawRect(Rect.fromLTWH(size.width - trimW, topH, trimW, botTop - topH), stretchPaint);

    // Double arrow icon (⟺)
    final arrowPaint = Paint()
      ..color = const Color(0xFFFF6B6B).withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final cy = (topH + botTop) / 2;
    // Left arrows
    canvas.drawLine(Offset(2, cy), Offset(trimW - 2, cy), arrowPaint);
    canvas.drawLine(Offset(2, cy), Offset(6, cy - 4), arrowPaint);
    canvas.drawLine(Offset(2, cy), Offset(6, cy + 4), arrowPaint);
    // Right arrows
    canvas.drawLine(Offset(size.width - trimW + 2, cy), Offset(size.width - 2, cy), arrowPaint);
    canvas.drawLine(Offset(size.width - 2, cy), Offset(size.width - 6, cy - 4), arrowPaint);
    canvas.drawLine(Offset(size.width - 2, cy), Offset(size.width - 6, cy + 4), arrowPaint);
  }

  /// Crossfade zone indicator
  void _paintCrossfadeZone(Canvas canvas, Size size, double trimW, double botTop, double botH) {
    final paint = Paint()
      ..color = const Color(0xFFE040FB).withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    // Paint on both edges in bottom row
    canvas.drawRect(Rect.fromLTWH(0, botTop, trimW * 0.5, botH), paint);
    canvas.drawRect(Rect.fromLTWH(size.width - trimW * 0.5, botTop, trimW * 0.5, botH), paint);
  }

  /// Slip content indicator — horizontal arrows overlay
  void _paintSlipZone(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, paint);

    // H-resize arrows in center
    final arrowPaint = Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(Offset(cx - 15, cy), Offset(cx + 15, cy), arrowPaint);
    canvas.drawLine(Offset(cx - 15, cy), Offset(cx - 11, cy - 4), arrowPaint);
    canvas.drawLine(Offset(cx - 15, cy), Offset(cx - 11, cy + 4), arrowPaint);
    canvas.drawLine(Offset(cx + 15, cy), Offset(cx + 11, cy - 4), arrowPaint);
    canvas.drawLine(Offset(cx + 15, cy), Offset(cx + 11, cy + 4), arrowPaint);
  }

  /// Body midpoint separator — subtle dashed line at 50%
  void _paintMidpointLine(Canvas canvas, double w, double midY, double trimW) {
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.08)
      ..strokeWidth = 0.5;

    // Dashed line
    const dashW = 4.0;
    const gapW = 3.0;
    var x = trimW;
    while (x < w - trimW) {
      canvas.drawLine(Offset(x, midY), Offset((x + dashW).clamp(0, w - trimW), midY), paint);
      x += dashW + gapW;
    }
  }

  @override
  bool shouldRepaint(_SmartToolZonePainter oldDelegate) =>
      mode != oldDelegate.mode ||
      clipWidth != oldDelegate.clipWidth ||
      clipHeight != oldDelegate.clipHeight;
}

/// Stateful drag handle for a single warp marker.
/// Tracks accumulated position to avoid the stale-data bug.
class _WarpMarkerDragHandle extends StatefulWidget {
  final int markerId;
  final double initialTimelinePos;
  /// Current pitch offset (semitones) for this marker's segment
  final double pitchSemitones;
  final double clipDuration;
  final double zoom;
  final double snapValue;
  final double tempo;
  final bool snapEnabled;
  final void Function(int markerId, double newTimelinePos)? onMove;
  final void Function(int markerId, double originalPos, double finalPos)? onMoveEnd;
  /// Right-click → pitch preset selection
  final void Function(int markerId, double semitones)? onPitchChanged;
  /// Notifies parent which marker is being dragged (for overlay painter guide)
  final ValueChanged<int?>? onDragStateChanged;

  const _WarpMarkerDragHandle({
    required this.markerId,
    required this.initialTimelinePos,
    this.pitchSemitones = 0.0,
    required this.clipDuration,
    required this.zoom,
    this.snapValue = 1.0,
    this.tempo = 120.0,
    this.snapEnabled = false,
    this.onMove,
    this.onMoveEnd,
    this.onPitchChanged,
    this.onDragStateChanged,
  });

  @override
  State<_WarpMarkerDragHandle> createState() => _WarpMarkerDragHandleState();
}

class _WarpMarkerDragHandleState extends State<_WarpMarkerDragHandle> {
  double _accumulatedPos = 0;
  double _originalPos = 0;
  bool _isDragging = false;

  double _snapTime(double time) {
    if (!widget.snapEnabled) return time;
    final beatDuration = 60.0 / widget.tempo;
    final gridDuration = beatDuration * widget.snapValue;
    if (gridDuration <= 0) return time;
    return (time / gridDuration).round() * gridDuration;
  }

  void _showPitchMenu(BuildContext context, Offset globalPosition) {
    const presets = <double>[-24, -12, -7, -5, -2, -1, 0, 1, 2, 5, 7, 12, 24];
    final currentPitch = widget.pitchSemitones;

    showMenu<double>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx, globalPosition.dy,
        globalPosition.dx + 1, globalPosition.dy + 1,
      ),
      color: const Color(0xFF1C1C26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: [
        PopupMenuItem<double>(
          enabled: false,
          height: 28,
          child: Text(
            'Segment Pitch',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white54,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const PopupMenuDivider(height: 1),
        ...presets.map((st) {
          final isActive = (st - currentPitch).abs() < 0.05;
          final label = st == 0
              ? '0  (no pitch shift)'
              : st > 0
                  ? '+${st.toStringAsFixed(0)} st'
                  : '${st.toStringAsFixed(0)} st';
          return PopupMenuItem<double>(
            value: st,
            height: 32,
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  child: isActive
                      ? const Icon(Icons.check, size: 12, color: Color(0xFF50D0FF))
                      : null,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isActive
                        ? const Color(0xFF50D0FF)
                        : st == 0
                            ? Colors.white70
                            : st > 0
                                ? const Color(0xFFFF9850)
                                : const Color(0xFF50AAFF),
                    fontFamily: 'JetBrains Mono',
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    ).then((selected) {
      if (selected != null) {
        widget.onPitchChanged?.call(widget.markerId, selected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) {
        _originalPos = widget.initialTimelinePos;
        _accumulatedPos = widget.initialTimelinePos;
        _isDragging = true;
        widget.onDragStateChanged?.call(widget.markerId);
      },
      onHorizontalDragUpdate: (details) {
        if (!_isDragging) return;
        final deltaSec = details.delta.dx / widget.zoom;
        var newPos = (_accumulatedPos + deltaSec).clamp(0.0, widget.clipDuration);
        newPos = _snapTime(newPos);
        _accumulatedPos = newPos;
        widget.onMove?.call(widget.markerId, _accumulatedPos);
      },
      onHorizontalDragEnd: (_) {
        if (_isDragging && (_accumulatedPos - _originalPos).abs() > 0.001) {
          widget.onMoveEnd?.call(widget.markerId, _originalPos, _accumulatedPos);
        }
        _isDragging = false;
        widget.onDragStateChanged?.call(null);
      },
      onHorizontalDragCancel: () {
        _isDragging = false;
        widget.onDragStateChanged?.call(null);
      },
      onSecondaryTapUp: widget.onPitchChanged != null
          ? (details) => _showPitchMenu(context, details.globalPosition)
          : null,
      child: const MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: SizedBox.expand(),
      ),
    );
  }
}

/// Warp overlay painter: transient markers (gray dots) + warp markers (cyan lines)
/// + stretch region coloring (blue=compressed, orange=expanded) with intensity
/// proportional to stretch ratio. Phase 4 visualization upgrade.
class _WarpOverlayPainter extends CustomPainter {
  final List<WarpMarkerData> markers;
  final List<double> transients;
  final double clipDuration;
  /// Currently dragged marker ID (shows source-position guide line)
  final int? draggingMarkerId;

  // Pre-allocated paints (avoid GC in paint loop)
  static final _transientPaint = Paint()
    ..color = const Color(0x60FFFFFF)
    ..style = PaintingStyle.fill;
  static final _markerPaint = Paint()
    ..color = const Color(0xAA50D0FF)
    ..strokeWidth = 1.5;
  static final _lockedPaint = Paint()
    ..color = const Color(0x60FFFFFF)
    ..strokeWidth = 1.0;
  static final _quantizedPaint = Paint()
    ..color = const Color(0xAA50FF98)
    ..strokeWidth = 1.5;
  static final _diamondPaint = Paint()..color = const Color(0xCC50D0FF);
  static final _lockedDiamondPaint = Paint()..color = const Color(0x80FFFFFF);
  static final _quantizedDiamondPaint = Paint()..color = const Color(0xCC50FF98);
  static final _sourceGuidePaint = Paint()
    ..color = const Color(0x60FF9850)
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;
  static final _sourceGuideDashPaint = Paint()
    ..color = const Color(0x40FF9850)
    ..strokeWidth = 1.0;

  _WarpOverlayPainter({
    required this.markers,
    required this.transients,
    required this.clipDuration,
    this.draggingMarkerId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (clipDuration <= 0) return;
    final pxPerSec = size.width / clipDuration;

    // Draw stretch regions between markers (colored bands with intensity)
    if (markers.length >= 2) {
      for (int i = 0; i < markers.length - 1; i++) {
        final m0 = markers[i];
        final m1 = markers[i + 1];
        final sourceLen = m1.sourcePos - m0.sourcePos;
        final timelineLen = m1.timelinePos - m0.timelinePos;
        if (sourceLen <= 0 || timelineLen <= 0) continue;
        final ratio = timelineLen / sourceLen;

        if ((ratio - 1.0).abs() > 0.02) {
          final x0 = m0.timelinePos * pxPerSec;
          final x1 = m1.timelinePos * pxPerSec;
          final regionWidth = x1 - x0;
          if (regionWidth < 1) continue;

          // Intensity proportional to how much stretch/compress
          // ratio < 1.0 = compressed (blue), ratio > 1.0 = expanded (orange)
          final isExpanded = ratio > 1.0;
          final deviation = (ratio - 1.0).abs().clamp(0.0, 2.0);
          // Alpha scales: subtle at 2%, strong at 50%+ deviation
          final alpha = (0.08 + deviation * 0.25).clamp(0.0, 0.45);

          final regionColor = isExpanded
              ? Color.fromRGBO(255, 152, 80, alpha)   // orange for expand
              : Color.fromRGBO(80, 170, 255, alpha);  // blue for compress

          final regionPaint = Paint()
            ..color = regionColor
            ..style = PaintingStyle.fill;

          final rect = Rect.fromLTRB(
            x0.clamp(0.0, size.width), 0,
            x1.clamp(0.0, size.width), size.height,
          );
          canvas.drawRect(rect, regionPaint);

          // Top/bottom edge lines for region boundaries
          final edgeColor = isExpanded
              ? Color.fromRGBO(255, 152, 80, (alpha * 1.5).clamp(0.0, 0.6))
              : Color.fromRGBO(80, 170, 255, (alpha * 1.5).clamp(0.0, 0.6));
          final edgePaint = Paint()
            ..color = edgeColor
            ..strokeWidth = 0.5;
          canvas.drawLine(Offset(x0, 0), Offset(x1, 0), edgePaint);
          canvas.drawLine(Offset(x0, size.height), Offset(x1, size.height), edgePaint);

          // Ratio label for wide-enough regions
          if (regionWidth > 35) {
            _drawRegionRatioLabel(canvas, x0, regionWidth, size.height, ratio, isExpanded);
          }
        }
      }
    }

    // Draw transient markers (small gray triangles at top)
    for (final t in transients) {
      final x = t * pxPerSec;
      if (x < 0 || x > size.width) continue;
      final path = Path()
        ..moveTo(x - 2.5, 0)
        ..lineTo(x + 2.5, 0)
        ..lineTo(x, 5)
        ..close();
      canvas.drawPath(path, _transientPaint);
    }

    // Draw warp marker lines + diamond handles
    for (final m in markers) {
      final x = m.timelinePos * pxPerSec;
      if (x < -5 || x > size.width + 5) continue;

      // Choose paint based on marker kind
      final Paint linePaint;
      final Paint handlePaint;
      if (m.locked) {
        linePaint = _lockedPaint;
        handlePaint = _lockedDiamondPaint;
      } else if (m.kind == WarpMarkerKind.quantized) {
        linePaint = _quantizedPaint;
        handlePaint = _quantizedDiamondPaint;
      } else {
        linePaint = _markerPaint;
        handlePaint = _diamondPaint;
      }

      // Vertical marker line
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

      // Source position guide (dashed) when dragging this marker
      if (draggingMarkerId == m.id && m.sourcePos != m.timelinePos) {
        final srcX = m.sourcePos * pxPerSec;
        if (srcX >= 0 && srcX <= size.width) {
          // Draw dashed vertical line at source position
          const dashLen = 3.0;
          const gapLen = 3.0;
          double y = 0;
          while (y < size.height) {
            final endY = (y + dashLen).clamp(0.0, size.height);
            canvas.drawLine(Offset(srcX, y), Offset(srcX, endY), _sourceGuideDashPaint);
            y += dashLen + gapLen;
          }
          // Arrow from source to current position
          final midY = size.height * 0.6;
          canvas.drawLine(Offset(srcX, midY), Offset(x, midY), _sourceGuidePaint);
        }
      }

      // Diamond handle at top
      if (!m.locked) {
        final diamond = Path()
          ..moveTo(x, 2)
          ..lineTo(x + 4, 7)
          ..lineTo(x, 12)
          ..lineTo(x - 4, 7)
          ..close();
        canvas.drawPath(diamond, handlePaint);
        // White outline when dragging
        if (draggingMarkerId == m.id) {
          canvas.drawPath(diamond, Paint()
            ..color = const Color(0xCCFFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0);
        }
      } else {
        // Lock indicator (small square) for locked markers
        canvas.drawRect(
          Rect.fromCenter(center: Offset(x, 7), width: 6, height: 6),
          handlePaint,
        );
      }

      // Pitch badge: shown below diamond when segment has non-zero pitch shift
      if (m.hasPitch) {
        _drawPitchBadge(canvas, x, size.height, m.pitchSemitones);
      }
    }
  }

  void _drawPitchBadge(Canvas canvas, double x, double height, double semitones) {
    final label = semitones > 0
        ? '+${semitones.toStringAsFixed(semitones.truncateToDouble() == semitones ? 0 : 1)}'
        : semitones.toStringAsFixed(semitones.truncateToDouble() == semitones ? 0 : 1);
    final color = semitones > 0
        ? const Color(0xFFFF9850)  // orange = pitch up
        : const Color(0xFF50AAFF); // blue  = pitch down

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 7,
          fontWeight: FontWeight.bold,
          fontFamily: 'JetBrains Mono',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Position: just below diamond (y=14), centered on marker x
    const badgeY = 14.0;
    final badgeX = x - tp.width / 2;
    if (badgeX < 0 || badgeX + tp.width > 9999) return; // skip if off-screen

    // Dark pill background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(badgeX - 2, badgeY - 1, tp.width + 4, tp.height + 2),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xCC08080C),
    );
    tp.paint(canvas, Offset(badgeX, badgeY));
  }

  void _drawRegionRatioLabel(Canvas canvas, double x, double width,
      double height, double ratio, bool isExpanded) {
    final text = '${(ratio * 100).toStringAsFixed(0)}%';
    final color = isExpanded
        ? const Color(0xFFFF9850)
        : const Color(0xFF50AAFF);

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.bold,
          fontFamily: 'JetBrains Mono',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final textX = x + (width - textPainter.width) / 2;
    final textY = (height - textPainter.height) / 2;

    // Background pill for readability
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(textX - 3, textY - 1, textPainter.width + 6, textPainter.height + 2),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xCC08080C),
    );

    textPainter.paint(canvas, Offset(textX, textY));
  }

  @override
  bool shouldRepaint(_WarpOverlayPainter oldDelegate) {
    if (clipDuration != oldDelegate.clipDuration) return true;
    if (markers.length != oldDelegate.markers.length) return true;
    if (transients.length != oldDelegate.transients.length) return true;
    if (draggingMarkerId != oldDelegate.draggingMarkerId) return true;
    // Deep compare markers (WarpMarkerData has == operator)
    for (int i = 0; i < markers.length; i++) {
      if (markers[i] != oldDelegate.markers[i]) return true;
    }
    for (int i = 0; i < transients.length; i++) {
      if (transients[i] != oldDelegate.transients[i]) return true;
    }
    return false;
  }
}
