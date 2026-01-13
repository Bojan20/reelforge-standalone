/// Track Lane Widget
///
/// Single track lane with:
/// - Grid lines
/// - Clips (stereo split when track is expanded)
/// - Crossfades
/// - Drop zone for audio

import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../models/timeline_models.dart';
import '../../theme/fluxforge_theme.dart';
import 'grid_lines.dart';
import 'clip_widget.dart';
import 'crossfade_overlay.dart';

/// Height threshold for stereo waveform display (Logic Pro style)
const double kStereoDisplayThreshold = 160.0;

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
  final void Function(String clipId, String newName)? onClipRename;
  final void Function(String clipId, double newSourceOffset)? onClipSlipEdit;
  final void Function(String clipId)? onClipOpenAudioEditor;
  final void Function(String crossfadeId, double duration)? onCrossfadeUpdate;
  final void Function(String crossfadeId)? onCrossfadeDelete;
  final ValueChanged<double>? onPlayheadMove;
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
    this.onClipCrossTrackDrag,
    this.onClipCrossTrackDragEnd,
    this.onClipDragStart,
    this.onClipDragUpdate,
    this.onClipDragEnd,
    this.onClipGainChange,
    this.onClipFadeChange,
    this.onClipResize,
    this.onClipRename,
    this.onClipSlipEdit,
    this.onClipOpenAudioEditor,
    this.onCrossfadeUpdate,
    this.onCrossfadeDelete,
    this.onPlayheadMove,
    this.snapEnabled = false,
    this.snapValue = 1,
    this.allClips = const [],
  });

  @override
  State<TrackLane> createState() => _TrackLaneState();
}

class _TrackLaneState extends State<TrackLane> with AutomaticKeepAliveClientMixin {
  /// Check if we should display stereo split view (height-based, not content-based)
  bool get _isStereoMode => widget.trackHeight >= kStereoDisplayThreshold;

  /// Check if track has any clips with waveform data
  bool get _hasWaveformContent => widget.clips.any((c) => c.waveform != null);

  @override
  bool get wantKeepAlive => true; // Keep track state alive when scrolling

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    // Use track color for lane background (Logic Pro style)
    // Audio tracks: subtle blue tint, MIDI: green tint, etc.
    final trackColor = widget.track.color;
    // Show stereo split when track is tall enough and has waveform content
    final showStereoSplit = _isStereoMode && _hasWaveformContent;

    return Container(
      height: widget.trackHeight,
      decoration: BoxDecoration(
        // Blend track color with dark background (Logic Pro style visible tint)
        color: Color.lerp(FluxForgeTheme.bgDeep, trackColor, 0.18),
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate lane heights for stereo split
          final halfHeight = widget.trackHeight / 2;
          final clipHeightMono = widget.trackHeight;
          final clipHeightStereo = halfHeight - 2; // -2 for center divider

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

              // Stereo mode: show L/R labels and center divider
              if (showStereoSplit) ...[
                // Center divider line
                Positioned(
                  left: 0,
                  right: 0,
                  top: halfHeight - 0.5,
                  height: 1,
                  child: Container(
                    color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5),
                  ),
                ),
                // L channel label
                Positioned(
                  left: 4,
                  top: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgVoid.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      'L',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: FluxForgeTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
                // R channel label
                Positioned(
                  left: 4,
                  top: halfHeight + 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgVoid.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      'R',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: FluxForgeTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],

              // Clips - in stereo mode, render each clip twice (L/R)
              if (showStereoSplit)
                ...widget.clips.expand((clip) => [
                  // LEFT CHANNEL (top half)
                  _StereoClipChannel(
                    key: ValueKey('${clip.id}_${clip.color?.value ?? 0}_L'),
                    clip: clip,
                    zoom: widget.zoom,
                    scrollOffset: widget.scrollOffset,
                    trackHeight: clipHeightStereo,
                    topOffset: 1,
                    isLeftChannel: true,
                    onSelect: (multi) => widget.onClipSelect?.call(clip.id),
                  ),
                  // RIGHT CHANNEL (bottom half)
                  _StereoClipChannel(
                    key: ValueKey('${clip.id}_${clip.color?.value ?? 0}_R'),
                    clip: clip,
                    zoom: widget.zoom,
                    scrollOffset: widget.scrollOffset,
                    trackHeight: clipHeightStereo,
                    topOffset: halfHeight + 1,
                    isLeftChannel: false,
                    onSelect: (multi) => widget.onClipSelect?.call(clip.id),
                  ),
                ])
              else
                // Normal mode - single clip (Positioned must be direct child of Stack)
                ...widget.clips.map((clip) => ClipWidget(
                      key: ValueKey('${clip.id}_${clip.color?.value ?? 0}'),
                      clip: clip,
                      zoom: widget.zoom,
                      scrollOffset: widget.scrollOffset,
                      trackHeight: clipHeightMono,
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
                    onDelete: () => widget.onCrossfadeDelete?.call(xfade.id),
                  )),
            ],
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// STEREO CLIP CHANNEL WIDGET
// ════════════════════════════════════════════════════════════════════════════

/// Renders a single channel (L or R) of a stereo clip for split view
class _StereoClipChannel extends StatelessWidget {
  final TimelineClip clip;
  final double zoom;
  final double scrollOffset;
  final double trackHeight;
  final double topOffset;
  final bool isLeftChannel;
  final ValueChanged<bool>? onSelect;

  const _StereoClipChannel({
    super.key,
    required this.clip,
    required this.zoom,
    required this.scrollOffset,
    required this.trackHeight,
    required this.topOffset,
    required this.isLeftChannel,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final x = (clip.startTime - scrollOffset) * zoom;
    final width = clip.duration * zoom;

    // Skip if not visible
    if (x + width < 0 || x > 2000) return const SizedBox.shrink();

    final clipHeight = trackHeight - 2;
    const clipColor = Color(0xFF4A90C2); // Logic Pro audio region blue

    // Select waveform for this channel
    final waveform = isLeftChannel
        ? clip.waveform
        : (clip.waveformRight ?? clip.waveform);

    return Positioned(
      left: x,
      top: topOffset,
      width: width.clamp(4, double.infinity),
      height: clipHeight,
      child: GestureDetector(
        onTap: () => onSelect?.call(false),
        child: Container(
          decoration: BoxDecoration(
            color: clipColor,
            borderRadius: BorderRadius.circular(3),
            border: clip.selected
                ? Border.all(color: Colors.white, width: 1.5)
                : Border.all(color: clipColor.withValues(alpha: 0.6), width: 0.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: waveform != null
                ? CustomPaint(
                    painter: _SingleChannelWaveformPainter(
                      waveform: waveform,
                      gain: clip.gain,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SINGLE CHANNEL WAVEFORM PAINTER
// ════════════════════════════════════════════════════════════════════════════

/// Paints a single-channel waveform (Logic Pro style white on blue)
class _SingleChannelWaveformPainter extends CustomPainter {
  final Float32List waveform;
  final double gain;

  _SingleChannelWaveformPainter({
    required this.waveform,
    this.gain = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty || size.width <= 0 || size.height <= 0) return;

    final centerY = size.height / 2;
    final amplitude = centerY * 0.85 * gain;
    final samplesPerPixel = waveform.length / size.width;

    // Logic Pro style: clean white filled waveform
    final fillPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = Path();
    final bottomPath = <double>[];

    for (double x = 0; x < size.width; x++) {
      final startIdx = (x * samplesPerPixel).floor().clamp(0, waveform.length - 1);
      final endIdx = ((x + 1) * samplesPerPixel).ceil().clamp(startIdx + 1, waveform.length);

      double minVal = waveform[startIdx];
      double maxVal = waveform[startIdx];

      for (int i = startIdx; i < endIdx; i++) {
        final s = waveform[i];
        if (s < minVal) minVal = s;
        if (s > maxVal) maxVal = s;
      }

      final yTop = centerY - maxVal * amplitude;
      final yBottom = centerY - minVal * amplitude;

      if (x == 0) {
        path.moveTo(x, yTop);
      } else {
        path.lineTo(x, yTop);
      }
      bottomPath.add(yBottom);
    }

    // Close path with bottom contour
    for (int i = bottomPath.length - 1; i >= 0; i--) {
      path.lineTo(i.toDouble(), bottomPath[i]);
    }
    path.close();

    canvas.drawPath(path, fillPaint);

    // Draw outline
    final outlinePath = Path();
    for (double x = 0; x < size.width; x++) {
      final startIdx = (x * samplesPerPixel).floor().clamp(0, waveform.length - 1);
      final endIdx = ((x + 1) * samplesPerPixel).ceil().clamp(startIdx + 1, waveform.length);

      double maxAbs = 0;
      for (int i = startIdx; i < endIdx; i++) {
        final s = waveform[i].abs();
        if (s > maxAbs) maxAbs = s;
      }

      final yTop = centerY - maxAbs * amplitude;
      if (x == 0) {
        outlinePath.moveTo(x, yTop);
      } else {
        outlinePath.lineTo(x, yTop);
      }
    }
    // Mirror for bottom
    for (double x = size.width - 1; x >= 0; x--) {
      final startIdx = (x * samplesPerPixel).floor().clamp(0, waveform.length - 1);
      final endIdx = ((x + 1) * samplesPerPixel).ceil().clamp(startIdx + 1, waveform.length);

      double maxAbs = 0;
      for (int i = startIdx; i < endIdx; i++) {
        final s = waveform[i].abs();
        if (s > maxAbs) maxAbs = s;
      }

      final yBottom = centerY + maxAbs * amplitude;
      outlinePath.lineTo(x, yBottom);
    }
    outlinePath.close();

    canvas.drawPath(outlinePath, linePaint);
  }

  @override
  bool shouldRepaint(_SingleChannelWaveformPainter oldDelegate) =>
      waveform != oldDelegate.waveform || gain != oldDelegate.gain;
}
