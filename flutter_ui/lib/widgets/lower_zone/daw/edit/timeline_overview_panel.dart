/// DAW Timeline Overview Panel (P0.1 Extracted)
///
/// Compact timeline visualization showing:
/// - Track list with mute/solo indicators
/// - Timeline grid with clip positions
/// - Playhead indicator
/// - Connected to MixerProvider for real track data
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
/// Lines 1434-1619 + 4729-4812 (~268 LOC total)
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../lower_zone_types.dart';
import '../../../../providers/mixer_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TIMELINE OVERVIEW PANEL
// ═══════════════════════════════════════════════════════════════════════════

class TimelineOverviewPanel extends StatelessWidget {
  const TimelineOverviewPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('TIMELINE OVERVIEW', Icons.timeline),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                // Track list
                SizedBox(
                  width: 120,
                  child: _buildTrackList(context),
                ),
                const SizedBox(width: 8),
                // Timeline visualization
                Expanded(child: _buildTimelineVisualization()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── UI Builders ───────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: LowerZoneColors.dawAccent),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: LowerZoneColors.dawAccent,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildTrackList(BuildContext context) {
    // Try to get MixerProvider from context
    MixerProvider? mixerProvider;
    try {
      mixerProvider = context.watch<MixerProvider>();
    } catch (_) {
      // Provider not available
    }

    return Container(
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: ListView(
        padding: const EdgeInsets.all(4),
        children: [
          // Master channel (always shown)
          if (mixerProvider != null)
            _buildMixerTrackItem(mixerProvider.master, isMaster: true)
          else
            _buildTrackListItem('Master', Icons.speaker, true),

          // Divider
          if (mixerProvider != null && mixerProvider.channels.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Divider(height: 1, color: LowerZoneColors.border),
            ),

          // Audio channels from MixerProvider
          if (mixerProvider != null)
            ...mixerProvider.channels.map((ch) => _buildMixerTrackItem(ch))
          else ...[
            _buildTrackListItem('Track 1', Icons.audiotrack, false),
            _buildTrackListItem('Track 2', Icons.audiotrack, false),
          ],

          // Buses section
          if (mixerProvider != null && mixerProvider.buses.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                'BUSES',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            ...mixerProvider.buses.map((bus) => _buildMixerTrackItem(bus, isBus: true)),
          ],
        ],
      ),
    );
  }

  Widget _buildMixerTrackItem(MixerChannel channel, {bool isMaster = false, bool isBus = false}) {
    final icon = isMaster
        ? Icons.speaker
        : isBus
            ? Icons.call_split
            : Icons.audiotrack;

    final accentColor = isMaster
        ? LowerZoneColors.dawAccent
        : isBus
            ? const Color(0xFF9B59B6)
            : channel.color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isMaster ? accentColor.withValues(alpha: 0.1) : null,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          // Color indicator
          Container(
            width: 3,
            height: 12,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Icon(icon, size: 12, color: isMaster ? accentColor : LowerZoneColors.textMuted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              channel.name,
              style: TextStyle(
                fontSize: 9,
                color: isMaster ? accentColor : LowerZoneColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Mute indicator
          if (channel.muted)
            const Icon(Icons.volume_off, size: 10, color: LowerZoneColors.warning),
          // Solo indicator
          if (channel.soloed)
            const Icon(Icons.headphones, size: 10, color: LowerZoneColors.warning),
        ],
      ),
    );
  }

  Widget _buildTrackListItem(String name, IconData icon, bool isMaster) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isMaster ? LowerZoneColors.dawAccent.withValues(alpha: 0.1) : null,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: isMaster ? LowerZoneColors.dawAccent : LowerZoneColors.textMuted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 9,
                color: isMaster ? LowerZoneColors.dawAccent : LowerZoneColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineVisualization() {
    return Container(
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: const CustomPaint(
        painter: TimelineOverviewPainter(color: LowerZoneColors.dawAccent),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TIMELINE OVERVIEW PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class TimelineOverviewPainter extends CustomPainter {
  final Color color;

  const TimelineOverviewPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = LowerZoneColors.border
      ..strokeWidth = 1;

    // Draw timeline grid
    for (int i = 0; i < 8; i++) {
      final x = (i / 8) * size.width;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        linePaint,
      );
    }

    // Draw track lanes
    final trackHeight = size.height / 4;
    for (int i = 0; i < 4; i++) {
      final y = i * trackHeight;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        linePaint,
      );
    }

    // Draw sample clips
    const clips = [
      (0, 0.1, 0.4),
      (0, 0.5, 0.8),
      (1, 0.2, 0.6),
      (2, 0.0, 0.3),
      (2, 0.4, 0.9),
      (3, 0.3, 0.7),
    ];

    for (final (track, start, end) in clips) {
      final rect = Rect.fromLTRB(
        start * size.width + 2,
        track * trackHeight + 4,
        end * size.width - 2,
        (track + 1) * trackHeight - 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );

      // Clip border
      final borderPaint = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        borderPaint,
      );
    }

    // Draw playhead
    final playheadPaint = Paint()
      ..color = LowerZoneColors.error
      ..strokeWidth = 2;
    final playheadX = size.width * 0.35;
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      playheadPaint,
    );
  }

  @override
  bool shouldRepaint(covariant TimelineOverviewPainter oldDelegate) =>
      oldDelegate.color != color;
}
