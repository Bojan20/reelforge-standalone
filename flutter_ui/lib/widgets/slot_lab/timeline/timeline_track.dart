// Timeline Track Widget — Single Audio Track Display
//
// Professional audio track with:
// - Waveform rendering (multi-LOD)
// - Region editing (drag, trim, fade)
// - Track controls (mute, solo, record arm)
// - Automation lanes

import 'package:flutter/material.dart';
import '../../../models/timeline/timeline_state.dart';
import '../../../models/timeline/audio_region.dart';
import 'timeline_waveform_painter.dart';

class TimelineTrackWidget extends StatelessWidget {
  final TimelineTrack track;
  final double duration;           // Total timeline duration
  final double zoom;
  final double canvasWidth;
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final VoidCallback? onRecordArmToggle;
  final Function(String regionId)? onRegionSelected;
  final Function(String regionId, double newStartTime)? onRegionMoved;

  const TimelineTrackWidget({
    super.key,
    required this.track,
    required this.duration,
    required this.zoom,
    required this.canvasWidth,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onRecordArmToggle,
    this.onRegionSelected,
    this.onRegionMoved,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Row(
        children: [
          // Track header (fixed 120px)
          _buildTrackHeader(),

          // Track content (regions)
          Expanded(
            child: SizedBox(
              width: canvasWidth,
              child: Stack(
                children: track.regions.map((region) {
                  return _buildRegion(region);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Track header (fixed left panel)
  Widget _buildTrackHeader() {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A22),
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Track name
          Text(
            track.name,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          // M/S/R buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMuteButton(),
              const SizedBox(width: 2),
              _buildSoloButton(),
              const SizedBox(width: 2),
              _buildRecordArmButton(),
            ],
          ),

          // Volume/Pan indicators
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${track.volume.toStringAsFixed(1)}',
                style: const TextStyle(fontSize: 9, color: Colors.white54),
              ),
              const SizedBox(width: 4),
              Text(
                track.pan == 0 ? 'C' : (track.pan < 0 ? 'L${(-track.pan * 100).toInt()}' : 'R${(track.pan * 100).toInt()}'),
                style: const TextStyle(fontSize: 9, color: Colors.white54),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMuteButton() {
    return InkWell(
      onTap: onMuteToggle,
      child: Container(
        width: 20,
        height: 16,
        decoration: BoxDecoration(
          color: track.isMuted ? const Color(0xFFFF9040) : const Color(0xFF242430),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: track.isMuted ? const Color(0xFFFF9040) : Colors.white.withOpacity(0.3),
          ),
        ),
        child: const Center(
          child: Text(
            'M',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildSoloButton() {
    return InkWell(
      onTap: onSoloToggle,
      child: Container(
        width: 20,
        height: 16,
        decoration: BoxDecoration(
          color: track.isSoloed ? const Color(0xFFFFFF40) : const Color(0xFF242430),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: track.isSoloed ? const Color(0xFFFFFF40) : Colors.white.withOpacity(0.3),
          ),
        ),
        child: Center(
          child: Text(
            'S',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: track.isSoloed ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordArmButton() {
    return InkWell(
      onTap: onRecordArmToggle,
      child: Container(
        width: 20,
        height: 16,
        decoration: BoxDecoration(
          color: track.isRecordArmed ? const Color(0xFFFF4060) : const Color(0xFF242430),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: track.isRecordArmed ? const Color(0xFFFF4060) : Colors.white.withOpacity(0.3),
          ),
        ),
        child: const Center(
          child: Text(
            'R',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
    );
  }

  /// Build audio region
  Widget _buildRegion(AudioRegion region) {
    final leftPos = (region.startTime / duration) * canvasWidth;
    final width = (region.duration / duration) * canvasWidth;

    return Positioned(
      left: leftPos,
      top: 10,
      width: width,
      height: 60,
      child: GestureDetector(
        onTap: () => onRegionSelected?.call(region.id),
        child: Container(
          decoration: BoxDecoration(
            color: region.isSelected
                ? const Color(0xFFFF9040).withOpacity(0.1)
                : Colors.transparent,
            border: Border.all(
              color: region.isSelected ? const Color(0xFFFF9040) : const Color(0xFF4A9EFF),
              width: region.isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                // Waveform
                CustomPaint(
                  size: Size(width, 60),
                  painter: TimelineWaveformPainter(
                    waveformData: region.waveformData,
                    zoom: zoom,
                    isSelected: region.isSelected,
                    isMuted: region.isMuted || track.isMuted,
                    trimStart: region.trimStart,
                    trimEnd: region.trimEnd,
                  ),
                ),

                // Fade in overlay
                if (region.fadeInMs > 0)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: (region.fadeInMs / 1000.0 / duration) * canvasWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withOpacity(0.5),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: CustomPaint(
                        painter: _FadeCurvePainter(
                          curve: region.fadeInCurve,
                          isReversed: false,
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                    ),
                  ),

                // Fade out overlay
                if (region.fadeOutMs > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: (region.fadeOutMs / 1000.0 / duration) * canvasWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.5),
                          ],
                        ),
                      ),
                      child: CustomPaint(
                        painter: _FadeCurvePainter(
                          curve: region.fadeOutCurve,
                          isReversed: true,
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                    ),
                  ),

                // Region name (if no waveform)
                if (region.waveformData == null)
                  Center(
                    child: Text(
                      region.audioPath.split('/').last,
                      style: const TextStyle(fontSize: 9, color: Colors.white54),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fade curve painter (visual curve line)
class _FadeCurvePainter extends CustomPainter {
  final FadeCurve curve;
  final bool isReversed;
  final Color color;

  const _FadeCurvePainter({
    required this.curve,
    required this.isReversed,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final path = Path();

    // Draw fade curve
    for (int x = 0; x < size.width.toInt(); x++) {
      final t = x / size.width;
      final gain = _applyCurve(isReversed ? 1 - t : t, curve);
      final y = size.height * (1 - gain);

      if (x == 0) {
        path.moveTo(x.toDouble(), y);
      } else {
        path.lineTo(x.toDouble(), y);
      }
    }

    canvas.drawPath(path, paint);
  }

  double _applyCurve(double t, FadeCurve curve) {
    switch (curve) {
      case FadeCurve.linear:
        return t;
      case FadeCurve.exponential:
        return t * t;
      case FadeCurve.logarithmic:
        return t > 0 ? t : 0.0; // Simplified
      case FadeCurve.sCurve:
        return t * t * (3 - 2 * t);
      case FadeCurve.equalPower:
        return t; // Simplified for visualization
    }
  }

  @override
  bool shouldRepaint(_FadeCurvePainter oldDelegate) {
    return oldDelegate.curve != curve ||
        oldDelegate.isReversed != isReversed ||
        oldDelegate.color != color;
  }
}
