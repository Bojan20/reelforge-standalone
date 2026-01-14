/// Glass Metering Panel
///
/// Liquid Glass styled professional metering suite:
/// - Dynamic Range Meter with glass gradients
/// - Stereo Balance Meter with frosted effects
/// - K-System Meter with blur overlays
/// - Complete metering panel with glass styling

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../providers/theme_mode_provider.dart';
import '../../src/rust/engine_api.dart';
import 'dart:typed_data';
import '../meters/pro_metering_panel.dart';
import '../meters/pro_meter.dart';
import '../meters/correlation_meter.dart';
import '../meters/goniometer.dart';
import '../meters/glass_pro_meter.dart';
import '../meters/advanced_metering_panel.dart';
import '../meters/vectorscope.dart';
import '../meters/loudness_meter.dart';
import '../meters/pdc_display.dart';
import 'glass_dsp_panels.dart';

// ==============================================================================
// THEME-AWARE METERING PANEL
// ==============================================================================

/// Theme-aware metering panel that switches between Classic and Glass
class ThemeAwareMeteringPanel extends StatelessWidget {
  final MeteringState metering;

  const ThemeAwareMeteringPanel({
    super.key,
    required this.metering,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return GlassMeteringPanel(metering: metering);
    }

    return ProMeteringPanel(metering: metering);
  }
}

// ==============================================================================
// GLASS METERING PANEL
// ==============================================================================

class GlassMeteringPanel extends StatefulWidget {
  final MeteringState metering;

  const GlassMeteringPanel({
    super.key,
    required this.metering,
  });

  @override
  State<GlassMeteringPanel> createState() => _GlassMeteringPanelState();
}

class _GlassMeteringPanelState extends State<GlassMeteringPanel> {
  MeterMode _selectedMeterMode = MeterMode.ppm;
  KSystem _selectedKSystem = KSystem.k14;

  double _dbToLinear(double db) {
    if (db <= -60) return 0.0;
    return math.pow(10, db / 20).toDouble().clamp(0.0, 1.5);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metering;

    final peakL = _dbToLinear(m.masterPeakL);
    final peakR = _dbToLinear(m.masterPeakR);
    final rmsL = _dbToLinear(m.masterRmsL);
    final rmsR = _dbToLinear(m.masterRmsR);

    return ClipRRect(
      borderRadius: BorderRadius.circular(LiquidGlassTheme.radiusMedium),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: LiquidGlassTheme.blurAmount,
          sigmaY: LiquidGlassTheme.blurAmount,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.08),
                Colors.white.withValues(alpha: 0.04),
                Colors.black.withValues(alpha: 0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(LiquidGlassTheme.radiusMedium),
            border: Border.all(color: LiquidGlassTheme.borderLight),
          ),
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
                      _buildGlassMeterModeSelector(),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildGlassMainMeter(peakL, peakR, rmsL, rmsR),
                            const SizedBox(width: 16),
                            _buildGlassKSystemSection(peakL, peakR, rmsL, rmsR),
                            const SizedBox(width: 16),
                            GlassDynamicRangeMeter(
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

              // Glass divider
              Container(
                width: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.0),
                      Colors.white.withValues(alpha: 0.2),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),

              // Center section: Phase/Stereo
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _buildGlassSectionHeader('STEREO ANALYSIS'),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Goniometer(
                          leftData: null,
                          rightData: null,
                          config: const GoniometerConfig(
                            showGrid: true,
                            showLabels: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
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
                      GlassStereoBalanceMeter(
                        leftLevel: peakL,
                        rightLevel: peakR,
                        width: double.infinity,
                        height: 20,
                      ),
                    ],
                  ),
                ),
              ),

              // Glass divider
              Container(
                width: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.0),
                      Colors.white.withValues(alpha: 0.2),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),

              // Right section: LUFS & Loudness
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildGlassSectionHeader('LOUDNESS (EBU R128)'),
                      const SizedBox(height: 12),
                      _buildGlassLufsDisplay(m),
                      const Spacer(),
                      _buildGlassTruePeakDisplay(m),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassSectionHeader(String text) {
    return Text(
      text,
      style: TextStyle(
        color: LiquidGlassTheme.textTertiary,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildGlassMeterModeSelector() {
    return Row(
      children: [
        Text(
          'MODE: ',
          style: TextStyle(
            color: LiquidGlassTheme.textTertiary,
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
            child: GestureDetector(
              onTap: () => setState(() => _selectedMeterMode = mode),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: AnimatedContainer(
                    duration: LiquidGlassTheme.animFast,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(
                              colors: [
                                LiquidGlassTheme.accentBlue.withValues(alpha: 0.6),
                                LiquidGlassTheme.accentBlue.withValues(alpha: 0.4),
                              ],
                            )
                          : null,
                      color: isSelected ? null : Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected
                            ? LiquidGlassTheme.accentBlue
                            : Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      mode.name.toUpperCase(),
                      style: TextStyle(
                        color: isSelected
                            ? LiquidGlassTheme.textPrimary
                            : LiquidGlassTheme.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildGlassMainMeter(double peakL, double peakR, double rmsL, double rmsR) {
    return Column(
      children: [
        Text(
          _selectedMeterMode.name.toUpperCase(),
          style: TextStyle(
            color: LiquidGlassTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: GlassProMeter(
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

  Widget _buildGlassKSystemSection(double peakL, double peakR, double rmsL, double rmsR) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: KSystem.values.map((k) {
            final isSelected = _selectedKSystem == k;
            final label = k == KSystem.k12 ? '12' : k == KSystem.k14 ? '14' : '20';
            return Padding(
              padding: const EdgeInsets.only(right: 2),
              child: GestureDetector(
                onTap: () => setState(() => _selectedKSystem = k),
                child: AnimatedContainer(
                  duration: LiquidGlassTheme.animFast,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? LinearGradient(
                            colors: [
                              LiquidGlassTheme.accentOrange.withValues(alpha: 0.6),
                              LiquidGlassTheme.accentOrange.withValues(alpha: 0.4),
                            ],
                          )
                        : null,
                    color: isSelected ? null : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isSelected
                          ? LiquidGlassTheme.accentOrange
                          : Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Text(
                    'K$label',
                    style: TextStyle(
                      color: isSelected
                          ? LiquidGlassTheme.textPrimary
                          : LiquidGlassTheme.textTertiary,
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
          child: GlassKSystemMeter(
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

  Widget _buildGlassLufsDisplay(MeteringState m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGlassLufsRow('Momentary', m.masterLufsM, LiquidGlassTheme.accentCyan),
        const SizedBox(height: 8),
        _buildGlassLufsRow('Short-term', m.masterLufsS, LiquidGlassTheme.accentGreen),
        const SizedBox(height: 8),
        _buildGlassLufsRow('Integrated', m.masterLufsI, LiquidGlassTheme.accentOrange),
        const SizedBox(height: 16),
        // Glass target comparison
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Icon(Icons.flag, size: 14, color: LiquidGlassTheme.textTertiary),
                  const SizedBox(width: 8),
                  Text(
                    'Target: -14 LUFS',
                    style: TextStyle(color: LiquidGlassTheme.textSecondary, fontSize: 11),
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
          ),
        ),
      ],
    );
  }

  Widget _buildGlassLufsRow(String label, double value, Color color) {
    final displayValue = value.isFinite ? value : -60.0;
    return Row(
      children: [
        Container(
          width: 4,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 6,
                spreadRadius: -2,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: LiquidGlassTheme.textTertiary, fontSize: 10),
              ),
              Text(
                '${displayValue.toStringAsFixed(1)} LUFS',
                style: TextStyle(
                  color: LiquidGlassTheme.textPrimary,
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

  Widget _buildGlassTruePeakDisplay(MeteringState m) {
    final tp = m.masterTruePeak.isFinite ? m.masterTruePeak : -60.0;
    final isOver = tp > -1.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: isOver
                ? LinearGradient(
                    colors: [
                      LiquidGlassTheme.accentRed.withValues(alpha: 0.3),
                      LiquidGlassTheme.accentRed.withValues(alpha: 0.15),
                    ],
                  )
                : null,
            color: isOver ? null : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isOver
                  ? LiquidGlassTheme.accentRed
                  : Colors.white.withValues(alpha: 0.15),
            ),
            boxShadow: isOver
                ? [
                    BoxShadow(
                      color: LiquidGlassTheme.accentRed.withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                isOver ? Icons.warning : Icons.show_chart,
                color: isOver ? LiquidGlassTheme.accentRed : LiquidGlassTheme.textTertiary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TRUE PEAK',
                    style: TextStyle(
                      color: LiquidGlassTheme.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${tp.toStringAsFixed(1)} dBTP',
                    style: TextStyle(
                      color: isOver ? LiquidGlassTheme.accentRed : LiquidGlassTheme.textPrimary,
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
                    color: LiquidGlassTheme.accentRed,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: LiquidGlassTheme.accentRed.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Text(
                    'OVER',
                    style: TextStyle(
                      color: LiquidGlassTheme.textPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
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
    if (!current.isFinite) return LiquidGlassTheme.textTertiary;
    final diff = (current - target).abs();
    if (diff < 1) return LiquidGlassTheme.accentGreen;
    if (diff < 3) return LiquidGlassTheme.accentYellow;
    return LiquidGlassTheme.accentRed;
  }
}

// ==============================================================================
// GLASS DYNAMIC RANGE METER
// ==============================================================================

class GlassDynamicRangeMeter extends StatelessWidget {
  final double peakDb;
  final double rmsDb;
  final double width;
  final double height;

  const GlassDynamicRangeMeter({
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
              color: LiquidGlassTheme.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: CustomPaint(
                  size: Size(width, height),
                  painter: _GlassDynamicRangePainter(
                    peakDb: peakDb,
                    rmsDb: rmsDb,
                    dynamicRange: dynamicRange,
                  ),
                ),
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
              shadows: [
                Shadow(
                  color: _getDrColor(dynamicRange).withValues(alpha: 0.5),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getDrColor(double dr) {
    if (dr < 6) return LiquidGlassTheme.accentRed;
    if (dr < 10) return LiquidGlassTheme.accentOrange;
    if (dr < 14) return LiquidGlassTheme.accentYellow;
    return LiquidGlassTheme.accentGreen;
  }
}

class _GlassDynamicRangePainter extends CustomPainter {
  final double peakDb;
  final double rmsDb;
  final double dynamicRange;

  _GlassDynamicRangePainter({
    required this.peakDb,
    required this.rmsDb,
    required this.dynamicRange,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Glass background gradient
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, size.height),
        [
          LiquidGlassTheme.accentRed.withValues(alpha: 0.15),
          LiquidGlassTheme.accentOrange.withValues(alpha: 0.15),
          LiquidGlassTheme.accentYellow.withValues(alpha: 0.15),
          LiquidGlassTheme.accentGreen.withValues(alpha: 0.15),
        ],
        [0.0, 0.25, 0.5, 1.0],
      );

    canvas.drawRect(rect, bgPaint);

    // DR scale (0-40 dB)
    final drNorm = (dynamicRange / 40.0).clamp(0.0, 1.0);
    final barHeight = size.height * drNorm;

    // Glass DR bar with glow
    final barColor = dynamicRange < 6
        ? LiquidGlassTheme.accentRed
        : dynamicRange < 10
            ? LiquidGlassTheme.accentOrange
            : dynamicRange < 14
                ? LiquidGlassTheme.accentYellow
                : LiquidGlassTheme.accentGreen;

    final barPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, size.height - barHeight),
        Offset(0, size.height),
        [
          barColor.withValues(alpha: 0.8),
          barColor.withValues(alpha: 0.4),
        ],
      );

    // Glow effect
    final glowPaint = Paint()
      ..color = barColor.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawRect(
      Rect.fromLTWH(4, size.height - barHeight, size.width - 8, barHeight),
      glowPaint,
    );

    canvas.drawRect(
      Rect.fromLTWH(4, size.height - barHeight, size.width - 8, barHeight),
      barPaint,
    );

    // Scale markers
    final markerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
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
  bool shouldRepaint(covariant _GlassDynamicRangePainter oldDelegate) {
    return oldDelegate.dynamicRange != dynamicRange;
  }
}

// ==============================================================================
// GLASS STEREO BALANCE METER
// ==============================================================================

class GlassStereoBalanceMeter extends StatelessWidget {
  final double leftLevel;
  final double rightLevel;
  final double width;
  final double height;

  const GlassStereoBalanceMeter({
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
              Text('L', style: TextStyle(color: LiquidGlassTheme.textTertiary, fontSize: 10)),
              Text('Balance', style: TextStyle(color: LiquidGlassTheme.textTertiary, fontSize: 10)),
              Text('R', style: TextStyle(color: LiquidGlassTheme.textTertiary, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: CustomPaint(
                  size: Size(width, height),
                  painter: _GlassBalancePainter(balance: balance),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            balance.abs() < 0.05 ? 'C' :
              '${balance > 0 ? "R" : "L"} ${(balance.abs() * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              color: balance.abs() < 0.1
                  ? LiquidGlassTheme.accentGreen
                  : LiquidGlassTheme.accentOrange,
              fontSize: 10,
              shadows: [
                Shadow(
                  color: (balance.abs() < 0.1
                      ? LiquidGlassTheme.accentGreen
                      : LiquidGlassTheme.accentOrange).withValues(alpha: 0.5),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassBalancePainter extends CustomPainter {
  final double balance;

  _GlassBalancePainter({required this.balance});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;

    // Center line with glow
    final centerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center, 0),
      Offset(center, size.height),
      centerPaint,
    );

    // Balance indicator with glow
    final indicatorWidth = 8.0;
    final indicatorX = center + (balance * (size.width / 2 - indicatorWidth / 2));

    final indicatorColor = balance.abs() < 0.1
        ? LiquidGlassTheme.accentGreen
        : LiquidGlassTheme.accentOrange;

    // Glow
    final glowPaint = Paint()
      ..color = indicatorColor.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(indicatorX, size.height / 2),
          width: indicatorWidth,
          height: size.height - 4,
        ),
        const Radius.circular(2),
      ),
      glowPaint,
    );

    // Indicator
    final indicatorPaint = Paint()..color = indicatorColor;

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

    // L/R bars with glass effect
    final leftWidth = (1 - balance) / 2 * (size.width - 20);
    final rightWidth = (1 + balance) / 2 * (size.width - 20);

    final barPaint = Paint()
      ..color = LiquidGlassTheme.accentCyan.withValues(alpha: 0.3);

    // Left bar
    canvas.drawRect(
      Rect.fromLTWH(4, 4, leftWidth.clamp(0, center - 10), size.height - 8),
      barPaint,
    );

    // Right bar
    canvas.drawRect(
      Rect.fromLTWH(size.width - 4 - rightWidth.clamp(0, center - 10), 4,
                   rightWidth.clamp(0, center - 10), size.height - 8),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GlassBalancePainter oldDelegate) {
    return oldDelegate.balance != balance;
  }
}

// ==============================================================================
// GLASS K-SYSTEM METER
// ==============================================================================

class GlassKSystemMeter extends StatelessWidget {
  final double peakLeft;
  final double peakRight;
  final double rmsLeft;
  final double rmsRight;
  final KSystem kSystem;
  final double width;
  final double height;

  const GlassKSystemMeter({
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
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Text(
                  'K-$headroom',
                  style: TextStyle(
                    color: LiquidGlassTheme.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: CustomPaint(
                  size: Size(width, height),
                  painter: _GlassKMeterPainter(
                    peakLeft: peakLeft,
                    peakRight: peakRight,
                    rmsLeft: rmsLeft,
                    rmsRight: rmsRight,
                    headroom: headroom,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassKMeterPainter extends CustomPainter {
  final double peakLeft;
  final double peakRight;
  final double rmsLeft;
  final double rmsRight;
  final int headroom;

  _GlassKMeterPainter({
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
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 1;

    final marks = [3, 0, -3, -6, -9, -12, -20, -30, -40];

    for (final db in marks) {
      final y = size.height * (1 - _dbToNorm(db.toDouble() - headroom));
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        linePaint,
      );
    }
  }

  void _drawMeter(Canvas canvas, double x, double width, double height,
      double peakDb, double rmsDb) {
    // RMS bar with gradient and glow
    final rmsNorm = _dbToNorm(rmsDb);
    final rmsHeight = height * rmsNorm;

    Color rmsColor;
    if (rmsDb > -headroom + 3) {
      rmsColor = LiquidGlassTheme.accentRed;
    } else if (rmsDb > -headroom) {
      rmsColor = LiquidGlassTheme.accentYellow;
    } else {
      rmsColor = LiquidGlassTheme.accentGreen;
    }

    // Glow
    final glowPaint = Paint()
      ..color = rmsColor.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    canvas.drawRect(
      Rect.fromLTWH(x, height - rmsHeight, width, rmsHeight),
      glowPaint,
    );

    // RMS bar with gradient
    final rmsPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(x, height - rmsHeight),
        Offset(x, height),
        [
          rmsColor.withValues(alpha: 0.9),
          rmsColor.withValues(alpha: 0.5),
        ],
      );

    canvas.drawRect(
      Rect.fromLTWH(x, height - rmsHeight, width, rmsHeight),
      rmsPaint,
    );

    // Peak indicator with glow
    final peakNorm = _dbToNorm(peakDb);
    final peakY = height * (1 - peakNorm);

    final peakGlowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    canvas.drawLine(
      Offset(x, peakY),
      Offset(x + width, peakY),
      peakGlowPaint,
    );

    final peakPaint = Paint()
      ..color = LiquidGlassTheme.textPrimary
      ..strokeWidth = 2;

    canvas.drawLine(
      Offset(x, peakY),
      Offset(x + width, peakY),
      peakPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GlassKMeterPainter oldDelegate) {
    return oldDelegate.peakLeft != peakLeft ||
           oldDelegate.peakRight != peakRight ||
           oldDelegate.rmsLeft != rmsLeft ||
           oldDelegate.rmsRight != rmsRight;
  }
}

// ==============================================================================
// THEME-AWARE WRAPPERS FOR INDIVIDUAL METERS
// ==============================================================================

class ThemeAwareDynamicRangeMeter extends StatelessWidget {
  final double peakDb;
  final double rmsDb;
  final double width;
  final double height;

  const ThemeAwareDynamicRangeMeter({
    super.key,
    required this.peakDb,
    required this.rmsDb,
    this.width = 60,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return GlassDynamicRangeMeter(
        peakDb: peakDb,
        rmsDb: rmsDb,
        width: width,
        height: height,
      );
    }

    return DynamicRangeMeter(
      peakDb: peakDb,
      rmsDb: rmsDb,
      width: width,
      height: height,
    );
  }
}

class ThemeAwareStereoBalanceMeter extends StatelessWidget {
  final double leftLevel;
  final double rightLevel;
  final double width;
  final double height;

  const ThemeAwareStereoBalanceMeter({
    super.key,
    required this.leftLevel,
    required this.rightLevel,
    this.width = 200,
    this.height = 24,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return GlassStereoBalanceMeter(
        leftLevel: leftLevel,
        rightLevel: rightLevel,
        width: width,
        height: height,
      );
    }

    return StereoBalanceMeter(
      leftLevel: leftLevel,
      rightLevel: rightLevel,
      width: width,
      height: height,
    );
  }
}

class ThemeAwareKSystemMeter extends StatelessWidget {
  final double peakLeft;
  final double peakRight;
  final double rmsLeft;
  final double rmsRight;
  final KSystem kSystem;
  final double width;
  final double height;

  const ThemeAwareKSystemMeter({
    super.key,
    required this.peakLeft,
    required this.peakRight,
    required this.rmsLeft,
    required this.rmsRight,
    this.kSystem = KSystem.k14,
    this.width = 60,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return GlassKSystemMeter(
        peakLeft: peakLeft,
        peakRight: peakRight,
        rmsLeft: rmsLeft,
        rmsRight: rmsRight,
        kSystem: kSystem,
        width: width,
        height: height,
      );
    }

    return KSystemMeter(
      peakLeft: peakLeft,
      peakRight: peakRight,
      rmsLeft: rmsLeft,
      rmsRight: rmsRight,
      kSystem: kSystem,
      width: width,
      height: height,
    );
  }
}

// ==============================================================================
// THEME-AWARE ADVANCED METERING PANEL
// ==============================================================================

class ThemeAwareAdvancedMeteringPanel extends StatelessWidget {
  const ThemeAwareAdvancedMeteringPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = const AdvancedMeteringPanel();
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// THEME-AWARE CORRELATION METER
// ==============================================================================

class ThemeAwareCorrelationMeter extends StatelessWidget {
  final Float64List? leftData;
  final Float64List? rightData;
  final double? correlation;
  final CorrelationMeterConfig config;
  final double? width;
  final double? height;

  const ThemeAwareCorrelationMeter({
    super.key,
    this.leftData,
    this.rightData,
    this.correlation,
    this.config = const CorrelationMeterConfig(),
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final meter = CorrelationMeter(
      leftData: leftData,
      rightData: rightData,
      correlation: correlation,
      config: config,
      width: width,
      height: height,
    );
    if (isGlassMode) return _GlassMeterWrapper(child: meter);
    return meter;
  }
}

// ==============================================================================
// THEME-AWARE GONIOMETER
// ==============================================================================

class ThemeAwareGoniometer extends StatelessWidget {
  final Float64List? leftData;
  final Float64List? rightData;
  final GoniometerConfig config;
  final double? size;

  const ThemeAwareGoniometer({
    super.key,
    this.leftData,
    this.rightData,
    this.config = const GoniometerConfig(),
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final meter = Goniometer(
      leftData: leftData,
      rightData: rightData,
      config: config,
      size: size,
    );
    if (isGlassMode) return _GlassMeterWrapper(child: meter);
    return meter;
  }
}

// ==============================================================================
// THEME-AWARE VECTORSCOPE
// ==============================================================================

class ThemeAwareVectorscope extends StatelessWidget {
  final Float64List? leftSamples;
  final Float64List? rightSamples;
  final VectorscopeConfig config;

  const ThemeAwareVectorscope({
    super.key,
    this.leftSamples,
    this.rightSamples,
    this.config = const VectorscopeConfig(),
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final meter = Vectorscope(
      leftSamples: leftSamples,
      rightSamples: rightSamples,
      config: config,
    );
    if (isGlassMode) return _GlassMeterWrapper(child: meter);
    return meter;
  }
}

// ==============================================================================
// THEME-AWARE LOUDNESS METER
// ==============================================================================

class ThemeAwareLoudnessMeter extends StatelessWidget {
  final MeteringState metering;
  final LoudnessTarget target;
  final double customTargetLufs;
  final double customTruePeakCeiling;
  final bool showHistory;
  final bool compact;
  final ValueChanged<LoudnessTarget>? onTargetChanged;

  const ThemeAwareLoudnessMeter({
    super.key,
    required this.metering,
    this.target = LoudnessTarget.streaming,
    this.customTargetLufs = -14.0,
    this.customTruePeakCeiling = -1.0,
    this.showHistory = true,
    this.compact = false,
    this.onTargetChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final meter = LoudnessMeter(
      metering: metering,
      target: target,
      customTargetLufs: customTargetLufs,
      customTruePeakCeiling: customTruePeakCeiling,
      showHistory: showHistory,
      compact: compact,
      onTargetChanged: onTargetChanged,
    );
    if (isGlassMode) return _GlassMeterWrapper(child: meter);
    return meter;
  }
}

// ==============================================================================
// THEME-AWARE PDC DETAIL PANEL
// ==============================================================================

class ThemeAwarePdcDetailPanel extends StatelessWidget {
  final List<int> trackIds;
  final double sampleRate;

  const ThemeAwarePdcDetailPanel({
    super.key,
    required this.trackIds,
    this.sampleRate = 48000,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;
    final panel = PdcDetailPanel(
      trackIds: trackIds,
      sampleRate: sampleRate,
    );
    if (isGlassMode) return GlassDspPanelWrapper(child: panel);
    return panel;
  }
}

// ==============================================================================
// GLASS METER WRAPPER (for visualization meters)
// ==============================================================================

class _GlassMeterWrapper extends StatelessWidget {
  final Widget child;

  const _GlassMeterWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(LiquidGlassTheme.radiusMedium),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: LiquidGlassTheme.blurLight,
          sigmaY: LiquidGlassTheme.blurLight,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.05),
                Colors.white.withValues(alpha: 0.02),
                Colors.black.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(LiquidGlassTheme.radiusMedium),
            border: Border.all(
              color: LiquidGlassTheme.accentCyan.withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: LiquidGlassTheme.accentCyan.withValues(alpha: 0.1),
                blurRadius: 16,
                spreadRadius: -4,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
