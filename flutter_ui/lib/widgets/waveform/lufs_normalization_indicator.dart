/// LUFS Normalization Indicator
///
/// Visual overlay for waveforms showing LUFS normalization level.
/// Displays a horizontal line indicating the normalized target level.
///
/// Features:
/// - Horizontal line at normalized level
/// - dB label showing adjustment
/// - Color-coded (green=reducing, orange=boosting)
/// - Toggle on/off with AudioPlaybackService
///
/// Task: P1-02 LUFS Normalization Preview

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/audio_playback_service.dart';
import '../../theme/fluxforge_theme.dart';

/// Overlay widget showing LUFS normalization level on waveform
class LufsNormalizationIndicator extends StatelessWidget {
  /// Audio file path to show normalization for
  final String audioPath;

  /// Waveform height (to position the indicator correctly)
  final double waveformHeight;

  /// Whether to show the indicator (defaults to service state)
  final bool? forceShow;

  const LufsNormalizationIndicator({
    super.key,
    required this.audioPath,
    required this.waveformHeight,
    this.forceShow,
  });

  @override
  Widget build(BuildContext context) {
    final service = AudioPlaybackService.instance;

    // Don't show if normalization is disabled (unless forced)
    final shouldShow = forceShow ?? service.lufsNormalizationEnabled;
    if (!shouldShow) return const SizedBox.shrink();

    // Get measured LUFS for this audio file
    final measuredLufs = service.getLufsForAudio(audioPath);
    if (measuredLufs == null) {
      // Not measured yet — show placeholder
      return _buildPlaceholder(context, service.targetLufs);
    }

    // Calculate gain adjustment
    final targetLufs = service.targetLufs;
    final gainDb = targetLufs - measuredLufs;
    final clampedGainDb = gainDb.clamp(-12.0, 12.0);

    // Color based on adjustment direction
    final color = _getColorForGain(clampedGainDb);

    // Calculate vertical position (normalized level)
    // Assuming waveform displays -1.0 to +1.0 range
    // Normalized level = how much of the waveform height the normalized audio will occupy
    final linearGain = _dbToLinear(clampedGainDb);
    final normalizedPosition = _calculateNormalizedPosition(linearGain);

    return CustomPaint(
      size: Size(double.infinity, waveformHeight),
      painter: _LufsIndicatorPainter(
        measuredLufs: measuredLufs,
        targetLufs: targetLufs,
        gainDb: clampedGainDb,
        normalizedPosition: normalizedPosition,
        color: color,
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context, double targetLufs) {
    return Positioned(
      top: 4,
      right: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 12,
              color: Colors.white.withOpacity(0.5),
            ),
            const SizedBox(width: 4),
            Text(
              'Measuring...',
              style: TextStyle(
                fontSize: 9,
                color: Colors.white.withOpacity(0.5),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getColorForGain(double gainDb) {
    if (gainDb.abs() < 0.5) {
      return Colors.green; // Minimal adjustment
    } else if (gainDb > 0) {
      return FluxForgeTheme.accentOrange; // Boosting
    } else {
      return FluxForgeTheme.accentCyan; // Reducing
    }
  }

  double _dbToLinear(double db) {
    return math.pow(10, db / 20).toDouble();
  }

  /// Calculate normalized position in waveform (0.0 = top, 1.0 = bottom)
  /// Takes into account that normalized audio might be louder or quieter
  double _calculateNormalizedPosition(double linearGain) {
    // Waveform typically shows full range (-1.0 to +1.0)
    // If linearGain > 1.0, normalized audio will be louder (use more vertical space)
    // If linearGain < 1.0, normalized audio will be quieter (use less vertical space)

    // Position of normalized level line (0.0 = top, 0.5 = center, 1.0 = bottom)
    // For gain > 1, line moves up (audio will be louder)
    // For gain < 1, line moves down (audio will be quieter)

    // Map linear gain to vertical position
    // 1.0 (0dB) → 0.5 (center)
    // 2.0 (+6dB) → 0.75 (75% of height)
    // 0.5 (-6dB) → 0.25 (25% of height)

    return 0.5 * linearGain;
  }
}

/// Custom painter for LUFS normalization indicator
class _LufsIndicatorPainter extends CustomPainter {
  final double measuredLufs;
  final double targetLufs;
  final double gainDb;
  final double normalizedPosition;
  final Color color;

  _LufsIndicatorPainter({
    required this.measuredLufs,
    required this.targetLufs,
    required this.gainDb,
    required this.normalizedPosition,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // Calculate Y position for normalized level
    final y = height * normalizedPosition.clamp(0.0, 1.0);

    // Draw horizontal line at normalized level
    final linePaint = Paint()
      ..color = color.withOpacity(0.6)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Dashed line
    const dashWidth = 8.0;
    const dashSpace = 4.0;
    double startX = 0;

    while (startX < width) {
      canvas.drawLine(
        Offset(startX, y),
        Offset(math.min(startX + dashWidth, width), y),
        linePaint,
      );
      startX += dashWidth + dashSpace;
    }

    // Draw label at right end
    final labelText = _buildLabel();
    final textPainter = TextPainter(
      text: TextSpan(
        text: labelText,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
          fontFamily: 'monospace',
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.8),
              offset: const Offset(1, 1),
              blurRadius: 2,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Position label at right edge, vertically centered on line
    final labelX = width - textPainter.width - 8;
    final labelY = y - textPainter.height / 2;

    // Draw background for label
    final labelBg = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        labelX - 4,
        labelY - 2,
        textPainter.width + 8,
        textPainter.height + 4,
      ),
      const Radius.circular(4),
    );

    canvas.drawRRect(
      labelBg,
      Paint()..color = Colors.black.withOpacity(0.7),
    );

    textPainter.paint(canvas, Offset(labelX, labelY));

    // Draw small indicator arrows at left edge
    _drawArrows(canvas, y, height, color);
  }

  String _buildLabel() {
    final sign = gainDb >= 0 ? '+' : '';
    return '$sign${gainDb.toStringAsFixed(1)} dB';
  }

  void _drawArrows(Canvas canvas, double y, double height, Color color) {
    final arrowPaint = Paint()
      ..color = color.withOpacity(0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const arrowSize = 6.0;
    const arrowX = 8.0;

    // Draw arrow indicating direction
    if (gainDb > 0.5) {
      // Boosting — arrow pointing up
      final path = Path()
        ..moveTo(arrowX, y)
        ..lineTo(arrowX - arrowSize / 2, y - arrowSize)
        ..moveTo(arrowX, y)
        ..lineTo(arrowX + arrowSize / 2, y - arrowSize);
      canvas.drawPath(path, arrowPaint);
    } else if (gainDb < -0.5) {
      // Reducing — arrow pointing down
      final path = Path()
        ..moveTo(arrowX, y)
        ..lineTo(arrowX - arrowSize / 2, y + arrowSize)
        ..moveTo(arrowX, y)
        ..lineTo(arrowX + arrowSize / 2, y + arrowSize);
      canvas.drawPath(path, arrowPaint);
    } else {
      // Minimal change — horizontal line
      canvas.drawLine(
        Offset(arrowX - arrowSize / 2, y),
        Offset(arrowX + arrowSize / 2, y),
        arrowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LufsIndicatorPainter oldDelegate) {
    return measuredLufs != oldDelegate.measuredLufs ||
        targetLufs != oldDelegate.targetLufs ||
        gainDb != oldDelegate.gainDb ||
        normalizedPosition != oldDelegate.normalizedPosition ||
        color != oldDelegate.color;
  }
}

/// Helper widget to add LUFS indicator to any waveform widget
class WaveformWithLufsIndicator extends StatelessWidget {
  final Widget waveformWidget;
  final String audioPath;
  final double waveformHeight;

  const WaveformWithLufsIndicator({
    super.key,
    required this.waveformWidget,
    required this.audioPath,
    required this.waveformHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        waveformWidget,
        LufsNormalizationIndicator(
          audioPath: audioPath,
          waveformHeight: waveformHeight,
        ),
      ],
    );
  }
}
