/// Metering Bridge - Professional Mastering-Grade Meters
///
/// Includes:
/// - K-System meters (K-12, K-14, K-20)
/// - Goniometer (Lissajous)
/// - Correlation meter
/// - Phase scope
/// - Loudness history
/// - True peak meters

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// K-SYSTEM METER TYPES
// ═══════════════════════════════════════════════════════════════════════════

enum KSystemType {
  k12, // Broadcast
  k14, // Most music
  k20, // Classical/Wide DR
}

// ═══════════════════════════════════════════════════════════════════════════
// METERING BRIDGE
// ═══════════════════════════════════════════════════════════════════════════

class MeteringBridge extends StatefulWidget {
  // Real-time metering data
  final double peakL;
  final double peakR;
  final double rmsL;
  final double rmsR;
  final double truePeakL;
  final double truePeakR;
  final double correlation;
  final double balance;
  final double lufsMomentary;
  final double lufsShort;
  final double lufsIntegrated;
  // Configuration
  final KSystemType kSystem;
  final bool showGoniometer;
  final bool showLoudnessHistory;
  final ValueChanged<KSystemType>? onKSystemChange;

  const MeteringBridge({
    super.key,
    this.peakL = 0,
    this.peakR = 0,
    this.rmsL = 0,
    this.rmsR = 0,
    this.truePeakL = 0,
    this.truePeakR = 0,
    this.correlation = 1.0,
    this.balance = 0,
    this.lufsMomentary = -70,
    this.lufsShort = -70,
    this.lufsIntegrated = -70,
    this.kSystem = KSystemType.k14,
    this.showGoniometer = true,
    this.showLoudnessHistory = true,
    this.onKSystemChange,
  });

  @override
  State<MeteringBridge> createState() => _MeteringBridgeState();
}

class _MeteringBridgeState extends State<MeteringBridge> {
  // Peak hold
  double _peakHoldL = 0;
  double _peakHoldR = 0;
  // Loudness history (last 60 seconds at 10Hz)
  final List<double> _loudnessHistory = List.filled(600, -70.0);
  int _historyIndex = 0;

  @override
  void didUpdateWidget(MeteringBridge oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update peak hold
    if (widget.peakL > _peakHoldL) _peakHoldL = widget.peakL;
    if (widget.peakR > _peakHoldR) _peakHoldR = widget.peakR;
    // Update loudness history
    if (widget.lufsShort != oldWidget.lufsShort) {
      _loudnessHistory[_historyIndex] = widget.lufsShort;
      _historyIndex = (_historyIndex + 1) % _loudnessHistory.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeepest,
      child: Row(
        children: [
          // Left: K-System meters
          Expanded(
            flex: 2,
            child: _KSystemMeter(
              peakL: widget.peakL,
              peakR: widget.peakR,
              rmsL: widget.rmsL,
              rmsR: widget.rmsR,
              peakHoldL: _peakHoldL,
              peakHoldR: _peakHoldR,
              kSystem: widget.kSystem,
              onKSystemChange: widget.onKSystemChange,
              onResetPeaks: () => setState(() {
                _peakHoldL = 0;
                _peakHoldR = 0;
              }),
            ),
          ),
          const _VerticalDivider(),
          // Center: Goniometer + Correlation
          if (widget.showGoniometer) ...[
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  // Goniometer
                  Expanded(
                    child: _Goniometer(
                      peakL: widget.peakL,
                      peakR: widget.peakR,
                    ),
                  ),
                  // Correlation meter
                  SizedBox(
                    height: 30,
                    child: _CorrelationMeter(
                      correlation: widget.correlation,
                    ),
                  ),
                  // Balance meter
                  SizedBox(
                    height: 20,
                    child: _BalanceMeter(
                      balance: widget.balance,
                    ),
                  ),
                ],
              ),
            ),
            const _VerticalDivider(),
          ],
          // Right: Loudness + True Peak
          Expanded(
            flex: 3,
            child: Column(
              children: [
                // Loudness display
                SizedBox(
                  height: 60,
                  child: _LoudnessDisplay(
                    momentary: widget.lufsMomentary,
                    shortTerm: widget.lufsShort,
                    integrated: widget.lufsIntegrated,
                  ),
                ),
                // Loudness history graph
                if (widget.showLoudnessHistory)
                  Expanded(
                    child: _LoudnessHistory(
                      history: _loudnessHistory,
                      currentIndex: _historyIndex,
                    ),
                  ),
                // True Peak display
                SizedBox(
                  height: 30,
                  child: _TruePeakDisplay(
                    truePeakL: widget.truePeakL,
                    truePeakR: widget.truePeakR,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// K-SYSTEM METER
// ═══════════════════════════════════════════════════════════════════════════

class _KSystemMeter extends StatelessWidget {
  final double peakL;
  final double peakR;
  final double rmsL;
  final double rmsR;
  final double peakHoldL;
  final double peakHoldR;
  final KSystemType kSystem;
  final ValueChanged<KSystemType>? onKSystemChange;
  final VoidCallback? onResetPeaks;

  const _KSystemMeter({
    required this.peakL,
    required this.peakR,
    required this.rmsL,
    required this.rmsR,
    this.peakHoldL = 0,
    this.peakHoldR = 0,
    this.kSystem = KSystemType.k14,
    this.onKSystemChange,
    this.onResetPeaks,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // K-System selector
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _KSystemButton(
                label: 'K-12',
                selected: kSystem == KSystemType.k12,
                onTap: () => onKSystemChange?.call(KSystemType.k12),
              ),
              _KSystemButton(
                label: 'K-14',
                selected: kSystem == KSystemType.k14,
                onTap: () => onKSystemChange?.call(KSystemType.k14),
              ),
              _KSystemButton(
                label: 'K-20',
                selected: kSystem == KSystemType.k20,
                onTap: () => onKSystemChange?.call(KSystemType.k20),
              ),
            ],
          ),
        ),
        // Meters
        Expanded(
          child: Row(
            children: [
              // Left channel
              Expanded(
                child: _KMeterBar(
                  peak: peakL,
                  rms: rmsL,
                  peakHold: peakHoldL,
                  kSystem: kSystem,
                  label: 'L',
                ),
              ),
              // Right channel
              Expanded(
                child: _KMeterBar(
                  peak: peakR,
                  rms: rmsR,
                  peakHold: peakHoldR,
                  kSystem: kSystem,
                  label: 'R',
                ),
              ),
            ],
          ),
        ),
        // Reset button
        GestureDetector(
          onTap: onResetPeaks,
          child: Container(
            height: 20,
            child: const Center(
              child: Text(
                'RESET PEAKS',
                style: TextStyle(
                  color: FluxForgeTheme.textTertiary,
                  fontSize: 8,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _KSystemButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _KSystemButton({
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: selected
              ? FluxForgeTheme.accentBlue.withOpacity(0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: selected
                ? FluxForgeTheme.accentBlue
                : Colors.white.withOpacity(0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? FluxForgeTheme.accentBlue
                : FluxForgeTheme.textTertiary,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _KMeterBar extends StatelessWidget {
  final double peak;
  final double rms;
  final double peakHold;
  final KSystemType kSystem;
  final String label;

  const _KMeterBar({
    required this.peak,
    required this.rms,
    this.peakHold = 0,
    this.kSystem = KSystemType.k14,
    this.label = '',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: CustomPaint(
              painter: _KMeterPainter(
                peak: peak,
                rms: rms,
                peakHold: peakHold,
                kSystem: kSystem,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _KMeterPainter extends CustomPainter {
  final double peak;
  final double rms;
  final double peakHold;
  final KSystemType kSystem;

  _KMeterPainter({
    required this.peak,
    required this.rms,
    this.peakHold = 0,
    this.kSystem = KSystemType.k14,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = const Color(0xFF0A0A0C),
    );

    // K-System reference line (0dBFS -> K-Reference)
    final kRef = _getKReference();
    final refY = size.height * (1 - kRef);

    // Scale marks
    _drawScaleMarks(canvas, size);

    // RMS bar (wider, behind peak)
    final rmsHeight = size.height * rms.clamp(0.0, 1.2);
    if (rmsHeight > 0) {
      final rmsRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(4, size.height - rmsHeight, size.width - 8, rmsHeight),
        const Radius.circular(1),
      );
      canvas.drawRRect(
        rmsRect,
        Paint()..color = _getRmsColor(rms),
      );
    }

    // Peak bar (narrower, on top)
    final peakHeight = size.height * peak.clamp(0.0, 1.2);
    if (peakHeight > 0) {
      final peakRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(8, size.height - peakHeight, size.width - 16, peakHeight),
        const Radius.circular(1),
      );
      canvas.drawRRect(
        peakRect,
        Paint()..shader = _getMeterGradient(rect).createShader(rect),
      );
    }

    // Peak hold line
    if (peakHold > 0.01) {
      final holdY = size.height * (1 - peakHold.clamp(0.0, 1.2));
      canvas.drawLine(
        Offset(2, holdY),
        Offset(size.width - 2, holdY),
        Paint()
          ..color = peakHold > 1.0
              ? const Color(0xFFFF4040)
              : const Color(0xFFFFFFFF)
          ..strokeWidth = 2,
      );
    }

    // Reference line (K-system)
    canvas.drawLine(
      Offset(0, refY),
      Offset(size.width, refY),
      Paint()
        ..color = Colors.white.withOpacity(0.5)
        ..strokeWidth = 1,
    );
  }

  double _getKReference() {
    switch (kSystem) {
      case KSystemType.k12:
        return 0.251; // -12dB = 0dB ref
      case KSystemType.k14:
        return 0.2; // -14dB = 0dB ref
      case KSystemType.k20:
        return 0.1; // -20dB = 0dB ref
    }
  }

  void _drawScaleMarks(Canvas canvas, Size size) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final marks = [0, -6, -12, -20, -30, -40, -60];

    for (final db in marks) {
      final linear = math.pow(10, db / 20).toDouble();
      final y = size.height * (1 - linear);

      // Tick mark
      canvas.drawLine(
        Offset(0, y),
        Offset(3, y),
        Paint()
          ..color = Colors.white.withOpacity(0.3)
          ..strokeWidth = 1,
      );
    }
  }

  Color _getRmsColor(double level) {
    if (level > 1.0) return const Color(0x80FF4040);
    if (level > 0.7) return const Color(0x80FFFF40);
    return const Color(0x8040C8FF);
  }

  LinearGradient _getMeterGradient(Rect rect) {
    return const LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        Color(0xFF40C8FF),
        Color(0xFF40FF90),
        Color(0xFFFFFF40),
        Color(0xFFFF9040),
        Color(0xFFFF4040),
      ],
      stops: [0.0, 0.4, 0.7, 0.85, 1.0],
    );
  }

  @override
  bool shouldRepaint(_KMeterPainter oldDelegate) =>
      peak != oldDelegate.peak ||
      rms != oldDelegate.rms ||
      peakHold != oldDelegate.peakHold ||
      kSystem != oldDelegate.kSystem;
}

// ═══════════════════════════════════════════════════════════════════════════
// GONIOMETER (LISSAJOUS)
// ═══════════════════════════════════════════════════════════════════════════

class _Goniometer extends StatelessWidget {
  final double peakL;
  final double peakR;

  const _Goniometer({
    required this.peakL,
    required this.peakR,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: CustomPaint(
        painter: _GoniometerPainter(peakL: peakL, peakR: peakR),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GoniometerPainter extends CustomPainter {
  final double peakL;
  final double peakR;

  _GoniometerPainter({required this.peakL, required this.peakR});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;

    // Grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 0.5;

    // Diagonal lines (M/S axes)
    canvas.drawLine(
      Offset(center.dx - radius, center.dy - radius),
      Offset(center.dx + radius, center.dy + radius),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx - radius, center.dy + radius),
      Offset(center.dx + radius, center.dy - radius),
      gridPaint,
    );

    // Center cross
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      gridPaint,
    );

    // Labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    const labelStyle = TextStyle(
      color: FluxForgeTheme.textTertiary,
      fontSize: 8,
    );

    // L label (top-left)
    textPainter.text = const TextSpan(text: 'L', style: labelStyle);
    textPainter.layout();
    textPainter.paint(canvas, Offset(4, 4));

    // R label (top-right)
    textPainter.text = const TextSpan(text: 'R', style: labelStyle);
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - 12, 4));

    // M label (top)
    textPainter.text = const TextSpan(text: 'M', style: labelStyle);
    textPainter.layout();
    textPainter.paint(canvas, Offset(center.dx - 4, 4));

    // S label (right)
    textPainter.text = const TextSpan(text: 'S', style: labelStyle);
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - 12, center.dy - 4));

    // Signal dot
    // In a real implementation, this would show the actual L/R relationship
    // Simplified: M = (L+R)/2, S = (L-R)/2
    final m = (peakL + peakR) / 2;
    final s = (peakL - peakR) / 2;

    final dotX = center.dx + s * radius;
    final dotY = center.dy - m * radius;

    // Draw signal trail (simplified - just current point)
    canvas.drawCircle(
      Offset(dotX, dotY),
      3,
      Paint()
        ..color = FluxForgeTheme.accentBlue.withOpacity(0.8)
        ..style = PaintingStyle.fill,
    );

    // Glow
    canvas.drawCircle(
      Offset(dotX, dotY),
      6,
      Paint()
        ..color = FluxForgeTheme.accentBlue.withOpacity(0.3)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(_GoniometerPainter oldDelegate) =>
      peakL != oldDelegate.peakL || peakR != oldDelegate.peakR;
}

// ═══════════════════════════════════════════════════════════════════════════
// CORRELATION METER
// ═══════════════════════════════════════════════════════════════════════════

class _CorrelationMeter extends StatelessWidget {
  final double correlation;

  const _CorrelationMeter({required this.correlation});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('-1', style: TextStyle(
                color: FluxForgeTheme.textTertiary, fontSize: 8)),
              const Text('CORRELATION', style: TextStyle(
                color: FluxForgeTheme.textSecondary, fontSize: 8)),
              const Text('+1', style: TextStyle(
                color: FluxForgeTheme.textTertiary, fontSize: 8)),
            ],
          ),
          const SizedBox(height: 2),
          Expanded(
            child: CustomPaint(
              painter: _CorrelationPainter(correlation: correlation),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CorrelationPainter extends CustomPainter {
  final double correlation;

  _CorrelationPainter({required this.correlation});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = const Color(0xFF0A0A0C),
    );

    // Gradient (red on sides, green in center)
    final gradient = const LinearGradient(
      colors: [
        Color(0xFFFF4040), // -1 (out of phase)
        Color(0xFFFFFF40), // 0 (uncorrelated)
        Color(0xFF40FF90), // +1 (mono)
      ],
      stops: [0.0, 0.5, 1.0],
    );

    // Fill based on correlation
    final centerX = size.width / 2;
    final indicatorX = centerX + (correlation * centerX);

    // Background bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..shader = gradient.createShader(rect),
    );

    // Indicator line
    canvas.drawLine(
      Offset(indicatorX, 0),
      Offset(indicatorX, size.height),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2,
    );

    // Center line
    canvas.drawLine(
      Offset(centerX, 0),
      Offset(centerX, size.height),
      Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_CorrelationPainter oldDelegate) =>
      correlation != oldDelegate.correlation;
}

// ═══════════════════════════════════════════════════════════════════════════
// BALANCE METER
// ═══════════════════════════════════════════════════════════════════════════

class _BalanceMeter extends StatelessWidget {
  final double balance;

  const _BalanceMeter({required this.balance});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        children: [
          const Text('BALANCE', style: TextStyle(
            color: FluxForgeTheme.textSecondary, fontSize: 8)),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0C),
                borderRadius: BorderRadius.circular(2),
              ),
              child: CustomPaint(
                painter: _BalancePainter(balance: balance),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalancePainter extends CustomPainter {
  final double balance;

  _BalancePainter({required this.balance});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;

    // Center line
    canvas.drawLine(
      Offset(centerX, 0),
      Offset(centerX, size.height),
      Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..strokeWidth = 1,
    );

    // Balance bar
    final barWidth = balance.abs() * centerX;
    final barX = balance < 0 ? centerX - barWidth : centerX;

    canvas.drawRect(
      Rect.fromLTWH(barX, 2, barWidth, size.height - 4),
      Paint()..color = FluxForgeTheme.accentBlue,
    );
  }

  @override
  bool shouldRepaint(_BalancePainter oldDelegate) =>
      balance != oldDelegate.balance;
}

// ═══════════════════════════════════════════════════════════════════════════
// LOUDNESS DISPLAY & HISTORY
// ═══════════════════════════════════════════════════════════════════════════

class _LoudnessDisplay extends StatelessWidget {
  final double momentary;
  final double shortTerm;
  final double integrated;

  const _LoudnessDisplay({
    required this.momentary,
    required this.shortTerm,
    required this.integrated,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _LoudnessValue(label: 'M', value: momentary, unit: 'LUFS'),
          _LoudnessValue(label: 'S', value: shortTerm, unit: 'LUFS'),
          _LoudnessValue(label: 'I', value: integrated, unit: 'LUFS', highlight: true),
        ],
      ),
    );
  }
}

class _LoudnessValue extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final bool highlight;

  const _LoudnessValue({
    required this.label,
    required this.value,
    required this.unit,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: highlight
              ? FluxForgeTheme.accentBlue.withOpacity(0.1)
              : Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(4),
          border: highlight
              ? Border.all(color: FluxForgeTheme.accentBlue.withOpacity(0.3))
              : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: highlight
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.textTertiary,
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value > -70 ? value.toStringAsFixed(1) : '-∞',
                style: TextStyle(
                  color: highlight
                      ? FluxForgeTheme.textPrimary
                      : FluxForgeTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                unit,
                style: const TextStyle(
                  color: FluxForgeTheme.textTertiary,
                  fontSize: 6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoudnessHistory extends StatelessWidget {
  final List<double> history;
  final int currentIndex;

  const _LoudnessHistory({
    required this.history,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: CustomPaint(
        painter: _LoudnessHistoryPainter(
          history: history,
          currentIndex: currentIndex,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LoudnessHistoryPainter extends CustomPainter {
  final List<double> history;
  final int currentIndex;

  _LoudnessHistoryPainter({
    required this.history,
    required this.currentIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Grid lines (every 6dB)
    for (var db = -6; db >= -30; db -= 6) {
      final y = _dbToY(db.toDouble(), size.height);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = Colors.white.withOpacity(0.1)
          ..strokeWidth = 0.5,
      );
    }

    // Target range (-14 ± 1 LUFS for streaming)
    final targetTop = _dbToY(-13, size.height);
    final targetBottom = _dbToY(-15, size.height);
    canvas.drawRect(
      Rect.fromLTRB(0, targetTop, size.width, targetBottom),
      Paint()..color = FluxForgeTheme.accentGreen.withOpacity(0.1),
    );

    // History line
    final path = Path();
    var started = false;

    for (var i = 0; i < history.length; i++) {
      final idx = (currentIndex + i) % history.length;
      final value = history[idx];
      if (value > -70) {
        final x = i / history.length * size.width;
        final y = _dbToY(value, size.height);

        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = FluxForgeTheme.accentBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  double _dbToY(double db, double height) {
    // Map -6 to 0, -36 to height
    final normalized = (db + 6) / -30;
    return normalized.clamp(0.0, 1.0) * height;
  }

  @override
  bool shouldRepaint(_LoudnessHistoryPainter oldDelegate) {
    // History is a rolling buffer - repaint if index changed or list reference changed
    return currentIndex != oldDelegate.currentIndex || history != oldDelegate.history;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRUE PEAK DISPLAY
// ═══════════════════════════════════════════════════════════════════════════

class _TruePeakDisplay extends StatelessWidget {
  final double truePeakL;
  final double truePeakR;

  const _TruePeakDisplay({
    required this.truePeakL,
    required this.truePeakR,
  });

  @override
  Widget build(BuildContext context) {
    final peakDbL = truePeakL > 0 ? 20.0 * math.log(truePeakL) / math.ln10 : -70.0;
    final peakDbR = truePeakR > 0 ? 20.0 * math.log(truePeakR) / math.ln10 : -70.0;
    final isOver = peakDbL > -1 || peakDbR > -1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isOver
            ? const Color(0x40FF4040)
            : Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isOver
              ? const Color(0xFFFF4040)
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'TRUE PEAK',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            'L: ${_formatDb(peakDbL)} | R: ${_formatDb(peakDbR)} dBTP',
            style: TextStyle(
              color: isOver
                  ? const Color(0xFFFF4040)
                  : FluxForgeTheme.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  String _formatDb(double db) {
    if (db <= -70) return '-∞';
    return db >= 0 ? '+${db.toStringAsFixed(1)}' : db.toStringAsFixed(1);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.white.withOpacity(0.1),
    );
  }
}
