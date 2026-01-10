/// Professional Metering Panel
///
/// Complete metering suite with:
/// - VU Meter (analog-style 300ms integration)
/// - PPM Meter (EBU/BBC peak programme)
/// - K-System Meter (K-12/14/20)
/// - Phase Scope / Goniometer
/// - Correlation Meter
/// - Dynamic Range Meter
/// - Stereo Balance Meter
/// - LUFS display (momentary/short/integrated)
///
/// Based on ITU-R BS.1770-4, EBU R128, AES17

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';
import '../../src/rust/engine_api.dart';
import 'pro_meter.dart';
import 'correlation_meter.dart';
import 'goniometer.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DYNAMIC RANGE METER
// ═══════════════════════════════════════════════════════════════════════════════

/// Dynamic Range Meter - Shows difference between peak and RMS
class DynamicRangeMeter extends StatelessWidget {
  final double peakDb;
  final double rmsDb;
  final double width;
  final double height;

  const DynamicRangeMeter({
    super.key,
    required this.peakDb,
    required this.rmsDb,
    this.width = 60,
    this.height = 200,
  });

  double get dynamicRange => (peakDb - rmsDb).clamp(0, 40);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'DR',
            style: TextStyle(
              color: ReelForgeTheme.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgDeepest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: ReelForgeTheme.borderSubtle),
            ),
            child: CustomPaint(
              size: Size(width, height),
              painter: _DynamicRangePainter(
                peakDb: peakDb,
                rmsDb: rmsDb,
                dynamicRange: dynamicRange,
              ),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          '${dynamicRange.toStringAsFixed(1)} dB',
          style: TextStyle(
            color: _getDrColor(dynamicRange),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        ],
      ),
    );
  }

  Color _getDrColor(double dr) {
    if (dr < 6) return ReelForgeTheme.accentRed;
    if (dr < 10) return ReelForgeTheme.accentOrange;
    if (dr < 14) return ReelForgeTheme.accentYellow;
    return ReelForgeTheme.accentGreen;
  }
}

class _DynamicRangePainter extends CustomPainter {
  final double peakDb;
  final double rmsDb;
  final double dynamicRange;

  _DynamicRangePainter({
    required this.peakDb,
    required this.rmsDb,
    required this.dynamicRange,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Background gradient
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          ReelForgeTheme.accentRed.withValues(alpha: 0.3),
          ReelForgeTheme.accentOrange.withValues(alpha: 0.3),
          ReelForgeTheme.accentYellow.withValues(alpha: 0.3),
          ReelForgeTheme.accentGreen.withValues(alpha: 0.3),
        ],
        stops: const [0.0, 0.25, 0.5, 1.0],
      ).createShader(rect);

    canvas.drawRect(rect, bgPaint);

    // DR scale (0-40 dB)
    final drNorm = (dynamicRange / 40.0).clamp(0.0, 1.0);
    final barHeight = size.height * drNorm;

    // DR bar
    final barPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          dynamicRange < 6 ? ReelForgeTheme.accentRed :
          dynamicRange < 10 ? ReelForgeTheme.accentOrange :
          dynamicRange < 14 ? ReelForgeTheme.accentYellow : ReelForgeTheme.accentGreen,
          ReelForgeTheme.accentGreen.withValues(alpha: 0.5),
        ],
      ).createShader(Rect.fromLTWH(0, size.height - barHeight, size.width, barHeight));

    canvas.drawRect(
      Rect.fromLTWH(4, size.height - barHeight, size.width - 8, barHeight),
      barPaint,
    );

    // Scale markers
    final markerPaint = Paint()
      ..color = ReelForgeTheme.textPrimary.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    for (final db in [6, 10, 14, 20, 30, 40]) {
      final y = size.height * (1 - db / 40.0);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        markerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DynamicRangePainter oldDelegate) {
    return oldDelegate.dynamicRange != dynamicRange;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STEREO BALANCE METER
// ═══════════════════════════════════════════════════════════════════════════════

/// Stereo Balance Meter - Shows L/R balance
class StereoBalanceMeter extends StatelessWidget {
  final double leftLevel;
  final double rightLevel;
  final double width;
  final double height;

  const StereoBalanceMeter({
    super.key,
    required this.leftLevel,
    required this.rightLevel,
    this.width = 200,
    this.height = 24,
  });

  double get balance {
    final total = leftLevel + rightLevel;
    if (total < 0.0001) return 0.0;
    return ((rightLevel - leftLevel) / total).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('L', style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 10)),
              Text('Balance', style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 10)),
              Text('R', style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 2),
          Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgDeepest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: ReelForgeTheme.borderSubtle),
            ),
            child: CustomPaint(
              size: Size(width, height),
              painter: _BalancePainter(balance: balance),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            balance.abs() < 0.05 ? 'C' :
              '${balance > 0 ? "R" : "L"} ${(balance.abs() * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              color: balance.abs() < 0.1 ? ReelForgeTheme.accentGreen : ReelForgeTheme.accentOrange,
              fontSize: 10,
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
    final center = size.width / 2;

    // Background
    final bgPaint = Paint()..color = ReelForgeTheme.bgDeep;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(2)),
      bgPaint,
    );

    // Center line
    final centerPaint = Paint()
      ..color = ReelForgeTheme.textPrimary.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center, 0),
      Offset(center, size.height),
      centerPaint,
    );

    // Balance indicator
    final indicatorWidth = 8.0;
    final indicatorX = center + (balance * (size.width / 2 - indicatorWidth / 2));

    final indicatorPaint = Paint()
      ..color = balance.abs() < 0.1 ? ReelForgeTheme.accentGreen : ReelForgeTheme.accentOrange;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(indicatorX, size.height / 2),
          width: indicatorWidth,
          height: size.height - 4,
        ),
        const Radius.circular(2),
      ),
      indicatorPaint,
    );

    // L/R bars
    final leftWidth = (1 - balance) / 2 * (size.width - 20);
    final rightWidth = (1 + balance) / 2 * (size.width - 20);

    final leftPaint = Paint()
      ..color = ReelForgeTheme.accentCyan.withValues(alpha: 0.4);
    final rightPaint = Paint()
      ..color = ReelForgeTheme.accentCyan.withValues(alpha: 0.4);

    // Left bar (from left edge)
    canvas.drawRect(
      Rect.fromLTWH(4, 4, leftWidth.clamp(0, center - 10), size.height - 8),
      leftPaint,
    );

    // Right bar (from right edge)
    canvas.drawRect(
      Rect.fromLTWH(size.width - 4 - rightWidth.clamp(0, center - 10), 4,
                   rightWidth.clamp(0, center - 10), size.height - 8),
      rightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BalancePainter oldDelegate) {
    return oldDelegate.balance != balance;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// K-SYSTEM METER WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// K-System Meter Selection
enum KSystem { k12, k14, k20 }

/// K-System Meter with proper scales
class KSystemMeter extends StatelessWidget {
  final double peakLeft;
  final double peakRight;
  final double rmsLeft;
  final double rmsRight;
  final KSystem kSystem;
  final double width;
  final double height;

  const KSystemMeter({
    super.key,
    required this.peakLeft,
    required this.peakRight,
    required this.rmsLeft,
    required this.rmsRight,
    this.kSystem = KSystem.k14,
    this.width = 60,
    this.height = 200,
  });

  int get headroom {
    switch (kSystem) {
      case KSystem.k12: return 12;
      case KSystem.k14: return 14;
      case KSystem.k20: return 20;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'K-$headroom',
              style: const TextStyle(
                color: ReelForgeTheme.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgDeepest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: ReelForgeTheme.borderSubtle),
            ),
            child: CustomPaint(
              size: Size(width, height),
              painter: _KMeterPainter(
                peakLeft: peakLeft,
                peakRight: peakRight,
                rmsLeft: rmsLeft,
                rmsRight: rmsRight,
                headroom: headroom,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KMeterPainter extends CustomPainter {
  final double peakLeft;
  final double peakRight;
  final double rmsLeft;
  final double rmsRight;
  final int headroom;

  _KMeterPainter({
    required this.peakLeft,
    required this.peakRight,
    required this.rmsLeft,
    required this.rmsRight,
    required this.headroom,
  });

  double _linearToDb(double linear) {
    if (linear <= 0.00001) return -60;
    return 20 * math.log(linear) / math.ln10;
  }

  double _dbToNorm(double db) {
    // K-system: 0 VU = -headroom dBFS, scale from -40 to +3
    final adjusted = db + headroom;
    return ((adjusted + 40) / 43).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final meterWidth = (size.width - 12) / 2;

    // Draw scale markers
    _drawScale(canvas, size, meterWidth);

    // Left meter
    _drawMeter(canvas, 4, meterWidth, size.height,
        _linearToDb(peakLeft), _linearToDb(rmsLeft));

    // Right meter
    _drawMeter(canvas, 8 + meterWidth, meterWidth, size.height,
        _linearToDb(peakRight), _linearToDb(rmsRight));
  }

  void _drawScale(Canvas canvas, Size size, double meterWidth) {
    final linePaint = Paint()
      ..color = ReelForgeTheme.textPrimary.withValues(alpha: 0.2)
      ..strokeWidth = 1;

    // Scale marks: +3, 0, -3, -6, -9, -12, -20, -30, -40
    final marks = [3, 0, -3, -6, -9, -12, -20, -30, -40];

    for (final db in marks) {
      final y = size.height * (1 - _dbToNorm(db.toDouble() - headroom));

      // Line
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        linePaint,
      );
    }
  }

  void _drawMeter(Canvas canvas, double x, double width, double height,
      double peakDb, double rmsDb) {
    // RMS bar (wide, green/yellow/red)
    final rmsNorm = _dbToNorm(rmsDb);
    final rmsHeight = height * rmsNorm;

    final rmsPaint = Paint();
    if (rmsDb > -headroom + 3) {
      rmsPaint.color = ReelForgeTheme.accentRed;
    } else if (rmsDb > -headroom) {
      rmsPaint.color = ReelForgeTheme.accentYellow;
    } else {
      rmsPaint.color = ReelForgeTheme.accentGreen;
    }

    canvas.drawRect(
      Rect.fromLTWH(x, height - rmsHeight, width, rmsHeight),
      rmsPaint,
    );

    // Peak indicator (thin line)
    final peakNorm = _dbToNorm(peakDb);
    final peakY = height * (1 - peakNorm);

    final peakPaint = Paint()
      ..color = ReelForgeTheme.textPrimary
      ..strokeWidth = 2;

    canvas.drawLine(
      Offset(x, peakY),
      Offset(x + width, peakY),
      peakPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _KMeterPainter oldDelegate) {
    return oldDelegate.peakLeft != peakLeft ||
           oldDelegate.peakRight != peakRight ||
           oldDelegate.rmsLeft != rmsLeft ||
           oldDelegate.rmsRight != rmsRight;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPLETE METERING PANEL
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete Professional Metering Panel
class ProMeteringPanel extends StatefulWidget {
  final MeteringState metering;

  const ProMeteringPanel({
    super.key,
    required this.metering,
  });

  @override
  State<ProMeteringPanel> createState() => _ProMeteringPanelState();
}

class _ProMeteringPanelState extends State<ProMeteringPanel> {
  MeterMode _selectedMeterMode = MeterMode.ppm;
  KSystem _selectedKSystem = KSystem.k14;

  double _dbToLinear(double db) {
    if (db <= -60) return 0.0;
    return math.pow(10, db / 20).toDouble().clamp(0.0, 1.5);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metering;

    // Convert dB to linear for meters
    final peakL = _dbToLinear(m.masterPeakL);
    final peakR = _dbToLinear(m.masterPeakR);
    final rmsL = _dbToLinear(m.masterRmsL);
    final rmsR = _dbToLinear(m.masterRmsR);

    return Container(
      color: ReelForgeTheme.bgDeep,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left section: Main meters
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Meter mode selector
                  _buildMeterModeSelector(),
                  const SizedBox(height: 12),
                  // Main meters row
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // VU/PPM/Peak meter
                        _buildMainMeter(peakL, peakR, rmsL, rmsR),
                        const SizedBox(width: 16),
                        // K-System meter
                        _buildKSystemSection(peakL, peakR, rmsL, rmsR),
                        const SizedBox(width: 16),
                        // Dynamic Range
                        DynamicRangeMeter(
                          peakDb: m.masterPeakL.isFinite ? m.masterPeakL : -60,
                          rmsDb: m.masterRmsL.isFinite ? m.masterRmsL : -60,
                          width: 50,
                          height: 180,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Divider
          Container(width: 1, color: ReelForgeTheme.borderSubtle),

          // Center section: Phase/Stereo
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    'STEREO ANALYSIS',
                    style: TextStyle(
                      color: ReelForgeTheme.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Goniometer / Phase Scope
                  Expanded(
                    child: Goniometer(
                      leftData: null, // Will be connected to real data
                      rightData: null,
                      config: const GoniometerConfig(
                        showGrid: true,
                        showLabels: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Correlation meter
                  SizedBox(
                    height: 30,
                    child: CorrelationMeter(
                      correlation: m.correlation,
                      config: const CorrelationMeterConfig(
                        mode: CorrelationDisplayMode.bar,
                        showLabels: true,
                      ),
                      width: double.infinity,
                      height: 20,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Balance meter
                  StereoBalanceMeter(
                    leftLevel: peakL,
                    rightLevel: peakR,
                    width: double.infinity,
                    height: 20,
                  ),
                ],
              ),
            ),
          ),

          // Divider
          Container(width: 1, color: ReelForgeTheme.borderSubtle),

          // Right section: LUFS & Loudness
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LOUDNESS (EBU R128)',
                    style: TextStyle(
                      color: ReelForgeTheme.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // LUFS values
                  _buildLufsDisplay(m),
                  const Spacer(),
                  // True Peak
                  _buildTruePeakDisplay(m),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeterModeSelector() {
    return Row(
      children: [
        Text(
          'MODE: ',
          style: TextStyle(
            color: ReelForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        ...MeterMode.values.where((m) =>
          m == MeterMode.peak || m == MeterMode.vu || m == MeterMode.ppm
        ).map((mode) {
          final isSelected = _selectedMeterMode == mode;
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: InkWell(
              onTap: () => setState(() => _selectedMeterMode = mode),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected ? ReelForgeTheme.accentBlue : ReelForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  mode.name.toUpperCase(),
                  style: TextStyle(
                    color: isSelected ? ReelForgeTheme.textPrimary : ReelForgeTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMainMeter(double peakL, double peakR, double rmsL, double rmsR) {
    return Column(
      children: [
        Text(
          _selectedMeterMode.name.toUpperCase(),
          style: TextStyle(
            color: ReelForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ProMeter(
            readings: MeterReadings(
              peakLeft: peakL,
              peakRight: peakR,
              rmsLeft: rmsL,
              rmsRight: rmsR,
            ),
            mode: _selectedMeterMode,
            width: 40,
            showLabels: true,
            showPeakHold: true,
          ),
        ),
      ],
    );
  }

  Widget _buildKSystemSection(double peakL, double peakR, double rmsL, double rmsR) {
    return Column(
      children: [
        // K-System selector
        Row(
          mainAxisSize: MainAxisSize.min,
          children: KSystem.values.map((k) {
            final isSelected = _selectedKSystem == k;
            final label = k == KSystem.k12 ? '12' : k == KSystem.k14 ? '14' : '20';
            return Padding(
              padding: const EdgeInsets.only(right: 2),
              child: InkWell(
                onTap: () => setState(() => _selectedKSystem = k),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? ReelForgeTheme.accentOrange : ReelForgeTheme.bgMid,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'K$label',
                    style: TextStyle(
                      color: isSelected ? ReelForgeTheme.textPrimary : ReelForgeTheme.textTertiary,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: KSystemMeter(
            peakLeft: peakL,
            peakRight: peakR,
            rmsLeft: rmsL,
            rmsRight: rmsR,
            kSystem: _selectedKSystem,
            width: 50,
          ),
        ),
      ],
    );
  }

  Widget _buildLufsDisplay(MeteringState m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLufsRow('Momentary', m.masterLufsM, ReelForgeTheme.accentCyan),
        const SizedBox(height: 8),
        _buildLufsRow('Short-term', m.masterLufsS, ReelForgeTheme.accentGreen),
        const SizedBox(height: 8),
        _buildLufsRow('Integrated', m.masterLufsI, ReelForgeTheme.accentOrange),
        const SizedBox(height: 16),
        // Target comparison
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: ReelForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(Icons.flag, size: 14, color: ReelForgeTheme.textTertiary),
              const SizedBox(width: 8),
              Text(
                'Target: -14 LUFS',
                style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 11),
              ),
              const Spacer(),
              Text(
                _getTargetDiff(m.masterLufsI, -14),
                style: TextStyle(
                  color: _getTargetColor(m.masterLufsI, -14),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLufsRow(String label, double value, Color color) {
    final displayValue = value.isFinite ? value : -60.0;
    return Row(
      children: [
        Container(
          width: 4,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 10),
              ),
              Text(
                '${displayValue.toStringAsFixed(1)} LUFS',
                style: TextStyle(
                  color: ReelForgeTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTruePeakDisplay(MeteringState m) {
    final tp = m.masterTruePeak.isFinite ? m.masterTruePeak : -60.0;
    final isOver = tp > -1.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isOver ? ReelForgeTheme.accentRed.withValues(alpha: 0.2) : ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isOver ? ReelForgeTheme.accentRed : ReelForgeTheme.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isOver ? Icons.warning : Icons.show_chart,
            color: isOver ? ReelForgeTheme.accentRed : ReelForgeTheme.textTertiary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TRUE PEAK',
                style: TextStyle(
                  color: ReelForgeTheme.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${tp.toStringAsFixed(1)} dBTP',
                style: TextStyle(
                  color: isOver ? ReelForgeTheme.accentRed : ReelForgeTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (isOver)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: ReelForgeTheme.accentRed,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'OVER',
                style: TextStyle(
                  color: ReelForgeTheme.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getTargetDiff(double current, double target) {
    if (!current.isFinite) return '---';
    final diff = current - target;
    final sign = diff >= 0 ? '+' : '';
    return '$sign${diff.toStringAsFixed(1)} LU';
  }

  Color _getTargetColor(double current, double target) {
    if (!current.isFinite) return ReelForgeTheme.textTertiary;
    final diff = (current - target).abs();
    if (diff < 1) return ReelForgeTheme.accentGreen;
    if (diff < 3) return ReelForgeTheme.accentYellow;
    return ReelForgeTheme.accentRed;
  }
}
