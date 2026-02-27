/// DAW Timeline Overview Panel
///
/// Compact timeline visualization showing:
/// - Track list with mute/solo/armed indicators
/// - Real clip positions from timeline data
/// - Live playhead indicator
/// - Click-to-seek in overview
/// - Track color coding matching main timeline
library;

import 'package:flutter/material.dart';
import '../../lower_zone_types.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LIGHTWEIGHT DATA MODELS (avoid importing heavy timeline_models.dart)
// ═══════════════════════════════════════════════════════════════════════════

/// Lightweight track info for overview display
class TimelineOverviewTrack {
  final String id;
  final String name;
  final Color color;
  final bool muted;
  final bool soloed;
  final bool armed;
  final bool isFolder;
  final bool isBus;
  final bool isAux;

  const TimelineOverviewTrack({
    required this.id,
    required this.name,
    required this.color,
    this.muted = false,
    this.soloed = false,
    this.armed = false,
    this.isFolder = false,
    this.isBus = false,
    this.isAux = false,
  });
}

/// Lightweight clip info for overview display
class TimelineOverviewClip {
  final String trackId;
  final double startTime;
  final double duration;
  final Color? color;
  final bool muted;
  final bool selected;

  const TimelineOverviewClip({
    required this.trackId,
    required this.startTime,
    required this.duration,
    this.color,
    this.muted = false,
    this.selected = false,
  });

  double get endTime => startTime + duration;
}

// ═══════════════════════════════════════════════════════════════════════════
// TIMELINE OVERVIEW PANEL
// ═══════════════════════════════════════════════════════════════════════════

class TimelineOverviewPanel extends StatelessWidget {
  final List<TimelineOverviewTrack> tracks;
  final List<TimelineOverviewClip> clips;
  final double playheadPosition;
  final double totalDuration;
  final ValueChanged<double>? onSeek;

  const TimelineOverviewPanel({
    super.key,
    this.tracks = const [],
    this.clips = const [],
    this.playheadPosition = 0,
    this.totalDuration = 120,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          Expanded(
            child: tracks.isEmpty
                ? _buildEmptyState()
                : Row(
                    children: [
                      SizedBox(
                        width: 130,
                        child: _buildTrackList(),
                      ),
                      const SizedBox(width: 1),
                      Expanded(child: _buildTimelineCanvas()),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final selectedCount = clips.where((c) => c.selected).length;
    return Row(
      children: [
        const Icon(Icons.view_timeline, size: 14, color: LowerZoneColors.dawAccent),
        const SizedBox(width: 6),
        const Text(
          'TIMELINE OVERVIEW',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.dawAccent,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        // Stats
        Text(
          '${tracks.length} tracks • ${clips.length} clips',
          style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
        ),
        if (selectedCount > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: LowerZoneColors.dawAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '$selectedCount sel',
              style: const TextStyle(fontSize: 8, color: LowerZoneColors.dawAccent),
            ),
          ),
        ],
      ],
    );
  }

  // ─── Empty State ──────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Container(
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_timeline, size: 32, color: LowerZoneColors.textMuted),
            SizedBox(height: 8),
            Text(
              'No tracks in timeline',
              style: TextStyle(fontSize: 12, color: LowerZoneColors.textMuted),
            ),
            SizedBox(height: 4),
            Text(
              'Add tracks to see the overview',
              style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Track List (left panel) ──────────────────────────────────────────────

  Widget _buildTrackList() {
    return Container(
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          bottomLeft: Radius.circular(4),
        ),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(2),
        itemCount: tracks.length,
        itemBuilder: (context, index) => _buildTrackItem(tracks[index]),
      ),
    );
  }

  Widget _buildTrackItem(TimelineOverviewTrack track) {
    final icon = track.isFolder
        ? Icons.folder
        : track.isBus
            ? Icons.call_split
            : track.isAux
                ? Icons.call_merge
                : Icons.audiotrack;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      margin: const EdgeInsets.only(bottom: 1),
      decoration: BoxDecoration(
        color: track.armed ? const Color(0x22FF4040) : null,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: [
          // Color bar
          Container(
            width: 3,
            height: 12,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: track.muted ? LowerZoneColors.textMuted : track.color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Icon(icon, size: 10, color: track.muted ? LowerZoneColors.textMuted : track.color),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              track.name,
              style: TextStyle(
                fontSize: 9,
                color: track.muted
                    ? LowerZoneColors.textMuted
                    : LowerZoneColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Status indicators
          if (track.armed)
            const Padding(
              padding: EdgeInsets.only(left: 2),
              child: Icon(Icons.fiber_manual_record, size: 8, color: Color(0xFFFF4040)),
            ),
          if (track.muted)
            const Padding(
              padding: EdgeInsets.only(left: 2),
              child: Text('M', style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: Color(0xFFFF9040))),
            ),
          if (track.soloed)
            const Padding(
              padding: EdgeInsets.only(left: 2),
              child: Text('S', style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
            ),
        ],
      ),
    );
  }

  // ─── Timeline Canvas (right panel) ────────────────────────────────────────

  Widget _buildTimelineCanvas() {
    return Container(
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(3),
          bottomRight: Radius.circular(3),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              onTapDown: (details) {
                if (onSeek != null && totalDuration > 0) {
                  final fraction = details.localPosition.dx / constraints.maxWidth;
                  onSeek!(fraction.clamp(0, 1) * totalDuration);
                }
              },
              child: CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _TimelineOverviewPainter(
                  tracks: tracks,
                  clips: clips,
                  playheadPosition: playheadPosition,
                  totalDuration: totalDuration,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TIMELINE OVERVIEW PAINTER — Real Data
// ═══════════════════════════════════════════════════════════════════════════

class _TimelineOverviewPainter extends CustomPainter {
  final List<TimelineOverviewTrack> tracks;
  final List<TimelineOverviewClip> clips;
  final double playheadPosition;
  final double totalDuration;

  const _TimelineOverviewPainter({
    required this.tracks,
    required this.clips,
    required this.playheadPosition,
    required this.totalDuration,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (tracks.isEmpty || totalDuration <= 0) return;

    final trackCount = tracks.length;
    final trackHeight = size.height / trackCount;
    final effectiveDuration = _effectiveDuration();

    // Build track index map for O(1) lookup
    final trackIndexMap = <String, int>{};
    for (int i = 0; i < tracks.length; i++) {
      trackIndexMap[tracks[i].id] = i;
    }

    // ─── Grid lines (time markers) ──────────────────────────────────
    _drawGrid(canvas, size, effectiveDuration, trackHeight, trackCount);

    // ─── Clips ──────────────────────────────────────────────────────
    for (final clip in clips) {
      final trackIndex = trackIndexMap[clip.trackId];
      if (trackIndex == null) continue;

      final track = tracks[trackIndex];
      final x1 = (clip.startTime / effectiveDuration) * size.width;
      final x2 = (clip.endTime / effectiveDuration) * size.width;
      final y = trackIndex * trackHeight;

      // Skip clips outside visible area
      if (x2 < 0 || x1 > size.width) continue;

      final clipColor = clip.color ?? track.color;
      final isMuted = clip.muted || track.muted;

      final rect = Rect.fromLTRB(
        x1.clamp(0, size.width) + 1,
        y + 2,
        x2.clamp(0, size.width) - 1,
        y + trackHeight - 2,
      );

      // Skip too-narrow clips
      if (rect.width < 2) continue;

      // Fill
      final fillPaint = Paint()
        ..color = isMuted
            ? clipColor.withValues(alpha: 0.15)
            : clip.selected
                ? clipColor.withValues(alpha: 0.5)
                : clipColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        fillPaint,
      );

      // Border
      final borderPaint = Paint()
        ..color = isMuted
            ? clipColor.withValues(alpha: 0.3)
            : clip.selected
                ? clipColor
                : clipColor.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = clip.selected ? 1.5 : 0.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        borderPaint,
      );
    }

    // ─── Playhead ───────────────────────────────────────────────────
    if (playheadPosition >= 0) {
      final playheadX = (playheadPosition / effectiveDuration) * size.width;
      if (playheadX >= 0 && playheadX <= size.width) {
        // Playhead line
        final playheadPaint = Paint()
          ..color = const Color(0xFFFF4040)
          ..strokeWidth = 1.5;
        canvas.drawLine(
          Offset(playheadX, 0),
          Offset(playheadX, size.height),
          playheadPaint,
        );

        // Playhead triangle at top
        final trianglePath = Path()
          ..moveTo(playheadX - 4, 0)
          ..lineTo(playheadX + 4, 0)
          ..lineTo(playheadX, 5)
          ..close();
        canvas.drawPath(
          trianglePath,
          Paint()..color = const Color(0xFFFF4040),
        );
      }
    }
  }

  double _effectiveDuration() {
    // Use actual content end or totalDuration, whichever is larger
    double maxEnd = totalDuration;
    for (final clip in clips) {
      if (clip.endTime > maxEnd) maxEnd = clip.endTime;
    }
    // Add small padding
    return maxEnd * 1.05;
  }

  void _drawGrid(Canvas canvas, Size size, double duration, double trackHeight, int trackCount) {
    final linePaint = Paint()
      ..color = LowerZoneColors.border.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;

    // Horizontal track separators
    for (int i = 1; i < trackCount; i++) {
      final y = i * trackHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Vertical time markers — choose interval based on duration
    double interval;
    if (duration <= 30) {
      interval = 5; // Every 5 seconds
    } else if (duration <= 120) {
      interval = 10; // Every 10 seconds
    } else if (duration <= 600) {
      interval = 30; // Every 30 seconds
    } else {
      interval = 60; // Every minute
    }

    final gridPaint = Paint()
      ..color = LowerZoneColors.border.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    final majorGridPaint = Paint()
      ..color = LowerZoneColors.border.withValues(alpha: 0.6)
      ..strokeWidth = 0.5;

    for (double t = 0; t <= duration; t += interval) {
      final x = (t / duration) * size.width;
      final isMajor = (t % (interval * 4)) < 0.001;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        isMajor ? majorGridPaint : gridPaint,
      );

      // Time label at top
      if (size.width > 200 && x + 30 < size.width) {
        final label = _formatTime(t);
        final textPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              fontSize: 7,
              color: LowerZoneColors.textMuted.withValues(alpha: 0.7),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, Offset(x + 2, 1));
      }
    }
  }

  String _formatTime(double seconds) {
    final m = (seconds / 60).floor();
    final s = (seconds % 60).floor();
    if (m > 0) return '${m}m${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  @override
  bool shouldRepaint(covariant _TimelineOverviewPainter oldDelegate) =>
      oldDelegate.playheadPosition != playheadPosition ||
      oldDelegate.totalDuration != totalDuration ||
      oldDelegate.tracks.length != tracks.length ||
      oldDelegate.clips.length != clips.length ||
      !_listsEqual(oldDelegate.clips, clips);

  bool _listsEqual(List<TimelineOverviewClip> a, List<TimelineOverviewClip> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].startTime != b[i].startTime ||
          a[i].duration != b[i].duration ||
          a[i].trackId != b[i].trackId ||
          a[i].selected != b[i].selected ||
          a[i].muted != b[i].muted) return false;
    }
    return true;
  }
}
