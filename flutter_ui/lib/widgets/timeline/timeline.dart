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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import '../../theme/reelforge_theme.dart';
import '../../models/timeline_models.dart';
import 'time_ruler.dart';
import 'track_header.dart';
import 'track_lane.dart';

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
  final void Function(
    String clipId,
    double newStartTime,
    double newDuration,
    double? newOffset,
  )? onClipResize;
  final void Function(String clipId, double newSourceOffset)? onClipSlipEdit;
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
  final void Function(String trackId, double volume)? onTrackVolumeChange;
  final void Function(String trackId, double pan)? onTrackPanChange;
  final ValueChanged<String>? onClipSplit;
  final ValueChanged<String>? onClipDuplicate;
  final ValueChanged<String>? onClipDelete;
  final ValueChanged<String>? onClipCopy;
  final VoidCallback? onClipPaste;
  final ValueChanged<String>? onMarkerClick;

  /// Crossfades
  final List<Crossfade> crossfades;
  final void Function(String crossfadeId, double duration)? onCrossfadeUpdate;
  final void Function(String crossfadeId)? onCrossfadeDelete;

  /// Snap settings
  final bool snapEnabled;
  final double snapValue;

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
    this.onClipResize,
    this.onClipSlipEdit,
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
    this.onTrackVolumeChange,
    this.onTrackPanChange,
    this.onClipSplit,
    this.onClipDuplicate,
    this.onClipDelete,
    this.onClipCopy,
    this.onClipPaste,
    this.onMarkerClick,
    this.crossfades = const [],
    this.onCrossfadeUpdate,
    this.onCrossfadeDelete,
    this.snapEnabled = true,
    this.snapValue = 1,
    this.onFileDrop,
    this.onPoolFileDrop,
    this.onTrackDuplicate,
    this.onTrackDelete,
    this.onTrackContextMenu,
  });

  @override
  State<Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<Timeline> {
  static const double _headerWidth = 180;
  static const double _trackHeight = 80;
  static const double _rulerHeight = 28;

  bool _isDraggingPlayhead = false;
  bool _isDraggingLoopLeft = false;
  bool _isDraggingLoopRight = false;
  bool _isDroppingFile = false;
  bool _isDroppingPoolFile = false;
  Offset? _dropPosition;
  Offset? _poolDropPosition;

  final FocusNode _focusNode = FocusNode();
  double _containerWidth = 800;

  /// Supported audio file extensions
  static const _audioExtensions = {'.wav', '.mp3', '.flac', '.ogg', '.aiff', '.aif'};

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  double get _playheadX => (widget.playheadPosition - widget.scrollOffset) * widget.zoom;

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

  void _handleWheel(PointerScrollEvent event) {
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      // Zoom
      final delta = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
      final newZoom = (widget.zoom * delta).clamp(10.0, 500.0);
      widget.onZoomChange?.call(newZoom);
    } else {
      // Scroll
      final delta = event.scrollDelta.dx != 0
          ? event.scrollDelta.dx
          : event.scrollDelta.dy;
      final newOffset = (widget.scrollOffset + delta / widget.zoom)
          .clamp(0.0, widget.totalDuration - _containerWidth / widget.zoom);
      widget.onScrollChange?.call(newOffset);
    }
  }

  void _handleTimelineClick(TapDownDetails details) {
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
    final time = (widget.scrollOffset + x / widget.zoom).clamp(0.0, widget.totalDuration);

    if (isLeft) {
      final newStart = time.clamp(0.0, widget.loopRegion!.end - 0.1);
      widget.onLoopRegionChange?.call(
        LoopRegion(start: newStart, end: widget.loopRegion!.end),
      );
    } else {
      final newEnd = time.clamp(widget.loopRegion!.start + 0.1, widget.totalDuration);
      widget.onLoopRegionChange?.call(
        LoopRegion(start: widget.loopRegion!.start, end: newEnd),
      );
    }
  }

  /// Handle file drop on timeline
  void _handleFileDrop(DropDoneDetails details) {
    if (widget.onFileDrop == null) return;

    final position = _dropPosition ?? details.localPosition;

    // Calculate time from X position
    final x = position.dx - _headerWidth;
    final startTime = (widget.scrollOffset + x / widget.zoom).clamp(0.0, widget.totalDuration);

    // Calculate track from Y position
    final trackIndex = ((position.dy - _rulerHeight) / _trackHeight).floor();
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

    setState(() {
      _isDroppingFile = false;
      _dropPosition = null;
    });
  }

  /// Check if any file is an audio file
  bool _hasAudioFiles(List<XFile> files) {
    return files.any((file) {
      final ext = file.path.toLowerCase().split('.').lastOrNull;
      return ext != null && _audioExtensions.contains('.$ext');
    });
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
    final trackIndex = (yInContent / _trackHeight).floor();

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
    if (event is! KeyDownEvent) return;

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

    // G - zoom in
    if (event.logicalKey == LogicalKeyboardKey.keyG) {
      widget.onZoomChange?.call((widget.zoom * 1.25).clamp(10, 500));
    }

    // H - zoom out
    if (event.logicalKey == LogicalKeyboardKey.keyH) {
      widget.onZoomChange?.call((widget.zoom * 0.8).clamp(10, 500));
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
                color: ReelForgeTheme.bgDeepest,
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
                                onTimeClick: widget.onPlayheadChange,
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
                      onTapDown: _handleTimelineClick,
                      child: Stack(
                        children: [
                          // Track rows
                          ListView.builder(
                            itemCount: widget.tracks.length + 1, // +1 for new track zone
                            itemBuilder: (context, index) {
                              if (index == widget.tracks.length) {
                                // New track drop zone
                                return SizedBox(
                                  height: widget.tracks.isEmpty ? 100 : 40,
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
                                              widget.tracks.isEmpty
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

                              final track = widget.tracks[index];
                              final trackClips = _clipsByTrack[track.id] ?? [];
                              final trackCrossfades =
                                  _crossfadesByTrack[track.id] ?? [];

                              return SizedBox(
                                height: _trackHeight,
                                child: Row(
                                  children: [
                                    // Track header
                                    TrackHeader(
                                      track: track,
                                      height: _trackHeight,
                                      onMuteToggle: () =>
                                          widget.onTrackMuteToggle?.call(track.id),
                                      onSoloToggle: () =>
                                          widget.onTrackSoloToggle?.call(track.id),
                                      onArmToggle: () =>
                                          widget.onTrackArmToggle?.call(track.id),
                                      onMonitorToggle: () =>
                                          widget.onTrackMonitorToggle?.call(track.id),
                                      onFreezeToggle: () =>
                                          widget.onTrackFreezeToggle?.call(track.id),
                                      onLockToggle: () =>
                                          widget.onTrackLockToggle?.call(track.id),
                                      onVolumeChange: (v) =>
                                          widget.onTrackVolumeChange
                                              ?.call(track.id, v),
                                      onPanChange: (p) =>
                                          widget.onTrackPanChange?.call(track.id, p),
                                      onClick: () =>
                                          widget.onTrackSelect?.call(track.id),
                                      onColorChange: (c) =>
                                          widget.onTrackColorChange
                                              ?.call(track.id, c),
                                      onBusChange: (b) =>
                                          widget.onTrackBusChange?.call(track.id, b),
                                      onRename: (n) =>
                                          widget.onTrackRename?.call(track.id, n),
                                      onDuplicate: () =>
                                          widget.onTrackDuplicate?.call(track.id),
                                      onDelete: () =>
                                          widget.onTrackDelete?.call(track.id),
                                      onContextMenu: (pos) =>
                                          widget.onTrackContextMenu?.call(track.id, pos),
                                    ),
                                    // Track lane
                                    Expanded(
                                      child: TrackLane(
                                        track: track,
                                        trackHeight: _trackHeight,
                                        clips: trackClips,
                                        crossfades: trackCrossfades,
                                        zoom: widget.zoom,
                                        scrollOffset: widget.scrollOffset,
                                        tempo: widget.tempo,
                                        timeSignatureNum: widget.timeSignatureNum,
                                        onClipSelect: (id) =>
                                            widget.onClipSelect?.call(id, false),
                                        onClipMove: widget.onClipMove,
                                        onClipGainChange: widget.onClipGainChange,
                                        onClipFadeChange: widget.onClipFadeChange,
                                        onClipResize: widget.onClipResize,
                                        onClipRename: widget.onClipRename,
                                        onClipSlipEdit: widget.onClipSlipEdit,
                                        onCrossfadeUpdate: widget.onCrossfadeUpdate,
                                        onCrossfadeDelete: widget.onCrossfadeDelete,
                                        snapEnabled: widget.snapEnabled,
                                        snapValue: widget.snapValue,
                                        allClips: widget.clips,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                          // Playhead
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
                                  cursor: SystemMouseCursors.resizeColumn,
                                  child: Container(
                                    width: 12,
                                    transform: Matrix4.translationValues(-6, 0, 0),
                                    child: Stack(
                                      alignment: Alignment.topCenter,
                                      children: [
                                        // Glow
                                        Container(
                                          width: _isDraggingPlayhead ? 4 : 2,
                                          color: ReelForgeTheme.accentRed
                                              .withValues(alpha: _isDraggingPlayhead ? 0.8 : 0.6),
                                        ),
                                        // Head
                                        CustomPaint(
                                          size: const Size(12, 10),
                                          painter: _PlayheadPainter(),
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
                                        style: const TextStyle(
                                          fontSize: 9,
                                          color: Colors.white,
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

                    // Drop overlay
                    if (_isDroppingFile)
                      Positioned.fill(
                        child: Container(
                          color: ReelForgeTheme.accentBlue.withValues(alpha: 0.1),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              decoration: BoxDecoration(
                                color: ReelForgeTheme.bgMid,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: ReelForgeTheme.accentBlue,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: ReelForgeTheme.accentBlue.withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.audio_file,
                                    size: 48,
                                    color: ReelForgeTheme.accentBlue,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Drop audio files here',
                                    style: ReelForgeTheme.body.copyWith(
                                      color: ReelForgeTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'WAV, MP3, FLAC, OGG, AIFF',
                                    style: ReelForgeTheme.bodySmall.copyWith(
                                      color: ReelForgeTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Drop position indicator
                    if (_isDroppingFile && _dropPosition != null)
                      Positioned(
                        left: _dropPosition!.dx - 1,
                        top: _rulerHeight,
                        bottom: 20,
                        child: Container(
                          width: 2,
                          color: ReelForgeTheme.accentBlue,
                        ),
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
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ReelForgeTheme.accentRed
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PlayheadPainter oldDelegate) => false;
}
