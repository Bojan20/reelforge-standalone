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
import '../../theme/fluxforge_theme.dart';
import '../../models/middleware_models.dart'; // For FadeCurve enum
import '../../src/rust/native_ffi.dart'; // For direct FFI calls

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
  hitpoint, // Cubase-style hitpoint editing
}

/// Hitpoint data structure (transient marker)
class Hitpoint {
  final int position; // Sample position
  final double strength; // Detection strength 0-1
  final bool isLocked;
  final bool isManual;

  const Hitpoint({
    required this.position,
    this.strength = 1.0,
    this.isLocked = false,
    this.isManual = false,
  });

  Hitpoint copyWith({
    int? position,
    double? strength,
    bool? isLocked,
    bool? isManual,
  }) {
    return Hitpoint(
      position: position ?? this.position,
      strength: strength ?? this.strength,
      isLocked: isLocked ?? this.isLocked,
      isManual: isManual ?? this.isManual,
    );
  }

  /// Convert position to seconds
  double toSeconds(int sampleRate) => position / sampleRate;
}

/// Hitpoint detection algorithm
enum HitpointAlgorithm {
  enhanced,     // Best general-purpose (default)
  highEmphasis, // Emphasize high-frequency transients (drums/percussion)
  lowEmphasis,  // Low-frequency focus (bass/kick)
  spectralFlux, // Spectral analysis based
  complexDomain, // Phase-based detection
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
  final void Function(String clipId, double newSourceOffset)? onSlipEdit;
  final ValueChanged<double>? onPlayheadChange;

  // Audition (playback preview) - Cubase-style
  final void Function(String clipId, double startTime, double endTime)? onAudition;
  final VoidCallback? onStopAudition;
  final bool isAuditioning;

  // Hitpoint callbacks
  final List<Hitpoint> hitpoints;
  final bool showHitpoints;
  final double hitpointSensitivity;
  final HitpointAlgorithm hitpointAlgorithm;
  final double hitpointMinGapMs;
  final ValueChanged<List<Hitpoint>>? onHitpointsChange;
  final ValueChanged<bool>? onShowHitpointsChange;
  final ValueChanged<double>? onHitpointSensitivityChange;
  final ValueChanged<HitpointAlgorithm>? onHitpointAlgorithmChange;
  final VoidCallback? onDetectHitpoints;
  final void Function(String clipId, List<Hitpoint> hitpoints)? onSliceAtHitpoints;
  final void Function(int index)? onDeleteHitpoint;
  final void Function(int index, int newPosition)? onMoveHitpoint;
  final void Function(int samplePosition)? onAddHitpoint;

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
    this.onSlipEdit,
    this.onPlayheadChange,
    // Audition
    this.onAudition,
    this.onStopAudition,
    this.isAuditioning = false,
    // Hitpoint defaults
    this.hitpoints = const [],
    this.showHitpoints = false,
    this.hitpointSensitivity = 0.5,
    this.hitpointAlgorithm = HitpointAlgorithm.enhanced,
    this.hitpointMinGapMs = 20.0,
    this.onHitpointsChange,
    this.onShowHitpointsChange,
    this.onHitpointSensitivityChange,
    this.onHitpointAlgorithmChange,
    this.onDetectHitpoints,
    this.onSliceAtHitpoints,
    this.onDeleteHitpoint,
    this.onMoveHitpoint,
    this.onAddHitpoint,
  });

  @override
  State<ClipEditor> createState() => _ClipEditorState();
}

class _ClipEditorState extends State<ClipEditor> with TickerProviderStateMixin {
  EditorTool _tool = EditorTool.select;
  bool _isDragging = false;
  double? _dragStart;
  _FadeHandle _draggingFade = _FadeHandle.none;
  // PERFORMANCE: Use ValueNotifier instead of setState for hover position
  // This prevents full widget rebuild on every mouse move
  final ValueNotifier<double> _hoverXNotifier = ValueNotifier(-1);
  double get _hoverX => _hoverXNotifier.value;
  set _hoverX(double value) => _hoverXNotifier.value = value;
  final FocusNode _focusNode = FocusNode();
  double _containerWidth = 0;

  // Hitpoint editing state
  int? _draggingHitpointIndex;
  int? _hoveredHitpointIndex;

  // Local hitpoint storage (direct FFI, bypasses callback chain)
  List<Hitpoint> _localHitpoints = [];
  bool _showLocalHitpoints = true;

  // SMOOTH ZOOM: Animated zoom system (Cubase-style)
  late AnimationController _zoomAnimController;
  late Animation<double> _zoomAnim;
  late Animation<double> _scrollAnim;
  double _zoomStart = 100;
  double _zoomTarget = 100;
  double _scrollStart = 0;
  double _scrollTarget = 0;
  bool _isZoomAnimating = false;

  @override
  void initState() {
    super.initState();

    // SMOOTH ZOOM: Initialize animation controller (80ms for snappy response)
    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _zoomAnimController.addListener(_onZoomAnimUpdate);
    _zoomAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _isZoomAnimating = false;
      }
    });

    // Initialize animations with linear (will be overridden)
    _zoomAnim = Tween<double>(begin: 100, end: 100).animate(_zoomAnimController);
    _scrollAnim = Tween<double>(begin: 0, end: 0).animate(_zoomAnimController);

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
    _zoomAnimController.dispose();
    _focusNode.dispose();
    _hoverXNotifier.dispose();
    super.dispose();
  }

  /// SMOOTH ZOOM: Animation update callback
  void _onZoomAnimUpdate() {
    if (!mounted) return;
    widget.onZoomChange?.call(_zoomAnim.value);
    widget.onScrollChange?.call(_scrollAnim.value);
  }

  /// SMOOTH ZOOM: Start animated zoom to target (cursor-anchored)
  void _animateZoomTo(double targetZoom, double anchorX, double anchorTime) {
    final clip = widget.clip;
    if (clip == null || _containerWidth <= 0) return;

    final minZoom = _containerWidth / clip.duration;
    final clampedZoom = targetZoom.clamp(minZoom, 50000.0);

    // Calculate new scroll offset to keep anchor point fixed
    final newScrollOffset = anchorTime - anchorX / clampedZoom;
    final clampedScroll = newScrollOffset.clamp(
      0.0,
      (clip.duration - _containerWidth / clampedZoom).clamp(0.0, double.infinity),
    );

    // Set up animation from current to target
    _zoomStart = widget.zoom;
    _zoomTarget = clampedZoom;
    _scrollStart = widget.scrollOffset;
    _scrollTarget = clampedScroll;

    // Create smooth animations with easeOut curve
    _zoomAnim = Tween<double>(
      begin: _zoomStart,
      end: _zoomTarget,
    ).animate(CurvedAnimation(
      parent: _zoomAnimController,
      curve: Curves.easeOut,
    ));

    _scrollAnim = Tween<double>(
      begin: _scrollStart,
      end: _scrollTarget,
    ).animate(CurvedAnimation(
      parent: _zoomAnimController,
      curve: Curves.easeOut,
    ));

    // Start animation
    _isZoomAnimating = true;
    _zoomAnimController.forward(from: 0);
  }

  /// Direct FFI call for hitpoint detection - bypasses broken callback chain
  void _detectHitpointsDirect(ClipEditorClip clip) {
    debugPrint('[ClipEditor] _detectHitpointsDirect for clip ${clip.id}');

    try {
      // Parse clip ID to int
      final clipId = int.tryParse(clip.id) ?? 0;
      if (clipId == 0) {
        debugPrint('[ClipEditor] Invalid clip ID: ${clip.id}');
        return;
      }

      // Map algorithm enum to int
      final algorithmInt = widget.hitpointAlgorithm.index;

      // Call FFI directly
      final results = NativeFFI.instance.detectClipTransients(
        clipId,
        sensitivity: widget.hitpointSensitivity,
        algorithm: algorithmInt,
        minGapMs: widget.hitpointMinGapMs,
        maxCount: 2000,
      );

      debugPrint('[ClipEditor] FFI returned ${results.length} hitpoints');

      // Convert to Hitpoint objects
      final hitpoints = results.map((r) => Hitpoint(
        position: r.position,
        strength: r.strength,
      )).toList();

      // Update local state
      setState(() {
        _localHitpoints = hitpoints;
        _showLocalHitpoints = true;
      });

      // Also notify parent if callback exists
      widget.onHitpointsChange?.call(hitpoints);

      debugPrint('[ClipEditor] Hitpoints stored locally: ${_localHitpoints.length}');
    } catch (e) {
      debugPrint('[ClipEditor] FFI error: $e');
    }
  }

  /// Get effective hitpoints (local or from widget)
  List<Hitpoint> get _effectiveHitpoints {
    // Prefer local hitpoints if available
    if (_localHitpoints.isNotEmpty) return _localHitpoints;
    return widget.hitpoints;
  }

  /// Whether to show hitpoints
  bool get _shouldShowHitpoints {
    return _showLocalHitpoints || widget.showHitpoints;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.clip != null,
      onKeyEvent: (node, event) {
        _handleKeyEvent(event);
        // Consume zoom, fade, tool, and hitpoint keys
        final isZoomKey = event.logicalKey == LogicalKeyboardKey.keyG ||
            event.logicalKey == LogicalKeyboardKey.keyH;
        final isFadeKey = event.logicalKey == LogicalKeyboardKey.bracketLeft ||
            event.logicalKey == LogicalKeyboardKey.bracketRight;
        final isToolKey = event.logicalKey == LogicalKeyboardKey.digit1 ||
            event.logicalKey == LogicalKeyboardKey.digit2 ||
            event.logicalKey == LogicalKeyboardKey.digit3 ||
            event.logicalKey == LogicalKeyboardKey.digit4 ||
            event.logicalKey == LogicalKeyboardKey.digit5 ||
            event.logicalKey == LogicalKeyboardKey.digit6;
        final isHitpointKey = event.logicalKey == LogicalKeyboardKey.keyD;
        final isAuditionKey = event.logicalKey == LogicalKeyboardKey.space;
        if (isZoomKey || isFadeKey || isToolKey || isHitpointKey || isAuditionKey) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _focusNode.requestFocus(),
        child: Container(
          decoration: const BoxDecoration(
            color: FluxForgeTheme.bgMid,
            border: Border(
              top: BorderSide(color: FluxForgeTheme.borderSubtle),
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

    // G - zoom out (SMOOTH animated, center-screen anchor)
    if (event.logicalKey == LogicalKeyboardKey.keyG && clip != null && _containerWidth > 0) {
      // Use target zoom if animating, otherwise current zoom
      final currentZoom = _isZoomAnimating ? _zoomTarget : widget.zoom;
      final centerX = _containerWidth / 2;
      final currentScroll = _isZoomAnimating ? _scrollTarget : widget.scrollOffset;
      final centerTime = currentScroll + centerX / currentZoom;
      final newZoom = currentZoom * 0.85; // Slightly larger step for smooth feel
      _animateZoomTo(newZoom, centerX, centerTime);
    }

    // H - zoom in (SMOOTH animated, center-screen anchor)
    if (event.logicalKey == LogicalKeyboardKey.keyH && clip != null && _containerWidth > 0) {
      // Use target zoom if animating, otherwise current zoom
      final currentZoom = _isZoomAnimating ? _zoomTarget : widget.zoom;
      final centerX = _containerWidth / 2;
      final currentScroll = _isZoomAnimating ? _scrollTarget : widget.scrollOffset;
      final centerTime = currentScroll + centerX / currentZoom;
      final newZoom = currentZoom * 1.18; // Slightly larger step for smooth feel
      _animateZoomTo(newZoom, centerX, centerTime);
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
    if (event.logicalKey == LogicalKeyboardKey.digit6) {
      setState(() => _tool = EditorTool.hitpoint);
    }

    // D - detect hitpoints (direct FFI call - bypasses callback chain)
    if (event.logicalKey == LogicalKeyboardKey.keyD) {
      if (clip != null) {
        _detectHitpointsDirect(clip);
      }
    }

    // Delete - remove selected/hovered hitpoint
    if ((event.logicalKey == LogicalKeyboardKey.delete ||
         event.logicalKey == LogicalKeyboardKey.backspace) &&
        _hoveredHitpointIndex != null &&
        _tool == EditorTool.hitpoint) {
      widget.onDeleteHitpoint?.call(_hoveredHitpointIndex!);
    }

    // Space - Audition (play clip or selection)
    if (event.logicalKey == LogicalKeyboardKey.space && clip != null) {
      if (widget.isAuditioning) {
        widget.onStopAudition?.call();
      } else {
        final sel = widget.selection;
        if (sel != null && sel.isValid) {
          widget.onAudition?.call(clip.id, sel.start, sel.end);
        } else {
          widget.onAudition?.call(clip.id, 0, clip.duration);
        }
      }
    }
  }

  Widget _buildHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.edit, size: 14, color: FluxForgeTheme.accentBlue),
          const SizedBox(width: 8),
          Text(
            widget.clip?.name ?? 'Clip Editor',
            style: FluxForgeTheme.h3,
          ),
          if (widget.clip != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                _formatTime(widget.clip!.duration),
                style: FluxForgeTheme.monoSmall,
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
        _ToolButton(
          icon: Icons.flash_on,
          label: 'Hitpoints (6)',
          isActive: _tool == EditorTool.hitpoint,
          onTap: () => setState(() => _tool = EditorTool.hitpoint),
        ),
        const SizedBox(width: 8),
        Container(width: 1, height: 16, color: FluxForgeTheme.borderSubtle),
        const SizedBox(width: 8),
        // Hitpoint controls (visible when hitpoint tool selected)
        if (_tool == EditorTool.hitpoint || _shouldShowHitpoints) ...[
          _ToolButton(
            icon: Icons.auto_fix_high,
            label: 'Detect (D)',
            isEnabled: hasClip,
            onTap: hasClip ? () {
              if (widget.clip != null) {
                _detectHitpointsDirect(widget.clip!);
              }
            } : null,
          ),
          // Show/Hide toggle
          _ToolButton(
            icon: _shouldShowHitpoints ? Icons.visibility : Icons.visibility_off,
            label: _shouldShowHitpoints ? 'Hide Hitpoints' : 'Show Hitpoints',
            isActive: _shouldShowHitpoints,
            onTap: () {
              setState(() {
                _showLocalHitpoints = !_showLocalHitpoints;
              });
              widget.onShowHitpointsChange?.call(!_shouldShowHitpoints);
            },
          ),
          // Hitpoint count
          if (_effectiveHitpoints.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentOrange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '${_effectiveHitpoints.length}',
                style: FluxForgeTheme.monoSmall.copyWith(
                  color: FluxForgeTheme.accentOrange,
                ),
              ),
            ),
          const SizedBox(width: 8),
          Container(width: 1, height: 16, color: FluxForgeTheme.borderSubtle),
          const SizedBox(width: 8),
        ],
        // Zoom controls (SMOOTH ANIMATED)
        _ToolButton(
          icon: Icons.zoom_out,
          label: 'Zoom Out',
          onTap: () {
            if (widget.clip == null || _containerWidth <= 0) return;
            final currentZoom = _isZoomAnimating ? _zoomTarget : widget.zoom;
            final currentScroll = _isZoomAnimating ? _scrollTarget : widget.scrollOffset;
            final centerX = _containerWidth / 2;
            final centerTime = currentScroll + centerX / currentZoom;
            _animateZoomTo(currentZoom * 0.75, centerX, centerTime);
          },
        ),
        Text('${widget.zoom.toInt()}%', style: FluxForgeTheme.monoSmall),
        _ToolButton(
          icon: Icons.zoom_in,
          label: 'Zoom In',
          onTap: () {
            if (widget.clip == null || _containerWidth <= 0) return;
            final currentZoom = _isZoomAnimating ? _zoomTarget : widget.zoom;
            final currentScroll = _isZoomAnimating ? _scrollTarget : widget.scrollOffset;
            final centerX = _containerWidth / 2;
            final centerTime = currentScroll + centerX / currentZoom;
            _animateZoomTo(currentZoom * 1.33, centerX, centerTime);
          },
        ),
        const SizedBox(width: 8),
        Container(width: 1, height: 16, color: FluxForgeTheme.borderSubtle),
        const SizedBox(width: 8),
        // AUDITION - Cubase-style playback preview (Space key)
        _ToolButton(
          icon: widget.isAuditioning ? Icons.stop : Icons.play_arrow,
          label: widget.isAuditioning ? 'Stop' : 'Audition',
          isEnabled: hasClip,
          isActive: widget.isAuditioning,
          onTap: hasClip
              ? () {
                  if (widget.isAuditioning) {
                    widget.onStopAudition?.call();
                  } else {
                    // Play selection or entire clip
                    final sel = widget.selection;
                    if (sel != null && sel.isValid) {
                      widget.onAudition?.call(widget.clip!.id, sel.start, sel.end);
                    } else {
                      widget.onAudition?.call(widget.clip!.id, 0, widget.clip!.duration);
                    }
                  }
                }
              : null,
        ),
        const SizedBox(width: 8),
        Container(width: 1, height: 16, color: FluxForgeTheme.borderSubtle),
        const SizedBox(width: 8),
        // Actions
        _ToolButton(
          icon: Icons.vertical_align_center,
          label: 'Normalize',
          isEnabled: hasClip,
          onTap: hasClip
              ? () {
                  debugPrint('[ClipEditor] Normalize clicked for clip ${widget.clip!.id}');
                  widget.onNormalize?.call(widget.clip!.id);
                }
              : null,
        ),
        _ToolButton(
          icon: Icons.swap_horiz,
          label: 'Reverse',
          isEnabled: hasClip,
          onTap: hasClip
              ? () {
                  debugPrint('[ClipEditor] Reverse clicked for clip ${widget.clip!.id}');
                  widget.onReverse?.call(widget.clip!.id);
                }
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
            color: FluxForgeTheme.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            'Select a clip to edit',
            style: FluxForgeTheme.body.copyWith(color: FluxForgeTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Double-click a clip on the timeline',
            style: FluxForgeTheme.bodySmall.copyWith(color: FluxForgeTheme.textTertiary),
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
        color: FluxForgeTheme.bgSurface,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
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
        // PERFORMANCE: No setState - just update the notifier
        _hoverX = event.localPosition.dx;
      },
      onExit: (_) {
        // PERFORMANCE: No setState - just update the notifier
        _hoverX = -1;
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
                  // PERFORMANCE: Waveform in RepaintBoundary - NO hover dependency
                  // Hover line is separate layer to prevent waveform repaint on mouse move
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _WaveformPainter(
                        waveform: widget.clip!.waveform,
                        zoom: widget.zoom,
                        scrollOffset: widget.scrollOffset,
                        duration: widget.clip!.duration,
                        selection: widget.selection,
                        fadeIn: widget.clip!.fadeIn,
                        fadeOut: widget.clip!.fadeOut,
                        color: widget.clip!.color ?? FluxForgeTheme.accentBlue,
                        channels: widget.clip!.channels,
                        hoverX: -1, // Disabled - hover line is separate
                      ),
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                    ),
                  ),
                  // PERFORMANCE: Hover line as separate lightweight layer
                  ValueListenableBuilder<double>(
                    valueListenable: _hoverXNotifier,
                    builder: (context, hoverX, _) {
                      if (hoverX < 0) return const SizedBox.shrink();
                      final clipEndX = (widget.clip!.duration - widget.scrollOffset) * widget.zoom;
                      if (hoverX > clipEndX) return const SizedBox.shrink();
                      return Positioned(
                        left: hoverX,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 1,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      );
                    },
                  ),
                  // Fade handles
                  _buildFadeHandles(constraints),
                  // Hitpoints (Cubase-style transient markers)
                  if (_shouldShowHitpoints || _tool == EditorTool.hitpoint)
                    _buildHitpoints(constraints),
                  // Playhead
                  _buildPlayhead(constraints),
                  // Hover info - wrapped in ValueListenableBuilder
                  ValueListenableBuilder<double>(
                    valueListenable: _hoverXNotifier,
                    builder: (context, hoverX, _) {
                      if (hoverX >= 0 && _tool != EditorTool.fade) {
                        return _buildHoverInfoWithX(constraints, hoverX);
                      }
                      return const SizedBox.shrink();
                    },
                  ),
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
        // Curved overlay for fade in
        if (fadeInTime > 0 && fadeInWidth > 0 && clipStartX < maxW)
          Positioned(
            key: ValueKey('fadeIn_${widget.clip!.fadeInCurve}'),
            left: clipStartX.clamp(0.0, maxW).toDouble(),
            top: 0,
            bottom: 0,
            width: fadeInWidth.clamp(1.0, maxW).toDouble(),
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FadeOverlayPainter(
                  isLeft: true,
                  curve: widget.clip!.fadeInCurve,
                ),
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
                // Use widget.clip!.fadeIn to get current value, not captured fadeInTime
                final currentFadeIn = widget.clip!.fadeIn;
                final newFadeIn = (currentFadeIn + timeDelta).clamp(0.0, widget.clip!.duration / 2);
                widget.onFadeInChange?.call(widget.clip!.id, _snapTime(newFadeIn));
              },
              onDragEnd: () => setState(() => _draggingFade = _FadeHandle.none),
            ),
          ),

        // ===== FADE OUT REGION (right side) =====
        // Curved overlay for fade out
        if (fadeOutTime > 0 && fadeOutWidth > 0 && clipEndX > 0)
          Positioned(
            key: ValueKey('fadeOut_${widget.clip!.fadeOutCurve}'),
            left: (clipEndX - fadeOutWidth).clamp(0.0, maxW).toDouble(),
            top: 0,
            bottom: 0,
            width: fadeOutWidth.clamp(1.0, maxW).toDouble(),
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FadeOverlayPainter(
                  isLeft: false,
                  curve: widget.clip!.fadeOutCurve,
                ),
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
                // Use widget.clip!.fadeOut to get current value, not captured fadeOutTime
                final currentFadeOut = widget.clip!.fadeOut;
                final newFadeOut = (currentFadeOut + timeDelta).clamp(0.0, widget.clip!.duration / 2);
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

    // PERFORMANCE: RepaintBoundary isolates playhead from waveform repaints
    return Positioned(
      left: playheadX - 1,
      top: 0,
      bottom: 0,
      child: RepaintBoundary(
        child: Container(
          width: 2,
          color: FluxForgeTheme.accentRed,
        ),
      ),
    );
  }

  /// Build hitpoint markers (Cubase-style transient lines)
  Widget _buildHitpoints(BoxConstraints constraints) {
    final hitpoints = _effectiveHitpoints;
    if (hitpoints.isEmpty || widget.clip == null) {
      return const SizedBox.shrink();
    }

    final sampleRate = widget.clip!.sampleRate;
    final maxW = constraints.maxWidth;
    final maxH = constraints.maxHeight;

    return Stack(
      children: [
        for (int i = 0; i < hitpoints.length; i++)
          Builder(
            builder: (context) {
              final hp = hitpoints[i];
              final timeSeconds = hp.position / sampleRate;
              final x = (timeSeconds - widget.scrollOffset) * widget.zoom;

              // Skip if outside visible range
              if (x < -10 || x > maxW + 10) return const SizedBox.shrink();

              final isHovered = _hoveredHitpointIndex == i;
              final isDragging = _draggingHitpointIndex == i;
              final isInHitpointMode = _tool == EditorTool.hitpoint;

              return Positioned(
                left: x - 5,
                top: 0,
                bottom: 0,
                child: MouseRegion(
                  onEnter: (_) {
                    if (isInHitpointMode) {
                      setState(() => _hoveredHitpointIndex = i);
                    }
                  },
                  onExit: (_) {
                    if (_hoveredHitpointIndex == i) {
                      setState(() => _hoveredHitpointIndex = null);
                    }
                  },
                  child: GestureDetector(
                    onPanStart: isInHitpointMode && !hp.isLocked
                        ? (details) {
                            setState(() => _draggingHitpointIndex = i);
                          }
                        : null,
                    onPanUpdate: isInHitpointMode && !hp.isLocked
                        ? (details) {
                            final deltaX = details.delta.dx;
                            final deltaSamples = (deltaX / widget.zoom * sampleRate).round();
                            final newPosition = (hp.position + deltaSamples).clamp(0, (widget.clip!.duration * sampleRate).round());
                            widget.onMoveHitpoint?.call(i, newPosition);
                          }
                        : null,
                    onPanEnd: isInHitpointMode
                        ? (details) {
                            setState(() => _draggingHitpointIndex = null);
                          }
                        : null,
                    onTap: isInHitpointMode
                        ? () {
                            // Double-tap to delete (single tap does nothing for now)
                          }
                        : null,
                    onDoubleTap: isInHitpointMode && !hp.isLocked
                        ? () => widget.onDeleteHitpoint?.call(i)
                        : null,
                    child: Container(
                      width: 10,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Main line
                          Positioned(
                            left: 4.5,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              width: isDragging ? 2 : 1,
                              decoration: BoxDecoration(
                                color: hp.isManual
                                    ? FluxForgeTheme.accentCyan
                                    : (isHovered || isDragging
                                        ? FluxForgeTheme.accentOrange
                                        : FluxForgeTheme.accentOrange.withValues(alpha: 0.7)),
                                boxShadow: (isHovered || isDragging)
                                    ? [
                                        BoxShadow(
                                          color: FluxForgeTheme.accentOrange.withValues(alpha: 0.5),
                                          blurRadius: 4,
                                          spreadRadius: 1,
                                        )
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                          // Triangle marker at top
                          Positioned(
                            left: 2,
                            top: 0,
                            child: CustomPaint(
                              painter: _HitpointMarkerPainter(
                                isHovered: isHovered || isDragging,
                                isManual: hp.isManual,
                                isLocked: hp.isLocked,
                                strength: hp.strength,
                              ),
                              size: const Size(6, 8),
                            ),
                          ),
                          // Strength indicator (small bar at bottom)
                          if (hp.strength < 1.0)
                            Positioned(
                              left: 3,
                              bottom: 4,
                              child: Container(
                                width: 4,
                                height: maxH * 0.1 * hp.strength,
                                decoration: BoxDecoration(
                                  color: FluxForgeTheme.accentOrange.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildHoverInfo(BoxConstraints constraints) {
    return _buildHoverInfoWithX(constraints, _hoverX);
  }

  /// PERFORMANCE: Separate method that takes hoverX as parameter
  /// Used by ValueListenableBuilder to avoid full widget rebuild
  Widget _buildHoverInfoWithX(BoxConstraints constraints, double hoverX) {
    final time = widget.scrollOffset + hoverX / widget.zoom;
    if (time < 0 || time > widget.clip!.duration) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: hoverX + 10,
      top: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgSurface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Text(
          _formatTime(time),
          style: FluxForgeTheme.monoSmall,
        ),
      ),
    );
  }

  Widget _buildOverview() {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle),
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
            // PERFORMANCE: RepaintBoundary for overview waveform
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _OverviewPainter(
                  waveform: widget.clip!.waveform,
                  duration: widget.clip!.duration,
                  viewportStart: widget.scrollOffset,
                  viewportEnd: widget.scrollOffset + constraints.maxWidth / widget.zoom,
                  color: widget.clip!.color ?? FluxForgeTheme.accentBlue,
                  selection: widget.selection,
                ),
                size: Size(constraints.maxWidth, 40),
              ),
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
      case EditorTool.hitpoint:
        return _hoveredHitpointIndex != null
            ? SystemMouseCursors.grab
            : SystemMouseCursors.precise;
    }
  }

  void _handleWheel(PointerScrollEvent event) {
    // ══════════════════════════════════════════════════════════════════
    // DAW-STANDARD SCROLL/ZOOM (SMOOTH ANIMATED - Cubase-style)
    // ══════════════════════════════════════════════════════════════════
    final clip = widget.clip;
    if (clip == null || _containerWidth <= 0) return;

    final isZoomModifier = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShiftHeld = HardwareKeyboard.instance.isShiftPressed;

    // Minimum zoom = fit entire clip to width (no zoom out beyond this)
    final minZoom = _containerWidth / clip.duration;

    if (isZoomModifier) {
      // ════════════════════════════════════════════════════════════════
      // SMOOTH ANIMATED ZOOM TO CURSOR
      // ════════════════════════════════════════════════════════════════
      final mouseX = event.localPosition.dx;

      // Use target zoom if animating, otherwise current zoom
      final currentZoom = _isZoomAnimating ? _zoomTarget : widget.zoom;
      final currentScroll = _isZoomAnimating ? _scrollTarget : widget.scrollOffset;

      // Simple zoom factor based on scroll direction
      final zoomIn = event.scrollDelta.dy < 0;
      final zoomFactor = zoomIn ? 1.2 : 0.83; // Slightly larger for smooth feel

      final newZoom = currentZoom * zoomFactor;
      final mouseTime = currentScroll + mouseX / currentZoom;

      // Use animated zoom
      _animateZoomTo(newZoom, mouseX, mouseTime);
    } else {
      // ════════════════════════════════════════════════════════════════
      // HORIZONTAL SCROLL (only if zoomed in) - instant, no animation
      // ════════════════════════════════════════════════════════════════
      // Don't scroll if at minZoom (entire clip visible)
      if (widget.zoom <= minZoom) return;

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
    if (widget.clip == null || _containerWidth <= 0) return;

    final time = widget.scrollOffset + details.localPosition.dx / widget.zoom;
    final minZoom = _containerWidth / widget.clip!.duration;

    switch (_tool) {
      case EditorTool.cut:
        widget.onSplitAtPosition?.call(widget.clip!.id, _snapTime(time));
        break;
      case EditorTool.zoom:
        // Zoom in on click, zoom out on alt+click (but not below minZoom)
        if (HardwareKeyboard.instance.isAltPressed) {
          widget.onZoomChange?.call((widget.zoom * 0.7).clamp(minZoom, 50000));
        } else {
          widget.onZoomChange?.call((widget.zoom * 1.4).clamp(minZoom, 50000));
        }
        break;
      case EditorTool.hitpoint:
        // Click to add manual hitpoint (if not clicking on existing one)
        if (_hoveredHitpointIndex == null) {
          final samplePosition = (time * widget.clip!.sampleRate).round();
          widget.onAddHitpoint?.call(samplePosition);
        }
        break;
      default:
        // Click to set playhead
        widget.onPlayheadChange?.call(_snapTime(time.clamp(0, widget.clip!.duration)));
        break;
    }
  }

  void _handlePanStart(DragStartDetails details) {
    if (widget.clip == null) return;

    if (_tool == EditorTool.select) {
      final time = widget.scrollOffset + details.localPosition.dx / widget.zoom;
      setState(() {
        _isDragging = true;
        _dragStart = time;
      });
      widget.onSelectionChange?.call(ClipEditorSelection(start: time, end: time));
    } else if (_tool == EditorTool.slip) {
      setState(() {
        _isDragging = true;
        _dragStart = details.localPosition.dx;
      });
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!_isDragging || _dragStart == null || widget.clip == null) return;

    if (_tool == EditorTool.select) {
      final time = (widget.scrollOffset + details.localPosition.dx / widget.zoom)
          .clamp(0.0, widget.clip!.duration);

      widget.onSelectionChange?.call(ClipEditorSelection(
        start: math.min(_dragStart!, time),
        end: math.max(_dragStart!, time),
      ));
    } else if (_tool == EditorTool.slip) {
      // Slip edit: move source offset based on drag delta
      final deltaX = details.localPosition.dx - _dragStart!;
      final deltaTime = deltaX / widget.zoom;

      // Calculate new source offset
      final clip = widget.clip!;
      final maxOffset = clip.sourceDuration - clip.duration;
      final newOffset = (clip.sourceOffset - deltaTime).clamp(0.0, maxOffset > 0 ? maxOffset : 0.0);

      widget.onSlipEdit?.call(clip.id, newOffset);
      _dragStart = details.localPosition.dx; // Update for continuous drag
    }
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
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: isActive
                ? Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.4))
                : null,
          ),
          child: Center(
            child: Icon(
              icon,
              size: 16,
              color: isEnabled
                  ? (isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary)
                  : FluxForgeTheme.textTertiary.withValues(alpha: 0.5),
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
        color: FluxForgeTheme.bgDeep,
        border: Border(
          left: BorderSide(color: FluxForgeTheme.borderSubtle),
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
              const Divider(height: 24, color: FluxForgeTheme.borderSubtle),
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
            const Divider(height: 24, color: FluxForgeTheme.borderSubtle),
            _SectionHeader(title: 'Fades'),
            const SizedBox(height: 8),

            Text('Fade In', style: FluxForgeTheme.label),
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
            Text('Fade Out', style: FluxForgeTheme.label),
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
            const Divider(height: 24, color: FluxForgeTheme.borderSubtle),
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
                          ? FluxForgeTheme.accentGreen
                          : FluxForgeTheme.accentRed,
                      inactiveTrackColor: FluxForgeTheme.borderSubtle,
                      thumbColor: clip.gain >= 0
                          ? FluxForgeTheme.accentGreen
                          : FluxForgeTheme.accentRed,
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
                    style: FluxForgeTheme.monoSmall.copyWith(
                      color: clip.gain >= 0
                          ? FluxForgeTheme.accentGreen
                          : FluxForgeTheme.accentRed,
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
      style: FluxForgeTheme.h3.copyWith(
        fontSize: 11,
        color: FluxForgeTheme.textSecondary,
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
          Text(label, style: FluxForgeTheme.label),
          Text(value, style: FluxForgeTheme.monoSmall),
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
      Paint()..color = FluxForgeTheme.bgSurface,
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
          ? FluxForgeTheme.textSecondary
          : FluxForgeTheme.borderSubtle;

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
            color: FluxForgeTheme.textTertiary,
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
          color: FluxForgeTheme.accentBlue,
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
    // Calculate visible clip width (clip ends at duration)
    final clipEndX = (duration - scrollOffset) * zoom;
    final visibleClipWidth = clipEndX.clamp(0.0, size.width);

    // Background only for clip area
    canvas.drawRect(
      Rect.fromLTWH(0, 0, visibleClipWidth, size.height),
      Paint()..color = FluxForgeTheme.bgDeepest,
    );

    // Darker background for area beyond clip (if any)
    if (visibleClipWidth < size.width) {
      canvas.drawRect(
        Rect.fromLTWH(visibleClipWidth, 0, size.width - visibleClipWidth, size.height),
        Paint()..color = const Color(0xFF050508),
      );
    }

    // Grid
    _drawGrid(canvas, size);

    // Selection
    if (selection != null && selection!.isValid) {
      _drawSelection(canvas, size);
    }

    // Center line (0 dB) - only within clip
    final centerY = size.height / 2;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(visibleClipWidth, centerY),
      Paint()
        ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );

    // Waveform
    if (waveform != null && waveform!.isNotEmpty) {
      _drawWaveform(canvas, size, centerY);
    } else {
      _drawDemoWaveform(canvas, size, centerY);
    }

    // Hover line
    if (hoverX >= 0 && hoverX <= visibleClipWidth) {
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
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.15)
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
        gridPaint.color = FluxForgeTheme.borderSubtle.withValues(
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
        Paint()..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.1),
      );
      canvas.drawLine(
        Offset(0, size.height / 2 + y),
        Offset(size.width, size.height / 2 + y),
        Paint()..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.1),
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

  /// HIGH ZOOM: Sample-accurate rendering with Catmull-Rom interpolation
  /// Professional DAW style - TRUE waveform shape (not rectified)
  void _drawDetailedWaveform(Canvas canvas, Size size, double centerY, double amplitude, double samplesPerSecond) {
    // Collect min/max per pixel for true waveform
    final minValues = <double>[];
    final maxValues = <double>[];
    final envelopes = <double>[];

    for (double x = 0; x < size.width; x++) {
      final timeStart = scrollOffset + x / zoom;
      final timeEnd = scrollOffset + (x + 1) / zoom;
      if (timeEnd < 0 || timeStart > duration) {
        minValues.add(0);
        maxValues.add(0);
        envelopes.add(0);
        continue;
      }

      final startSample = (timeStart * samplesPerSecond).floor().clamp(0, waveform!.length - 1);
      final endSample = (timeEnd * samplesPerSecond).ceil().clamp(startSample + 1, waveform!.length);

      double minVal = waveform![startSample];
      double maxVal = waveform![startSample];

      for (int i = startSample; i < endSample && i < waveform!.length; i++) {
        final s = waveform![i];
        if (s < minVal) minVal = s;
        if (s > maxVal) maxVal = s;
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
      envelopes.add(envelope);
    }

    if (maxValues.isEmpty) return;

    // Build smooth waveform path with bezier
    final peakPath = Path();
    peakPath.moveTo(0, centerY - maxValues[0] * amplitude * envelopes[0]);

    for (int i = 1; i < maxValues.length; i++) {
      final prevY = centerY - maxValues[i - 1] * amplitude * envelopes[i - 1];
      final currY = centerY - maxValues[i] * amplitude * envelopes[i];
      final midX = (i - 0.5);
      final midY = (prevY + currY) / 2;
      peakPath.quadraticBezierTo((i - 1).toDouble(), prevY, midX, midY);
    }
    peakPath.lineTo((maxValues.length - 1).toDouble(), centerY - maxValues.last * amplitude * envelopes.last);

    // Connect to minValues in reverse (TRUE waveform shape)
    for (int i = minValues.length - 1; i >= 0; i--) {
      if (i > 0) {
        final currY = centerY - minValues[i] * amplitude * envelopes[i];
        final prevY = centerY - minValues[i - 1] * amplitude * envelopes[i - 1];
        final midX = (i - 0.5);
        final midY = (prevY + currY) / 2;
        peakPath.quadraticBezierTo(i.toDouble(), currY, midX, midY);
      } else {
        peakPath.lineTo(0, centerY - minValues[0] * amplitude * envelopes[0]);
      }
    }
    peakPath.close();

    // 1. Fill
    canvas.drawPath(peakPath, Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true);

    // 2. Outline
    canvas.drawPath(peakPath, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true);

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

  /// LOW ZOOM: True min/max overview - shows REAL waveform shape
  void _drawOverviewWaveform(Canvas canvas, Size size, double centerY, double amplitude, double samplesPerSecond) {
    // TRUE min/max - preserves actual waveform shape
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

    if (maxValues.isEmpty) return;

    // Build TRUE waveform path with bezier smoothing
    final peakPath = Path();
    peakPath.moveTo(0, centerY - maxValues[0] * amplitude * envelopes[0]);

    for (int i = 1; i < maxValues.length; i++) {
      final prevY = centerY - maxValues[i - 1] * amplitude * envelopes[i - 1];
      final currY = centerY - maxValues[i] * amplitude * envelopes[i];
      final midX = (i - 0.5);
      final midY = (prevY + currY) / 2;
      peakPath.quadraticBezierTo((i - 1).toDouble(), prevY, midX, midY);
    }
    peakPath.lineTo((maxValues.length - 1).toDouble(), centerY - maxValues.last * amplitude * envelopes.last);

    // Connect to minValues in reverse (negative values go BELOW center)
    for (int i = minValues.length - 1; i >= 0; i--) {
      if (i > 0) {
        final currY = centerY - minValues[i] * amplitude * envelopes[i];
        final prevY = centerY - minValues[i - 1] * amplitude * envelopes[i - 1];
        final midX = (i - 0.5);
        final midY = (prevY + currY) / 2;
        peakPath.quadraticBezierTo(i.toDouble(), currY, midX, midY);
      } else {
        peakPath.lineTo(0, centerY - minValues[0] * amplitude * envelopes[0]);
      }
    }
    peakPath.close();

    // Build RMS path (symmetric around center)
    final rmsPath = Path();
    rmsPath.moveTo(0, centerY - rmsValues[0] * amplitude * envelopes[0]);
    for (int i = 1; i < rmsValues.length; i++) {
      rmsPath.lineTo(i.toDouble(), centerY - rmsValues[i] * amplitude * envelopes[i]);
    }
    for (int i = rmsValues.length - 1; i >= 0; i--) {
      rmsPath.lineTo(i.toDouble(), centerY + rmsValues[i] * amplitude * envelopes[i]);
    }
    rmsPath.close();

    // 1. Peak envelope (transparent outer)
    canvas.drawPath(peakPath, Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true);

    // 2. RMS core (solid inner)
    canvas.drawPath(rmsPath, Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true);

    // 3. Peak outline
    canvas.drawPath(peakPath, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..isAntiAlias = true);

    // Zero line
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()..color = Colors.white.withValues(alpha: 0.1)..strokeWidth = 0.5,
    );
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
        Paint()..color = FluxForgeTheme.accentCyan.withValues(alpha: 0.15),
      );

      // Borders
      final borderPaint = Paint()
        ..color = FluxForgeTheme.accentCyan
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
            ..color = FluxForgeTheme.accentCyan
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
            ..color = FluxForgeTheme.accentCyan
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
      Paint()..color = FluxForgeTheme.bgDeep,
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
        Paint()..color = FluxForgeTheme.accentCyan.withValues(alpha: 0.2),
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
        ..color = FluxForgeTheme.accentBlue
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
  final double sourceOffset;
  final double? sourceDuration;
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
  final void Function(String clipId, double newSourceOffset)? onSlipEdit;
  final ValueChanged<double>? onPlayheadChange;

  // Audition (playback preview) - Cubase-style
  final void Function(String clipId, double startTime, double endTime)? onAudition;
  final VoidCallback? onStopAudition;
  final bool isAuditioning;

  // Hitpoint callbacks (Cubase-style sample editor)
  final List<Hitpoint> hitpoints;
  final bool showHitpoints;
  final double hitpointSensitivity;
  final HitpointAlgorithm hitpointAlgorithm;
  final double hitpointMinGapMs;
  final ValueChanged<List<Hitpoint>>? onHitpointsChange;
  final ValueChanged<bool>? onShowHitpointsChange;
  final ValueChanged<double>? onHitpointSensitivityChange;
  final ValueChanged<HitpointAlgorithm>? onHitpointAlgorithmChange;
  final VoidCallback? onDetectHitpoints;
  final void Function(String clipId, List<Hitpoint> hitpoints)? onSliceAtHitpoints;
  final void Function(int index)? onDeleteHitpoint;
  final void Function(int index, int newPosition)? onMoveHitpoint;
  final void Function(int samplePosition)? onAddHitpoint;

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
    this.sourceOffset = 0,
    this.sourceDuration,
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
    this.onSlipEdit,
    this.onPlayheadChange,
    // Audition
    this.onAudition,
    this.onStopAudition,
    this.isAuditioning = false,
    // Hitpoint defaults
    this.hitpoints = const [],
    this.showHitpoints = false,
    this.hitpointSensitivity = 0.5,
    this.hitpointAlgorithm = HitpointAlgorithm.enhanced,
    this.hitpointMinGapMs = 20.0,
    this.onHitpointsChange,
    this.onShowHitpointsChange,
    this.onHitpointSensitivityChange,
    this.onHitpointAlgorithmChange,
    this.onDetectHitpoints,
    this.onSliceAtHitpoints,
    this.onDeleteHitpoint,
    this.onMoveHitpoint,
    this.onAddHitpoint,
  });

  @override
  State<ConnectedClipEditor> createState() => _ConnectedClipEditorState();
}

class _ConnectedClipEditorState extends State<ConnectedClipEditor> {
  double? _zoom;
  double _scrollOffset = 0;
  ClipEditorSelection? _selection;
  String? _lastClipId;

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
            sourceOffset: widget.sourceOffset,
            sourceDuration: widget.sourceDuration ?? widget.clipDuration!,
          )
        : null;

    // Reset zoom when clip changes
    if (widget.selectedClipId != _lastClipId) {
      _lastClipId = widget.selectedClipId;
      _zoom = null; // Will be set to fit-to-width
      _scrollOffset = 0;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate fit-to-width zoom (sidebar is 200px)
        final waveformWidth = constraints.maxWidth - 200;
        final duration = widget.clipDuration ?? 1;
        final fitZoom = waveformWidth > 0 && duration > 0
            ? waveformWidth / duration
            : 100.0;

        // Use fit zoom if not set yet, clamp to minimum
        final effectiveZoom = (_zoom ?? fitZoom).clamp(fitZoom, 50000.0);
        // When at fit zoom, scroll must be 0 (no empty space)
        final effectiveScrollOffset = effectiveZoom <= fitZoom ? 0.0 : _scrollOffset;

        return ClipEditor(
          clip: clip,
          selection: _selection,
          zoom: effectiveZoom,
          scrollOffset: effectiveScrollOffset,
          playheadPosition: widget.playheadPosition,
          snapEnabled: widget.snapEnabled,
          snapValue: widget.snapValue,
          onSelectionChange: (sel) => setState(() => _selection = sel),
          onZoomChange: (z) => setState(() => _zoom = z.clamp(fitZoom, 50000.0)),
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
          onSlipEdit: widget.onSlipEdit,
          onPlayheadChange: widget.onPlayheadChange,
          // Audition passthrough
          onAudition: widget.onAudition,
          onStopAudition: widget.onStopAudition,
          isAuditioning: widget.isAuditioning,
          // Hitpoint passthrough
          hitpoints: widget.hitpoints,
          showHitpoints: widget.showHitpoints,
          hitpointSensitivity: widget.hitpointSensitivity,
          hitpointAlgorithm: widget.hitpointAlgorithm,
          hitpointMinGapMs: widget.hitpointMinGapMs,
          onHitpointsChange: widget.onHitpointsChange,
          onShowHitpointsChange: widget.onShowHitpointsChange,
          onHitpointSensitivityChange: widget.onHitpointSensitivityChange,
          onHitpointAlgorithmChange: widget.onHitpointAlgorithmChange,
          onDetectHitpoints: () {
            debugPrint('[ConnectedClipEditor] onDetectHitpoints wrapper called, parent callback=${widget.onDetectHitpoints != null}');
            widget.onDetectHitpoints?.call();
          },
          onSliceAtHitpoints: widget.onSliceAtHitpoints,
          onDeleteHitpoint: widget.onDeleteHitpoint,
          onMoveHitpoint: widget.onMoveHitpoint,
          onAddHitpoint: widget.onAddHitpoint,
        );
      },
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
              activeTrackColor: FluxForgeTheme.accentCyan,
              inactiveTrackColor: FluxForgeTheme.borderSubtle,
              thumbColor: FluxForgeTheme.accentCyan,
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
            style: FluxForgeTheme.monoSmall,
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
          color: FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Icon(
          icon,
          size: 14,
          color: onTap != null
              ? FluxForgeTheme.textSecondary
              : FluxForgeTheme.textTertiary,
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
        Text(label, style: FluxForgeTheme.bodySmall.copyWith(color: FluxForgeTheme.textSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FluxForgeTheme.borderSubtle),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<FadeCurve>(
                value: value,
                isDense: true,
                dropdownColor: FluxForgeTheme.bgDeep,
                style: FluxForgeTheme.monoSmall.copyWith(color: FluxForgeTheme.textPrimary),
                icon: const Icon(Icons.arrow_drop_down, size: 16, color: FluxForgeTheme.textSecondary),
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
      ..color = FluxForgeTheme.accentCyan
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
  double _lastX = 0;

  @override
  Widget build(BuildContext context) {
    const size = 20.0;
    final isActive = widget.isActive || _isHovered || _isDragging;

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      cursor: SystemMouseCursors.resizeColumn,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (mounted) setState(() => _isDragging = true);
          _lastX = event.position.dx;
          widget.onDragStart();
        },
        onPointerMove: (event) {
          if (_isDragging) {
            final delta = event.position.dx - _lastX;
            _lastX = event.position.dx;
            widget.onDragUpdate(delta);
          }
        },
        onPointerUp: (event) {
          if (_isDragging) {
            if (mounted) setState(() => _isDragging = false);
            widget.onDragEnd();
          }
        },
        onPointerCancel: (event) {
          if (_isDragging) {
            if (mounted) setState(() => _isDragging = false);
            widget.onDragEnd();
          }
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isActive
                ? FluxForgeTheme.accentCyan
                : widget.hasFade
                    ? Colors.white.withValues(alpha: 0.9)
                    : Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(3),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: FluxForgeTheme.accentCyan.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Icon(
              widget.isLeft ? Icons.chevron_right : Icons.chevron_left,
              size: 14,
              color: isActive ? Colors.white : FluxForgeTheme.bgDeepest,
            ),
          ),
        ),
      ),
    );
  }
}

// ============ Fade Overlay Painter ============

/// Paints curved fade overlay on waveform following the selected curve shape
class _FadeOverlayPainter extends CustomPainter {
  final bool isLeft;
  final FadeCurve curve;

  _FadeOverlayPainter({required this.isLeft, required this.curve});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FluxForgeTheme.accentCyan.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final path = Path();
    const steps = 40;

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

    // Draw the curve line
    final linePaint = Paint()
      ..color = FluxForgeTheme.accentCyan
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final linePath = Path();
    if (isLeft) {
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = t * size.width;
        final fadeGain = _evaluateCurve(t);
        final y = size.height * (1 - fadeGain);
        if (i == 0) {
          linePath.moveTo(x, y);
        } else {
          linePath.lineTo(x, y);
        }
      }
    } else {
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = t * size.width;
        final fadeGain = _evaluateCurve(1 - t);
        final y = size.height * (1 - fadeGain);
        if (i == 0) {
          linePath.moveTo(x, y);
        } else {
          linePath.lineTo(x, y);
        }
      }
    }
    canvas.drawPath(linePath, linePaint);
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
      oldDelegate.isLeft != isLeft || oldDelegate.curve != curve;
}

/// Hitpoint marker painter (triangle indicator)
class _HitpointMarkerPainter extends CustomPainter {
  final bool isHovered;
  final bool isManual;
  final bool isLocked;
  final double strength;

  _HitpointMarkerPainter({
    required this.isHovered,
    required this.isManual,
    required this.isLocked,
    required this.strength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final baseColor = isManual
        ? FluxForgeTheme.accentCyan
        : FluxForgeTheme.accentOrange;

    final color = isHovered
        ? baseColor
        : baseColor.withValues(alpha: 0.7 * strength.clamp(0.5, 1.0));

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Draw downward-pointing triangle
    final path = Path()
      ..moveTo(size.width / 2, size.height)  // Bottom point
      ..lineTo(0, 0)                          // Top left
      ..lineTo(size.width, 0)                 // Top right
      ..close();

    canvas.drawPath(path, paint);

    // Draw lock icon if locked
    if (isLocked) {
      final lockPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;

      final lockSize = size.width * 0.4;
      final cx = size.width / 2;
      final cy = size.height * 0.3;

      // Simple lock shape
      canvas.drawRect(
        Rect.fromCenter(center: Offset(cx, cy), width: lockSize, height: lockSize * 0.8),
        lockPaint,
      );
      canvas.drawArc(
        Rect.fromCenter(center: Offset(cx, cy - lockSize * 0.4), width: lockSize * 0.6, height: lockSize * 0.6),
        math.pi,
        math.pi,
        false,
        lockPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_HitpointMarkerPainter oldDelegate) =>
      oldDelegate.isHovered != isHovered ||
      oldDelegate.isManual != isManual ||
      oldDelegate.isLocked != isLocked ||
      oldDelegate.strength != strength;
}
