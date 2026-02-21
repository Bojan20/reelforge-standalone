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
  final VoidCallback? onSplit;
  final VoidCallback? onMute;
  /// Called when clip is moved in Shuffle mode — clips should push neighbors
  final ValueChanged<double>? onShuffleMove;
  final ValueChanged<double>? onPlayheadMove;
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
    this.onShuffleMove,
    this.onPlayheadMove,
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

  // Smart Tool — last hit test result for cursor + drag routing
  SmartToolHitResult? _smartToolHitResult;

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
    // Time stretch is applied if clip has a time stretch FX slot that isn't bypassed
    return clip.fxChain.slots.any((s) => s.type == ClipFxType.timeStretch && !s.bypass);
  }

  /// Get time stretch ratio from clip
  double _getStretchRatio(TimelineClip clip) {
    // Calculate from duration vs source duration if available
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
          value: 'fx',
          child: Row(
            children: [
              const Icon(Icons.auto_fix_high, size: 18),
              const SizedBox(width: 8),
              const Text('Clip FX...'),
            ],
          ),
        ),
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

    // Skip if not visible
    if (x + width < 0 || x > 2000) return const SizedBox.shrink();

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
            onHover: smartEnabled && !isExplicitTool
                ? (event) {
                    final localPos = event.localPosition;
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
                : null,
            onExit: smartEnabled
                ? (_) {
                    if (_smartToolHitResult != null) {
                      setState(() => _smartToolHitResult = null);
                    }
                  }
                : null,
      // Listener detects trackpad two-finger pan (scroll gesture)
      // to prevent it from being interpreted as clip drag
      child: Listener(
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
                  // Split at click position — move playhead there first
                  if (!clip.locked) {
                    final clickTime = widget.scrollOffset + clickX / widget.zoom + clip.startTime;
                    widget.onPlayheadMove?.call(clickTime);
                    widget.onSplit?.call();
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
                  // Glue: select clip (glue requires two adjacent clips — handled at timeline level)
                  widget.onSelect?.call(false);
                  return;
                case TimelineEditTool.zoom:
                  // Zoom tool on clip: zoom in centered at click
                  // Alt+click = zoom out (handled in Timeline)
                  return;
                case TimelineEditTool.play:
                  // Play tool: move playhead to click position and trigger playback
                  final clickTime = widget.scrollOffset + clickX / widget.zoom + clip.startTime;
                  widget.onPlayheadMove?.call(clickTime);
                  return;
                default:
                  break; // smart, objectSelect, rangeSelect, draw — fall through to select
              }
            }

            // Default: select clip
            widget.onSelect?.call(false);
          },
          onDoubleTap: _startEditing,
          onSecondaryTapDown: (details) {
            // Select clip on right-click before showing menu
            widget.onSelect?.call(false);
            _showContextMenu(context, details.globalPosition);
          },
          onPanStart: (details) {
            // IGNORE if trackpad two-finger pan is active (that's scroll, not drag)
            // Only three-finger drag (equivalent to click+drag) should move clips
            if (_isTrackpadPanActive) return;

            // IGNORE if clip is locked
            if (clip.locked) return;

            // IGNORE if fade handle is being dragged
            if (_isDraggingFadeIn || _isDraggingFadeOut || fadeHandleActiveGlobal) {
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
              switch (mode) {
                case SmartToolMode.trimLeft:
                  // Start left edge trim
                  _dragStartTime = clip.startTime;
                  _dragStartDuration = clip.duration;
                  _dragStartSourceOffset = clip.sourceOffset;
                  _dragStartMouseX = details.globalPosition.dx;
                  setState(() => _isDraggingLeftEdge = true);
                  return;
                case SmartToolMode.trimRight:
                  // Start right edge trim
                  _dragStartDuration = clip.duration;
                  _dragStartMouseX = details.globalPosition.dx;
                  setState(() => _isDraggingRightEdge = true);
                  return;
                case SmartToolMode.fadeIn:
                  // Start fade in drag
                  setState(() => _isDraggingFadeIn = true);
                  fadeHandleActiveGlobal = true;
                  return;
                case SmartToolMode.fadeOut:
                  // Start fade out drag
                  setState(() => _isDraggingFadeOut = true);
                  fadeHandleActiveGlobal = true;
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
            // Check for modifier keys for slip edit (works with or without smart tool)
            if (isSlipMode ||
                HardwareKeyboard.instance.isMetaPressed ||
                HardwareKeyboard.instance.isControlPressed) {
              _dragStartSourceOffset = clip.sourceOffset;
              _dragStartMouseX = details.globalPosition.dx;
              setState(() => _isSlipEditing = true);
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

            // Update ghost position (visual feedback)
            widget.onDragUpdate?.call(details.globalPosition);

            // Cross-track drag (vertical movement)
            _isCrossTrackDrag = deltaY.abs() > 20;
            if (_isCrossTrackDrag) {
              _wasCrossTrackDrag = true; // Remember if ever crossed track threshold
              widget.onCrossTrackDrag?.call(_lastSnappedTime, deltaY);
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

          if (_isDraggingMove) {
            // Use _wasCrossTrackDrag to ensure cleanup even if user moved back
            if (_isCrossTrackDrag || _wasCrossTrackDrag) {
              // Cross-track drag - let timeline handle the move
              widget.onCrossTrackDragEnd?.call();
            }
            // Always call onMove for same-track or if cross-track resulted in same track
            if (!_isCrossTrackDrag) {
              // Shuffle mode: use shuffle callback to push adjacent clips
              final editMode = smartTool.activeEditMode;
              if (editMode == TimelineEditMode.shuffle && widget.onShuffleMove != null) {
                widget.onShuffleMove!(_lastSnappedTime);
              } else {
                widget.onMove?.call(_lastSnappedTime);
              }
            }
          }
          // ALWAYS call onDragEnd to clear ghost in timeline - no conditions
          widget.onDragEnd?.call(details.globalPosition);
          // Clear local state
          setState(() {
            _isDraggingMove = false;
            _isSlipEditing = false;
            _isCrossTrackDrag = false;
            _wasCrossTrackDrag = false;
            _isDraggingLeftEdge = false;
            _isDraggingRightEdge = false;
            _isDraggingFadeIn = false;
            _isDraggingFadeOut = false;
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
            _isSlipEditing = false;
            _isCrossTrackDrag = false;
            _wasCrossTrackDrag = false;
            _isDraggingLeftEdge = false;
            _isDraggingRightEdge = false;
            _isDraggingFadeIn = false;
            _isDraggingFadeOut = false;
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
                    // Stereo if waveformRight exists or name suggests stereo file
                    channels: clip.waveformRight != null ? 2 : 2, // Default to stereo for imported audio
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

              // Gain handle
              if (width > 60)
                Positioned(
                  top: 2,
                  left: (width - 40) / 2,
                  child: GestureDetector(
                    onVerticalDragStart: (_) {
                      // IGNORE if clip is locked
                      if (clip.locked) return;
                      setState(() => _isDraggingGain = true);
                    },
                    onVerticalDragUpdate: (details) {
                      // IGNORE if clip is locked
                      if (clip.locked) return;
                      // Up = louder, down = quieter
                      final delta = -details.delta.dy / 50;
                      final newGain = (widget.clip.gain + delta).clamp(0.0, 2.0);
                      widget.onGainChange?.call(newGain);
                    },
                    onVerticalDragEnd: (_) {
                      setState(() => _isDraggingGain = false);
                    },
                    onDoubleTap: () {
                      // IGNORE if clip is locked
                      if (clip.locked) return;
                      widget.onGainChange?.call(1); // Reset
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
              // Split tool: scissors icon
              if (isExplicitTool && activeTool == TimelineEditTool.split && !clip.locked)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: FluxForgeTheme.accentBlue.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.content_cut, color: Colors.white70, size: 18),
                    ),
                  ),
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
  });

  @override
  State<_UltimateClipWaveform> createState() => _UltimateClipWaveformState();
}

class _UltimateClipWaveformState extends State<_UltimateClipWaveform> {
  // ═══════════════════════════════════════════════════════════════════════════
  // GPU OPTIMIZATION: Fixed resolution cache with pre-computed combined L+R
  // - Render ONCE at fixed resolution, GPU scales during zoom
  // - Combined L+R computed in _loadCacheOnce(), not in build()
  // - Zero allocations during build/paint cycle
  // ═══════════════════════════════════════════════════════════════════════════
  static const int _fixedPixels = 1024;

  // Stereo data cache (L/R channels)
  StereoWaveformPixelData? _cachedStereoData;
  int _cachedClipId = 0;
  double _cachedSourceOffset = -1;
  double _cachedDuration = -1;

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
    _loadCacheOnce();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check if waveform generation changed (mode switch from SlotLab back to DAW)
    // This triggers reload even if widget props didn't change
    final currentGeneration = context.read<EditorModeProvider>().waveformGeneration;
    if (_cachedWaveformGeneration != currentGeneration && _cachedWaveformGeneration != -1) {
      _loadCacheOnce();
    }
  }

  @override
  void didUpdateWidget(_UltimateClipWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ONLY reload if CLIP CONTENT changed - NEVER on zoom!
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

    // Check waveform generation to detect mode switch invalidation
    // When user returns to DAW from SlotLab/Middleware, generation increases
    // which forces waveform cache refresh to prevent stale rendering
    final currentGeneration = context.read<EditorModeProvider>().waveformGeneration;
    final generationChanged = _cachedWaveformGeneration != currentGeneration;

    // Skip if already cached for this clip AND generation hasn't changed
    if (!generationChanged &&
        _cachedClipId == clipIdNum &&
        (_cachedSourceOffset - widget.sourceOffset).abs() < 0.01 &&
        (_cachedDuration - widget.duration).abs() < 0.01) {
      return;
    }

    // Update cached generation
    _cachedWaveformGeneration = currentGeneration;

    final sampleRate = NativeFFI.instance.getWaveformSampleRate(clipIdNum);
    final totalSamples = NativeFFI.instance.getWaveformTotalSamples(clipIdNum);
    if (totalSamples <= 0) return;

    final startFrame = (widget.sourceOffset * sampleRate).round();
    final endFrame = ((widget.sourceOffset + widget.duration) * sampleRate).round();

    // Render at FIXED resolution with STEREO data - GPU will scale to any zoom level
    final stereoData = NativeFFI.instance.queryWaveformPixelsStereo(
      clipIdNum, startFrame, endFrame, _fixedPixels,
    );

    if (stereoData != null && !stereoData.isEmpty) {
      _cachedStereoData = stereoData;
      _cachedClipId = clipIdNum;
      _cachedSourceOffset = widget.sourceOffset;
      _cachedDuration = widget.duration;

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
    }
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

    // Cached stereo path - GPU scales fixed-resolution waveform
    if (_cachedStereoData != null && !_cachedStereoData!.isEmpty) {
      // For stereo (2 channels) AND tall track (> 80px), show split L/R display
      // Otherwise show combined mono-style waveform (Pro Tools behavior)
      final showStereoSplit = widget.channels >= 2 && widget.trackHeight > 80;

      if (showStereoSplit) {
        return RepaintBoundary(
          child: ClipRect(
            child: Transform.scale(
              scaleY: widget.gain,
              child: CustomPaint(
                size: Size.infinite,
                painter: _StereoWaveformPainter(
                  leftMins: _cachedStereoData!.left.mins,
                  leftMaxs: _cachedStereoData!.left.maxs,
                  leftRms: _cachedStereoData!.left.rms,
                  rightMins: _cachedStereoData!.right.mins,
                  rightMaxs: _cachedStereoData!.right.maxs,
                  rightRms: _cachedStereoData!.right.rms,
                  color: waveColor,
                ),
              ),
            ),
          ),
        );
      }

      // Default: Combined L+R display (pre-computed, zero allocation)
      if (_combinedMins != null) {
        return RepaintBoundary(
          child: ClipRect(
            child: Transform.scale(
              scaleY: widget.gain,
              child: CustomPaint(
                size: Size.infinite,
                painter: _CubaseWaveformPainter(
                  mins: _combinedMins!,
                  maxs: _combinedMaxs!,
                  rms: _combinedRms!,
                  color: waveColor,
                ),
              ),
            ),
          ),
        );
      }
    }

    // Fallback - simple legacy waveform
    return RepaintBoundary(
      child: ClipRect(
        child: Transform.scale(
          scaleY: widget.gain,
          child: CustomPaint(
            size: Size.infinite,
            painter: _WaveformPainter(
              waveform: widget.waveform,
              sourceOffset: widget.sourceOffset,
              duration: widget.duration,
              color: waveColor,
            ),
          ),
        ),
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

  // Cached Path objects — rebuilt only on size change
  Path? _cachedWavePath;
  Path? _cachedRmsPath;
  Size? _cachedSize;

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

    // GPU OPTIMIZATION: Only rebuild paths when size changes
    if (_cachedWavePath == null || _cachedSize != size) {
      _rebuildPaths(size);
      _cachedSize = size;
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

  /// Build and cache Path objects — called only when size changes
  void _rebuildPaths(Size size) {
    final centerY = size.height / 2;
    final amplitude = centerY * 0.7;
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
      color != oldDelegate.color;
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

  // Cached Path objects — rebuilt only on size change
  Path? _leftWavePath;
  Path? _leftRmsPath;
  Path? _rightWavePath;
  Path? _rightRmsPath;
  Size? _cachedSize;

  // Pre-allocated Paint objects (zero allocation in paint())
  late final Paint _rmsFillPaint;
  late final Paint _peakFillPaint;
  late final Paint _peakStrokePaint;
  late final Paint _centerLinePaint;
  late final Paint _separatorPaint;

  _StereoWaveformPainter({
    required this.leftMins,
    required this.leftMaxs,
    required this.leftRms,
    required this.rightMins,
    required this.rightMaxs,
    required this.rightRms,
    required this.color,
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
      ..color = color.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (leftMins.isEmpty || size.width <= 0 || size.height <= 0) return;

    // GPU OPTIMIZATION: Only rebuild paths when size changes
    if (_leftWavePath == null || _cachedSize != size) {
      _rebuildAllPaths(size);
      _cachedSize = size;
    }

    final leftCenterY = size.height * 0.25;
    final rightCenterY = size.height * 0.75;

    // Draw LEFT channel (top half)
    if (_leftRmsPath != null) canvas.drawPath(_leftRmsPath!, _rmsFillPaint);
    canvas.drawPath(_leftWavePath!, _peakFillPaint);
    canvas.drawPath(_leftWavePath!, _peakStrokePaint);
    canvas.drawLine(Offset(0, leftCenterY), Offset(size.width, leftCenterY), _centerLinePaint);

    // Draw RIGHT channel (bottom half)
    if (_rightRmsPath != null) canvas.drawPath(_rightRmsPath!, _rmsFillPaint);
    canvas.drawPath(_rightWavePath!, _peakFillPaint);
    canvas.drawPath(_rightWavePath!, _peakStrokePaint);
    canvas.drawLine(Offset(0, rightCenterY), Offset(size.width, rightCenterY), _centerLinePaint);

    // Separator line between L/R
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), _separatorPaint);
  }

  /// Build and cache all 4 Path objects — called only when size changes
  void _rebuildAllPaths(Size size) {
    final numSamples = leftMins.length;
    final leftCenterY = size.height * 0.25;
    final rightCenterY = size.height * 0.75;
    final channelHeight = size.height * 0.45;
    final amplitude = channelHeight / 2;

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
      color != oldDelegate.color;
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
    final amplitude = centerY * 0.98;
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
      waveform != oldDelegate.waveform || color != oldDelegate.color;
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
