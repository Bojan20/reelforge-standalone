/// Timeline Widget
///
/// Cubase/Pro Tools style timeline with:
/// - Time ruler
/// - Track headers
/// - Track lanes with clips
/// - Playhead (draggable)
/// - Loop region
/// - Markers
/// - Zoom/scroll (Ctrl+wheel)
/// - Keyboard shortcuts
/// - Drag & drop audio files

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:provider/provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../providers/theme_mode_provider.dart';
import '../../models/timeline_models.dart';
import '../../models/comping_models.dart';
import '../../src/rust/engine_api.dart';
import '../../src/rust/native_ffi.dart';
import 'time_ruler.dart';
import 'track_header_simple.dart';
// import 'track_header_fluxforge.dart'; // Alternative: richer track headers
import 'track_lane.dart';
import 'automation_lane.dart';
import 'comping_lane.dart';

class Timeline extends StatefulWidget {
  /// Tracks
  final List<TimelineTrack> tracks;
  /// Clips on tracks
  final List<TimelineClip> clips;
  /// Markers
  final List<TimelineMarker> markers;
  /// Loop region
  final LoopRegion? loopRegion;
  /// Loop enabled
  final bool loopEnabled;
  /// Current playhead position in seconds
  final double playheadPosition;
  /// Tempo in BPM
  final double tempo;
  /// Time signature
  final int timeSignatureNum;
  final int timeSignatureDenom;
  /// Zoom level (pixels per second)
  final double zoom;
  /// Scroll offset in seconds
  final double scrollOffset;
  /// Total duration in seconds
  final double totalDuration;
  /// Time display mode
  final TimeDisplayMode timeDisplayMode;
  /// Sample rate
  final int sampleRate;

  // Callbacks
  final ValueChanged<double>? onPlayheadChange;
  final ValueChanged<double>? onPlayheadScrub;
  final void Function(String clipId, bool multiSelect)? onClipSelect;
  final void Function(String clipId, double newStartTime)? onClipMove;
  /// Move clip to a different track
  final void Function(String clipId, String targetTrackId, double newStartTime)? onClipMoveToTrack;
  /// Move clip to a NEW track (created on-the-fly)
  final void Function(String clipId, double newStartTime)? onClipMoveToNewTrack;
  final void Function(
    String clipId,
    double newStartTime,
    double newDuration,
    double? newOffset,
  )? onClipResize;
  /// Called when clip resize drag ends - for final FFI commit
  final void Function(String clipId)? onClipResizeEnd;
  final void Function(String clipId, double newSourceOffset)? onClipSlipEdit;
  final void Function(String clipId)? onClipOpenAudioEditor;
  final ValueChanged<double>? onZoomChange;
  final ValueChanged<double>? onScrollChange;
  final ValueChanged<LoopRegion?>? onLoopRegionChange;
  final VoidCallback? onLoopToggle;
  final ValueChanged<String>? onTrackMuteToggle;
  final ValueChanged<String>? onTrackSoloToggle;
  final ValueChanged<String>? onTrackSelect;
  final void Function(String clipId, double gain)? onClipGainChange;
  final void Function(String clipId, double fadeIn, double fadeOut)?
      onClipFadeChange;
  final void Function(String clipId, String newName)? onClipRename;
  final void Function(String trackId, Color color)? onTrackColorChange;
  final void Function(String trackId, OutputBus bus)? onTrackBusChange;
  final void Function(String trackId, String newName)? onTrackRename;
  final ValueChanged<String>? onTrackArmToggle;
  final ValueChanged<String>? onTrackMonitorToggle;
  final ValueChanged<String>? onTrackFreezeToggle;
  final ValueChanged<String>? onTrackLockToggle;
  final ValueChanged<String>? onTrackHideToggle;
  /// Toggle folder expanded state
  final ValueChanged<String>? onTrackFolderToggle;
  final void Function(String trackId, double volume)? onTrackVolumeChange;
  final void Function(String trackId, double pan)? onTrackPanChange;
  final ValueChanged<String>? onClipSplit;
  final ValueChanged<String>? onClipDuplicate;
  final ValueChanged<String>? onClipDelete;
  final ValueChanged<String>? onClipCopy;
  final VoidCallback? onClipPaste;
  final ValueChanged<String>? onMarkerClick;

  /// Stage markers from game engine (shown on ruler)
  final List<StageMarker> stageMarkers;
  /// Called when user clicks a stage marker
  final ValueChanged<StageMarker>? onStageMarkerClick;

  /// Transport controls
  final VoidCallback? onPlayPause;
  final VoidCallback? onStop;

  /// Undo/Redo
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  /// Crossfades
  final List<Crossfade> crossfades;
  final void Function(String crossfadeId, double duration)? onCrossfadeUpdate;
  /// Full crossfade update with startTime and duration (for left-edge resize)
  final void Function(String crossfadeId, double startTime, double duration)? onCrossfadeFullUpdate;
  final void Function(String crossfadeId)? onCrossfadeDelete;

  /// Snap settings
  final bool snapEnabled;
  final double snapValue;

  /// Transport state - is playback active
  final bool isPlaying;

  /// File drop callback
  /// Called when audio files are dropped on the timeline
  /// Returns (filePath, trackId, startTime) - trackId can be null for new track
  final void Function(String filePath, String? trackId, double startTime)? onFileDrop;

  /// Import audio files callback (Shift+Cmd+I)
  final VoidCallback? onImportAudio;

  /// Export audio callback (Alt+Cmd+E)
  final VoidCallback? onExportAudio;

  /// File operations (⌘S, ⌘⇧S, ⌘O, ⌘N)
  final VoidCallback? onSave;
  final VoidCallback? onSaveAs;
  final VoidCallback? onOpen;
  final VoidCallback? onNew;

  /// Edit operations
  final VoidCallback? onSelectAll;
  final VoidCallback? onDeselect;

  /// Add track callback (⌘T)
  final VoidCallback? onAddTrack;

  /// Pool file drop callback (for drag from Audio Pool)
  /// Called when PoolAudioFile is dropped on timeline
  /// Returns (poolFile, trackId, startTime) - trackId can be null for new track
  final void Function(dynamic poolFile, String? trackId, double startTime)? onPoolFileDrop;

  /// Track duplicate/delete callbacks
  final ValueChanged<String>? onTrackDuplicate;
  final ValueChanged<String>? onTrackDelete;
  /// Context menu callback for tracks (pass track ID and position)
  final void Function(String trackId, Offset position)? onTrackContextMenu;
  /// Currently selected track ID (controlled from parent)
  final String? selectedTrackId;

  // Automation callbacks
  /// Toggle automation lanes visibility for a track
  final ValueChanged<String>? onTrackAutomationToggle;
  /// Update automation lane data
  final void Function(String trackId, AutomationLaneData laneData)? onAutomationLaneChanged;
  /// Add automation lane to track
  final void Function(String trackId, AutomationParameter parameter)? onAddAutomationLane;
  /// Remove automation lane from track
  final void Function(String trackId, String laneId)? onRemoveAutomationLane;
  /// Track height change callback (for resizable tracks)
  final void Function(String trackId, double height)? onTrackHeightChange;

  // Comping callbacks
  /// Toggle comping lanes visibility for a track
  final ValueChanged<String>? onTrackCompingToggle;
  /// Set active comp lane
  final void Function(String trackId, int laneIndex)? onCompingLaneActivate;
  /// Toggle comp lane mute
  final void Function(String trackId, String laneId)? onCompingLaneMuteToggle;
  /// Delete comp lane
  final void Function(String trackId, String laneId)? onCompingLaneDelete;
  /// Take tap (select take)
  final void Function(String trackId, Take take)? onCompingTakeTap;
  /// Take double tap (edit take)
  final void Function(String trackId, Take take)? onCompingTakeDoubleTap;
  /// Create comp region from selection
  final void Function(String trackId, String takeId, double start, double end)? onCompRegionCreate;

  const Timeline({
    super.key,
    required this.tracks,
    required this.clips,
    this.markers = const [],
    this.loopRegion,
    this.loopEnabled = true,
    required this.playheadPosition,
    this.tempo = 120,
    this.timeSignatureNum = 4,
    this.timeSignatureDenom = 4,
    this.zoom = 50,
    this.scrollOffset = 0,
    this.totalDuration = 120,
    this.timeDisplayMode = TimeDisplayMode.bars,
    this.sampleRate = 48000,
    this.onPlayheadChange,
    this.onPlayheadScrub,
    this.onClipSelect,
    this.onClipMove,
    this.onClipMoveToTrack,
    this.onClipMoveToNewTrack,
    this.onClipResize,
    this.onClipResizeEnd,
    this.onClipSlipEdit,
    this.onClipOpenAudioEditor,
    this.onZoomChange,
    this.onScrollChange,
    this.onLoopRegionChange,
    this.onLoopToggle,
    this.onTrackMuteToggle,
    this.onTrackSoloToggle,
    this.onTrackSelect,
    this.onClipGainChange,
    this.onClipFadeChange,
    this.onClipRename,
    this.onTrackColorChange,
    this.onTrackBusChange,
    this.onTrackRename,
    this.onTrackArmToggle,
    this.onTrackMonitorToggle,
    this.onTrackFreezeToggle,
    this.onTrackLockToggle,
    this.onTrackHideToggle,
    this.onTrackFolderToggle,
    this.onTrackVolumeChange,
    this.onTrackPanChange,
    this.onClipSplit,
    this.onClipDuplicate,
    this.onClipDelete,
    this.onClipCopy,
    this.onClipPaste,
    this.onMarkerClick,
    this.stageMarkers = const [],
    this.onStageMarkerClick,
    this.onPlayPause,
    this.onStop,
    this.onUndo,
    this.onRedo,
    this.crossfades = const [],
    this.onCrossfadeUpdate,
    this.onCrossfadeFullUpdate,
    this.onCrossfadeDelete,
    this.snapEnabled = true,
    this.snapValue = 1,
    this.isPlaying = false,
    this.onFileDrop,
    this.onImportAudio,
    this.onExportAudio,
    this.onSave,
    this.onSaveAs,
    this.onOpen,
    this.onNew,
    this.onSelectAll,
    this.onDeselect,
    this.onAddTrack,
    this.onPoolFileDrop,
    this.onTrackDuplicate,
    this.onTrackDelete,
    this.onTrackContextMenu,
    this.selectedTrackId,
    this.onTrackAutomationToggle,
    this.onAutomationLaneChanged,
    this.onAddAutomationLane,
    this.onRemoveAutomationLane,
    this.onTrackHeightChange,
    // Comping callbacks
    this.onTrackCompingToggle,
    this.onCompingLaneActivate,
    this.onCompingLaneMuteToggle,
    this.onCompingLaneDelete,
    this.onCompingTakeTap,
    this.onCompingTakeDoubleTap,
    this.onCompRegionCreate,
  });

  @override
  State<Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<Timeline> with TickerProviderStateMixin {
  // Header width is now resizable (min 140, max 300)
  // Default to max width for full visibility
  double _headerWidth = 300;
  static const double _headerWidthMin = 140;
  static const double _headerWidthMax = 300;
  // Logic Pro style: taller tracks for better waveform visibility
  static const double _defaultTrackHeight = 100;
  static const double _rulerHeight = 28;

  // Selected track for highlighting (use widget.selectedTrackId if provided, else internal)
  String? _internalSelectedTrackId;

  /// Get effective selected track ID (prefer parent-controlled, fallback to internal)
  String? get _selectedTrackId => widget.selectedTrackId ?? _internalSelectedTrackId;

  // Momentum scrolling (trackpad inertia)
  late AnimationController _momentumController;
  double _scrollVelocity = 0;
  static const double _friction = 0.92; // Deceleration factor (lower = faster stop)
  static const double _velocityThreshold = 0.5; // Stop when velocity below this

  // ═══════════════════════════════════════════════════════════════════════════
  // SMOOTH ZOOM ANIMATION SYSTEM (Logic Pro X / Cubase style)
  // ═══════════════════════════════════════════════════════════════════════════
  // Smooth animated zoom with cursor anchor point tracking.
  // Key features:
  // - easeOutCubic curve for natural DAW feel
  // - Zoom anchored to cursor position (zoom-to-cursor)
  // - 120ms animation duration (fast but noticeable smoothness)
  // - Proper scroll offset compensation during animation
  // ═══════════════════════════════════════════════════════════════════════════
  late AnimationController _zoomAnimController;
  double _animatedZoom = 50.0; // Local animated zoom value
  double _zoomAnimStart = 50.0;
  double _zoomAnimTarget = 50.0;
  double _zoomAnchorTime = 0.0; // Time position to keep stable
  double _zoomAnchorPixelX = 0.0; // Pixel X of anchor from timeline left

  bool _isDraggingPlayhead = false;
  bool _isDraggingLoopLeft = false;
  bool _isDraggingLoopRight = false;
  bool _isDroppingFile = false;
  // ignore: unused_field
  bool _isDroppingPoolFile = false;
  bool _isResizingHeader = false;
  Offset? _dropPosition;
  // ignore: unused_field
  Offset? _poolDropPosition;

  // Cross-track drag state
  String? _crossTrackDraggingClipId;
  double _crossTrackDragTime = 0;
  // ignore: unused_field
  double _crossTrackDragYDelta = 0;
  int _crossTrackTargetIndex = -1;

  // Drag state (Cubase-style direct move)
  // ignore: unused_field
  int _dragSourceTrackIndex = -1;

  // Ghost preview state (visual feedback during drag)
  Offset? _ghostPosition;
  TimelineClip? _draggingClip;
  Offset _grabOffset = Offset.zero; // Where user grabbed the clip (local to clip)
  // Snap preview state
  double? _snapPreviewTime; // Time position where clip will snap to

  final FocusNode _focusNode = FocusNode();
  double _containerWidth = 800;

  // PERFORMANCE: Debounce zoom/scroll to prevent excessive setState in parent
  // This is critical because parent (engine_connected_layout) rebuilds entire UI
  // on zoom/scroll changes. We throttle to 60fps max.
  DateTime _lastZoomNotify = DateTime.now();
  DateTime _lastScrollNotify = DateTime.now();
  static const _debounceMs = 16; // ~60fps max
  double _pendingZoom = 0;
  double _pendingScroll = 0;
  bool _hasPendingZoom = false;
  bool _hasPendingScroll = false;

  /// Supported audio file extensions
  static const _audioExtensions = {'.wav', '.mp3', '.flac', '.ogg', '.aiff', '.aif'};

  @override
  void initState() {
    super.initState();
    // Momentum scrolling controller
    _momentumController = AnimationController.unbounded(vsync: this)
      ..addListener(_applyMomentum);

    // Smooth zoom animation controller (30ms for instant response)
    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 30),
    )..addListener(_onZoomAnimationTick);
    _animatedZoom = widget.zoom;

    // Auto-focus after first frame to enable keyboard shortcuts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(Timeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync animated zoom with widget.zoom when changed externally
    // (e.g., from zoom slider, but NOT during our animation)
    if (!_zoomAnimController.isAnimating && widget.zoom != oldWidget.zoom) {
      _animatedZoom = widget.zoom;
    }
  }

  @override
  void dispose() {
    _zoomAnimController.dispose();
    _momentumController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Apply momentum scrolling (called every frame during inertia)
  void _applyMomentum() {
    if (_scrollVelocity.abs() < _velocityThreshold) {
      _momentumController.stop();
      _scrollVelocity = 0;
      return;
    }

    // Apply friction
    _scrollVelocity *= _friction;

    // Calculate scroll delta in seconds
    final scrollSeconds = _scrollVelocity / widget.zoom;

    final maxOffset = (widget.totalDuration - _containerWidth / widget.zoom)
        .clamp(0.0, double.infinity);
    final newOffset = (widget.scrollOffset + scrollSeconds).clamp(0.0, maxOffset);

    _notifyScrollChange(newOffset);
  }

  /// Start momentum scrolling with initial velocity
  void _startMomentum(double velocity) {
    _scrollVelocity = velocity;
    if (velocity.abs() > _velocityThreshold) {
      // For unbounded controller, use animateTo with large target instead of repeat
      // This avoids the "no default Duration" error with repeat()
      _momentumController.stop();
      _momentumController.value = 0;
      _momentumController.animateTo(
        1000000, // Large target - will be stopped by friction before reaching
        duration: const Duration(seconds: 1000), // Long duration, friction stops it
      );
    }
  }

  /// Stop any ongoing momentum
  void _stopMomentum() {
    _momentumController.stop();
    _scrollVelocity = 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SMOOTH ZOOM ANIMATION METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Called on each animation frame during zoom animation
  void _onZoomAnimationTick() {
    // Interpolate using easeOutCubic curve
    final t = Curves.easeOutCubic.transform(_zoomAnimController.value);
    final newZoom = _zoomAnimStart + (_zoomAnimTarget - _zoomAnimStart) * t;

    // Update animated zoom locally (triggers repaint)
    setState(() {
      _animatedZoom = newZoom;
    });

    // Calculate new scroll offset to keep anchor point stable (zoom-to-cursor)
    if (_zoomAnchorPixelX > 0) {
      final newScrollOffset = _zoomAnchorTime - _zoomAnchorPixelX / newZoom;
      // Notify scroll on each frame for smooth scrolling
      _notifyScrollChange(newScrollOffset.clamp(0.0, double.infinity));
    }

    // Only notify parent of FINAL zoom value when animation completes
    // This prevents feedback loop and unnecessary parent rebuilds during animation
    if (_zoomAnimController.isCompleted) {
      _notifyZoomChange(_zoomAnimTarget);
    }
  }

  /// Start smooth zoom animation to target zoom level
  /// [targetZoom] - Target zoom in pixels per second
  /// [anchorPixelX] - Pixel X position from timeline left to keep stable (cursor position)
  void _animateZoomTo(double targetZoom, double anchorPixelX) {
    // Clamp to valid range
    targetZoom = targetZoom.clamp(0.1, 5000.0);

    // Store animation parameters
    _zoomAnimStart = _animatedZoom;
    _zoomAnimTarget = targetZoom;

    // Calculate anchor time (time position at anchor pixel)
    _zoomAnchorPixelX = anchorPixelX;
    _zoomAnchorTime = widget.scrollOffset + anchorPixelX / _animatedZoom;

    // Start animation from beginning
    _zoomAnimController.forward(from: 0.0);
  }

  /// Get effective zoom value (animated local value during animation, widget value otherwise)
  double get _effectiveZoom => _zoomAnimController.isAnimating ? _animatedZoom : widget.zoom;

  /// PERFORMANCE: Debounced zoom change notification
  /// Coalesces rapid zoom events to prevent parent rebuild storm
  void _notifyZoomChange(double newZoom) {
    _pendingZoom = newZoom;
    _hasPendingZoom = true;

    final now = DateTime.now();
    if (now.difference(_lastZoomNotify).inMilliseconds >= _debounceMs) {
      _lastZoomNotify = now;
      _hasPendingZoom = false;
      widget.onZoomChange?.call(newZoom);  // FIXED: was recursive call
    } else {
      // Schedule deferred notification
      Future.delayed(Duration(milliseconds: _debounceMs), () {
        if (_hasPendingZoom) {
          _hasPendingZoom = false;
          _lastZoomNotify = DateTime.now();
          widget.onZoomChange?.call(_pendingZoom);  // FIXED: was recursive call
        }
      });
    }
  }

  /// PERFORMANCE: Debounced scroll change notification
  void _notifyScrollChange(double newScroll) {
    _pendingScroll = newScroll;
    _hasPendingScroll = true;

    final now = DateTime.now();
    if (now.difference(_lastScrollNotify).inMilliseconds >= _debounceMs) {
      _lastScrollNotify = now;
      _hasPendingScroll = false;
      widget.onScrollChange?.call(newScroll);  // FIXED: was recursive call
    } else {
      // Schedule deferred notification
      Future.delayed(Duration(milliseconds: _debounceMs), () {
        if (_hasPendingScroll) {
          _hasPendingScroll = false;
          _lastScrollNotify = DateTime.now();
          widget.onScrollChange?.call(_pendingScroll);  // FIXED: was recursive call
        }
      });
    }
  }

  double get _playheadX => (widget.playheadPosition - widget.scrollOffset) * _effectiveZoom;

  /// Get visible tracks (filter out hidden)
  List<TimelineTrack> get _visibleTracks =>
      widget.tracks.where((t) => !t.hidden).toList();

  /// Get the end time of the last clip (actual content end)
  /// Adds extra space after content for Cubase-style scrolling (4 bars padding)
  double get _contentEndTime {
    if (widget.clips.isEmpty) return 0;
    double maxEnd = 0;
    for (final clip in widget.clips) {
      final clipEnd = clip.startTime + clip.duration;
      if (clipEnd > maxEnd) maxEnd = clipEnd;
    }
    // Add 4 bars of padding after last clip (Cubase style)
    // At 120 BPM, 4/4 time: 4 bars = 8 seconds
    final beatsPerBar = widget.timeSignatureNum;
    final secondsPerBeat = 60.0 / widget.tempo;
    final barsOfPadding = 4;
    final paddingSeconds = barsOfPadding * beatsPerBar * secondsPerBeat;
    return maxEnd + paddingSeconds;
  }

  /// Check if scrolling is needed (content extends beyond visible area)
  bool get _canScroll {
    if (_containerWidth <= 0) return false;
    final visibleDuration = _containerWidth / _effectiveZoom;
    // Allow scroll only if content end is beyond visible area
    return _contentEndTime > visibleDuration;
  }

  Map<String, List<TimelineClip>> get _clipsByTrack {
    final map = <String, List<TimelineClip>>{};
    for (final track in widget.tracks) {
      map[track.id] = [];
    }
    for (final clip in widget.clips) {
      map[clip.trackId]?.add(clip);
    }
    return map;
  }

  Map<String, List<Crossfade>> get _crossfadesByTrack {
    final map = <String, List<Crossfade>>{};
    for (final track in widget.tracks) {
      map[track.id] = [];
    }
    for (final xfade in widget.crossfades) {
      map[xfade.trackId]?.add(xfade);
    }
    return map;
  }

  /// Build resize handle for header width
  Widget _buildHeaderResizeHandle() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragStart: (_) {
          setState(() => _isResizingHeader = true);
        },
        onHorizontalDragUpdate: (details) {
          setState(() {
            _headerWidth = (_headerWidth + details.delta.dx)
                .clamp(_headerWidthMin, _headerWidthMax);
          });
        },
        onHorizontalDragEnd: (_) {
          setState(() => _isResizingHeader = false);
        },
        child: Container(
          width: 4,
          color: _isResizingHeader
              ? FluxForgeTheme.accentBlue
              : FluxForgeTheme.borderMedium,
        ),
      ),
    );
  }

  void _handleWheel(PointerScrollEvent event) {
    // INSTANT RESPONSE: No throttle - Flutter batches renders per frame
    // ══════════════════════════════════════════════════════════════════
    // DAW-STANDARD SCROLL/ZOOM (Cubase/Logic/Pro Tools/Ableton style)
    // ══════════════════════════════════════════════════════════════════
    //
    // SCROLL:
    //   - Wheel up/down      = Horizontal scroll
    //   - Shift + Wheel      = Faster horizontal scroll
    //   - Two-finger swipe   = Horizontal scroll (trackpad)
    //
    // ZOOM:
    //   - Cmd/Ctrl + Wheel   = Zoom to cursor
    //
    // ══════════════════════════════════════════════════════════════════

    final isZoomModifier = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShiftHeld = HardwareKeyboard.instance.isShiftPressed;

    if (isZoomModifier) {
      // ════════════════════════════════════════════════════════════════
      // SMOOTH ZOOM TO CURSOR (Logic Pro X / Cubase style)
      // ════════════════════════════════════════════════════════════════
      // Animated zoom with easeOutCubic curve for professional DAW feel.
      // Zoom anchored to cursor position for intuitive zoom-to-cursor.
      final mouseX = event.localPosition.dx - _headerWidth;

      // Accumulative zoom factor - chain zoom events during animation
      // Aggressive 35% per step for fast, responsive zooming
      final zoomIn = event.scrollDelta.dy < 0;
      final zoomFactor = zoomIn ? 1.35 : 0.74;

      // If animation is running, use current animated zoom as base
      // This allows smooth chained zooming during continuous scroll
      final currentZoom = _zoomAnimController.isAnimating ? _zoomAnimTarget : _animatedZoom;
      final newZoom = (currentZoom * zoomFactor).clamp(0.1, 5000.0);

      if (mouseX > 0 && _containerWidth > 0) {
        // SMOOTH ANIMATED ZOOM TO CURSOR
        // Store new target and restart/continue animation
        _zoomAnimTarget = newZoom;

        if (!_zoomAnimController.isAnimating) {
          // Start new animation
          _animateZoomTo(newZoom, mouseX);
        } else {
          // Update target for running animation (chained zooming)
          // Animation tick will interpolate to new target
        }
      } else {
        // Mouse over header - zoom from center
        _animateZoomTo(newZoom, _containerWidth / 2);
      }
    } else {
      // ════════════════════════════════════════════════════════════════
      // HORIZONTAL SCROLL ONLY (ignore vertical)
      // ════════════════════════════════════════════════════════════════
      // Timeline scrolls ONLY horizontally:
      // - Mouse wheel vertical (dy) → horizontal scroll
      // - Trackpad horizontal swipe (dx) → horizontal scroll
      // - Trackpad vertical swipe → IGNORED (no vertical scroll on timeline)

      // Cubase-style: no scroll if all content fits in visible area
      if (!_canScroll) {
        return;
      }

      // Calculate max scroll based on content end (not total project duration)
      final maxOffset = (_contentEndTime - _containerWidth / widget.zoom)
          .clamp(0.0, double.infinity);

      final dx = event.scrollDelta.dx;
      final dy = event.scrollDelta.dy;

      // ONLY use horizontal delta (dx) for trackpad horizontal swipe
      // Vertical scroll (dy) from mouse wheel also scrolls horizontally
      // But pure vertical trackpad swipe is IGNORED
      double rawDelta;
      if (dx.abs() > 1.0) {
        // Trackpad horizontal swipe - use it
        rawDelta = dx;
      } else if (dy.abs() > 1.0 && dx.abs() < 0.5) {
        // Pure vertical scroll (mouse wheel) - convert to horizontal
        rawDelta = dy;
      } else {
        // Ignore small movements / diagonal gestures
        return;
      }

      // Stop any existing momentum
      _stopMomentum();

      // Speed multiplier: 2.5x base speed, Shift = 4x faster
      final speedMultiplier = isShiftHeld ? 10.0 : 2.5;

      // Scroll amount in seconds (scale by zoom for consistent feel)
      final scrollSeconds = (rawDelta / widget.zoom) * speedMultiplier;

      final newOffset = (widget.scrollOffset + scrollSeconds).clamp(0.0, maxOffset);

      _notifyScrollChange(newOffset);
    }
  }

  // Track velocity for momentum scrolling
  double _lastPanVelocity = 0;
  DateTime _lastPanTime = DateTime.now();

  /// Handle macOS trackpad two-finger pan gesture with momentum
  void _handleTrackpadPan(PointerPanZoomUpdateEvent event) {
    final panDelta = event.panDelta;

    // ONLY horizontal pan scrolls timeline (ignore vertical)
    if (panDelta.dx.abs() < 0.5) return;

    // Cubase-style: no scroll if all content fits in visible area
    if (!_canScroll) {
      return;
    }

    // Calculate max scroll based on content end
    final maxOffset = (_contentEndTime - _containerWidth / widget.zoom)
        .clamp(0.0, double.infinity);

    // Stop previous momentum
    _stopMomentum();

    // Calculate velocity for momentum (pixels per frame)
    final now = DateTime.now();
    final dt = now.difference(_lastPanTime).inMilliseconds;
    _lastPanTime = now;

    // Track velocity for momentum when gesture ends
    if (dt > 0 && dt < 100) {
      // Average with previous to smooth out
      _lastPanVelocity = (_lastPanVelocity * 0.3) + (-panDelta.dx * 0.7);
    } else {
      _lastPanVelocity = -panDelta.dx;
    }

    // Speed multiplier for faster scrolling
    const speedMultiplier = 3.0;
    final scrollSeconds = -panDelta.dx * speedMultiplier / widget.zoom;

    final newOffset = (widget.scrollOffset + scrollSeconds).clamp(0.0, maxOffset);

    _notifyScrollChange(newOffset);
  }

  /// Handle trackpad gesture end - start momentum
  void _handleTrackpadEnd(PointerPanZoomEndEvent event) {
    // Start momentum with accumulated velocity
    if (_lastPanVelocity.abs() > 2.0) {
      // Amplify velocity for smoother momentum
      _startMomentum(_lastPanVelocity * 3.0);
    }
    _lastPanVelocity = 0;
  }

  void _handleTimelineClick(TapDownDetails details) {
    // Request focus for keyboard shortcuts (G, H, L, etc.)
    _focusNode.requestFocus();
    // Playhead only moves when clicking ON clips, not empty space
  }

  void _handlePlayheadDrag(DragUpdateDetails details) {
    final x = details.localPosition.dx - _headerWidth;
    final time = (widget.scrollOffset + x.clamp(0, double.infinity) / widget.zoom)
        .clamp(0.0, widget.totalDuration);

    if (widget.onPlayheadScrub != null) {
      widget.onPlayheadScrub!(time);
    } else {
      widget.onPlayheadChange?.call(time);
    }
  }

  void _handleLoopDrag(DragUpdateDetails details, bool isLeft) {
    if (widget.loopRegion == null) return;

    final x = details.localPosition.dx - _headerWidth;
    var time = (widget.scrollOffset + x / widget.zoom).clamp(0.0, widget.totalDuration);

    if (isLeft) {
      // Clamp first to valid range
      var newStart = time.clamp(0.0, widget.loopRegion!.end - 0.1);
      // Snap to grid if enabled (after clamp)
      if (widget.snapEnabled && widget.snapValue > 0) {
        newStart = snapToGrid(newStart, widget.snapValue, widget.tempo);
        // Re-clamp after snap to ensure validity
        newStart = newStart.clamp(0.0, widget.loopRegion!.end - 0.05);
      }
      widget.onLoopRegionChange?.call(
        LoopRegion(start: newStart, end: widget.loopRegion!.end),
      );
    } else {
      // Clamp first to valid range
      var newEnd = time.clamp(widget.loopRegion!.start + 0.1, widget.totalDuration);
      // Snap to grid if enabled (after clamp)
      if (widget.snapEnabled && widget.snapValue > 0) {
        newEnd = snapToGrid(newEnd, widget.snapValue, widget.tempo);
        // Re-clamp after snap to ensure validity
        newEnd = newEnd.clamp(widget.loopRegion!.start + 0.05, widget.totalDuration);
      }
      widget.onLoopRegionChange?.call(
        LoopRegion(start: widget.loopRegion!.start, end: newEnd),
      );
    }
  }

  /// Handle file drop on timeline
  void _handleFileDrop(DropDoneDetails details) {
    // Always clear drop state first (fixes ghost staying visible)
    setState(() {
      _isDroppingFile = false;
      _dropPosition = null;
    });

    if (widget.onFileDrop == null) return;

    final position = details.localPosition;

    // Calculate time from X position
    final x = position.dx - _headerWidth;
    final startTime = (widget.scrollOffset + x / widget.zoom).clamp(0.0, widget.totalDuration);

    // Calculate track from Y position
    final trackIndex = ((position.dy - _rulerHeight) / _defaultTrackHeight).floor();
    String? trackId;
    if (trackIndex >= 0 && trackIndex < widget.tracks.length) {
      trackId = widget.tracks[trackIndex].id;
    }

    // Process dropped files
    for (final file in details.files) {
      final path = file.path;
      final extension = path.toLowerCase().split('.').lastOrNull;

      if (extension != null && _audioExtensions.contains('.$extension')) {
        widget.onFileDrop!(path, trackId, startTime);
      }
    }
  }

  /// Check if any file is an audio file
  // ignore: unused_element
  bool _hasAudioFiles(List<XFile> files) {
    return files.any((file) {
      final ext = file.path.toLowerCase().split('.').lastOrNull;
      return ext != null && _audioExtensions.contains('.$ext');
    });
  }

  /// Format drop position as time string
  String _formatDropTime(double x) {
    final time = (widget.scrollOffset + (x - _headerWidth) / widget.zoom).clamp(0.0, widget.totalDuration);
    final minutes = (time / 60).floor();
    final seconds = (time % 60).floor();
    final ms = ((time % 1) * 1000).floor();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
  }

  /// Format snap time for badge display (compact format)
  String _formatSnapTime(double time) {
    final minutes = (time / 60).floor();
    final seconds = (time % 60).floor();
    final frames = ((time % 1) * 100).floor(); // Frames at 100fps resolution
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${frames.toString().padLeft(2, '0')}';
  }

  /// Handle pool file drop on timeline (drag from Audio Pool)
  void _handlePoolFileDrop(dynamic poolFile, Offset globalPosition) {
    if (widget.onPoolFileDrop == null) return;

    // Convert global position to local position within this widget
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPosition = renderBox.globalToLocal(globalPosition);

    // Calculate time from X position (local)
    final x = localPosition.dx - _headerWidth;
    final startTime = (widget.scrollOffset + x / widget.zoom).clamp(0.0, widget.totalDuration);

    // Calculate track from Y position (local)
    // Account for ruler height (no vertical scroll in this timeline implementation)
    final yInContent = localPosition.dy - _rulerHeight;
    final trackIndex = (yInContent / _defaultTrackHeight).floor();

    String? trackId;
    // Only assign trackId if dropping ON an existing track
    // If dropping below all tracks OR on empty space → trackId remains null → new track created
    if (trackIndex >= 0 && trackIndex < widget.tracks.length && yInContent >= 0) {
      trackId = widget.tracks[trackIndex].id;
    }
    // trackId == null means: create new track (Cubase-style behavior)

    debugPrint('[Timeline] Pool drop: global=$globalPosition, local=$localPosition, trackIndex=$trackIndex, trackId=$trackId');

    widget.onPoolFileDrop!(poolFile, trackId, startTime);

    setState(() {
      _isDroppingPoolFile = false;
      _poolDropPosition = null;
    });
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    debugPrint('[Timeline] Key event: ${event.logicalKey.keyLabel} (${event.runtimeType})');

    // Keys that allow repeat (hold key for continuous adjustment)
    final isZoomKey = event.logicalKey == LogicalKeyboardKey.keyG ||
        event.logicalKey == LogicalKeyboardKey.keyH;
    final isFadeKey = event.logicalKey == LogicalKeyboardKey.bracketLeft ||
        event.logicalKey == LogicalKeyboardKey.bracketRight;
    final isArrowKey = event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown;

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    // Only allow repeat for zoom, fade, and arrow keys
    if (event is KeyRepeatEvent && !isZoomKey && !isFadeKey && !isArrowKey) return KeyEventResult.ignored;

    // Check for modifiers
    final isCmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    final selectedClip = widget.clips.cast<TimelineClip?>().firstWhere(
      (c) => c?.selected == true,
      orElse: () => null,
    );

    // ═══════════════════════════════════════════════════════════════════════
    // FILE SHORTCUTS (Cmd + key)
    // ═══════════════════════════════════════════════════════════════════════

    // Cmd+S - Save
    if (isCmd && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyS) {
      debugPrint('[Timeline] Cmd+S detected, calling onSave');
      widget.onSave?.call();
      return KeyEventResult.handled;
    }

    // Cmd+Shift+S - Save As
    if (isCmd && isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyS) {
      debugPrint('[Timeline] Cmd+Shift+S detected, calling onSaveAs');
      widget.onSaveAs?.call();
      return KeyEventResult.handled;
    }

    // Cmd+O - Open
    if (isCmd && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyO) {
      debugPrint('[Timeline] Cmd+O detected, calling onOpen');
      widget.onOpen?.call();
      return KeyEventResult.handled;
    }

    // Cmd+N - New
    if (isCmd && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyN) {
      debugPrint('[Timeline] Cmd+N detected, calling onNew');
      widget.onNew?.call();
      return KeyEventResult.handled;
    }

    // Cmd+Shift+I - Import Audio Files
    if (isCmd && isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyI) {
      debugPrint('[Timeline] Cmd+Shift+I detected, calling onImportAudio');
      widget.onImportAudio?.call();
      return KeyEventResult.handled;
    }

    // Alt+Cmd+E - Export Audio
    if (isCmd && isAlt && !isShift && event.logicalKey == LogicalKeyboardKey.keyE) {
      debugPrint('[Timeline] Alt+Cmd+E detected, calling onExportAudio');
      widget.onExportAudio?.call();
      return KeyEventResult.handled;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EDIT SHORTCUTS (Cmd + key)
    // ═══════════════════════════════════════════════════════════════════════

    // Cmd+Z - Undo
    if (isCmd && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyZ) {
      debugPrint('[Timeline] Cmd+Z detected, calling onUndo');
      widget.onUndo?.call();
      return KeyEventResult.handled;
    }

    // Cmd+Shift+Z - Redo
    if (isCmd && isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyZ) {
      debugPrint('[Timeline] Cmd+Shift+Z detected, calling onRedo');
      widget.onRedo?.call();
      return KeyEventResult.handled;
    }

    // Cmd+Y - Redo (Windows style)
    if (isCmd && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyY) {
      debugPrint('[Timeline] Cmd+Y detected, calling onRedo');
      widget.onRedo?.call();
      return KeyEventResult.handled;
    }

    // Cmd+A - Select All
    if (isCmd && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyA) {
      debugPrint('[Timeline] Cmd+A detected, calling onSelectAll');
      widget.onSelectAll?.call();
      return KeyEventResult.handled;
    }

    // Cmd+C - Copy
    if (isCmd && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyC) {
      if (selectedClip != null) {
        debugPrint('[Timeline] Cmd+C detected, calling onClipCopy');
        widget.onClipCopy?.call(selectedClip.id);
        return KeyEventResult.handled;
      }
    }

    // Cmd+V - Paste
    if (isCmd && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyV) {
      debugPrint('[Timeline] Cmd+V detected, calling onClipPaste');
      widget.onClipPaste?.call();
      return KeyEventResult.handled;
    }

    // Cmd+D - Duplicate
    if (isCmd && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyD) {
      if (selectedClip != null) {
        debugPrint('[Timeline] Cmd+D detected, calling onClipDuplicate');
        widget.onClipDuplicate?.call(selectedClip.id);
        return KeyEventResult.handled;
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TRACK SHORTCUTS (Cmd + key)
    // ═══════════════════════════════════════════════════════════════════════

    // Cmd+T - Add Track
    if (isCmd && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyT) {
      debugPrint('[Timeline] Cmd+T detected, calling onAddTrack');
      widget.onAddTrack?.call();
      return KeyEventResult.handled;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SIMPLE KEY SHORTCUTS (no modifiers)
    // ═══════════════════════════════════════════════════════════════════════

    // SPACE - Play/Pause
    if (!isCmd && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.space) {
      debugPrint('[Timeline] Space detected, calling onPlayPause');
      widget.onPlayPause?.call();
      return KeyEventResult.handled;
    }

    // Escape - Deselect
    if (!isCmd && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.escape) {
      debugPrint('[Timeline] Escape detected, calling onDeselect');
      widget.onDeselect?.call();
      return KeyEventResult.handled;
    }

    // Delete/Backspace - Delete selected clip
    if (!isCmd && (event.logicalKey == LogicalKeyboardKey.delete ||
            event.logicalKey == LogicalKeyboardKey.backspace)) {
      if (selectedClip != null) {
        debugPrint('[Timeline] Delete detected, calling onClipDelete');
        widget.onClipDelete?.call(selectedClip.id);
        return KeyEventResult.handled;
      }
    }

    // S key (no modifiers) - Split clip at playhead
    if (!isCmd && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyS) {
      if (selectedClip != null && widget.onClipSplit != null) {
        if (widget.playheadPosition > selectedClip.startTime &&
            widget.playheadPosition < selectedClip.endTime) {
          debugPrint('[Timeline] S detected, calling onClipSplit');
          widget.onClipSplit!(selectedClip.id);
          return KeyEventResult.handled;
        }
      }
    }

    // M key - Mute selected track
    if (!isCmd && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyM) {
      if (_selectedTrackId != null && widget.onTrackMuteToggle != null) {
        debugPrint('[Timeline] M detected, calling onTrackMuteToggle');
        widget.onTrackMuteToggle!(_selectedTrackId!);
        return KeyEventResult.handled;
      }
    }

    // Alt+S - Solo selected track
    if (!isCmd && !isShift && isAlt && event.logicalKey == LogicalKeyboardKey.keyS) {
      if (_selectedTrackId != null && widget.onTrackSoloToggle != null) {
        debugPrint('[Timeline] Alt+S detected, calling onTrackSoloToggle');
        widget.onTrackSoloToggle!(_selectedTrackId!);
        return KeyEventResult.handled;
      }
    }

    // G - Zoom out centered on PLAYHEAD (aggressive 30% per keypress)
    if (!isCmd && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyG) {
      final playheadTime = widget.playheadPosition;
      final playheadX = (playheadTime - widget.scrollOffset) * widget.zoom;
      final newZoom = (widget.zoom * 0.70).clamp(0.1, 5000.0);
      final newScrollOffset = playheadTime - playheadX / newZoom;
      _notifyZoomChange(newZoom);
      _notifyScrollChange(newScrollOffset.clamp(0.0,
          (widget.totalDuration - _containerWidth / newZoom).clamp(0.0, double.infinity)));
      return KeyEventResult.handled;
    }

    // H - Zoom in centered on PLAYHEAD (aggressive 40% per keypress)
    if (!isCmd && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyH) {
      final playheadTime = widget.playheadPosition;
      final playheadX = (playheadTime - widget.scrollOffset) * widget.zoom;
      final newZoom = (widget.zoom * 1.40).clamp(0.1, 5000.0);
      final newScrollOffset = playheadTime - playheadX / newZoom;
      _notifyZoomChange(newZoom);
      _notifyScrollChange(newScrollOffset.clamp(0.0,
          (widget.totalDuration - _containerWidth / newZoom).clamp(0.0, double.infinity)));
      return KeyEventResult.handled;
    }

    // L - Set loop region around selected clip AND toggle loop on/off
    if (!isCmd && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyL) {
      if (selectedClip != null) {
        // Set loop region around selected clip
        if (widget.onLoopRegionChange != null) {
          widget.onLoopRegionChange!(LoopRegion(
            start: selectedClip.startTime,
            end: selectedClip.endTime,
          ));
        }
        // Toggle loop enabled
        widget.onLoopToggle?.call();
      } else {
        // No clip selected - just toggle loop on/off
        widget.onLoopToggle?.call();
      }
      return KeyEventResult.handled;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ARROW KEYS
    // ═══════════════════════════════════════════════════════════════════════

    // ↑/↓ Arrow keys - navigate between tracks
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final visibleTracks = _visibleTracks;
      if (visibleTracks.isEmpty) return KeyEventResult.ignored;

      // Find current track index
      int currentIndex = -1;
      if (_selectedTrackId != null) {
        currentIndex = visibleTracks.indexWhere((t) => t.id == _selectedTrackId);
      }

      int newIndex;
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        // Go to previous track (or last if at top/none selected)
        newIndex = currentIndex <= 0 ? visibleTracks.length - 1 : currentIndex - 1;
      } else {
        // Go to next track (or first if at bottom/none selected)
        newIndex = currentIndex >= visibleTracks.length - 1 ? 0 : currentIndex + 1;
      }

      final newTrack = visibleTracks[newIndex];
      setState(() => _internalSelectedTrackId = newTrack.id);
      widget.onTrackSelect?.call(newTrack.id);
      return KeyEventResult.handled;
    }

    // ←/→ Arrow keys - move playhead OR nudge clip (with Alt)
    final isHorizontalArrow = event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowRight;

    if (isHorizontalArrow) {
      final beatsPerSecond = widget.tempo / 60;

      // Alt+Arrow = nudge selected clip
      if (isAlt && selectedClip != null && widget.onClipMove != null) {
        final nudgeAmount = isShift
            ? 1 / beatsPerSecond  // 1 beat
            : 0.25 / beatsPerSecond;  // 1/4 beat

        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          final newTime = (selectedClip.startTime - nudgeAmount).clamp(0.0, double.infinity);
          widget.onClipMove!(selectedClip.id, newTime);
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          widget.onClipMove!(selectedClip.id, selectedClip.startTime + nudgeAmount);
        }
        return KeyEventResult.handled;
      }

      // Arrow without Alt = move playhead (Cubase-style)
      final playheadNudge = isShift
          ? 1 / beatsPerSecond  // 1 beat with Shift
          : 0.25 / beatsPerSecond;  // 1/4 beat normal

      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        final newPos = (widget.playheadPosition - playheadNudge).clamp(0.0, widget.totalDuration);
        widget.onPlayheadChange?.call(newPos);
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        final newPos = (widget.playheadPosition + playheadNudge).clamp(0.0, widget.totalDuration);
        widget.onPlayheadChange?.call(newPos);
      }
      return KeyEventResult.handled;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FADE KEYS ([ and ])
    // ═══════════════════════════════════════════════════════════════════════

    // [ and ] keys - fade nudge (Pro Tools style)
    if (selectedClip != null && widget.onClipFadeChange != null) {
      final fadeNudgeAmount = isShift
          ? 0.01  // 10ms fine control
          : 0.05; // 50ms normal

      // [ key - decrease fade in OR increase fade out (with Alt)
      if (event.logicalKey == LogicalKeyboardKey.bracketLeft) {
        if (isAlt) {
          // Alt+[ = increase fade out
          final newFadeOut = (selectedClip.fadeOut + fadeNudgeAmount)
              .clamp(0.0, selectedClip.duration * 0.5);
          widget.onClipFadeChange!(selectedClip.id, selectedClip.fadeIn, newFadeOut);
        } else {
          // [ = decrease fade in
          final newFadeIn = (selectedClip.fadeIn - fadeNudgeAmount)
              .clamp(0.0, selectedClip.duration * 0.5);
          widget.onClipFadeChange!(selectedClip.id, newFadeIn, selectedClip.fadeOut);
        }
        return KeyEventResult.handled;
      }

      // ] key - increase fade in OR decrease fade out (with Alt)
      if (event.logicalKey == LogicalKeyboardKey.bracketRight) {
        if (isAlt) {
          // Alt+] = decrease fade out
          final newFadeOut = (selectedClip.fadeOut - fadeNudgeAmount)
              .clamp(0.0, selectedClip.duration * 0.5);
          widget.onClipFadeChange!(selectedClip.id, selectedClip.fadeIn, newFadeOut);
        } else {
          // ] = increase fade in
          final newFadeIn = (selectedClip.fadeIn + fadeNudgeAmount)
              .clamp(0.0, selectedClip.duration * 0.5);
          widget.onClipFadeChange!(selectedClip.id, newFadeIn, selectedClip.fadeOut);
        }
        return KeyEventResult.handled;
      }
    }

    // Key not handled - let it propagate
    return KeyEventResult.ignored;
  }

  /// Handle cross-track drag update
  void _handleCrossTrackDrag(String clipId, double newStartTime, double verticalDelta, int sourceTrackIndex) {
    // Calculate target track index based on vertical delta
    // Allow tracks.length as valid target (means: create new track below)
    final tracksDelta = (verticalDelta / _defaultTrackHeight).round();
    final targetIndex = (sourceTrackIndex + tracksDelta).clamp(0, widget.tracks.length);

    setState(() {
      _crossTrackDraggingClipId = clipId;
      _crossTrackDragTime = newStartTime;
      _crossTrackDragYDelta = verticalDelta;
      _crossTrackTargetIndex = targetIndex;
    });
  }

  /// Handle cross-track drag end - commit the move
  void _handleCrossTrackDragEnd(String clipId) {
    if (_crossTrackDraggingClipId == clipId && _crossTrackTargetIndex >= 0) {
      // Check if dropping below all existing tracks → create new track
      if (_crossTrackTargetIndex >= widget.tracks.length) {
        // Move to NEW track (will be created by the handler)
        // Track selection will be handled by onClipMoveToNewTrack callback
        widget.onClipMoveToNewTrack?.call(clipId, _crossTrackDragTime);
      } else {
        final targetTrack = widget.tracks[_crossTrackTargetIndex];

        // Find the original clip to check if we're actually moving to a different track
        final clip = widget.clips.firstWhere(
          (c) => c.id == clipId,
          orElse: () => widget.clips.first,
        );

        if (clip.trackId != targetTrack.id) {
          // Move to different track - also select the target track
          setState(() => _internalSelectedTrackId = targetTrack.id);
          widget.onTrackSelect?.call(targetTrack.id);
          widget.onClipMoveToTrack?.call(clipId, targetTrack.id, _crossTrackDragTime);
        } else {
          // Same track, just update time
          widget.onClipMove?.call(clipId, _crossTrackDragTime);
        }
      }
    }

    setState(() {
      _crossTrackDraggingClipId = null;
      _crossTrackTargetIndex = -1;
      // Clear ghost state
      _draggingClip = null;
      _ghostPosition = null;
      _dragSourceTrackIndex = -1;
      _grabOffset = Offset.zero;
    });
  }

  /// Start dragging a clip (track source for cross-track detection)
  void _handleClipDragStart(String clipId, Offset globalPosition, Offset localPosition, int trackIndex) {
    debugPrint('[Timeline] _handleClipDragStart called for $clipId');
    // Find the clip being dragged
    final clip = widget.clips.firstWhere(
      (c) => c.id == clipId,
      orElse: () => widget.clips.first,
    );

    // Convert global position to local for ghost rendering
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    final localPos = renderBox?.globalToLocal(globalPosition) ?? globalPosition;

    setState(() {
      _dragSourceTrackIndex = trackIndex;
      _draggingClip = clip;
      _ghostPosition = localPos;
      // Store where user grabbed the clip (localPosition is relative to clip widget)
      _grabOffset = localPosition;
    });
  }

  /// Update during drag - update ghost position and snap preview
  void _handleClipDragUpdate(Offset globalPosition) {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    final localPos = renderBox?.globalToLocal(globalPosition) ?? globalPosition;

    // Calculate snapped time for preview line
    double? snapTime;
    if (widget.snapEnabled && _draggingClip != null) {
      // Calculate raw time from ghost position
      final rawTime = (localPos.dx - _grabOffset.dx + widget.scrollOffset * widget.zoom) / widget.zoom;
      // Apply snap
      snapTime = applySnap(
        rawTime,
        widget.snapEnabled,
        widget.snapValue,
        widget.tempo,
        widget.clips,
      );
    }

    setState(() {
      _ghostPosition = localPos;
      _snapPreviewTime = snapTime;
    });
  }

  /// End drag - clear ghost and snap preview
  void _handleClipDragEnd(Offset globalPosition) {
    debugPrint('[Timeline] _handleClipDragEnd called - clearing ghost');
    setState(() {
      _dragSourceTrackIndex = -1;
      _draggingClip = null;
      _ghostPosition = null;
      _grabOffset = Offset.zero;
      _snapPreviewTime = null;
    });
  }

  /// Build track row with optional automation and comping lanes
  Widget _buildTrackWithAutomation({
    required TimelineTrack track,
    required List<TimelineClip> trackClips,
    required List<Crossfade> trackCrossfades,
    required bool isEmpty,
    required List<AutomationLaneData> visibleAutomationLanes,
    required int trackIndex,
  }) {
    // Use track's height (per-track resizable) or default
    final trackHeight = track.height > 0 ? track.height : _defaultTrackHeight;

    // Calculate total height including automation lanes
    final automationHeight = visibleAutomationLanes.fold<double>(
      0.0, (sum, lane) => sum + lane.height);

    // Calculate comping lanes height
    final compState = track.compState;
    final compingHeight = (compState != null && compState.lanesExpanded)
        ? compState.expandedHeight
        : 0.0;

    final totalHeight = trackHeight + automationHeight + compingHeight;

    // Key includes track ID and color to force rebuild when color changes
    return SizedBox(
      key: ValueKey('track_${track.id}_${track.color.value}'),
      height: totalHeight,
      child: Column(
        children: [
          // Main track row
          SizedBox(
            height: trackHeight,
            child: Row(
              children: [
                // Track header - ULTIMATE VERSION with per-track resizing
                Builder(
                  builder: (context) {
                    final trackIdInt = int.tryParse(track.id) ?? 0;
                    final (peakL, _) = EngineApi.instance.getTrackPeakStereo(trackIdInt);
                    return TrackHeaderSimple(
                      track: track,
                      width: _headerWidth,
                      height: trackHeight,
                      trackNumber: trackIndex + 1,
                      isSelected: track.id == _selectedTrackId,
                      signalLevel: peakL,
                      onMuteToggle: () => widget.onTrackMuteToggle?.call(track.id),
                      onSoloToggle: () => widget.onTrackSoloToggle?.call(track.id),
                      onArmToggle: () => widget.onTrackArmToggle?.call(track.id),
                      onInputMonitorToggle: () => widget.onTrackMonitorToggle?.call(track.id),
                      onVolumeChange: (v) => widget.onTrackVolumeChange?.call(track.id, v),
                      onClick: () {
                        setState(() => _internalSelectedTrackId = track.id);
                        widget.onTrackSelect?.call(track.id);
                      },
                      onRename: (n) => widget.onTrackRename?.call(track.id, n),
                      onContextMenu: (pos) => widget.onTrackContextMenu?.call(track.id, pos),
                      onHeightChange: (h) => widget.onTrackHeightChange?.call(track.id, h),
                    );
                  },
                ),
                // Track lane - key includes track color for rebuild on color change
                Expanded(
                  child: TrackLane(
                    key: ValueKey('lane_${track.id}_${track.color.value}'),
                    track: track,
                    trackHeight: trackHeight,
                    clips: trackClips,
                    crossfades: trackCrossfades,
                    zoom: _effectiveZoom,
                    scrollOffset: widget.scrollOffset,
                    tempo: widget.tempo,
                    timeSignatureNum: widget.timeSignatureNum,
                    onClipSelect: (id) =>
                        widget.onClipSelect?.call(id, false),
                    onClipMove: widget.onClipMove,
                    onClipCrossTrackDrag: (clipId, newStartTime, verticalDelta) =>
                        _handleCrossTrackDrag(clipId, newStartTime, verticalDelta, trackIndex),
                    onClipCrossTrackDragEnd: (clipId) =>
                        _handleCrossTrackDragEnd(clipId),
                    onClipDragStart: (clipId, globalPos, localPos) =>
                        _handleClipDragStart(clipId, globalPos, localPos, trackIndex),
                    onClipDragUpdate: (clipId, globalPos) =>
                        _handleClipDragUpdate(globalPos),
                    onClipDragEnd: (clipId, globalPos) =>
                        _handleClipDragEnd(globalPos),
                    onClipGainChange: widget.onClipGainChange,
                    onClipFadeChange: widget.onClipFadeChange,
                    onClipResize: widget.onClipResize,
                    onClipResizeEnd: widget.onClipResizeEnd,
                    onClipRename: widget.onClipRename,
                    onClipSlipEdit: widget.onClipSlipEdit,
                    onClipOpenAudioEditor: widget.onClipOpenAudioEditor,
                    onPlayheadMove: widget.onPlayheadChange,
                    onCrossfadeUpdate: widget.onCrossfadeUpdate,
                    onCrossfadeFullUpdate: widget.onCrossfadeFullUpdate,
                    onCrossfadeDelete: widget.onCrossfadeDelete,
                    snapEnabled: widget.snapEnabled,
                    snapValue: widget.snapValue,
                    allClips: widget.clips,
                  ),
                ),
              ],
            ),
          ),
          // Automation lanes
          ...visibleAutomationLanes.map((laneData) => _buildAutomationLaneRow(
            track: track,
            laneData: laneData,
          )),
          // Comping lanes
          if (compState != null && compState.lanesExpanded)
            _buildCompingView(track: track, compState: compState),
        ],
      ),
    );
  }

  /// Build comping view with all lanes
  Widget _buildCompingView({
    required TimelineTrack track,
    required CompState compState,
  }) {
    return CompingView(
      compState: compState,
      pixelsPerSecond: _effectiveZoom,
      scrollOffset: widget.scrollOffset,
      visibleWidth: _containerWidth,
      trackHeaderWidth: _headerWidth,
      onActiveLaneChanged: (index) =>
          widget.onCompingLaneActivate?.call(track.id, index),
      onLaneMuteToggle: (laneId) =>
          widget.onCompingLaneMuteToggle?.call(track.id, laneId),
      onLaneDelete: (laneId) =>
          widget.onCompingLaneDelete?.call(track.id, laneId),
      onTakeTap: (take) =>
          widget.onCompingTakeTap?.call(track.id, take),
      onTakeDoubleTap: (take) =>
          widget.onCompingTakeDoubleTap?.call(track.id, take),
      onCompRegionCreated: (takeId, start, end) =>
          widget.onCompRegionCreate?.call(track.id, takeId, start, end),
    );
  }

  /// Build a single automation lane row
  Widget _buildAutomationLaneRow({
    required TimelineTrack track,
    required AutomationLaneData laneData,
  }) {
    return SizedBox(
      height: laneData.height,
      child: Row(
        children: [
          // Automation lane header (match main header width)
          SizedBox(
            width: _headerWidth,
            child: AutomationLaneHeader(
              data: laneData,
              onModeChanged: (mode) {
                final updatedLane = laneData.copyWith(mode: mode);
                widget.onAutomationLaneChanged?.call(track.id, updatedLane);
              },
              onVisibilityChanged: (visible) {
                final updatedLane = laneData.copyWith(visible: visible);
                widget.onAutomationLaneChanged?.call(track.id, updatedLane);
              },
              onRemove: () {
                widget.onRemoveAutomationLane?.call(track.id, laneData.id);
              },
            ),
          ),
          // Automation lane content
          Expanded(
            child: AutomationLane(
              data: laneData,
              zoom: _effectiveZoom,
              scrollOffset: widget.scrollOffset,
              width: _containerWidth,
              onDataChanged: (updatedLane) {
                widget.onAutomationLaneChanged?.call(track.id, updatedLane);
              },
              onRemove: () {
                widget.onRemoveAutomationLane?.call(track.id, laneData.id);
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Wrap in DragTarget for Audio Pool items
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) {
        // Accept any PoolAudioFile
        setState(() {
          _isDroppingPoolFile = true;
        });
        return true;
      },
      onLeave: (data) {
        setState(() {
          _isDroppingPoolFile = false;
          _poolDropPosition = null;
        });
      },
      onAcceptWithDetails: (details) {
        _handlePoolFileDrop(details.data, details.offset);
      },
      builder: (context, candidateData, rejectedData) {
        return DropTarget(
          onDragEntered: (details) {
            setState(() {
              _isDroppingFile = true;
            });
          },
      onDragExited: (details) {
        setState(() {
          _isDroppingFile = false;
          _dropPosition = null;
        });
      },
      onDragUpdated: (details) {
        setState(() {
          _dropPosition = details.localPosition;
        });
      },
      onDragDone: _handleFileDrop,
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: (node, event) {
          return _handleKeyEvent(event);
        },
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              _handleWheel(event);
            }
          },
          onPointerPanZoomUpdate: (event) {
            // macOS trackpad two-finger pan gesture
            _handleTrackpadPan(event);
          },
          onPointerPanZoomEnd: (event) {
            // Start momentum when gesture ends
            _handleTrackpadEnd(event);
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              _containerWidth = constraints.maxWidth - _headerWidth;
              final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

              Widget timelineContent = Container(
                // Theme-aware timeline background
                decoration: isGlassMode
                    ? BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.02),
                            Colors.black.withValues(alpha: 0.03),
                          ],
                        ),
                      )
                    : const BoxDecoration(color: FluxForgeTheme.bgMid),
                child: Stack(
                  children: [
                    Column(
                children: [
                  // Ruler row
                  SizedBox(
                    height: _rulerHeight,
                    child: Row(
                      children: [
                        // Header spacer
                        Container(
                          width: _headerWidth,
                          decoration: isGlassMode
                              ? BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.white.withValues(alpha: 0.03),
                                      Colors.black.withValues(alpha: 0.02),
                                    ],
                                  ),
                                )
                              : const BoxDecoration(color: FluxForgeTheme.bgMid),
                        ),
                        // Resize handle
                        _buildHeaderResizeHandle(),
                        // Time ruler
                        Expanded(
                          child: Stack(
                            children: [
                              TimeRuler(
                                width: _containerWidth,
                                zoom: _effectiveZoom,
                                scrollOffset: widget.scrollOffset,
                                tempo: widget.tempo,
                                timeSignatureNum: widget.timeSignatureNum,
                                timeDisplayMode: widget.timeDisplayMode,
                                sampleRate: widget.sampleRate,
                                loopRegion: widget.loopRegion,
                                loopEnabled: widget.loopEnabled,
                                playheadPosition: widget.playheadPosition,
                                onTimeClick: widget.onPlayheadChange,
                                onTimeScrub: widget.onPlayheadScrub ?? widget.onPlayheadChange,
                                onLoopToggle: widget.onLoopToggle,
                                stageMarkers: widget.stageMarkers,
                                onStageMarkerClick: widget.onStageMarkerClick,
                              ),
                              // Loop region handles
                              if (widget.loopRegion != null)
                                _buildLoopHandles(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tracks
                  Expanded(
                    child: GestureDetector(
                      // IMPORTANT: deferToChild allows child widgets (clips, fade handles)
                      // to handle taps first. Only unhandled taps move the playhead.
                      behavior: HitTestBehavior.deferToChild,
                      onTapDown: _handleTimelineClick,
                      child: Stack(
                        children: [
                          // Track rows (filter hidden tracks)
                          // CRITICAL: NeverScrollableScrollPhysics prevents ListView from
                          // capturing scroll gestures - we handle horizontal scroll ourselves
                          // and vertical scroll should NOT move the track list (Cubase-style)
                          ListView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _visibleTracks.length + 1, // +1 for new track zone
                            itemBuilder: (context, index) {
                              if (index == _visibleTracks.length) {
                                // New track drop zone
                                return SizedBox(
                                  height: _visibleTracks.isEmpty ? 100 : 40,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: _headerWidth,
                                        color: FluxForgeTheme.bgMid,
                                        child: Center(
                                          child: Text(
                                            '+ Add Track',
                                            style: FluxForgeTheme.bodySmall.copyWith(
                                              color: FluxForgeTheme.textTertiary,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: FluxForgeTheme.borderSubtle,
                                              style: BorderStyle.solid,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              _visibleTracks.isEmpty
                                                  ? 'Drop audio files here to create tracks'
                                                  : '+ Drop to add track',
                                              style: FluxForgeTheme.bodySmall.copyWith(
                                                color: FluxForgeTheme.textTertiary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              final track = _visibleTracks[index];
                              final trackClips = _clipsByTrack[track.id] ?? [];
                              final trackCrossfades =
                                  _crossfadesByTrack[track.id] ?? [];

                              // Check if track is empty (no clips)
                              final isEmpty = trackClips.isEmpty;

                              // Get visible automation lanes
                              final visibleAutomationLanes = track.automationExpanded
                                  ? track.visibleAutomationLanes
                                  : <AutomationLaneData>[];

                              return _buildTrackWithAutomation(
                                track: track,
                                trackClips: trackClips,
                                trackCrossfades: trackCrossfades,
                                isEmpty: isEmpty,
                                visibleAutomationLanes: visibleAutomationLanes,
                                trackIndex: index,
                              );
                            },
                          ),

                          // ISOLATED Playhead (Cubase-style) - RepaintBoundary for performance
                          // This ensures playhead repainting doesn't cause full timeline rebuild
                          _IsolatedPlayhead(
                            playheadX: _playheadX,
                            headerWidth: _headerWidth,
                            containerWidth: _containerWidth,
                            isDragging: _isDraggingPlayhead,
                            onDragStart: () => setState(() => _isDraggingPlayhead = true),
                            onDragUpdate: _handlePlayheadDrag,
                            onDragEnd: () => setState(() => _isDraggingPlayhead = false),
                          ),

                          // Markers
                          ...widget.markers.map((marker) {
                            final x = (marker.time - widget.scrollOffset) * _effectiveZoom;
                            if (x < 0 || x > _containerWidth) {
                              return const SizedBox.shrink();
                            }
                            return Positioned(
                              left: _headerWidth + x,
                              top: 0,
                              child: GestureDetector(
                                onTap: () {
                                  widget.onPlayheadChange?.call(marker.time);
                                  widget.onMarkerClick?.call(marker.id);
                                },
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: marker.color,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Text(
                                        marker.name,
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: FluxForgeTheme.textPrimary,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      height: 100,
                                      color: marker.color.withValues(alpha: 0.5),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),

                          // Ghost clip preview during drag
                          if (_draggingClip != null && _ghostPosition != null)
                            Positioned(
                              // Position ghost so grab point stays under cursor
                              left: _ghostPosition!.dx - _grabOffset.dx,
                              top: _ghostPosition!.dy - _rulerHeight - _grabOffset.dy,
                              child: IgnorePointer(
                                child: Opacity(
                                  opacity: 0.6,
                                  child: Container(
                                    width: _draggingClip!.duration * _effectiveZoom,
                                    height: _defaultTrackHeight - 4,
                                    decoration: BoxDecoration(
                                      color: (_draggingClip!.color ?? FluxForgeTheme.accentBlue).withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: FluxForgeTheme.textPrimary,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: FluxForgeTheme.bgVoid.withValues(alpha: 0.4),
                                          blurRadius: 8,
                                          offset: const Offset(2, 2),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(2),
                                      child: Stack(
                                        children: [
                                          // Waveform preview
                                          if (_draggingClip!.waveform != null)
                                            Positioned.fill(
                                              child: Padding(
                                                padding: const EdgeInsets.all(2),
                                                child: CustomPaint(
                                                  painter: _GhostWaveformPainter(
                                                    waveform: _draggingClip!.waveform!,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          // Name
                                          Positioned(
                                            left: 4,
                                            top: 2,
                                            child: Text(
                                              _draggingClip!.name,
                                              style: FluxForgeTheme.bodySmall.copyWith(
                                                color: FluxForgeTheme.textPrimary,
                                                fontWeight: FontWeight.w500,
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

                          // Snap preview line (vertical line showing snap position)
                          // Pro DAW style: prominent cyan line with glow + time badge
                          if (_snapPreviewTime != null && widget.snapEnabled)
                            Positioned(
                              left: (_snapPreviewTime! - widget.scrollOffset) * _effectiveZoom - 1,
                              top: 0,
                              bottom: 0,
                              child: IgnorePointer(
                                child: Column(
                                  children: [
                                    // Time badge at top
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: FluxForgeTheme.accentCyan,
                                        borderRadius: BorderRadius.circular(3),
                                        boxShadow: [
                                          BoxShadow(
                                            color: FluxForgeTheme.accentCyan.withOpacity(0.6),
                                            blurRadius: 6,
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        _formatSnapTime(_snapPreviewTime!),
                                        style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                    // Vertical snap line
                                    Expanded(
                                      child: Container(
                                        width: 2,
                                        decoration: BoxDecoration(
                                          color: FluxForgeTheme.accentCyan,
                                          boxShadow: [
                                            BoxShadow(
                                              color: FluxForgeTheme.accentCyan.withOpacity(0.7),
                                              blurRadius: 8,
                                              spreadRadius: 2,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Zoom indicator
                  Container(
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    color: FluxForgeTheme.bgMid,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${_effectiveZoom.toStringAsFixed(0)}px/s',
                          style: FluxForgeTheme.monoSmall,
                        ),
                      ],
                    ),
                  ),
                ],
                    ), // Column

                    // Drop overlay with ghost clip preview (Cubase-style)
                    if (_isDroppingFile)
                      Positioned.fill(
                        child: Container(
                          color: FluxForgeTheme.accentBlue.withValues(alpha: 0.05),
                        ),
                      ),

                    // Ghost clip preview at drop position
                    if (_isDroppingFile && _dropPosition != null)
                      Builder(
                        builder: (context) {
                          // Calculate target track
                          final yInContent = _dropPosition!.dy - _rulerHeight;
                          final trackIndex = (yInContent / _defaultTrackHeight).floor().clamp(0, math.max(0, widget.tracks.length - 1));
                          final targetTrackY = trackIndex * _defaultTrackHeight + _rulerHeight + 2;

                          // Ghost clip dimensions (preview)
                          const ghostWidth = 120.0; // Default width for preview
                          final ghostHeight = _defaultTrackHeight - 4;

                          return Stack(
                            children: [
                              // Track highlight
                              if (widget.tracks.isNotEmpty)
                                Positioned(
                                  left: _headerWidth,
                                  top: targetTrackY - 2,
                                  right: 0,
                                  height: _defaultTrackHeight,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: FluxForgeTheme.accentBlue.withValues(alpha: 0.1),
                                      border: Border.all(
                                        color: FluxForgeTheme.accentBlue.withValues(alpha: 0.4),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                ),

                              // Ghost clip
                              Positioned(
                                left: _dropPosition!.dx - ghostWidth / 2,
                                top: targetTrackY,
                                child: Container(
                                  width: ghostWidth,
                                  height: ghostHeight,
                                  decoration: BoxDecoration(
                                    color: FluxForgeTheme.accentBlue.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: FluxForgeTheme.accentBlue,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: FluxForgeTheme.accentBlue.withValues(alpha: 0.4),
                                        blurRadius: 12,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    children: [
                                      // Waveform placeholder
                                      Positioned.fill(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(2),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  FluxForgeTheme.textPrimary.withValues(alpha: 0.2),
                                                  FluxForgeTheme.textPrimary.withValues(alpha: 0.1),
                                                  FluxForgeTheme.textPrimary.withValues(alpha: 0.2),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Icon
                                      Center(
                                        child: Icon(
                                          Icons.audio_file,
                                          size: 20,
                                          color: FluxForgeTheme.textPrimary.withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Position line
                              Positioned(
                                left: _dropPosition!.dx - 1,
                                top: _rulerHeight,
                                bottom: 0,
                                child: Container(
                                  width: 2,
                                  color: FluxForgeTheme.accentBlue,
                                ),
                              ),

                              // Time tooltip
                              Positioned(
                                left: _dropPosition!.dx + 8,
                                top: _rulerHeight + 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: FluxForgeTheme.bgMid,
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: FluxForgeTheme.accentBlue),
                                  ),
                                  child: Text(
                                    _formatDropTime(_dropPosition!.dx),
                                    style: FluxForgeTheme.monoSmall.copyWith(
                                      color: FluxForgeTheme.accentBlue,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                    // DEBUG OVERLAY - Engine status (remove after debugging)
                    Positioned(
                      top: _rulerHeight + 4,
                      right: 8,
                      child: _DebugOverlay(
                        isPlaying: widget.isPlaying,
                        playheadPosition: widget.playheadPosition,
                      ),
                    ),
                  ],
                ), // Stack
              );

              // Apply Glass blur wrapper
              if (isGlassMode) {
                timelineContent = ClipRect(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: timelineContent,
                  ),
                );
              }

              return timelineContent;
            },
          ),
        ),
      ),
    ); // DropTarget
      }, // DragTarget builder
    ); // DragTarget
  }

  Widget _buildLoopHandles() {
    if (widget.loopRegion == null) return const SizedBox.shrink();

    final loopStartX = (widget.loopRegion!.start - widget.scrollOffset) * _effectiveZoom;
    final loopEndX = (widget.loopRegion!.end - widget.scrollOffset) * _effectiveZoom;
    final loopWidth = (loopEndX - loopStartX).clamp(10.0, double.infinity);

    return Positioned(
      left: loopStartX,
      top: 0,
      width: loopWidth,
      height: _rulerHeight,
      child: GestureDetector(
        onTap: widget.onLoopToggle,
        child: Stack(
          children: [
            // Left handle
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 8,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  onHorizontalDragStart: (_) {
                    setState(() => _isDraggingLoopLeft = true);
                  },
                  onHorizontalDragUpdate: (d) => _handleLoopDrag(d, true),
                  onHorizontalDragEnd: (_) {
                    setState(() => _isDraggingLoopLeft = false);
                  },
                  child: Container(
                    color: _isDraggingLoopLeft
                        ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
                        : Colors.transparent,
                  ),
                ),
              ),
            ),
            // Right handle
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 8,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  onHorizontalDragStart: (_) {
                    setState(() => _isDraggingLoopRight = true);
                  },
                  onHorizontalDragUpdate: (d) => _handleLoopDrag(d, false),
                  onHorizontalDragEnd: (_) {
                    setState(() => _isDraggingLoopRight = false);
                  },
                  child: Container(
                    color: _isDraggingLoopRight
                        ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
                        : Colors.transparent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayheadPainter extends CustomPainter {
  final bool isDragging;

  _PlayheadPainter({this.isDragging = false});

  @override
  void paint(Canvas canvas, Size size) {
    // Cubase-style playhead triangle with shadow
    final shadowPaint = Paint()
      ..color = FluxForgeTheme.bgVoid.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    final paint = Paint()
      ..color = isDragging
          ? FluxForgeTheme.accentRed
          : FluxForgeTheme.accentRed.withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;

    // Shadow
    final shadowPath = Path()
      ..moveTo(1, 1)
      ..lineTo(size.width - 1, 1)
      ..lineTo(size.width / 2, size.height + 1)
      ..close();
    canvas.drawPath(shadowPath, shadowPaint);

    // Main triangle
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);

    // Inner highlight for 3D effect
    if (isDragging) {
      final highlightPaint = Paint()
        ..color = FluxForgeTheme.textPrimary.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      final highlightPath = Path()
        ..moveTo(2, 2)
        ..lineTo(size.width - 2, 2)
        ..lineTo(size.width / 2, size.height - 2);
      canvas.drawPath(highlightPath, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(_PlayheadPainter oldDelegate) =>
      isDragging != oldDelegate.isDragging;
}

/// Simple waveform painter for ghost preview
class _GhostWaveformPainter extends CustomPainter {
  final Float32List waveform;

  _GhostWaveformPainter({required this.waveform});

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty || size.width <= 0 || size.height <= 0) return;

    final centerY = size.height / 2;
    final amplitude = centerY * 0.8;
    final samplesPerPixel = waveform.length / size.width;

    final paint = Paint()
      ..color = FluxForgeTheme.textPrimary.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final path = Path();
    bool started = false;
    final bottomY = <double>[];

    for (double x = 0; x < size.width; x++) {
      final startIdx = (x * samplesPerPixel).floor().clamp(0, waveform.length - 1);
      final endIdx = ((x + 1) * samplesPerPixel).ceil().clamp(startIdx + 1, waveform.length);

      double maxVal = 0;
      for (int i = startIdx; i < endIdx; i++) {
        final s = waveform[i].abs();
        if (s > maxVal) maxVal = s;
      }

      final yTop = centerY - maxVal * amplitude;
      if (!started) {
        path.moveTo(x, yTop);
        started = true;
      } else {
        path.lineTo(x, yTop);
      }
      bottomY.add(centerY + maxVal * amplitude);
    }

    for (int i = bottomY.length - 1; i >= 0; i--) {
      path.lineTo(i.toDouble(), bottomY[i]);
    }
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_GhostWaveformPainter oldDelegate) =>
      waveform != oldDelegate.waveform;
}

// ════════════════════════════════════════════════════════════════════════════
// ISOLATED PLAYHEAD WIDGET - PERFORMANCE CRITICAL
// ════════════════════════════════════════════════════════════════════════════
/// Isolated playhead widget with its own RepaintBoundary
/// This ensures playhead updates don't trigger full timeline rebuilds
class _IsolatedPlayhead extends StatelessWidget {
  final double playheadX;
  final double headerWidth;
  final double containerWidth;
  final bool isDragging;
  final VoidCallback onDragStart;
  final void Function(DragUpdateDetails) onDragUpdate;
  final VoidCallback onDragEnd;

  const _IsolatedPlayhead({
    required this.playheadX,
    required this.headerWidth,
    required this.containerWidth,
    required this.isDragging,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    // Skip if not visible
    if (playheadX < 0 || playheadX > containerWidth) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: headerWidth + playheadX,
      top: 0,
      bottom: 0,
      // RepaintBoundary INSIDE Positioned - isolates playhead painting
      child: RepaintBoundary(
        child: GestureDetector(
          onHorizontalDragStart: (_) => onDragStart(),
          onHorizontalDragUpdate: onDragUpdate,
          onHorizontalDragEnd: (_) => onDragEnd(),
          child: MouseRegion(
            cursor: isDragging
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.resizeColumn,
            child: Container(
              width: 16,
              transform: Matrix4.translationValues(-8, 0, 0),
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  // Glow effect (Cubase-style)
                  if (isDragging)
                    Container(
                      width: 8,
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: FluxForgeTheme.accentRed.withValues(alpha: 0.6),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  // Main line
                  Positioned(
                    left: 7,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: isDragging ? 3 : 2,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentRed,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 2,
                            offset: const Offset(1, 0),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Head triangle (Cubase-style at top)
                  CustomPaint(
                    size: const Size(14, 12),
                    painter: _PlayheadPainter(
                      isDragging: isDragging,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// STANDALONE PLAYHEAD OVERLAY - FOR PROVIDER-DRIVEN UPDATES
// ════════════════════════════════════════════════════════════════════════════
/// Standalone playhead overlay that can be used with ValueListenableBuilder
/// or Selector to avoid rebuilding the entire timeline
///
/// Usage:
/// ```dart
/// Stack(
///   children: [
///     Timeline(...), // Heavy widget - doesn't rebuild on playhead change
///     ValueListenableBuilder<double>(
///       valueListenable: playheadPositionNotifier,
///       builder: (_, position, __) => PlayheadOverlay(
///         playheadPosition: position,
///         zoom: zoom,
///         scrollOffset: scrollOffset,
///         headerWidth: headerWidth,
///         containerWidth: containerWidth,
///         onPlayheadDrag: (time) => seek(time),
///       ),
///     ),
///   ],
/// )
/// ```
class PlayheadOverlay extends StatefulWidget {
  final double playheadPosition;
  final double zoom;
  final double scrollOffset;
  final double headerWidth;
  final double containerWidth;
  final ValueChanged<double>? onPlayheadDrag;
  final ValueChanged<double>? onPlayheadScrub;
  final double totalDuration;

  const PlayheadOverlay({
    super.key,
    required this.playheadPosition,
    required this.zoom,
    required this.scrollOffset,
    required this.headerWidth,
    required this.containerWidth,
    this.onPlayheadDrag,
    this.onPlayheadScrub,
    this.totalDuration = 120,
  });

  @override
  State<PlayheadOverlay> createState() => _PlayheadOverlayState();
}

class _PlayheadOverlayState extends State<PlayheadOverlay> {
  bool _isDragging = false;

  double get _playheadX =>
      (widget.playheadPosition - widget.scrollOffset) * widget.zoom;

  void _handleDragUpdate(DragUpdateDetails details) {
    final x = details.localPosition.dx - widget.headerWidth;
    final time = (widget.scrollOffset + x.clamp(0, double.infinity) / widget.zoom)
        .clamp(0.0, widget.totalDuration);

    if (widget.onPlayheadScrub != null) {
      widget.onPlayheadScrub!(time);
    } else {
      widget.onPlayheadDrag?.call(time);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Skip if not visible
    if (_playheadX < 0 || _playheadX > widget.containerWidth) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: widget.headerWidth + _playheadX,
      top: 0,
      bottom: 0,
      child: RepaintBoundary(
        child: GestureDetector(
          onHorizontalDragStart: (_) => setState(() => _isDragging = true),
          onHorizontalDragUpdate: _handleDragUpdate,
          onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
          child: MouseRegion(
            cursor: _isDragging
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.resizeColumn,
            child: Container(
              width: 16,
              transform: Matrix4.translationValues(-8, 0, 0),
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  if (_isDragging)
                    Container(
                      width: 8,
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: FluxForgeTheme.accentRed.withValues(alpha: 0.6),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  Positioned(
                    left: 7,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: _isDragging ? 3 : 2,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentRed,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 2,
                            offset: const Offset(1, 0),
                          ),
                        ],
                      ),
                    ),
                  ),
                  CustomPaint(
                    size: const Size(14, 12),
                    painter: _PlayheadPainter(isDragging: _isDragging),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Debug overlay showing engine status (TEMPORARY - remove after debugging)
class _DebugOverlay extends StatefulWidget {
  final bool isPlaying;
  final double playheadPosition;

  const _DebugOverlay({
    required this.isPlaying,
    required this.playheadPosition,
  });

  @override
  State<_DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<_DebugOverlay> {
  String _debugInfo = 'Loading...';
  bool _isLibLoaded = false;

  @override
  void initState() {
    super.initState();
    _updateDebugInfo();
  }

  @override
  void didUpdateWidget(_DebugOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update on every frame when playing
    if (widget.isPlaying || oldWidget.isPlaying != widget.isPlaying) {
      _updateDebugInfo();
    }
  }

  void _updateDebugInfo() {
    final ffi = NativeFFI.instance;
    _isLibLoaded = ffi.isLoaded;
    if (_isLibLoaded) {
      _debugInfo = ffi.getPlaybackDebugInfo();
    } else {
      _debugInfo = 'Library NOT loaded';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _isLibLoaded ? Colors.green : Colors.red,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'DEBUG: Engine Status',
            style: FluxForgeTheme.monoSmall.copyWith(
              color: Colors.yellow,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Lib: ${_isLibLoaded ? "LOADED" : "NOT LOADED"}',
            style: FluxForgeTheme.monoSmall.copyWith(
              color: _isLibLoaded ? Colors.green : Colors.red,
            ),
          ),
          Text(
            'Playing: ${widget.isPlaying}',
            style: FluxForgeTheme.monoSmall.copyWith(
              color: widget.isPlaying ? Colors.green : Colors.grey,
            ),
          ),
          Text(
            'Pos: ${widget.playheadPosition.toStringAsFixed(3)}s',
            style: FluxForgeTheme.monoSmall.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            _debugInfo,
            style: FluxForgeTheme.monoSmall.copyWith(
              color: Colors.cyan,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
