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
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import '../../theme/reelforge_theme.dart';
import '../../models/timeline_models.dart';
import '../../src/rust/engine_api.dart';
import 'time_ruler.dart';
import 'track_header_simple.dart';
// import 'track_header_reelforge.dart'; // Alternative: richer track headers
import 'track_lane.dart';
import 'automation_lane.dart';
import 'clip_widget.dart' show fadeHandleActiveGlobal;

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

  /// Transport controls
  final VoidCallback? onPlayPause;
  final VoidCallback? onStop;

  /// Undo/Redo
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  /// Crossfades
  final List<Crossfade> crossfades;
  final void Function(String crossfadeId, double duration)? onCrossfadeUpdate;
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

  /// Pool file drop callback (for drag from Audio Pool)
  /// Called when PoolAudioFile is dropped on timeline
  /// Returns (poolFile, trackId, startTime) - trackId can be null for new track
  final void Function(dynamic poolFile, String? trackId, double startTime)? onPoolFileDrop;

  /// Track duplicate/delete callbacks
  final ValueChanged<String>? onTrackDuplicate;
  final ValueChanged<String>? onTrackDelete;
  /// Context menu callback for tracks (pass track ID and position)
  final void Function(String trackId, Offset position)? onTrackContextMenu;

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
    this.onPlayPause,
    this.onStop,
    this.onUndo,
    this.onRedo,
    this.crossfades = const [],
    this.onCrossfadeUpdate,
    this.onCrossfadeDelete,
    this.snapEnabled = true,
    this.snapValue = 1,
    this.isPlaying = false,
    this.onFileDrop,
    this.onPoolFileDrop,
    this.onTrackDuplicate,
    this.onTrackDelete,
    this.onTrackContextMenu,
    this.onTrackAutomationToggle,
    this.onAutomationLaneChanged,
    this.onAddAutomationLane,
    this.onRemoveAutomationLane,
    this.onTrackHeightChange,
  });

  @override
  State<Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<Timeline> {
  // Header width is now resizable (min 140, max 300)
  double _headerWidth = 180;
  static const double _headerWidthMin = 140;
  static const double _headerWidthMax = 300;
  static const double _defaultTrackHeight = 80;
  static const double _rulerHeight = 28;

  // Selected track for highlighting
  String? _selectedTrackId;

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

  /// Supported audio file extensions
  static const _audioExtensions = {'.wav', '.mp3', '.flac', '.ogg', '.aiff', '.aif'};

  @override
  void initState() {
    super.initState();
    // Auto-focus after first frame to enable keyboard shortcuts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  double get _playheadX => (widget.playheadPosition - widget.scrollOffset) * widget.zoom;

  /// Get visible tracks (filter out hidden)
  List<TimelineTrack> get _visibleTracks =>
      widget.tracks.where((t) => !t.hidden).toList();

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
              ? ReelForgeTheme.accentBlue
              : ReelForgeTheme.borderMedium,
        ),
      ),
    );
  }

  void _handleWheel(PointerScrollEvent event) {
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      // SMOOTH ZOOM with zoom-to-cursor (Cubase/Logic style)
      // Scale zoom factor based on scroll magnitude for smooth trackpad support
      final scrollMagnitude = event.scrollDelta.dy.abs();
      final zoomFactor = 1.0 + (scrollMagnitude / 400.0).clamp(0.02, 0.12);
      final delta = event.scrollDelta.dy > 0 ? 1.0 / zoomFactor : zoomFactor;

      // Calculate cursor position in timeline
      final mouseX = event.localPosition.dx - _headerWidth;
      if (mouseX < 0) {
        // Mouse over header, just zoom without cursor tracking
        final newZoom = (widget.zoom * delta).clamp(5.0, 500.0);
        widget.onZoomChange?.call(newZoom);
        return;
      }

      // Time position under cursor before zoom
      final mouseTime = widget.scrollOffset + mouseX / widget.zoom;

      // Apply zoom
      final newZoom = (widget.zoom * delta).clamp(5.0, 500.0);

      // Calculate new scroll offset to keep cursor position stable
      final newScrollOffset = mouseTime - mouseX / newZoom;

      // Apply both changes
      widget.onZoomChange?.call(newZoom);
      widget.onScrollChange?.call(newScrollOffset.clamp(0.0,
          (widget.totalDuration - _containerWidth / newZoom).clamp(0.0, double.infinity)));
    } else {
      // SMOOTH SCROLL - scale based on zoom level for consistent feel
      final rawDelta = event.scrollDelta.dx != 0
          ? event.scrollDelta.dx
          : event.scrollDelta.dy;
      // Smoother scroll: scale delta by zoom level
      final scrollSpeed = 1.0 + (widget.zoom / 100.0).clamp(0.5, 2.0);
      final delta = rawDelta / widget.zoom * scrollSpeed;
      final newOffset = (widget.scrollOffset + delta)
          .clamp(0.0, (widget.totalDuration - _containerWidth / widget.zoom).clamp(0.0, double.infinity));
      widget.onScrollChange?.call(newOffset);
    }
  }

  void _handleTimelineClick(TapDownDetails details) {
    // Request focus for keyboard shortcuts (G, H, L, etc.)
    _focusNode.requestFocus();

    // IGNORE click if fade handle is active (prevents playhead jumping)
    if (fadeHandleActiveGlobal) {
      return;
    }

    final x = details.localPosition.dx - _headerWidth;
    if (x < 0) return;
    final time = widget.scrollOffset + x / widget.zoom;
    widget.onPlayheadChange?.call(time.clamp(0, widget.totalDuration));
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

  void _handleKeyEvent(KeyEvent event) {
    debugPrint('[Timeline] Key event: ${event.logicalKey.keyLabel} (${event.runtimeType})');

    // G/H zoom and [ ] fade - allow repeat (hold key for continuous adjustment)
    final isZoomKey = event.logicalKey == LogicalKeyboardKey.keyG ||
        event.logicalKey == LogicalKeyboardKey.keyH;
    final isFadeKey = event.logicalKey == LogicalKeyboardKey.bracketLeft ||
        event.logicalKey == LogicalKeyboardKey.bracketRight;

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    // Only allow repeat for zoom and fade keys
    if (event is KeyRepeatEvent && !isZoomKey && !isFadeKey) return;

    final selectedClip = widget.clips.cast<TimelineClip?>().firstWhere(
      (c) => c?.selected == true,
      orElse: () => null,
    );

    // S key - split clip at playhead
    if (event.logicalKey == LogicalKeyboardKey.keyS) {
      if (selectedClip != null && widget.onClipSplit != null) {
        if (widget.playheadPosition > selectedClip.startTime &&
            widget.playheadPosition < selectedClip.endTime) {
          widget.onClipSplit!(selectedClip.id);
        }
      }
    }

    // Cmd+D - duplicate
    if ((HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyD) {
      if (selectedClip != null) {
        widget.onClipDuplicate?.call(selectedClip.id);
      }
    }

    // G - zoom out (Cubase-style, hold for continuous)
    // Smooth zoom with center-screen anchor
    if (event.logicalKey == LogicalKeyboardKey.keyG) {
      final centerX = _containerWidth / 2;
      final centerTime = widget.scrollOffset + centerX / widget.zoom;
      final newZoom = (widget.zoom * 0.92).clamp(5.0, 500.0);
      final newScrollOffset = centerTime - centerX / newZoom;
      widget.onZoomChange?.call(newZoom);
      widget.onScrollChange?.call(newScrollOffset.clamp(0.0,
          (widget.totalDuration - _containerWidth / newZoom).clamp(0.0, double.infinity)));
    }

    // H - zoom in (Cubase-style, hold for continuous)
    // Smooth zoom with center-screen anchor
    if (event.logicalKey == LogicalKeyboardKey.keyH) {
      final centerX = _containerWidth / 2;
      final centerTime = widget.scrollOffset + centerX / widget.zoom;
      final newZoom = (widget.zoom * 1.08).clamp(5.0, 500.0);
      final newScrollOffset = centerTime - centerX / newZoom;
      widget.onZoomChange?.call(newZoom);
      widget.onScrollChange?.call(newScrollOffset.clamp(0.0,
          (widget.totalDuration - _containerWidth / newZoom).clamp(0.0, double.infinity)));
    }

    // L - set loop around selected clip OR toggle loop if no selection
    if (event.logicalKey == LogicalKeyboardKey.keyL) {
      if (selectedClip != null && widget.onLoopRegionChange != null) {
        // Set loop region around selected clip
        widget.onLoopRegionChange!(LoopRegion(
          start: selectedClip.startTime,
          end: selectedClip.endTime,
        ));
        // Enable loop if not already
        if (!widget.loopEnabled) {
          widget.onLoopToggle?.call();
        }
      } else {
        // No selection - toggle loop on/off
        widget.onLoopToggle?.call();
      }
    }

    // Arrow keys - nudge clip
    if (selectedClip != null && widget.onClipMove != null) {
      final beatsPerSecond = widget.tempo / 60;
      final nudgeAmount = HardwareKeyboard.instance.isShiftPressed
          ? 1 / beatsPerSecond
          : 0.25 / beatsPerSecond;

      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        final newTime = (selectedClip.startTime - nudgeAmount).clamp(0.0, double.infinity);
        widget.onClipMove!(selectedClip.id, newTime);
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        widget.onClipMove!(selectedClip.id, selectedClip.startTime + nudgeAmount);
      }
    }

    // [ and ] keys - fade nudge (Pro Tools style)
    // [ = decrease fade in / increase fade out
    // ] = increase fade in / decrease fade out
    // Shift = fine control (10ms steps)
    if (selectedClip != null && widget.onClipFadeChange != null) {
      final fadeNudgeAmount = HardwareKeyboard.instance.isShiftPressed
          ? 0.01  // 10ms fine control
          : 0.05; // 50ms normal

      // [ key - decrease fade in OR increase fade out
      if (event.logicalKey == LogicalKeyboardKey.bracketLeft) {
        if (HardwareKeyboard.instance.isAltPressed) {
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
      }

      // ] key - increase fade in OR decrease fade out
      if (event.logicalKey == LogicalKeyboardKey.bracketRight) {
        if (HardwareKeyboard.instance.isAltPressed) {
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
      }
    }

    // Delete/Backspace
    if ((event.logicalKey == LogicalKeyboardKey.delete ||
            event.logicalKey == LogicalKeyboardKey.backspace) &&
        selectedClip != null) {
      widget.onClipDelete?.call(selectedClip.id);
    }

    // Cmd+C - copy
    if ((HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyC &&
        selectedClip != null) {
      widget.onClipCopy?.call(selectedClip.id);
    }

    // Cmd+V - paste
    if ((HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyV) {
      widget.onClipPaste?.call();
    }

    // SPACE - play/pause
    if (event.logicalKey == LogicalKeyboardKey.space) {
      widget.onPlayPause?.call();
    }

    // Cmd+Z - undo, Cmd+Shift+Z - redo
    if ((HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        debugPrint('[Timeline] Redo shortcut triggered');
        widget.onRedo?.call();
      } else {
        debugPrint('[Timeline] Undo shortcut triggered');
        widget.onUndo?.call();
      }
    }

    // Cmd+Y - redo (Windows style)
    if ((HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyY) {
      widget.onRedo?.call();
    }
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
        widget.onClipMoveToNewTrack?.call(clipId, _crossTrackDragTime);
      } else {
        final targetTrack = widget.tracks[_crossTrackTargetIndex];

        // Find the original clip to check if we're actually moving to a different track
        final clip = widget.clips.firstWhere(
          (c) => c.id == clipId,
          orElse: () => widget.clips.first,
        );

        if (clip.trackId != targetTrack.id) {
          // Move to different track
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

  /// Build track row with optional automation lanes
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
    final totalHeight = trackHeight + automationHeight;

    return SizedBox(
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
                      onVolumeChange: (v) => widget.onTrackVolumeChange?.call(track.id, v),
                      onClick: () {
                        setState(() => _selectedTrackId = track.id);
                        widget.onTrackSelect?.call(track.id);
                      },
                      onRename: (n) => widget.onTrackRename?.call(track.id, n),
                      onContextMenu: (pos) => widget.onTrackContextMenu?.call(track.id, pos),
                      onHeightChange: (h) => widget.onTrackHeightChange?.call(track.id, h),
                    );
                  },
                ),
                // Track lane
                Expanded(
                  child: TrackLane(
                    track: track,
                    trackHeight: trackHeight,
                    clips: trackClips,
                    crossfades: trackCrossfades,
                    zoom: widget.zoom,
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
                    onClipRename: widget.onClipRename,
                    onClipSlipEdit: widget.onClipSlipEdit,
                    onClipOpenAudioEditor: widget.onClipOpenAudioEditor,
                    onCrossfadeUpdate: widget.onCrossfadeUpdate,
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
        ],
      ),
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
              zoom: widget.zoom,
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
          _handleKeyEvent(event);
          return KeyEventResult.handled;
        },
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              _handleWheel(event);
            }
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              _containerWidth = constraints.maxWidth - _headerWidth;

              return Container(
                // Logic Pro-style timeline background
                color: ReelForgeTheme.bgMid,
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
                          color: ReelForgeTheme.bgMid,
                        ),
                        // Resize handle
                        _buildHeaderResizeHandle(),
                        // Time ruler
                        Expanded(
                          child: Stack(
                            children: [
                              TimeRuler(
                                width: _containerWidth,
                                zoom: widget.zoom,
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
                          ListView.builder(
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
                                        color: ReelForgeTheme.bgMid,
                                        child: Center(
                                          child: Text(
                                            '+ Add Track',
                                            style: ReelForgeTheme.bodySmall.copyWith(
                                              color: ReelForgeTheme.textTertiary,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: ReelForgeTheme.borderSubtle,
                                              style: BorderStyle.solid,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              _visibleTracks.isEmpty
                                                  ? 'Drop audio files here to create tracks'
                                                  : '+ Drop to add track',
                                              style: ReelForgeTheme.bodySmall.copyWith(
                                                color: ReelForgeTheme.textTertiary,
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

                          // Playhead (Cubase-style)
                          if (_playheadX >= 0 && _playheadX <= _containerWidth)
                            Positioned(
                              left: _headerWidth + _playheadX,
                              top: 0,
                              bottom: 0,
                              child: GestureDetector(
                                onHorizontalDragStart: (_) {
                                  setState(() => _isDraggingPlayhead = true);
                                },
                                onHorizontalDragUpdate: _handlePlayheadDrag,
                                onHorizontalDragEnd: (_) {
                                  setState(() => _isDraggingPlayhead = false);
                                },
                                child: MouseRegion(
                                  cursor: _isDraggingPlayhead
                                      ? SystemMouseCursors.grabbing
                                      : SystemMouseCursors.resizeColumn,
                                  child: Container(
                                    width: 16,
                                    transform: Matrix4.translationValues(-8, 0, 0),
                                    child: Stack(
                                      alignment: Alignment.topCenter,
                                      children: [
                                        // Glow effect (Cubase-style)
                                        if (_isDraggingPlayhead)
                                          Container(
                                            width: 8,
                                            decoration: BoxDecoration(
                                              boxShadow: [
                                                BoxShadow(
                                                  color: ReelForgeTheme.accentRed.withValues(alpha: 0.6),
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
                                            width: _isDraggingPlayhead ? 3 : 2,
                                            decoration: BoxDecoration(
                                              color: ReelForgeTheme.accentRed,
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
                                            isDragging: _isDraggingPlayhead,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          // Markers
                          ...widget.markers.map((marker) {
                            final x = (marker.time - widget.scrollOffset) * widget.zoom;
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
                                          color: ReelForgeTheme.textPrimary,
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
                                    width: _draggingClip!.duration * widget.zoom,
                                    height: _defaultTrackHeight - 4,
                                    decoration: BoxDecoration(
                                      color: (_draggingClip!.color ?? ReelForgeTheme.accentBlue).withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: ReelForgeTheme.textPrimary,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: ReelForgeTheme.bgVoid.withValues(alpha: 0.4),
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
                                              style: ReelForgeTheme.bodySmall.copyWith(
                                                color: ReelForgeTheme.textPrimary,
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
                          if (_snapPreviewTime != null && widget.snapEnabled)
                            Positioned(
                              left: (_snapPreviewTime! - widget.scrollOffset) * widget.zoom,
                              top: 0,
                              bottom: 0,
                              child: IgnorePointer(
                                child: Container(
                                  width: 2,
                                  decoration: BoxDecoration(
                                    color: ReelForgeTheme.accentCyan.withOpacity(0.8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: ReelForgeTheme.accentCyan.withOpacity(0.5),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
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
                    color: ReelForgeTheme.bgMid,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${widget.zoom.toStringAsFixed(0)}px/s',
                          style: ReelForgeTheme.monoSmall,
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
                          color: ReelForgeTheme.accentBlue.withValues(alpha: 0.05),
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
                                      color: ReelForgeTheme.accentBlue.withValues(alpha: 0.1),
                                      border: Border.all(
                                        color: ReelForgeTheme.accentBlue.withValues(alpha: 0.4),
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
                                    color: ReelForgeTheme.accentBlue.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: ReelForgeTheme.accentBlue,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: ReelForgeTheme.accentBlue.withValues(alpha: 0.4),
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
                                                  ReelForgeTheme.textPrimary.withValues(alpha: 0.2),
                                                  ReelForgeTheme.textPrimary.withValues(alpha: 0.1),
                                                  ReelForgeTheme.textPrimary.withValues(alpha: 0.2),
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
                                          color: ReelForgeTheme.textPrimary.withValues(alpha: 0.7),
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
                                  color: ReelForgeTheme.accentBlue,
                                ),
                              ),

                              // Time tooltip
                              Positioned(
                                left: _dropPosition!.dx + 8,
                                top: _rulerHeight + 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: ReelForgeTheme.bgMid,
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: ReelForgeTheme.accentBlue),
                                  ),
                                  child: Text(
                                    _formatDropTime(_dropPosition!.dx),
                                    style: ReelForgeTheme.monoSmall.copyWith(
                                      color: ReelForgeTheme.accentBlue,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                  ],
                ), // Stack
              );
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

    final loopStartX = (widget.loopRegion!.start - widget.scrollOffset) * widget.zoom;
    final loopEndX = (widget.loopRegion!.end - widget.scrollOffset) * widget.zoom;
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
                        ? ReelForgeTheme.accentBlue.withValues(alpha: 0.5)
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
                        ? ReelForgeTheme.accentBlue.withValues(alpha: 0.5)
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
      ..color = ReelForgeTheme.bgVoid.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    final paint = Paint()
      ..color = isDragging
          ? ReelForgeTheme.accentRed
          : ReelForgeTheme.accentRed.withValues(alpha: 0.95)
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
        ..color = ReelForgeTheme.textPrimary.withValues(alpha: 0.3)
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
      ..color = ReelForgeTheme.textPrimary.withValues(alpha: 0.5)
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
