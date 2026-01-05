// Loudness Meter Widget
//
// Professional broadcast-quality loudness metering:
// - ITU-R BS.1770-4 LUFS (Momentary, Short-term, Integrated)
// - EBU R128 compliant
// - True Peak (4x oversampled, dBTP)
// - Target loudness indicators
// - History graph (optional)

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';
import '../../src/rust/engine_api.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

/// EBU R128 target: -23 LUFS for broadcast
const double kLufsTargetBroadcast = -23.0;

/// Streaming target: -14 LUFS (Spotify, YouTube, etc.)
const double kLufsTargetStreaming = -14.0;

/// True Peak ceiling for broadcast: -1 dBTP
const double kTruePeakCeilingBroadcast = -1.0;

/// True Peak ceiling for streaming: -2 dBTP
const double kTruePeakCeilingStreaming = -2.0;

/// Loudness target mode
enum LoudnessTarget {
  broadcast,  // EBU R128: -23 LUFS, -1 dBTP
  streaming,  // Spotify/YouTube: -14 LUFS, -2 dBTP
  cinema,     // Film: -24 LUFS (ATSC A/85)
  custom,
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOUDNESS METER WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Professional loudness meter with LUFS and True Peak
class LoudnessMeter extends StatelessWidget {
  /// Current metering state from engine
  final MeteringState metering;

  /// Loudness target mode
  final LoudnessTarget target;

  /// Custom target LUFS (when target == custom)
  final double customTargetLufs;

  /// Custom True Peak ceiling (when target == custom)
  final double customTruePeakCeiling;

  /// Show history graph
  final bool showHistory;

  /// Compact mode (reduced height)
  final bool compact;

  /// Callback when target mode changes
  final ValueChanged<LoudnessTarget>? onTargetChanged;

  /// Callback to reset integrated loudness
  final VoidCallback? onResetIntegrated;

  const LoudnessMeter({
    super.key,
    required this.metering,
    this.target = LoudnessTarget.streaming,
    this.customTargetLufs = -14.0,
    this.customTruePeakCeiling = -1.0,
    this.showHistory = false,
    this.compact = false,
    this.onTargetChanged,
    this.onResetIntegrated,
  });

  double get _targetLufs {
    switch (target) {
      case LoudnessTarget.broadcast:
        return kLufsTargetBroadcast;
      case LoudnessTarget.streaming:
        return kLufsTargetStreaming;
      case LoudnessTarget.cinema:
        return -24.0;
      case LoudnessTarget.custom:
        return customTargetLufs;
    }
  }

  double get _truePeakCeiling {
    switch (target) {
      case LoudnessTarget.broadcast:
        return kTruePeakCeilingBroadcast;
      case LoudnessTarget.streaming:
        return kTruePeakCeilingStreaming;
      case LoudnessTarget.cinema:
        return -2.0;
      case LoudnessTarget.custom:
        return customTruePeakCeiling;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeep,
        border: Border.all(color: ReelForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with target selector
          _buildHeader(),

          // Main LUFS display
          _buildLufsDisplay(),

          // True Peak display
          _buildTruePeakDisplay(),

          // Visual meters
          if (!compact) _buildVisualMeters(),

          // History graph (optional)
          if (showHistory && !compact) _buildHistoryGraph(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
        border: Border(
          bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.graphic_eq,
            size: 14,
            color: ReelForgeTheme.accentCyan,
          ),
          const SizedBox(width: 6),
          Text(
            'LOUDNESS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: ReelForgeTheme.accentCyan,
            ),
          ),
          const Spacer(),
          // Target selector
          _buildTargetSelector(),
          // Reset button
          if (onResetIntegrated != null) ...[
            const SizedBox(width: 4),
            _buildResetButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildTargetSelector() {
    return PopupMenuButton<LoudnessTarget>(
      onSelected: onTargetChanged,
      tooltip: 'Target',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: ReelForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _targetLabel,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: ReelForgeTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 12,
              color: ReelForgeTheme.textTertiary,
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        _buildTargetMenuItem(LoudnessTarget.broadcast, 'Broadcast', '-23 LUFS'),
        _buildTargetMenuItem(LoudnessTarget.streaming, 'Streaming', '-14 LUFS'),
        _buildTargetMenuItem(LoudnessTarget.cinema, 'Cinema', '-24 LUFS'),
      ],
    );
  }

  PopupMenuItem<LoudnessTarget> _buildTargetMenuItem(
    LoudnessTarget value,
    String label,
    String sublabel,
  ) {
    return PopupMenuItem<LoudnessTarget>(
      value: value,
      height: 32,
      child: Row(
        children: [
          if (target == value)
            Icon(Icons.check, size: 14, color: ReelForgeTheme.accentCyan)
          else
            const SizedBox(width: 14),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              Text(
                sublabel,
                style: TextStyle(
                  fontSize: 10,
                  color: ReelForgeTheme.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get _targetLabel {
    switch (target) {
      case LoudnessTarget.broadcast:
        return 'R128';
      case LoudnessTarget.streaming:
        return 'STREAM';
      case LoudnessTarget.cinema:
        return 'FILM';
      case LoudnessTarget.custom:
        return 'CUSTOM';
    }
  }

  Widget _buildResetButton() {
    return GestureDetector(
      onTap: onResetIntegrated,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: ReelForgeTheme.borderSubtle),
        ),
        child: Icon(
          Icons.refresh,
          size: 12,
          color: ReelForgeTheme.textTertiary,
        ),
      ),
    );
  }

  Widget _buildLufsDisplay() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // Momentary
          _buildLufsRow(
            label: 'M',
            description: 'Momentary',
            value: metering.masterLufsM,
            showDelta: false,
          ),
          const SizedBox(height: 4),

          // Short-term
          _buildLufsRow(
            label: 'S',
            description: 'Short-term',
            value: metering.masterLufsS,
            showDelta: false,
          ),
          const SizedBox(height: 4),

          // Integrated (main)
          _buildLufsRow(
            label: 'I',
            description: 'Integrated',
            value: metering.masterLufsI,
            isMain: true,
            showDelta: true,
          ),
        ],
      ),
    );
  }

  Widget _buildLufsRow({
    required String label,
    required String description,
    required double value,
    bool isMain = false,
    bool showDelta = false,
  }) {
    final isValid = value > -70;
    final delta = value - _targetLufs;
    final isOnTarget = delta.abs() < 1.0;
    final isOver = delta > 0;

    Color valueColor;
    if (!isValid) {
      valueColor = ReelForgeTheme.textTertiary;
    } else if (isMain) {
      valueColor = isOnTarget
          ? const Color(0xFF40FF90) // Green - on target
          : isOver
              ? const Color(0xFFFF4040) // Red - over target
              : ReelForgeTheme.textPrimary; // Normal - under target
    } else {
      valueColor = ReelForgeTheme.textPrimary;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 8,
        vertical: isMain ? 6 : 4,
      ),
      decoration: isMain
          ? BoxDecoration(
              color: isOnTarget
                  ? const Color(0x1A40FF90)
                  : isOver
                      ? const Color(0x1AFF4040)
                      : ReelForgeTheme.bgDeepest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isOnTarget
                    ? const Color(0x4040FF90)
                    : isOver
                        ? const Color(0x40FF4040)
                        : ReelForgeTheme.borderSubtle,
              ),
            )
          : null,
      child: Row(
        children: [
          // Label
          SizedBox(
            width: 20,
            child: Text(
              label,
              style: TextStyle(
                fontSize: isMain ? 16 : 12,
                fontWeight: FontWeight.bold,
                color: ReelForgeTheme.accentCyan,
              ),
            ),
          ),

          // Description
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                fontSize: 9,
                color: ReelForgeTheme.textTertiary,
              ),
            ),
          ),

          // Value
          Text(
            isValid ? value.toStringAsFixed(1) : '-∞',
            style: TextStyle(
              fontSize: isMain ? 20 : 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: valueColor,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'LUFS',
            style: TextStyle(
              fontSize: isMain ? 10 : 8,
              color: ReelForgeTheme.textTertiary,
            ),
          ),

          // Delta from target
          if (showDelta && isValid) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: isOnTarget
                    ? const Color(0x3340FF90)
                    : isOver
                        ? const Color(0x33FF4040)
                        : ReelForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: isOnTarget
                      ? const Color(0xFF40FF90)
                      : isOver
                          ? const Color(0xFFFF4040)
                          : ReelForgeTheme.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTruePeakDisplay() {
    final truePeak = metering.masterTruePeak;
    final isValid = truePeak > -70;
    final isOver = truePeak > _truePeakCeiling;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isOver ? const Color(0x33FF4040) : ReelForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isOver ? const Color(0x80FF4040) : ReelForgeTheme.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          // Label
          Text(
            'TP',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isOver
                  ? const Color(0xFFFF4040)
                  : ReelForgeTheme.accentOrange,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'True Peak',
            style: TextStyle(
              fontSize: 9,
              color: ReelForgeTheme.textTertiary,
            ),
          ),
          const Spacer(),

          // Value
          Text(
            isValid ? truePeak.toStringAsFixed(1) : '-∞',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: isOver
                  ? const Color(0xFFFF4040)
                  : isValid
                      ? ReelForgeTheme.textPrimary
                      : ReelForgeTheme.textTertiary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'dBTP',
            style: TextStyle(
              fontSize: 9,
              color: ReelForgeTheme.textTertiary,
            ),
          ),

          // Ceiling indicator
          if (isValid) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: isOver
                    ? const Color(0x66FF4040)
                    : ReelForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isOver ? Icons.warning_amber : Icons.check,
                    size: 10,
                    color: isOver
                        ? const Color(0xFFFF4040)
                        : const Color(0xFF40FF90),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    _truePeakCeiling.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 9,
                      color: isOver
                          ? const Color(0xFFFF4040)
                          : ReelForgeTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVisualMeters() {
    return Container(
      height: 60,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ReelForgeTheme.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: CustomPaint(
          painter: _LoudnessMeterPainter(
            lufsM: metering.masterLufsM,
            lufsS: metering.masterLufsS,
            lufsI: metering.masterLufsI,
            truePeak: metering.masterTruePeak,
            targetLufs: _targetLufs,
            truePeakCeiling: _truePeakCeiling,
          ),
          size: const Size(double.infinity, 60),
        ),
      ),
    );
  }

  Widget _buildHistoryGraph() {
    // TODO: Implement loudness history graph
    return Container(
      height: 80,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ReelForgeTheme.borderSubtle),
      ),
      child: Center(
        child: Text(
          'History Graph',
          style: TextStyle(
            fontSize: 10,
            color: ReelForgeTheme.textTertiary,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOUDNESS METER PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _LoudnessMeterPainter extends CustomPainter {
  final double lufsM;
  final double lufsS;
  final double lufsI;
  final double truePeak;
  final double targetLufs;
  final double truePeakCeiling;

  _LoudnessMeterPainter({
    required this.lufsM,
    required this.lufsS,
    required this.lufsI,
    required this.truePeak,
    required this.targetLufs,
    required this.truePeakCeiling,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final lufsBarHeight = size.height * 0.6;
    final tpBarHeight = size.height * 0.3;
    final spacing = size.height * 0.1;

    // Draw LUFS meter (top)
    _drawLufsMeter(canvas, Rect.fromLTWH(0, 0, size.width, lufsBarHeight));

    // Draw True Peak meter (bottom)
    _drawTruePeakMeter(
      canvas,
      Rect.fromLTWH(0, lufsBarHeight + spacing, size.width, tpBarHeight),
    );
  }

  void _drawLufsMeter(Canvas canvas, Rect rect) {
    // Background
    final bgPaint = Paint()..color = const Color(0xFF1A1A20);
    canvas.drawRect(rect, bgPaint);

    // Scale: -60 to 0 LUFS
    const minLufs = -60.0;
    const maxLufs = 0.0;

    double lufsToX(double lufs) {
      final normalized = (lufs - minLufs) / (maxLufs - minLufs);
      return rect.left + normalized.clamp(0.0, 1.0) * rect.width;
    }

    // Target zone (-1 to +1 around target)
    final targetZonePaint = Paint()..color = const Color(0x3340FF90);
    final targetLeft = lufsToX(targetLufs - 1);
    final targetRight = lufsToX(targetLufs + 1);
    canvas.drawRect(
      Rect.fromLTRB(targetLeft, rect.top, targetRight, rect.bottom),
      targetZonePaint,
    );

    // Target line
    final targetLinePaint = Paint()
      ..color = const Color(0xFF40FF90)
      ..strokeWidth = 2;
    final targetX = lufsToX(targetLufs);
    canvas.drawLine(
      Offset(targetX, rect.top),
      Offset(targetX, rect.bottom),
      targetLinePaint,
    );

    // Draw LUFS bars
    final barHeight = rect.height / 3 - 2;

    // Momentary (top)
    _drawLufsBar(
      canvas,
      Rect.fromLTWH(rect.left, rect.top + 1, rect.width, barHeight),
      lufsM,
      const Color(0xFF4A9EFF),
      minLufs,
      maxLufs,
    );

    // Short-term (middle)
    _drawLufsBar(
      canvas,
      Rect.fromLTWH(rect.left, rect.top + barHeight + 2, rect.width, barHeight),
      lufsS,
      const Color(0xFF40C8FF),
      minLufs,
      maxLufs,
    );

    // Integrated (bottom)
    _drawLufsBar(
      canvas,
      Rect.fromLTWH(
          rect.left, rect.top + (barHeight + 2) * 2, rect.width, barHeight),
      lufsI,
      const Color(0xFF40FF90),
      minLufs,
      maxLufs,
    );

    // Scale ticks
    final tickPaint = Paint()
      ..color = const Color(0x40FFFFFF)
      ..strokeWidth = 1;
    for (final tick in [-48, -36, -24, -18, -12, -6, 0]) {
      final x = lufsToX(tick.toDouble());
      canvas.drawLine(
        Offset(x, rect.top),
        Offset(x, rect.bottom),
        tickPaint,
      );
    }
  }

  void _drawLufsBar(
    Canvas canvas,
    Rect rect,
    double value,
    Color color,
    double minLufs,
    double maxLufs,
  ) {
    if (value <= minLufs) return;

    final normalized = (value - minLufs) / (maxLufs - minLufs);
    final barWidth = normalized.clamp(0.0, 1.0) * rect.width;

    final gradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        color.withValues(alpha: 0.3),
        color,
      ],
    ).createShader(Rect.fromLTWH(rect.left, rect.top, barWidth, rect.height));

    final barPaint = Paint()..shader = gradient;
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, barWidth, rect.height),
      barPaint,
    );
  }

  void _drawTruePeakMeter(Canvas canvas, Rect rect) {
    // Background
    final bgPaint = Paint()..color = const Color(0xFF1A1A20);
    canvas.drawRect(rect, bgPaint);

    // Scale: -60 to +3 dBTP
    const minDb = -60.0;
    const maxDb = 3.0;

    double dbToX(double db) {
      final normalized = (db - minDb) / (maxDb - minDb);
      return rect.left + normalized.clamp(0.0, 1.0) * rect.width;
    }

    // Ceiling line
    final ceilingX = dbToX(truePeakCeiling);
    final ceilingPaint = Paint()
      ..color = const Color(0xFFFF4040)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(ceilingX, rect.top),
      Offset(ceilingX, rect.bottom),
      ceilingPaint,
    );

    // Over ceiling zone
    final overZonePaint = Paint()..color = const Color(0x33FF4040);
    canvas.drawRect(
      Rect.fromLTRB(ceilingX, rect.top, rect.right, rect.bottom),
      overZonePaint,
    );

    // True Peak bar
    if (truePeak > minDb) {
      final normalized = (truePeak - minDb) / (maxDb - minDb);
      final barWidth = normalized.clamp(0.0, 1.0) * rect.width;
      final isOver = truePeak > truePeakCeiling;

      final gradient = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0xFF40C8FF),
          const Color(0xFF40FF90),
          const Color(0xFFFFFF40),
          const Color(0xFFFF9040),
          const Color(0xFFFF4040),
        ],
        stops: const [0.0, 0.3, 0.6, 0.85, 1.0],
      ).createShader(Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height));

      final barPaint = Paint()..shader = gradient;
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top + 2, barWidth, rect.height - 4),
        barPaint,
      );

      // Peak hold indicator
      final peakX = dbToX(truePeak);
      final peakPaint = Paint()
        ..color = isOver ? const Color(0xFFFF4040) : Colors.white
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(peakX, rect.top),
        Offset(peakX, rect.bottom),
        peakPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_LoudnessMeterPainter oldDelegate) =>
      lufsM != oldDelegate.lufsM ||
      lufsS != oldDelegate.lufsS ||
      lufsI != oldDelegate.lufsI ||
      truePeak != oldDelegate.truePeak ||
      targetLufs != oldDelegate.targetLufs ||
      truePeakCeiling != oldDelegate.truePeakCeiling;
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPACT LOUDNESS DISPLAY
// ═══════════════════════════════════════════════════════════════════════════════

/// Compact loudness display for toolbar/status bar
class CompactLoudnessDisplay extends StatelessWidget {
  final MeteringState metering;
  final VoidCallback? onTap;

  const CompactLoudnessDisplay({
    super.key,
    required this.metering,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lufs = metering.masterLufsI;
    final tp = metering.masterTruePeak;
    final isLufsValid = lufs > -70;
    final isTpValid = tp > -70;
    final isTpOver = tp > -1.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: ReelForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // LUFS
            Text(
              'LUFS',
              style: TextStyle(
                fontSize: 9,
                color: ReelForgeTheme.textTertiary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              isLufsValid ? lufs.toStringAsFixed(1) : '-∞',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: isLufsValid
                    ? ReelForgeTheme.textPrimary
                    : ReelForgeTheme.textTertiary,
              ),
            ),

            // Separator
            Container(
              width: 1,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: ReelForgeTheme.borderSubtle,
            ),

            // True Peak
            Text(
              'TP',
              style: TextStyle(
                fontSize: 9,
                color: isTpOver
                    ? const Color(0xFFFF4040)
                    : ReelForgeTheme.textTertiary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              isTpValid ? tp.toStringAsFixed(1) : '-∞',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: isTpOver
                    ? const Color(0xFFFF4040)
                    : isTpValid
                        ? ReelForgeTheme.textPrimary
                        : ReelForgeTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
