/// Track Lane Widget
///
/// Single track lane with:
/// - Grid lines
/// - Clips
/// - Crossfades
/// - Drop zone for audio

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';
import '../../models/timeline_models.dart';
import 'grid_lines.dart';
import 'clip_widget.dart';
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
  final void Function(String clipId, double gain)? onClipGainChange;
  final void Function(String clipId, double fadeIn, double fadeOut)?
      onClipFadeChange;
  final void Function(
    String clipId,
    double newStartTime,
    double newDuration,
    double? newOffset,
  )? onClipResize;
  final void Function(String clipId, String newName)? onClipRename;
  final void Function(String clipId, double newSourceOffset)? onClipSlipEdit;
  final void Function(String crossfadeId, double duration)? onCrossfadeUpdate;
  final void Function(String crossfadeId)? onCrossfadeDelete;
  final bool snapEnabled;
  final double snapValue;
  final List<TimelineClip> allClips;

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
    this.onClipGainChange,
    this.onClipFadeChange,
    this.onClipResize,
    this.onClipRename,
    this.onClipSlipEdit,
    this.onCrossfadeUpdate,
    this.onCrossfadeDelete,
    this.snapEnabled = false,
    this.snapValue = 1,
    this.allClips = const [],
  });

  @override
  State<TrackLane> createState() => _TrackLaneState();
}

class _TrackLaneState extends State<TrackLane> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.trackHeight,
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeep.withValues(alpha: 0.5),
        border: const Border(
          bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // Grid lines
              GridLines(
                width: constraints.maxWidth,
                height: widget.trackHeight,
                zoom: widget.zoom,
                scrollOffset: widget.scrollOffset,
                tempo: widget.tempo,
                timeSignatureNum: widget.timeSignatureNum,
              ),

              // Clips
              ...widget.clips.map((clip) => ClipWidget(
                    key: ValueKey(clip.id),
                    clip: clip,
                    zoom: widget.zoom,
                    scrollOffset: widget.scrollOffset,
                    trackHeight: widget.trackHeight,
                    onSelect: (multi) => widget.onClipSelect?.call(clip.id),
                    onMove: (newStart) =>
                        widget.onClipMove?.call(clip.id, newStart),
                    onGainChange: (gain) =>
                        widget.onClipGainChange?.call(clip.id, gain),
                    onFadeChange: (fadeIn, fadeOut) =>
                        widget.onClipFadeChange?.call(clip.id, fadeIn, fadeOut),
                    onResize: (newStart, newDur, newOffset) =>
                        widget.onClipResize
                            ?.call(clip.id, newStart, newDur, newOffset),
                    onRename: (name) => widget.onClipRename?.call(clip.id, name),
                    onSlipEdit: (offset) =>
                        widget.onClipSlipEdit?.call(clip.id, offset),
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
                    onDelete: () => widget.onCrossfadeDelete?.call(xfade.id),
                  )),
            ],
          );
        },
      ),
    );
  }
}
