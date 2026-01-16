/// Track Lane Widget
///
/// Single track lane with:
/// - Grid lines
/// - Clips (stereo handled by ClipWidget based on trackHeight)
/// - Crossfades
/// - Drop zone for audio
/// - Theme-aware: Glass/Classic mode support

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/timeline_models.dart';
import '../../providers/midi_provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../providers/theme_mode_provider.dart';
import 'grid_lines.dart';
import '../glass/glass_clip_widget.dart';
import '../midi/midi_clip_widget.dart';
import 'crossfade_overlay.dart';

class TrackLane extends StatefulWidget {
  final TimelineTrack track;
  final double trackHeight;
  final List<TimelineClip> clips;
  final List<Crossfade> crossfades;
  final double zoom;
  final double scrollOffset;
  final double tempo;
  final int timeSignatureNum;
  final ValueChanged<String>? onClipSelect;
  final void Function(String clipId, double newStartTime)? onClipMove;
  /// Called during cross-track drag with clip ID, new start time, and Y delta
  final void Function(String clipId, double newStartTime, double verticalDelta)? onClipCrossTrackDrag;
  /// Called when cross-track drag ends - determines final track placement
  final void Function(String clipId)? onClipCrossTrackDragEnd;
  /// Smooth drag callbacks (Cubase-style ghost preview)
  final void Function(String clipId, Offset globalPosition, Offset localPosition)? onClipDragStart;
  final void Function(String clipId, Offset globalPosition)? onClipDragUpdate;
  final void Function(String clipId, Offset globalPosition)? onClipDragEnd;
  final void Function(String clipId, double gain)? onClipGainChange;
  final void Function(String clipId, double fadeIn, double fadeOut)?
      onClipFadeChange;
  final void Function(
    String clipId,
    double newStartTime,
    double newDuration,
    double? newOffset,
  )? onClipResize;
  /// Called when clip resize drag ends - for final FFI commit
  final void Function(String clipId)? onClipResizeEnd;
  final void Function(String clipId, String newName)? onClipRename;
  final void Function(String clipId, double newSourceOffset)? onClipSlipEdit;
  final void Function(String clipId)? onClipOpenAudioEditor;
  final void Function(String crossfadeId, double duration)? onCrossfadeUpdate;
  /// Full crossfade update with startTime and duration
  final void Function(String crossfadeId, double startTime, double duration)? onCrossfadeFullUpdate;
  final void Function(String crossfadeId)? onCrossfadeDelete;
  final ValueChanged<double>? onPlayheadMove;
  final bool snapEnabled;
  final double snapValue;
  final List<TimelineClip> allClips;
  /// MIDI clips for MIDI/Instrument tracks
  final List<MidiClip> midiClips;
  /// Selected MIDI clip ID
  final String? selectedMidiClipId;
  /// MIDI clip callbacks
  final ValueChanged<String>? onMidiClipSelect;
  final void Function(String clipId)? onMidiClipDoubleTap;
  final void Function(String clipId, double newStartTime)? onMidiClipMove;
  final void Function(String clipId, double newStartTime, double newDuration)? onMidiClipResize;

  const TrackLane({
    super.key,
    required this.track,
    required this.trackHeight,
    required this.clips,
    this.crossfades = const [],
    required this.zoom,
    required this.scrollOffset,
    this.tempo = 120,
    this.timeSignatureNum = 4,
    this.onClipSelect,
    this.onClipMove,
    this.onClipCrossTrackDrag,
    this.onClipCrossTrackDragEnd,
    this.onClipDragStart,
    this.onClipDragUpdate,
    this.onClipDragEnd,
    this.onClipGainChange,
    this.onClipFadeChange,
    this.onClipResize,
    this.onClipResizeEnd,
    this.onClipRename,
    this.onClipSlipEdit,
    this.onClipOpenAudioEditor,
    this.onCrossfadeUpdate,
    this.onCrossfadeFullUpdate,
    this.onCrossfadeDelete,
    this.onPlayheadMove,
    this.snapEnabled = false,
    this.snapValue = 1,
    this.allClips = const [],
    this.midiClips = const [],
    this.selectedMidiClipId,
    this.onMidiClipSelect,
    this.onMidiClipDoubleTap,
    this.onMidiClipMove,
    this.onMidiClipResize,
  });

  @override
  State<TrackLane> createState() => _TrackLaneState();
}

class _TrackLaneState extends State<TrackLane> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Keep track state alive when scrolling

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    // Use track color for lane background (Logic Pro style)
    // Audio tracks: subtle blue tint, MIDI: green tint, etc.
    final trackColor = widget.track.color;

    // Build decoration based on theme mode
    BoxDecoration decoration;
    if (isGlassMode) {
      // Glass mode: subtle gradient with track color tint
      decoration = BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            trackColor.withValues(alpha: 0.08),
            Colors.black.withValues(alpha: 0.04),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      );
    } else {
      // Classic mode: solid color blend
      decoration = BoxDecoration(
        color: Color.lerp(FluxForgeTheme.bgDeep, trackColor, 0.18),
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      );
    }

    Widget content = Container(
      height: widget.trackHeight,
      decoration: decoration,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // PERFORMANCE: Grid lines with RepaintBoundary - prevents rebuild on clip changes
              // Positioned.fill wraps RepaintBoundary because GridLines is a Stack child
              Positioned.fill(
                child: RepaintBoundary(
                  child: GridLines(
                    width: constraints.maxWidth,
                    height: widget.trackHeight,
                    zoom: widget.zoom,
                    scrollOffset: widget.scrollOffset,
                    tempo: widget.tempo,
                    timeSignatureNum: widget.timeSignatureNum,
                  ),
                ),
              ),

              // Clips - ClipWidget handles stereo display internally based on trackHeight
              // (stereo split shown when trackHeight > 80px)
              ...widget.clips.map((clip) => ThemeAwareClipWidget(
                      key: ValueKey('${clip.id}_${clip.color?.value ?? 0}'),
                      clip: clip,
                      zoom: widget.zoom,
                      scrollOffset: widget.scrollOffset,
                      trackHeight: widget.trackHeight,
                      onSelect: (multi) => widget.onClipSelect?.call(clip.id),
                      onMove: (newStart) =>
                          widget.onClipMove?.call(clip.id, newStart),
                      onCrossTrackDrag: (newStart, verticalDelta) =>
                          widget.onClipCrossTrackDrag?.call(clip.id, newStart, verticalDelta),
                      onCrossTrackDragEnd: () =>
                          widget.onClipCrossTrackDragEnd?.call(clip.id),
                      // Smooth drag callbacks (Cubase-style)
                      onDragStart: (globalPos, localPos) =>
                          widget.onClipDragStart?.call(clip.id, globalPos, localPos),
                      onDragUpdate: (globalPos) =>
                          widget.onClipDragUpdate?.call(clip.id, globalPos),
                      onDragEnd: (globalPos) =>
                          widget.onClipDragEnd?.call(clip.id, globalPos),
                      onGainChange: (gain) =>
                          widget.onClipGainChange?.call(clip.id, gain),
                      onFadeChange: (fadeIn, fadeOut) =>
                          widget.onClipFadeChange?.call(clip.id, fadeIn, fadeOut),
                      onResize: (newStart, newDur, newOffset) =>
                          widget.onClipResize
                              ?.call(clip.id, newStart, newDur, newOffset),
                      onResizeEnd: () => widget.onClipResizeEnd?.call(clip.id),
                      onRename: (name) => widget.onClipRename?.call(clip.id, name),
                      onSlipEdit: (offset) =>
                          widget.onClipSlipEdit?.call(clip.id, offset),
                      onOpenAudioEditor: () =>
                          widget.onClipOpenAudioEditor?.call(clip.id),
                      onPlayheadMove: widget.onPlayheadMove,
                      snapEnabled: widget.snapEnabled,
                      snapValue: widget.snapValue,
                      tempo: widget.tempo,
                      allClips: widget.allClips,
                    )),

              // Crossfades
              ...widget.crossfades.map((xfade) => CrossfadeOverlay(
                    key: ValueKey(xfade.id),
                    crossfade: xfade,
                    zoom: widget.zoom,
                    scrollOffset: widget.scrollOffset,
                    height: widget.trackHeight,
                    onUpdate: (duration) =>
                        widget.onCrossfadeUpdate?.call(xfade.id, duration),
                    onFullUpdate: (startTime, duration) =>
                        widget.onCrossfadeFullUpdate?.call(xfade.id, startTime, duration),
                    onDelete: () => widget.onCrossfadeDelete?.call(xfade.id),
                  )),

              // MIDI clips (for MIDI/Instrument tracks)
              ...widget.midiClips.map((midiClip) => MidiClipWidget(
                    key: ValueKey('midi_${midiClip.id}'),
                    clip: midiClip,
                    zoom: widget.zoom,
                    scrollOffset: widget.scrollOffset,
                    trackHeight: widget.trackHeight,
                    isSelected: midiClip.id == widget.selectedMidiClipId,
                    onTap: () => widget.onMidiClipSelect?.call(midiClip.id),
                    onDoubleTap: () => widget.onMidiClipDoubleTap?.call(midiClip.id),
                    onMove: (newStart) => widget.onMidiClipMove?.call(midiClip.id, newStart),
                    onResize: (newStart, newDur) =>
                        widget.onMidiClipResize?.call(midiClip.id, newStart, newDur),
                  )),
            ],
          );
        },
      ),
    );

    // Wrap with Glass blur in Glass mode
    if (isGlassMode) {
      content = ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: content,
        ),
      );
    }

    return content;
  }
}
