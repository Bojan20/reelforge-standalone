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
import '../editors/clip_fx_editor.dart';
import '../waveform/ultimate_waveform.dart';
import 'stretch_overlay.dart';

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
  final ValueChanged<String>? onRename;
  final ValueChanged<double>? onSlipEdit;
  final VoidCallback? onOpenFxEditor;
  final VoidCallback? onOpenAudioEditor;
  /// Context menu callbacks
  final VoidCallback? onDelete;
  final VoidCallback? onDuplicate;
  final VoidCallback? onSplit;
  final VoidCallback? onMute;
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
    this.onRename,
    this.onSlipEdit,
    this.onOpenFxEditor,
    this.onOpenAudioEditor,
    this.onDelete,
    this.onDuplicate,
    this.onSplit,
    this.onMute,
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
                Icon(Icons.graphic_eq, size: 18, color: ReelForgeTheme.accentBlue),
                const SizedBox(width: 8),
                Text('Edit Audio', style: TextStyle(color: ReelForgeTheme.accentBlue)),
                const Spacer(),
                Text('Double-Click', style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 10)),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              const Icon(Icons.edit, size: 18),
              const SizedBox(width: 8),
              const Text('Rename'),
              const Spacer(),
              Text('F2', style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 18),
              const SizedBox(width: 8),
              const Text('Duplicate'),
              const Spacer(),
              Text('⌘D', style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'split',
          child: Row(
            children: [
              const Icon(Icons.content_cut, size: 18),
              const SizedBox(width: 8),
              const Text('Split at Playhead'),
              const Spacer(),
              Text('S', style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 12)),
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
              Text('M', style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 12)),
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
          child: Row(
            children: [
              Icon(Icons.delete, size: 18, color: ReelForgeTheme.accentRed),
              const SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: ReelForgeTheme.accentRed)),
              const Spacer(),
              Text('⌫', style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 12)),
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
          _startEditing();
          break;
        case 'duplicate':
          widget.onDuplicate?.call();
          break;
        case 'split':
          widget.onSplit?.call();
          break;
        case 'mute':
          widget.onMute?.call();
          break;
        case 'fx':
          widget.onOpenFxEditor?.call();
          break;
        case 'delete':
          widget.onDelete?.call();
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
    // Logic Pro style: Pastel blue background with white waveform
    const clipColor = Color(0xFF4A90C2); // Logic Pro audio region blue

    return Positioned(
      left: x,
      top: 2,
      width: width.clamp(4, double.infinity),
      height: clipHeight,
      child: GestureDetector(
        onTap: () => widget.onSelect?.call(false),
        onDoubleTap: _startEditing,
        onSecondaryTapDown: (details) {
          // Select clip on right-click before showing menu
          widget.onSelect?.call(false);
          _showContextMenu(context, details.globalPosition);
        },
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
            final snappedTime = applySnap(
              rawNewStartTime,
              widget.snapEnabled,
              widget.snapValue,
              widget.tempo,
              widget.allClips,
            );
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
          if (_isDraggingMove) {
            // Use _wasCrossTrackDrag to ensure cleanup even if user moved back
            if (_isCrossTrackDrag || _wasCrossTrackDrag) {
              // Cross-track drag - let timeline handle the move
              widget.onCrossTrackDragEnd?.call();
            }
            // Always call onMove for same-track or if cross-track resulted in same track
            if (!_isCrossTrackDrag) {
              widget.onMove?.call(_lastSnappedTime);
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
          });
        },
        onPanCancel: () {
          // ALWAYS call onDragEnd to clear ghost - no conditions
          widget.onDragEnd?.call(_lastDragPosition);
          setState(() {
            _isDraggingMove = false;
            _isSlipEditing = false;
            _isCrossTrackDrag = false;
            _wasCrossTrackDrag = false;
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
              if (clip.waveform != null && width > 20)
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: _UltimateClipWaveform(
                      waveform: clip.waveform!,
                      waveformRight: clip.waveformRight, // Stereo support
                      sourceOffset: clip.sourceOffset,
                      duration: clip.duration,
                      gain: clip.gain,
                      zoom: widget.zoom,
                      clipColor: clipColor,
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
                            color: ReelForgeTheme.textPrimary,
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
                            color: ReelForgeTheme.textPrimary,
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
                            : ReelForgeTheme.bgVoid.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        _gainDisplay,
                        style: TextStyle(
                          fontSize: 9,
                          color: ReelForgeTheme.textPrimary,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                    ),
                  ),
                ),

              // Fade in handle
              _FadeHandle(
                width: (clip.fadeIn * widget.zoom).clamp(8.0, double.infinity),
                fadeTime: clip.fadeIn,
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
                fadeTime: clip.fadeOut,
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

// ============ Ultimate Clip Waveform ============
/// Advanced waveform widget for clips - best of all DAWs

class _UltimateClipWaveform extends StatefulWidget {
  final Float32List waveform;
  final Float32List? waveformRight;
  final double sourceOffset;
  final double duration;
  final double gain;
  final double zoom;
  final Color clipColor;

  const _UltimateClipWaveform({
    required this.waveform,
    this.waveformRight,
    required this.sourceOffset,
    required this.duration,
    required this.gain,
    required this.zoom,
    required this.clipColor,
  });

  @override
  State<_UltimateClipWaveform> createState() => _UltimateClipWaveformState();
}

class _UltimateClipWaveformState extends State<_UltimateClipWaveform> {
  UltimateWaveformData? _waveformData;
  Float32List? _lastWaveform;

  @override
  void didUpdateWidget(_UltimateClipWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuild data only if waveform changed
    if (widget.waveform != _lastWaveform) {
      _buildWaveformData();
    }
  }

  @override
  void initState() {
    super.initState();
    _buildWaveformData();
  }

  void _buildWaveformData() {
    _lastWaveform = widget.waveform;
    // Convert Float32List to List<double> for UltimateWaveformData
    final leftSamples = widget.waveform.map((s) => s.toDouble()).toList();
    final rightSamples = widget.waveformRight?.map((s) => s.toDouble()).toList();

    _waveformData = UltimateWaveformData.fromSamples(
      leftSamples,
      rightChannelSamples: rightSamples,
      sampleRate: 48000, // Default, could be passed from clip
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_waveformData == null) {
      return const SizedBox.shrink();
    }

    // Calculate samples per pixel for LOD selection
    final isStereo = widget.waveformRight != null;

    // Logic Pro style: CLEAN WHITE waveform on BLUE background
    // No transients, no clipping markers, no extra colors - JUST CLEAN WHITE WAVE
    const waveColor = Color(0xFFFFFFFF); // Pure white
    const rmsWaveColor = Color(0xDDFFFFFF); // Slightly transparent white

    final config = UltimateWaveformConfig(
      style: WaveformStyle.filled,
      primaryColor: waveColor,
      rmsColor: rmsWaveColor,
      transientColor: waveColor,
      clippingColor: waveColor,
      zeroCrossingColor: waveColor,
      showRms: true,
      showTransients: false,
      showClipping: false,
      showZeroCrossings: false,
      showSampleDots: false,
      use3dEffect: false,
      antiAlias: true,
      lineWidth: 1.0,
      transparentBackground: true, // Use clip's background color instead
    );

    return Transform.scale(
      scaleY: widget.gain,
      child: UltimateWaveform(
        data: _waveformData!,
        config: config,
        zoom: 1, // Zoom handled by clip width
        scrollOffset: 0,
        isStereoSplit: isStereo && widget.zoom > 40, // Split at higher zoom
      ),
    );
  }

  /// Darken a color by a factor (0.0 = no change, 1.0 = black)
  Color _darkenColor(Color color, double factor) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness * (1 - factor)).clamp(0.0, 1.0)).toColor();
  }

  /// Lighten a color by a factor (0.0 = no change, 1.0 = white)
  Color _lightenColor(Color color, double factor) {
    final hsl = HSLColor.fromColor(color);
    final newLightness = hsl.lightness + (1.0 - hsl.lightness) * factor;
    return hsl.withLightness(newLightness.clamp(0.0, 1.0)).toColor();
  }

  /// Increase saturation of a color (Logic Pro style vivid waveforms)
  Color _saturateColor(Color color, double factor) {
    final hsl = HSLColor.fromColor(color);
    final newSaturation = (hsl.saturation + factor).clamp(0.0, 1.0);
    return hsl.withSaturation(newSaturation).toColor();
  }
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

  _WaveformPainter({
    required this.waveform,
    required this.color,
    required this.sourceOffset,
    required this.duration,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty || size.width <= 0 || size.height <= 0) return;

    final centerY = size.height / 2;
    final amplitude = centerY * 0.9;
    final samplesPerPixel = waveform.length / size.width;

    // LOD: Choose rendering method based on zoom level (Cubase/Pro Tools style)
    // High zoom (< 4 samples/pixel) = sample-accurate with interpolation
    // Medium zoom (4-100 samples/pixel) = true min/max envelope (shows all transients)
    // Low zoom (> 100 samples/pixel) = RMS + peak overview

    if (samplesPerPixel < 4) {
      _drawDetailedWaveform(canvas, size, centerY, amplitude, samplesPerPixel);
    } else if (samplesPerPixel < 100) {
      _drawMinMaxWaveform(canvas, size, centerY, amplitude, samplesPerPixel);
    } else {
      _drawOverviewWaveform(canvas, size, centerY, amplitude, samplesPerPixel);
    }
  }

  /// HIGH ZOOM: Sample-accurate waveform with sinc interpolation appearance
  void _drawDetailedWaveform(Canvas canvas, Size size, double centerY, double amplitude, double samplesPerPixel) {
    // Use path for smooth curves (like Cubase)
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

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

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(topPath, linePaint);
    canvas.drawPath(bottomPath, linePaint);

    // Zero line (subtle)
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()..color = Colors.white.withValues(alpha: 0.1)..strokeWidth = 0.5,
    );
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
  /// This is critical for accuracy: shows ACTUAL peaks, not averaged
  void _drawMinMaxWaveform(Canvas canvas, Size size, double centerY, double amplitude, double samplesPerPixel) {
    // Peak envelope (outer) - shows true transients
    final peakPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    // RMS envelope (inner) - shows perceived loudness
    final rmsPaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    // Collect min/max for path-based rendering (smoother)
    final minValues = <double>[];
    final maxValues = <double>[];
    final rmsValues = <double>[];

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

      minValues.add(minVal);
      maxValues.add(maxVal);
      rmsValues.add(count > 0 ? math.sqrt(sumSq / count) : 0);
    }

    // Draw peak envelope as filled path (more accurate than rectangles)
    final peakPath = Path();
    for (int i = 0; i < maxValues.length; i++) {
      final y = centerY - maxValues[i] * amplitude;
      if (i == 0) {
        peakPath.moveTo(i.toDouble(), y);
      } else {
        peakPath.lineTo(i.toDouble(), y);
      }
    }
    // Connect to min values in reverse
    for (int i = minValues.length - 1; i >= 0; i--) {
      final y = centerY - minValues[i] * amplitude;
      peakPath.lineTo(i.toDouble(), y);
    }
    peakPath.close();
    canvas.drawPath(peakPath, peakPaint);

    // Draw RMS as filled path (inner, solid)
    final rmsPath = Path();
    for (int i = 0; i < rmsValues.length; i++) {
      final y = centerY - rmsValues[i] * amplitude;
      if (i == 0) {
        rmsPath.moveTo(i.toDouble(), y);
      } else {
        rmsPath.lineTo(i.toDouble(), y);
      }
    }
    for (int i = rmsValues.length - 1; i >= 0; i--) {
      final y = centerY + rmsValues[i] * amplitude;
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

  /// LOW ZOOM: RMS overview with peak indicators
  void _drawOverviewWaveform(Canvas canvas, Size size, double centerY, double amplitude, double samplesPerPixel) {
    final rmsPaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    final peakPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    final rmsPath = Path();
    final peakPath = Path();
    bool started = false;

    final rmsBottom = <double>[];
    final peakBottom = <double>[];

    for (double x = 0; x < size.width; x++) {
      final startIdx = (x * samplesPerPixel).floor().clamp(0, waveform.length - 1);
      final endIdx = ((x + 1) * samplesPerPixel).ceil().clamp(startIdx + 1, waveform.length);

      double peakAbs = 0;
      double sumSq = 0;
      int count = 0;

      for (int i = startIdx; i < endIdx; i++) {
        final s = waveform[i].abs();
        if (s > peakAbs) peakAbs = s;
        sumSq += s * s;
        count++;
      }

      final rms = count > 0 ? math.sqrt(sumSq / count) : 0;

      final rmsTop = centerY - rms * amplitude;
      final peakTop = centerY - peakAbs * amplitude;

      if (!started) {
        rmsPath.moveTo(x, rmsTop);
        peakPath.moveTo(x, peakTop);
        started = true;
      } else {
        rmsPath.lineTo(x, rmsTop);
        peakPath.lineTo(x, peakTop);
      }

      rmsBottom.add(centerY + rms * amplitude);
      peakBottom.add(centerY + peakAbs * amplitude);
    }

    // Close peak path
    for (int i = peakBottom.length - 1; i >= 0; i--) {
      peakPath.lineTo(i.toDouble(), peakBottom[i]);
    }
    peakPath.close();

    // Close RMS path
    for (int i = rmsBottom.length - 1; i >= 0; i--) {
      rmsPath.lineTo(i.toDouble(), rmsBottom[i]);
    }
    rmsPath.close();

    canvas.drawPath(peakPath, peakPaint);
    canvas.drawPath(rmsPath, rmsPaint);

    // Zero line
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()..color = Colors.white.withValues(alpha: 0.06)..strokeWidth = 0.5,
    );
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
      // Fade IN: dark at top-left (silence) → clear at right (full volume)
      // Triangle: top-left corner filled, representing reduced gain at start
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(0, size.height);
      path.close();
    } else {
      // Fade OUT: clear at left (full volume) → dark at top-right (silence)
      // Triangle: top-right corner filled, representing reduced gain at end
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, 0);
      path.close();
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_FadeOverlayPainter oldDelegate) => isLeft != oldDelegate.isLeft;
}

// ============ Fade Handle (Logic Pro + Cubase Style) ============

class _FadeHandle extends StatefulWidget {
  final double width;
  final double fadeTime;
  final bool isLeft;
  final bool isActive;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  const _FadeHandle({
    required this.width,
    required this.fadeTime,
    required this.isLeft,
    required this.isActive,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  State<_FadeHandle> createState() => _FadeHandleState();
}

class _FadeHandleState extends State<_FadeHandle> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.isLeft ? 0 : null,
      right: widget.isLeft ? null : 0,
      top: 0,
      width: widget.width,
      height: double.infinity,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          onHorizontalDragStart: (_) => widget.onDragStart(),
          onHorizontalDragUpdate: (details) => widget.onDragUpdate(details.localPosition.dx),
          onHorizontalDragEnd: (_) => widget.onDragEnd(),
          child: Stack(
            children: [
              // Triangular fade overlay (like Logic Pro)
              Positioned.fill(
                child: CustomPaint(
                  painter: _FadeTrianglePainter(
                    isLeft: widget.isLeft,
                    isActive: widget.isActive || _isHovered,
                  ),
                ),
              ),

              // Drag handle at top corner (like Cubase)
              Positioned(
                left: widget.isLeft ? null : 0,
                right: widget.isLeft ? 0 : null,
                top: 0,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: (widget.isActive || _isHovered)
                        ? ReelForgeTheme.accentBlue
                        : ReelForgeTheme.textSecondary.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.only(
                      topLeft: widget.isLeft ? Radius.zero : const Radius.circular(4),
                      topRight: widget.isLeft ? const Radius.circular(4) : Radius.zero,
                      bottomLeft: widget.isLeft ? const Radius.circular(4) : Radius.zero,
                      bottomRight: widget.isLeft ? Radius.zero : const Radius.circular(4),
                    ),
                    boxShadow: (widget.isActive || _isHovered) ? [
                      BoxShadow(
                        color: ReelForgeTheme.accentBlue.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ] : null,
                  ),
                  child: Icon(
                    widget.isLeft ? Icons.arrow_forward_ios : Icons.arrow_back_ios,
                    size: 10,
                    color: Colors.white,
                  ),
                ),
              ),

              // Fade time label (like Pro Tools)
              if (_isHovered || widget.isActive)
                Positioned(
                  left: widget.isLeft ? 4 : null,
                  right: widget.isLeft ? null : 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: ReelForgeTheme.bgDeepest.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: ReelForgeTheme.accentBlue.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      _formatFadeTime(widget.width),
                      style: TextStyle(
                        fontSize: 9,
                        fontFamily: 'JetBrains Mono',
                        color: ReelForgeTheme.accentBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatFadeTime(double width) {
    // Use actual fade time from widget
    final seconds = widget.fadeTime;
    if (seconds < 0.01) return '0ms';
    if (seconds < 1.0) return '${(seconds * 1000).round()}ms';
    if (seconds < 10.0) return '${seconds.toStringAsFixed(2)}s';
    return '${seconds.toStringAsFixed(1)}s';
  }
}

/// Triangular fade overlay painter (Logic Pro style)
class _FadeTrianglePainter extends CustomPainter {
  final bool isLeft;
  final bool isActive;

  _FadeTrianglePainter({required this.isLeft, required this.isActive});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isActive
          ? ReelForgeTheme.accentBlue.withValues(alpha: 0.2)
          : ReelForgeTheme.textSecondary.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final path = Path();
    if (isLeft) {
      // Fade in: triangle from left
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(0, size.height);
      path.close();
    } else {
      // Fade out: triangle from right
      path.moveTo(size.width, 0);
      path.lineTo(0, 0);
      path.lineTo(size.width, size.height);
      path.close();
    }

    canvas.drawPath(path, paint);

    // Draw fade curve line (like Cubase)
    final curvePaint = Paint()
      ..color = isActive
          ? ReelForgeTheme.accentBlue.withValues(alpha: 0.6)
          : ReelForgeTheme.textSecondary.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final curvePath = Path();
    if (isLeft) {
      curvePath.moveTo(0, 0);
      curvePath.lineTo(size.width, size.height);
    } else {
      curvePath.moveTo(size.width, 0);
      curvePath.lineTo(0, size.height);
    }

    canvas.drawPath(curvePath, curvePaint);
  }

  @override
  bool shouldRepaint(_FadeTrianglePainter oldDelegate) =>
      isLeft != oldDelegate.isLeft || isActive != oldDelegate.isActive;
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
